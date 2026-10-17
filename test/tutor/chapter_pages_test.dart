// Oracle RED test (2026-10-06, private lesson Slice-2, G7a).
// Spec: internal design note §7.2 (chapter page gathering, pure).
//
// Pinned contract: for each page in the chapter's page range (Chapter.startPage..endPage),
// use the CLEAN cached text first, otherwise the raw PDF text; if neither exists the page
// enters the range with empty text (the splitter does not add empty pages to the text).
// The counter + one-line diagnostic make the Syncfusion measurement visible in the field.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/chapter_map.dart';
import 'package:sesli_kitap/src/tutor/chapter_pages.dart';
import 'package:sesli_kitap/src/tutor/lesson_split.dart';

/// Reader from a page -> text map; logs every call into [log].
Future<String?> Function(int) _reader(Map<int, String?> texts, List<int> log) =>
    (int p) async {
      log.add(p);
      return texts[p];
    };

void main() {
  group('gatherChapterPages — source selection', () {
    test(
      'clean text is used when present, trimmed; the raw reader is not called',
      () async {
        final cleanLog = <int>[];
        final rawLog = <int>[];
        final r = await gatherChapterPages(
          fromPage: 10,
          toPage: 11,
          readPage: _reader({
            10: '  Clean ten  ',
            11: 'Clean eleven',
          }, cleanLog),
          readRawPage: _reader({10: 'RAW', 11: 'RAW'}, rawLog),
        );
        expect(r.pages.map((p) => p.page), [10, 11]);
        expect(r.pages.map((p) => p.text), ['Clean ten', 'Clean eleven']);
        expect(r.cleanCount, 2);
        expect(r.rawCount, 0);
        expect(r.emptyCount, 0);
        expect(
          rawLog,
          isEmpty,
          reason: 'the PDF is not read when clean text exists',
        );
      },
    );

    test(
      'if clean text is missing (null), the raw text is used and counted',
      () async {
        final r = await gatherChapterPages(
          fromPage: 5,
          toPage: 5,
          readPage: _reader({5: null}, []),
          readRawPage: _reader({5: '  Raw five '}, []),
        );
        expect(r.pages.single.page, 5);
        expect(r.pages.single.text, 'Raw five');
        expect(r.cleanCount, 0);
        expect(r.rawCount, 1);
        expect(r.emptyCount, 0);
      },
    );

    test(
      'if clean text is only whitespace, it falls back to the raw text',
      () async {
        final r = await gatherChapterPages(
          fromPage: 1,
          toPage: 1,
          readPage: _reader({1: '   \n '}, []),
          readRawPage: _reader({1: 'Raw one'}, []),
        );
        expect(r.pages.single.text, 'Raw one');
        expect(r.rawCount, 1);
      },
    );

    test(
      'neither clean nor raw: the page enters the range with empty text and is counted as empty',
      () async {
        final r = await gatherChapterPages(
          fromPage: 3,
          toPage: 4,
          readPage: _reader({3: 'Three', 4: null}, []),
          readRawPage: _reader({4: '  '}, []),
        );
        expect(r.pages.map((p) => p.page), [3, 4]);
        expect(r.pages[1].text, '');
        expect(r.cleanCount, 1);
        expect(r.rawCount, 0);
        expect(r.emptyCount, 1);
      },
    );

    test(
      'without a raw reader, a non-clean page is counted as empty',
      () async {
        final r = await gatherChapterPages(
          fromPage: 7,
          toPage: 8,
          readPage: _reader({7: 'Seven'}, []),
        );
        expect(r.pages.map((p) => p.text), ['Seven', '']);
        expect(r.emptyCount, 1);
        expect(r.rawCount, 0);
      },
    );
  });

  group('gatherChapterPages — range and call count', () {
    test(
      'range is complete and ascending; the clean reader is called EXACTLY once per page',
      () async {
        final cleanLog = <int>[];
        final rawLog = <int>[];
        final r = await gatherChapterPages(
          fromPage: 164,
          toPage: 168,
          readPage: _reader({164: 'a', 166: 'c', 168: 'e'}, cleanLog),
          readRawPage: _reader({165: 'b'}, rawLog),
        );
        expect(r.pages.map((p) => p.page), [164, 165, 166, 167, 168]);
        expect(r.pages, hasLength(168 - 164 + 1));
        expect(cleanLog, [164, 165, 166, 167, 168]);
        expect(rawLog, [
          165,
          167,
        ], reason: 'raw is read only for pages without clean text');
        expect(r.cleanCount + r.rawCount + r.emptyCount, 5);
      },
    );

    test('single-page range (from == to) is valid', () async {
      final r = await gatherChapterPages(
        fromPage: 2,
        toPage: 2,
        readPage: _reader({2: 'two'}, []),
      );
      expect(r.pages, hasLength(1));
    });

    test('pages cannot be modified', () async {
      final r = await gatherChapterPages(
        fromPage: 1,
        toPage: 1,
        readPage: _reader({1: 'one'}, []),
      );
      expect(
        () => r.pages.add(const ChapterPage(page: 2, text: 'x')),
        throwsUnsupportedError,
      );
    });

    test('fromPage < 1 -> ArgumentError, reader is not called', () async {
      final log = <int>[];
      await expectLater(
        gatherChapterPages(fromPage: 0, toPage: 3, readPage: _reader({}, log)),
        throwsArgumentError,
      );
      expect(log, isEmpty);
    });

    test('toPage < fromPage -> ArgumentError, reader is not called', () async {
      final log = <int>[];
      await expectLater(
        gatherChapterPages(fromPage: 9, toPage: 8, readPage: _reader({}, log)),
        throwsArgumentError,
      );
      expect(log, isEmpty);
    });
  });

  group('describeChapterPages + tutorChapterLabel', () {
    test(
      'diagnostic line exactly: range, pages, clean/raw/empty, characters',
      () async {
        final r = await gatherChapterPages(
          fromPage: 164,
          toPage: 166,
          readPage: _reader({164: 'abcd'}, []),
          readRawPage: _reader({165: 'xy'}, []),
        );
        expect(
          describeChapterPages(r),
          'tutor text: s.164-166, 3 pages (clean 1, raw 1, empty 1), 6 ch',
        );
        expect(
          describeChapterPages(
            const ChapterPagesResult(
              pages: <ChapterPage>[],
              cleanCount: 0,
              rawCount: 0,
              emptyCount: 0,
            ),
          ),
          'tutor text: empty',
        );
      },
    );

    test(
      'chapter label: title + range if present, otherwise "Chapter <n>" (also when blank)',
      () {
        expect(
          tutorChapterLabel(
            const Chapter(
              title: '  Chapter 5 Pricing Book Values ',
              startPage: 164,
              endPage: 201,
            ),
            4,
          ),
          'Chapter 5 Pricing Book Values (s.164-201)',
        );
        expect(
          tutorChapterLabel(const Chapter(startPage: 1, endPage: 23), 0),
          'Chapter 1 (s.1-23)',
        );
        expect(
          tutorChapterLabel(
            const Chapter(title: '   ', startPage: 24, endPage: 40),
            2,
          ),
          'Chapter 3 (s.24-40)',
        );
      },
    );
  });
}
