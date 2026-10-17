// Oracle test (Gemini TTS slice, 2026-09-28): GeminiTts REST provider.
// The lib/io HTTP body is outside the coverage gate -> body/URL/header + error chain
// are pinned with MockClient (google_tts_test pattern).
// Measurement: gemini-3.8-flash-lite-tts accepts at most 2 voices in multi-speaker mode
// (HTTP 400 at 4) -> the app asks for ONE speaker per utterance. It returns the audio
// WITH its header as WAV (RIFF); a double header produces crackling (field lesson).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sesli_kitap/io/gemini_tts.dart';
import 'package:sesli_kitap/src/voices.dart';
import 'package:sesli_kitap/src/wav.dart';

http.Response _audio(List<int> bytes, {String mime = 'audio/wav'}) =>
    http.Response(
      jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {
                  'inlineData': {'mimeType': mime, 'data': base64Encode(bytes)},
                },
              ],
            },
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test(
    'request: flash-lite-tts model, key in the HEADER (not the URL), AUDIO mode, '
    'single speaker voice + text',
    () async {
      late Uri url;
      late Map<String, String> headers;
      late Map<String, dynamic> body;
      final mock = MockClient((req) async {
        url = req.url;
        headers = Map<String, String>.of(req.headers);
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return _audio(pcmToWav(Uint8List.fromList([1, 0]), sampleRate: 24000));
      });

      await GeminiTts(
        apiKey: 'gm-key',
        client: mock,
      ).synthesize(text: 'Merhaba dünya.', voice: SesliVoice.wavenetE);

      expect(geminiTtsModel, 'gemini-3.8-flash-lite-tts');
      expect(
        url.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models/'
        'gemini-3.8-flash-lite-tts:generateContent',
      );
      expect(url.toString(), isNot(contains('gm-key')));
      expect(headers['x-goog-api-key'], 'gm-key');
      expect(
        ((((body['contents'] as List)[0] as Map)['parts'] as List)[0]
            as Map)['text'],
        'Merhaba dünya.',
      );
      final gen = body['generationConfig'] as Map<String, dynamic>;
      expect(gen['responseModalities'], ['AUDIO']);
      expect(
        (((gen['speechConfig'] as Map)['voiceConfig']
                as Map)['prebuiltVoiceConfig']
            as Map)['voiceName'],
        'Gacrux',
      );
      expect(
        (gen['speechConfig'] as Map).containsKey('multiSpeakerVoiceConfig'),
        isFalse,
      );
    },
  );

  test(
    'WAV (RIFF) reply is returned AS-IS -- single header, no crackling',
    () async {
      final wav = pcmToWav(
        Uint8List.fromList(List<int>.filled(100, 7)),
        sampleRate: 24000,
      );
      final mock = MockClient((_) async => _audio(wav));
      final out = await GeminiTts(
        apiKey: 'k',
        client: mock,
      ).synthesize(text: 'x', voice: SesliVoice.aoede);
      expect(out, wav);
      expect(latin1.decode(out).split('RIFF').length - 1, 1);
    },
  );

  test(
    'raw PCM reply (audio/L16;rate=24000) is wrapped with a WAV header',
    () async {
      final pcm = [5, 0, 6, 0];
      final mock = MockClient(
        (_) async => _audio(pcm, mime: 'audio/L16;codec=pcm;rate=24000'),
      );
      final out = await GeminiTts(
        apiKey: 'k',
        client: mock,
      ).synthesize(text: 'x', voice: SesliVoice.wavenetC);
      expect(out, pcmToWav(Uint8List.fromList(pcm), sampleRate: 24000));
    },
  );

  test(
    'HTTP != 200 -> GeminiTtsException, the server message is carried over',
    () async {
      final mock = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'message': 'quota exceeded'},
          }),
          429,
        ),
      );
      expect(
        () => GeminiTts(
          apiKey: 'k',
          client: mock,
        ).synthesize(text: 'x', voice: SesliVoice.aoede),
        throwsA(
          isA<GeminiTtsException>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('429'), contains('quota exceeded')),
          ),
        ),
      );
    },
  );

  test('reply without audio data -> GeminiTtsException', () async {
    for (final bad in <Object>[
      {'candidates': <Object>[]},
      {
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'text'},
              ],
            },
          },
        ],
      },
      'plain text',
    ]) {
      final mock = MockClient(
        (_) async => http.Response(bad is String ? bad : jsonEncode(bad), 200),
      );
      await expectLater(
        GeminiTts(
          apiKey: 'k',
          client: mock,
        ).synthesize(text: 'x', voice: SesliVoice.aoede),
        throwsA(isA<GeminiTtsException>()),
        reason: '$bad',
      );
    }
  });
}
