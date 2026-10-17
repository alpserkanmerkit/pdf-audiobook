// Oracle test (PR-K1): PagePipeline.prepareAudio karaoke timing sidecar.
// If the provider is a TimedTtsProvider, synthesizeWithTimings is called;
// sentence timings are built from the collected words and written via
// store.writeTimings (BEFORE the mp3 write, best-effort). A plain TtsProvider
// has no sidecar. The cachedTimings read path uses the same stamp. Without
// touching the real network/PDF/LLM: the text cache is pre-filled and the
// ttsProviderFactory seam is used.
//
// REVIEW FINDING (concurrency): reader prefetch (fire-and-forget) and
// user-play may call prepareAudio concurrently for the SAME key. writeAudio/
// writeTimings use a FIXED .tmp path -> two writers interleave bytes (a
// corrupt mp3 is then served permanently with hasAudio>0), or the second
// rename throws a FileSystemException. In-flight dedup is REQUIRED; the
// synthesis count is pinned with a Completer-gated fake provider.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/io/cache_store.dart';
import 'package:sesli_kitap/io/page_pipeline.dart';
import 'package:sesli_kitap/io/tts_provider.dart';
import 'package:sesli_kitap/src/sentence_timing.dart';
import 'package:sesli_kitap/src/voices.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// A real single-page PDF (same pattern as the llm_fallback test): the force=true
/// path also forces prepareText (the text cache is skipped) -> real PDF
/// extraction is reached; an empty bookBytes would throw there.
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

/// Fake TimedTtsProvider that returns word boundaries.
class _FakeTimedTts implements TimedTtsProvider {
  int plainCalls = 0;
  int timedCalls = 0;

  @override
  Future<Uint8List> synthesize({
    required String text,
    required SesliVoice voice,
    double rate = 1.0,
  }) async {
    plainCalls++;
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<TimedSynthesis> synthesizeWithTimings({
    required String text,
    required SesliVoice voice,
    double rate = 1.0,
  }) async {
    timedCalls++;
    return TimedSynthesis(
      audio: Uint8List.fromList([1, 2, 3]),
      words: const [
        WordBoundary(offsetMs: 0, durationMs: 100, text: 'Bir'),
        WordBoundary(offsetMs: 100, durationMs: 100, text: 'iki'),
        WordBoundary(offsetMs: 500, durationMs: 100, text: 'Uc'),
        WordBoundary(offsetMs: 700, durationMs: 100, text: 'dort'),
      ],
    );
  }
}

/// Fake TimedTtsProvider that HOLDS synthesis with a Completer gate
/// (concurrency test): each synthesizeWithTimings call blocks on its own gate;
/// the test opens the gates one by one and pins the synthesis COUNT.
class _GatedTimedTts implements TimedTtsProvider {
  final List<Completer<void>> gates = [];
  int plainCalls = 0;
  int timedCalls = 0;

  @override
  Future<Uint8List> synthesize({
    required String text,
    required SesliVoice voice,
    double rate = 1.0,
  }) async {
    plainCalls++;
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<TimedSynthesis> synthesizeWithTimings({
    required String text,
    required SesliVoice voice,
    double rate = 1.0,
  }) async {
    timedCalls++;
    final gate = Completer<void>();
    gates.add(gate);
    await gate.future;
    return TimedSynthesis(
      audio: Uint8List.fromList([1, 2, 3]),
      words: const [
        WordBoundary(offsetMs: 0, durationMs: 100, text: 'Bir'),
        WordBoundary(offsetMs: 100, durationMs: 100, text: 'iki'),
        WordBoundary(offsetMs: 500, durationMs: 100, text: 'Uc'),
        WordBoundary(offsetMs: 700, durationMs: 100, text: 'dort'),
      ],
    );
  }
}

/// No timing: plain provider (no karaoke seam).
class _PlainTts implements TtsProvider {
  int calls = 0;

