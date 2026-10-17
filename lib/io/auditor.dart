// PHASE 2 wiring: conditional auditor (spec §6) -- ONLY suspicious pages are sent
// to the auditor model (llmAuditorModel) with the question "is this cleaning
// faithful to the original?" (about 20-30 expected across 706 pages).
// Error/unreachable -> null (unknown); the suspicious flag stays in the UI.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:sesli_kitap/io/llm_client.dart';

const String _auditSystemPrompt = '''
You will receive the RAW text of a scanned book page and its CLEANED version.
Question: is the cleaning faithful to the original? Were words added, removed, or the meaning changed?
OCR error corrections and hyphen joins count as faithful.
OUTPUT: Only this JSON: {"sadik": true} or {"sadik": false}''';

Future<bool?> auditClean({
  required String raw,
  required String clean,
  String apiKey = '',
  LlmAccess? access,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  try {
    final resp = await postChatCompletion(
      c,
      access: access ?? LlmAccess.single(LlmProvider.gemini, apiKey),
      body: {
        'messages': [
          {'role': 'system', 'content': _auditSystemPrompt},
          {'role': 'user', 'content': 'RAW:\n$raw\n\nCLEAN:\n$clean'},
        ],
        'stream': false,
        'temperature': 0,
        'response_format': {'type': 'json_object'},
      },
      auditor: true,
    );
    if (resp.statusCode != 200) {
      return null;
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    final content = ((data as Map)['choices'] as List).isEmpty
        ? null
        : (((data['choices'] as List).first as Map)['message']
              as Map)['content'];
    if (content is! String) {
      return null;
    }
    final verdict = jsonDecode(content);
    if (verdict is Map && verdict['sadik'] is bool) {
      return verdict['sadik'] as bool;
    }
    return null;
  } on Object catch (_) {
    // K12 contract: ANY error -> null (both Exception AND Error; an unexpected
    // response shape throws TypeError during the cast). The auditor is an
    // optional layer: the flow is not broken, and the suspicious flag stays in
    // the UI.
    return null;
  }
}
