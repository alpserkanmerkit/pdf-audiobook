// Oracle test (2026-09-28, audit finding "no HTTP timeout"):
// If LLM and TTS requests hang, the user waited FOREVER.
// Contract:
// - LLM (postChatCompletion): 90 s. Measured: a discussion call takes 17-18 s
//   (gemini-3.8-flash, 3000 token cap); "long" mode with 6000 tokens is ~2x
//   (inference). 90 s = ~2.5x the longest estimate -> a legitimately slow
//   response is NOT cut off.
// - TTS (GeminiTts / GoogleTts): 30 s. Measured: flash-lite-tts takes ~10-12 s
//   per line; live probe 2.8-3.4 s. 30 s = ~2.5x the longest measurement.
// The text shown to the user when the time runs out is Turkish and states the
// reason. Real time is NOT waited for: the fake clock of testWidgets
// (tester.pump(duration)) is advanced instead, so no new dependency is needed.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sesli_kitap/io/gemini_tts.dart';
import 'package:sesli_kitap/io/google_tts.dart';
import 'package:sesli_kitap/io/llm_client.dart';
import 'package:sesli_kitap/io/llm_discussion.dart';
import 'package:sesli_kitap/src/voices.dart';

/// A server that never responds (hanging connection).
MockClient _hangingClient() =>
    MockClient((_) => Completer<http.Response>().future);

/// A slow server that returns [response] after [after].
MockClient _slowClient(Duration after, http.Response response) =>
    MockClient((_) => Future.delayed(after, () => response));

/// Watches the result of [start] on fake time: no result until the [before]
/// mark, and an error at the [after] mark. Returns that error.
Future<Object> _errorAfterTimeout(
  WidgetTester tester,
  Future<Object?> Function() start, {
  required Duration before,
  required Duration after,
}) async {
  Object? error;
  var completed = false;
  unawaited(
    start().then<void>(
      (_) {
        completed = true;
      },
      onError: (Object e) {
        error = e;
      },
    ),
  );
  await tester.pump(before);
  expect(
    completed,
    isFalse,
    reason: 'request must not complete before the timeout',
  );
  expect(error, isNull, reason: 'no error must be raised before the timeout');
  await tester.pump(after - before);
  expect(completed, isFalse);
  expect(
    error,
    isNotNull,
    reason: 'request must fail with an error once the timeout passes',
  );
  return error!;
}

/// A slow-but-in-time response must still succeed. The limit must not be too
/// short: it must not cut off the measured legitimate duration.
Future<Object?> _resultWithin(
  WidgetTester tester,
  Future<Object?> Function() start,
  Duration elapse,
) async {
  Object? value;
  Object? error;
  unawaited(
    start().then<void>(
      (v) {
        value = v;
      },
      onError: (Object e) {
        error = e;
      },
    ),
  );
  await tester.pump(elapse);
  expect(
    error,
    isNull,
    reason: 'a response within the time window must not count as an error',
  );
  return value;
}

http.Response _geminiAudio() => http.Response(
  jsonEncode({
    'candidates': [
      {
        'content': {
          'parts': [
            {
              'inlineData': {
                'mimeType': 'audio/L16;codec=pcm;rate=24000',
                'data': base64Encode([1, 2, 3, 4]),
              },
            },
          ],
        },
      },
    ],
  }),
  200,
);

void main() {
  group('LLM (postChatCompletion) timeout', () {
    testWidgets(
      'a hanging request throws an Exception with an English message after 90 s',
      (tester) async {
        final e = await _errorAfterTimeout(
          tester,
          () => postChatCompletion(
            _hangingClient(),
            apiKey: 'k',
            body: const {'messages': <Object>[]},
          ),
          before: const Duration(seconds: 89),
          after: const Duration(seconds: 91),
        );
        // Exception (NOT Error): all callers catch with `on Exception`
        // (llm_discussion / _cleanOrFallback / auditor fail-open chain).
        expect(e, isA<Exception>());
        expect(e.toString(), contains('within 90 seconds'));
        expect(e.toString(), contains('did not respond'));
      },
    );

    testWidgets(
      'a legitimate 60 s response is NOT cut off (measured 17-18 s x 3)',
      (tester) async {
        final resp = await _resultWithin(
          tester,
          () => postChatCompletion(
            _slowClient(const Duration(seconds: 60), http.Response('{}', 200)),
            apiKey: 'k',
            body: const {},
          ),
          const Duration(seconds: 61),
        );
        expect((resp! as http.Response).statusCode, 200);
      },
    );

    testWidgets(
      'if a discussion request hangs, the error reason shown to the user is in '
      'English (LlmDiscussionException)',
      (tester) async {
        final e = await _errorAfterTimeout(
          tester,
          () => LlmDiscussion(
            apiKey: 'k',
            client: _hangingClient(),
          ).generate('topic'),
          before: const Duration(seconds: 89),
          after: const Duration(seconds: 91),
        );
        expect(e, isA<LlmDiscussionException>());
        expect(e.toString(), contains('did not respond within 90 seconds'));
      },
    );
  });

  group('TTS timeout', () {
    testWidgets(
      'GeminiTts: a hanging request throws GeminiTtsException after 30 s',
      (tester) async {
        final e = await _errorAfterTimeout(
          tester,
          () => GeminiTts(
            apiKey: 'k',
            client: _hangingClient(),
          ).synthesize(text: 'merhaba', voice: SesliVoice.ahmet),
          before: const Duration(seconds: 29),
          after: const Duration(seconds: 31),
        );
        expect(e, isA<GeminiTtsException>());
        expect(
          e.toString(),
          contains('voice server did not respond within 30 seconds'),
        );
      },
    );

    testWidgets(
      'GeminiTts: a legitimate 20 s response is NOT cut off (measured 10-12 s)',
      (tester) async {
        final bytes = await _resultWithin(
          tester,
          () => GeminiTts(
            apiKey: 'k',
            client: _slowClient(const Duration(seconds: 20), _geminiAudio()),
          ).synthesize(text: 'merhaba', voice: SesliVoice.ahmet),
          const Duration(seconds: 21),
        );
        expect(bytes, isNotNull);
      },
    );

    testWidgets(
      'GoogleTts: a hanging request throws GoogleTtsException after 30 s',
      (tester) async {
        final e = await _errorAfterTimeout(
          tester,
          () => GoogleTts(
            apiKey: 'k',
            client: _hangingClient(),
          ).synthesize(text: 'merhaba', voice: SesliVoice.ahmet),
          before: const Duration(seconds: 29),
          after: const Duration(seconds: 31),
        );
        expect(e, isA<GoogleTtsException>());
        expect(
          e.toString(),
          contains('voice server did not respond within 30 seconds'),
        );
      },
    );

    testWidgets('GoogleTts: a legitimate 20 s response is NOT cut off', (
      tester,
    ) async {
      final bytes = await _resultWithin(
        tester,
        () => GoogleTts(
          apiKey: 'k',
          client: _slowClient(
            const Duration(seconds: 20),
            http.Response(
              jsonEncode({
                'audioContent': base64Encode([9, 9]),
              }),
              200,
            ),
          ),
        ).synthesize(text: 'merhaba', voice: SesliVoice.ahmet),
        const Duration(seconds: 21),
      );
      expect(bytes, [9, 9]);
    });
  });
}
