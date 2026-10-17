// Oracle RED test (2026-10-05, "private lesson book" Slice-1).
// Spec: internal design note §3.4 (session flow) + §3.5 (error path).
//
// Pinned contract (pure logic; the LLM is injected and FAKE in tests):
// - Flow: load a part (1 LLM call) -> answer each question (1 call per question)
//   -> next part -> after the last part, finished.
// - The prompt sent to the LLM is exactly the prompt produced by tutor_prompts.
// - Lesson F9: if the provider is down, there is NO silent fallback. The error is visible
//   (TutorProviderException, underlying message unchanged), a single call (no hidden retry),
//   no lesson/result is fabricated (step stays null, no note is recorded).
// - An empty answer never reaches the LLM (TutorInputException).
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/tutor/lesson_split.dart';
import 'package:sesli_kitap/src/tutor/tutor_prompts.dart';
import 'package:sesli_kitap/src/tutor/tutor_session.dart';

class _Call {
  _Call(this.system, this.user);
  final String system;
  final String user;
}

/// Fake LLM that records calls. [handler] produces a reply or throws based on the prompt text.
class _FakeLlm {
  _FakeLlm(this.handler);
  final String Function(String user) handler;
  final List<_Call> calls = [];

  Future<String> call({required String system, required String user}) async {
    calls.add(_Call(system, user));
    return handler(user);
  }
}

class _ProviderDown implements Exception {
  _ProviderDown(this.message);
  final String message;
  @override
  String toString() => message;
}

const _book = 'Financial Statement Analysis and Security Valuation';
const _chapter = 'Chapter 5: Pricing Book Values';

const _parts = [
  LessonPart(index: 0, fromPage: 164, toPage: 172, text: 'text one'),
  LessonPart(index: 1, fromPage: 173, toPage: 181, text: 'text two'),
  LessonPart(index: 2, fromPage: 182, toPage: 190, text: 'text three'),
];

String _lessonJson(int n, {int questions = 1}) {
  final qs = [
    for (var i = 1; i <= questions; i++)
      '{"soru":"P$n question $i","beklenen":"P$n expected $i"}',
  ].join(',');
  return '{"anlatim":"Part $n explanation","sorular":[$qs]}';
}

const _gradeJson = '{"sonuc":"yarim","aciklama":"Partly correct."}';

/// In the lesson prompt 'Part n/3' -> the lesson of part n; in the grading prompt, the grade.
String _scripted(String user, {int questions = 1}) {
  if (user.contains('STUDENT ANSWER:')) return _gradeJson;
  for (var n = 1; n <= 3; n++) {
    if (user.contains('Part $n/3')) {
      return _lessonJson(n, questions: questions);
    }
  }
  throw StateError('unexpected prompt');
}

TutorSession _session(_FakeLlm llm, {List<LessonPart> parts = _parts}) =>
    TutorSession(
      parts: parts,
      llm: llm.call,
      bookTitle: _book,
      chapterTitle: _chapter,
    );

