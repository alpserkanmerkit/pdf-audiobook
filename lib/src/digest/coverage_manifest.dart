import 'package:sesli_kitap/src/digest/digest_model.dart';

/// PURE layer (gate-tested at 100%): COVERAGE MANIFEST.
/// Spec: internal design note (section 4).
///
/// This layer gives the user MECHANICAL proof for the claim "the whole book was
/// framed" -- a count, NOT the LLM's own statement: chapter -> page-range ->
/// pagesProcessed table, gap/overlap detection; `isComplete` is true only while ALL
/// pages are fully covered exactly once. No IO.

/// A page range (1-based, inclusive).
typedef PageRange = ({int start, int end});

/// Coverage row of a single chapter.
class ChapterCoverage {
  const ChapterCoverage({
    required this.chapterIndex,
    required this.title,
    required this.startPage,
    required this.endPage,
    required this.pagesProcessed,
    required this.rangeValid,
  });
  final int chapterIndex;
  final String? title;
  final int startPage;
  final int endPage;

  /// Raw pagesProcessed claimed by the chapter (not clamped; kept for transparency).
  final int pagesProcessed;

  /// Is the claim valid? 1 <= start <= end <= totalPages.
  final bool rangeValid;

  /// Number of pages covered by the range; 0 for an invalid range (the mechanical
  /// proof does not count an invalid claim).
  int get pageCount => rangeValid ? (endPage - startPage + 1) : 0;

  /// Actually processed pages, clamped to the [0, pageCount] range.
  int get effectiveProcessed {
    if (!rangeValid) return 0;
    if (pagesProcessed < 0) return 0;
    if (pagesProcessed > pageCount) return pageCount;
    return pagesProcessed;
  }

  /// Is the chapter complete? Valid range + fully processed + summary present.
  bool get complete => rangeValid && effectiveProcessed >= pageCount;
}

/// Coverage report (mechanical). `isComplete` is true only if everything holds.
class CoverageReport {
  CoverageReport({
    required this.totalPages,
    required List<ChapterCoverage> chapters,
    required List<PageRange> uncoveredRanges,
    required List<PageRange> overlapRanges,
    required List<int> incompleteChapters,
    required this.processedPages,
  }) : chapters = List<ChapterCoverage>.unmodifiable(chapters),
       uncoveredRanges = List<PageRange>.unmodifiable(uncoveredRanges),
       overlapRanges = List<PageRange>.unmodifiable(overlapRanges),
       incompleteChapters = List<int>.unmodifiable(incompleteChapters);
  final int totalPages;

  /// Chapter coverage rows (in input order).
  final List<ChapterCoverage> chapters;

  /// Page ranges not framed by any chapter.
  final List<PageRange> uncoveredRanges;

  /// Ranges framed by more than one chapter (overlaps).
  final List<PageRange> overlapRanges;

  /// 0-based indexes of chapters that are not fully processed, invalid, or without a summary.
  final List<int> incompleteChapters;

  /// Mechanical count: sum(effectiveProcessed) -- the numeric basis for the claim
  /// "N/total pages went through a summarization call".
  final int processedPages;

  /// FULL coverage: every page is covered exactly once (no gaps or overlaps) AND
  /// every chapter is complete. `isComplete = true` = mechanically "the whole book was framed".
  bool get isComplete =>
      totalPages >= 1 &&
      uncoveredRanges.isEmpty &&
      overlapRanges.isEmpty &&
      incompleteChapters.isEmpty;
}

/// Builds a mechanical coverage report from the chapter ranges of [digest].
CoverageReport buildCoverage(BookDigest digest, {required int totalPages}) {
  final chapters = <ChapterCoverage>[];
  final incomplete = <int>[];
  var processed = 0;

  // If totalPages >= 1: per-page coverage counter (1-based; index 0 is unused).
  final coverCount = totalPages >= 1
      ? List<int>.filled(totalPages + 1, 0)
      : <int>[];

  for (final c in digest.chapters) {
    final rangeValid =
        totalPages >= 1 &&
        c.startPage >= 1 &&
        c.startPage <= c.endPage &&
        c.endPage <= totalPages;
    final cov = ChapterCoverage(
      chapterIndex: c.chapterIndex,
      title: c.title,
      startPage: c.startPage,
      endPage: c.endPage,
      pagesProcessed: c.pagesProcessed,
      rangeValid: rangeValid,
    );
    chapters.add(cov);

    // The coverage counter reflects ACTUAL framing: a forward claim (start<=end)
    // covers the pages clipped to inside the book, even if it extends past the edge
    // (gaps and overlaps are mechanically exact). A reversed range (start>end) covers
    // nothing. `rangeValid`/`processedPages` measure claim validity separately -> an
    // invalid claim creates no gap, yet it still cannot make isComplete true.
    if (totalPages >= 1 && c.startPage <= c.endPage) {
      final from = c.startPage < 1 ? 1 : c.startPage;
      final to = c.endPage > totalPages ? totalPages : c.endPage;
      for (var p = from; p <= to; p++) {
        coverCount[p]++;
      }
    }
    if (rangeValid) {
      processed += cov.effectiveProcessed;
    }
    if (!cov.complete || c.summary.trim().isEmpty) {
      incomplete.add(c.chapterIndex);
    }
  }

  final uncovered = <PageRange>[];
  final overlap = <PageRange>[];
  if (totalPages >= 1) {
    _collectRuns(coverCount, totalPages, (p) => p == 0, uncovered);
    _collectRuns(coverCount, totalPages, (p) => p >= 2, overlap);
  }

  return CoverageReport(
    totalPages: totalPages,
    chapters: chapters,
    uncoveredRanges: uncovered,
    overlapRanges: overlap,
    incompleteChapters: incomplete,
    processedPages: processed,
  );
}

/// Appends to [out] the contiguous runs of pages in 1..totalPages that satisfy [pred], as ranges.
void _collectRuns(
  List<int> coverCount,
  int totalPages,
  bool Function(int) pred,
  List<PageRange> out,
) {
  int? runStart;
  for (var p = 1; p <= totalPages; p++) {
    if (pred(coverCount[p])) {
      runStart ??= p;
    } else if (runStart != null) {
      out.add((start: runStart, end: p - 1));
      runStart = null;
    }
  }
  if (runStart != null) {
    out.add((start: runStart, end: totalPages));
  }
}
