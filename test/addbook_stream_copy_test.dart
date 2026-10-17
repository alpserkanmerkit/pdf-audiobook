// Bug-D RED test (2026-07-04 — 185MB PDF import Java-heap OOM).
// Live evidence: on Android, file_picker withData:true reads the whole file into
// ONE Java ByteArray(size) (see file_picker package FileUtils.kt loadData()).
// For a 185MB PDF that single array grew the Java heap by ~402MB and crashed the
// app with OutOfMemoryError (FAZ-3 live crash, 15:34).
//
// Fix direction: pickPdf must now be able to return ONLY a path (PickedBook.path)
// (withData:false), and the add-book flow must move the large file to its target
// without loading it into memory in one piece (synchronous chunk-by-chunk copy with
// RandomAccessFile; see lib/ui/screens/add_book_screen.dart _copyWithChunkedHash).
// This test checks the SEAM: the fake picker returns a DISK PATH, the source file is
// copied chunk by chunk through the real file system (temp dir), source and target
// content must be bit-for-bit identical, AND PickedBook must now support path-based
// selection (bytes are not mandatory).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'helpers/test_app.dart';

Uint8List _pdfWithPageLines(List<List<String>> pages) {
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

/// Opens the "Add book" (add book) screen from the Library tab, taps "Choose file"
/// (choose file) and pumps while the async pipeline runs (same pattern as
/// addbook_wiring_test.dart -- see the comments there for the two known flutter-test
/// pitfalls, handled with runAsync + periodic pump).
///
/// If [done] is given (positive flow: was the book written to prefs?), once the
/// condition holds it waits 5 more rounds (for trailing writes/redraws) and exits,
/// instead of a fixed 1 sec wait. If the condition is never met, it still exits
/// after 20 rounds and the test's own assert fails. Negative flows (no [done])
/// always wait the full 20 rounds, to prove that nothing happens.
Future<void> _openAddBookAndPick(
  WidgetTester tester, {
  bool Function()? done,
}) async {
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('Add book').first);
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('Choose file').first);
  var extra = -1;
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (done != null) {
      if (extra < 0 && done()) extra = 0;
      if (extra >= 0 && ++extra > 5) break;
    }
  }
}

void main() {
  group('Bug-D RED: PickedBook path-based selection + streamed copy', () {
    testWidgets(
      'PickedBook.path selection -> disk copy is bit-identical to the source; '
      'persistence (hash/pages) works the same way as the bytes path',
      (tester) async {
        final bytes = _pdfWithPageLines([
          ['Bölüm Bir', 'Gövde metni bir.'],
          ['Bölüm Bir', 'Gövde metni iki.'],
          ['Bölüm İki', 'Gövde metni üç.'],
        ]);

        // Fake picker writes a REAL temp file and returns ONLY its path
        // (same shape as file_picker withData:false -- bytes never reach Dart,
        // only the path is passed).
        final srcDir = Directory.systemTemp.createTempSync(
          'sesli_kitap_addbook_stream_src_',
        );
        addTearDown(() {
          try {
            srcDir.deleteSync(recursive: true);
          } on FileSystemException {
            // best-effort
          }
        });
        final srcFile = File('${srcDir.path}/buyuk_kitap.pdf')
          ..writeAsBytesSync(bytes);

        final expectedHash = sha256.convert(bytes).toString().substring(0, 16);

        final services = await buildTestServices(
          pickPdf: () async =>
              PickedBook(name: 'buyuk_kitap.pdf', path: srcFile.path),
        );

        await tester.pumpWidget(buildTestAppFromServices(services));
        await _openAddBookAndPick(
          tester,
          done: () => services.prefs.getString('books_v1') != null,
        );

        expect(
          tester.takeException(),
          isNull,
          reason: 'path-based PickedBook must be processed without crashing',
        );

        final raw = services.prefs.getString('books_v1');
        expect(
          raw,
          isNotNull,
          reason:
              'books_v1 must be written for path-based selection too (the '
              'SAME behavior as the bytes path)',
        );
        final books = decodeBooks(raw!);
        expect(books, hasLength(1));
        expect(books.single.hash, expectedHash);
        expect(books.single.totalPages, 3);

        // Target file: must be copied chunk by chunk into app storage --
        // bit-for-bit identical to the source (this is also the outcome when a
        // chunked RandomAccessFile copy is used INSTEAD of a single-piece readAsBytes).
        final destFile = File(
          '${services.dataDir.path}/books/$expectedHash.pdf',
        );
        expect(
          destFile.existsSync(),
          isTrue,
          reason: 'PDF must be copied chunk by chunk to the target location',
        );
        expect(destFile.lengthSync(), srcFile.lengthSync());
        expect(destFile.readAsBytesSync(), bytes);
      },
    );
  });
}
