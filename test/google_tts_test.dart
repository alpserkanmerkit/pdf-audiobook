// Oracle test (slice-2): GoogleTts Cloud TTS REST provider.
// The lib/io HTTP body is outside the coverage gate -> body-assert + error-chain are
// pinned with MockClient (azure_tts REST pattern + llm_discussion_test MockClient pattern).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sesli_kitap/io/google_tts.dart';
import 'package:sesli_kitap/src/voices.dart';

void main() {
  test(
    'synthesize body: tr-TR + voice name + MP3 + speakingRate; base64 -> bytes',
    () async {
      Map<String, dynamic>? body;
      String? url;
      Map<String, String>? headers;
      final mock = MockClient((req) async {
        url = req.url.toString();
        headers = Map<String, String>.of(req.headers);
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'audioContent': base64Encode([1, 2, 3, 4]),
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final bytes = await GoogleTts(
        apiKey: 'test-key',
        client: mock,
      ).synthesize(text: 'merhaba', voice: SesliVoice.wavenetB, rate: 1.25);

      expect(bytes, [1, 2, 3, 4]);
      expect(url, contains('text:synthesize'));
      // FAZ3a S3: the key is NOT carried in the URL query -- the network layer embeds the
      // ClientException's uri in its message, and the key would leak into logs.
      // The key travels only in the X-Goog-Api-Key header.
      expect(url, isNot(contains('key=')));
      final apiKeyHeaders = headers!.entries
          .where((e) => e.key.toLowerCase() == 'x-goog-api-key')
          .map((e) => e.value)
          .toList();
      expect(apiKeyHeaders, ['test-key']);
      expect(body!['input'], {'text': 'merhaba'});
      expect((body!['voice'] as Map)['languageCode'], 'tr-TR');
      expect((body!['voice'] as Map)['name'], 'tr-TR-Wavenet-B');
      expect((body!['audioConfig'] as Map)['audioEncoding'], 'MP3');
      expect((body!['audioConfig'] as Map)['speakingRate'], 1.25);
    },
  );

  // Phase 2 (English TTS support): languageCode is NO LONGER a fixed 'tr-TR' --
  // it is derived from the voice's own locale (localeCodeOf). When an English voice is
  // chosen, the body must also carry en-US (before, it always sent tr-TR, which was wrong).
  test(
    'English voice selected -> body carries en-US (tr-TR hard-coding removed)',
    () async {
      Map<String, dynamic>? body;
      final mock = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'audioContent': base64Encode([1, 2, 3]),
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      await GoogleTts(
        apiKey: 'test-key',
        client: mock,
      ).synthesize(text: 'hello', voice: SesliVoice.enWavenetD);

      expect((body!['voice'] as Map)['languageCode'], 'en-US');
      expect((body!['voice'] as Map)['name'], 'en-US-Wavenet-D');
    },
  );

  test('HTTP != 200 -> GoogleTtsException', () async {
    final mock = MockClient((req) async => http.Response('err', 403));
    await expectLater(
      GoogleTts(
        apiKey: 'k',
        client: mock,
      ).synthesize(text: 't', voice: SesliVoice.aoede),
      throwsA(isA<GoogleTtsException>()),
    );
  });

  test('empty audioContent -> GoogleTtsException', () async {
    final mock = MockClient(
      (req) async => http.Response(jsonEncode({'audioContent': ''}), 200),
    );
    await expectLater(
      GoogleTts(
        apiKey: 'k',
        client: mock,
      ).synthesize(text: 't', voice: SesliVoice.aoede),
      throwsA(isA<GoogleTtsException>()),
    );
  });

  // Bug-G (2026-07-04, device finding): on the device, provider='google' +
  // voice=tr-TR-AhmetNeural (Microsoft family) was saved. GoogleTts put the raw
  // voiceId(voice) into the body -> curl proof: Google returns 400
  // "Voice 'tr-TR-AhmetNeural' does not exist. Is it misspelled?"
  // synthesize() must put a Google-VALID voice.name in the body (mapped via googleVoiceId)
  // -- TODAY the raw AhmetNeural goes out, so this test starts RED.
  test(
    'Microsoft-family voice (ahmet) -> the voice.name in the body is mapped to a '
    'Google-valid name (NOT the raw tr-TR-AhmetNeural)',
    () async {
      Map<String, dynamic>? body;
      final mock = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'audioContent': base64Encode([1, 2, 3]),
          }),
          200,
        );
      });
      await GoogleTts(
        apiKey: 'k',
        client: mock,
      ).synthesize(text: 'merhaba', voice: SesliVoice.ahmet);

      expect(
        (body!['voice'] as Map)['name'],
        isNot('tr-TR-AhmetNeural'),
        reason:
            'Google does not know this name (curl: 400 "does not exist"); '
            'it must be mapped to a Google-compatible equivalent',
      );
      expect((body!['voice'] as Map)['name'], 'tr-TR-Wavenet-B');
    },
  );

  test(
    'Microsoft-family voice (emel) -> the voice.name in the body is mapped to a '
    'Google-valid name',
    () async {
      Map<String, dynamic>? body;
      final mock = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'audioContent': base64Encode([1, 2, 3]),
          }),
          200,
        );
      });
      await GoogleTts(
        apiKey: 'k',
        client: mock,
      ).synthesize(text: 'merhaba', voice: SesliVoice.emel);

      expect((body!['voice'] as Map)['name'], isNot('tr-TR-EmelNeural'));
      expect((body!['voice'] as Map)['name'], 'tr-TR-Chirp3-HD-Aoede');
    },
  );

  // Bug-G secondary cause: the Google text:synthesize input is limited to 5000 UTF-8 bytes
  // (curl proof: 5001 bytes -> 400 "...longer than the limit of 5000 bytes..."; 4900 bytes
  // -> 200 OK). Long pages (e.g. p640) may exceed this limit. synthesize() must split the
  // text and synthesize the parts in order.
  group('long-text splitting (Bug-G secondary cause)', () {
    test(
      'SHORT text (under the limit) -> ONE request, body IDENTICAL to before '
      '(behavior-identity pin -- the fix must change NOTHING for short texts)',
      () async {
        var callCount = 0;
        String? seenText;
        final mock = MockClient((req) async {
          callCount++;
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          seenText = (body['input'] as Map)['text'] as String;
          return http.Response(
            jsonEncode({
              'audioContent': base64Encode([9, 9, 9]),
            }),
            200,
          );
        });
        final bytes = await GoogleTts(
          apiKey: 'k',
          client: mock,
        ).synthesize(text: 'Kisa bir metin.', voice: SesliVoice.wavenetB);

        expect(callCount, 1, reason: 'a short text must go in ONE request');
        expect(seenText, 'Kisa bir metin.');
        expect(bytes, [9, 9, 9]);
      },
    );

    test('multi-sentence text OVER 4500 UTF-8 bytes -> MANY requests, EACH request body '
        '<= 4500 bytes, the returned audio parts are CONCATENATED', () async {
      // sentence ~61 UTF-8 bytes; 82 repeats ~5002 bytes -- exceeds Google's RAW
      // 5000-byte limit as well as the 4500 safety-margin limit.
      const sentence = 'Türkçe şğüöçİı karakterli örnek bir cümle burada. ';
      final longText = sentence * 82;

      final requestBodies = <Map<String, dynamic>>[];
      final mock = MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        requestBodies.add(body);
        return http.Response(
          jsonEncode({
            'audioContent': base64Encode([requestBodies.length]),
          }),
          200,
        );
      });

      final bytes = await GoogleTts(
        apiKey: 'k',
        client: mock,
      ).synthesize(text: longText, voice: SesliVoice.wavenetB);

      expect(
        requestBodies.length,
        greaterThan(1),
        reason: 'a long text must be split into MANY requests',
      );
      for (final body in requestBodies) {
        final text = (body['input'] as Map)['text'] as String;
        expect(
          utf8.encode(text).length,
          lessThanOrEqualTo(4500),
          reason:
              'each request body must be <= 4500 bytes, with a safety margin',
        );
      }
      // The returned audio bytes must be the SEQUENTIAL join of the single-byte markers
      // each request returned (MP3 frames may be concatenated one after another).
      expect(bytes, List<int>.generate(requestBodies.length, (i) => i + 1));
    });

    test('in a split request EVERY PART carries the same speed (rate)', () async {
      const sentence = 'Türkçe şğüöçİı karakterli örnek bir cümle burada. ';
      final longText = sentence * 82;
      final seenRates = <num>[];
      final mock = MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        seenRates.add((body['audioConfig'] as Map)['speakingRate'] as num);
        return http.Response(
          jsonEncode({
            'audioContent': base64Encode([1]),
          }),
          200,
        );
      });
      await GoogleTts(
        apiKey: 'k',
        client: mock,
      ).synthesize(text: longText, voice: SesliVoice.wavenetB, rate: 1.25);
      expect(
        seenRates.length,
        greaterThan(1),
        reason:
            'this text must be split into multiple requests (precondition of the rate test)',
      );
      expect(seenRates.toSet(), {1.25});
    });
  });
}
