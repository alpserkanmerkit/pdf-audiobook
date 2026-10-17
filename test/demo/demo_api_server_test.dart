// DemoApiServer + DemoHttpOverrides: the real postChatCompletion / GoogleTts /
// GeminiTts / WebSocket paths go to a loopback fake server; NO request
// leaves the loopback interface.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sesli_kitap/demo/demo_api_server.dart';
import 'package:sesli_kitap/demo/demo_llm_router.dart';
import 'package:sesli_kitap/demo/demo_wav.dart';
import 'package:sesli_kitap/io/edge_tts.dart';
import 'package:sesli_kitap/io/gemini_tts.dart';
import 'package:sesli_kitap/io/google_tts.dart';
import 'package:sesli_kitap/io/llm_client.dart';
import 'package:sesli_kitap/src/voices.dart';

void main() {
  late DemoApiServer server;
  late DemoLlmRouter router;
  HttpOverrides? previous;

  setUp(() async {
    router = DemoLlmRouter();
    server = await DemoApiServer.start(chatResponder: router.respond);
    previous = HttpOverrides.current;
    HttpOverrides.global = DemoHttpOverrides(server.port);
  });
  tearDown(() async {
    HttpOverrides.global = previous;
    await server.close();
  });

  test(
    'chat: the DeepSeek URL goes to loopback, the original host is recorded',
    () async {
      final client = http.Client();
      addTearDown(client.close);
      final resp = await postChatCompletion(
        client,
        access: LlmAccess.single(LlmProvider.deepseek, 'demo-anahtar-yok'),
        body: {
          'messages': [
            {
              'role': 'system',
              'content':
                  'You will be given the raw text of a scanned Turkish book page.',
            },
            {'role': 'user', 'content': 'Merhaba dünya'},
          ],
        },
      );
      expect(resp.statusCode, 200);
      final choices =
          (jsonDecode(utf8.decode(resp.bodyBytes))
                  as Map<String, dynamic>)['choices']
              as List<dynamic>;
      final message =
          (choices.first as Map<String, dynamic>)['message']
              as Map<String, dynamic>;
      final content = message['content'];
      expect(jsonDecode(content as String), {'metin': 'Merhaba dünya'});
      final rec = server.chatRequests.single;
      expect(rec.originalHost, 'api.deepseek.com');
      expect(rec.authorization, 'Bearer demo-anahtar-yok');
      expect(server.unrouted, isEmpty);
    },
  );

  test('Google TTS: RIFF/WAVE, duration ~ characters/45 s', () async {
    final text = 'a' * 900; // 20 s
    final bytes = await GoogleTts(
      apiKey: 'demo-anahtar-yok',
    ).synthesize(text: text, voice: SesliVoice.ahmet);
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(wavDuration(bytes)!.inSeconds, closeTo(20, 1));
    expect(
      server.ttsRequests.single.originalHost,
      'texttospeech.googleapis.com',
    );
    expect(
      server.ttsRequests.single.headers['x-goog-api-key'],
      'demo-anahtar-yok',
    );
  });

  test(
    'Gemini TTS: raw PCM is wrapped, short text has a 1.5 s lower bound',
    () async {
      final bytes = await GeminiTts(
        apiKey: 'demo-anahtar-yok',
      ).synthesize(text: 'Kısa.', voice: SesliVoice.aoede);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(wavDuration(bytes)!.inMilliseconds, closeTo(1500, 20));
      expect(
        server.geminiTtsRequests.single.originalHost,
        'generativelanguage.googleapis.com',
      );
      expect(server.unrouted, isEmpty);
    },
  );

  test('every request to a real host returns to loopback (no leak)', () async {
    final client = http.Client();
    addTearDown(client.close);
    final r = await client
        .get(Uri.https('example.com', '/gizli-yol'))
        .timeout(const Duration(seconds: 5));
    expect(
      r.statusCode,
      404,
      reason: 'the fake server returns 404 for unknown paths',
    );
    expect(server.requests.single.originalHost, 'example.com');
    expect(server.unrouted, hasLength(1));
  });

  test(
    'the real EdgeTts WebSocket also falls to loopback (does not reach the real server)',
    () async {
      // EdgeTts customClient: connects via HttpClient() -> the DemoHttpOverrides
      // client is valid. A raw WebSocket.connect uses dart:io's STATIC shared
      // client; the flutter test harness creates it beforehand, so redirection
      // does not work there -- the test uses the app's own class.
      Object? error;
      try {
        await EdgeTts()
            .synthesize(text: 'Merhaba', voice: SesliVoice.ahmet)
            .timeout(const Duration(seconds: 8));
      } on Object catch (e) {
        error = e;
      }
      expect(
        error,
        isNotNull,
        reason: 'the fake server does not upgrade to WebSocket',
      );
      expect(
        server.requests,
        isNotEmpty,
        reason: 'request must reach loopback',
      );
      expect(
        server.requests.map((r) => r.originalHost),
        everyElement('speech.platform.bing.com'),
      );
      expect(server.unrouted, isNotEmpty);
    },
  );

  test(
    'an unrecognized chat prompt is written to unrouted and a safe fallback is returned',
    () async {
      final client = http.Client();
      addTearDown(client.close);
      await postChatCompletion(
        client,
        access: LlmAccess.single(LlmProvider.gemini, 'demo-anahtar-yok'),
        body: {
          'messages': [
            {'role': 'system', 'content': 'bilinmeyen istem'},
            {'role': 'user', 'content': 'x'},
          ],
        },
      );
      expect(server.unrouted, hasLength(1));
      expect(router.unrouted, hasLength(1));
    },
  );
}
