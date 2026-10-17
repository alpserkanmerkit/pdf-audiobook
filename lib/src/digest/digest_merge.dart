import 'package:sesli_kitap/src/digest/digest_model.dart';

/// PURE layer (gate-tested at 100%): merges a chapter's N PART-SUMMARIES into a
/// SINGLE [ChapterDigest]. No IO.
///
/// CRITICAL review note (Digest-A): `chapterDigestCacheKey` has NO partIndex
/// -> io must FIRST merge a chapter's N part-summaries into ONE ChapterDigest with
/// this function and only THEN cache it (otherwise the part records overwrite or
/// lose each other). Spec: internal design note (sections 3/4/6).

/// [chapterIndex]/[title]/[startPage]/[endPage] are the chapter's fixed identity;
/// [partSummaries] is each part's summary text (the raw LLM replies io received).
/// If [partIndexes] is omitted, `partSummaries` is assumed to already be in plan
/// order (0..N-1); if given, the element at each index is paired with
/// [partSummaries], and the merged result orders the parts by ascending partIndex
/// (arrival order is NOT trusted -- parallel call replies may come back mixed up).
///
/// pagesProcessed is mechanical: the chapter's full page range ([startPage]..[endPage])
/// -- since all parts are merged, the chapter counts as FULLY processed.
ChapterDigest mergeChapterParts({
  required int chapterIndex,
  required String? title,
  required int startPage,
  required int endPage,
  required List<String> partSummaries,
  List<int>? partIndexes,
}) {
  if (partSummaries.isEmpty) {
    throw ArgumentError.value(
      partSummaries,
      'partSummaries',
      'at least one part summary is required',
    );
  }
  if (partIndexes != null && partIndexes.length != partSummaries.length) {
    throw ArgumentError.value(
      partIndexes,
      'partIndexes',
      'must have the same length as partSummaries',
    );
  }

  final ordered = List<String>.from(partSummaries);
  if (partIndexes != null) {
    final indexed = List<int>.generate(partSummaries.length, (i) => i)
      ..sort((a, b) => partIndexes[a].compareTo(partIndexes[b]));
    for (var i = 0; i < indexed.length; i++) {
      ordered[i] = partSummaries[indexed[i]];
    }
  }

  return ChapterDigest(
    chapterIndex: chapterIndex,
    title: title,
    startPage: startPage,
    endPage: endPage,
    pagesProcessed: endPage - startPage + 1,
    summary: ordered.join('\n\n'),
  );
}
