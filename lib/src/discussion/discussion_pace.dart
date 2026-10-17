// PR-Q1 (DESIGN §4): basis for the duration label.
//
// kDiscussionWordsPerMinute = 108: A2b experiment 1 field measurement (6 samples,
// range 103-113, from real device mp3s, same TTS pipeline, 1x speed).
// DQ-W1: the Short/Medium/Long/Endless picker uses this constant to produce a
// per-mode duration estimate (see discussionModeDurationLabel below).
import 'package:sesli_kitap/src/discussion/discussion_budget.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';

const int kDiscussionWordsPerMinute = 108;

/// Plain whitespace-separated word counter (enough for turn texts -- Turkish
/// punctuation does not break word boundaries, same simplicity as the word
/// budget design in DESIGN).
int discussionWordCount(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return 0;
  return trimmed.split(RegExp(r'\s+')).length;
}

/// DQ-W1: "~N min" estimate for the length-mode picker.
/// Short/Medium/Long -> targetWordsFor(mode) / kDiscussionWordsPerMinute
/// (rounded up). Endless -> no target word count, returns a fixed label.
String discussionModeDurationLabel(DiscussionLengthMode mode) {
  final targetWords = targetWordsFor(mode);
  if (targetWords == null) return 'Until you stop it';
  final minutes = (targetWords / kDiscussionWordsPerMinute).ceil();
  return '~$minutes min';
}

// ── A2: inter-turn micro-pause ─────────────────────────────────────────────
//
// The author prompt already FORCES every beat to be marked with '...'
// (see the natural-speech texture encouragement in discussion_directive), but
// the gapless player was SILENTLY SWALLOWING those marks between turns: the
// text had "a thinking moment", yet the audio left no trace of it. turnDelivery
// gives these marks a REAL landing duration; an interruption line -- on the
// contrary -- jumps in quickly without waiting for the other speaker to FINISH.

/// Natural "landing" pause (ms) after a line that ends with '...'.
const int kEllipsisLandingPauseMs = 650;

/// Default gap between turns when there is no special marker (ms).
const int kDefaultTurnPauseMs = 180;

/// When a speaker breaks in over the other speaker (interruption), there is no gap.
const int kInterruptionPauseMs = 0;

/// General safety ceiling: no pause on the '...' landing path may exceed this.
const int kMaxTurnPauseMs = 800;

/// Narrower ceiling for paths OTHER than the '...' landing (default/interruption).
const int kMaxNonEllipsisPauseMs = 450;

/// Does `next` open with an "interrupt / cut in" word? (case-insensitive; the
/// \b word boundary keeps words like "Durum"/"Duracagim" from matching by
/// accident.) "hay[ıi]r" covers both Turkish I variants (dotted/dotless).
final RegExp _interruptionOpener = RegExp(
  r'^(dur|ama|hay[ıi]r|bir\s+dakika)\b',
  caseSensitive: false,
);

/// A2: computes the delivery settings (gap) between two consecutive turns.
///
/// - [prev] null (the script's first turn -- nothing is playing before it): no
///   gap, pauseMs=0.
/// - [next] opens with an interruption word (Dur/Ama/Hayır/Bir dakika): fast
///   path (pauseMs=0) -- the interruption wins EVEN IF [prev] ends with '...'
///   (the speaker is cutting in without waiting for the other one's landing).
/// - [prev] ends with '...' (the mandatory beat marker from the author prompt):
///   a natural landing time ([kEllipsisLandingPauseMs], in the ~500-800ms band).
/// - Otherwise: a small default gap between turns ([kDefaultTurnPauseMs]).
///
/// pauseMs is ALWAYS clamped to the [kMaxTurnPauseMs] (0..800) band, and to the
/// narrower [kMaxNonEllipsisPauseMs] (0..450) band on the default/interruption
/// paths (HARD-CLAMP) -- the contract holds even if the constants change later.
///
/// rateDelta (speaking-rate deviation) is computed too (positive = faster,
/// negative = slower) but in THIS wave it is connected to nothing -- it is only
/// returned and tested; it is there to open a channel to playback speed later.
({int pauseMs, double rateDelta}) turnDelivery(
  DiscussionTurn? prev,
  DiscussionTurn next,
) {
  if (prev == null) {
    return (pauseMs: 0, rateDelta: 0.0);
  }
  if (_interruptionOpener.hasMatch(next.text.trimLeft())) {
    return (
      pauseMs: kInterruptionPauseMs.clamp(0, kMaxNonEllipsisPauseMs),
      rateDelta: 0.1,
    );
  }
  if (prev.text.trimRight().endsWith('...')) {
    return (
      pauseMs: kEllipsisLandingPauseMs.clamp(0, kMaxTurnPauseMs),
      rateDelta: -0.05,
    );
  }
  return (
    pauseMs: kDefaultTurnPauseMs.clamp(0, kMaxNonEllipsisPauseMs),
    rateDelta: 0.0,
  );
}
