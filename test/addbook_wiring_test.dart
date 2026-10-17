// Slice-10 + FAZ-W2 WIRING test (§13.7 — oracle). Is the add-book flow REAL:
// "Choose file" -> AppServices.pickPdf() (injectable fake) -> sha256 ->
// page count -> running header -> chapter skeleton (buildChapterMap fallback
// when there is no LLM) -> persistence (dataDir/books/<hash>.pdf + prefs books_v1 + chapters_<hash>).
// The fixture PDF is generated INSIDE the test with syncfusion (FAZ4 pattern,
// test/page_pipeline_header_test.dart) — no device or file-system input is needed.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart' show Key;
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/chapter_cache.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'helpers/pump_fast.dart';
import 'helpers/test_app.dart';

/// Generates a PDF where each inner list holds the lines of one page (top to bottom)
/// (identical to the FAZ4 pattern in test/page_pipeline_header_test.dart).
Uint8List pdfWithPageLines(List<List<String>> pages) {
  final doc = PdfDocument();
  final font = PdfStandardFont(PdfFontFamily.helvetica, 12);
  for (final lines in pages) {
    final page = doc.pages.add();
    var y = 0.0;
    for (final line in lines) {
      page.graphics.drawString(
        line,
        font,
        bounds: Rect.fromLTWH(0, y, 400, 16),
      );
      y += 24;
    }
  }
  final bytes = Uint8List.fromList(doc.saveSync());
  doc.dispose();
  return bytes;
}

/// A real 3-page PDF fixture (the running header is not asserted in this slice --
/// only the page count, the hash and the chapter-skeleton fallback are tested).
Uint8List threePagePdf() => pdfWithPageLines([
  ['Bölüm Bir', 'Gövde metni bir.'],
  ['Bölüm Bir', 'Gövde metni iki.'],
  ['Bölüm İki', 'Gövde metni üç.'],
]);

/// Taps "Choose file" and pumps while the async pipeline completes
/// (the common final step for t1-t6).
///
/// TWO KNOWN flutter-test pitfalls come together here:
/// 1) The "processing" phase may show an indeterminate CircularProgressIndicator.
///    It keeps scheduling new frames, so pumpAndSettle() NEVER settles
///    (hasScheduledFrame is always true).
/// 2) The pipeline does REAL dart:io file-write I/O (File.writeAsBytes).
///    That work is dispatched to the OS / a background thread, and the completion
///    signal may NOT be triggered by tester.pump() alone (verified: the OS write
///    really finishes, but the pump loop ran out before the Future resolved).
///    flutter_test provides WidgetTester.runAsync for exactly this ("real async
///    work: for methods dispatched to isolates or OS threads" — official docs).
/// Solution: run the whole duration inside runAsync, refreshing the widget tree
/// with pump() at intervals (pump CANNOT be called DURING runAsync, so the outer
/// loop calls runAsync and pump back to back).
///
/// One round = 10 ms of real waiting + pump (speed-up 4: previously 50 ms; the same
/// 1 sec upper bound = 100 rounds). Once [done] holds, [graceRounds] more rounds are
/// waited and the loop exits. [done] is passed on EVERY call (no fixed 1 sec wait):
/// - positive flow: book written to prefs / Ready phase visible; a short grace
///   (3 rounds = 30 ms) for trailing writes and redraws.
/// - negative flows (t4: "pickPdf called", t5: "error phase visible"): the
///   "nothing else happened" claim gets the OLD time budget (25 rounds = 250 ms,
///   previously 5 x 50 ms) through the long grace ([graceRounds] = 25).
/// If the condition is never met, the loop still exits after 100 rounds and the
/// test's own assert fails.
Future<void> _pickAndWait(
  WidgetTester tester, {
  required bool Function() done,
  int graceRounds = 3,
}) async {
  await tester.tap(find.textContaining('Choose file').first);
  var extra = -1;
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (extra < 0 && done()) extra = 0;
    if (extra >= 0 && ++extra > graceRounds) break;
  }
}

