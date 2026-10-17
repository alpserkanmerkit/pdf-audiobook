// Slice-4 RED test (oracle). lib/src/quiz_choice_machine.dart is written by a worker.
// 4-option quiz presentation machine — NOT review_scheduler (knew/didn't-know flashcard),
// a SEPARATE parallel type (quiz-report analysis LAYER-1 finding). 100% branch target.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/quiz_choice_machine.dart';

MultipleChoiceQuestion _q(int dogru) => MultipleChoiceQuestion(
  soru: 'Question?',
  secenekler: const ['A', 'B', 'C', 'D'],
  dogruIndex: dogru,
  kaynak: 's. 42',
);

void main() {
  group('ChoiceSelected', () {
    test('first choice sets the selection', () {
      final s = QuizChoiceState.initial([_q(1)]);
      final r = quizChoiceTransition(s, const ChoiceSelected(2));
      expect(r.secilen, 2);
      expect(r.yanitlandi, isTrue);
    });
    test('a second choice after answering is ignored (lock)', () {
      var s = QuizChoiceState.initial([_q(1)]);
      s = quizChoiceTransition(s, const ChoiceSelected(2));
      final r = quizChoiceTransition(s, const ChoiceSelected(0));
      expect(r.secilen, 2, reason: 'lock: the first choice is kept');
    });
    test('out-of-range choice (-1, 4) is ignored', () {
      final s = QuizChoiceState.initial([_q(1)]);
      expect(quizChoiceTransition(s, const ChoiceSelected(-1)).secilen, isNull);
      expect(quizChoiceTransition(s, const ChoiceSelected(4)).secilen, isNull);
    });
  });

  group('NextRequested', () {
    test('NO-OP when not yet answered', () {
      final s = QuizChoiceState.initial([_q(1), _q(0)]);
      final r = quizChoiceTransition(s, const NextRequested());
      expect(r.qIndex, 0);
      expect(r.secilen, isNull);
    });
    test('advances on a middle question + selection is reset', () {
      var s = QuizChoiceState.initial([_q(1), _q(0)]);
      s = quizChoiceTransition(s, const ChoiceSelected(1)); // q0 answered
      s = quizChoiceTransition(s, const NextRequested()); // -> q1
      expect(s.qIndex, 1);
      expect(s.secilen, isNull);
      expect(s.tamamlandi, isFalse);
    });
    test(
      'answering the last question and pressing Next -> completed (NOT CIRCULAR, does not wrap to start)',
      () {
        var s = QuizChoiceState.initial([_q(1), _q(0)]);
        s = quizChoiceTransition(s, const ChoiceSelected(1)); // q0 answered
        s = quizChoiceTransition(s, const NextRequested()); // -> q1
        s = quizChoiceTransition(
          s,
          const ChoiceSelected(0),
        ); // q1 (last) answered
        s = quizChoiceTransition(s, const NextRequested()); // -> completed
        expect(s.tamamlandi, isTrue);
        expect(
          s.qIndex,
          1,
          reason: 'stays on the last question, does NOT wrap to start',
        );
      },
    );
    test('after completion all events are NO-OP', () {
      var s = QuizChoiceState.initial([_q(1)]);
      s = quizChoiceTransition(
        s,
        const ChoiceSelected(1),
      ); // single question answered
      s = quizChoiceTransition(s, const NextRequested()); // -> completed
      expect(s.tamamlandi, isTrue);
      final r1 = quizChoiceTransition(s, const ChoiceSelected(0));
      final r2 = quizChoiceTransition(s, const NextRequested());
      expect(r1.tamamlandi, isTrue);
      expect(r2.tamamlandi, isTrue);
      expect(r1.qIndex, s.qIndex);
    });
  });

  group('correctness tracking (for reviewbank wiring)', () {
    test('correct option chosen -> dogrular[qIndex]=true, wrong=false', () {
      var s = QuizChoiceState.initial([_q(1), _q(2)]);
      s = quizChoiceTransition(
        s,
        const ChoiceSelected(1),
      ); // q0 CORRECT (dogruIndex=1)
      expect(s.dogrular[0], isTrue);
      s = quizChoiceTransition(s, const NextRequested());
      s = quizChoiceTransition(
        s,
        const ChoiceSelected(0),
      ); // q1 WRONG (dogruIndex=2)
      expect(s.dogrular[1], isFalse);
    });
    test('dogruSayisi counts correct answers', () {
      var s = QuizChoiceState.initial([_q(1), _q(2), _q(3)]);
      s = quizChoiceTransition(s, const ChoiceSelected(1)); // correct
      s = quizChoiceTransition(s, const NextRequested());
      s = quizChoiceTransition(s, const ChoiceSelected(0)); // wrong
      s = quizChoiceTransition(s, const NextRequested());
      s = quizChoiceTransition(s, const ChoiceSelected(3)); // correct
      expect(s.dogruSayisi, 2);
    });
    test('initial: dogrular all null, tamamlandi false, dogruSayisi 0', () {
      final s = QuizChoiceState.initial([_q(0), _q(1)]);
      expect(s.dogrular, [null, null]);
      expect(s.tamamlandi, isFalse);
      expect(s.dogruSayisi, 0);
    });
  });

  group('empty list + structure', () {
    test(
      'empty list: every event is NO-OP; gecerliSoru null; progress 0/0',
      () {
        final s = QuizChoiceState.initial(const []);
        expect(
          quizChoiceTransition(s, const ChoiceSelected(0)).secilen,
          isNull,
        );
        expect(quizChoiceTransition(s, const NextRequested()).qIndex, 0);
        expect(s.gecerliSoru, isNull);
        expect(s.ilerlemeEtiketi, '0 / 0');
      },
    );
    test('progress label is 1-indexed for the user (2 / 3)', () {
      var s = QuizChoiceState.initial([_q(0), _q(1), _q(2)]);
      s = quizChoiceTransition(s, const ChoiceSelected(0));
      s = quizChoiceTransition(s, const NextRequested());
      expect(s.ilerlemeEtiketi, '2 / 3');
    });
    // K25 (FAZ3b RED, 2026-07-02): 'exactly 4 options' today is ONLY an assert
    // (stripped in release; UI List.generate(4) assumes a fixed 4). Contract:
    // runtime validation -> ArgumentError even in release semantics.
    test('options != 4 -> ArgumentError (in release semantics too)', () {
      expect(
        () => MultipleChoiceQuestion(
          soru: 's',
          secenekler: const ['A', 'B'],
          dogruIndex: 0,
          kaynak: 's.1',
        ),
        throwsArgumentError,
      );
    });
    test('dogruIndex out of range (-1, 4) -> ArgumentError', () {
      expect(() => _q(-1), throwsArgumentError);
      expect(() => _q(4), throwsArgumentError);
    });
  });

  group('seedQuizQuestions (exact match of HTML QUIZ)', () {
    test(
      '3 questions, first is about space/negative space, each has 4 options + valid dogruIndex',
      () {
        final qs = seedQuizQuestions();
        expect(qs, hasLength(3));
        expect(qs.first.soru, contains('boşluk'));
        for (final q in qs) {
          expect(q.secenekler, hasLength(4));
          expect(q.dogruIndex, inInclusiveRange(0, 3));
          expect(q.kaynak, startsWith('s.'));
        }
      },
    );
  });
}
