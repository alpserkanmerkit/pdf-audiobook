import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sesli_kitap/io/llm_client.dart';
import 'package:sesli_kitap/src/weekly_report_contract.dart';

const String _reportSystem =
    // Turkish anchor sentence kept verbatim: demo_llm_router matches it.
    'You are a student assistant. '
    'Write a motivating progress letter based on the weekly statistics. '
    'Respond only in JSON format.';

class WeeklyReportExtractException implements Exception {
  WeeklyReportExtractException(this.reason);
  final String reason;

  @override
  String toString() => 'WeeklyReportExtractException: $reason';
}

class WeeklyReportExtractor {
  WeeklyReportExtractor({
    this.apiKey = '',
    LlmAccess? access,
    http.Client? client,
  }) : access = access ?? LlmAccess.single(LlmProvider.gemini, apiKey),
       _client = client ?? http.Client();

  /// Legacy single Gemini key; used when [access] is not given.
  final String apiKey;

  /// Providers to try in order (from the Settings choice).
  final LlmAccess access;
  final http.Client _client;

  Future<WeeklyReport> extract({required WeeklyStats stats}) async {
    final http.Response resp;
    try {
      resp = await postChatCompletion(
        _client,
        access: access,
        body: {
          'messages': [
            {'role': 'system', 'content': _reportSystem},
            {'role': 'user', 'content': buildWeeklyReportPrompt(stats)},
          ],
          'stream': false,
          'temperature': 0,
          'top_p': 1,
          'response_format': {'type': 'json_object'},
        },
      );
    } on Exception catch (e) {
      throw WeeklyReportExtractException('network error: $e');
    }
    if (resp.statusCode != 200) {
      final body = utf8.decode(resp.bodyBytes);
      throw WeeklyReportExtractException(
        'HTTP ${resp.statusCode}: '
        '${body.substring(0, body.length > 300 ? 300 : body.length)}',
      );
    }
    final Object? data;
    try {
      data = jsonDecode(utf8.decode(resp.bodyBytes));
    } on FormatException catch (e) {
      throw WeeklyReportExtractException('invalid JSON body: $e');
    }
    if (data is! Map<String, dynamic>) {
      throw WeeklyReportExtractException('unexpected response body');
    }
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      throw WeeklyReportExtractException('choices is empty');
    }
    final first = choices.first;
    if (first is! Map) {
      throw WeeklyReportExtractException('choices[0] is not an object');
    }
    final message = first['message'];
    final content = (message is Map) ? message['content'] : null;
    if (content is! String) {
      throw WeeklyReportExtractException('message.content is not a string');
    }
    return parseWeeklyReportResponse(content);
  }
}
