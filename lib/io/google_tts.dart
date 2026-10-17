import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sesli_kitap/io/tts_provider.dart';
import 'package:sesli_kitap/src/tts_chunking.dart';
import 'package:sesli_kitap/src/voices.dart';

/// The Google Cloud TTS text:synthesize input is limited to 5000 UTF-8 bytes
/// (curl proof: 5001 bytes -> 400 "...longer than the limit of 5000 bytes...").
/// 4500 is used as a safety margin.
const _maxChunkBytes = 4500;

class GoogleTtsException implements Exception {
  GoogleTtsException(this.reason);
  final String reason;

  @override
  String toString() => 'GoogleTtsException: $reason';
}

class GoogleTts implements TtsProvider {
  GoogleTts({required this.apiKey, http.Client? client})
    : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  @override
  Future<Uint8List> synthesize({
    required String text,
    required SesliVoice voice,
    double rate = 1.0,
  }) async {
    final chunks = chunkTextForTts(text, maxBytes: _maxChunkBytes);
    if (chunks.length <= 1) {
      // Short text: a SINGLE request, IDENTICAL to the old behavior (if chunks is
      // empty -- empty input -- a single request is still sent as in the old
      // path, so the server's empty-body error STAYS the same).
      return _synthesizeOne(text: text, voice: voice, rate: rate);
    }
    final builder = BytesBuilder(copy: false);
    for (final chunk in chunks) {
      final part = await _synthesizeOne(text: chunk, voice: voice, rate: rate);
      builder.add(part);
    }
    return builder.toBytes();
  }

  Future<Uint8List> _synthesizeOne({
    required String text,
    required SesliVoice voice,
    required double rate,
  }) async {
    // S3: the key is NOT carried in the URL query -- the network layer embeds
    // the uri in the ClientException message, and the key would leak into the
    // log/error text. It is sent in a header.
    final uri = Uri.parse(
      'https://texttospeech.googleapis.com/v1/text:synthesize',
    );
    final body = jsonEncode({
      'input': {'text': text},
      // Bug-G: the raw voiceId(voice) sends a name UNKNOWN to Google for
      // Microsoft-family voices (ahmet/emel) (curl proof: 400 "Voice ...
      // does not exist"). googleVoiceId returns a Google-valid counterpart for
      // EVERY SesliVoice. Phase 2: languageCode is NO LONGER a fixed 'tr-TR' --
      // it is derived from the voice's own locale (English voice -> en-US).
      'voice': {
        'languageCode': localeCodeOf(voice),
        'name': googleVoiceId(voice),
      },
      'audioConfig': {'audioEncoding': 'MP3', 'speakingRate': rate},
    });
    final response = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'X-Goog-Api-Key': apiKey,
          },
          body: body,
        )
        .timeout(
          ttsRequestTimeout,
          onTimeout: () =>
              throw GoogleTtsException(ttsTimeoutMessage(ttsRequestTimeout)),
        );
    if (response.statusCode != 200) {
      // Google's error body carries a diagnosable message (e.g. "Voice ... does
      // not exist" / "...longer than the limit of 5000 bytes..."); carrying this
      // summary into the exception gives users/logs a MEANINGFUL hint instead of
      // a bare "HTTP 400".
      throw GoogleTtsException(
        'HTTP ${response.statusCode}: ${_summarize(response.body)}',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (e) {
      throw GoogleTtsException('invalid JSON: $e');
    }
    if (decoded is! Map<String, dynamic>) {
      throw GoogleTtsException('unexpected response body');
    }
    final data = decoded;
    final audioContent = data['audioContent'];
    if (audioContent is! String || audioContent.isEmpty) {
      throw GoogleTtsException('empty audioContent');
    }
    return base64Decode(audioContent);
  }

  /// Extracts a short, readable summary from the error body (error.message if
  /// it is JSON; otherwise the first 200 characters of the raw body). The key
  /// never appears in the error body (Google does not echo the key back).
  static String _summarize(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic> && error['message'] is String) {
          return error['message'] as String;
        }
      }
    } on FormatException {
      // Not JSON -- fall through to the raw body.
    }
    return responseBody.length > 200
        ? '${responseBody.substring(0, 200)}...'
        : responseBody;
  }
}