void main() {
  group('setup', () {
    test('empty part list is rejected', () {
      final llm = _FakeLlm(_scripted);
      expect(() => _session(llm, parts: const []), throwsArgumentError);
    });

    test('initial state: first part, no step, not finished, no LLM call', () {
      final llm = _FakeLlm(_scripted);
      final s = _session(llm);
      expect(s.parts.length, 3);
      expect(s.parts[2].text, 'text three');
      expect(s.currentIndex, 0);
      expect(s.currentPart.fromPage, 164);
      expect(s.currentStep, isNull);
      expect(s.grades, isEmpty);
      expect(s.isFinished, isFalse);
      expect(llm.calls, isEmpty);
    });
  });

  group('part loading', () {
    test('one call; prompt identical to tutor_prompts', () async {
      final llm = _FakeLlm(_scripted);
      final s = _session(llm);
      final step = await s.loadCurrentPart();
      expect(llm.calls.length, 1);
      expect(llm.calls.single.system, kTutorSystemPrompt);
      expect(
        llm.calls.single.user,
        buildLessonPrompt(
          part: _parts[0],
          totalParts: 3,
          bookTitle: _book,
          chapterTitle: _chapter,
        ),
      );
      expect(step.anlatim, 'Part 1 explanation');
      expect(s.currentStep, same(step));
    });
  });

  group('answering', () {
    test('grading: one call, prompt identical, answer trimmed', () async {
      final llm = _FakeLlm(_scripted);
      final s = _session(llm);
      final step = await s.loadCurrentPart();
      final g = await s.answer(0, '  profit minus cost of capital  ');
      expect(llm.calls.length, 2);
      expect(llm.calls.last.system, kTutorSystemPrompt);
      expect(
        llm.calls.last.user,
        buildGradePrompt(
          part: _parts[0],
          question: step.sorular[0],
          userAnswer: 'profit minus cost of capital',
        ),
      );
      expect(g.verdict, AnswerVerdict.yarim);
      expect(g.aciklama, 'Partly correct.');
      expect(s.grades[0], same(g));
    });

    test(
      'answering before the step is loaded -> StateError, no LLM call',
      () async {
        final llm = _FakeLlm(_scripted);
        final s = _session(llm);
        await expectLater(s.answer(0, 'x'), throwsStateError);
        expect(llm.calls, isEmpty);
      },
    );

    test('invalid question index -> RangeError, no LLM call', () async {
      final llm = _FakeLlm(_scripted);
      final s = _session(llm);
      await s.loadCurrentPart();
      await expectLater(s.answer(1, 'x'), throwsRangeError);
      await expectLater(s.answer(-1, 'x'), throwsRangeError);
      expect(llm.calls.length, 1);
    });

    test('empty answer never reaches the LLM -> TutorInputException', () async {
      final llm = _FakeLlm(_scripted);
      final s = _session(llm);
      await s.loadCurrentPart();
      await expectLater(
        s.answer(0, '   \n '),
        throwsA(isA<TutorInputException>()),
      );
      expect(llm.calls.length, 1);
      expect(s.grades, isEmpty);
    });

    test('empty answer error text is human-readable, no class name', () async {
      final s = _session(_FakeLlm(_scripted));
      await s.loadCurrentPart();
      try {
        await s.answer(0, '');
        fail('TutorInputException expected');
      } on TutorInputException catch (e) {
        expect(e.toString(), e.reason);
        expect(e.reason.trim().isNotEmpty, isTrue);
        expect(e.toString().contains('TutorInputException'), isFalse);
      }
    });

    test('notes cannot be modified from outside', () async {
      final llm = _FakeLlm(_scripted);
      final s = _session(llm);
      await s.loadCurrentPart();
      await s.answer(0, 'x');
      expect(
        () => s.grades[5] = const GradeResult(
          verdict: AnswerVerdict.dogru,
          aciklama: 'fake',
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('progress', () {
    test('no advance until all questions are answered', () async {
      final llm = _FakeLlm((u) => _scripted(u, questions: 2));
      final s = _session(llm);
      await s.loadCurrentPart();
      await s.answer(0, 'x');
      expect(s.nextPart, throwsStateError);
      expect(s.currentIndex, 0);
    });

    test('no advance before the step is loaded', () {
      final s = _session(_FakeLlm(_scripted));
      expect(s.nextPart, throwsStateError);
    });

    test(
      'full flow: 3 parts -> finished; calls = 3 lessons + 3 grades',
      () async {
        final llm = _FakeLlm(_scripted);
        final s = _session(llm);
        for (var i = 0; i < 3; i++) {
          expect(s.currentIndex, i);
          final step = await s.loadCurrentPart();
          expect(step.anlatim, 'Part ${i + 1} explanation');
          await s.answer(0, 'answer $i');
          s.nextPart();
          expect(
            s.currentStep,
            isNull,
            reason: 'the step resets on a new part',
          );
          expect(s.grades, isEmpty, reason: 'the notes reset on a new part');
        }
        expect(s.isFinished, isTrue);
        expect(llm.calls.length, 6);
        expect(() => s.currentPart, throwsStateError);
        await expectLater(s.loadCurrentPart(), throwsStateError);
        expect(llm.calls.length, 6);
      },
    );
  });

  group('provider error path (F9: NO silent fallback)', () {
    test(
      'provider down on loading: visible error, one call, no step',
      () async {
        final llm = _FakeLlm(
          (_) => throw _ProviderDown('HTTP 503: unavailable'),
        );
        final s = _session(llm);
        await expectLater(
          s.loadCurrentPart(),
          throwsA(
            isA<TutorProviderException>().having(
              (e) => e.reason,
              'reason',
              'HTTP 503: unavailable',
            ),
          ),
        );
        expect(llm.calls.length, 1, reason: 'no hidden retry/fallback call');
        expect(s.currentStep, isNull, reason: 'no lesson is fabricated');
        expect(s.currentIndex, 0);
      },
    );

    test('provider error text has no class name', () async {
      final llm = _FakeLlm((_) => throw _ProviderDown('Connection failed.'));
      final s = _session(llm);
      try {
        await s.loadCurrentPart();
        fail('TutorProviderException expected');
      } on TutorProviderException catch (e) {
        expect(e.toString(), 'Connection failed.');
      }
    });

    test('broken reply: TutorParseException, no step', () async {
      final llm = _FakeLlm((_) => 'Sorry, I cannot help with that.');
      final s = _session(llm);
      await expectLater(
        s.loadCurrentPart(),
        throwsA(isA<TutorParseException>()),
      );
      expect(llm.calls.length, 1);
      expect(s.currentStep, isNull);
    });

    test('provider down on grading: visible error, no note', () async {
      var down = false;
      final llm = _FakeLlm((u) {
        if (down) throw _ProviderDown('HTTP 500');
        return _scripted(u);
      });
      final s = _session(llm);
      await s.loadCurrentPart();
      down = true;
      await expectLater(
        s.answer(0, 'answer'),
        throwsA(
          isA<TutorProviderException>().having(
            (e) => e.reason,
            'reason',
            'HTTP 500',
          ),
        ),
      );
      expect(llm.calls.length, 2, reason: 'no hidden retry');
      expect(s.grades, isEmpty, reason: 'no result is fabricated');
      expect(s.nextPart, throwsStateError);
    });

    test('broken grading reply: TutorParseException, no note', () async {
      var broken = false;
      final llm = _FakeLlm((u) => broken ? '{"sonuc":"belki"}' : _scripted(u));
      final s = _session(llm);
      await s.loadCurrentPart();
      broken = true;
      await expectLater(
        s.answer(0, 'answer'),
        throwsA(isA<TutorParseException>()),
      );
      expect(s.grades, isEmpty);
    });

    test('user retries: the call is repeated and the flow continues', () async {
      var failing = true;
      final llm = _FakeLlm((u) {
        if (failing) throw _ProviderDown('temporary');
        return _scripted(u);
      });
      final s = _session(llm);
      await expectLater(
        s.loadCurrentPart(),
        throwsA(isA<TutorProviderException>()),
      );
      failing = false;
      final step = await s.loadCurrentPart();
      expect(step.anlatim, 'Part 1 explanation');
      expect(llm.calls.length, 2);
    });
  });
}
