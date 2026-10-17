// Oracle RED test (2026-09-28 night, USER FEEDBACK -- listened on the phone):
// "it uses information from outside the book ... it never really describes the
// book; not directly like DeepSeek; too much safety ... silly things like 'let's
// make peace, it's for the good'" + "Make it even more toxic and direct. The
// debaters argue with each other about everything."
//
// Pinned contract (author prompts -- opening AND continuation):
//  - If book text is given, EVERY line rests on a concrete claim, concept or
//    example in the text; an everyday-life example is used only to explain that
//    idea.
//  - Each line directly opposes the previous one. Sarcastic and dismissive
//    objections are FREE. Agreement, consensus, politeness filler, "you're right
//    but", common ground, reconciliation and moral lectures are BANNED.
//    Limit: no profanity, no personal insults, no hate speech (so the Gemini
//    safety filter does not return an empty or blocked reply).
//  - Softening old lines are REMOVED: "present the book's information as the
//    speaker's own opinion" (it blocked describing the book), the mandatory
//    "alliance" moment, "a pure person changes their mind", and D's "SUPPORTS
//    ONE SIDE" line. An unfilled template leftover "{{KONU_VE_OZET}}" does not
//    reach the system prompt.
//  - KEPT user rule: 3-4 sentences.
//  - The SHIELD ban was lifted (S7b, user decision 2026-09-29 evening, in
//    writing: naming the book is fine, it is a nice way to give a reference).
//    The line "do not mention the book's title or author" is NOT in the prompt;
//    the book's title, author and the thinkers it names may be cited (source
//    attribution).
//  - The reviewer does not soften the harsh style and does not count it as an
//    error.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sesli_kitap/io/llm_discussion.dart';
import 'package:sesli_kitap/src/discussion/discussion_review.dart';

http.Response _ok() => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': 'A: one\nB: two'},
        'finish_reason': 'stop',
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<String> _systemPrompt({required bool continuation}) async {
  String? sys;
  final mock = MockClient((req) async {
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    sys = ((body['messages'] as List)[0] as Map)['content'] as String;
    return _ok();
  });
  final llm = LlmDiscussion(apiKey: 'k', client: mock);
  if (continuation) {
    await llm.generateContinuation('topic', const []);
  } else {
    await llm.generate('topic');
  }
  return sys!;
}

void main() {
  for (final continuation in [false, true]) {
    final label = continuation ? 'continuation prompt' : 'opening prompt';

    group(label, () {
      test('grounded in the book: every line rests on a concrete claim/concept/example '
          'in the text; NO out-of-text examples (closed box)', () async {
        final sys = await _systemPrompt(continuation: continuation);
        expect(
          sys,
          contains(
            'EVERY line rests on a concrete claim, concept or example in the text',
          ),
        );
        // CLOSED BOX (user spec 2026-09-30; field: 6 examples not in the source
        // across 13 lines): out-of-text everyday examples are NO LONGER free.
        expect(sys, isNot(contains('everyday-life examples are FREE')));
        expect(sys, contains('CLOSED BOX'));
      });

      test('direct and harsh: opposes the previous line, sarcastic objection is free, '
          'consensus/politeness/moral lecture are BANNED', () async {
        final sys = await _systemPrompt(continuation: continuation);
        expect(sys, contains('directly opposes the previous one'));
        expect(sys, contains('sarcastically'));
        for (final banned in [
          // Live L2 (agent3): an approval like "you're right since you broke the
          // myth" without "but"; the ban must also cover the bare "you're right".
          '"haklısın", "haklısın ama"',
          '"haklısın ama"',
          '"barışalım"',
          '"iyilik olsun"',
          'meeting in the middle',
          'moral lessons',
        ]) {
          expect(
            sys,
            contains(banned),
            reason: '$banned is in the banned list',
          );
        }
      });

      test(
        'limit: the prompt covers profanity / personal insults / hate speech',
        () async {
          final sys = await _systemPrompt(continuation: continuation);
          expect(sys, contains('profanity'));
          expect(sys, contains('personal insults'));
          expect(sys, contains('hate speech'));
        },
      );

      test('the softening old lines were REMOVED', () async {
        final sys = await _systemPrompt(continuation: continuation);
        expect(sys, isNot(contains("present it as the speaker's own opinion")));
        expect(sys, isNot(contains('alliance')));
        expect(sys, isNot(contains('a pure person changes their mind')));
        expect(sys, isNot(contains('SUPPORTS ONE SIDE')));
      });

      test(
        'the kept user rule is 3-4 sentences; the ban on the book title/author was '
        'LIFTED, mentioning them is allowed',
        () async {
          final sys = await _systemPrompt(continuation: continuation);
          expect(sys, contains('at least 3 and at most 4 sentences'));
          expect(
            sys,
            isNot(contains("do not mention the book's title and author")),
          );
          expect(sys, isNot(contains('do not mention the author')));
          // The side effect of the old ban, the workaround "cite it as 'the text' or
          // 'the idea put forward here'", is gone too (it only existed to avoid
          // naming the book).
          expect(sys, isNot(contains('"the idea put forward here"')));
          expect(
            sys,
            contains(
              "You may mention the book's title, its author, and the "
              'thinkers and researchers named in the book.',
            ),
          );
          // The rule that the speaker must NOT name THEMSELVES (separate rule)
          // stays exactly as it is.
          expect(sys, contains('A speaker NEVER addresses themselves'));
        },
      );
    });
  }

  test('opening prompt: no unfilled template leftover ({{...}})', () async {
    final sys = await _systemPrompt(continuation: false);
    expect(sys, isNot(contains('{{')));
  });

  test(
    'reviewer does not soften the harsh style and does not count it as an error',
    () {
      expect(
        reviewerPrompt,
        contains('keep the harshness, sarcasm and objection EXACTLY'),
      );
      expect(reviewerPrompt, contains('disagreement are NOT ERRORS'));
    },
  );
}
