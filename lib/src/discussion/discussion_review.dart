// DQ-2: discussion REVIEWER core -- pure JSON parsing + correction application +
// activation policy. The real second LLM call (io wiring) is the NEXT wave; this
// file only contains the pure layer.
//
// Contract (internal design note §2 + internal experiment note A2b):
// - Reviewer scope is limited to name + repetition + length + self-address.
//   Stance-violation checks are NOT given to the reviewer (in the A2b live trial
//   it was over-sensitive: it flagged the tone's harshness as a violation).
//   Stance protection is left to the lint and the author prompt (outside this file).
// - Output is FORCED into the JSON schema: {"ok": bool, "corrections": [{"index":
//   int, "text": string}]}. Broken/missing/wrong-type -> null (FAIL-OPEN: if the
//   reviewer fails the original script is kept; the flow NEVER breaks).
import 'dart:convert';

import 'package:sesli_kitap/src/discussion/discussion_turn.dart';
import 'package:sesli_kitap/src/llm_fence.dart';

/// A single line correction proposed by the reviewer.
class ReviewCorrection {
  const ReviewCorrection({required this.index, required this.text});

  /// Zero-based index of the line to correct in the [DiscussionTurn] list.
  final int index;

  /// The new text of the line (the speaker does not change, only the text does).
  final String text;
}

/// The parsed form of the reviewer's reply.
class ReviewResult {
  const ReviewResult({required this.ok, required this.corrections});

  /// true means the batch was approved without issues; even if corrections are
  /// filled, [applyReviewCorrections] changes nothing (approval > correction).
  final bool ok;

  final List<ReviewCorrection> corrections;
}

/// Parses the reviewer's JSON reply. Tolerates replies wrapped in a code block or
/// with extra whitespace/fields around them (same pattern as clean_contract /
/// parseDiscussionScript). ANY deviation from the schema (invalid JSON, missing
/// field, wrong type) -> null. Never throws: the caller reads null as "do not trust
/// the reviewer, keep the original".
ReviewResult? parseReviewResponse(String content) {
  final trimmed = stripCodeFence(content);
  if (trimmed.isEmpty) return null;

  dynamic parsed;
  try {
    parsed = jsonDecode(trimmed);
  } on Object catch (_) {
    return null;
  }

  if (parsed is! Map<String, dynamic>) return null;

  final okValue = parsed['ok'];
  if (okValue is! bool) return null;

  final correctionsValue = parsed['corrections'];
  if (correctionsValue is! List) return null;

  final corrections = <ReviewCorrection>[];
  for (final item in correctionsValue) {
    if (item is! Map<String, dynamic>) return null;
    final index = item['index'];
    final text = item['text'];
    if (index is! int) return null;
    if (text is! String) return null;
    corrections.add(ReviewCorrection(index: index, text: text));
  }

  return ReviewResult(ok: okValue, corrections: corrections);
}

/// The share of a line's content words that appear in a correction, above which
/// the correction is considered to belong to ANOTHER line (measurement T3: a
/// completion written to the wrong index carried ~100% of its true owner's words
/// and ~5% of its target's; a legitimate NAME/LENGTH correction carries ~90%+ of
/// its target's words).
const double kForeignTurnContainment = 0.6;

/// Content words for comparison: lowercase Turkish, split on non-letter characters
/// (an apostrophe separates the suffix), keeping parts of 4+ letters (short
/// conjunction/suffix noise is dropped).
Set<String> _contentWords(String text) => text
    .replaceAll('I', 'ı')
    .replaceAll('İ', 'i')
    .toLowerCase()
    .split(RegExp('[^a-zçğıöşüâîû]+'))
    .where((w) => w.length >= 4)
    .toSet();

/// The share (0..1) of [turnWords] that is contained in [correctionWords]. A line
/// with fewer than 5 content words is not measured (0): a chance full overlap from
/// a one-word line like "Evet." must not produce a false rejection.
double _containment(Set<String> turnWords, Set<String> correctionWords) {
  if (turnWords.length < 5) return 0;
  return turnWords.intersection(correctionWords).length / turnWords.length;
}

/// Does [text] carry the content of ANOTHER line rather than the line at [index]?
/// (The reviewer drifting while counting lines -- measurement T3.)
bool _carriesAnotherTurn(List<DiscussionTurn> turns, int index, String text) {
  final correctionWords = _contentWords(text);
  final own = _containment(_contentWords(turns[index].text), correctionWords);
  for (var k = 0; k < turns.length; k++) {
    if (k == index) continue;
    final other = _containment(_contentWords(turns[k].text), correctionWords);
    if (other >= kForeignTurnContainment && other > own) return true;
  }
  return false;
}

