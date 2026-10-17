// DemoLlmRouter: the REAL io classes (LlmCleaner, LlmDiscussion, LlmQuiz, ...)
// connect through a MockClient to a fake router; the answers pass through the app's
// OWN parsers (parseXxx). If the system prompt changes and the routing escapes,
// `unrouted` fills up and this test turns red (a fragile-match safety net).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sesli_kitap/demo/demo_api_server.dart';
import 'package:sesli_kitap/demo/demo_llm_router.dart';
import 'package:sesli_kitap/io/auditor.dart';
import 'package:sesli_kitap/io/llm_cleaner.dart';
import 'package:sesli_kitap/io/llm_discussion.dart';
import 'package:sesli_kitap/io/llm_explanation.dart';
import 'package:sesli_kitap/io/llm_quiz.dart';
import 'package:sesli_kitap/io/llm_skeleton.dart';
import 'package:sesli_kitap/io/llm_tutor.dart';
import 'package:sesli_kitap/io/question_bank.dart';
import 'package:sesli_kitap/io/weekly_report_extractor.dart';
import 'package:sesli_kitap/src/chapter_map.dart';
import 'package:sesli_kitap/src/discussion/discussion_name_lint.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';
import 'package:sesli_kitap/src/llm_access.dart';
import 'package:sesli_kitap/src/study_questions.dart';
import 'package:sesli_kitap/src/tutor/lesson_split.dart';
import 'package:sesli_kitap/src/tutor/tutor_prompts.dart';
import 'package:sesli_kitap/src/weekly_report_contract.dart';

final LlmAccess _access = LlmAccess.single(
  LlmProvider.gemini,
  'demo-anahtar-yok',
);

http.Client _clientFor(DemoLlmRouter router) => MockClient((req) async {
  final rec = RecordedRequest(
    method: req.method,
    path: req.url.path,
    originalHost: req.url.host,
    headers: req.headers,
    body: req.body,
  );
  final content = router.respond(rec) ?? jsonEncode({'metin': rec.userMessage});
  return http.Response.bytes(
    utf8.encode(
      jsonEncode({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': content},
          },
        ],
      }),
    ),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
});

int _sentences(String text) =>
    RegExp(r'[.!?]+(?=\s|$)').allMatches(text.trim()).length;

void _expectCleanScript(List<DiscussionTurn> turns) {
  for (final t in turns) {
    expect(t.text, isNot(contains('(')));
    expect(t.text, isNot(contains('[')));
    final n = _sentences(t.text);
    expect(n, inInclusiveRange(3, 4), reason: 'turn ${t.text}');
  }
  expect(lintDiscussionNames(turns), isEmpty);
}

