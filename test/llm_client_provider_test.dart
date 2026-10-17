// Provider consolidation (P4a, decision 0610 #58): the shared LLM client goes to the endpoint/model of the chosen provider;
// on the "all" choice, if a provider fails (non-200 response or network/timeout error) it moves on to the next one.
// No network: MockClient. Keys are fake.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sesli_kitap/io/auditor.dart';
import 'package:sesli_kitap/io/llm_client.dart';
import 'package:sesli_kitap/io/llm_quiz.dart';

const _ok = '{"choices":[{"message":{"content":"{}"}}]}';

void main() {
  test('DeepSeek: official endpoint, Bearer key, v4-flash, thinking disabled, '
      'NO reasoning_effort', () async {
    late http.Request captured;
    final mock = MockClient((req) async {
      captured = req;
      return http.Response(_ok, 200);
    });
    final resp = await postChatCompletion(
      mock,
      access: LlmAccess.single(LlmProvider.deepseek, 'ds-sahte'),
      body: const {'temperature': 0},
    );
    expect(resp.statusCode, 200);
    expect(
      captured.url.toString(),
      'https://api.deepseek.com/chat/completions',
    );
    expect(captured.headers['Authorization'], 'Bearer ds-sahte');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['model'], 'deepseek-v4-flash');
    expect(body['thinking'], {'type': 'disabled'});
    expect(body.containsKey('reasoning_effort'), isFalse);
    expect(body['temperature'], 0);
  });

  test('NVIDIA: integrate endpoint + deepseek-v4.1-flash', () async {
    late http.Request captured;
    final mock = MockClient((req) async {
      captured = req;
      return http.Response(_ok, 200);
    });
    await postChatCompletion(
      mock,
      access: LlmAccess.single(LlmProvider.nvidia, 'nv-sahte'),
      body: const {},
    );
    expect(
      captured.url.toString(),
      'https://integrate.api.nvidia.com/v1/chat/completions',
    );
    expect(captured.headers['Authorization'], 'Bearer nv-sahte');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['model'], 'deepseek-ai/deepseek-v4.1-flash');
  });

  test("auditor role picks the provider's auditor model", () async {
    final models = <String>[];
    final mock = MockClient((req) async {
      models.add((jsonDecode(req.body) as Map)['model'] as String);
      return http.Response(_ok, 200);
    });
    for (final p in LlmProvider.values) {
      await postChatCompletion(
        mock,
        access: LlmAccess.single(p, 'k'),
        body: const {},
        auditor: true,
      );
    }
    expect(models, [
      'gemini-3.8-flash',
      'deepseek-v4-pro',
      'nvidia/nemotron-3-ultra-550b-a55b',
    ]);
  });

  test(
    '"all": first provider returns 500 -> second is tried, its response is returned',
    () async {
      final hosts = <String>[];
      final mock = MockClient((req) async {
        hosts.add(req.url.host);
        if (req.url.host == 'generativelanguage.googleapis.com') {
          return http.Response('err', 500);
        }
        return http.Response(_ok, 200);
      });
      final resp = await postChatCompletion(
        mock,
        access: LlmAccess.fromSettings(
          choice: 'all',
          geminiKey: 'g',
          deepseekKey: 'd',
          nvidiaKey: 'n',
        ),
        body: const {},
      );
      expect(resp.statusCode, 200);
      expect(hosts, ['generativelanguage.googleapis.com', 'api.deepseek.com']);
    },
  );

  test(
    '"all": network error -> next one; if all fail, the last response is returned',
    () async {
      final hosts = <String>[];
      final mock = MockClient((req) async {
        hosts.add(req.url.host);
        if (req.url.host == 'api.deepseek.com') {
          throw http.ClientException('connection dropped');
        }
        return http.Response('unauthorized', 401);
      });
      final resp = await postChatCompletion(
        mock,
        access: LlmAccess.fromSettings(
          choice: 'all',
          deepseekKey: 'd',
          nvidiaKey: 'n',
        ),
        body: const {},
      );
      expect(hosts, ['api.deepseek.com', 'integrate.api.nvidia.com']);
      expect(resp.statusCode, 401);
    },
  );

  test(
    '"all": if the last provider also has a network error, the error is rethrown',
    () async {
      final mock = MockClient((req) async {
        throw http.ClientException('none');
      });
      await expectLater(
        postChatCompletion(
          mock,
          access: LlmAccess.fromSettings(
            choice: 'all',
            deepseekKey: 'd',
            nvidiaKey: 'n',
          ),
          body: const {},
        ),
        throwsA(isA<http.ClientException>()),
      );
    },
  );

  test('no key -> no network call, Turkish error message', () async {
    final mock = MockClient((req) async => fail('network must not be called'));
    await expectLater(
      postChatCompletion(
        mock,
        access: LlmAccess.fromSettings(choice: 'deepseek'),
        body: const {},
      ),
      throwsA(
        isA<LlmNotConfiguredException>().having(
          (e) => e.toString(),
          'message',
          contains('API key'),
        ),
      ),
    );
  });

  test(
    'LlmQuiz access goes to the DeepSeek endpoint (end-to-end propagation)',
    () async {
      final hosts = <String>[];
      final mock = MockClient((req) async {
        hosts.add(req.url.host);
        return http.Response('err', 500);
      });
      final quiz = LlmQuiz(
        access: LlmAccess.single(LlmProvider.deepseek, 'd'),
        client: mock,
      );
      await expectLater(
        quiz.fetch(bookText: 'A paragraph of text.', kaynak: 'k'),
        throwsA(isA<LlmQuizException>()),
      );
      expect(hosts, ['api.deepseek.com']);
    },
  );

  test('auditClean access uses the NVIDIA auditor model', () async {
    String? model;
    final mock = MockClient((req) async {
      model = (jsonDecode(req.body) as Map)['model'] as String;
      return http.Response('err', 500);
    });
    final verdict = await auditClean(
      access: LlmAccess.single(LlmProvider.nvidia, 'n'),
      raw: 'raw text',
      clean: 'clean text',
      client: mock,
    );
    expect(verdict, isNull);
    expect(model, 'nvidia/nemotron-3-ultra-550b-a55b');
  });
}
