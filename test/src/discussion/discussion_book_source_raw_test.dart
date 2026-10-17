// Oracle RED test (2026-09-30, user spec "closed box" discussion).
//
// Field measurement (phone, logcat 09-30 13:5x): in a discussion started with a book chip,
// `discussion book text: s.1-13, 4 pages, 1910 chars` -- only the 4 pages that had CLEAN cached
// text (1, 2, 4, 13; the last one ~300 kr, the cover) went through; the 9 unprepared pages
// were silently skipped (B1). ("kr" = characters.)
//
// Oracle decision K2: when there is no clean cache, the RAW text layer of the PDF is used
// (no LLM cleaning / no OCR, no cost). A page with no raw text either (image) is skipped and
// COUNTED. The diagnostic line reports the clean/raw/skipped counts.
// Oracle decision K3: the closed-box rule is defined in ONE constant.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/discussion/discussion_book_source.dart';

Future<String?> Function(int) _reader(Map<int, String> pages) =>
    (p) async => pages[p];

void main() {
  group('K2 -- raw text fallback when there is no clean cache', () {
    test('uses clean text if present, otherwise raw text; a page with neither '
        'is skipped and counted; a page AHEAD is NEVER read', () async {
      final src = await gatherDiscussionSource(
        currentPage: 4,
        readPage: _reader({1: 'Clean one.', 3: 'Clean three.'}),
        readRawPage: _reader({
          1: 'RAW ONE -- should not be used when clean text exists',
          2: 'Raw two.',
          3: 'RAW THREE -- should not be used when clean text exists',
          5: 'PAGE AHEAD -- the reader never got here',
        }),
      );

      expect(src, isNotNull);
      expect(src!.text, 'Clean one.\n\nRaw two.\n\nClean three.');
      expect(src.fromPage, 1);
      expect(src.toPage, 3);
      expect(src.pageCount, 3);
      expect(src.cleanPageCount, 2);
      expect(src.rawPageCount, 1);
      expect(src.skippedPageCount, 1, reason: 'p.4 is neither clean nor raw');
    });

    test(
      'the raw reader is called ONLY for pages that have no clean text',
      () async {
        final rawCalls = <int>[];
        await gatherDiscussionSource(
          currentPage: 3,
          readPage: _reader({2: 'Clean two.'}),
          readRawPage: (p) async {
            rawCalls.add(p);
            return 'raw $p';
          },
        );
        expect(rawCalls, [1, 3]);
      },
    );

    test(
      'raw text made of whitespace only does not count as text (skipped)',
      () async {
        final src = await gatherDiscussionSource(
          currentPage: 2,
          readPage: _reader({}),
          readRawPage: _reader({1: '  \n\t ', 2: 'Raw two.'}),
        );
        expect(src!.text, 'Raw two.');
        expect(src.fromPage, 2);
        expect(src.rawPageCount, 1);
        expect(src.cleanPageCount, 0);
        expect(
          src.skippedPageCount,
          1,
          reason:
              'no trimming: every empty page in the range 1..reader page is counted',
        );
      },
    );

    test(
      'without a raw reader, only clean text; empty pages are counted',
      () async {
        final src = await gatherDiscussionSource(
          currentPage: 3,
          readPage: _reader({2: 'Clean two.'}),
        );
        expect(src!.text, 'Clean two.');
        expect(src.cleanPageCount, 1);
        expect(src.rawPageCount, 0);
        expect(src.skippedPageCount, 2, reason: 'p.1 and p.3 are empty');
      },
    );

    test(
      'returns null when there is no text at all (neither clean nor raw)',
      () async {
        final src = await gatherDiscussionSource(
          currentPage: 2,
          readPage: _reader({}),
          readRawPage: _reader({}),
        );
        expect(src, isNull);
      },
    );

    test('counts after trimming are based on the REMAINING range', () async {
      // p.1 clean (will be trimmed), p.2 empty, p.3 raw, p.4 clean, p.5 empty.
      final src = await gatherDiscussionSource(
        currentPage: 5,
        readPage: _reader({1: 'aaaa aaaa', 4: 'dddd'}),
        readRawPage: _reader({3: 'cccc'}),
        maxChars: 10,
      );
      expect(src!.text, 'cccc\n\ndddd');
      expect(src.fromPage, 3);
      expect(src.toPage, 4);
      expect(src.pageCount, 2);
      expect(src.cleanPageCount, 1);
      expect(src.rawPageCount, 1);
      expect(
        src.skippedPageCount,
        1,
        reason:
            'p.2 is in the trimmed part (not counted), p.5 is in the remaining range (counted)',
      );
      expect(src.trimmedChars, greaterThan(0));
    });
  });

  group('K2 -- diagnostic line', () {
    test('clean/raw/skipped counts and character count', () {
      const src = DiscussionBookSource(
        fromPage: 1,
        toPage: 13,
        text: 'abc',
        pageCount: 12,
        cleanPageCount: 4,
        rawPageCount: 8,
        skippedPageCount: 1,
      );
      expect(
        describeDiscussionSource(src),
        'discussion book text: s.1-13, 12 pages '
        '(clean 4, raw 8, skipped 1), 3 chars',
      );
    });

    test('trimming is appended to the line when present', () {
      const src = DiscussionBookSource(
        fromPage: 5,
        toPage: 9,
        text: 'abcd',
        pageCount: 5,
        cleanPageCount: 5,
        trimmedChars: 42,
      );
      expect(
        describeDiscussionSource(src),
        'discussion book text: s.5-9, 5 pages '
        '(clean 5, raw 0, skipped 0), 4 chars, trimmed 42 chars from the start',
      );
    });
  });

  group('K3 -- closed-box rule (single constant)', () {
    test(
      'rule: only book text; no invented examples, people or events outside the text; '
      'if the text is not enough, "kitapta bu geçmiyor"',
      () {
        expect(kClosedBoxRule, contains('CLOSED BOX'));
        expect(kClosedBoxRule, contains('ONLY'));
        expect(kClosedBoxRule, contains('TEXT FROM THE BOOK'));
        expect(kClosedBoxRule, contains('Do NOT invent'));
        expect(kClosedBoxRule, contains('kitapta bu geçmiyor'));
        expect(kClosedBoxRule, contains('Listener questions'));
      },
    );
  });
}
