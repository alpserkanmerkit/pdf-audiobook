import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:sesli_kitap/io/llm_client.dart';

class LlmTutorException implements Exception {
  LlmTutorException(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

class LlmTutor {
  LlmTutor({this.apiKey = '', LlmAccess? access, http.Client? client})
    : access = access ?? LlmAccess.single(LlmProvider.gemini, apiKey),
      _client = client ?? http.Client();

  /// Legacy single Gemini key; used when [access] is not given.
  final String apiKey;

  /// Providers to try in order (from the Settings choice).
  final LlmAccess access;
  final http.Client _client;

  Future<String> complete({
    required String system,
    required String user,
  }) async {
    final http.Response resp;
    try {
      resp = await postChatCompletion(
        _client,
        access: access,
        body: {
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': user},
          ],
          'stream': false,
          'temperature': 0,
          'response_format': {'type': 'json_object'},
        },
      );
    } on LlmTimeoutException catch (e) {
      throw LlmTutorException(e.toString());
    } on Exception {
      throw LlmTutorException(
        'Could not connect to the AI server. '
        'Check your internet connection and try again.',
      );
    }

    if (resp.statusCode != 200) {
      throw LlmTutorException(
        'The AI server returned an error (HTTP ${resp.statusCode}).',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    } on FormatException {
      throw LlmTutorException('Unexpected response from the AI server.');
    }

    if (decoded is! Map) {
      throw LlmTutorException('Unexpected response from the AI server.');
    }

    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw LlmTutorException('Unexpected response from the AI server.');
    }

    final first = choices.first;
    if (first is! Map) {
      throw LlmTutorException('Unexpected response from the AI server.');
    }

    final message = first['message'];
    final content = (message is Map) ? message['content'] : null;
    if (content is! String || content.trim().isEmpty) {
      throw LlmTutorException('Unexpected response from the AI server.');
    }

    return content;
  }
}
