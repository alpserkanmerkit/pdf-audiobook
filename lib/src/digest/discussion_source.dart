import 'package:sesli_kitap/src/digest/digest_model.dart';

/// PURE layer (gate-tested at 100%): discussion SOURCE SELECTOR.
/// Spec: internal design note (sections 3-C/5/6).
///
/// Builds the "SOURCE MATERIAL" block added to the discussion's user message:
/// book summary + 2-3 chapter summaries most relevant to the topic + (caller-supplied)
/// selected passages; it is HARD-CAPPED by a character budget. Relevance scoring is
/// PURE and DETERMINISTIC (Turkish lowercase term matching) -- the optional mini-LLM
/// selection was deferred to Wave-B. No IO.

/// Relevance score of a chapter for a topic (deterministic tie-breaking order).
class ScoredChapter {
  const ScoredChapter(this.chapter, this.score);
  final ChapterDigest chapter;
  final int score;
}

const String _sourceHeader =
    'SOURCE MATERIAL (book digest):\n\n'
    '=== BOOK SUMMARY ===\n';

/// Lowercase conversion that handles Turkish. Dart's locale-insensitive [String.toLowerCase]
/// maps 'I' to 'i'; in Turkish the correct mapping is 'ı'. It first applies
/// I -> ı and İ -> i (the inverse of turkish_case.dart).
String _trLower(String s) =>
    s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

/// Turkish stopwords (frequent conjunctions/particles that add noise to the score) --
/// 3+ letter words that are not semantic terms. Short words (< 3 letters) are already filtered out.
const Set<String> _stopwords = {
  'hakkında',
  'için',
  'gibi',
  'daha',
  'çok',
  'kadar',
  'ile',
  'ama',
  'veya',
  'ya',
  'bir',
  'bu',
  've',
};

/// Deterministic, unique term set from [topic]: Turkish lowercase, 3+ letters,
/// not a stopword. Order is preserved (first occurrence).
List<String> _topicTerms(String topic) {
  final terms = <String>[];
  final seen = <String>{};
  for (final rawWord in _trLower(topic).split(RegExp('[^0-9a-zçğıöşü]+'))) {
    if (rawWord.length < 3) continue;
    if (_stopwords.contains(rawWord)) continue;
    if (seen.add(rawWord)) terms.add(rawWord);
  }
  return terms;
}

/// Number of non-overlapping occurrences of [needle] in [haystack].
int _countOccurrences(String haystack, String needle) {
  if (needle.isEmpty) return 0;
  var count = 0;
  var from = 0;
  while (true) {
    final idx = haystack.indexOf(needle, from);
    if (idx < 0) break;
    count++;
    from = idx + needle.length;
  }
  return count;
}

int _scoreChapter(ChapterDigest chapter, List<String> terms) {
  if (terms.isEmpty) return 0;
  final titleText = _trLower(chapter.title ?? '');
  final summaryText = _trLower(chapter.summary);
  var score = 0;
  for (final term in terms) {
    // A title match weighs more than a summary match (x3): the title points directly at the topic.
    score += _countOccurrences(titleText, term) * 3;
    score += _countOccurrences(summaryText, term);
  }
  return score;
}

/// Returns ALL chapters of [digest] with their relevance score for [topic] (including
/// score 0), sorted by descending score; on ties, the lower `chapterIndex` comes first
/// (deterministic).
List<ScoredChapter> scoreChaptersForTopic({
  required BookDigest digest,
  required String topic,
}) {
  final terms = _topicTerms(topic);
  final scored =
      [
        for (final c in digest.chapters)
          ScoredChapter(c, _scoreChapter(c, terms)),
      ]..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        return a.chapter.chapterIndex.compareTo(b.chapter.chapterIndex);
      });
  return scored;
}

/// Returns up to [maxChapters] chapters relevant to [topic] (score > 0), in score order.
/// Empty if nothing matches (score-0 chapters are NOT selected -- the book summary alone
/// serves as the source).
List<ChapterDigest> selectRelevantChapters({
  required BookDigest digest,
  required String topic,
  int maxChapters = 3,
}) {
  if (maxChapters <= 0) return const [];
  final scored = scoreChaptersForTopic(digest: digest, topic: topic);
  return [
    for (final s in scored)
      if (s.score > 0) s.chapter,
  ].take(maxChapters).toList();
}

/// Human-readable label of a chapter in the source block. The title if present;
/// otherwise "Chapter N" (1-based).
String _chapterLabel(ChapterDigest c) {
  final t = c.title?.trim();
  if (t != null && t.isNotEmpty) return t;
  return 'Chapter ${c.chapterIndex + 1}';
}

/// Builds the "SOURCE MATERIAL" block added to the discussion's user message:
/// book summary + 2-3 chapter summaries most relevant to [topic] + [passages].
/// The output NEVER exceeds [maxChars] characters -- a block that does not fit is
/// dropped starting from the first piece that does not fit; if even the header does
/// not fit, it is hard-truncated.
String selectDigestContext({
  required BookDigest digest,
  required String topic,
  required int maxChars,
  List<String> passages = const [],
}) {
  if (maxChars <= 0) return '';

  final head = '$_sourceHeader${digest.bookSummary}';
  // If the budget cannot even fit the whole header, hard-truncate (deterministic).
  if (head.length > maxChars) return head.substring(0, maxChars);

  final buffer = StringBuffer(head);
  var used = head.length;

  bool tryAppend(String chunk) {
    if (used + chunk.length > maxChars) return false;
    buffer.write(chunk);
    used += chunk.length;
    return true;
  }

  final relevant = selectRelevantChapters(digest: digest, topic: topic);
  for (final c in relevant) {
    final section =
        '\n\n=== CHAPTER: ${_chapterLabel(c)} '
        '(s.${c.startPage}-${c.endPage}) ===\n${c.summary}';
    if (!tryAppend(section)) break;
  }

  // Passages go under a single "SELECTED PASSAGES" heading; if the heading and the
  // first passage do not fit together, none are added (the heading alone is meaningless).
  var first = true;
  for (final p in passages) {
    final chunk = first ? '\n\n=== SELECTED PASSAGES ===\n$p' : '\n\n$p';
    if (!tryAppend(chunk)) break;
    first = false;
  }

  return buffer.toString();
}
