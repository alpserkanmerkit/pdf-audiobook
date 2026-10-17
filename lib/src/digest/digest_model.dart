import 'dart:convert';

/// PURE layer (gate-tested at 100%): book-digest DATA MODEL + JSON encoding.
/// No IO -- cache read/write lives in io Wave-B; this layer only defines the shape.
/// Spec: internal design note (sections 4/6).
///
/// Contract rule: fromJson/decode return `null` on BROKEN input instead of throwing
/// (reading from cache degrades softly -> io regenerates). Integrity is ALL-OR-NOTHING:
/// a single broken chapter discards the WHOLE book (no partial acceptance -- the
/// coverage proof must not rest on unreliable records).

/// Digest summary of a single chapter.
class ChapterDigest {
  const ChapterDigest({
    required this.chapterIndex,
    required this.title,
    required this.startPage,
    required this.endPage,
    required this.pagesProcessed,
    required this.summary,
  });

  /// 0-based chapter order (aligned with the plan's `chapterIndex`).
  final int chapterIndex;

  /// Chapter title; `null` for untitled chapters (front/back matter).
  final String? title;

  /// First page of the chapter (1-based, inclusive).
  final int startPage;

  /// Last page of the chapter (1-based, inclusive).
  final int endPage;

  /// Number of pages actually passed through a summarization call (coverage counter --
  /// a mechanical fact recorded by io, not the LLM's claim).
  final int pagesProcessed;

  /// Generated chapter summary text.
  final String summary;

  Map<String, Object?> toJson() => {
    'chapterIndex': chapterIndex,
    'title': title,
    'startPage': startPage,
    'endPage': endPage,
    'pagesProcessed': pagesProcessed,
    'summary': summary,
  };

  /// `null` if [raw] is not a map in the expected shape, or if required fields are
  /// missing or wrong-typed. `title` may only be `null` or a `String`
  /// (any other type -> `null`).
  static ChapterDigest? fromJson(Object? raw) {
    if (raw is! Map) return null;

    final index = raw['chapterIndex'];
    final start = raw['startPage'];
    final end = raw['endPage'];
    final processed = raw['pagesProcessed'];
    final summary = raw['summary'];
    if (index is! int ||
        start is! int ||
        end is! int ||
        processed is! int ||
        summary is! String) {
      return null;
    }

    final title = raw['title'];
    if (title != null && title is! String) return null;

    return ChapterDigest(
      chapterIndex: index,
      title: title as String?,
      startPage: start,
      endPage: end,
      pagesProcessed: processed,
      summary: summary,
    );
  }
}

/// Full digest of a book: chapter summaries + book-level summary.
class BookDigest {
  BookDigest({
    required this.bookHash,
    required this.createdAtMs,
    required List<ChapterDigest> chapters,
    required this.bookSummary,
  }) : chapters = List<ChapterDigest>.unmodifiable(chapters);

  /// JSON schema version (the report's `v:1` contract). If it is bumped, old cache
  /// entries are treated as invalid (`fromJson` -> `null`).
  static const int schemaVersion = 1;

  /// Book identity (same hash as the cache key space).
  final String bookHash;

  /// Creation time (epoch ms) -- shown in the coverage manifest as "creation: `<date>`".
  final int createdAtMs;

  /// Chapter summaries (immutable).
  final List<ChapterDigest> chapters;

  /// Book-level summary (the core of the discussion source block).
  final String bookSummary;

  Map<String, Object?> toJson() => {
    'v': schemaVersion,
    'bookHash': bookHash,
    'createdAtMs': createdAtMs,
    'chapters': [for (final c in chapters) c.toJson()],
    'bookSummary': bookSummary,
  };

  /// `null` if [raw] is not a map / the version does not match / a required field is
  /// missing or corrupt / a single entry in the chapter list is corrupt.
  static BookDigest? fromJson(Object? raw) {
    if (raw is! Map) return null;
    if (raw['v'] != schemaVersion) return null;

    final bookHash = raw['bookHash'];
    final createdAtMs = raw['createdAtMs'];
    final chaptersRaw = raw['chapters'];
    final bookSummary = raw['bookSummary'];
    if (bookHash is! String ||
        createdAtMs is! int ||
        chaptersRaw is! List ||
        bookSummary is! String) {
      return null;
    }

    final chapters = <ChapterDigest>[];
    for (final entry in chaptersRaw) {
      final ch = ChapterDigest.fromJson(entry);
      if (ch == null) return null;
      chapters.add(ch);
    }

    return BookDigest(
      bookHash: bookHash,
      createdAtMs: createdAtMs,
      chapters: chapters,
      bookSummary: bookSummary,
    );
  }
}

/// [digest] -> compact JSON text (written to the cache).
String encodeBookDigest(BookDigest digest) => jsonEncode(digest.toJson());

/// JSON text -> [BookDigest]; `null` if it is malformed or semantically corrupt.
BookDigest? decodeBookDigest(String source) {
  final Object? parsed;
  try {
    parsed = jsonDecode(source);
  } on FormatException {
    return null;
  }
  return BookDigest.fromJson(parsed);
}
