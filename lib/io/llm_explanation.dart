// IO transport: LLM "Explain" (same split as llm_quiz --
// prompt+parse are in the PURE layer: lib/src/explanation/explanation.dart, gate-tested;
// here only the HTTP transport, live errors are visible).
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sesli_kitap/io/llm_client.dart';
import 'package:sesli_kitap/src/explanation/explanation.dart';

const String _explanationSystem =
    // Turkish anchor sentence kept verbatim: demo_llm_router matches it.
    'You are a reading assistant. '
    'You explain the word or sentence the reader touched in TURKISH, based on '
    'the given context. Follow the requested JSON schema exactly and return ONLY JSON.';

class LlmExplanationException implements Exception {
  LlmExplanationException(this.reason);
  final String reason;

  @override
  String toString() => 'LlmExplanationException: $reason';
}

/// Produces the context-specific TURKISH explanation of the touched word/sentence
/// (V4-Flash, temp=0, json_object). The caller (ExplanationSheet) falls back to a
/// friendly error state on failure.
class LlmExplanation {
  LlmExplanation({this.apiKey = '', LlmAccess? access, http.Client? client})
    : access = access ?? LlmAccess.single(LlmProvider.gemini, apiKey),
      _client = client ?? http.Client();

  /// Legacy single Gemini key; used when [access] is not given.
  final String apiKey;

  /// Providers to try in order (from the Settings choice).
  final LlmAccess access;
  final http.Client _client;

  Future<String> fetch({
    required String target,
    required bool isWord,
    required String sentence,
    required String contextText,
  }) async {
    final http.Response resp;
    try {
      resp = await postChatCompletion(
        _client,
        access: access,
        body: {
          'messages': [
            {'role': 'system', 'content': _explanationSystem},
            {
              'role': 'user',
              'content': buildExplanationPrompt(
                target: target,
                isWord: isWord,
                sentence: sentence,
                contextText: contextText,
              ),
            },
          ],
          'stream': false,
          'temperature': 0,
          'top_p': 1,
          'response_format': {'type': 'json_object'},
        },
      );
    } on Exception catch (e) {
      throw LlmExplanationException('network error: $e');
    }
    if (resp.statusCode != 200) {
      final body = utf8.decode(resp.bodyBytes);
      throw LlmExplanationException(
        'HTTP ${resp.statusCode}: '
        '${body.substring(0, body.length > 300 ? 300 : body.length)}',
      );
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    if (data is! Map<String, dynamic>) {
      throw LlmExplanationException('unexpected response body');
    }
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      throw LlmExplanationException('choices is empty');
    }
    final first = choices.first;
    if (first is! Map) {
      throw LlmExplanationException('choices[0] is not an object');
    }
    final message = first['message'];
    final content = (message is Map) ? message['content'] : null;
    if (content is! String) {
      throw LlmExplanationException('message.content is not a string');
    }
    try {
      return parseExplanationResponse(content);
    } on ExplanationParseException {
      throw LlmExplanationException(
        'explanation contract violation (invalid JSON/field)',
      );
    }
  }
}
