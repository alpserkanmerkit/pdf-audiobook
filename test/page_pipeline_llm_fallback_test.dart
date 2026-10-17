// Oracle test: LLM cleaning must be an optional layer (same contract as auditClean/K12).
// TODAY prepareText calls LlmCleaner UNCONDITIONALLY; if geminiKey is empty (the user never entered an AI key --
// the fresh-install default), the request goes out with 'Bearer ' (empty token), the LLM answers 401, and
// LlmCleanException is THROWN out of prepareAudio -- audio playback stops completely ("no sound", "HTTP401 LLM
// clean exception" field report). This file proves: (1) with an empty key the network is NEVER touched and the raw
// text is used, (2) with a key that is set but failing there is also a graceful fallback, (3) on a successful call
// the AI-cleaned text is still used (regression).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sesli_kitap/io/cache_store.dart';
import 'package:sesli_kitap/io/page_pipeline.dart';
import 'package:sesli_kitap/src/voices.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

Uint8List _onePagePdf(String line) {
  final doc = PdfDocument();
  final font = PdfStandardFont(PdfFontFamily.helvetica, 12);
  final page = doc.pages.add();
  page.graphics.drawString(
    line,
    font,
    bounds: const Rect.fromLTWH(0, 0, 400, 16),
  );
  final bytes = Uint8List.fromList(doc.saveSync());
  doc.dispose();
  return bytes;
}

void main() {
  late Directory tmp;
  late CacheStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp(
      'page_pipeline_llm_fallback_test',
    );
    store = CacheStore(tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  test(
    'if geminiKey is empty, LlmCleaner is NOT called and the raw page-stripped text '
    'is used as clean (network calls: 0 -- MockClient must see no requests)',
    () async {
      var callCount = 0;
      final mock = MockClient((req) async {
        callCount++;
        return http.Response('the server must never be reached', 500);
      });
      final bytes = _onePagePdf('Test page content here.');
      final pipeline = PagePipeline(
        store: store,
        bookBytes: bytes,
        bookHash: 'emptykey',
        llmClient: mock,
      );

      const settings = PipelineSettings(
        geminiKey: '',
        voice: SesliVoice.ahmet,
        rate: 1,
        provider: 'edge',
      );

      final entry = await pipeline.prepareText(1, settings);

      expect(
        callCount,
        0,
        reason: 'no network call must be made with an empty key',
      );
      expect(entry.clean, contains('Test page content here.'));
    },
  );

  test(
    'if geminiKey is set but LlmCleaner returns HTTP 401, graceful fallback '
    'happens -- no exception LEAKS out, the raw (stripped) text is used',
    () async {
      final mock = MockClient(
        (req) async => http.Response('unauthorized', 401),
      );
      final bytes = _onePagePdf('Second test line.');
      final pipeline = PagePipeline(
        store: store,
        bookBytes: bytes,
        bookHash: 'badkey',
        llmClient: mock,
      );

      const settings = PipelineSettings(
        geminiKey: 'invalid-or-expired-key',
        voice: SesliVoice.ahmet,
        rate: 1,
        provider: 'edge',
      );

      final entry = await pipeline.prepareText(1, settings);

      expect(entry.clean, contains('Second test line.'));
    },
  );

  test(
    'geminiKey set, HTTP 200 but message.content is NOT a VALID {"metin":...} '
    '(model returned broken content) -> CleanParseException does NOT leak -- '
    'graceful fallback uses the raw (stripped) text (field: page skipped on play, '
    '"CleanParseException: metin", no audio/text)',
    () async {
      // parseCleanResponse throws CleanParseException on invalid content;
      // this is NOT LlmCleanException, a separate class. _cleanOrFallback only
      // catches LlmCleanException, so this exception would leak to the reader.
      final mock = MockClient((req) async {
        return http.Response(
          '{"choices":[{"message":{"content":"this is not json"}}]}',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final bytes = _onePagePdf('Fourth test line.');
      final pipeline = PagePipeline(
        store: store,
        bookBytes: bytes,
        bookHash: 'parsefailkey',
        llmClient: mock,
      );

      const settings = PipelineSettings(
        geminiKey: 'valid-key',
        voice: SesliVoice.ahmet,
        rate: 1,
        provider: 'edge',
      );

      final entry = await pipeline.prepareText(1, settings);

      expect(entry.clean, contains('Fourth test line.'));
    },
  );

  test('geminiKey set and the call SUCCEEDS -> AI-cleaned text is used '
      '(regression -- the fallback must not always kick in)', () async {
    final mock = MockClient((req) async {
      return http.Response(
        r'{"choices":[{"message":{"content":"{\"metin\":\"AI CLEANED TEXT\"}"}}]}',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final bytes = _onePagePdf('Third test line.');
    final pipeline = PagePipeline(
      store: store,
      bookBytes: bytes,
      bookHash: 'goodkey',
      llmClient: mock,
    );

    const settings = PipelineSettings(
      geminiKey: 'valid-key',
      voice: SesliVoice.ahmet,
      rate: 1,
      provider: 'edge',
    );

    final entry = await pipeline.prepareText(1, settings);

    expect(entry.clean, 'AI CLEANED TEXT');
  });
}
