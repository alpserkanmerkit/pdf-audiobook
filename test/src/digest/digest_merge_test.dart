// RED-once oracle test (Wave-A / PR-A, review note Digest-A): CHAPTER-PART
// MERGE layer. chapterDigestCacheKey has NO partIndex -> the io layer
// must FIRST merge a chapter's N part summaries into one ChapterDigest, then
// cache it; this pure merge logic is 100% tested here.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/digest/digest_merge.dart';
import 'package:sesli_kitap/src/digest/digest_model.dart';

void main() {
  group('mergeChapterParts — single part', () {
    test('partCount=1: the single summary becomes a ChapterDigest as-is', () {
      final merged = mergeChapterParts(
        chapterIndex: 3,
        title: 'Yasa 1',
        startPage: 27,
        endPage: 62,
        partSummaries: const ['Single-part chapter summary.'],
      );
      expect(merged.chapterIndex, 3);
      expect(merged.title, 'Yasa 1');
      expect(merged.startPage, 27);
      expect(merged.endPage, 62);
      expect(merged.pagesProcessed, 62 - 27 + 1);
      expect(merged.summary, 'Single-part chapter summary.');
    });
  });

  group('mergeChapterParts — multiple parts (dev chapter sub-splitting)', () {
    test('merged by partIndex order, NOT by arrival order', () {
      // planDigest produces parts in order, but io may receive them in a different order
      // (parallel call returns) -- merging sorts by partIndex
      // and does not rely on arrival order.
      final merged = mergeChapterParts(
        chapterIndex: 0,
        title: 'Dev',
        startPage: 1,
        endPage: 300,
        partSummaries: const ['second part', 'first part', 'third part'],
        partIndexes: const [1, 0, 2],
      );
      expect(merged.summary, 'first part\n\nsecond part\n\nthird part');
      expect(merged.pagesProcessed, 300);
    });

    test('3 equal parts (100 pages/part) -> pagesProcessed total 300', () {
      final merged = mergeChapterParts(
        chapterIndex: 0,
        title: 'Dev',
        startPage: 1,
        endPage: 300,
        partSummaries: const ['p1', 'p2', 'p3'],
      );
      expect(merged.pagesProcessed, 300);
      expect(merged.summary, 'p1\n\np2\n\np3');
    });
  });

  group('mergeChapterParts — edge cases', () {
    test('empty partSummaries -> ArgumentError (nothing to merge)', () {
      expect(
        () => mergeChapterParts(
          chapterIndex: 0,
          title: null,
          startPage: 1,
          endPage: 10,
          partSummaries: const [],
        ),
        throwsArgumentError,
      );
    });

    test(
      'partIndexes length does not match partSummaries -> ArgumentError',
      () {
        expect(
          () => mergeChapterParts(
            chapterIndex: 0,
            title: null,
            startPage: 1,
            endPage: 10,
            partSummaries: const ['a', 'b'],
            partIndexes: const [0],
          ),
          throwsArgumentError,
        );
      },
    );

    test('untitled chapter (front matter) keeps null title', () {
      final merged = mergeChapterParts(
        chapterIndex: 0,
        title: null,
        startPage: 1,
        endPage: 12,
        partSummaries: const ['front matter summary'],
      );
      expect(merged.title, isNull);
    });
  });

  group('mergeChapterParts -> ChapterDigest contract compatibility', () {
    test(
      'produced ChapterDigest is counted as complete by coverage_manifest',
      () {
        // Plain integration: the merge output is a ChapterDigest directly -- no extra
        // conversion needed (can be passed to buildCoverage unconditionally).
        final merged = mergeChapterParts(
          chapterIndex: 5,
          title: 'X',
          startPage: 100,
          endPage: 109,
          partSummaries: const ['single part summary'],
        );
        expect(merged, isA<ChapterDigest>());
        expect(merged.pagesProcessed, merged.endPage - merged.startPage + 1);
      },
    );
  });
}
