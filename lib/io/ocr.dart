// PHASE 2 wiring: OCR fallback (spec §3) — for pages whose text layer is EMPTY.
// pdfx renders the page to an image, ML Kit recognizes it on the device (spec §2; no network).
// No gate test (device/native context) -> manual acceptance class.
import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

Future<String> ocrPdfPage(Uint8List pdfBytes, int pageNumber) async {
  if (!Platform.isAndroid) return ''; // OCR is Android-only (google_mlkit)
  final doc = await PdfDocument.openData(pdfBytes);
  try {
    final page = await doc.getPage(pageNumber);
    final image = await page.render(
      width: page.width * 2,
      height: page.height * 2,
      format: PdfPageImageFormat.png,
    );
    await page.close();
    if (image == null) {
      throw StateError(
        'Page $pageNumber could not be converted to an image (OCR).',
      );
    }
    final tmp = await getTemporaryDirectory();
    // S7: a fixed 'ocr_sayfa_N.png' name collided between books / concurrent runs,
    // and the file was never deleted -> unique timestamped name + cleanup in finally.
    final f = File(
      '${tmp.path}/ocr_${DateTime.now().microsecondsSinceEpoch}_s$pageNumber.png',
    );
    await f.writeAsBytes(image.bytes, flush: true);
    final recognizer = TextRecognizer();
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(f.path),
      );
      return result.text;
    } finally {
      await recognizer.close();
      try {
        await f.delete();
      } on Object catch (_) {
        // If the temp file cannot be deleted the flow is not broken (no diagnostic value).
      }
    }
  } finally {
    await doc.close();
  }
}
