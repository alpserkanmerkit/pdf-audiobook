// Slice-2b WIRING test (§13.7 — oracle). Is the library screen wired to the app_shell library tab,
// and are the book list and "Add book" ("Add book") reachable? (antidote to unit-green != wired)
//
// FAZ-W3 (library -> reader transition): real books_v1 books must show up in the library, and a single
// corrupt record must not drop the whole list (regression pin for the FAZ2c decodeBooks hardening -- here
// it really exercises that code path (per-record try/catch)).
//
// Field report (02.07.2026): a user who added a real PDF still saw fake demo books in the library --
// the seedBooks() fallback was REMOVED (t2 now proves the empty-state message, NOT demo titles).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sesli_kitap/src/library/library_store.dart';

import 'helpers/pump_fast.dart';
import 'helpers/test_app.dart';

/// W3 fixed fixtures: two real books whose titles do NOT clash with seedBooks() titles
/// (t1/t3 clearly prove "a real book is shown, not the seed").
const _kW3BookOne = Book(
  id: 'w3-1',
  title: 'Notebook of the Wind',
  author: 'N. Aksoy',
  chapterLabel: 'Chapter 1',
  progressPercent: 10,
  totalPages: 120,
  coverIndex: 0,
  hash: 'w3hash0001111111',
  filePath: '/tmp/w3/w3hash0001111111.pdf',
);

const _kW3BookTwo = Book(
  id: 'w3-2',
  title: 'Map of the Lost City',
  author: 'F. Erol',
  chapterLabel: 'Chapter 3',
  progressPercent: 55,
  totalPages: 200,
  coverIndex: 1,
  hash: 'w3hash0002222222',
  filePath: '/tmp/w3/w3hash0002222222.pdf',
);

