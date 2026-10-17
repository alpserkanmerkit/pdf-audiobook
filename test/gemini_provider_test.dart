// Oracle test (2026-09-28, Gemini migration, paid 3.8 Flash): every LLM call point in
// the app must go to the Gemini (OpenAI-compatible) endpoint, with the gemini-3.8-flash
// model, reasoning_effort:"low" on every request, using the user's Gemini key; the
// DeepSeek-specific 'thinking' field must not be sent.
// An old saved NVIDIA key must not count as a Gemini key (transition state, no crash)
// -- same pattern as the earlier DeepSeek key handling.
// Fake HTTP client (MockClient) -- no network access.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sesli_kitap/io/auditor.dart';
import 'package:sesli_kitap/io/book_digest.dart';
import 'package:sesli_kitap/io/llm_cleaner.dart';
import 'package:sesli_kitap/io/llm_client.dart' show llmRetryDelays;
import 'package:sesli_kitap/io/llm_discussion.dart';
import 'package:sesli_kitap/io/llm_explanation.dart';
import 'package:sesli_kitap/io/llm_quiz.dart';
import 'package:sesli_kitap/io/llm_skeleton.dart';
import 'package:sesli_kitap/io/question_bank.dart';
import 'package:sesli_kitap/io/weekly_report_extractor.dart';
import 'package:sesli_kitap/src/chapter_map.dart';
import 'package:sesli_kitap/src/weekly_report_contract.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _geminiEndpoint =
    'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions';
const _geminiModel = 'gemini-3.8-flash';
const _key = 'gm-test-key';

/// Old version's SharedPreferences key (fixed literal for the migration test).
const _legacyPrefKey =
    'nvidia'
    'Key';

http.Response _ok(String content) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': content},
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// Runs [call] with the fake client and captures the ONE request that goes out.
/// The response content may not fit each call point's contract -> parse errors are
/// swallowed; this test only checks the address/model/key of the OUTGOING request.
Future<http.Request> _capture(
  Future<Object?> Function(http.Client c) call, {
  String content = '{}',
}) async {
  http.Request? captured;
  final mock = MockClient((req) async {
    captured = req;
    return _ok(content);
  });
  try {
    await call(mock);
  } on Object catch (_) {
    // A content-contract error is not what this test is about.
  }
  expect(captured, isNotNull, reason: 'no HTTP request was sent at all');
  return captured!;
}

void _expectGemini(http.Request req, {String model = _geminiModel}) {
  expect(req.url.toString(), _geminiEndpoint);
  expect(req.headers['Authorization'], 'Bearer $_key');
  final body = jsonDecode(req.body) as Map<String, dynamic>;
  expect(body['model'], model);
  expect(
    body.containsKey('thinking'),
    isFalse,
    reason: "the DeepSeek-specific 'thinking' field must not be sent to Gemini",
  );
  expect(
    body['reasoning_effort'],
    'low',
    reason: 'measured: without low, Gemini cuts the text off early',
  );
}

void main() {
  group('every LLM call point goes to the Gemini endpoint', () {
    test('cleaner (reader page cleanup)', () async {
      final req = await _capture(
        (c) => LlmCleaner(apiKey: _key, client: c).clean('raw'),
        content: '{"metin":"clean"}',
      );
      _expectGemini(req);
    });

    test('discussion: generate', () async {
      final req = await _capture(
        (c) => LlmDiscussion(apiKey: _key, client: c).generate('topic'),
        content: 'A: hello\nB: hi',
      );
      _expectGemini(req);
    });

    test('discussion: generateContinuation', () async {
      final req = await _capture(
        (c) => LlmDiscussion(
          apiKey: _key,
          client: c,
        ).generateContinuation('topic', const []),
        content: 'A: hello\nB: hi',
      );
      _expectGemini(req);
    });

    test('Ask explanation', () async {
      final req = await _capture(
        (c) => LlmExplanation(apiKey: _key, client: c).fetch(
          target: 'word',
          isWord: true,
          sentence: 'a sentence',
          contextText: 'context',
        ),
      );
      _expectGemini(req);
    });

    test('quiz', () async {
      final req = await _capture(
        (c) => LlmQuiz(
          apiKey: _key,
          client: c,
        ).fetch(bookText: 'text', kaynak: 'book'),
      );
      _expectGemini(req);
    });

    test('chapter skeleton', () async {
      final req = await _capture(
        (c) => LlmSkeleton(apiKey: _key, client: c).fetch(
          headers: const [PageHeaderEntry(page: 1, header: 'Chapter 1')],
          totalPages: 1,
        ),
      );
      _expectGemini(req);
    });

    test('question bank', () async {
      final req = await _capture(
        (c) =>
            QuestionBank(apiKey: _key, client: c).generate(chapterText: 'text'),
      );
      _expectGemini(req);
    });

    test('weekly report', () async {
      final req = await _capture(
        (c) => WeeklyReportExtractor(apiKey: _key, client: c).extract(
          stats: const WeeklyStats(
            toplam: 1,
            hakim: 0,
            devam: 1,
            vadesiGecen: 0,
          ),
        ),
      );
      _expectGemini(req);
    });

    test('book digest (summary client)', () async {
      final req = await _capture(
        (c) => LlmDigestClient(
          apiKey: _key,
          client: c,
        ).summarizeBook(chapterSummaries: const ['summary']),
        content: 'book summary',
      );
      _expectGemini(req);
    });

    // User decision (2026-09-28): the auditor also moves to gemini-3.8-flash for the
    // single key (no separate model/key maintenance).
    test('auditor -- gemini-3.8-flash model', () async {
      final req = await _capture(
        (c) => auditClean(apiKey: _key, raw: 'raw', clean: 'clean', client: c),
        content: '{"sadik": true}',
      );
      _expectGemini(req);
    });
  });

  test(
    '429 (per-minute limit) -> backs off and retries, second attempt succeeds',
    () async {
      var calls = 0;
      final mock = MockClient((req) async {
        calls++;
        if (calls == 1) {
          return http.Response(
            '{"status":429,"title":"Too Many Requests"}',
            429,
          );
        }
        return _ok('A: hello\nB: hi');
      });
      final slept = <Duration>[];
      final turns = await LlmDiscussion(
        apiKey: _key,
        client: mock,
        sleep: (d) async => slept.add(d),
      ).generate('topic');
      expect(calls, 2);
      expect(slept, [llmRetryDelays.first]);
      expect(turns, hasLength(2));
    },
  );

  group('settings: old NVIDIA key -> a Gemini key is required', () {
    test(
      'a saved old key is not counted as a Gemini key and is deleted',
      () async {
        SharedPreferences.setMockInitialValues(const {
          _legacyPrefKey: 'sk-old-nvidia',
        });
        final prefs = await SharedPreferences.getInstance();
        final reading = ReadingSettings(prefs)..load();
        expect(reading.geminiKey, isEmpty);
        expect(prefs.getString(_legacyPrefKey), isNull);
      },
    );

    test('an empty setup does not crash, the key stays empty', () async {
      SharedPreferences.setMockInitialValues(const {});
      final prefs = await SharedPreferences.getInstance();
      final reading = ReadingSettings(prefs)..load();
      expect(reading.geminiKey, isEmpty);
    });
  });
}
