// Oracle test (2026-09-28, Gemini migration): shared LLM client
// (lib/io/llm_client.dart). Single source of truth: Gemini (OpenAI-compatible) endpoint + model +
// key header + reasoning_effort:"low" on every request (measured: the default thinking-token budget
// cut the text short). On 429, up to 2 retries with 5 s / 10 s backoff.
// Sleep is injected -> the test does not really wait.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sesli_kitap/io/llm_client.dart';

void main() {
  test(
    'constants: Gemini (OpenAI-compatible) endpoint + gemini-3.8-flash model',
    () {
      expect(
        llmChatEndpoint.toString(),
        'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
      );
      expect(llmModel, 'gemini-3.8-flash');
      expect(llmAuditorModel, 'gemini-3.8-flash');
      expect(llmRetryDelays, const [
        Duration(seconds: 5),
        Duration(seconds: 10),
      ]);
    },
  );

  test(
    'request: Gemini endpoint, Bearer key, default model + reasoning_effort:low are added to the body',
    () async {
      late http.Request captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response('{}', 200);
      });
      final resp = await postChatCompletion(
        mock,
        apiKey: 'gm-k',
        body: const {'temperature': 0},
      );
      expect(resp.statusCode, 200);
      expect(captured.url, llmChatEndpoint);
      expect(captured.headers['Authorization'], 'Bearer gm-k');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], llmModel);
      expect(body['temperature'], 0);
      expect(
        body['reasoning_effort'],
        'low',
        reason:
            'measured: without reasoning_effort the default thinking-token budget '
            'cuts the text off after ~3 turns',
      );
    },
  );

  test(
    'even if reasoning_effort is passed explicitly in the body, it is OVERRIDDEN to "low" (single-source contract)',
    () async {
      late http.Request captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response('{}', 200);
      });
      await postChatCompletion(
        mock,
        apiKey: 'k',
        body: const {'reasoning_effort': 'high'},
      );
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['reasoning_effort'], 'low');
    },
  );

  test('the model parameter overrides the default', () async {
    late http.Request captured;
    final mock = MockClient((req) async {
      captured = req;
      return http.Response('{}', 200);
    });
    await postChatCompletion(
      mock,
      apiKey: 'k',
      body: const {},
      model: 'other/model',
    );
    expect((jsonDecode(captured.body) as Map)['model'], 'other/model');
  });

  test('429 -> wait 5 s, retry; second attempt 200', () async {
    var calls = 0;
    final slept = <Duration>[];
    final mock = MockClient((req) async {
      calls++;
      return http.Response('limit', calls == 1 ? 429 : 200);
    });
    final resp = await postChatCompletion(
      mock,
      apiKey: 'k',
      body: const {},
      sleep: (d) async => slept.add(d),
    );
    expect(resp.statusCode, 200);
    expect(calls, 2);
    expect(slept, const [Duration(seconds: 5)]);
  });

  test(
    'persistent 429 -> 3 attempts (5 s + 10 s), last 429 response is returned',
    () async {
      var calls = 0;
      final slept = <Duration>[];
      final mock = MockClient((req) async {
        calls++;
        return http.Response('limit', 429);
      });
      final resp = await postChatCompletion(
        mock,
        apiKey: 'k',
        body: const {},
        sleep: (d) async => slept.add(d),
      );
      expect(resp.statusCode, 429);
      expect(calls, 3);
      expect(slept, const [Duration(seconds: 5), Duration(seconds: 10)]);
    },
  );

  test('non-429 error (500) is not retried', () async {
    var calls = 0;
    final mock = MockClient((req) async {
      calls++;
      return http.Response('err', 500);
    });
    final resp = await postChatCompletion(
      mock,
      apiKey: 'k',
      body: const {},
      sleep: (d) async => fail('must not sleep'),
    );
    expect(resp.statusCode, 500);
    expect(calls, 1);
  });
}
