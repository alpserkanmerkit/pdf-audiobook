// Oracle test (PHASE 3 slice-2): chapter map — chapter list from running headers.
// Spec Phase 3: "Chapter map: derived from the running headers the regex recorded."
// (The running header is recorded as metadata BEFORE it is removed — spec §4 flow;
// stripPageArtifacts.strippedHeader is the source of this metadata, wiring maps it.)
//
// Contract decisions (oracle, 2026-06-12):
// - Input: PageHeaderEntry(page, header) list in page order; header
//   null/empty/whitespace-only = headerless page. Page numbers need not be
//   consecutive (a page may be skipped); start/end are the input values.
// - Title comparison is NORMALIZED: trim + lower-case + internal whitespace
//   runs collapsed to one space. The chapter's displayed title = the trimmed
//   ORIGINAL form from the FIRST page where it was seen (not the normalized form).
// - CONSECUTIVE same-normalized headers = ONE chapter (a repeated header does not
//   open a chapter).
// - A headerless page sticks to the current chapter (the running header is often
//   not printed on chapter-opening pages); headerless pages BEFORE the first header
//   become a title:null PRE-CHAPTER (the UI labels it, e.g. "Giriş" = "Introduction").
// - If the same header comes back AFTER an interval (A,B,A) it is a NEW chapter —
//   only consecutive runs are merged.
// - No cancel/order: the function is PURE; the returned list is UNMODIFIABLE
//   and does not mutate the input.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/chapter_map.dart';

PageHeaderEntry e(int page, [String? header]) =>
    PageHeaderEntry(page: page, header: header);