/// Applies the reviewer's corrections on top of [turns]. If `review.ok` is true or
/// corrections is empty, turns is returned AS-IS (approval > correction; empty =
/// no change). Out-of-range indices (negative or >= turns.length) are SAFELY
/// skipped -- one bad index does not spoil the whole batch. The speaker NEVER
/// changes, only the text does; the turn count and order do not change (no
/// deletion/insertion). A correction that carries ANOTHER line's content (wrong
/// index) is REJECTED: it is not guessed onto the "right" index -- the target line
/// stays as it is (fail-open).
List<DiscussionTurn> applyReviewCorrections(
  List<DiscussionTurn> turns,
  ReviewResult review,
) {
  if (review.ok || review.corrections.isEmpty) return turns;

  final result = List<DiscussionTurn>.of(turns);
  for (final correction in review.corrections) {
    if (correction.index < 0 || correction.index >= result.length) continue;
    // Empty/whitespace-only text: KEEP the original (FAIL-OPEN). If the reviewer
    // "deletes" a line by returning empty text, or leaves it empty by cutting its
    // JSON, producing an empty line would break TTS (empty text -> Google 400) and
    // take down the whole batch -- the reviewer's contract is the opposite: never
    // break the flow.
    if (correction.text.trim().isEmpty) continue;
    if (_carriesAnotherTurn(turns, correction.index, correction.text)) continue;
    final original = result[correction.index];
    result[correction.index] = DiscussionTurn(
      original.speaker,
      correction.text,
    );
  }
  return result;
}

/// Reviewer activation policy: batch 1 (batchIndex == 0) is ALWAYS reviewed (the
/// first impression and the name rule holding matter most at that moment).
/// Later batches are not reviewed by default in this pure layer -- the "review if
/// the lint trips" branch of the design is applied in the upper layer (io/controller)
/// that has access to the lint signal; this function expresses only the basic
/// batch-1 policy.
bool shouldReview({required int batchIndex}) => batchIndex == 0;

/// The fixed prompt text sent to the reviewer. Per the hard decision of experiment
/// A2b (internal experiment note Experiment 3), scope is STRICTLY limited to name +
/// repetition + length (+ self-address, measured 2026-09-28); there is NO
/// stance-violation check (it gave over-sensitive output). Output is forced into
/// the JSON schema.
const String reviewerPrompt = '''
You will be given the context and a batch of a discussion (a group of lines).
Line labels show the speaker: A=Ahmet, B=Emel, C=Deniz, D=Kaya.
Your ONLY task is to perform these four checks:
1. NAME: When a speaker addresses another speaker, do they use the WRONG
   person's name? (E.g. if speaker C answers Deniz and says "Emel", that is an error.)
2. REPETITION: Does a line repeat an earlier line from the context, word for word
   or as a paraphrase?
3. LENGTH: Is every line at least 3 and at most 4 sentences? A single-sentence
   line, or a monologue longer than 4 sentences, is a LENGTH error.
4. SELF-ADDRESS: Does a speaker say their own name? (E.g. "Deniz olarak söylüyorum",
   "Ben Kaya", or Emel referring to herself in the third person as "Emel'in
   eleştirisi".) If so, rewrite that line so that its own name no longer appears,
   keeping its meaning.

DO NOT EVALUATE ANYTHING BEYOND THESE. A speaker's harsh, assertive or sharp
speech is NOT AN ERROR; do not touch tone, style or character attitude.
Harsh, sarcastic, condescending objections and disagreement are NOT ERRORS;
returning to the same claim from a different angle is NOT counted as a REPETITION.
In a line you correct, keep the harshness, sarcasm and objection EXACTLY as they
are -- do not soften it, and do not add a conciliatory or polite sentence.

Each line in the batch starts with "#<index> <label>:" (e.g. "#12 C: ...").
Write the number of the line you correct in the "index" field EXACTLY as shown;
do not count it yourself. Correct a line's text only using ITS OWN number; do
not write another line's words in its place. The corrected text must stay in
Turkish, the language of the original line.

Reply ONLY with this JSON schema, with no other text:
{"ok": true|false, "corrections": [{"index": <0-based line index>, "text": "<corrected line text>"}]}

If there are no problematic lines, return "ok": true and "corrections": [].
''';
