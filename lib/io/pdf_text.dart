// PHASE 1 wiring: PDF text-layer extraction (syncfusion; spec §2).
// No gate test (binary PDF input needs a device/file context) -> manual acceptance.
import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Returns the raw text of the 1-based `pageNumber` page.
/// On a page with an empty text layer an empty string may be returned (Phase 1:
/// an error is shown to the user; the OCR fallback is Phase 2 work -- spec §7).
/// Total page count of the book (for the progress/prefetch limit).
int pdfPageCount(Uint8List pdfBytes) {
  final doc = PdfDocument(inputBytes: pdfBytes);
  try {
    return doc.pages.count;
  } finally {
    doc.dispose();
  }
}

String extractPageText(Uint8List pdfBytes, int pageNumber) {
  final doc = PdfDocument(inputBytes: pdfBytes);
  try {
    if (pageNumber < 1 || pageNumber > doc.pages.count) {
      throw RangeError(
        'Page $pageNumber is invalid (the book has ${doc.pages.count} pages).',
      );
    }
    return PdfTextExtractor(
      doc,
    ).extractText(startPageIndex: pageNumber - 1, endPageIndex: pageNumber - 1);
  } finally {
    doc.dispose();
  }
}

/// Extracts the raw text of all pages with a SINGLE PdfDocument opening.
/// DEVICE ANR FIX (2026-06-13): the old path called extractPageText 706 times
/// while building chapters, re-parsing the 24MB PDF EVERY time -> the main thread
/// locked for 5+ seconds on the phone = ANR (evidence: logcat "Input dispatching timed out").
/// Here the parse happens ONCE; a breath to the event loop every ~32 pages (UI does not freeze).
// (Code: spec-driven IO, 2026-06-13)
///
/// If [lastPage] is given only 1..[lastPage] are extracted (discussion source,
/// K2 2026-09-30: pages after the reader's page are never parsed).
Future<List<String>> extractAllPageTexts(
  Uint8List pdfBytes, {
  void Function(int done, int total)? onProgress,
  int? lastPage,
}) async {
  final doc = PdfDocument(inputBytes: pdfBytes);
  try {
    final count = doc.pages.count;
    final total = lastPage == null || lastPage > count ? count : lastPage;
    final extractor = PdfTextExtractor(doc);
    final texts = <String>[];
    for (var i = 0; i < total; i++) {
      final text = extractor.extractText(startPageIndex: i, endPageIndex: i);
      texts.add(text);
      if ((i + 1) % 32 == 0) {
        await Future<void>.delayed(Duration.zero);
        onProgress?.call(i + 1, total);
      }
    }
    return texts;
  } finally {
    doc.dispose();
  }
}