  @override
  Future<Uint8List> synthesize({
    required String text,
    required SesliVoice voice,
    double rate = 1.0,
  }) async {
    calls++;
    return Uint8List.fromList([9, 9, 9]);
  }
}

void main() {
  late Directory tmp;
  late CacheStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('page_pipeline_timing_test');
    store = CacheStore(tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  /// Pre-fills the text cache (so prepareText returns from the cache-hit).
  Future<void> seedText(
    String bookHash,
    int pageNo,
    String promptVersion,
    String clean,
  ) async {
    await store.writeText(
      't_${bookHash}_p${pageNo}_$promptVersion'.replaceAll(
        RegExp('[^a-zA-Z0-9._-]'),
        '_',
      ),
      TextEntry(
        raw: clean,
        clean: clean,
        promptVersion: promptVersion,
        suspicious: false,
      ),
    );
  }

  const settings = PipelineSettings(
    geminiKey: 'k',
    voice: SesliVoice.emel,
    rate: 1,
    provider: 'edge',
  );

  test(
    'TimedTtsProvider -> sidecar is written + cachedTimings returns it',
    () async {
      final timed = _FakeTimedTts();
      final pipeline = PagePipeline(
        store: store,
        bookBytes: Uint8List(0),
        bookHash: 'thash',
        ttsProviderFactory: (_) => timed,
      );
      await seedText(
        'thash',
        1,
        settings.stamp.cleanPromptVersion,
        'Bir iki. Uc dort.',
      );

      await pipeline.prepareAudio(1, settings);

      expect(timed.timedCalls, 1, reason: 'the timed path must be called');
      expect(
        timed.plainCalls,
        0,
        reason: 'plain synthesize must not be called',
      );

      final t = await pipeline.cachedTimings(1, settings);
      expect(t, isNotNull, reason: 'the sidecar must have been written');
      expect(t!.startsMs.length, 2);
      expect(t.startsMs[0], 0);
    },
  );

  test('plain TtsProvider -> NO sidecar, cachedTimings null', () async {
    final plain = _PlainTts();
    final pipeline = PagePipeline(
      store: store,
      bookBytes: Uint8List(0),
      bookHash: 'phash',
      ttsProviderFactory: (_) => plain,
    );
    await seedText(
      'phash',
      1,
      settings.stamp.cleanPromptVersion,
      'Bir iki. Uc dort.',
    );

    await pipeline.prepareAudio(1, settings);

    expect(plain.calls, 1);
    final t = await pipeline.cachedTimings(1, settings);
    expect(t, isNull, reason: 'a plain provider does not produce a sidecar');
  });

  test(
    'cache-hit: no re-synthesis when mp3 exists (including the timed path)',
    () async {
      final timed = _FakeTimedTts();
      final pipeline = PagePipeline(
        store: store,
        bookBytes: Uint8List(0),
        bookHash: 'chash',
        ttsProviderFactory: (_) => timed,
      );
      await seedText(
        'chash',
        1,
        settings.stamp.cleanPromptVersion,
        'Bir iki. Uc dort.',
      );

      await pipeline.prepareAudio(1, settings); // 1st production
      expect(timed.timedCalls, 1);

      await pipeline.prepareAudio(1, settings); // cache-hit
      expect(timed.timedCalls, 1, reason: 'a cache-hit must not re-synthesize');
    },
  );

  group('concurrent prepareAudio — in-flight dedup (review finding)', () {
    /// Waits until the condition holds; if it does not happen within 5 s the
    /// test FAILs explicitly (a diagnosable red instead of hanging forever).
    Future<void> until(bool Function() cond, String neden) async {
      final sw = Stopwatch()..start();
      while (!cond()) {
        if (sw.elapsedMilliseconds > 5000) {
          fail('Not reached within 5 s: $neden');
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    test('two concurrent calls for the same key -> synthesis runs EXACTLY once, both calls return '
        'the SAME file, no leftover tmp files', () async {
      final tts = _GatedTimedTts();
      final pipeline = PagePipeline(
        store: store,
        bookBytes: Uint8List(0),
        bookHash: 'dhash',
        ttsProviderFactory: (_) => tts,
      );
      await seedText(
        'dhash',
        1,
        settings.stamp.cleanPromptVersion,
        'Bir iki. Uc dort.',
      );

      // Reader prefetch + user-play race: same key, concurrent.
      final f1 = pipeline.prepareAudio(1, settings);
      final f2 = pipeline.prepareAudio(1, settings);

      await until(() => tts.gates.isNotEmpty, 'the first synthesis must start');
      // Short settle: without dedup, the second synthesis would also start.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        tts.timedCalls,
        1,
        reason:
            'the concurrent second call must NOT start a NEW synthesis (dedup)',
      );

      tts.gates[0].complete();
      final r1 = await f1;
      final r2 = await f2;
      expect(r1.path, r2.path, reason: 'both calls must return the same file');
      expect(tts.timedCalls, 1);

      final artik = tmp
          .listSync()
          .where((e) => e.path.endsWith('.tmp'))
          .toList();
      expect(
        artik,
        isEmpty,
        reason:
            'two writers must not interleave on the fixed .tmp path (corrupt mp3 risk)',
      );

      // Production finished: the next call returns from the cache-hit, no new synthesis.
      final r3 = await pipeline.prepareAudio(1, settings);
      expect(r3.path, r1.path);
      expect(tts.timedCalls, 1);
    });

    test('force=true while in-flight: waits until the current production FINISHES, '
        'then regenerates (behavior pin)', () async {
      final tts = _GatedTimedTts();
      // force also forces prepareText -> real PDF bytes are required; with an
      // EMPTY geminiKey the network is never touched (K12 contract, the
      // fallback is raw text).
      final pipeline = PagePipeline(
        store: store,
        bookBytes: _onePagePdf('Bir iki. Uc dort.'),
        bookHash: 'fhash',
        ttsProviderFactory: (_) => tts,
      );
      const forceSettings = PipelineSettings(
        geminiKey: '',
        voice: SesliVoice.emel,
        rate: 1,
        provider: 'edge',
      );

      final f1 = pipeline.prepareAudio(1, forceSettings);
      await until(
        () => tts.gates.length == 1,
        'the first synthesis must start',
      );

      final f2 = pipeline.prepareAudio(1, forceSettings, force: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        tts.timedCalls,
        1,
        reason:
            'a force call must NOT start synthesis before the current in-flight '
            'finishes (two writers would interleave on the fixed .tmp path)',
      );

      tts.gates[0].complete();
      await until(
        () => tts.gates.length == 2,
        'the force regeneration must start once the first production finishes',
      );
      expect(tts.timedCalls, 2, reason: 'force must regenerate');
      tts.gates[1].complete();

      final r1 = await f1;
      final r2 = await f2;
      expect(r2.path, r1.path, reason: 'same key, same final file');

      final artik = tmp
          .listSync()
          .where((e) => e.path.endsWith('.tmp'))
          .toList();
      expect(artik, isEmpty);
    });
  });
}
