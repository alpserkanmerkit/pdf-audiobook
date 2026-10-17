// Quiz -> reviewbank bridge (PURE -- no IO, gate-tested 100%).
// Merges the ephemeral 4-option quiz results (MultipleChoiceQuestion + right/wrong)
// into the persistent ReviewBank (spaced repetition). The 'Learned' counter in the
// report (report_screen -> computeWeeklyStats) is fed automatically from this bank;
// the same bank is also practiced in CardsScreen with spaced repetition.
import 'package:sesli_kitap/src/quiz_choice_machine.dart';
import 'package:sesli_kitap/src/review_scheduler.dart';
import 'package:sesli_kitap/src/review_store.dart';
import 'package:sesli_kitap/src/study_questions.dart';

/// Converts a 4-option question into a StudyQuestion: answer = the TEXT of the
/// correct option, kind = factual (MCQ carries no kind information, so a
/// default is assigned).
StudyQuestion mcqToStudyQuestion(MultipleChoiceQuestion m) => StudyQuestion(
  soru: m.soru,
  cevap: m.secenekler[m.dogruIndex],
  tip: QuestionKind.olgusal,
);

/// Merges quiz results into the existing [mevcut] review bank:
/// - The progress (intervalIndex/dueDay) of questions already in the bank is
///   matched by question text and PRESERVED (not overwritten).
/// - Quiz questions that are not in the bank are ADDED as fresh items.
/// - applyAnswer (right -> advance, wrong -> reset) is applied to each answered
///   question.
/// The `items[i].id == 'q$i' == questions[i]` index-parallel invariant is kept.
///
/// IDENTITY = question TEXT. Two consequences:
/// (F1) If the same question appears more than once in the quiz, it counts as
///   ONE review event (the first answer) -- otherwise a single item would
///   advance twice. (F2) Two different questions with the same text are treated
///   as the same item (the existing answer is kept) -- a documented, intentional
///   limit.
ReviewBank mergeQuizIntoReviewBank({
  required List<MultipleChoiceQuestion> sorular,
  required List<bool> dogrular,
  required int today,
  ReviewBank? mevcut,
}) {
  final study = <StudyQuestion>[];
  final items = <ReviewItem>[];
  final soruIndex =
      <String, int>{}; // question text -> index in the merged list

  // 1. Carry over the existing bank; re-index the ids to the new order.
  if (mevcut != null) {
    for (var i = 0; i < mevcut.questions.length; i++) {
      final q = mevcut.questions[i];
      soruIndex[q.soru] = study.length;
      study.add(q);
      final it = mevcut.items[i];
      items.add(
        ReviewItem(
          id: 'q${items.length}',
          intervalIndex: it.intervalIndex,
          dueDay: it.dueDay,
        ),
      );
    }
  }

  // 2. Add the NEW quiz questions (not already in the bank).
  for (final mcq in sorular) {
    if (soruIndex.containsKey(mcq.soru)) continue;
    soruIndex[mcq.soru] = study.length;
    study.add(mcqToStudyQuestion(mcq));
    items.add(planNewItem('q${items.length}', today));
  }

  // 3. Apply the answers (sorular and dogrular in the same order; up to the
  // shorter of the two). If the same item gets several answers (duplicate
  // question), ONLY the first is applied -- one review event (F1: prevents a
  // double advance).
  var bank = ReviewBank(
    items: List.unmodifiable(items),
    questions: List.unmodifiable(study),
  );
  final n = sorular.length < dogrular.length ? sorular.length : dogrular.length;
  final uygulanan = <int>{};
  for (var j = 0; j < n; j++) {
    final idx = soruIndex[sorular[j].soru]!;
    // An answer was already applied to this item.
    if (!uygulanan.add(idx)) continue;
    bank = withAnswer(bank, 'q$idx', knewIt: dogrular[j], today: today);
  }
  return bank;
}