void main() {
  late DemoLlmRouter router;
  late http.Client client;
  setUp(() {
    router = DemoLlmRouter();
    client = _clientFor(router);
  });
  tearDown(() => expect(router.unrouted, isEmpty));

  test('cleaner: returns the text verbatim (faithful)', () async {
    const raw =
        'Ahırın avlusunda oynarken aşağıda, derenin şırıltısını işittik.';
    final r = await LlmCleaner(access: _access, client: client).clean(raw);
    expect(r.metin, raw);
  });

  test('auditor: faithful=true', () async {
    final v = await auditClean(
      raw: 'ham',
      clean: 'temiz',
      access: _access,
      client: client,
    );
    expect(v, isTrue);
  });

  test(
    'chapter map: 21 pages -> Kasagi 1-7, Forsa 8-14, Primo 15-21',
    () async {
      final headers = [
        for (var p = 1; p <= 21; p++)
          PageHeaderEntry(page: p, header: 'Üç Hikâye'),
      ];
      final chapters = await LlmSkeleton(
        access: _access,
        client: client,
      ).fetch(headers: headers, totalPages: 21);
      expect(chapters.map((c) => (c.title, c.startPage, c.endPage)).toList(), [
        ('Kaşağı', 1, 7),
        ('Forsa', 8, 14),
        ('Primo Türk Çocuğu', 15, 21),
      ]);
    },
  );

  test('discussion: opening batch has >=12 turns, 4 speakers, clean', () async {
    final llm = LlmDiscussion(access: _access, client: client);
    final turns = await llm.generateReviewed('Topic and source: Kaşağı');
    expect(turns.length, greaterThanOrEqualTo(12));
    expect(
      turns.map((t) => t.speaker).toSet(),
      DiscussionSpeaker.values.toSet(),
    );
    _expectCleanScript(turns);
    expect(
      turns.map((t) => t.text).join(' '),
      allOf(contains('Dadaruh'), contains('Pervin')),
    );
  });

  test(
    'discussion: continuation batches cycle in order, each with >=6 clean turns',
    () async {
      final llm = LlmDiscussion(access: _access, client: client);
      final opening = await llm.generate('konu');
      final batches = <List<DiscussionTurn>>[];
      for (var i = 0; i < 4; i++) {
        batches.add(await llm.generateContinuation('konu', opening));
      }
      for (final b in batches) {
        expect(b.length, greaterThanOrEqualTo(6));
        _expectCleanScript(b);
      }
      expect(batches[0].first.text, isNot(batches[1].first.text));
      expect(
        batches[0].first.text,
        batches[3].first.text,
        reason: 'the pool cycles',
      );
      final all = batches.expand((b) => b).map((t) => t.text).join(' ');
      expect(all, allOf(contains('Kara Memiş'), contains('Primo')));
    },
  );

  test(
    'discussion: listener question answer has 2-4 turns and repeats the question',
    () async {
      final llm = LlmDiscussion(access: _access, client: client);
      final turns = await llm.generateAnswer(
        'konu',
        'Why is Hasan dying',
        const [DiscussionTurn(DiscussionSpeaker.a, 'Previous line.')],
      );
      expect(turns.length, inInclusiveRange(2, 4));
      expect(turns.first.text, contains('Why is Hasan dying'));
      expect(lintDiscussionNames(turns), isEmpty);
    },
  );

  test('quiz: 5 questions, all with 4 options, varied dogruIndex', () async {
    final qs = await LlmQuiz(
      access: _access,
      client: client,
    ).fetch(bookText: 'text', kaynak: 'Üç Hikâye');
    expect(qs, hasLength(5));
    for (final q in qs) {
      expect(q.secenekler, hasLength(4));
    }
    expect(qs.map((q) => q.dogruIndex).toSet().length, greaterThan(1));
  });

  test('question bank: 8-12 questions, three kinds', () async {
    final qs = await QuestionBank(
      access: _access,
      client: client,
    ).generate(chapterText: 'text', chapterTitle: 'Kaşağı');
    expect(qs.length, inInclusiveRange(8, 12));
    expect(qs.map((q) => q.tip).toSet(), QuestionKind.values.toSet());
  });

  test(
    'Ask: word and sentence explanations come back and say it is a demo',
    () async {
      final llm = LlmExplanation(access: _access, client: client);
      final word = await llm.fetch(
        target: 'kaşağı',
        isWord: true,
        sentence: 'Dadaruh eline kaşağıyı aldı.',
        contextText: 'Dadaruh eline kaşağıyı aldı.',
      );
      expect(word, contains('A curry comb'));
      final other = await llm.fetch(
        target: 'zırzop',
        isWord: true,
        sentence: 'Zırzop bir söz.',
        contextText: 'Zırzop bir söz.',
      );
      expect(other, contains('zırzop'));
      final sentence = await llm.fetch(
        target: 'Dadaruh onu kendi önüne alırdı.',
        isWord: false,
        sentence: 'Dadaruh onu kendi önüne alırdı.',
        contextText: 'x',
      );
      expect(sentence, isNotEmpty);
    },
  );

  group('private lesson', () {
    const chapters = ['Kaşağı', 'Forsa', 'Primo Türk Çocuğu'];
    test('every chapter x part (0-4) returns a valid lesson', () async {
      final tutor = LlmTutor(access: _access, client: client);
      for (final title in chapters) {
        for (var i = 0; i < 5; i++) {
          final part = LessonPart(
            index: i,
            fromPage: 1 + i,
            toPage: 2 + i,
            text: 'text',
          );
          final raw = await tutor.complete(
            system: kTutorSystemPrompt,
            user: buildLessonPrompt(
              part: part,
              totalParts: 5,
              bookTitle: 'Üç Hikâye (DEMO)',
              chapterTitle: title,
            ),
          );
          final step = parseLessonResponse(raw);
          expect(step.sorular, isNotEmpty);
          expect(step.anlatim.length, greaterThan(80));
        }
      }
    });

    test(
      'grading: close to the expected answer is correct, unrelated is wrong',
      () async {
        final tutor = LlmTutor(access: _access, client: client);
        const part = LessonPart(index: 0, fromPage: 1, toPage: 2, text: 'text');
        const q = TutorQuestion(
          soru: 'Whom does the child say broke the currycomb?',
          beklenen: 'He blames his brother Hasan, accusing him.',
        );
        Future<AnswerVerdict> grade(String answer) async => parseGradeResponse(
          await tutor.complete(
            system: kTutorSystemPrompt,
            user: buildGradePrompt(part: part, question: q, userAnswer: answer),
          ),
        ).verdict;
        expect(await grade('He blamed his brother Hasan'), AnswerVerdict.dogru);
        expect(await grade('Something about Hasan'), AnswerVerdict.yarim);
        expect(await grade('blue cloud'), AnswerVerdict.yanlis);
      },
    );
  });

  test('weekly report: carries the stats into the letter', () async {
    final report = await WeeklyReportExtractor(access: _access, client: client)
        .extract(
          stats: const WeeklyStats(
            toplam: 12,
            hakim: 3,
            devam: 5,
            vadesiGecen: 2,
          ),
        );
    expect(report.mektup, allOf(contains('12'), contains('3')));
  });

  test('an unrecognized system prompt lands in the unrouted list', () {
    final rec = RecordedRequest(
      method: 'POST',
      path: '/v1/chat/completions',
      originalHost: 'x',
      headers: const {},
      body: jsonEncode({
        'messages': [
          {'role': 'system', 'content': 'a completely different prompt'},
          {'role': 'user', 'content': 'hello'},
        ],
      }),
    );
    expect(router.respond(rec), isNull);
    expect(router.unrouted, hasLength(1));
    router.unrouted.clear(); // for the tearDown expectation
  });
}
