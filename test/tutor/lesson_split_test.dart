// Oracle RED test (2026-10-05, "private lesson book" Slice-1).
// Spec: internal design note §3.1 (splitting a chapter into 3-5 lesson parts).
//
// Pinned contract (pure logic, no I/O):
// - Part count N = ceil(total / targetChars), clamped to the range [3, 5].
// - Parts are cut at page boundaries; ordered, contiguous, covering all pages.
// - Each part's text is the "\n\n"-joined trimmed text of its non-empty pages.
// - Each part contains at least one filled page.
// - Invalid input (empty list, unordered pages, <3 filled pages, empty text) is a visible error.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/tutor/lesson_split.dart';

/// [count] pages, each [chars] characters long (page numbers start at [first]).
List<ChapterPage> _equalPages(int count, int chars, {int first = 1}) => [
  for (var i = 0; i < count; i++)
    ChapterPage(
      page: first + i,
      text: String.fromCharCode(97 + i % 26) * chars,
    ),
];

String _joinedPageText(List<ChapterPage> pages) =>
    pages.map((p) => p.text.trim()).where((t) => t.isNotEmpty).join('\n\n');

void _expectContiguousCover(List<LessonPart> parts, List<ChapterPage> pages) {
  expect(parts.first.fromPage, pages.first.page);
  expect(parts.last.toPage, pages.last.page);
  for (var i = 0; i < parts.length; i++) {
    expect(parts[i].index, i, reason: 'index must be 0-based and ordered');
    expect(
      parts[i].fromPage <= parts[i].toPage,
      isTrue,
      reason: 'part $i: fromPage <= toPage',
    );
    if (i > 0) {
      expect(
        parts[i].fromPage,
        parts[i - 1].toPage + 1,
        reason: 'part $i must start right after the previous one',
      );
    }
  }
}

