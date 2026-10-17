// PHASE 2 wiring: Azure Speech F0 fallback (spec §2/§9). The key is entered in
// settings; on quota exhaustion Azure stops the request, so there is no
// structural billing risk (spec §9).
// SSML building is reused from the pure layer (lib/src/tts_messages.dart).
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sesli_kitap/io/tts_provider.dart';
import 'package:sesli_kitap/src/tts_messages.dart';
import 'package:sesli_kitap/src/voices.dart';

class AzureTtsException implements Exception {
  AzureTtsException(this.reason);
  final String reason;

  @override
  String toString() => 'AzureTtsException: $reason';
}

class AzureTts implements TtsProvider {
  AzureTts({
    required this.subscriptionKey,
    this.region = 'westeurope',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String subscriptionKey;
  final String region;
  final http.Client _client;

  @override
  Future<Uint8List> synthesize({
    required String text,
    required SesliVoice voice,
    double rate = 1.0,
  }) async {
    final uri = Uri.parse(
      'https://$region.tts.speech.microsoft.com/cognitiveservices/v1',
    );
    final resp = await _client.post(
      uri,
      headers: {
        'Ocp-Apim-Subscription-Key': subscriptionKey,
        'Content-Type': 'application/ssml+xml',
        'X-Microsoft-OutputFormat': 'audio-24khz-48kbitrate-mono-mp3',
        'User-Agent': 'sesli-kitap',
      },
      body: buildSsml(
        text: text,
        voiceId: voiceId(voice),
        rate: formatRate(rate),
        languageCode: localeCodeOf(voice),
      ),
    );
    if (resp.statusCode != 200) {
      throw AzureTtsException('HTTP ${resp.statusCode}');
    }
    if (resp.bodyBytes.isEmpty) {
      throw AzureTtsException('empty audio returned');
    }
    return resp.bodyBytes;
  }
}
