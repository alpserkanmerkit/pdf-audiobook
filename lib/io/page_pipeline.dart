import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sesli_kitap/io/auditor.dart';
import 'package:sesli_kitap/io/azure_tts.dart';
import 'package:sesli_kitap/io/cache_store.dart';
import 'package:sesli_kitap/io/edge_tts.dart';
import 'package:sesli_kitap/io/google_tts.dart';
import 'package:sesli_kitap/io/llm_cleaner.dart';
import 'package:sesli_kitap/io/ocr.dart';
import 'package:sesli_kitap/io/pdf_text.dart';
import 'package:sesli_kitap/io/tts_provider.dart';
import 'package:sesli_kitap/src/cache_keys.dart';
import 'package:sesli_kitap/src/clean_contract.dart';
import 'package:sesli_kitap/src/llm_access.dart';
import 'package:sesli_kitap/src/page_preprocess.dart';
import 'package:sesli_kitap/src/pronunciation_rules.dart';
import 'package:sesli_kitap/src/sentence_split.dart';
import 'package:sesli_kitap/src/sentence_timing.dart';
import 'package:sesli_kitap/src/suspicion.dart';
import 'package:sesli_kitap/src/voices.dart';

class UnknownTtsProviderException implements Exception {
  UnknownTtsProviderException(this.provider);
  final String provider;
  @override
  String toString() =>
      'UnknownTtsProviderException: unknown provider "$provider"';
}

class PipelineSettings {
  const PipelineSettings({
    required this.geminiKey,
    required this.voice,
    required this.rate,
    required this.provider,
    this.azureKey = '',
    this.azureRegion = 'westeurope',
    this.pronRules = const [],
    this.googleKey = '',
    this.llmAccess,
  });

  final String geminiKey;
  final SesliVoice voice;
  final double rate;
  final String provider;
  final String azureKey;
  final String azureRegion;
  final List<PronRule> pronRules;
  final String googleKey;

  /// Provider chosen in Settings; if not given, only Gemini ([geminiKey]).
  final LlmAccess? llmAccess;

  LlmAccess get access =>
      llmAccess ?? LlmAccess.single(LlmProvider.gemini, geminiKey);

  CacheStamp get stamp => CacheStamp(
    cleanPromptVersion: cleanPromptVersion,
    ttsVoice: voiceId(voice),
    ttsRate: formatRate(rate),
    pronTag: pronRulesTag(pronRules),
  );
}

class PagePipeline {
  PagePipeline({
    required this.store,
    required this.bookBytes,
    required this.bookHash,
    this.knownHeader,
    this.ttsProviderFactory,
    this.llmClient,
  });

  final CacheStore store;
  final Uint8List bookBytes;
  final String bookHash;
  final String? knownHeader;
  final TtsProvider Function(PipelineSettings s)? ttsProviderFactory;
  final http.Client? llmClient;

  String _textKey(int pageNo) => textCacheKey(
    bookHash: bookHash,
    pageNo: pageNo,
    cleanPromptVersion: cleanPromptVersion,
  );

  static String? detectRunningHeader(Uint8List bytes, int totalPages) {
    String? firstLine(int page) {
      final raw = extractPageText(bytes, page);
      final lines = raw
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty);
      for (final l in lines) {
        if (stripPageArtifacts(l).pageNumber == null) {
          return l;
        }
      }
      return null;
    }

