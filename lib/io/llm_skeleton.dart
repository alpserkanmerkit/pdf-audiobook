// IO wiring: LLM chapter-skeleton call (chapter detection, spike-verified prompt).
// Input preparation + JSON contract parsing are in the PURE layer
// (lib/src/chapter_skeleton.dart, gate-tested); here only the HTTP transport + prompt
// (no gate test -> live errors + skeleton ACCURACY are visible manually/e2e).
// Evidence: internal design note (706 headings ->
// clean 20-chapter PDF-indexed skeleton; OCR merged, names cleaned).
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:sesli_kitap/io/llm_client.dart';
import 'package:sesli_kitap/src/chapter_map.dart';
import 'package:sesli_kitap/src/chapter_skeleton.dart';

// demo_llm_router matches the phrase "extract the book's REAL chapter skeleton";
// keep it in sync when editing this prompt.
const String _skeletonSystemPrompt = '''
You will be given the FIRST LINE of every page of a scanned Turkish book
(a running-header candidate), in the form "sNN: text" (NN = page number). These lines:
- contain OCR noise (e.g. "İ@nsa@n", "Yasast" = "Yasası").
- CHANGE between even and odd pages: even pages are usually the book title (repeated on every page),
  odd pages the chapter name.
- On chapter-start pages, or in front/back matter, there may be no heading.

YOUR TASK: extract the book's REAL chapter skeleton.

RULES:
1. MERGE the OCR VARIANTS of the same chapter into ONE chapter
   (e.g. "Narsisizm Yasası" / "Narsisizm Yasast" = one chapter).
2. Keep numbered DIFFERENT chapters SEPARATE
   (e.g. "Birinci Söz" ≠ "İkinci Söz" — these are separate chapters).
3. CLEAN chapter names from OCR noise; write the most accurate/clean Turkish form
   (e.g. "Kendim Baltalama" → "Kendini Baltalama").
4. The BOOK TITLE that repeats on every even page is NOT a chapter — skip it.
5. Extract ONLY from the given headings — do NOT INVENT chapters that are not in the book.
6. Chapters are in increasing page order; the end of one chapter is smaller than the start of the next.
   If there is a front matter/introduction, count it as a chapter too.
7. VERY IMPORTANT — page number source: startPage and endPage are ALWAYS the number NN in the
   "s<NN>" at the start of the line (the PDF file page order, starting from 1). NEVER use a number
   inside the heading TEXT. The startPage is the s<NN> where the first chapter begins;
   the last page is the largest s<NN>.

OUTPUT: ONLY this JSON, write nothing else:
{"chapters":[{"title":"Chapter Title","startPage":N,"endPage":M}, ...]}''';

class LlmSkeletonException implements Exception {
  LlmSkeletonException(this.reason);
  final String reason;

  @override
  String toString() => 'LlmSkeletonException: $reason';
}

/// Single-call chapter skeleton: a chapter list from the raw running headers via LLM.
/// The caller (reader_screen) falls back to the buildChapterMap backup on failure.
class LlmSkeleton {
  LlmSkeleton({this.apiKey = '', LlmAccess? access, http.Client? client})
    : access = access ?? LlmAccess.single(LlmProvider.gemini, apiKey),
      _client = client ?? http.Client();

  /// Legacy single Gemini key; used when [access] is not given.
  final String apiKey;

  /// Providers to try in order (from the Settings choice).
  final LlmAccess access;
  final http.Client _client;

  Future<List<Chapter>> fetch({
    required List<PageHeaderEntry> headers,
    required int totalPages,
  }) async {
    final input = buildSkeletonInput(headers);
    final http.Response resp;
    try {
      resp = await postChatCompletion(
        _client,
        access: access,
        body: {
          'messages': [
            {'role': 'system', 'content': _skeletonSystemPrompt},
            {
              'role': 'user',
              'content':
                  'First lines of the book pages (sNN: heading; NN=PDF page index):\n\n$input',
            },
          ],
          'stream': false,
          'temperature': 0,
          'top_p': 1,
          'max_tokens': 16000,
          'response_format': {'type': 'json_object'},
        },
      );
    } on Exception catch (e) {
      throw LlmSkeletonException('network error: $e');
    }

    if (resp.statusCode != 200) {
      final body = utf8.decode(resp.bodyBytes);
      throw LlmSkeletonException(
        'HTTP ${resp.statusCode}: '
        '${body.substring(0, body.length > 300 ? 300 : body.length)}',
      );
    }
    final Object? data;
    try {
      data = jsonDecode(utf8.decode(resp.bodyBytes));
    } on FormatException catch (e) {
      throw LlmSkeletonException('invalid JSON body: $e');
    }
    if (data is! Map<String, dynamic>) {
      throw LlmSkeletonException('unexpected response body');
    }
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      throw LlmSkeletonException('choices is empty');
    }
    final first = choices.first;
    if (first is! Map) {
      throw LlmSkeletonException('choices[0] is not an object');
    }
    final message = first['message'];
    final content = (message is Map) ? message['content'] : null;
    if (content is! String) {
      throw LlmSkeletonException('message.content is not a string');
    }
    try {
      return parseSkeletonResponse(content, totalPages: totalPages);
    } on SkeletonParseException {
      throw LlmSkeletonException(
        'skeleton contract violation (invalid JSON/range)',
      );
    }
  }
}
