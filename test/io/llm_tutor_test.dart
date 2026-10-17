// Oracle RED test (2026-10-05, "private tutor book" Slice-1).
// Spec: internal design note §3.6 (HTTP transport, lib/io/llm_tutor.dart).
//
// Pinned contract:
// - Single provider path: llm_client.postChatCompletion -> llmChatEndpoint, llmModel.
// - F9 rule: an error (network / timeout / HTTP != 200 / malformed body) is thrown
//   as a VISIBLE LlmTutorException; no silent switch to another model or endpoint,
//   and no hidden retry (exactly 1 request on a 500).
// - The text shown to the user is English; no class name is printed.
// - LlmTutor.complete matches the TutorLlm signature that TutorSession expects.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sesli_kitap/io/llm_client.dart';
import 'package:sesli_kitap/io/llm_tutor.dart';

http.Response _ok(Object? body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object?> _completion(Object? content) => {
  'choices': [
    {
      'message': {'role': 'assistant', 'content': content},
    },
  ],
};

Future<String> _errorText(MockClient mock) async {
  try {
    await LlmTutor(apiKey: 'k', client: mock).complete(system: 's', user: 'u');
  } on LlmTutorException catch (e) {
    return e.toString();
  }
  fail('LlmTutorException bekleniyordu');
}

void main() {
  test(
    'matches the TutorLlm signature (compile-time link) and returns the content when called',
    () async {
      final mock = MockClient((_) async => _ok(_completion('{"a":1}')));
      final llm = LlmTutor(apiKey: 'k', client: mock).complete;
      expect(await llm(system: 's', user: 'u'), '{"a":1}');
    },
  );

  test(
    'success: content returned as-is; a single request with the correct endpoint/model/messages',
    () async {
      final requests = <http.Request>[];
      final mock = MockClient((req) async {
        requests.add(req);
        return _ok(_completion('{"anlatim":"Ğüşiöç"}'));
      });
      final out = await LlmTutor(
        apiKey: 'key',
        client: mock,
      ).complete(system: 'SYSTEM', user: 'USER');
      expect(out, '{"anlatim":"Ğüşiöç"}');
      expect(requests.length, 1);
      final req = requests.single;
      expect(req.url, llmChatEndpoint);
      expect(req.headers['Authorization'], 'Bearer key');
      final body =
          jsonDecode(utf8.decode(req.bodyBytes)) as Map<String, Object?>;
      expect(body['model'], llmModel);
      expect(body['messages'], [
        {'role': 'system', 'content': 'SYSTEM'},
        {'role': 'user', 'content': 'USER'},
      ]);
      expect(body['response_format'], {'type': 'json_object'});
    },
  );

  test(
    'HTTP 500: visible error, exactly 1 request (no hidden retry)',
    () async {
      var count = 0;
      final mock = MockClient((_) async {
        count++;
        return http.Response('server down', 500);
      });
      final text = await _errorText(mock);
      expect(text, 'The AI server returned an error (HTTP 500).');
      expect(count, 1);
    },
  );

  test('HTTP 403: same format, code in the text', () async {
    final mock = MockClient((_) async => http.Response('forbidden', 403));
    expect(
      await _errorText(mock),
      'The AI server returned an error (HTTP 403).',
    );
  });

  test('network error: connection message, exactly 1 request', () async {
    var count = 0;
    final mock = MockClient((_) async {
      count++;
      throw http.ClientException('Failed host lookup');
    });
    expect(
      await _errorText(mock),
      'Could not connect to the AI server. '
      'Check your internet connection and try again.',
    );
    expect(count, 1);
  });

  test("timeout: llm_client's message as-is", () async {
    final mock = MockClient(
      (_) async => throw LlmTimeoutException(const Duration(seconds: 90)),
    );
    expect(
      await _errorText(mock),
      'The AI server did not respond within 90 seconds. '
      'Check your internet connection and try again.',
    );
  });

  test('malformed bodies: unexpected-response error', () async {
    final bodies = <http.Response>[
      http.Response('not json', 200),
      _ok([1, 2]),
      _ok({'choices': <Object?>[]}),
      _ok({'choices': 'x'}),
      _ok({
        'choices': ['x'],
      }),
      _ok(_completion(null)),
      _ok(_completion(42)),
      _ok(_completion('   ')),
    ];
    for (final resp in bodies) {
      final mock = MockClient((_) async => resp);
      expect(
        await _errorText(mock),
        'Unexpected response from the AI server.',
        reason: resp.body,
      );
    }
  });
}