void main() {
  testWidgets('Library tab shows the title + real book + add button', (
    tester,
  ) async {
    final services = await buildTestServices(
      prefsValues: {
        'books_v1': encodeBooks([_kW3BookOne]),
      },
    );
    await tester.pumpWidget(buildTestAppFromServices(services));
    await pumpFast(tester);

    // Library is the default active tab.
    expect(find.text('Your library'), findsOneWidget);
    expect(find.text(_kW3BookOne.title), findsWidgets);
    // "Add book" ("Add book") pill is reachable.
    expect(find.textContaining('Add book'), findsWidgets);
  });

  group('FAZ-W3: library is fed by real books_v1 data', () {
    testWidgets('t1: if books_v1 has 2 valid real books -> they are shown, '
        'seedBooks() demo titles are NOT shown', (tester) async {
      final raw = encodeBooks([_kW3BookOne, _kW3BookTwo]);
      final services = await buildTestServices(prefsValues: {'books_v1': raw});
      await tester.pumpWidget(buildTestAppFromServices(services));
      await pumpFast(tester);

      expect(find.text(_kW3BookOne.title), findsWidgets);
      expect(find.text(_kW3BookTwo.title), findsWidgets);
      // The demo/seed title must never appear (no fallback to the seed when real data exists).
      expect(find.text('Sessizliğin Mimarisi'), findsNothing);
    });

    testWidgets(
      't2: books_v1 missing/empty -> NOT fake demo books, but the explicit empty-state '
      'message is shown (field report: a real user must not see fake books)',
      (tester) async {
        await tester.pumpWidget(await buildTestApp());
        await pumpFast(tester);

        expect(tester.takeException(), isNull);
        expect(
          find.text('Sessizliğin Mimarisi'),
          findsNothing,
          reason: 'the old fake demo book title must NOT appear anymore',
        );
        expect(find.textContaining('No books yet'), findsWidgets);
      },
    );

    testWidgets(
      't7: books_v1 has 1 corrupt + 1 valid record -> only the valid one '
      'is shown, no crash (FAZ2c decodeBooks per-record tolerance regression pin)',
      (tester) async {
        final entries = <Object?>[
          _kW3BookOne.toJson(),
          <String, Object?>{
            'id': 'bozuk-w3',
            'title': 'Corrupt W3 Record',
            'author': 'X',
            'chapterLabel': 'B1',
            'progressPercent': 'kirk', // not an int -> decodeBooks skips it
            'totalPages': 100,
            'coverIndex': 0,
          },
        ];
        final raw = jsonEncode(entries);
        final services = await buildTestServices(
          prefsValues: {'books_v1': raw},
        );
        await tester.pumpWidget(buildTestAppFromServices(services));
        await pumpFast(tester);

        expect(tester.takeException(), isNull);
        expect(find.text(_kW3BookOne.title), findsWidgets);
        expect(find.text('Corrupt W3 Record'), findsNothing);
      },
    );
  });

  group('book deletion (long-press -> confirm -> remove)', () {
    testWidgets(
      'long-press + Delete confirm: the book is removed from both prefs and disk',
      (tester) async {
        final services = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks([_kW3BookOne]),
          },
        );
        // Create a real file (services.dataDir is the test's own temp dir) --
        // to prove the delete flow also cleans up the disk, as it does in the field.
        final file = File('${services.dataDir.path}/${_kW3BookTwo.hash}.pdf')
          ..writeAsStringSync('fake-pdf-content');
        final bookWithRealFile = Book(
          id: _kW3BookTwo.id,
          title: _kW3BookTwo.title,
          author: _kW3BookTwo.author,
          chapterLabel: _kW3BookTwo.chapterLabel,
          progressPercent: _kW3BookTwo.progressPercent,
          totalPages: _kW3BookTwo.totalPages,
          coverIndex: _kW3BookTwo.coverIndex,
          hash: _kW3BookTwo.hash,
          filePath: file.path,
        );
        await services.prefs.setString(
          'books_v1',
          encodeBooks([_kW3BookOne, bookWithRealFile]),
        );
        await services.prefs.setString(
          'chapters_${_kW3BookTwo.hash}',
          'fake-chapter-map',
        );
        await tester.pumpWidget(buildTestAppFromServices(services));
        await pumpFast(tester);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'precondition: the file exists',
        );

        // _kW3BookTwo is second -> only visible on the shelf (the continue card shows the first one),
        // so the finder stays unique. ensureVisible: on the default 800x600 test surface the grid
        // overflows to a second row, so pre-scrolling is required.
        await tester.ensureVisible(find.text(_kW3BookTwo.title));
        await pumpFast(tester);
        await tester.longPress(find.text(_kW3BookTwo.title));
        await pumpFast(tester);
        expect(find.text('Delete book?'), findsOneWidget);

        await tester.tap(find.byKey(const Key('confirm-delete-book')));
        await pumpFast(tester);

        expect(find.text(_kW3BookTwo.title), findsNothing);
        expect(find.text(_kW3BookOne.title), findsWidgets);
        final remaining = decodeBooks(services.prefs.getString('books_v1')!);
        expect(remaining.map((b) => b.id).toList(), [_kW3BookOne.id]);
        expect(
          file.existsSync(),
          isFalse,
          reason: 'the owned copy on disk must also be deleted',
        );
        expect(
          services.prefs.getString('chapters_${_kW3BookTwo.hash}'),
          isNull,
          reason: 'the chapter-map cache must also be cleared',
        );
      },
    );

    testWidgets('long-press + Cancel: book is NOT deleted', (tester) async {
      final services = await buildTestServices(
        prefsValues: {
          'books_v1': encodeBooks([_kW3BookOne, _kW3BookTwo]),
        },
      );
      await tester.pumpWidget(buildTestAppFromServices(services));
      await pumpFast(tester);

      await tester.ensureVisible(find.text(_kW3BookTwo.title));
      await pumpFast(tester);
      await tester.longPress(find.text(_kW3BookTwo.title));
      await pumpFast(tester);
      await tester.tap(find.text('Cancel'));
      await pumpFast(tester);

      expect(find.text(_kW3BookTwo.title), findsWidgets);
      final remaining = decodeBooks(services.prefs.getString('books_v1')!);
      expect(remaining, hasLength(2));
    });

    testWidgets(
      'if the book currently open in the Reader is deleted, the Reader does NOT '
      'stay attached to old content (review-finding-1: ghost session)',
      (tester) async {
        final services = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks([_kW3BookOne, _kW3BookTwo]),
          },
        );
        await tester.pumpWidget(buildTestAppFromServices(services));
        await pumpFast(tester);

        // Open _kW3BookTwo (unique finder on the shelf) -> switches to the Reader.
        await tester.ensureVisible(find.text(_kW3BookTwo.title));
        await pumpFast(tester);
        await tester.tap(find.text(_kW3BookTwo.title));
        await pumpFast(tester);
        expect(find.byKey(const Key('tab-reader')), findsOneWidget);

        // Go back to the library (leaving already stops audio; _openBook REMAINS).
        await tester.tap(find.text('Library'));
        await pumpFast(tester);

        // Delete the same book, which is still open.
        await tester.ensureVisible(find.text(_kW3BookTwo.title));
        await pumpFast(tester);
        await tester.longPress(find.text(_kW3BookTwo.title));
        await pumpFast(tester);
        await tester.tap(find.byKey(const Key('confirm-delete-book')));
        await pumpFast(tester);

        // Back to the Reader tab -- the deleted book's ghost must NOT remain.
        await tester.tap(find.text('Reader'));
        await pumpFast(tester);

        expect(
          find.textContaining('No book is open yet'),
          findsWidgets,
          reason:
              '_openBook must be cleared; must not keep working with the deleted book '
              '(including quiz/tts generation)',
        );
      },
    );

    testWidgets(
      'SAME hash shared across two different cards: deleting one does NOT affect the OTHER '
      'or the SHARED file (review-finding-2)',
      (tester) async {
        final services = await buildTestServices();
        final file = File('${services.dataDir.path}/ortak-hash.pdf')
          ..writeAsStringSync('shared-content');
        final dup1 = Book(
          id: 'ortak-hash',
          title: 'First Card',
          author: '',
          chapterLabel: '',
          progressPercent: 0,
          totalPages: 5,
          coverIndex: 0,
          hash: 'ortak-hash',
          filePath: file.path,
        );
        final dup2 = Book(
          id: 'ortak-hash',
          title: 'Second Card',
          author: '',
          chapterLabel: '',
          progressPercent: 0,
          totalPages: 5,
          coverIndex: 1,
          hash: 'ortak-hash',
          filePath: file.path,
        );
        await services.prefs.setString('books_v1', encodeBooks([dup1, dup2]));
        await tester.pumpWidget(buildTestAppFromServices(services));
        await pumpFast(tester);

        // dup2 is second -> unique finder on the shelf.
        await tester.ensureVisible(find.text('Second Card'));
        await pumpFast(tester);
        await tester.longPress(find.text('Second Card'));
        await pumpFast(tester);
        await tester.tap(find.byKey(const Key('confirm-delete-book')));
        await pumpFast(tester);

        expect(find.text('Second Card'), findsNothing);
        expect(
          find.text('First Card'),
          findsWidgets,
          reason: 'the other record sharing the id/hash must SURVIVE',
        );
        final remaining = decodeBooks(services.prefs.getString('books_v1')!);
        expect(remaining, hasLength(1));
        expect(remaining.single.title, 'First Card');
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'the other record is STILL using this file -- it must not be deleted',
        );
      },
    );
  });
}
