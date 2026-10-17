// Oracle: IO modules must throw a TYPED exception on a MALFORMED body with
// HTTP 200 (raw FormatException/TypeError must not leak). This extends the
// existing "catch jsonDecode, convert to a typed exception" pattern from
// llm_cleaner/llm_discussion to question_bank/weekly_report/skeleton/google_tts.
// Runs with MockClient, never touching the real network.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sesli_kitap/io/google_tts.dart';
import 'package:sesli_kitap/io/llm_skeleton.dart';
import 'package:sesli_kitap/io/question_bank.dart';
import 'package:sesli_kitap/io/weekly_report_extractor.dart';
import 'package:sesli_kitap/src/chapter_map.dart';
import 'package:sesli_kitap/src/voices.dart';
import 'package:sesli_kitap/src/weekly_report_contract.dart';

http.Client _resp200(String body) => MockClient(
  (req) async => http.Response(
    body,
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  ),
);

void main() {
  const notJson = 'this is not JSON {{{';

  test(
    'QuestionBank: HTTP200 + malformed JSON -> QuestionBankException',
    () async {
      await expectLater(
        QuestionBank(
          apiKey: 'k',
          client: _resp200(notJson),
        ).generate(chapterText: 'x'),
        throwsA(isA<QuestionBankException>()),
      );
    },
  );

  test('WeeklyReportExtractor: HTTP200 + malformed JSON -> '
      'WeeklyReportExtractException', () async {
    const stats = WeeklyStats(toplam: 1, hakim: 0, devam: 1, vadesiGecen: 0);
    await expectLater(
      WeeklyReportExtractor(
        apiKey: 'k',
        client: _resp200(notJson),
      ).extract(stats: stats),
      throwsA(isA<WeeklyReportExtractException>()),
    );
  });

  test(
    'LlmSkeleton: HTTP200 + malformed JSON -> LlmSkeletonException',
    () async {
      await expectLater(
        LlmSkeleton(
          apiKey: 'k',
          client: _resp200(notJson),
        ).fetch(headers: const <PageHeaderEntry>[], totalPages: 10),
        throwsA(isA<LlmSkeletonException>()),
      );
    },
  );

  test('GoogleTts: HTTP200 + malformed JSON -> GoogleTtsException', () async {
    await expectLater(
      GoogleTts(
        apiKey: 'k',
        client: _resp200(notJson),
      ).synthesize(text: 't', voice: SesliVoice.wavenetB),
      throwsA(isA<GoogleTtsException>()),
    );
  });

  test('GoogleTts: HTTP200 + JSON but NOT a Map (array) -> GoogleTtsException '
      '(typed check instead of an as-cast)', () async {
    await expectLater(
      GoogleTts(
        apiKey: 'k',
        client: _resp200('[1,2,3]'),
      ).synthesize(text: 't', voice: SesliVoice.wavenetB),
      throwsA(isA<GoogleTtsException>()),
    );
  });
}
