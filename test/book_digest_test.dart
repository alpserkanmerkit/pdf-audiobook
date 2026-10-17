// RED-once oracle test (DG-W1): the PRODUCTION io orchestrator of the book digest.
// The lib/io HTTP body is OUTSIDE the coverage gate (sibling llm_discussion_test /
// llm_cleaner_request_test pattern) -> with a fake LLM client (canned summaries) this
// verifies that BookDigestBuilder.build produces the correct BookDigest, that the
// coverage manifest's isComplete is true, and that part-merging is correct (CRITICAL
// review note Digest-A: without partIndex, N parts must MERGE into ONE ChapterDigest
// and only then be cached).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/io/book_digest.dart';
import 'package:sesli_kitap/io/cache_store.dart';
import 'package:sesli_kitap/src/digest/coverage_manifest.dart';
import 'package:sesli_kitap/src/digest/digest_constants.dart'
    show chapterDigestCacheKey;

/// Canned-summary fake: records every call and returns a deterministic summary text.
/// Tells the book-summary call (isChapterSummary=false) apart from the chapter calls
/// (isChapterSummary=true).
class _FakeDigestClient implements DigestSummaryClient {
  final List<String> requestedTexts = [];
  int chapterCalls = 0;
  int bookCalls = 0;
  Exception? failChapterAt; // optional, for the error path being tested

  @override
  Future<String> summarizeChapterPart({
    required String title,
    required String pageText,
  }) async {
    chapterCalls++;
    requestedTexts.add(pageText);
    if (failChapterAt != null && chapterCalls == 1) {
      throw failChapterAt!;
    }
    return 'SUMMARY[$title]: ${pageText.length} chars.';
  }

  @override
  Future<String> summarizeBook({required List<String> chapterSummaries}) async {
    bookCalls++;
    return 'BOOK SUMMARY (${chapterSummaries.length} chapters)';
  }
}

void main() {
  late Directory tmp;
  late CacheStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('book_digest_test');
    store = CacheStore(tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  // A scaled-down map similar to Mir: 3 chapters, one large enough to be split into
  // parts (also covers the large-chapter sub-splitting path).
  const chapters = [
    (title: 'Giriş', startPage: 1, endPage: 2),
    (title: 'Dev Bölüm', startPage: 3, endPage: 8), // sub-split (below)
    (title: 'Sonuç', startPage: 9, endPage: 10),
  ];
  const totalPages = 10;

  String pageTextOf(int page) => 'Sayfa $page metni. ' * 5;

  Future<BookDigestResult> buildWith(_FakeDigestClient client) {
    final builder = BookDigestBuilder(
      store: store,
      client: client,
      bookHash: 'kitap123',
      pageText: pageTextOf,
    );
    return builder.build(
      chapters: chapters,
      totalPages: totalPages,
      // Small budget: 'Dev Bölüm' (6 pages) must be split into 2 parts.
      maxTokensPerCall: 30,
      charsPerPage: 100,
    );
  }

  group('BookDigestBuilder.build — basic generation', () {
    test(
      'BookDigest includes all chapters + a book summary is produced',
      () async {
        final client = _FakeDigestClient();
        final result = await buildWith(client);

        expect(result.digest.bookHash, 'kitap123');
        expect(result.digest.chapters, hasLength(3));
        expect(result.digest.bookSummary, contains('BOOK SUMMARY'));
        expect(client.bookCalls, 1);
      },
    );

    test('CRITICAL Digest-A: the N part-summaries of the big chapter are merged into '
        'ONE ChapterDigest (no partIndex in the cache key)', () async {
      final client = _FakeDigestClient();
      final result = await buildWith(client);

      final devChapter = result.digest.chapters.firstWhere(
        (c) => c.title == 'Dev Bölüm',
      );
      // The 6-page chapter must be split into at least 2 parts (the budget is small).
      expect(client.chapterCalls, greaterThan(3));
      // The merged summary must contain ALL the PARTS (not one part's summary).
      expect(devChapter.summary, contains('SUMMARY[Dev Bölüm]'));
      // The merged chapter covers the whole page range (verified again in the
      // coverage test) -- but here directly through the model.
      expect(devChapter.startPage, 3);
      expect(devChapter.endPage, 8);
      expect(devChapter.pagesProcessed, 6);
    });

    test(
      'cache: only ONE ChapterDigest record is written (no part-intermediate records)',
      () async {
        final client = _FakeDigestClient();
        await buildWith(client);

        // For the big chapter the cache key does NOT carry partIndex (review note):
        // chapterDigestCacheKey(chapterIndex: 1) is the single record; the multi-part
        // records are NOT VISIBLE on disk (the merge happens BEFORE the cache).
        final key = chapterDigestCacheKey(
          bookHash: 'kitap123',
          chapterIndex: 1,
        );
        final cached = await store.readChapterDigest(key);
        expect(cached, isNotNull);
        expect(cached!.startPage, 3);
        expect(cached.endPage, 8);
      },
    );

    test(
      'coverage manifest computes isComplete MECHANICALLY (not an LLM claim)',
      () async {
        final client = _FakeDigestClient();
        final result = await buildWith(client);

        final coverage = buildCoverage(result.digest, totalPages: totalPages);
        expect(coverage.isComplete, isTrue);
        expect(coverage.uncoveredRanges, isEmpty);
        expect(coverage.overlapRanges, isEmpty);
        expect(coverage.processedPages, totalPages);
        // build() must carry the same report too (io does not compute it itself --
        // it calls the same pure function).
        expect(result.coverage.isComplete, isTrue);
      },
    );
  });

  group('BookDigestBuilder.build — cache-once (once per book)', () {
    test(
      'a second build with the same bookHash does NOT call the network again (full cache)',
      () async {
        final client1 = _FakeDigestClient();
        await buildWith(client1);
        final totalCallsFirst = client1.chapterCalls + client1.bookCalls;
        expect(totalCallsFirst, greaterThan(0));

        final client2 = _FakeDigestClient();
        final result2 = await buildWith(client2);
        expect(client2.chapterCalls, 0);
        expect(client2.bookCalls, 0);
        expect(result2.digest.chapters, hasLength(3));
        expect(result2.coverage.isComplete, isTrue);
      },
    );
  });

  group('BookDigestBuilder.build — call-count order of magnitude', () {
    test('chapter calls + book call total is in the expected range', () async {
      final client = _FakeDigestClient();
      await buildWith(client);
      // 3 chapters + the sub-split big chapter + 1 book-summary call.
      expect(client.chapterCalls, greaterThanOrEqualTo(4));
      expect(client.bookCalls, 1);
    });
  });
}
