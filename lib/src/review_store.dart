// PHASE 4: spaced-repetition persistence contract (PURE -- no IO, gate-tested).
// The question bank + ReviewItems are stored in a single JSON: questions are
// generated once (the quiz counterpart of the one-AI-call-per-page principle),
// and later days are asked via the dueItems filter. The shell only carries
// encode/decode + prefs.
import 'dart:convert';

import 'package:sesli_kitap/src/review_scheduler.dart';
import 'package:sesli_kitap/src/study_questions.dart';

/// Fixed day-epoch: 2026-01-01. The pure core only uses integer days.
/// S4: the user's LOCAL calendar day is the basis (the old toUtc shifted the
/// day boundary to 03:00 in TR). The components are differenced in UTC space so
/// the difference is always a whole day (DST-immune).
int daysSinceEpoch(DateTime now) {
  final d = DateTime.utc(now.year, now.month, now.day);
  return d.difference(DateTime.utc(2026)).inDays;
}

class ReviewBank {
  const ReviewBank({required this.items, required this.questions});

  /// `items[i].id == 'q$i' == questions[i]` (construction invariant).
  final List<ReviewItem> items;
  final List<StudyQuestion> questions;
}

/// Builds a bank from newly generated questions (each question is scheduled via planNewItem).
ReviewBank newBank(List<StudyQuestion> questions, int today) {
  return ReviewBank(
    items: List.unmodifiable([
      for (var i = 0; i < questions.length; i++) planNewItem('q$i', today),
    ]),
    questions: List.unmodifiable(questions),
  );
}

/// 'q3' -> questions[3]; an unknown/out-of-range id -> null (no crash).
StudyQuestion? questionById(ReviewBank bank, String id) {
  if (!id.startsWith('q')) return null;
  final i = int.tryParse(id.substring(1));
  if (i == null || i < 0 || i >= bank.questions.length) return null;
  return bank.questions[i];
}

/// Answer marked: the matching item advances via applyAnswer, the others are unchanged.
ReviewBank withAnswer(
  ReviewBank bank,
  String id, {
  required bool knewIt,
  required int today,
}) {
  return ReviewBank(
    items: List.unmodifiable([
      for (final item in bank.items)
        if (item.id == id)
          applyAnswer(item, knewIt: knewIt, today: today)
        else
          item,
    ]),
    questions: bank.questions,
  );
}

/// IDs of the questions due today (in dueItems order).
List<String> dueIds(ReviewBank bank, int today) {
  return List.unmodifiable([
    for (final item in dueItems(bank.items, today)) item.id,
  ]);
}

String encodeReviewBank(ReviewBank bank) {
  return jsonEncode({
    'items': [
      for (final item in bank.items)
        {
          'id': item.id,
          'intervalIndex': item.intervalIndex,
          'dueDay': item.dueDay,
        },
    ],
    'questions': [
      for (final q in bank.questions)
        {'soru': q.soru, 'cevap': q.cevap, 'tip': q.tip.name},
    ],
  });
}

/// Corrupt/incomplete record -> FormatException (the shell catches it and regenerates the bank).
ReviewBank decodeReviewBank(String raw) {
  final Object decoded;
  try {
    decoded = jsonDecode(raw) as Object;
  } on FormatException {
    throw const FormatException('review bank: invalid JSON');
  }
  if (decoded is! Map ||
      decoded['items'] is! List ||
      decoded['questions'] is! List) {
    throw const FormatException('review bank: unexpected schema');
  }
  final items = <ReviewItem>[];
  for (final it in decoded['items'] as List) {
    if (it is! Map ||
        it['id'] is! String ||
        it['intervalIndex'] is! int ||
        it['dueDay'] is! int) {
      throw const FormatException('review bank: corrupt item');
    }
    final intervalIndex = it['intervalIndex'] as int;
    // K7: an index outside 0..3 leads to an intervals[] overflow (RangeError) --
    // it is rejected at the persistence boundary (the shell catches it and
    // regenerates the bank).
    if (intervalIndex < 0 || intervalIndex > 3) {
      throw const FormatException('review bank: intervalIndex out of range');
    }
    items.add(
      ReviewItem(
        id: it['id'] as String,
        intervalIndex: intervalIndex,
        dueDay: it['dueDay'] as int,
      ),
    );
  }
  final questions = <StudyQuestion>[];
  for (final q in decoded['questions'] as List) {
    if (q is! Map ||
        q['soru'] is! String ||
        q['cevap'] is! String ||
        q['tip'] is! String) {
      throw const FormatException('review bank: corrupt question');
    }
    final kind = QuestionKind.values.cast<QuestionKind?>().firstWhere(
      (k) => k!.name == q['tip'],
      orElse: () => null,
    );
    if (kind == null) {
      throw const FormatException('review bank: unknown type');
    }
    questions.add(
      StudyQuestion(
        soru: q['soru'] as String,
        cevap: q['cevap'] as String,
        tip: kind,
      ),
    );
  }
  // Construction invariant (items[i].id == 'q$i' == questions[i]): a dangling
  // item id or a length mismatch makes questionById(id) return null -- CardsScreen
  // CRASHES on the null-check operator (questionById(...)!). The same boundary-
  // rejection philosophy as K7: a corrupt record is rejected at the decode
  // boundary, and the shell catches the FormatException and falls back to the
  // seed (a safe fallback instead of a crash).
  if (items.length != questions.length) {
    throw const FormatException('review bank: items/questions length mismatch');
  }
  for (var i = 0; i < items.length; i++) {
    if (items[i].id != 'q$i') {
      throw const FormatException(
        r'review bank: item id q$i violates the positional invariant',
      );
    }
  }
  return ReviewBank(
    items: List.unmodifiable(items),
    questions: List.unmodifiable(questions),
  );
}
