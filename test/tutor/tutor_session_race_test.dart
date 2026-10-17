// Oracle RED test (2026-10-05, "private lesson book" Slice-1 EK1).
// Spec: internal design note §3.5a (concurrency).
// Source: Fable robustness review MEDIUM-1 (probe R1/R1b) -- the pending note was being
// written to the new step, and nextPart advanced before the new questions were answered.
//
// Pinned contract (the fake LLM reply is held with a Completer):
// - If, when answer() started, the current step is no longer the valid step once the LLM
//   returns, the note is NOT written and TutorStaleStepException is thrown (text unchanged).
// - If the step did not change (reload not finished), the note is written normally.
// - While an evaluation is pending, nextPart is rejected (TutorInputException, text
//   unchanged); this rejection comes before the unanswered-question check.
// - The wait counter drops on every exit (success, provider error, parse error, stale reply).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/tutor/lesson_split.dart';
import 'package:sesli_kitap/src/tutor/tutor_prompts.dart';
import 'package:sesli_kitap/src/tutor/tutor_session.dart';

const _staleReason = 'The lesson step changed; this answer was not graded.';
const _loadingReason =
    'The lesson part is still loading; the next part cannot be opened until loading finishes.';
const _pendingReason =
    'Your answer is still being graded; the next part cannot be opened before the result arrives.';

final TypeMatcher<TutorStaleStepException> _isStale =
    isA<TutorStaleStepException>()
        .having((e) => e.reason, 'reason', _staleReason)
        .having((e) => e.toString(), 'toString', _staleReason);

final TypeMatcher<TutorInputException> _isPending = isA<TutorInputException>()
    .having((e) => e.reason, 'reason', _pendingReason);

String _lessonJson(int load, int questions) {
  final qs = [
    for (var i = 1; i <= questions; i++)
      '{"soru":"Y$load question $i","beklenen":"Y$load expected $i"}',
  ].join(',');
  return '{"anlatim":"Load $load explanation","sorular":[$qs]}';
}

String _gradeJson(String sonuc) =>
    '{"sonuc":"$sonuc","aciklama":"Explanation."}';