    if (totalPages < 4) {
      return null;
    }
    final a = firstLine(2);
    final b = firstLine(4);
    if (a != null && a.isNotEmpty && a == b) {
      return a;
    }
    return null;
  }

  Future<List<({String rawFirstLine, String? strippedHeader})>> chapterHeaders({
    void Function(int done, int total)? onProgress,
  }) async {
    final texts = await extractAllPageTexts(bookBytes, onProgress: onProgress);
    final out = <({String rawFirstLine, String? strippedHeader})>[];
    for (final raw in texts) {
      final first = raw
          .trim()
          .split('\n')
          .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '')
          .trim();
      final pre = stripPageArtifacts(raw, knownHeader: knownHeader);
      out.add((rawFirstLine: first, strippedHeader: pre.strippedHeader));
    }
    return out;
  }

  Future<String?> cachedCleanText(int pageNo) async {
    final cached = await store.readText(_textKey(pageNo));
    return cached?.clean;
  }

  Future<TextEntry> prepareText(
    int pageNo,
    PipelineSettings s, {
    bool force = false,
  }) async {
    final key = _textKey(pageNo);
    if (!force) {
      final cached = await store.readText(key);
      if (cached != null &&
          !isTextStale(
            storedPromptVersion: cached.promptVersion,
            currentPromptVersion: cleanPromptVersion,
          )) {
        return cached;
      }
    }
    var raw = extractPageText(bookBytes, pageNo);
    if (raw.trim().isEmpty) {
      raw = await ocrPdfPage(bookBytes, pageNo);
    }
    if (raw.trim().isEmpty) {
      throw StateError('Page $pageNo: both the text layer and OCR are empty.');
    }
    final pre = stripPageArtifacts(raw, knownHeader: knownHeader);
    final clean = await _cleanOrFallback(pre.text, s);
    final verdict = assessClean(raw: pre.text, clean: clean.metin);
    bool? audit;
    if (verdict.suspicious) {
      audit = await auditClean(
        access: s.access,
        raw: pre.text,
        clean: clean.metin,
        client: llmClient,
      );
    }

    final entry = TextEntry(
      raw: pre.text,
      clean: clean.metin,
      promptVersion: cleanPromptVersion,
      suspicious: verdict.suspicious,
      suspicionReasons: verdict.reasons,
      auditFaithful: audit,
    );
    await store.writeText(key, entry);
    return entry;
  }

  /// LLM cleaning is an OPTIONAL layer (same contract as auditClean/K12):
  /// if the key is empty no network call is made at all; if the call fails
  /// (401 / network error / invalid body / PARSE error) it silently falls back
  /// to the locally stripped raw text. So the audio reading flow never breaks,
  /// even when the LLM is not configured.
  Future<CleanResult> _cleanOrFallback(
    String rawText,
    PipelineSettings s,
  ) async {
    if (s.llmAccess == null
        ? s.geminiKey.trim().isEmpty
        : !s.access.isConfigured) {
      return CleanResult(rawText);
    }
    try {
      return await LlmCleaner(
        access: s.access,
        client: llmClient,
      ).clean(rawText);
    } on LlmCleanException {
      return CleanResult(rawText);
    } on CleanParseException {
      // Even with HTTP 200, if the model returns broken content instead of a valid
      // {"metin":...}, parseCleanResponse (clean_contract) throws CleanParseException
      // -- this is NOT a LlmCleanException. If uncaught, the reader would see
      // "CleanParseException: metin" and no audio/text (field bug).
      return CleanResult(rawText);
    }
  }

  TtsProvider _resolveTts(PipelineSettings s) {
    if (ttsProviderFactory != null) {
      return ttsProviderFactory!(s);
    }
    return resolveTtsProvider(s);
  }

  /// In-flight production map (review finding): the reader prefetch
  /// (fire-and-forget) and a user play can call prepareAudio concurrently for the
  /// SAME key. writeAudio/writeTimings use a FIXED .tmp path -> two writers would
  /// write mixed bytes (a broken mp3 with hasAudio>0 would be served PERMANENTLY),
  /// or the second write would throw PathAccessException/FileSystemException
  /// (errno 32 was reproduced live in a RED run). Same key = same content stamp =
  /// same input; one production is enough.
  final Map<String, Future<File>> _inflightAudio = {};

  Future<File> prepareAudio(
    int pageNo,
    PipelineSettings s, {
    bool force = false,
  }) {
    final key = audioCacheKey(
      bookHash: bookHash,
      pageNo: pageNo,
      stamp: s.stamp,
    );
    final existing = _inflightAudio[key];
    if (existing != null && !force) {
      return existing; // dedup: a concurrent second call shares the same production
    }
    // force + in-flight: wait until the current production FINISHES (its result/error
    // does not matter), THEN produce again -- two writers can never touch the fixed
    // .tmp path at the same time (pinned by a test).
    final fut = _produceAudio(pageNo, s, key, force: force, waitFor: existing);
    _inflightAudio[key] = fut;
    fut
        .whenComplete(() {
          // Only remove OUR OWN entry: a force chain may have written a newer
          // future into the map.
          if (identical(_inflightAudio[key], fut)) {
            unawaited(_inflightAudio.remove(key));
          }
        })
        // The cleanup chain's own error already reaches the caller through `fut`;
        // this copy must not become an unhandled async error.
        .ignore();
    return fut;
  }

  Future<File> _produceAudio(
    int pageNo,
    PipelineSettings s,
    String key, {
    required bool force,
    Future<File>? waitFor,
  }) async {
    if (waitFor != null) {
      try {
        await waitFor;
      } on Object catch (_) {
        // The previous production's error does not concern us; we only waited for it to finish.
      }
    }
    if (!force && await store.hasAudio(key)) {
      return store.audioFile(key);
    }
    final entry = await prepareText(pageNo, s, force: force);
    final tts = _resolveTts(s);
    final spoken = applyPronRules(entry.clean, s.pronRules);

    // Karaoke foundation (PR-K1): if the provider is a TimedTtsProvider, collect the
    // word boundaries and produce the sentence-timing sidecar. Sidecar production is
    // BEST-EFFORT (try/catch) -- it NEVER breaks the audio flow; timing errors are swallowed silently.
    Uint8List mp3;
    if (tts is TimedTtsProvider) {
      final r = await tts.synthesizeWithTimings(
        text: spoken,
        voice: s.voice,
        rate: s.rate,
      );
      mp3 = r.audio;
      final words = r.words;
      if (words != null && words.isNotEmpty) {
        try {
          final t = timingsFromWordBoundaries(
            sentences: splitIntoSentences(entry.clean),
            words: words,
          );
          if (t != null) {
            // BEFORE the mp3 write: when hasAudio==true, the sidecar (if produced)
            // is already ready.
            await store.writeTimings(key, t);
          }
        } on Object catch (_) {
          // sidecar is best-effort; the audio path is not broken
        }
      }
    } else {
      mp3 = await tts.synthesize(text: spoken, voice: s.voice, rate: s.rate);
    }
    return store.writeAudio(key, mp3);
  }

  /// Previously produced sentence-timing sidecar (for the PR-K2 reader wiring).
  /// Old mp3s have no sidecar -> null (fallback by design).
  Future<SentenceTimings?> cachedTimings(int pageNo, PipelineSettings s) {
    final key = audioCacheKey(
      bookHash: bookHash,
      pageNo: pageNo,
      stamp: s.stamp,
    );
    return store.readTimings(key);
  }
}

