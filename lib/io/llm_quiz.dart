// IO transport: LLM 4-choice quiz generation (same split as question_bank /
// llm_skeleton -- prompt+parse are in the PURE layer: lib/src/quiz_generation.dart,
// gate-tested; here only the HTTP transport, live errors are visible).
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sesli_kitap/io/llm_client.dart';
import 'package:sesli_kitap/src/quiz_choice_machine.dart';
import 'package:sesli_kitap/src/quiz_generation.dart';

const String _quizSystem =
    'You are a study assistant. You will be given the clean text of a book. '
    'Follow the requested JSON schema exactly and return ONLY JSON.';

class LlmQuizException implements Exception {
  LlmQuizException(this.reason);
  final String reason;

  @override
  String toString() => 'LlmQuizException: $reason';
}

/// Generates `count` 4-choice questions from the book text (V4-Flash, temp=0,
/// json_object). The caller (QuizScreen) falls back to a friendly error on failure.
class LlmQuiz {
  LlmQuiz({this.apiKey = '', LlmAccess? access, http.Client? client})
    : access = access ?? LlmAccess.single(LlmProvider.gemini, apiKey),
      _client = client ?? http.Client();

  /// Legacy single Gemini key; used when [access] is not given.
  final String apiKey;

  /// Providers to try in order (from the Settings choice).
  final LlmAccess access;
  final http.Client _client;

  Future<List<MultipleChoiceQuestion>> fetch({
    required String bookText,
    required String kaynak,
    int count = 5,
  }) async {
    final http.Response resp;
    try {
      resp = await postChatCompletion(
        _client,
        access: access,
        body: {
          'messages': [
            {'role': 'system', 'content': _quizSystem},
            {
              'role': 'user',
              'content': buildQuizPrompt(bookText: bookText, count: count),
            },
          ],
          'stream': false,
          'temperature': 0,
          'top_p': 1,
          'response_format': {'type': 'json_object'},
        },
      );
    } on Exception catch (e) {
      throw LlmQuizException('network error: $e');
    }
    if (resp.statusCode != 200) {
      final body = utf8.decode(resp.bodyBytes);
      throw LlmQuizException(
        'HTTP ${resp.statusCode}: '
        '${body.substring(0, body.length > 300 ? 300 : body.length)}',
      );
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    if (data is! Map<String, dynamic>) {
      throw LlmQuizException('unexpected response body');
    }
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      throw LlmQuizException('choices is empty');
    }
    final first = choices.first;
    if (first is! Map) {
      throw LlmQuizException('choices[0] is not an object');
    }
    final message = first['message'];
    final content = (message is Map) ? message['content'] : null;
    if (content is! String) {
      throw LlmQuizException('message.content is not a string');
    }
    try {
      return parseQuizResponse(content, kaynak: kaynak);
    } on QuizParseException {
      throw LlmQuizException('quiz contract violation (invalid JSON/field)');
    }
  }
}
