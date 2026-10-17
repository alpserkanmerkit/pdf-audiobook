// DQ-W2 (Akim B2) RED tests: the io/wiring layer of the "author -> review ->
// fix" chain. Core (lib/src/discussion/discussion_review.dart, already merged):
// ReviewResult/ReviewCorrection, parseReviewResponse (fail-open null),
// applyReviewCorrections (range-safe, immutable), shouldReview, reviewerPrompt
// (focused on names + repetition + length; NO check for stance).
//
// This file targets a surface that DOES NOT EXIST YET:
// `LlmDiscussion.generateReviewed(topic)` -- a new public method that shares the
// same typed-exception contract as generate(), and ADDITIONALLY sends batch 1
// through the automatic review (per the shouldReview policy) and applies
// applyReviewCorrections. The existing generate()/generateContinuation() methods
// are NOT touched (B1 works there) -- so the tests target ONLY the new method,
// keeping the overlap surface minimal.
//
// Contract (pinned by these RED tests):
// - generateReviewed first makes the author call (same system/user contract as
//   generate), and turns the script into turns with parseDiscussionScript.
// - Then, because shouldReview(batchIndex: 0) is TRUE, a SECOND LLM call is made
//   with reviewerPrompt (same endpoint/key).
// - The reviewer reply is parsed with parseReviewResponse:
//   * ok:true or corrections empty -> the original turns are used AS-IS.
//   * ok:false + valid corrections -> applyReviewCorrections is applied.
//   * reviewer HTTP error / broken body / unparseable reply -> FAIL-OPEN: the
//     original (uncorrected) turns are used as-is, and no exception leaks.
// - The return value is always List<DiscussionTurn> (same type as generate).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sesli_kitap/io/llm_discussion.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';

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

/// Helper for sequenced requests: tells the author and reviewer prompts apart
/// by the system message of each body. The reviewer prompt carries the content
/// pin "Your ONLY task is to perform these four checks" (see the reviewerPrompt tests in
/// discussion_review_test.dart, which are consistent with this).
bool _isReviewerRequest(http.Request req) {
  final body = jsonDecode(req.body) as Map<String, dynamic>;
  final messages = body['messages'] as List;
  final sys = (messages[0] as Map)['content'] as String;
  return sys.contains('Your ONLY task is to perform these four checks');
}

