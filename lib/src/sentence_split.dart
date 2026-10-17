/// Splits text into sentences. The reader draws each piece as a separate box;
/// TTS chunking and karaoke timing use the same pieces.
///
/// A sentence end = a run of [.!?] (a closing quote/bracket that follows is part
/// of the sentence). Field report (2026-09-28, Freud PDF, 649 pages): the old
/// `[^.!?]+[.!?]*` split at every period -> broken boxes such as "(s." | "553): ...",
/// "52." | "sayfa", "vb." | "'nin", "F." | "RÜYADA", "www." | "saykitap." (893 of
/// 12951 blocks started with a lowercase letter). Now a period is NOT counted as a
/// sentence end in these cases:
/// - the text continues without a space and the next character is not an
///   uppercase letter ("3.5", "vb.'nin");
/// - the first character after the space is lowercase ("52. sayfa");
/// - a single period whose preceding word is a single uppercase letter or a
///   known abbreviation ("F. RÜYADA", "K. Fischer", "(s. 553)", "Dr. Ahmet").
/// A piece consisting only of punctuation (no letter or digit to read) is dropped.
/// Empty input -> [].
List<String> splitIntoSentences(String text) {
  final out = <String>[];
  var start = 0;
  var i = 0;
  while (i < text.length) {
    if (!_terminals.contains(text[i])) {
      i++;
      continue;
    }
    var runEnd = i;
    while (runEnd < text.length && _terminals.contains(text[runEnd])) {
      runEnd++;
    }
    var end = runEnd;
    while (end < text.length && _closers.contains(text[end])) {
      end++;
    }
    if (_isBoundary(text, i, runEnd, end)) {
      _addPiece(out, text.substring(start, end));
      start = end;
    }
    i = end;
  }
  _addPiece(out, text.substring(start));
  return out;
}

const String _terminals = '.!?';
const String _closers = '"\'”’»)';

/// Known abbreviations stored in lowercase (they end with a single period).
const Set<String> _abbreviations = {
  's',
  'sf',
  'bkz',
  'bk',
  'vb',
  'vs',
  'vd',
  'örn',
  'dr',
  'prof',
  'doç',
  'yy',
  'ltd',
  'şti',
  'cad',
  'sok',
  'mah',
};

final RegExp _readable = RegExp(r'[\p{L}\p{N}]', unicode: true);

bool _isUpper(String c) => c != c.toLowerCase();
bool _isLower(String c) => c != c.toUpperCase() && !_isUpper(c);

/// [punctStart]..[runEnd] is the punctuation run, [end] is the position after
/// the closing characters. Is this period a sentence end?
bool _isBoundary(String text, int punctStart, int runEnd, int end) {
  final glued = end < text.length && text[end].trim().isNotEmpty;
  var j = end;
  while (j < text.length && text[j].trim().isEmpty) {
    j++;
  }
  if (j >= text.length) return true;
  final next = text[j];
  if (glued && !_isUpper(next)) return false;
  if (_isLower(next)) return false;
  final singleDot = runEnd - punctStart == 1 && text[punctStart] == '.';
  return !(singleDot && _isAbbreviation(_wordBefore(text, punctStart)));
}

/// The letter sequence (word) immediately before [index].
String _wordBefore(String text, int index) {
  var k = index;
  while (k > 0 && text[k - 1].toLowerCase() != text[k - 1].toUpperCase()) {
    k--;
  }
  return text.substring(k, index);
}

bool _isAbbreviation(String word) =>
    (word.length == 1 && _isUpper(word)) ||
    _abbreviations.contains(word.toLowerCase());

void _addPiece(List<String> out, String piece) {
  final s = piece.trim();
  if (_readable.hasMatch(s)) out.add(s);
}
