// GATE test (2026-06-30; NVIDIA migration 2026-09-28): because the lib/io HTTP body is outside the coverage gate,
// request-body regressions can only be caught by a body-assert test like this one. Model/thinking/reasoning_effort/URL
// claims (Gemini-specific endpoint, DeepSeek 'thinking' field NOT present) are not repeated here: they are covered by
// the 'temizleyici' (cleaner) test (_expectGemini) in gemini_provider_test.dart. This file covers: end-to-end result
// (result.metin) + request message structure.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sesli_kitap/io/llm_cleaner.dart';

void main() {
  test(
    'clean() sends the raw text in the user message and returns the parsed text',
    () async {
      Map<String, dynamic>? capturedBody;
      final mock = MockClient((req) async {
        capturedBody = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '{"metin":"clean text"}'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final cleaner = LlmCleaner(apiKey: 'test-key', client: mock);
      final result = await cleaner.clean('raw page text');

      expect(result.metin, 'clean text');
      expect(capturedBody, isNotNull);
      // Model/thinking/reasoning_effort/URL/auth claims are verified in the gemini_provider_test 'temizleyici'
      // (_expectGemini) test; here only two things that test does not see: the raw text to be cleaned is sent in the
      // 'user' message, and the system prompt is a separate 'system' message.
      final messages = capturedBody!['messages'] as List<dynamic>;
      expect(messages.map((m) => (m as Map)['role']), ['system', 'user']);
      expect((messages.last as Map)['content'], 'raw page text');
    },
  );

  // FAZ3a K9: HTTP 200 + non-JSON body (gateway HTML) currently escapes as a raw FormatException
  // (OUTSIDE the jsonDecode try/catch) -> violates the typed-exception contract. Expected: LlmCleanException.
  test('HTTP 200 + non-JSON body -> LlmCleanException', () async {
    final mock = MockClient(
      (req) async => http.Response('<html>error</html>', 200),
    );
    await expectLater(
      LlmCleaner(apiKey: 'k', client: mock).clean('text'),
      throwsA(isA<LlmCleanException>()),
    );
  });
}