void main() {
  group('constants', () {
    test('min 3, max 5 parts; target 15000 characters', () {
      expect(kLessonMinParts, 3);
      expect(kLessonMaxParts, 5);
      expect(kLessonTargetChars, 15000);
    });
  });

  group('part count', () {
    test('short total -> at least 3 parts', () {
      final pages = _equalPages(
        6,
        100,
      ); // 600 chars, target 15000 -> ceil=1 -> 3
      final parts = splitChapterIntoLessons(pages);
      expect(parts.length, 3);
    });

    test('long total -> at most 5 parts', () {
      final pages = _equalPages(27, 3100); // ~83700 chars -> ceil=6 -> 5
      final parts = splitChapterIntoLessons(pages);
      expect(parts.length, 5);
    });

    test('middle value: 40000 chars / target 10000 -> 4 parts', () {
      final pages = _equalPages(8, 5000);
      final parts = splitChapterIntoLessons(pages, targetChars: 10000);
      expect(parts.length, 4);
    });

    test(
      'exact division boundary ceil: 30001 chars / target 10000 -> 4 parts',
      () {
        final pages = [
          ..._equalPages(3, 10000),
          const ChapterPage(page: 4, text: 'x'),
        ];
        final parts = splitChapterIntoLessons(pages, targetChars: 10000);
        expect(parts.length, 4);
      },
    );

    test('measured characters are after trimming (spaces are not counted)', () {
      // Each page: 4000 filled chars + 6000 spaces. Untrimmed 40000 -> 4 parts;
      // trimmed 16000 / 10000 -> ceil=2 -> min 3.
      final pages = [
        for (var i = 1; i <= 4; i++)
          ChapterPage(page: i, text: '${'k' * 4000}${' ' * 6000}'),
      ];
      final parts = splitChapterIntoLessons(pages, targetChars: 10000);
      expect(parts.length, 3);
    });
  });

  group('boundaries and text', () {
    test('parts are ordered, contiguous and cover all pages', () {
      final pages = _equalPages(12, 2000, first: 164);
      final parts = splitChapterIntoLessons(pages, targetChars: 5000);
      _expectContiguousCover(parts, pages);
    });

    test('with equal pages, part page counts differ by at most 1', () {
      final pages = _equalPages(10, 1000);
      final parts = splitChapterIntoLessons(pages, targetChars: 2500);
      expect(parts.length, 4);
      final sizes = [for (final p in parts) p.toPage - p.fromPage + 1];
      final maxSize = sizes.reduce((a, b) => a > b ? a : b);
      final minSize = sizes.reduce((a, b) => a < b ? a : b);
      expect(maxSize - minSize <= 1, isTrue, reason: 'sizes: $sizes');
    });

    test('the union of part texts equals the union of page texts', () {
      final pages = _equalPages(9, 1200, first: 20);
      final parts = splitChapterIntoLessons(pages, targetChars: 3000);
      expect(parts.map((p) => p.text).join('\n\n'), _joinedPageText(pages));
    });

    test('part text is only the trimmed text of its own pages', () {
      final pages = [
        const ChapterPage(page: 1, text: '  one  '),
        const ChapterPage(page: 2, text: 'two'),
        const ChapterPage(page: 3, text: '\nthree\n'),
      ];
      final parts = splitChapterIntoLessons(pages);
      expect(parts.length, 3);
      expect(parts[0].text, 'one');
      expect(parts[1].text, 'two');
      expect(parts[2].text, 'three');
      expect([parts[0].fromPage, parts[0].toPage], [1, 1]);
      expect([parts[2].fromPage, parts[2].toPage], [3, 3]);
    });

    test('an empty (image) page enters the range but adds no text', () {
      final pages = [
        ChapterPage(page: 1, text: 'a' * 500),
        const ChapterPage(page: 2, text: '   '),
        ChapterPage(page: 3, text: 'b' * 500),
        ChapterPage(page: 4, text: 'c' * 500),
        const ChapterPage(page: 5, text: ''),
        ChapterPage(page: 6, text: 'd' * 500),
      ];
      final parts = splitChapterIntoLessons(pages);
      _expectContiguousCover(parts, pages);
      expect(parts.map((p) => p.text).join('\n\n'), _joinedPageText(pages));
      for (final p in parts) {
        expect(
          p.text.trim().isNotEmpty,
          isTrue,
          reason: 'part ${p.index} is empty',
        );
        expect(p.text.contains('\n\n\n'), isFalse);
      }
    });

    test('each part has at least one filled page (filled page count = N)', () {
      // 3 filled pages with many empty pages in between: each part gets exactly 1 filled page.
      final pages = [
        const ChapterPage(page: 1, text: 'first'),
        for (var i = 2; i <= 5; i++) ChapterPage(page: i, text: ''),
        const ChapterPage(page: 6, text: 'second'),
        for (var i = 7; i <= 9; i++) ChapterPage(page: i, text: ' '),
        const ChapterPage(page: 10, text: 'third'),
      ];
      final parts = splitChapterIntoLessons(pages);
      expect(parts.length, 3);
      expect(parts.map((p) => p.text).toList(), ['first', 'second', 'third']);
      _expectContiguousCover(parts, pages);
    });

    test(
      'N cannot exceed the filled page count; a single huge page: parts are not empty',
      () {
        // 90003 chars / 15000 -> ceil=7 -> clamp 5; but only 4 filled pages -> N=4.
        final pages = [
          const ChapterPage(page: 1, text: 'x'),
          const ChapterPage(page: 2, text: 'y'),
          ChapterPage(page: 3, text: 'z' * 90000),
          const ChapterPage(page: 4, text: 'w'),
        ];
        final parts = splitChapterIntoLessons(pages);
        expect(parts.length, 4);
        _expectContiguousCover(parts, pages);
        expect(parts.map((p) => p.text).toList(), ['x', 'y', 'z' * 90000, 'w']);
      },
    );

    test(
      'if the threshold is passed on an empty page, the part extends to the next filled page; leading/trailing empty pages go to the edge parts',
      () {
        // Total 1020, N=3, thresholds 340 / 680. Part 2 cannot close at empty page 3
        // (its threshold was already exceeded, but it has no filled page) -> extends to filled page 4.
        final pages = [
          const ChapterPage(page: 1, text: ''),
          ChapterPage(page: 2, text: 'a' * 1000),
          const ChapterPage(page: 3, text: ''),
          ChapterPage(page: 4, text: 'b' * 10),
          ChapterPage(page: 5, text: 'c' * 10),
          const ChapterPage(page: 6, text: '  '),
        ];
        final parts = splitChapterIntoLessons(pages);
        expect(parts.length, 3);
        expect(
          [for (final p in parts) (p.fromPage, p.toPage)],
          [(1, 2), (3, 4), (5, 6)],
        );
        expect(parts.map((p) => p.text).toList(), [
          'a' * 1000,
          'b' * 10,
          'c' * 10,
        ]);
      },
    );

    test('the returned list cannot be modified', () {
      final parts = splitChapterIntoLessons(_equalPages(3, 10));
      expect(
        () => parts.add(
          const LessonPart(index: 9, fromPage: 1, toPage: 1, text: 'x'),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('invalid input raises a visible error', () {
    test('empty list', () {
      expect(
        () => splitChapterIntoLessons(const []),
        throwsA(isA<LessonSplitException>()),
      );
    });

    test('fewer than 3 filled pages', () {
      final pages = [
        const ChapterPage(page: 1, text: 'filled'),
        const ChapterPage(page: 2, text: ''),
        const ChapterPage(page: 3, text: 'filled'),
        const ChapterPage(page: 4, text: '   '),
      ];
      expect(
        () => splitChapterIntoLessons(pages),
        throwsA(isA<LessonSplitException>()),
      );
    });

    test('all pages empty', () {
      final pages = [
        for (var i = 1; i <= 5; i++) ChapterPage(page: i, text: '  '),
      ];
      expect(
        () => splitChapterIntoLessons(pages),
        throwsA(isA<LessonSplitException>()),
      );
    });

    test('page numbers are not strictly ascending (duplicate)', () {
      final pages = [
        const ChapterPage(page: 1, text: 'a'),
        const ChapterPage(page: 2, text: 'b'),
        const ChapterPage(page: 2, text: 'c'),
      ];
      expect(
        () => splitChapterIntoLessons(pages),
        throwsA(isA<LessonSplitException>()),
      );
    });

    test('page numbers are not strictly ascending (going backwards)', () {
      final pages = [
        const ChapterPage(page: 5, text: 'a'),
        const ChapterPage(page: 4, text: 'b'),
        const ChapterPage(page: 6, text: 'c'),
      ];
      expect(
        () => splitChapterIntoLessons(pages),
        throwsA(isA<LessonSplitException>()),
      );
    });

    test('targetChars <= 0', () {
      expect(
        () => splitChapterIntoLessons(_equalPages(3, 10), targetChars: 0),
        throwsA(isA<LessonSplitException>()),
      );
    });

    test(
      'error text is human-readable and does not include the class name',
      () {
        try {
          splitChapterIntoLessons(const []);
          fail('LessonSplitException expected');
        } on LessonSplitException catch (e) {
          expect(e.toString(), e.reason);
          expect(e.reason.trim().isNotEmpty, isTrue);
          expect(e.toString().contains('LessonSplitException'), isFalse);
        }
      },
    );
  });
}
