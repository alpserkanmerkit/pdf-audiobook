// Oracle test (PHASE W4, K24-pipeline): the provider routing ternary inside
// PagePipeline.prepareAudio currently sends EVERY provider string other than
// 'azure' (typos included) silently to EdgeTts. This file:
//  1) proves that with provider='google' + googleKey given, GoogleTts is REALLY
//     called (NOT EdgeTts),
//  2) proves that an unrecognized provider string throws a TYPED exception
//     instead of silently falling back to EdgeTts.
//
// To test without touching the real network/PDF/LLM, the text cache is
// pre-filled (prepareText returns via the cache-hit path) and an injectable
// ttsProviderFactory seam is used (same DI pattern as AppServices'
// playerOpsFactory).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/io/azure_tts.dart';
import 'package:sesli_kitap/io/cache_store.dart';
import 'package:sesli_kitap/io/edge_tts.dart';
import 'package:sesli_kitap/io/google_tts.dart';
import 'package:sesli_kitap/io/page_pipeline.dart';
import 'package:sesli_kitap/io/tts_provider.dart';
import 'package:sesli_kitap/src/voices.dart';

class _RecordingTts implements TtsProvider {
  _RecordingTts(this.label);
  final String label;
  int calls = 0;

  @override
  Future<Uint8List> synthesize({
    required String text,
    required SesliVoice voice,
    double rate = 1.0,
  }) async {
    calls++;
    return Uint8List.fromList([1, 2, 3]);
  }
}