/// Selects a concrete [TtsProvider] from the provider string (the real path outside the factory).
/// For the PAID Google/Azure providers, if the KEY is empty it falls back to Edge --
/// Edge needs no key; otherwise the network would be hit with an empty key, HTTP 401
/// would come back and a raw '401' snackbar would reach the user. This is the SAME
/// contract as the reader-path LLM cleaning (_cleanOrFallback) and the discussion
/// empty-key guard: 'if the key is empty, no network; drop to the silently working path'.
/// An unknown provider string still throws a TYPED exception (not a silent Edge, K24).
TtsProvider resolveTtsProvider(PipelineSettings s) {
  switch (s.provider) {
    case 'edge':
      return EdgeTts();
    case 'azure':
      return s.azureKey.trim().isEmpty
          ? EdgeTts()
          : AzureTts(subscriptionKey: s.azureKey, region: s.azureRegion);
    case 'google':
      if (s.googleKey.trim().isNotEmpty) return GoogleTts(apiKey: s.googleKey);
      // Phase 2 review finding: with an empty key, fall back to Edge ONLY if the voice
      // really works on Edge too. A Google-only voice (Turkish Wavenet/Chirp family, or
      // the Phase 2 English voices) sent to Edge makes voiceId() return a Google-style
      // name (e.g. 'en-US-Wavenet-D') -- Edge/Microsoft does NOT recognize it and fails
      // silently with a "no voice" error. In that case throw a typed, clear exception
      // instead of a silent Edge.
      if (providerOf(s.voice) == TtsProviderKind.google) {
        throw GoogleTtsException(
          'A Google API key is required for this voice (Settings > Account & API).',
        );
      }
      return EdgeTts();
    default:
      throw UnknownTtsProviderException(s.provider);
  }
}
