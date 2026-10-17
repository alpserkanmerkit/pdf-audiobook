// Gemini TTS provider (user decision 2026-09-28): the discussion's 4 voices.
// Measurement (internal measurement note): flash-lite-tts
// ~10-12 s generation per turn, ~31-37 s of audio; a multi-speaker request
// accepts at most 2 voices (HTTP 400 with 4) -> ONE speaker per turn is requested.
// The key goes in the HEADER, NOT in the URL (same reason as google_tts S3: a
// network error embeds the uri in its message, and the key would leak into logs).
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sesli_kitap/io/tts_provider.dart';
import 'package:sesli_kitap/src/voices.dart';
import 'package:sesli_kitap/src/wav.dart';

/// Model chosen by the user (33% cheaper than Flash, no audible difference).
const String geminiTtsModel = 'gemini-3.8-flash-lite-tts';

class GeminiTtsException implements Exception {
  GeminiTtsException(this.reason);
  final String reason;

  @override
  String toString() => 'GeminiTtsException: $reason';
}

class GeminiTts implements TtsProvider {
  GeminiTts({required this.apiKey, http.Client? client})
    : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  /// [rate] is ignored because Gemini has no equivalent (speed is the model's
  /// natural speaking rate). The returned bytes are ALWAYS a playable WAV.
  @override
  Future<Uint8List> synthesize({
    required String text,
    required SesliVoice voice,
    double rate = 1.0,
  }) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$geminiTtsModel:generateContent',
    );
    final response = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'x-goog-api-key': apiKey,
          },
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': text},
                ],
              },
            ],
            'generationConfig': {
              'responseModalities': ['AUDIO'],
              'speechConfig': {
                'voiceConfig': {
                  'prebuiltVoiceConfig': {'voiceName': geminiVoiceName(voice)},
                },
              },
            },
          }),
        )
        .timeout(
          ttsRequestTimeout,
          onTimeout: () =>
              throw GeminiTtsException(ttsTimeoutMessage(ttsRequestTimeout)),
        );
    if (response.statusCode != 200) {
      throw GeminiTtsException(
        'HTTP ${response.statusCode}: ${_summarize(response.bodyBytes)}',
      );
    }
    final inline = _inlineAudio(response.bodyBytes);
    return ensureWav(
      base64Decode(inline.data),
      sampleRate: sampleRateFromMime(inline.mimeType),
    );
  }

  /// candidates[0].content.parts[0].inlineData; otherwise [GeminiTtsException].
  static ({String data, String? mimeType}) _inlineAudio(Uint8List body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(body));
    } on FormatException catch (e) {
      throw GeminiTtsException('invalid JSON: $e');
    }
    final candidates = decoded is Map ? decoded['candidates'] : null;
    final content = candidates is List && candidates.isNotEmpty
        ? (candidates.first as Map)['content']
        : null;
    final parts = content is Map ? content['parts'] : null;
    final inline = parts is List && parts.isNotEmpty
        ? (parts.first as Map)['inlineData']
        : null;
    final data = inline is Map ? inline['data'] : null;
    if (data is! String || data.isEmpty) {
      throw GeminiTtsException('no audio data in response');
    }
    // If data is a String, inline is definitely a Map (the `inline is Map` branch above).
    final mime = (inline as Map)['mimeType'];
    return (data: data, mimeType: mime is String ? mime : null);
  }

  /// Short summary from the error body: error.message if it is JSON, otherwise
  /// the first 200 characters.
  static String _summarize(Uint8List body) {
    final text = utf8.decode(body, allowMalformed: true);
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['error'] is Map) {
        final message = (decoded['error'] as Map)['message'];
        if (message is String) return message;
      }
    } on FormatException {
      // Not JSON -- fall through to the raw body.
    }
    return text.length > 200 ? '${text.substring(0, 200)}...' : text;
  }
}
