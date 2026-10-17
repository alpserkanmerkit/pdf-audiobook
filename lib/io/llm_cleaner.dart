// PHASE 1 wiring: LLM (Gemini, gemini-3.8-flash) cleaning call (spec §5 prompt v1).
// JSON contract parsing lives in the PURE layer (lib/src/clean_contract.dart,
// gate-tested); only the HTTP transport is here (no gate test -> live errors are
// visible manually).
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sesli_kitap/io/llm_client.dart';
import 'package:sesli_kitap/src/clean_contract.dart';

/// Spec §5: if the prompt changes, SPEC is updated and this label is incremented
/// (the cache key will carry this label in Phase 2).
const String cleanPromptVersion = 'v1';

const String _systemPrompt = r'''
You will be given the raw text of a scanned Turkish book page.
Your task is ONLY the following:
1. Fix OCR errors (e.g. "farkmdahk" → "farkındalık").
2. Join words split across a line break with a hyphen (e.g. "bü-\nyük" → "büyük").
3. Preserve paragraph structure.
4. Keep the text in its original language (Turkish); do not translate.
PROHIBITIONS:
- Do NOT add, remove, summarize, or interpret words.
- Do not change the order of sentences.
- Never change the meaning.
OUTPUT: Only this JSON: {"metin": "..."}''';

class LlmCleanException implements Exception {
  LlmCleanException(this.reason);
  final String reason;

  @override
  String toString() => 'LlmCleanException: $reason';
}

class LlmCleaner {
  LlmCleaner({this.apiKey = '', LlmAccess? access, http.Client? client})
    : access = access ?? LlmAccess.single(LlmProvider.gemini, apiKey),
      _client = client ?? http.Client();

  /// Legacy single-Gemini key; used when [access] is not given.
  final String apiKey;

  /// Providers to try (Settings choice).
  final LlmAccess access;
  final http.Client _client;

  /// Cleans the raw page text. Gemini (llmModel), temp=0, top_p=1. The 'thinking'
  /// field is not sent (provider-specific, legacy).
  Future<CleanResult> clean(String rawPageText) async {
    final http.Response resp;
    try {
      resp = await postChatCompletion(
        _client,
        access: access,
        body: {
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            {'role': 'user', 'content': rawPageText},
          ],
          'stream': false,
          'temperature': 0,
          'top_p': 1,
          'response_format': {'type': 'json_object'},
        },
      );
    } on Exception catch (e) {
      throw LlmCleanException('network error: $e');
    }
    if (resp.statusCode != 200) {
      final body = utf8.decode(resp.bodyBytes);
      throw LlmCleanException(
        'HTTP ${resp.statusCode}: '
        '${body.substring(0, body.length > 300 ? 300 : body.length)}',
      );
    }
    // K9: HTTP 200 + a non-JSON body (e.g. a gateway HTML page) must not escape
    // as a raw FormatException -> the typed exception contract is kept.
    final Object? data;
    try {
      data = jsonDecode(utf8.decode(resp.bodyBytes));
    } on FormatException catch (e) {
      throw LlmCleanException('invalid JSON body: ${e.message}');
    }
    if (data is! Map<String, dynamic>) {
      throw LlmCleanException('unexpected response body');
    }
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      throw LlmCleanException('choices is empty');
    }
    final first = choices.first;
    if (first is! Map) {
      throw LlmCleanException('choices[0] is not an object');
    }
    final message = first['message'];
    final content = (message is Map) ? message['content'] : null;
    if (content is! String) {
      throw LlmCleanException('message.content is not a string');
    }
    return parseCleanResponse(content);
  }
}
