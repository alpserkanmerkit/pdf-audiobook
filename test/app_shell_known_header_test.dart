// K4 (project report 5.2/K4): the PagePipeline that AppShell builds on the REAL path
// (pipelineFactory == null) was NOT given the running header. When adding a book
// (add_book_screen) the header is detected and stripped for the chapter map, but in
// the reading pipeline (AppShell -> PagePipeline.prepareText -> stripPageArtifacts)
// `knownHeader` always stayed null: in a real PDF the running header stayed in the
// text of every page and was read aloud. The existing AppShell tests inject a fake
// pipeline via pipelineFactory, so they never exercised this path.
//
// Test: a real (syncfusion-generated) PDF file + AppShell's own file-reading path;
// the prepareText of the pipeline built when the book is tapped (LLM key empty ->
// local stripped text) must NOT contain the running header.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/io/page_pipeline.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/src/voices.dart';
import 'package:sesli_kitap/ui/screens/reader_screen.dart';
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

const _settings = PipelineSettings(
  geminiKey: '',
  voice: SesliVoice.ahmet,
  rate: 1,
  provider: 'edge',
);

void main() {
  testWidgets(
    'K4: AppShell passes the running header to the pipeline for a real PDF -- '
    'prepareText output has NO running header, body text IS present',
    (tester) async {
      // Pages 2 and 4 (same parity) carry the same first line -> detectRunningHeader
      // returns 'KOSU BASLIGI SAHTE' (same pattern as page_pipeline_header_test).
      final bytes = _pdfWithPageLines([
        ['KAPAK SAYFASI'],
        ['KOSU BASLIGI SAHTE', 'Govde metni iki.'],
        ['KOSU BASLIGI SAHTE', 'Govde metni uc.'],
        ['KOSU BASLIGI SAHTE', 'Govde metni dort.'],
        ['KOSU BASLIGI SAHTE', 'Govde metni bes.'],
      ]);
      final dir = Directory.systemTemp.createTempSync('k4_known_header_');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {
          // temp dir cleanup is best-effort
        }
      });
      final pdf = File('${dir.path}/kitap.pdf')..writeAsBytesSync(bytes);
      final book = Book(
        id: 'k4-1',
        title: 'Kosu Basligi Kitabi',
        author: 'T. Test',
        chapterLabel: 'Bolum 1',
        progressPercent: 0,
        totalPages: 5,
        coverIndex: 0,
        hash: 'k4hash0000000001',
        filePath: pdf.path,
      );
      final services = await buildTestServices(
        prefsValues: {
          'books_v1': encodeBooks([book]),
        },
      );
      await tester.pumpWidget(buildTestAppFromServices(services));
      await tester.pumpAndSettle();

      await tester.tap(find.text(book.title).first);
      await tester.pump();

      // AppShell._buildPipelineAsync performs the REAL file read (the fake-async
      // pump does not advance it): wait REAL time until the pipeline is built.
      PagePipeline? pipeline;
      for (var i = 0; i < 200 && pipeline == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        final readers = find.byType(ReaderScreen);
        if (readers.evaluate().isNotEmpty) {
          pipeline = tester.widget<ReaderScreen>(readers).pipeline;
        }
      }
      expect(pipeline, isNotNull, reason: 'AppShell must build the pipeline');

      final entry = await tester.runAsync(
        () => pipeline!.prepareText(2, _settings),
      );

      expect(
        entry!.raw,
        isNot(contains('KOSU BASLIGI SAHTE')),
        reason:
            'if the running header stays in the page text it gets read aloud',
      );
      expect(entry.clean, isNot(contains('KOSU BASLIGI SAHTE')));
      expect(entry.raw, contains('Govde metni iki'));
    },
  );
}
