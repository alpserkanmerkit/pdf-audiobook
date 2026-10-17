// PHASE 4 wiring: question-bank HTTP transport (study_extractor pattern — a SEPARATE
// pass, not added to the cleaning prompt). Contract/parse lives in the PURE layer
// (lib/src/study_questions.dart, gate-tested); here only the transport.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sesli_kitap/io/llm_client.dart';
import 'package:sesli_kitap/src/study_questions.dart';

const String _quizSystem =
    'You are a study assistant. You will be given the clean text of a book chapter. '
    'Follow the requested JSON schema exactly and return ONLY JSON.';

class QuestionBankException implements Exception {
  QuestionBankException(this.reason);
  final String reason;

  @override
  String toString() => 'QuestionBankException: $reason';
}

class QuestionBank {
  QuestionBank({this.apiKey = '', LlmAccess? access, http.Client? client})
    : access = access ?? LlmAccess.single(LlmProvider.gemini, apiKey),
      _client = client ?? http.Client();

  /// Legacy single Gemini key; used when [access] is not given.
  final String apiKey;

  /// Providers to try in order (from the Settings choice).
  final LlmAccess access;
  final http.Client _client;

  /// Generates 8-12 study questions from the chapter text (V4-Flash, temp=0,
  /// json_object — same transport discipline as study_extractor).
  Future<List<StudyQuestion>> generate({
    required String chapterText,
    String? chapterTitle,
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
              'content': buildQuestionsPrompt(
                chapterText: chapterText,
                chapterTitle: chapterTitle,
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
      throw QuestionBankException('network error: $e');
    }
    if (resp.statusCode != 200) {
      final body = utf8.decode(resp.bodyBytes);
      throw QuestionBankException(
        'HTTP ${resp.statusCode}: '
        '${body.substring(0, body.length > 300 ? 300 : body.length)}',
      );
    }
    final Object? data;
    try {
      data = jsonDecode(utf8.decode(resp.bodyBytes));
    } on FormatException catch (e) {
      throw QuestionBankException('invalid JSON body: $e');
    }
    if (data is! Map<String, dynamic>) {
      throw QuestionBankException('unexpected response body');
    }
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      throw QuestionBankException('choices is empty');
    }
    final first = choices.first;
    if (first is! Map) {
      throw QuestionBankException('choices[0] is not an object');
    }
    final message = first['message'];
    final content = (message is Map) ? message['content'] : null;
    if (content is! String) {
      throw QuestionBankException('message.content is not a string');
    }
    return parseQuestionsResponse(content);
  }
}
