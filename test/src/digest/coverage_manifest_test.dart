// RED-once oracle test (Wave-A / PR-A): COVERAGE MANIFEST layer.
// Spec: internal design note §4 —
// the claim "the whole book was framed" is a mechanical count, NOT an LLM statement:
// chapter -> page range -> pagesProcessed table; gap/overlap detection;
// isComplete is true only when all pages are fully covered.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/digest/coverage_manifest.dart';
import 'package:sesli_kitap/src/digest/digest_model.dart';

BookDigest _digest(List<ChapterDigest> chapters) => BookDigest(
  bookHash: 'h',
  createdAtMs: 0,
  chapters: chapters,
  bookSummary: 'k',
);

ChapterDigest _ch(
  int index,
  int start,
  int end, {
  int? done,
  String summary = 'summary',
  String? title,
}) => ChapterDigest(
  chapterIndex: index,
  title: title,
  startPage: start,
  endPage: end,
  pagesProcessed: done ?? (end - start + 1),
  summary: summary,
);

/// Mir-like 20-chapter structure: content s13-704 contiguous (692 pages).
const List<(String, int, int)> _mirRanges = [
  ('Giris', 13, 26),
  ('Yasa 1', 27, 62),
  ('Yasa 2', 63, 98),
  ('Yasa 3', 99, 134),
  ('Yasa 4', 135, 170),
  ('Yasa 5', 171, 206),
  ('Savunuculuk Yasasi', 207, 251),
  ('Yasa 7', 252, 287),
  ('Yasa 8', 288, 323),
  ('Uyum', 324, 376),
  ('Yasa 10', 377, 412),
  ('Yasa 11', 413, 448),
  ('Yasa 12', 449, 484),
  ('Yasa 13', 485, 520),
  ('Yasa 14', 521, 556),
  ('Yasa 15', 557, 592),
  ('Yasa 16', 593, 628),
  ('Yasa 17', 629, 671),
  ('Olumu Inkar', 672, 700),
  ('Kaynakca', 701, 704),
];