/// Opens the "Add book" screen from the Library tab, runs [onIdle] (if given; e.g.
/// language selection), then [_pickAndWait] (the common pre-step for t1-t6).
Future<void> _openAddBookAndPick(
  WidgetTester tester, {
  required bool Function() done,
  int graceRounds = 3,
  Future<void> Function()? onIdle,
}) async {
  await pumpFast(tester);
  await tester.tap(find.textContaining('Add book').first);
  await pumpFast(tester);
  if (onIdle != null) await onIdle();
  await _pickAndWait(tester, done: done, graceRounds: graceRounds);
}

bool _addDoneVisible() =>
    find.textContaining('Start reading').evaluate().isNotEmpty;

void main() {
  testWidgets('Library "Add book" -> add-book screen idle state', (
    tester,
  ) async {
    await tester.pumpWidget(await buildTestApp());
    await pumpFast(tester);
    await tester.tap(find.textContaining('Add book').first);
    await pumpFast(tester);
    expect(
      find.textContaining('Drop your PDF here'),
      findsWidgets,
    ); // UI hint: "Drop your PDF here"
    expect(find.textContaining('Choose file'), findsWidgets);
  });

  group('W2: add-book flow (pick -> hash -> pages -> chapters -> persistence)', () {
    testWidgets(
      't1: fixture PDF is picked -> processed -> reaches the Ready phase, file name is shown',
      (tester) async {
        final bytes = threePagePdf();
        await tester.pumpWidget(
          await buildTestApp(
            pickPdf: () async =>
                PickedBook(name: 'test_kitabi.pdf', bytes: bytes),
          ),
        );
        await _openAddBookAndPick(tester, done: _addDoneVisible);

        expect(
          find.textContaining('Ready'),
          findsWidgets,
          reason:
              'must reach the Ready phase (the file name is already visible '
              'during processing too; the real proof is Ready)',
        );
        expect(
          find.textContaining('test_kitabi'),
          findsWidgets,
          reason: 'the Ready phase must show the selected file name/title',
        );
      },
    );

    testWidgets(
      't2: persistence — books_v1 holds one book with the correct hash/pages/progress; file is on disk',
      (tester) async {
        final bytes = threePagePdf();
        final expectedHash = sha256.convert(bytes).toString().substring(0, 16);

        final services = await buildTestServices(
          pickPdf: () async =>
              PickedBook(name: 'test_kitabi.pdf', bytes: bytes),
        );

        await tester.pumpWidget(buildTestAppFromServices(services));
        await _openAddBookAndPick(
          tester,
          done: () => services.prefs.getString('books_v1') != null,
        );

        final raw = services.prefs.getString('books_v1');
        expect(raw, isNotNull, reason: 'books_v1 prefs key must be written');
        final books = decodeBooks(raw!);
        expect(books, hasLength(1));
        final book = books.single;
        expect(book.hash, expectedHash);
        expect(book.totalPages, 3);
        expect(book.progressPercent, 0);

        final file = File('${services.dataDir.path}/books/$expectedHash.pdf');
        expect(
          file.existsSync(),
          isTrue,
          reason: 'PDF must be copied to the file',
        );
        expect(file.readAsBytesSync(), bytes);
      },
    );

    testWidgets(
      'Phase 2: if no language is chosen, the default "tr" is saved (backward compatibility)',
      (tester) async {
        final bytes = threePagePdf();
        final services = await buildTestServices(
          pickPdf: () async =>
              PickedBook(name: 'test_kitabi.pdf', bytes: bytes),
        );
        await tester.pumpWidget(buildTestAppFromServices(services));
        await _openAddBookAndPick(
          tester,
          done: () => services.prefs.getString('books_v1') != null,
        );

        final books = decodeBooks(services.prefs.getString('books_v1')!);
        expect(books.single.language, 'tr');
      },
    );

    testWidgets(
      'Phase 2: if "English" (English) is chosen, the saved book carries language="en"',
      (tester) async {
        final bytes = threePagePdf();
        final services = await buildTestServices(
          pickPdf: () async =>
              PickedBook(name: 'test_kitabi.pdf', bytes: bytes),
        );
        await tester.pumpWidget(buildTestAppFromServices(services));

        await _openAddBookAndPick(
          tester,
          onIdle: () async {
            await tester.tap(find.text('English'));
            await pumpFast(tester);
          },
          done: () => services.prefs.getString('books_v1') != null,
        );

        final books = decodeBooks(services.prefs.getString('books_v1')!);
        expect(books.single.language, 'en');
      },
    );

    testWidgets(
      't3: chapters_<hash> prefs is written and reads back cleanly with the chapter_cache decoder',
      (tester) async {
        final bytes = threePagePdf();
        final expectedHash = sha256.convert(bytes).toString().substring(0, 16);

        final services = await buildTestServices(
          pickPdf: () async =>
              PickedBook(name: 'test_kitabi.pdf', bytes: bytes),
        );

        await tester.pumpWidget(buildTestAppFromServices(services));
        await _openAddBookAndPick(
          tester,
          done: () => services.prefs.getString('books_v1') != null,
        );

        final rawChapters = services.prefs.getString('chapters_$expectedHash');
        expect(
          rawChapters,
          isNotNull,
          reason: 'chapters_<hash> prefs key must be written',
        );
        // decodeChapters must complete without throwing (round-trip contract).
        expect(() => decodeChapters(rawChapters!), returnsNormally);
      },
    );

    testWidgets(
      't4: user cancels (null result) -> stays in the idle phase, books_v1 is not written',
      (tester) async {
        var pickCalls = 0;
        final services = await buildTestServices(
          pickPdf: () async {
            pickCalls++;
            return null;
          },
        );

        await tester.pumpWidget(buildTestAppFromServices(services));
        await _openAddBookAndPick(
          tester,
          done: () => pickCalls > 0,
          graceRounds: 25,
        );

        expect(pickCalls, 1, reason: 'file picker must be called exactly once');

        // Proof of staying in the idle phase: "Choose file" is still visible, "Ready" is not.
        expect(find.textContaining('Choose file'), findsWidgets);
        expect(find.textContaining('Ready'), findsNothing);
        expect(services.prefs.getString('books_v1'), isNull);
      },
    );

    testWidgets(
      't5: invalid PDF bytes -> error phase, no crash, prefs unchanged',
      (tester) async {
        final garbage = Uint8List.fromList(
          utf8.encode('bu bir PDF degil, sadece duz metin'),
        );
        final services = await buildTestServices(
          pickPdf: () async => PickedBook(name: 'bozuk.pdf', bytes: garbage),
        );

        await tester.pumpWidget(buildTestAppFromServices(services));
        await _openAddBookAndPick(
          tester,
          done: () => find
              .textContaining('An error occurred while adding the book')
              .evaluate()
              .isNotEmpty,
          graceRounds: 25,
        );

        // Error phase is VISIBLE (AddPhase.error, add_book_screen.dart).
        expect(
          find.textContaining('An error occurred while adding the book'),
          findsOneWidget,
        );
        // pumpAndSettle must complete NORMALLY: no exception may escape.
        expect(tester.takeException(), isNull);
        expect(services.prefs.getString('books_v1'), isNull);
      },
    );

    testWidgets('t6: "Start reading" -> goes straight to the Reader tab AND '
        'the new book is visible when returning to the Library (field report: the book '
        'was saved correctly, but after returning to the Library the screen kept showing "No books yet" '
        'until the user switched tabs and came back)', (tester) async {
      final bytes = threePagePdf();
      await tester.pumpWidget(
        await buildTestApp(
          pickPdf: () async =>
              PickedBook(name: 'test_kitabi.pdf', bytes: bytes),
        ),
      );
      await _openAddBookAndPick(tester, done: _addDoneVisible);

      await tester.tap(find.textContaining('Start reading').first);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('tab-reader')),
        findsOneWidget,
        reason: '"Start reading" must open the reader directly',
      );
      expect(
        find.text('test_kitabi'),
        findsWidgets,
        reason: 'the reader must show the title of the newly added book',
      );

      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No books yet'),
        findsNothing,
        reason:
            'the library must NOT show the empty state anymore (a book is saved)',
      );
      expect(find.text('test_kitabi'), findsWidgets);
    });
  });
}
