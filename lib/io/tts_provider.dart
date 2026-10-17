// PHASE 2 wiring: TTS provider interface (spec §2 "TTS is a module").
// EdgeTts (default) and AzureTts (fallback, spec §9) implement it; chosen from settings.
import 'dart:typed_data';

import 'package:sesli_kitap/src/sentence_timing.dart';
import 'package:sesli_kitap/src/voices.dart';

/// Single request timeout for cloud TTS (Gemini / Google). Measurement (2026-09-28):
/// flash-lite-tts takes ~10-12 s per line to generate, live probe 2.8-3.4 s ->
/// 30 s is ~2.5x the longest measurement; a hanging connection does not keep the user waiting forever.
const Duration ttsRequestTimeout = Duration(seconds: 30);

/// Reason shown to the user when the timeout elapses.
String ttsTimeoutMessage(Duration limit) =>
    'The voice server did not respond within ${limit.inSeconds} seconds. '
    'Check your internet connection and try again.';

// Several real providers + test fakes `implements` this interface;
// turning it into a typedef would break this contract.
// ignore: one_member_abstracts
abstract class TtsProvider {
  Future<Uint8List> synthesize({
    required String text,
    required SesliVoice voice,
    double rate = 1.0,
  });
}

/// Audio + (if any) word-boundary events. Karaoke foundation (PR-K1): [words] is null
/// when the provider produced no timing (old/plain path).
class TimedSynthesis {
  const TimedSynthesis({required this.audio, this.words});

  final Uint8List audio;
  final List<WordBoundary>? words;
}

/// Provider that can collect word-boundary timestamps (EdgeTts implements it).
/// The [synthesize] signature does NOT change; this is an ADDITION only.
abstract class TimedTtsProvider implements TtsProvider {
  Future<TimedSynthesis> synthesizeWithTimings({
    required String text,
    required SesliVoice voice,
    double rate = 1.0,
  });
}
