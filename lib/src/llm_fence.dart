// lib/src/llm_fence.dart — shared helper that strips the markdown code-fence
// wrapper from an LLM response (FAZ3b K1). Previously 3 copies (chapter_skeleton,
// clean_contract, study_questions._unwrapFence) did the same job with DIFFERENT
// robustness; a single-line fence in chapter_skeleton produced a substring(0,-1)
// RangeError. Contract: fence tolerance (```json / plain ``` / single line --
// same semantics as the study_questions contract); string operations can NEVER
// produce a negative index; if there is no fence, only trim.

/// Strips an optional markdown code fence (with optional language tag,
/// e.g. ```json) wrapping [raw] and returns the trimmed inner content.
String stripCodeFence(String raw) {
  var s = raw.trim();
  if (!s.startsWith('```')) return s;
  s = s.substring(3);
  // Language tag of the opening fence (markdown info-string, e.g. 'json').
  final tag = RegExp('^[A-Za-z0-9_-]+').firstMatch(s);
  if (tag != null) {
    s = s.substring(tag.end);
  }
  if (s.endsWith('```')) {
    s = s.substring(0, s.length - 3);
  }
  return s.trim();
}