class _ProviderDown implements Exception {
  _ProviderDown(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Fake LLM: lesson and grading calls can be held individually.
/// The Completer of a held call is added to [held] in call order.
class _HeldLlm {
  _HeldLlm({this.questions = 2});

  final int questions;
  bool holdLessons = false;
  bool holdGrades = false;
  int loads = 0;
  final List<Completer<String>> held = [];

  Future<String> call({required String system, required String user}) {
    final isGrade = user.contains('STUDENT ANSWER:');
    if (isGrade ? holdGrades : holdLessons) {
      final c = Completer<String>();
      held.add(c);
      return c.future;
    }
    if (isGrade) return Future.value(_gradeJson('dogru'));
    loads++;
    return Future.value(_lessonJson(loads, questions));
  }
}

const _parts = [
  LessonPart(index: 0, fromPage: 164, toPage: 172, text: 'text one'),
  LessonPart(index: 1, fromPage: 173, toPage: 181, text: 'text two'),
];

TutorSession _session(_HeldLlm llm) => TutorSession(
  parts: _parts,
  llm: llm.call,
  bookTitle: 'Book',
  chapterTitle: 'Chapter',
);

void main() {
  group('stale answer (step changed)', () {
    test(
      'notes arriving after a reload are not written to the new step',
      () async {
        final llm = _HeldLlm();
        final s = _session(llm);
        final first = await s.loadCurrentPart();
        llm.holdGrades = true;
        final a0 = s.answer(0, 'old answer 0');
        final a1 = s.answer(1, 'old answer 1');
        final e0 = expectLater(a0, throwsA(_isStale));
        final e1 = expectLater(a1, throwsA(_isStale));

        final second = await s.loadCurrentPart();
        expect(second, isNot(same(first)));
        llm.held[0].complete(_gradeJson('dogru'));
        llm.held[1].complete(_gradeJson('dogru'));
        await e0;
        await e1;

        expect(s.currentStep, same(second));
        expect(
          s.grades,
          isEmpty,
          reason: 'old notes do not fall into the new step',
        );
        expect(
          s.nextPart,
          throwsStateError,
          reason: 'new questions are unanswered',
        );
        expect(s.currentIndex, 0);
      },
    );

    test(
      'after a stale answer, the new step can be answered and advanced',
      () async {
        final llm = _HeldLlm();
        final s = _session(llm);
        await s.loadCurrentPart();
        llm.holdGrades = true;
        final a0 = s.answer(0, 'old answer');
        final e0 = expectLater(a0, throwsA(_isStale));
        await s.loadCurrentPart();
        llm.held[0].complete(_gradeJson('dogru'));
        await e0;

        llm.holdGrades = false;
        await s.answer(0, 'new answer 0');
        await s.answer(1, 'new answer 1');
        expect(s.grades.keys, unorderedEquals([0, 1]));
        s.nextPart();
        expect(
          s.currentIndex,
          1,
          reason: 'the stale exit drops the wait counter',
        );
      },
    );

    test(
      'a note returned before the reload finishes is written to the old step',
      () async {
        final llm = _HeldLlm();
        final s = _session(llm);
        final first = await s.loadCurrentPart();
        llm.holdGrades = true;
        final a0 = s.answer(0, 'answer');
        llm.holdLessons = true;
        final reload = s.loadCurrentPart();

        llm.held[0].complete(_gradeJson('yanlis'));
        final g = await a0;
        expect(g.verdict, AnswerVerdict.yanlis);
        expect(s.currentStep, same(first));
        expect(s.grades[0], same(g));

        llm.held[1].complete(_lessonJson(99, 2));
        final second = await reload;
        expect(s.currentStep, same(second));
        expect(s.grades, isEmpty);
      },
    );
  });

  // G3 / Y1 (CROSS_2_PRODUCT, 2026-10-06): while a reload was in progress, nextPart
  // was accepted; the pending load wrote the old part's lesson into the new index and
  // a part was skipped without ever being taught. Spec gap decision: while a load is in
  // progress nextPart is rejected (state unchanged); every part is taught in order.
  group('no progress while loading (G3/Y1)', () {
    test(
      'nextPart is rejected while a reload is waiting; no part is skipped',
      () async {
        final llm = _HeldLlm(questions: 1);
        final prompts = <String>[];
        final recording = TutorSession(
          parts: _parts,
          llm: ({required system, required user}) {
            if (!user.contains('STUDENT ANSWER:')) prompts.add(user);
            return llm.call(system: system, user: user);
          },
          bookTitle: 'Book',
          chapterTitle: 'Chapter',
        );
        await recording.loadCurrentPart();
        await recording.answer(0, 'answer');
        llm.holdLessons = true;
        final reload = recording.loadCurrentPart();

        expect(
          recording.nextPart,
          throwsA(
            isA<TutorInputException>().having(
              (e) => e.reason,
              'reason',
              _loadingReason,
            ),
          ),
        );
        expect(recording.currentIndex, 0, reason: 'no advance while loading');

        llm.held[0].complete(_lessonJson(7, 1));
        final again = await reload;
        expect(recording.currentIndex, 0);
        expect(recording.currentStep, same(again));

        llm.holdLessons = false;
        await recording.answer(0, 'answer retry');
        recording.nextPart();
        expect(recording.currentIndex, 1);
        await recording.loadCurrentPart();
        expect(
          prompts.last,
          contains('text two'),
          reason: 'part 1 is taught to the student, not skipped',
        );
        await recording.answer(0, 'final answer');
        recording.nextPart();
        expect(recording.isFinished, isTrue);
        expect(
          [for (final p in prompts) p.contains('text two')],
          [false, false, true],
          reason: 'order: part0, part0 again, part1',
        );
      },
    );

    test('a failed load clears the waiting flag', () async {
      final llm = _HeldLlm(questions: 1);
      final s = _session(llm);
      await s.loadCurrentPart();
      await s.answer(0, 'answer');
      llm.holdLessons = true;
      final reload = s.loadCurrentPart();
      final e = expectLater(reload, throwsA(isA<TutorProviderException>()));
      llm.held[0].completeError(_ProviderDown('HTTP 503'));
      await e;

      s.nextPart();
      expect(
        s.currentIndex,
        1,
        reason: 'the error exit clears the loading flag',
      );
    });
  });

  group('no progress while an evaluation is pending', () {
    test(
      'nextPart is rejected while a second answer to an already graded question is waiting',
      () async {
        final llm = _HeldLlm(questions: 1);
        final s = _session(llm);
        final step = await s.loadCurrentPart();
        final g1 = await s.answer(0, 'first answer');
        llm.holdGrades = true;
        final pending = s.answer(0, 'second answer');

        expect(s.nextPart, throwsA(_isPending));
        expect(s.currentIndex, 0);
        expect(s.currentStep, same(step));
        expect(s.grades[0], same(g1));

        llm.held[0].complete(_gradeJson('yanlis'));
        final g2 = await pending;
        expect(s.grades[0], same(g2));
        s.nextPart();
        expect(s.currentIndex, 1);
        expect(s.currentStep, isNull);
        expect(
          s.grades,
          isEmpty,
          reason: "the previous part's notes are not carried over",
        );
      },
    );

    test(
      'the pending rejection comes before the unanswered-question check',
      () async {
        final llm = _HeldLlm();
        final s = _session(llm);
        await s.loadCurrentPart();
        llm.holdGrades = true;
        final a0 = s.answer(0, 'answer');

        expect(s.nextPart, throwsA(_isPending));

        llm.held[0].complete(_gradeJson('dogru'));
        await a0;
        expect(
          s.nextPart,
          throwsStateError,
          reason: 'question 2 is unanswered',
        );
        expect(s.currentIndex, 0);
      },
    );

    test('a provider error drops the wait counter', () async {
      final llm = _HeldLlm(questions: 1);
      final s = _session(llm);
      await s.loadCurrentPart();
      llm.holdGrades = true;
      final a0 = s.answer(0, 'answer');
      final e0 = expectLater(a0, throwsA(isA<TutorProviderException>()));
      llm.held[0].completeError(_ProviderDown('HTTP 500'));
      await e0;

      expect(
        s.nextPart,
        throwsStateError,
        reason: 'nothing pending, the question is unanswered',
      );
      llm.holdGrades = false;
      await s.answer(0, 'retry');
      s.nextPart();
      expect(s.currentIndex, 1);
    });

    test('a parse error drops the wait counter', () async {
      final llm = _HeldLlm(questions: 1);
      final s = _session(llm);
      await s.loadCurrentPart();
      llm.holdGrades = true;
      final a0 = s.answer(0, 'answer');
      final e0 = expectLater(a0, throwsA(isA<TutorParseException>()));
      llm.held[0].complete('Sorry, I cannot grade this.');
      await e0;

      expect(
        s.nextPart,
        throwsStateError,
        reason: 'nothing pending, the question is unanswered',
      );
      llm.holdGrades = false;
      await s.answer(0, 'retry');
      s.nextPart();
      expect(s.currentIndex, 1);
    });
  });
}
