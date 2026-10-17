// PR (interactive participation): listener-directive injection -- pure text.
//
// When the user presses a steer chip while playback is running, or types a
// free-text question, that text is added to the NEXT continuation call
// (generateContinuation) as a "LISTENER DIRECTIVE". It is SINGLE-USE: the
// calling side (discussion_room_screen.dart) clears it as soon as it reads it.
// It only affects the NEXT batch, does NOT interrupt the current playback, and
// does NOT leak into later batches.
//
// The matching author rule lives in _continuationSystemPrompt
// (lib/io/llm_discussion.dart): "if present, address it in the NEXT 2-3 lines".
//
// SAFETY (insurance package): a free-text "question" can be multi-line or very
// long. It could imitate the block structure of the continuation prompt and
// skew the model's tone (a prompt-injection-like risk). So before injection the
// text is SANITIZED: runs of whitespace/newlines collapse to a single space,
// then it is cut down to about kListenerDirectiveMaxChars characters. The
// null/empty behaviour (topic returned AS-IS) stays BYTE-IDENTICAL -- sanitizing
// runs ONLY when a real directive exists.

/// Upper character limit for a directive before injection. Kept modest: this is
/// a "steering trace", not the continuation itself.
const int kListenerDirectiveMaxChars = 200;

/// If [directive] is null, empty or whitespace-only, [topic] is returned AS-IS
/// (no injection). Otherwise the directive, with runs of whitespace/newlines
/// collapsed and cut to [kListenerDirectiveMaxChars] characters, is appended to
/// [topic] as a block headed "LISTENER DIRECTION" (the marker the prompt
/// looks for).
String withListenerDirective(String topic, String? directive) {
  final trimmed = directive?.trim();
  if (trimmed == null || trimmed.isEmpty) return topic;
  final sanitized = sanitizeListenerText(trimmed);
  return '$topic\n\n'
      'LISTENER DIRECTION: $sanitized — address this in the next few lines.';
}

/// Shared sanitizer for listener text (a steer directive or a "Ask" question).
/// Single source of truth. K4 2026-09-30: a question also goes into a separate
/// answer-batch prompt. Runs of spaces/newlines/tabs collapse to one space, then
/// the text is cut to [kListenerDirectiveMaxChars] characters (an ellipsis "…"
/// is added when it is cut -- same convention as _clip in
/// discussion_rolling_summary.dart).
String sanitizeListenerText(String input) {
  final collapsed = input.replaceAll(RegExp(r'\s+'), ' ').trim();
  return collapsed.length > kListenerDirectiveMaxChars
      ? '${collapsed.substring(0, kListenerDirectiveMaxChars)}…'
      : collapsed;
}