void main() {
  group('buildChapterMap — empty and single inputs', () {
    test('empty list → empty map', () {
      expect(buildChapterMap(const []), isEmpty);
    });

    test('single titled page → one chapter, start=end', () {
      final map = buildChapterMap([e(1, 'Birinci Kısım')]);
      expect(map, hasLength(1));
      expect(map[0].title, 'Birinci Kısım');
      expect(map[0].startPage, 1);
      expect(map[0].endPage, 1);
    });

    test('single headerless page → title:null pre-chapter', () {
      final map = buildChapterMap([e(1)]);
      expect(map, hasLength(1));
      expect(map[0].title, isNull);
      expect(map[0].startPage, 1);
      expect(map[0].endPage, 1);
    });
  });

  group('buildChapterMap — repeated header is one chapter', () {
    test('consecutive identical headers are merged', () {
      final map = buildChapterMap([
        e(1, 'İnsan'),
        e(2, 'İnsan'),
        e(3, 'İnsan'),
      ]);
      expect(map, hasLength(1));
      expect(map[0].title, 'İnsan');
      expect(map[0].startPage, 1);
      expect(map[0].endPage, 3);
    });

    test('normalized match: trim + case + internal whitespace collapse', () {
      final map = buildChapterMap([
        e(1, 'Sonuç  Bölümü'),
        e(2, '  sonuç bölümü '),
        e(3, 'SONUÇ BÖLÜMÜ'),
      ]);
      expect(map, hasLength(1));
      expect(map[0].title, 'Sonuç  Bölümü'); // first seen, trimmed original
      expect(map[0].endPage, 3);
    });

    test('new chapter when header changes; boundaries are adjacent', () {
      final map = buildChapterMap([
        e(1, 'Madde'),
        e(2, 'Madde'),
        e(3, 'Enerji'),
        e(4, 'Enerji'),
      ]);
      expect(map, hasLength(2));
      expect(map[0].title, 'Madde');
      expect(map[0].endPage, 2);
      expect(map[1].title, 'Enerji');
      expect(map[1].startPage, 3);
      expect(map[1].endPage, 4);
    });

    test('same header again after an interval → NEW chapter (A,B,A)', () {
      final map = buildChapterMap([e(1, 'Akıl'), e(2, 'Kalp'), e(3, 'Akıl')]);
      expect(map, hasLength(3));
      expect(map[0].title, 'Akıl');
      expect(map[1].title, 'Kalp');
      expect(map[2].title, 'Akıl');
      expect(map[2].startPage, 3);
    });
  });

  group('buildChapterMap — headerless page attachment', () {
    test(
      'headerless page in the middle of a chapter stays in that chapter',
      () {
        final map = buildChapterMap([e(1, 'Su'), e(2), e(3, 'Su')]);
        expect(map, hasLength(1));
        expect(map[0].endPage, 3);
      },
    );

    test(
      'trailing headerless pages attach to the last chapter (last edge)',
      () {
        final map = buildChapterMap([e(1, 'Veda'), e(2), e(3)]);
        expect(map, hasLength(1));
        expect(map[0].title, 'Veda');
        expect(map[0].endPage, 3);
      },
    );

    test(
      'a headerless page between DIFFERENT headers attaches to the NEXT chapter '
      '(the running header is not printed on chapter-opening pages; probe FAIL-1)',
      () {
        final map = buildChapterMap([
          e(1, 'Bir'),
          e(2, 'Bir'),
          e(3), // first headerless page of chapter 'İki'
          e(4, 'İki'),
          e(5, 'İki'),
        ]);
        expect(map, hasLength(2));
        expect(map[0].endPage, 2);
        expect(map[1].startPage, 3);
        expect(map[1].title, 'İki');
      },
    );

    test(
      'a multi-page headerless run between different headers also attaches forward',
      () {
        final map = buildChapterMap([e(1, 'Bir'), e(2), e(3), e(4, 'İki')]);
        expect(map, hasLength(2));
        expect(map[0].endPage, 1);
        expect(map[1].startPage, 2);
      },
    );

    test('empty and whitespace-only headers count as headerless', () {
      final map = buildChapterMap([e(1, 'Gök'), e(2, ''), e(3, '   ')]);
      expect(map, hasLength(1));
      expect(map[0].endPage, 3);
    });

    // S1 FIX (PHASE 4): this test used to pin a WRONG first-edge rule
    // (chapter 1's headerless opening page fell into the pre-chapter). New contract,
    // consistent with the inner edges: the LAST page of the headerless run before the
    // first header is chapter 1's headerless opening page (the running header is not
    // printed on chapter-opening pages — same reason as probe FAIL-1); the pre-chapter
    // = only the pages BEFORE chapter 1's real start.
    test(
      'headerless run before the first header: its last page attaches to '
      'chapter 1, the earlier pages become the pre-chapter (first edge, S1)',
      () {
        final map = buildChapterMap([e(1), e(2), e(3, 'Doğuş'), e(4, 'Doğuş')]);
        expect(map, hasLength(2));
        expect(map[0].title, isNull);
        expect(map[0].startPage, 1);
        expect(map[0].endPage, 1);
        expect(map[1].title, 'Doğuş');
        expect(map[1].startPage, 2);
        expect(map[1].endPage, 4);
      },
    );

    test(
      'a SINGLE headerless page before the first header: attaches to chapter 1, '
      'no pre-chapter (means chapter 1 starts on page 1)',
      () {
        final map = buildChapterMap([e(1), e(2, 'A'), e(3, 'A')]);
        expect(map, hasLength(1));
        expect(map[0].title, 'A');
        expect(map[0].startPage, 1);
        expect(map[0].endPage, 3);
      },
    );

    test(
      'probe scenario (S1): pre-chapter + two chapters with headerless opening pages — '
      'each chapter takes its own headerless first page',
      () {
        final map = buildChapterMap([
          e(1), e(2), // front matter
          e(3), // chapter 1's headerless opening page
          e(4, 'B1'), e(5, 'B1'),
          e(
            6,
          ), // chapter 2's headerless opening page (inner edge: attaches forward)
          e(7, 'B2'),
        ]);
        expect(map, hasLength(3));
        expect(map[0].title, isNull);
        expect(map[0].startPage, 1);
        expect(map[0].endPage, 2);
        expect(map[1].title, 'B1');
        expect(map[1].startPage, 3);
        expect(map[1].endPage, 5);
        expect(map[2].title, 'B2');
        expect(map[2].startPage, 6);
        expect(map[2].endPage, 7);
      },
    );

    test('all headerless → one pre-chapter', () {
      final map = buildChapterMap([e(5), e(6), e(7)]);
      expect(map, hasLength(1));
      expect(map[0].title, isNull);
      expect(map[0].startPage, 5);
      expect(map[0].endPage, 7);
    });
  });

  group('buildChapterMap — page number contract', () {
    test('start/end are the input page values (need not start at 1)', () {
      final map = buildChapterMap([e(41, 'Medium'), e(42, 'Medium')]);
      expect(map[0].startPage, 41);
      expect(map[0].endPage, 42);
    });

    test('a skipped page number does not split a chapter (gap tolerance)', () {
      final map = buildChapterMap([e(10, 'Dağ'), e(13, 'Dağ')]);
      expect(map, hasLength(1));
      expect(map[0].startPage, 10);
      expect(map[0].endPage, 13);
    });
  });

  group('buildChapterMap — purity and immutability', () {
    test('returned list is unmodifiable', () {
      final map = buildChapterMap([e(1, 'Tek')]);
      expect(
        () => map.add(const Chapter(title: 'x', startPage: 9, endPage: 9)),
        throwsUnsupportedError,
      );
    });

    test('input list is not mutated', () {
      final input = [e(1, 'Kök'), e(2)];
      final before = List.of(input);
      buildChapterMap(input);
      expect(input.length, before.length);
      expect(input[0].page, before[0].page);
      expect(input[0].header, before[0].header);
      expect(input[1].header, isNull);
    });

    test(
      'consecutive single-page different chapters (A,B) → two correct boundaries',
      () {
        final map = buildChapterMap([e(1, 'Bir'), e(2, 'İki')]);
        expect(map, hasLength(2));
        expect(map[0].startPage, 1);
        expect(map[0].endPage, 1);
        expect(map[1].startPage, 2);
        expect(map[1].endPage, 2);
      },
    );
  });
}
