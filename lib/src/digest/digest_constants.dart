/// PURE layer (gate-tested at 100%): constants of the book-digest package +
/// cache-key builders. No IO. Spec:
/// internal design note (sections 1/3/6).
///
/// This layer is the BACKBONE of the Wave-A core: token estimation (plan), cache
/// layout (io Wave-B) and versioning are all fed from the single constant source
/// defined here. The measurement origin is in the report; ASSUMPTIONs are flagged
/// here as comments.
library;

/// Average characters per page. FACT: in a 14-page sample pulled from the device,
/// the average was 2133.5 chars/page (median 2161, ss=107 -- very uniform typesetting).
/// Rounded to an integer (the ±0.5 chars/page is negligible for token estimation).
const int defaultCharsPerPage = 2133;

/// Characters-per-token ratio. ASSUMPTION (flagged in the report, must be verified):
/// for Turkish, the model's (v4.1-flash) tokenizer typically gives 2.5-3.0 chars/token.
/// The pessimistic end (2.5) is the default -- it OVERESTIMATES tokens, so budget
/// overruns are caught early (the safe side). Until confirmed against the model's
/// tokenizer, it can be overridden via the planDigest parameter.
const double defaultCharsPerToken = 2.5;

/// Input token budget for one digest call. INFERENCE (NOT verified on the Gemini
/// gemini-3.8-flash endpoint): the V3.x family has a 128K-token context window; after
/// subtracting the system prompt, the ~1500 requested output tokens and a safety margin,
/// ~100K input tokens comfortably fit many chapters in one call (the largest, "Uyum",
/// 53 pages ≈ 45K tokens). A chapter that exceeds the budget is split into page ranges
/// in the plan layer.
const int defaultMaxTokensPerCall = 100000;

/// Digest prompt/schema version. The book does not change -> the summary is cached
/// indefinitely; it is regenerated only when this version is bumped (versioned cache
/// via `digestPromptVersion` -- the report's freshness note).
const String digestPromptVersion = 'd1';

/// Safe-character escaping for cache keys. SAME contract as the (private) `_sanitize`
/// in cache_keys.dart: every rune outside [a-zA-Z0-9._-] becomes `x<two-digit-hex>`.
/// Deliberately aligned with the existing key space (that file's function is private,
/// so it cannot be reused without changing that file).
String _sanitize(String input) {
  final buffer = StringBuffer();
  for (final char in input.runes) {
    final c = String.fromCharCode(char);
    if (RegExp(r'^[a-zA-Z0-9._-]$').hasMatch(c)) {
      buffer.write(c);
    } else {
      buffer.write('x${char.toRadixString(16).padLeft(2, '0')}');
    }
  }
  return buffer.toString();
}

/// Cache key for a chapter's digest summary: `d_<hash>_c<idx>_<ver>`
/// (design-sketch contract §6). [chapterIndex] is 0-based.
String chapterDigestCacheKey({
  required String bookHash,
  required int chapterIndex,
  String version = digestPromptVersion,
}) {
  return 'd_${_sanitize(bookHash)}_c${chapterIndex}_${_sanitize(version)}';
}

/// Cache key for the book-level digest (manifest): `dm_<hash>_<ver>`
/// (design-sketch contract §6).
String bookDigestCacheKey({
  required String bookHash,
  String version = digestPromptVersion,
}) {
  return 'dm_${_sanitize(bookHash)}_${_sanitize(version)}';
}
