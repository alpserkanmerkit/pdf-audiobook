// Karaoke foundation (PR-K1): pure sentence-timing layer. Converts TTS word-boundary
// events (REAL audio time) into sentence start times.
//
// This layer is INVISIBLE to the user (the reader wiring comes in PR-K2); it only
// PRODUCES timing. The existing estimateNarratingSentenceIndex
// (reader_highlight_view.dart) STAYS -- this layer does not touch it; it is a
// parallel, more accurate source.

/// TTS word-boundary event. [offsetMs] is the REAL audio time (ms).
class WordBoundary {
  const WordBoundary({
    required this.offsetMs,
    required this.durationMs,
    required this.text,
  });

  final int offsetMs;
  final int durationMs;
  final String text;
}

/// Sentence start times. [startsMs] length == number of sentences; non-decreasing;
/// startsMs[0] == 0. [totalMs] is the end of the last sentence (>= startsMs.last).
class SentenceTimings {
  const SentenceTimings({required this.startsMs, required this.totalMs});

  final List<int> startsMs;
  final int totalMs;

  Map<String, dynamic> toJson() => {
    'v': 1,
    'startsMs': startsMs,
    'totalMs': totalMs,
  };

  /// Malformed shape / unsupported version -> null (never throws).
  static SentenceTimings? fromJson(Map<String, dynamic> j) {
    if (j['v'] != 1) return null;
    final rawStarts = j['startsMs'];
    final rawTotal = j['totalMs'];
    if (rawStarts is! List || rawTotal is! int) return null;
    final starts = <int>[];
    for (final e in rawStarts) {
      if (e is! int) return null;
      starts.add(e);
    }
    // An empty startsMs = unusable timing: narratingIndexAt clamp(0, -1)
    // would throw an ArgumentError (review finding) -> treat it as a malformed shape.
    if (starts.isEmpty) return null;
    return SentenceTimings(startsMs: starts, totalMs: rawTotal);
  }
}

/// Sentence/word weight: number of non-whitespace characters, at least 1.
int sentenceWeight(String s) {
  var count = 0;
  for (final r in s.runes) {
    if (!_isWhitespace(r)) count++;
  }
  return count < 1 ? 1 : count;
}

bool _isWhitespace(int rune) {
  // Space, tab, line feed, CR -- a fast ASCII set instead of general Unicode whitespace.
  return rune == 0x20 || rune == 0x09 || rune == 0x0A || rune == 0x0D;
}

/// Produces sentence timing from word-boundary events. NO text MATCHING: the two
/// streams (sentences / words) are walked through their cumulative character
/// ratio. REASON: TTS normalization ("2026" -> "iki bin yirmi alti") changes the
/// word count and text, but the two streams stay PROPORTIONAL; pronunciation-rule
/// differences are absorbed too. Empty words / sentences -> null.
SentenceTimings? timingsFromWordBoundaries({
  required List<String> sentences,
  required List<WordBoundary> words,
  int? totalMs,
}) {
  if (sentences.isEmpty || words.isEmpty) return null;

  // (1) Sentence prefix ratios f_k = sum(weight[0..k-1]) / total (f_0 = 0).
  final sentTotal = _sumWeights(sentences);
  final f = _prefixRatios(sentences, sentTotal);

  // (2) Word prefix ratios g_i = sum(wordWeight[0..i-1]) / total.
  final wordTexts = words.map((w) => w.text).toList();
  final wordTotal = _sumWeights(wordTexts);
  final g = _prefixRatios(wordTexts, wordTotal);

  // (3) startsMs[k] = the offset of the FIRST word where g_i >= f_k; if there is
  //     none, the offset of the last word (default). startsMs[0] is forced to 0;
  //     monotonicity is forced via max(prev, cur).
  final starts = <int>[];
  var prev = 0;
  for (var k = 0; k < sentences.length; k++) {
    var chosen = words
        .last
        .offsetMs; // default: last word (if the threshold is never reached)
    for (var i = 0; i < words.length; i++) {
      if (g[i] >= f[k]) {
        chosen = words[i].offsetMs;
        break;
      }
    }
    if (k == 0) chosen = 0; // startsMs[0] is always 0
    if (chosen < prev) chosen = prev; // monotonicity
    starts.add(chosen);
    prev = chosen;
  }

  // (4) totalMs: the given value ?? (last word offset + duration); it is not
  //     allowed to fall below startsMs.last.
  final last = words.last;
  var total = totalMs ?? (last.offsetMs + last.durationMs);
  if (total < starts.last) total = starts.last;

  return SentenceTimings(startsMs: starts, totalMs: total);
}

/// Length-weighted proportional pseudo-timing (the path WITHOUT word boundaries).
/// Equal lengths = IDENTICAL to the old uniform result. totalMs <= 0 -> ArgumentError;
/// empty sentences -> null.
SentenceTimings? timingsFromSentenceLengths({
  required List<String> sentences,
  required int totalMs,
}) {
  if (totalMs <= 0) {
    throw ArgumentError('totalMs must be positive');
  }
  if (sentences.isEmpty) return null;

  final total = _sumWeights(sentences);
  final f = _prefixRatios(sentences, total);
  final starts = <int>[];
  var prev = 0;
  for (var k = 0; k < sentences.length; k++) {
    var cur = k == 0 ? 0 : (f[k] * totalMs).round();
    if (cur < prev) cur = prev;
    starts.add(cur);
    prev = cur;
  }
  return SentenceTimings(startsMs: starts, totalMs: totalMs);
}

/// The sentence index being read at [position]. Negative -> 0; the LAST k where
/// `startsMs[k]` <= posMs; clamped to [0, n-1].
int narratingIndexAt({
  required SentenceTimings timings,
  required Duration position,
}) {
  final posMs = position.inMilliseconds < 0 ? 0 : position.inMilliseconds;
  final starts = timings.startsMs;
  var idx = 0;
  for (var k = 0; k < starts.length; k++) {
    if (starts[k] <= posMs) {
      idx = k;
    }
  }
  return idx.clamp(0, starts.length - 1);
}

int _sumWeights(List<String> items) {
  var sum = 0;
  for (final s in items) {
    sum += sentenceWeight(s);
  }
  return sum;
}

/// Prefix ratios: `ratios[k]` = `sum(weight[0..k-1]) / total` (`ratios[0]` = 0).
List<double> _prefixRatios(List<String> items, int total) {
  final ratios = <double>[];
  var acc = 0;
  for (var k = 0; k < items.length; k++) {
    ratios.add(acc / total);
    acc += sentenceWeight(items[k]);
  }
  return ratios;
}
