// Quiz -> reviewbank bridge (PURE, 100% branch target). MERGES ephemeral MultipleChoiceQuestion
// results into the persistent ReviewBank: the existing progress (intervalIndex/
// dueDay) is KEPT by matching on the question text, new questions are added, and
// applyAnswer (spaced repetition) is applied to every answer. The items[i].id=='q$i' invariant is preserved.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/quiz_choice_machine.dart';
import 'package:sesli_kitap/src/quiz_review_bridge.dart';
import 'package:sesli_kitap/src/review_scheduler.dart';
import 'package:sesli_kitap/src/review_store.dart';
import 'package:sesli_kitap/src/study_questions.dart';

MultipleChoiceQuestion _mcq(String soru, int dogru) => MultipleChoiceQuestion(
  soru: soru,
  secenekler: const ['A', 'B', 'C', 'D'],
  dogruIndex: dogru,
  kaynak: 's. 1',
);

void main() {
  group('mcqToStudyQuestion', () {
    test('answer = text of the correct option, type = factual', () {
      final m = MultipleChoiceQuestion(
        soru: 'Capital?',
        secenekler: const ['Izmir', 'Ankara', 'Bursa', 'Konya'],
        dogruIndex: 1,
        kaynak: 's. 5',
      );
      final sq = mcqToStudyQuestion(m);
      expect(sq.soru, 'Capital?');
      expect(sq.cevap, 'Ankara');
      expect(sq.tip, QuestionKind.olgusal);
    });
  });

  group('mergeQuizIntoReviewBank — no existing bank', () {
    test(
      'fresh bank from quiz results: correct advances, wrong stays at zero',
      () {
        final bank = mergeQuizIntoReviewBank(
          sorular: [_mcq('S0', 1), _mcq('S1', 2)],
          dogrular: [true, false],
          today: 100,
        );
        expect(bank.items, hasLength(2));
        expect(bank.questions, hasLength(2));
        // id invariant
        expect(bank.items[0].id, 'q0');
        expect(bank.items[1].id, 'q1');
        // S0 correct: planNewItem(index0) -> applyAnswer(true) -> index1, dueDay 100+3
        expect(bank.items[0].intervalIndex, 1);
        expect(bank.items[0].dueDay, 103);
        // S1 wrong: index0 -> applyAnswer(false) -> index0, dueDay 100+1
        expect(bank.items[1].intervalIndex, 0);
        expect(bank.items[1].dueDay, 101);
        // questions converted to StudyQuestion
        expect(bank.questions[0].soru, 'S0');
        expect(
          bank.questions[0].cevap,
          'B',
        ); // dogruIndex=1 -> secenekler[1]='B'
      },
    );

    test(
      'a new question answered correctly again goes to index1, all correct',
      () {
        final bank = mergeQuizIntoReviewBank(
          sorular: [_mcq('X', 0)],
          dogrular: [true],
          today: 0,
        );
        expect(bank.items[0].intervalIndex, 1);
      },
    );
  });

  group('mergeQuizIntoReviewBank — existing bank present (progress is kept)', () {
    test(
      'same question CONTINUES from existing progress (does NOT overwrite)',
      () {
        // Existing: S0 is already at index1 (answered correctly in a previous session).
        final mevcut = ReviewBank(
          items: const [ReviewItem(id: 'q0', intervalIndex: 1, dueDay: 50)],
          questions: [
            StudyQuestion(soru: 'S0', cevap: 'B', tip: QuestionKind.olgusal),
          ],
        );
        final bank = mergeQuizIntoReviewBank(
          mevcut: mevcut,
          sorular: [_mcq('S0', 1)],
          dogrular: [true],
          today: 100,
        );
        // S0 correct from index1 -> index2, dueDay 100+7 (not from zero!)
        expect(bank.items, hasLength(1));
        expect(bank.items[0].intervalIndex, 2);
        expect(bank.items[0].dueDay, 107);
      },
    );

    test('new question is ADDED to the existing bank (id is re-indexed)', () {
      final mevcut = ReviewBank(
        items: const [ReviewItem(id: 'q0', intervalIndex: 0, dueDay: 50)],
        questions: [
          StudyQuestion(soru: 'OLD', cevap: 'B', tip: QuestionKind.olgusal),
        ],
      );
      final bank = mergeQuizIntoReviewBank(
        mevcut: mevcut,
        sorular: [_mcq('NEW', 2)],
        dogrular: [true],
        today: 10,
      );
      expect(bank.questions.map((q) => q.soru), ['OLD', 'NEW']);
      expect(bank.items.map((i) => i.id), ['q0', 'q1']);
      // OLD was not touched (not in the quiz): index0, dueDay 50 is kept
      expect(bank.items[0].intervalIndex, 0);
      expect(bank.items[0].dueDay, 50);
      // NEW correct: index1
      expect(bank.items[1].intervalIndex, 1);
    });

    test(
      'a MASTERED (index3) question does NOT change when answered again (applyAnswer no-op)',
      () {
        final mevcut = ReviewBank(
          items: const [ReviewItem(id: 'q0', intervalIndex: 3, dueDay: -1)],
          questions: [
            StudyQuestion(
              soru: 'MASTERED',
              cevap: 'A',
              tip: QuestionKind.olgusal,
            ),
          ],
        );
        final bank = mergeQuizIntoReviewBank(
          mevcut: mevcut,
          sorular: [_mcq('MASTERED', 0)],
          dogrular: [true],
          today: 200,
        );
        expect(bank.items[0].intervalIndex, 3);
        expect(bank.items[0].dueDay, -1);
      },
    );
  });

  group('mergeQuizIntoReviewBank — defensive', () {
    test(
      'if dogrular is shorter than sorular, extra questions are not processed (no crash)',
      () {
        final bank = mergeQuizIntoReviewBank(
          sorular: [_mcq('A', 0), _mcq('B', 1)],
          dogrular: [true], // only 1 answer
          today: 0,
        );
        // Both questions enter the bank; the answer is applied only to A.
        expect(bank.questions, hasLength(2));
        expect(bank.items[0].intervalIndex, 1); // A answered
        expect(bank.items[1].intervalIndex, 0); // B unanswered (fresh)
      },
    );

    test('empty quiz + empty existing -> empty bank', () {
      final bank = mergeQuizIntoReviewBank(
        sorular: const [],
        dogrular: const [],
        today: 0,
      );
      expect(bank.items, isEmpty);
      expect(bank.questions, isEmpty);
    });

    test(
      'same question TWICE inside the quiz -> ONE review event (no double progression)',
      () {
        // Adversarial-review finding (F1): parseQuizResponse does not dedupe;
        // the LLM may generate the same stem again. If the same question is answered
        // correctly twice, the item must NOT jump 0->1->2 (one review = 0->1).
        final bank = mergeQuizIntoReviewBank(
          sorular: [_mcq('DUP', 0), _mcq('DUP', 0)],
          dogrular: [true, true],
          today: 0,
        );
        expect(bank.items, hasLength(1), reason: 'same question = one item');
        expect(
          bank.items[0].intervalIndex,
          1,
          reason: 'one review event -> index1 (NOT 2; no double progression)',
        );
      },
    );

    test('new question with the SAME text as an existing one -> same item (text=identity, '
        'documented limit): old answer is kept, progress continues', () {
      // Adversarial-review finding (F2): identity = question TEXT. If two DIFFERENT
      // questions have the same text, they count as one item. This is a documented/intentional
      // limit -- pin the behavior (no surprises).
      final mevcut = ReviewBank(
        items: const [ReviewItem(id: 'q0', intervalIndex: 1, dueDay: 50)],
        questions: [
          StudyQuestion(
            soru: 'SAME',
            cevap: 'old-answer',
            tip: QuestionKind.olgusal,
          ),
        ],
      );
      final bank = mergeQuizIntoReviewBank(
        mevcut: mevcut,
        sorular: [_mcq('SAME', 0)], // same text, answer = secenekler[0]='A'
        dogrular: [true],
        today: 100,
      );
      expect(bank.questions, hasLength(1), reason: 'text=identity: one item');
      expect(
        bank.questions[0].cevap,
        'old-answer',
        reason: 'text=identity: existing answer is kept (documented limit)',
      );
      expect(
        bank.items[0].intervalIndex,
        2,
        reason:
            'q0 index1 -> correct -> index2 (continues from existing progress)',
      );
    });
  });
}
