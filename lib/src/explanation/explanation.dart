// PURE layer (gate-tested): the "Ask" feature -- extracting word chips for an
// in-context Turkish explanation of the tapped word/sentence + LLM context
// window + prompt building + JSON contract parsing. HTTP transport lives in
// lib/io/llm_explanation.dart (same split as quiz_generation).
import 'dart:convert';

class ExplanationParseException implements Exception {
  ExplanationParseException(this.reason);
  final String reason;

  @override
  String toString() => 'ExplanationParseException: $reason';
}

/// Word-body character: a letter or a digit (Unicode -- including Turkish).
final RegExp _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);
final RegExp _whitespace = RegExp(r'\s+');

/// Extracts tappable word chips from a sentence: splits on whitespace, trims
/// leading/trailing punctuation, and drops empty leftovers. First-pass order is
/// kept; the same word (case-insensitive) is not repeated. Marks INSIDE a word
/// (hyphen/apostrophe) count as part of the word body ("state-of-the-art" is a
/// single chip).
List<String> explainableWords(String sentence) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in sentence.split(_whitespace)) {
    final w = _trimPunctuation(raw);
    if (w.isEmpty) continue;
    if (seen.add(w.toLowerCase())) out.add(w);
  }
  return out;
}

String _trimPunctuation(String s) {
  var start = 0;
  var end = s.length;
  while (start < end && !_wordChar.hasMatch(s[start])) {
    start++;
  }
  while (end > start && !_wordChar.hasMatch(s[end - 1])) {
    end--;
  }
  return s.substring(start, end);
}

/// Joins the sentence at [index] with its +-[radius] neighbors into an LLM
/// context window. If the result exceeds [maxChars], the radius is shrunk first
/// (the center sentence is NEVER dropped); if it still exceeds at radius 0, the
/// center sentence itself is cut to [maxChars] (a token/cost cap -- the same
/// rationale as the quiz's 8000-character cut contract). An empty list,
/// an out-of-range index, a negative radius or a non-positive maxChars ->
/// [ArgumentError].
String contextWindow(
  List<String> sentences,
  int index, {
  int radius = 2,
  int maxChars = 1200,
}) {
  if (sentences.isEmpty) {
    throw ArgumentError('sentences must not be empty');
  }
  if (index < 0 || index >= sentences.length) {
    throw ArgumentError('index out of range: $index');
  }
  if (radius < 0) {
    throw ArgumentError('radius must not be negative: $radius');
  }
  if (maxChars <= 0) {
    throw ArgumentError('maxChars must be positive: $maxChars');
  }
  for (var r = radius; r >= 0; r--) {
    final lo = (index - r).clamp(0, sentences.length - 1);
    final hi = (index + r).clamp(0, sentences.length - 1);
    final joined = sentences.sublist(lo, hi + 1).join(' ');
    if (joined.length <= maxChars) return joined;
  }
  return sentences[index].substring(0, maxChars);
}

/// LLM user prompt: asks for the meaning of [target] ([isWord] true: a single
/// word; false: the whole sentence) within [sentence], to be explained IN
/// TURKISH, ONLY via the `{"aciklama":"..."}` JSON schema. Whatever language
/// the source text is in (English included), the explanation is in Turkish.
String buildExplanationPrompt({
  required String target,
  required bool isWord,
  required String sentence,
  required String contextText,
}) {
  final hedef = isWord
      ? 'Explain the meaning of the word "$target" in THIS context, '
            'from the sentence below'
      : 'Explain what the sentence below means';
  return '$hedef. The explanation MUST be in Turkish (regardless of the source '
      'language, English included). Keep it short and clear (2-4 sentences). '
      'Return ONLY this JSON schema, write nothing else:\n'
      '{"aciklama":"explanation text"}\n\n'
      'SENTENCE:\n$sentence\n\n'
      'CONTEXT (neighboring sentences):\n$contextText';
}

/// Converts the LLM response body (JSON) into the explanation text. On a
/// contract violation (invalid JSON, not an object, the aciklama field missing,
/// empty or not a string) it throws [ExplanationParseException].
String parseExplanationResponse(String content) {
  final Object? data;
  try {
    data = jsonDecode(content);
  } on FormatException catch (e) {
    throw ExplanationParseException('invalid JSON body: $e');
  }
  if (data is! Map) {
    throw ExplanationParseException('root value is not an object');
  }
  final aciklama = data['aciklama'];
  if (aciklama is! String || aciklama.trim().isEmpty) {
    throw ExplanationParseException(
      'aciklama field is missing, empty or not a string',
    );
  }
  return aciklama.trim();
}