void main() {
  group('generateReviewed — batch 1 is ALWAYS reviewed (shouldReview)', () {
    test(
      'author + reviewer make TWO SEPARATE LLM calls (the reviewer prompt is included)',
      () async {
        final requests = <http.Request>[];
        final mock = MockClient((req) async {
          requests.add(req);
          if (_isReviewerRequest(req)) {
            return _ok('{"ok": true, "corrections": []}');
          }
          return _ok('A: one\nB: two');
        });

        final turns = await LlmDiscussion(
          apiKey: 'test-key',
          client: mock,
        ).generateReviewed('brain and sleep');

        expect(
          requests.length,
          2,
          reason: 'author call + batch-1 reviewer call (shouldReview true)',
        );
        expect(turns, hasLength(2));
        expect(turns[0].speaker, DiscussionSpeaker.a);
        expect(turns[1].speaker, DiscussionSpeaker.b);
      },
    );

    test(
      'if the reviewer returns ok:true, the original turns are kept AS-IS',
      () async {
        final mock = MockClient((req) async {
          if (_isReviewerRequest(req)) {
            return _ok(
              '{"ok": true, "corrections": '
              '[{"index": 0, "text": "should-not-be-used"}]}',
            );
          }
          return _ok('A: original line\nB: second line');
        });

        final turns = await LlmDiscussion(
          apiKey: 'k',
          client: mock,
        ).generateReviewed('topic');

        expect(turns[0].text, 'original line');
        expect(turns[1].text, 'second line');
      },
    );

    test(
      'if the reviewer returns ok:false + a valid correction, applyReviewCorrections is applied',
      () async {
        final mock = MockClient((req) async {
          if (_isReviewerRequest(req)) {
            return _ok(
              '{"ok": false, "corrections": '
              '[{"index": 0, "text": "Used the correct name instead of Ahmet"}]}',
            );
          }
          return _ok('A: Emel, what do you think\nB: second line');
        });

        final turns = await LlmDiscussion(
          apiKey: 'k',
          client: mock,
        ).generateReviewed('topic');

        expect(
          turns[0].speaker,
          DiscussionSpeaker.a,
          reason: 'speaker does not change',
        );
        expect(turns[0].text, 'Used the correct name instead of Ahmet');
        expect(
          turns[1].text,
          'second line',
          reason: 'uncorrected line stays as-is',
        );
      },
    );

    test(
      'if the reviewer suggests an out-of-range index it is safely skipped (applyReviewCorrections contract)',
      () async {
        final mock = MockClient((req) async {
          if (_isReviewerRequest(req)) {
            return _ok(
              '{"ok": false, "corrections": [{"index": 99, "text": "ignored"}]}',
            );
          }
          return _ok('A: one\nB: two');
        });

        final turns = await LlmDiscussion(
          apiKey: 'k',
          client: mock,
        ).generateReviewed('topic');

        expect(turns[0].text, 'one');
        expect(turns[1].text, 'two');
      },
    );
  });

  group('generateReviewed — FAIL-OPEN (reviewer fails -> original script)', () {
    test(
      'reviewer HTTP error (500) -> original turns returned as-is, exception does NOT leak',
      () async {
        final mock = MockClient((req) async {
          if (_isReviewerRequest(req)) {
            return http.Response('server error', 500);
          }
          return _ok('A: one\nB: two');
        });

        final turns = await LlmDiscussion(
          apiKey: 'k',
          client: mock,
        ).generateReviewed('topic');

        expect(turns, hasLength(2));
        expect(turns[0].text, 'one');
        expect(turns[1].text, 'two');
      },
    );

    test(
      'reviewer returns a malformed JSON body -> original turns returned as-is',
      () async {
        final mock = MockClient((req) async {
          if (_isReviewerRequest(req)) {
            return _ok('this is not valid JSON, plain text');
          }
          return _ok('A: one\nB: two');
        });

        final turns = await LlmDiscussion(
          apiKey: 'k',
          client: mock,
        ).generateReviewed('topic');

        expect(turns[0].text, 'one');
        expect(turns[1].text, 'two');
      },
    );

    test(
      'reviewer returns an HTML/gateway body (200, not JSON) -> original turns returned as-is',
      () async {
        final mock = MockClient((req) async {
          if (_isReviewerRequest(req)) {
            return http.Response('<html>error</html>', 200);
          }
          return _ok('A: one\nB: two');
        });

        final turns = await LlmDiscussion(
          apiKey: 'k',
          client: mock,
        ).generateReviewed('topic');

        expect(turns[0].text, 'one');
        expect(turns[1].text, 'two');
      },
    );

    test(
      'reviewer returns empty content -> original turns returned as-is',
      () async {
        final mock = MockClient((req) async {
          if (_isReviewerRequest(req)) {
            return _ok('   ');
          }
          return _ok('A: one\nB: two');
        });

        final turns = await LlmDiscussion(
          apiKey: 'k',
          client: mock,
        ).generateReviewed('topic');

        expect(turns[0].text, 'one');
        expect(turns[1].text, 'two');
      },
    );

    test(
      'if the author call fails, the reviewer is NEVER called and LlmDiscussionException '
      'is thrown (same typed-exception contract as generate)',
      () async {
        var reviewerCalled = false;
        final mock = MockClient((req) async {
          if (_isReviewerRequest(req)) {
            reviewerCalled = true;
            return _ok('{"ok": true, "corrections": []}');
          }
          return http.Response('server error', 500);
        });

        await expectLater(
          LlmDiscussion(apiKey: 'k', client: mock).generateReviewed('topic'),
          throwsA(isA<LlmDiscussionException>()),
        );
        expect(
          reviewerCalled,
          isFalse,
          reason: 'if the author fails, no script is produced to review',
        );
      },
    );
  });

  group('generateReviewed — reviewer prompt body (content pin)', () {
    test(
      'the reviewer call carries the reviewerPrompt system message + batch text as the user message',
      () async {
        Map<String, dynamic>? reviewerBody;
        final mock = MockClient((req) async {
          if (_isReviewerRequest(req)) {
            reviewerBody = jsonDecode(req.body) as Map<String, dynamic>;
            return _ok('{"ok": true, "corrections": []}');
          }
          return _ok('A: one\nB: two');
        });

        await LlmDiscussion(
          apiKey: 'k',
          client: mock,
        ).generateReviewed('topic');

        expect(reviewerBody, isNotNull);
        // Gemini pass: 3-4 sentence lines + corrections are written back in JSON
        // -> the reviewer cap is also 3000 (oracle mutation probe M07).
        expect(reviewerBody!['max_tokens'], 3000);
        // Live measurement (agent3 L1, 2026-09-28 night): the reviewer ignored the
        // "JSON only" rule and first wrote a "#0: 4 sentences..." list for 36
        // lines; it was cut at 2995/3000 while starting the JSON -> parse failed,
        // 10.5 s wasted. JSON mode closes this structurally (same as cleaner/auditor).
        expect(reviewerBody!['response_format'], {'type': 'json_object'});
        final sys =
            ((reviewerBody!['messages'] as List)[0] as Map)['content']
                as String;
        expect(sys, contains('NAME:'));
        expect(sys, contains('ok'));
        expect(sys, contains('corrections'));
        final user =
            ((reviewerBody!['messages'] as List)[1] as Map)['content']
                as String;
        expect(user, contains('A: one'));
        expect(user, contains('B: two'));
      },
    );

    test(
      'batch lines are numbered 0-based as "#<index>" (measurement T3: with unnumbered '
      'lines the model counted by itself and said index 35 instead of 36)',
      () async {
        String? user;
        final mock = MockClient((req) async {
          if (_isReviewerRequest(req)) {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            user = ((body['messages'] as List)[1] as Map)['content'] as String;
            return _ok('{"ok": true, "corrections": []}');
          }
          return _ok('A: one\nB: two\nC: three');
        });

        await LlmDiscussion(
          apiKey: 'k',
          client: mock,
        ).generateReviewed('topic');

        expect(user, contains('#0 A: one'));
        expect(user, contains('#1 B: two'));
        expect(user, contains('#2 C: three'));
      },
    );
  });
}