void main() {
  group('buildCoverage — full coverage', () {
    test('two chapters covering 1..10 fully -> isComplete true', () {
      final r = buildCoverage(
        _digest([_ch(0, 1, 4), _ch(1, 5, 10)]),
        totalPages: 10,
      );
      expect(r.isComplete, isTrue);
      expect(r.uncoveredRanges, isEmpty);
      expect(r.overlapRanges, isEmpty);
      expect(r.incompleteChapters, isEmpty);
      expect(r.processedPages, 10);
      expect(r.totalPages, 10);
      expect(r.chapters, hasLength(2));
      final first = r.chapters.first;
      expect(first.chapterIndex, 0);
      expect(first.pageCount, 4);
      expect(first.pagesProcessed, 4);
      expect(first.rangeValid, isTrue);
      expect(first.complete, isTrue);
    });
  });

  group('buildCoverage — missing pages / gaps', () {
    test('gap in the middle -> uncoveredRanges + isComplete false', () {
      final r = buildCoverage(
        _digest([_ch(0, 1, 4), _ch(1, 7, 10)]),
        totalPages: 10,
      );
      expect(r.uncoveredRanges, [(start: 5, end: 6)]);
      expect(r.isComplete, isFalse);
    });

    test('leading and trailing gaps are reported as separate ranges', () {
      final r = buildCoverage(_digest([_ch(0, 3, 8)]), totalPages: 10);
      expect(r.uncoveredRanges, [(start: 1, end: 2), (start: 9, end: 10)]);
      expect(r.isComplete, isFalse);
    });

    test('pagesProcessed < pageCount -> chapter in the incomplete list', () {
      final r = buildCoverage(
        _digest([_ch(0, 1, 10, done: 7)]),
        totalPages: 10,
      );
      expect(r.incompleteChapters, [0]);
      expect(r.processedPages, 7);
      expect(r.isComplete, isFalse);
      expect(r.chapters.single.complete, isFalse);
    });

    test(
      'empty/blank summary -> chapter incomplete (summary PRESENT rule)',
      () {
        final r = buildCoverage(
          _digest([_ch(0, 1, 10, summary: '   ')]),
          totalPages: 10,
        );
        expect(r.incompleteChapters, [0]);
        expect(r.isComplete, isFalse);
      },
    );
  });

  group('buildCoverage — overlap', () {
    test('two chapters framing the same page -> overlapRanges filled', () {
      final r = buildCoverage(
        _digest([_ch(0, 1, 6), _ch(1, 5, 10)]),
        totalPages: 10,
      );
      expect(r.overlapRanges, [(start: 5, end: 6)]);
      expect(r.uncoveredRanges, isEmpty);
      expect(r.isComplete, isFalse);
    });
  });

  group('buildCoverage — invalid ranges / edges', () {
    test('reversed range: no pages framed, chapter incomplete', () {
      final r = buildCoverage(
        _digest([_ch(0, 10, 1, done: 10)]),
        totalPages: 10,
      );
      expect(r.chapters.single.rangeValid, isFalse);
      expect(r.chapters.single.pageCount, 0);
      expect(r.uncoveredRanges, [(start: 1, end: 10)]);
      expect(r.incompleteChapters, [0]);
      expect(r.processedPages, 0);
    });

    test(
      'range beyond the book bound: clipped for counting, chapter invalid',
      () {
        final r = buildCoverage(
          _digest([_ch(0, 1, 12, done: 12)]),
          totalPages: 10,
        );
        // 1-10 were effectively framed (no gap)...
        expect(r.uncoveredRanges, isEmpty);
        // ...but the claim exceeds the book bound -> the mechanical proof rejects it.
        expect(r.chapters.single.rangeValid, isFalse);
        expect(r.processedPages, 0);
        expect(r.isComplete, isFalse);
      },
    );

    test('negative pagesProcessed is clipped to 0', () {
      final r = buildCoverage(
        _digest([_ch(0, 1, 10, done: -3)]),
        totalPages: 10,
      );
      expect(r.processedPages, 0);
      expect(r.incompleteChapters, [0]);
    });

    test(
      'excessive pagesProcessed is clipped to pageCount, raw claim kept',
      () {
        final r = buildCoverage(
          _digest([_ch(0, 1, 10, done: 99)]),
          totalPages: 10,
        );
        expect(r.processedPages, 10);
        expect(r.chapters.single.pagesProcessed, 99);
        expect(r.isComplete, isTrue);
      },
    );

    test('empty chapter list -> whole book is a gap, isComplete false', () {
      final r = buildCoverage(_digest(const []), totalPages: 10);
      expect(r.uncoveredRanges, [(start: 1, end: 10)]);
      expect(r.chapters, isEmpty);
      expect(r.isComplete, isFalse);
    });

    test('totalPages < 1 -> isComplete false, ranges empty', () {
      final r = buildCoverage(_digest([_ch(0, 1, 5)]), totalPages: 0);
      expect(r.isComplete, isFalse);
      expect(r.uncoveredRanges, isEmpty);
      expect(r.overlapRanges, isEmpty);
      expect(r.processedPages, 0);
    });
  });

  group('buildCoverage — realistic Mir-like scenario', () {
    List<ChapterDigest> mirChapters() => [
      for (var i = 0; i < _mirRanges.length; i++)
        _ch(
          i,
          _mirRanges[i].$2,
          _mirRanges[i].$3,
          title: _mirRanges[i].$1,
          summary: 'Chapter ${i + 1} summary',
        ),
    ];

    test(
      '20 chapters fully processed: 692/706, front/back matter honest gap',
      () {
        final r = buildCoverage(_digest(mirChapters()), totalPages: 706);
        // Mechanical count: sum(pagesProcessed) = 692 content pages.
        expect(r.processedPages, 692);
        expect(r.uncoveredRanges, [
          (start: 1, end: 12),
          (start: 705, end: 706),
        ]);
        expect(r.overlapRanges, isEmpty);
        expect(r.incompleteChapters, isEmpty);
        // The proof does not lie: front/back matter is not framed -> not complete.
        expect(r.isComplete, isFalse);
      },
    );

    test('front matter declared as its own row -> isComplete true', () {
      final full = [
        _ch(0, 1, 12, summary: 'Front matter (cover/imprint).'),
        for (var i = 0; i < _mirRanges.length; i++)
          _ch(
            i + 1,
            _mirRanges[i].$2,
            _mirRanges[i].$3,
            title: _mirRanges[i].$1,
            summary: 'Chapter ${i + 1} summary',
          ),
        _ch(21, 705, 706, summary: 'Back matter.'),
      ];
      final r = buildCoverage(_digest(full), totalPages: 706);
      expect(r.uncoveredRanges, isEmpty);
      expect(r.overlapRanges, isEmpty);
      expect(r.incompleteChapters, isEmpty);
      expect(r.isComplete, isTrue);
      expect(r.processedPages, 706);
    });
  });
}
