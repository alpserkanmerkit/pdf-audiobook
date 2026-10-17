import 'dart:math' as math;

import 'package:sesli_kitap/src/digest/digest_constants.dart';

/// PURE layer (gate-tested at 100%): SUMMARIZATION WORK PLAN from the chapter map.
/// No IO -- this layer decides "how many calls, over which page range, for each
/// range"; the summarization itself (network) is done by io Wave-B. Spec:
/// internal design note (sections 3/6).

/// Plan for a single summarization call (one chapter, or one sub-part of it if needed).
class DigestJob {
  const DigestJob({
    required this.chapterIndex,
    required this.partIndex,
    required this.partCount,
    required this.title,
    required this.startPage,
    required this.endPage,
    required this.estimatedChars,
    required this.estimatedTokens,
  });

  /// 0-based order of the chapter it belongs to.
  final int chapterIndex;

  /// Which part of the chapter this is (0-based; 0 if not split).
  final int partIndex;

  /// Total number of parts in the chapter (1 if not split).
  final int partCount;

  /// Chapter title (`null` if untitled).
  final String? title;

  /// First page of this part (1-based, inclusive).
  final int startPage;

  /// Last page of this part (1-based, inclusive).
  final int endPage;

  /// Estimated characters (`pageCount * charsPerPage`); the base for token estimation.
  final int estimatedChars;

  /// Estimated tokens (`ceil(estimatedChars / charsPerToken)`). HONEST estimate:
  /// even if the minimum granule (1 page) exceeds the budget, this value stays ABOVE
  /// the budget -- no silent shrinking; the overrun can be reported to io.
  final int estimatedTokens;

  /// Number of pages in this part (inclusive range).
  int get pageCount => endPage - startPage + 1;
}

/// planDigest output: job list + whether the map is degenerate.
class DigestPlan {
  DigestPlan({
    required List<DigestJob> jobs,
    required this.usedFallback,
    required this.totalPages,
  }) : jobs = List<DigestJob>.unmodifiable(jobs);

  /// Summarization jobs (immutable), in book order.
  final List<DigestJob> jobs;

  /// Whether the chapter map was empty or degenerate and fell back to a single 1..N chapter.
  final bool usedFallback;

  /// Total planned pages (the `totalPages` input).
  final int totalPages;

  /// Number of distinct chapters (not the number of parts).
  int get chapterCount =>
      jobs.isEmpty ? 0 : jobs.map((j) => j.chapterIndex).toSet().length;
}

/// Builds a digest plan from the chapter map ([chapters]: title + 1-based inclusive page range).
///
/// - If a chapter exceeds the [maxTokensPerCall] token budget, it is split into page
///   ranges (parts are page-quantized and balanced; larger parts come first).
/// - If the map is empty or DEGENERATE (invalid range / out of bounds / reversed /
///   overlapping), it falls back to a single chapter 1..[totalPages] (`usedFallback = true`);
///   a gap (uncovered pages) is NOT degenerate -- the coverage layer reports it.
/// - If [totalPages] < 1, the plan is empty.
DigestPlan planDigest({
  required List<({String? title, int startPage, int endPage})> chapters,
  required int totalPages,
  int maxTokensPerCall = defaultMaxTokensPerCall,
  int charsPerPage = defaultCharsPerPage,
  double charsPerToken = defaultCharsPerToken,
}) {
  if (maxTokensPerCall < 1) {
    throw ArgumentError.value(maxTokensPerCall, 'maxTokensPerCall', '>= 1');
  }
  if (charsPerPage < 1) {
    throw ArgumentError.value(charsPerPage, 'charsPerPage', '>= 1');
  }
  if (charsPerToken <= 0) {
    throw ArgumentError.value(charsPerToken, 'charsPerToken', '> 0');
  }

  if (totalPages < 1) {
    return DigestPlan(
      jobs: const [],
      usedFallback: false,
      totalPages: totalPages,
    );
  }

  final valid = _isValidMap(chapters, totalPages);
  final effective = valid
      ? chapters
      : <({String? title, int startPage, int endPage})>[
          (title: null, startPage: 1, endPage: totalPages),
        ];

  // Max pages that fit in one call (minimum 1 -- even if a single page exceeds the
  // budget, there is no smaller granule).
  final pagesPerCall = math.max(
    1,
    (maxTokensPerCall * charsPerToken / charsPerPage).floor(),
  );

  final jobs = <DigestJob>[];
  for (var ci = 0; ci < effective.length; ci++) {
    final ch = effective[ci];
    final total = ch.endPage - ch.startPage + 1;
    final partCount = (total / pagesPerCall).ceil();
    var page = ch.startPage;
    for (var pi = 0; pi < partCount; pi++) {
      // Spread the remaining pages evenly over the remaining parts (larger parts first).
      final remainingPages = ch.endPage - page + 1;
      final remainingParts = partCount - pi;
      final partPages = (remainingPages / remainingParts).ceil();
      final partEnd = page + partPages - 1;
      final estChars = partPages * charsPerPage;
      jobs.add(
        DigestJob(
          chapterIndex: ci,
          partIndex: pi,
          partCount: partCount,
          title: ch.title,
          startPage: page,
          endPage: partEnd,
          estimatedChars: estChars,
          estimatedTokens: (estChars / charsPerToken).ceil(),
        ),
      );
      page = partEnd + 1;
    }
  }

  return DigestPlan(jobs: jobs, usedFallback: !valid, totalPages: totalPages);
}

/// Is the map valid? Every chapter lies within 1..totalPages, is not reversed, and is
/// ordered (starts after the end of the previous chapter -- gaps are allowed, overlaps
/// are not). An empty map is invalid (triggers the fallback).
bool _isValidMap(
  List<({String? title, int startPage, int endPage})> chapters,
  int totalPages,
) {
  if (chapters.isEmpty) return false;
  var prevEnd = 0;
  for (final ch in chapters) {
    if (ch.startPage < 1 || ch.endPage > totalPages) return false;
    if (ch.startPage > ch.endPage) return false;
    if (ch.startPage <= prevEnd) return false;
    prevEnd = ch.endPage;
  }
  return true;
}
