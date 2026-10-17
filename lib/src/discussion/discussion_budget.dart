// DQ-1: word-budget core for long discussions.
//
// Pure functions -- no IO/UI wiring (separate wave). Design:
// internal design note (sections 1, 4).
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';

/// Total word count across all turns (splits on whitespace, ignores empty pieces).
int scriptWordCount(List<DiscussionTurn> turns) {
  var total = 0;
  for (final turn in turns) {
    total += turn.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }
  return total;
}

/// Rough number of turns needed to reach the target word count (rounded up).
///
/// Throws [ArgumentError] if [avgWordsPerTurn] is zero or negative.
int computeTargetTurns({
  required int targetWords,
  required int avgWordsPerTurn,
}) {
  if (avgWordsPerTurn <= 0) {
    throw ArgumentError.value(
      avgWordsPerTurn,
      'avgWordsPerTurn',
      'must be greater than zero',
    );
  }
  return (targetWords / avgWordsPerTurn).ceil();
}

/// Has the current word count reached or passed the target -- should a closing turn be requested?
bool shouldRequestClosing({
  required int currentWords,
  required int targetWords,
}) => currentWords >= targetWords;

/// Discussion length profiles the user can choose from.
enum DiscussionLengthMode { kisa, orta, uzun, sonsuz }

/// Word target -- `sonsuz` (infinite) has no target (null).
int? targetWordsFor(DiscussionLengthMode mode) {
  switch (mode) {
    case DiscussionLengthMode.kisa:
      return 550;
    case DiscussionLengthMode.orta:
      return 1100;
    case DiscussionLengthMode.uzun:
      return 2150;
    case DiscussionLengthMode.sonsuz:
      return null;
  }
}
