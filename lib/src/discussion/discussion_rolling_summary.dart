// DQ-4: long-term context for endless mode -- a cheap "rolling summary".
//
// Problem: kRecentContextTurns (discussion_controller.dart) gives the continuation
// prompt only the last 6 lines verbatim. Real device endurance (300+ turns) showed
// that in a 100+ turn run, everything beyond that 6-turn window is erased from the
// model's "memory" -> risk of the same 2-3 arguments repeating in a loop. The fix
// is not a REDESIGN: for each speaker (A/B/C/D), add the LAST line they said outside
// the last-6 window as a short trace to the continuation prompt -- pure text
// processing, NO extra LLM call (cheap; "cheap addition, not a redesign").
//
// Design note: internal design note §7, item 4 mentioned a "rolling state block"
// (reviewer-generated, phase 2, a separate slice). Here, instead, a zero-extra-cost
// pure-text approach was chosen -- the scope of this wave is explicitly a "cheap
// addition" (the task definition), so it adds no extra LLM call or parse risk.
import 'package:sesli_kitap/src/discussion/discussion_presenter.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';

/// Upper character limit of the text carried per speaker in the summary line.
/// Kept modest: this is a "reminder trace", not a second verbatim line.
const int kRollingSummaryMaxChars = 100;

/// Adds, to the [topic] argument, a short "previous course" block made of each
/// speaker's LAST line from [olderTurns] (the turns outside the last-K window --
/// the calling side does the slicing, this function stays pure). If [olderTurns]
/// is EMPTY (there is no older material yet -- in the first few extensions this
/// means byte-identical BEHAVIOUR) [topic] is returned AS-IS.
String withRollingSummary(String topic, List<DiscussionTurn> olderTurns) {
  if (olderTurns.isEmpty) return topic;

  final lastBySpeaker = <DiscussionSpeaker, String>{};
  for (final turn in olderTurns) {
    lastBySpeaker[turn.speaker] = turn.text;
  }

  final lines = <String>[];
  for (final speaker in DiscussionSpeaker.values) {
    final text = lastBySpeaker[speaker];
    if (text == null) continue;
    lines.add('${speakerName(speaker)}: ${_clip(text)}');
  }

  return '$topic\n\n'
      'PREVIOUS COURSE OF THE DISCUSSION (summary -- do NOT repeat, only remember): '
      '${lines.join(' / ')}';
}

String _clip(String text) => text.length > kRollingSummaryMaxChars
    ? '${text.substring(0, kRollingSummaryMaxChars)}…'
    : text;