void main() {
  late Directory tmp;
  late CacheStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('page_pipeline_provider_test');
    store = CacheStore(tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  /// Pre-fills the text cache so that prepareAudio -> prepareText passes
  /// through the cache-hit path without touching the real PDF/OCR/LLM.
  Future<void> seedCachedText(
    String bookHash,
    int pageNo,
    String promptVersion,
  ) async {
    await store.writeText(
      't_${bookHash}_p${pageNo}_$promptVersion'.replaceAll(
        RegExp('[^a-zA-Z0-9._-]'),
        '_',
      ),
      TextEntry(
        raw: 'raw text',
        clean: 'clean text',
        promptVersion: promptVersion,
        suspicious: false,
      ),
    );
  }

  test("provider='google' + googleKey given -> GoogleTts is called, NOT EdgeTts "
      '(K24 fix -- TODAY it silently uses EdgeTts)', () async {
    final edge = _RecordingTts('edge');
    final google = _RecordingTts('google');
    String? seenProvider;

    final pipeline = PagePipeline(
      store: store,
      bookBytes: Uint8List(0),
      bookHash: 'ghash',
      ttsProviderFactory: (s) {
        seenProvider = s.provider;
        return s.provider == 'google' ? google : edge;
      },
    );

    const settings = PipelineSettings(
      geminiKey: 'k',
      voice: SesliVoice.wavenetB,
      rate: 1,
      provider: 'google',
      googleKey: 'goog-key',
    );
    await seedCachedText('ghash', 1, settings.stamp.cleanPromptVersion);

    await pipeline.prepareAudio(1, settings);

    expect(
      seenProvider,
      'google',
      reason:
          'prepareAudio must pass the correct provider to the dispatch function',
    );
    expect(
      google.calls,
      1,
      reason: "GoogleTts MUST be called when provider='google'",
    );
    expect(
      edge.calls,
      0,
      reason: "EdgeTts must NOT be silently used when provider='google' (K24)",
    );
  });

  test(
    "provider='edge' still goes to EdgeTts (backward-compatibility regression pin)",
    () async {
      final edge = _RecordingTts('edge');
      final azure = _RecordingTts('azure');
      final google = _RecordingTts('google');

      final pipeline = PagePipeline(
        store: store,
        bookBytes: Uint8List(0),
        bookHash: 'ehash',
        ttsProviderFactory: (s) {
          switch (s.provider) {
            case 'azure':
              return azure;
            case 'google':
              return google;
            default:
              return edge;
          }
        },
      );

      const settings = PipelineSettings(
        geminiKey: 'k',
        voice: SesliVoice.ahmet,
        rate: 1,
        provider: 'edge',
      );
      await seedCachedText('ehash', 1, settings.stamp.cleanPromptVersion);

      await pipeline.prepareAudio(1, settings);

      expect(edge.calls, 1);
      expect(azure.calls, 0);
      expect(google.calls, 0);
    },
  );

  test(
    "provider='azure' still goes to AzureTts (backward-compatibility regression pin)",
    () async {
      final edge = _RecordingTts('edge');
      final azure = _RecordingTts('azure');

      final pipeline = PagePipeline(
        store: store,
        bookBytes: Uint8List(0),
        bookHash: 'ahash',
        ttsProviderFactory: (s) => s.provider == 'azure' ? azure : edge,
      );

      const settings = PipelineSettings(
        geminiKey: 'k',
        voice: SesliVoice.ahmet,
        rate: 1,
        provider: 'azure',
        azureKey: 'az-key',
      );
      await seedCachedText('ahash', 1, settings.stamp.cleanPromptVersion);

      await pipeline.prepareAudio(1, settings);

      expect(azure.calls, 1);
      expect(edge.calls, 0);
    },
  );

  test(
    'unrecognized provider string (typo) -> throws a TYPED exception and does '
    'NOT silently use EdgeTts (K24 -- TODAY it silently picks EdgeTts)',
    () async {
      final pipeline = PagePipeline(
        store: store,
        bookBytes: Uint8List(0),
        bookHash: 'xhash',
      );

      const settings = PipelineSettings(
        geminiKey: 'k',
        voice: SesliVoice.ahmet,
        rate: 1,
        provider: 'gogle', // typo -- not recognized
      );
      await seedCachedText('xhash', 1, settings.stamp.cleanPromptVersion);

      await expectLater(
        pipeline.prepareAudio(1, settings),
        throwsA(isA<UnknownTtsProviderException>()),
      );
    },
  );

  test(
    'real dispatch without ttsProviderFactory: provider=google -> '
    'GoogleTtsException type surfaces on a network error (proof that the real '
    'GoogleTts was used -- an invalid key is expected to give HTTP 401/403, NOT '
    'the EdgeTts protocol)',
    () async {
      final pipeline = PagePipeline(
        store: store,
        bookBytes: Uint8List(0),
        bookHash: 'nhash',
      );

      const settings = PipelineSettings(
        geminiKey: 'k',
        voice: SesliVoice.wavenetB,
        rate: 1,
        provider: 'google',
        googleKey: 'invalid-key-test',
      );
      await seedCachedText('nhash', 1, settings.stamp.cleanPromptVersion);

      // Real network call (GoogleTts uses the default http.Client) -- it is
      // EXPECTED to fail with the invalid key. What matters is that the error
      // is the GoogleTtsException (or a network-layer error), and never an
      // EdgeTtsException (proof that there is no silent fallback to EdgeTts).
      await expectLater(
        pipeline.prepareAudio(1, settings),
        throwsA(isNot(isA<EdgeTtsException>())),
      );
    },
    skip:
        'requires a real network call -- does not work in CI/offline environments; '
        'dispatch correctness is already gated by the ttsProviderFactory tests above',
  );

  group(
    'empty-key guard: when a paid provider is selected but its key is empty, it falls back to Edge '
    '(instead of a raw HTTP 401 -- same contract as the LLM fallback + discussion guard in the reader)',
    () {
      PipelineSettings settings(
        String provider, {
        SesliVoice voice = SesliVoice.wavenetB,
        String googleKey = '',
        String azureKey = '',
      }) => PipelineSettings(
        geminiKey: 'k',
        voice: voice,
        rate: 1,
        provider: provider,
        googleKey: googleKey,
        azureKey: azureKey,
      );

      test(
        "provider='google' + EMPTY googleKey + Microsoft-compatible voice (ahmet) -> "
        'EdgeTts (instead of a raw 401; ahmet is a name that really works on Edge too)',
        () {
          expect(
            resolveTtsProvider(settings('google', voice: SesliVoice.ahmet)),
            isA<EdgeTts>(),
          );
        },
      );

      // Phase 2 review finding: the default voice here used to be wavenetB
      // (Google-only) -- this test then expected "EdgeTts", but wavenetB is an
      // UNDEFINED name on Edge (Edge would fail silently with a "voice not
      // found" error). This was an unnoticed hidden break because it could
      // never be selected from the UI before Phase 2; it became really
      // triggerable once the English voices (Google-only) were added. Fix: for
      // a Google-only voice + empty key, a typed, understandable exception
      // INSTEAD of a silent fallback to Edge.
      test(
        "provider='google' + EMPTY googleKey + Google-only voice (wavenetB) -> "
        'a typed GoogleTtsException INSTEAD of silent Edge (Edge would not '
        'recognize this voice name and would silently fail)',
        () {
          expect(
            () => resolveTtsProvider(settings('google')),
            throwsA(isA<GoogleTtsException>()),
          );
        },
      );

      test(
        "provider='google' + EMPTY googleKey + English voice (enWavenetD) -> "
        'same typed GoogleTtsException (Phase 2 review finding 1)',
        () {
          expect(
            () => resolveTtsProvider(
              settings('google', voice: SesliVoice.enWavenetD),
            ),
            throwsA(isA<GoogleTtsException>()),
          );
        },
      );

      test(
        "provider='google' + FILLED googleKey -> GoogleTts (whatever the voice)",
        () {
          expect(
            resolveTtsProvider(
              settings(
                'google',
                voice: SesliVoice.enWavenetD,
                googleKey: 'goog',
              ),
            ),
            isA<GoogleTts>(),
          );
        },
      );

      test("provider='azure' + EMPTY azureKey -> EdgeTts", () {
        expect(resolveTtsProvider(settings('azure')), isA<EdgeTts>());
      });

      test("provider='azure' + FILLED azureKey -> AzureTts", () {
        expect(
          resolveTtsProvider(settings('azure', azureKey: 'az')),
          isA<AzureTts>(),
        );
      });

      test("provider='edge' -> EdgeTts (backward compatibility)", () {
        expect(resolveTtsProvider(settings('edge')), isA<EdgeTts>());
      });

      test(
        'unrecognized provider -> UnknownTtsProviderException (the guard does '
        'NOT silently use Edge, the typed exception is preserved)',
        () {
          expect(
            () => resolveTtsProvider(settings('gogle')),
            throwsA(isA<UnknownTtsProviderException>()),
          );
        },
      );
    },
  );
}
