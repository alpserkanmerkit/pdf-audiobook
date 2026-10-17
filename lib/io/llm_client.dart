// The single shared source of ALL LLM calls.
// The user's provider choice (lib/src/llm_access.dart): Google (Gemini),
// DeepSeek, NVIDIA or "all" -- all are OpenAI-compatible chat/completions endpoints.
// In "all" mode, if one provider fails (non-200 / network error), the next one is tried.
// Legacy `apiKey:` call = Gemini only (backward compatibility).
// On 429, back off 5 s / 10 s (per provider).
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:sesli_kitap/src/llm_access.dart';

export '../src/llm_access.dart';

final Uri llmChatEndpoint = Uri.parse(
  'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
);

const String llmModel = 'gemini-3.8-flash';

// User decision 2026-09-28: the auditor is also the general model (same single Gemini key).
// The previous NVIDIA auditor was nemotron-3-ultra; the Gemini auditor is measured
// separately by the oracle with a faithful/broken double probe.
const String llmAuditorModel = 'gemini-3.8-flash';

const List<Duration> llmRetryDelays = [
  Duration(seconds: 5),
  Duration(seconds: 10),
];

/// Longest time for a single LLM request (each 429 retry is timed separately).
/// Measurement (2026-09-28, 3c3cc0d live probe): the discussion call took 17.8/17.0 s
/// (3000 token cap); the "long" mode measured 46 s (5996 tokens, ~130 tokens/s).
/// Raising the long-mode cap to 8000 tokens -> worst case ~62 s; 90 s still leaves
/// ~1.45x headroom: a legitimately slow response is not cut, and a hanging connection
/// does not keep the user waiting forever.
const Duration llmRequestTimeout = Duration(seconds: 90);

/// Thrown when the time runs out. [Exception] (not Error): all callers catch
/// `on Exception` -> fail-open chains (cleaner/auditor) work as they are; the
/// discussion shows this message to the user.
class LlmTimeoutException implements Exception {
  LlmTimeoutException(this.limit);
  final Duration limit;

  @override
  String toString() =>
      'The AI server did not respond within ${limit.inSeconds} seconds. '
      'Check your internet connection and try again.';
}

typedef LlmSleep = Future<void> Function(Duration d);

/// The selected provider has no key -> no network call is made.
class LlmNotConfiguredException implements Exception {
  @override
  String toString() =>
      'An API key is required for AI features. Go to Settings > ACCOUNT & API '
      'and enter the key for the selected provider.';
}

/// If [access] is not given, [apiKey] is used with Gemini only (legacy contract).
/// If [model] is given, it is used for every provider; [auditor] selects the
/// provider's auditor model.
Future<http.Response> postChatCompletion(
  http.Client client, {
  required Map<String, Object?> body,
  String apiKey = '',
  LlmAccess? access,
  String? model,
  bool auditor = false,
  LlmSleep sleep = llmRealSleep,
}) async {
  final routes =
      (access ?? LlmAccess.single(LlmProvider.gemini, apiKey)).routes;
  if (routes.isEmpty) throw LlmNotConfiguredException();

  final last = routes.length - 1;
  for (var i = 0; i < last; i++) {
    try {
      final response = await _postOnce(
        client,
        routes[i],
        body: body,
        model: model,
        auditor: auditor,
        sleep: sleep,
      );
      if (response.statusCode == 200) return response;
    } on Exception {
      // Try the next provider.
    }
  }
  return _postOnce(
    client,
    routes[last],
    body: body,
    model: model,
    auditor: auditor,
    sleep: sleep,
  );
}

Future<http.Response> _postOnce(
  http.Client client,
  LlmRoute route, {
  required Map<String, Object?> body,
  required String? model,
  required bool auditor,
  required LlmSleep sleep,
}) async {
  final spec = llmProviderSpec(route.provider);
  final requestBody = jsonEncode({
    'model': model ?? (auditor ? spec.auditorModel : spec.model),
    ...body,
    ...spec.extraBody,
  });
  final headers = {
    'Authorization': 'Bearer ${route.apiKey}',
    'Content-Type': 'application/json; charset=utf-8',
  };
  final endpoint = Uri.parse(spec.endpoint);

  var attempt = 0;
  while (true) {
    final response = await client
        .post(endpoint, headers: headers, body: requestBody)
        .timeout(
          llmRequestTimeout,
          onTimeout: () => throw LlmTimeoutException(llmRequestTimeout),
        );

    if (response.statusCode == 429 && attempt < llmRetryDelays.length) {
      await sleep(llmRetryDelays[attempt]);
      attempt++;
      continue;
    }
    return response;
  }
}

/// Production wait; tests skip the real wait by injecting an [LlmSleep].
Future<void> llmRealSleep(Duration d) => Future.delayed(d);
