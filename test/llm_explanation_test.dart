// Oracle test: LlmExplanation IO/HTTP/parse error chain.
// lib/io HTTP body is outside the coverage gate -> body-assert + error chain can only be pinned by a MockClient test
// (llm_discussion_test pattern).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sesli_kitap/io/llm_explanation.dart';

http.Response _ok(String content) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': content},
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test(
    'fetch: body uses v4-flash + json_object + target in the prompt; returns the explanation',
    () async {
      Map<String, dynamic>? body;
      final mock = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return _ok('{"aciklama":"this is a test"}');
      });
      final result = await LlmExplanation(apiKey: 'test-key', client: mock)
          .fetch(
            target: 'exampleword',
            isWord: true,
            sentence: 'This sentence contains exampleword.',
            contextText: 'Context text.',
          );
      expect(result, 'this is a test');
      expect(body, isNotNull);
      expect(body!['model'], 'gemini-3.8-flash');
      expect(body!.containsKey('thinking'), isFalse);
      expect(body!['reasoning_effort'], 'low');
      expect(body!['temperature'], 0);
      expect(body!['response_format'], {'type': 'json_object'});
      final user = ((body!['messages'] as List)[1] as Map)['content'] as String;
      expect(user, contains('exampleword'));
      expect(user, contains('Context text.'));
    },
  );

  test('fetch: HTTP 500 -> LlmExplanationException', () async {
    final mock = MockClient((req) async => http.Response('exploded', 500));
    expect(
      () => LlmExplanation(
        apiKey: 'k',
        client: mock,
      ).fetch(target: 'x', isWord: true, sentence: 's', contextText: 'c'),
      throwsA(isA<LlmExplanationException>()),
    );
  });

  test(
    'fetch: contract violation (no explanation field) -> LlmExplanationException',
    () async {
      final mock = MockClient((req) async => _ok('{"wrong":"field"}'));
      expect(
        () => LlmExplanation(
          apiKey: 'k',
          client: mock,
        ).fetch(target: 'x', isWord: false, sentence: 's', contextText: 'c'),
        throwsA(isA<LlmExplanationException>()),
      );
    },
  );

  test('fetch: network error -> LlmExplanationException', () async {
    final mock = MockClient(
      (req) async => throw http.ClientException('dropped'),
    );
    expect(
      () => LlmExplanation(
        apiKey: 'k',
        client: mock,
      ).fetch(target: 'x', isWord: true, sentence: 's', contextText: 'c'),
      throwsA(isA<LlmExplanationException>()),
    );
  });
}
