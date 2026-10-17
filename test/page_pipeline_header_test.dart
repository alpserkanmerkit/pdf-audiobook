// Oracle test (FAZ 4, K16): detectRunningHeader — running-header heuristic.
// The input needs real PDF bytes; the fixture is produced INSIDE the test with syncfusion
// (drawString -> PdfTextExtractor round-trip runs in pure Dart, no device needed).
// K16 finding: NEIGHBOURING pages (2,3) have opposite parity; for books that print an alternating
// (even/odd different) running header, first lines never match. Fix contract: SAME-parity pages (2,4) are compared.
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/io/page_pipeline.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Produces a PDF where each inner list is the lines of one page (top to bottom).
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

void main() {
  test(
    'alternating running header (even/odd differ): captured from SAME-parity pages '
    '(K16 — neighbour-page comparison never matched)',
    () {
      final bytes = pdfWithPageLines([
        ['COVER PAGE'],
        ['2', 'LEFT HEADER', 'Body text two.'],
        ['3', 'RIGHT HEADER', 'Body text three.'],
        ['4', 'LEFT HEADER', 'Body text four.'],
        ['5', 'RIGHT HEADER', 'Body text five.'],
      ]);
      expect(
        PagePipeline.detectRunningHeader(bytes, 5),
        'LEFT HEADER', // pages 2 and 4 (same parity) match
      );
    },
  );

  test('same running header on every page: detected (pin)', () {
    final bytes = pdfWithPageLines([
      ['COVER PAGE'],
      ['SINGLE HEADER', 'Body two.'],
      ['SINGLE HEADER', 'Body three.'],
      ['SINGLE HEADER', 'Body four.'],
      ['SINGLE HEADER', 'Body five.'],
    ]);
    expect(PagePipeline.detectRunningHeader(bytes, 5), 'SINGLE HEADER');
  });

  test('book without a running header: null (pin)', () {
    final bytes = pdfWithPageLines([
      ['COVER PAGE'],
      ['First sentence two.', 'Continued.'],
      ['Different sentence three.', 'Continued.'],
      ['Another sentence four.', 'Continued.'],
      ['Again different five.', 'Continued.'],
    ]);
    expect(PagePipeline.detectRunningHeader(bytes, 5), isNull);
  });

  test(
    'book shorter than 4 pages: null (insufficient data for the heuristic, pin)',
    () {
      final bytes = pdfWithPageLines([
        ['SAME', 'Body.'],
        ['SAME', 'Body.'],
        ['SAME', 'Body.'],
      ]);
      expect(PagePipeline.detectRunningHeader(bytes, 3), isNull);
    },
  );
}
