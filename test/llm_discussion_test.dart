// Oracle test (Slice-1.1): LlmDiscussion IO/HTTP/parse error chain.
// lib/io HTTP body is outside the coverage gate -> body-assert + error chain can only be pinned
// by a MockClient test (sibling llm_cleaner_request_test pattern).
// §13.7 dep-layer guard: the "Tartis" (debate) flow -> generate() is live; regressions reach the user.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sesli_kitap/io/llm_discussion.dart';
import 'package:sesli_kitap/src/discussion/discussion_budget.dart';
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

void main() {
  test(
    'generate body: gemini-3.8-flash + reasoning_effort:low + temperature + max_tokens',
    () async {
      Map<String, dynamic>? body;
      final mock = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return _ok('A: hello\nB: hi');
      });
      final turns = await LlmDiscussion(
        apiKey: 'test-key',
        client: mock,
      ).generate('brain and sleep');
      expect(turns, hasLength(2));
      expect(turns[0].speaker, DiscussionSpeaker.a);
      expect(turns[1].speaker, DiscussionSpeaker.b);
      expect(body, isNotNull);
      expect(body!['model'], 'gemini-3.8-flash');
      expect(body!['reasoning_effort'], 'low');
      expect(body!['temperature'], 0.85);
      // Gemini migration (measured): 14 turns x 3-4 sentences ~= 1800-2350 output
      // tokens -- the old 2000 opening cap is NOT enough, raised to 3000.
      expect(body!['max_tokens'], 3000);
      // Slice-2: the system prompt v2 is a 4-voice director prompt (A/B/C/D).
      final sys = ((body!['messages'] as List)[0] as Map)['content'] as String;
      // User feedback (2026-09-28, VERBATIM): instead of a one-sentence turn, the rule is a
      // 3-4 sentence, connecting, explanatory turn.
      expect(
        sys,
        contains(
          'EVERY LINE is at least 3 and at most 4 sentences. Sentences connect: '
          'the speaker bridges what was said before and their own idea, and gives '
          'their reasoning and example in an explanatory tone. A one-sentence line '
          'is FORBIDDEN; but a monologue longer than 4 sentences is also FORBIDDEN.',
        ),
      );
      expect(sys, isNot(contains('180 karakteri GEÇMEZ')));
      expect(sys, isNot(contains('TEK BİR DÜŞÜNCE')));
      expect(sys, contains('A, B, C and D'));
      // PR-Q1 (finding #6 name fix): real names are TOLD to the model + speakers address each other ONLY
      // by real name + letter tokens NEVER appear + the rule of not naming oneself.
      expect(sys, contains('A=Ahmet'));
      expect(sys, contains('B=Emel'));
      expect(sys, contains('C=Deniz'));
      expect(sys, contains('D=Kaya'));
      expect(
        sys,
        contains('Speakers address each other ONLY by these real names'),
      );
      expect(sys, contains('addresses themselves'));
      // Example patterns now use real names, NOT letters (finding #6 root cause:
      // the model learned to address by letter INSIDE the conversation from the examples).
      expect(sys, contains('az önce Ahmet şunu dedi ama'));
      expect(sys, contains('Dur Ahmet, sözünü keseceğim'));
      expect(sys, isNot(contains('az önce A şunu dedi ama')));
      expect(sys, isNot(contains('Dur A, sözünü keseceğim')));
      // Phase (natural texture): light conversational filler encouragement -- may be used
      // occasionally, NOT in EVERY turn (overuse must not slide into everyday chatter -- the
      // existing firm/assertive tone is kept).
      expect(sys, contains('Natural speech texture'));
      expect(sys, contains('"yani"'));
      expect(sys, contains('"dur"'));
      expect(sys, contains('"aslında"'));
      expect(sys, contains('NOT in every line'));
      // User decision 2026-09-28 (option b): the filler permission STAYS, but the old
      // "the turn is again ONE thought, stays firm and short" part is removed from the prompt,
      // because it CONFLICTS with the 3-4 sentence rule (so the model does not get contradictory instructions).
      expect(sys, isNot(contains('TEK düşünce')));
      expect(sys, isNot(contains('kısa kalır')));
      expect(
        sys,
        contains(
          'a short filler like "yani", "dur", "aslında" may be used; '
          'do not slide into everyday chatter.',
        ),
      );
      // User decision 2026-09-28: thinkers named in the book may be cited (the live probe cited
      // Hildebrandt/Radestock). S7b user decision 2026-09-29 evening (written): "It may mention
      // them; it gives a nice reference." -> the ban on "do not mention the book's name and author"
      // was LIFTED; the book's title and author may also be cited (llm_discussion_style_test.dart).
      expect(sys, isNot(contains('Kaynak adını ağzına alma')));
      expect(sys, isNot(contains('Kitabın adını ve yazarını ağzına alma')));
      expect(
        sys,
        contains(
          "You may mention the book's title, its author, and the thinkers and "
          'researchers named in the book.',
        ),
      );
      // ROOT-CAUSE FIX (device evidence 08.07, Bug#1): the finite-mode opening prompt must also
      // (in the SAME spirit as the continuation prompt) recognise and handle the
      // "LISTENER DIRECTION:" line -- previously this instruction existed ONLY in the continuation
      // prompt, so even if a chip pressed while idle was injected into the first generation,
      // the model had NO instruction to recognise it.
      expect(sys, contains('LISTENER DIRECTION:'));
    },
  );

  // DQ-W1 RED test (body pin): if a mode is given, generate() embeds the selected mode's
  // target word/turn count into the system prompt. If no mode is given (old call form),
  // behaviour stays identical (the tests above pin this).
  group('generate — length-mode target is embedded in the prompt', () {
    test(
      'mode: uzun -> ~2150 word target + rough turn count in the prompt',
      () async {
        Map<String, dynamic>? body;
        final mock = MockClient((req) async {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return _ok('A: one\nB: two');
        });
        await LlmDiscussion(
          apiKey: 'k',
          client: mock,
        ).generate('topic', mode: DiscussionLengthMode.uzun);

        final sys =
            ((body!['messages'] as List)[0] as Map)['content'] as String;
        expect(sys, contains('2150'));
        // User feedback (2026-09-28): the average turn length rose from 32 words to ~65 words
        // (3-4 sentence turn rule) -> ceil(2150/65) = 34 rough turns (the old 32 gave ~67).
        expect(sys, contains('~34 lines'));
      },
    );

    test('mode: kisa -> 550-word target in the prompt', () async {
      Map<String, dynamic>? body;
      final mock = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return _ok('A: one\nB: two');
      });
      await LlmDiscussion(
        apiKey: 'k',
        client: mock,
      ).generate('topic', mode: DiscussionLengthMode.kisa);

      final sys = ((body!['messages'] as List)[0] as Map)['content'] as String;
      expect(sys, contains('550'));
    });

    test(
      'mode: sonsuz -> NO word target added (the existing opening rule stays)',
      () async {
        Map<String, dynamic>? body;
        final mock = MockClient((req) async {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return _ok('A: one\nB: two');
        });
        await LlmDiscussion(
          apiKey: 'k',
          client: mock,
        ).generate('topic', mode: DiscussionLengthMode.sonsuz);

        final sys =
            ((body!['messages'] as List)[0] as Map)['content'] as String;
        // In sonsuz (infinite) mode no special word target is injected -- the opening turn
        // stays bounded by the existing "AT LEAST 12, at most 16" rule.
        expect(sys, isNot(contains('TARGET WORDS')));
      },
    );

    test(
      'if no mode is given (old call) the word-target block is NOT added at all',
      () async {
        Map<String, dynamic>? body;
        final mock = MockClient((req) async {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return _ok('A: one\nB: two');
        });
        await LlmDiscussion(apiKey: 'k', client: mock).generate('topic');

        final sys =
            ((body!['messages'] as List)[0] as Map)['content'] as String;
        expect(sys, isNot(contains('TARGET WORDS')));
      },
    );
  });

  // DQ-W1 REWORK (adversarial review MAJOR): prompt INTERNAL CONSISTENCY.
  // In the finite modes (Short/Medium/Long) the system prompt must NOT contain a HARD turn limit
  // such as "at most 16 lines" alongside the mode target (contradiction).
  // In sonsuz/null the old 12-16 opening rule is kept.
  group('generate — prompt internal consistency (no mode-limit contradiction)', () {
    Future<String> sysFor(DiscussionLengthMode? mode) async {
      Map<String, dynamic>? body;
      final mock = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return _ok('A: one\nB: two');
      });
      await LlmDiscussion(
        apiKey: 'k',
        client: mock,
      ).generate('topic', mode: mode);
      return ((body!['messages'] as List)[0] as Map)['content'] as String;
    }

    test(
      'finite modes must NOT have a rigid "16 turns" limit in the prompt',
      () async {
        for (final mode in [
          DiscussionLengthMode.kisa,
          DiscussionLengthMode.orta,
          DiscussionLengthMode.uzun,
        ]) {
          final sys = await sysFor(mode);
          expect(
            sys,
            isNot(contains('at most 16')),
            reason:
                'in $mode mode, the mode target contradicts a rigid 16-turn limit; '
                'in a finite mode, a single consistent target must come from the mode',
          );
          expect(
            sys,
            isNot(contains('AT LEAST 12')),
            reason:
                'in $mode mode, the fixed 12-turn lower limit also contradicts',
          );
        }
      },
    );

    test('in sonsuz mode the old 12-16 opening rule is KEPT', () async {
      final sys = await sysFor(DiscussionLengthMode.sonsuz);
      expect(sys, contains('AT LEAST 12'));
      expect(sys, contains('at most 16'));
    });

    test('if no mode is given (old call) the 12-16 rule is KEPT', () async {
      final sys = await sysFor(null);
      expect(sys, contains('AT LEAST 12'));
      expect(sys, contains('at most 16'));
    });
  });

  // DQ-W1 REWORK (MAJOR): max_tokens scales with the mode -- the fixed 2000 was not enough for the
  // uzun (~2150 words) target. Kisa<Orta<Uzun increasing; sonsuz/null opening value 3000
  // (Gemini migration: 2000 was not enough for 3-4 sentence turns).
  group('generate — max_tokens scales with the mode', () {
    Future<int> maxTokensFor(DiscussionLengthMode? mode) async {
      Map<String, dynamic>? body;
      final mock = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return _ok('A: one\nB: two');
      });
      await LlmDiscussion(
        apiKey: 'k',
        client: mock,
      ).generate('topic', mode: mode);
      return body!['max_tokens'] as int;
    }

    test(
      'in uzun mode max_tokens is large enough to hold 2150 words',
      () async {
        final t = await maxTokensFor(DiscussionLengthMode.uzun);
        // ~2150 Turkish words is roughly >= 4000 tokens; a safe lower bound.
        expect(t, greaterThanOrEqualTo(4000));
      },
    );

    test('max_tokens increases: kisa < orta < uzun', () async {
      final kisa = await maxTokensFor(DiscussionLengthMode.kisa);
      final orta = await maxTokensFor(DiscussionLengthMode.orta);
      final uzun = await maxTokensFor(DiscussionLengthMode.uzun);
      expect(kisa, lessThan(orta));
      expect(orta, lessThan(uzun));
    });

    test(
      'sonsuz/null -> new opening value 3000 (the old 2000 was not enough for long turns)',
      () async {
        expect(await maxTokensFor(DiscussionLengthMode.sonsuz), 3000);
        expect(await maxTokensFor(null), 3000);
      },
    );
  });

  test('4-voice A/B/C/D response is parsed into 4 turns', () async {
    final mock = MockClient(
      (req) async => _ok('A: one\nB: two\nC: three\nD: four'),
    );
    final turns = await LlmDiscussion(
      apiKey: 'k',
      client: mock,
    ).generate('topic');
    expect(turns, hasLength(4));
    expect(turns[0].speaker, DiscussionSpeaker.a);
    expect(turns[2].speaker, DiscussionSpeaker.c);
    expect(turns[3].speaker, DiscussionSpeaker.d);
  });

  test('HTTP != 200 -> LlmDiscussionException', () async {
    final mock = MockClient((req) async => http.Response('server error', 500));
    await expectLater(
      LlmDiscussion(apiKey: 'k', client: mock).generate('topic'),
      throwsA(isA<LlmDiscussionException>()),
    );
  });

  // FAZ3a K9: HTTP 200 + non-JSON body (gateway HTML) currently escapes as a raw
  // FormatException (OUTSIDE the jsonDecode try/catch) -> violates the typed-exception contract.
  // Expected: LlmDiscussionException.
  test('HTTP 200 + non-JSON body -> LlmDiscussionException', () async {
    final mock = MockClient(
      (req) async => http.Response('<html>error</html>', 200),
    );
    await expectLater(
      LlmDiscussion(apiKey: 'k', client: mock).generate('topic'),
      throwsA(isA<LlmDiscussionException>()),
    );
  });

  test('empty content -> LlmDiscussionException', () async {
    final mock = MockClient((req) async => _ok('   '));
    await expectLater(
      LlmDiscussion(apiKey: 'k', client: mock).generate('topic'),
      throwsA(isA<LlmDiscussionException>()),
    );
  });

  test('unparseable content (no labels) -> LlmDiscussionException', () async {
    final mock = MockClient((req) async => _ok('no labels plain text'));
    await expectLater(
      LlmDiscussion(apiKey: 'k', client: mock).generate('topic'),
      throwsA(isA<LlmDiscussionException>()),
    );
  });

  // ── S2: generateContinuation (sonsuz mode continuation turn) ───────────────────
  // The continuation call uses the same model/parameters BUT the continuation system prompt
  // and the last-turn history are passed. The body is pinned with MockClient (sibling
  // "generate body" test pattern); the shared _complete contract -> the error chain
  // throws the same typed exception as generate.
  group('generateContinuation — continuation turn (sonsuz mode)', () {
    test('body: gemini-3.8-flash + reasoning_effort:low + temp + max_tokens 3000 + '
        'continuation rules as system + last-turn history as user', () async {
      Map<String, dynamic>? body;
      final mock = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return _ok('C: new front\nD: concrete data');
      });
      const recent = [
        DiscussionTurn(DiscussionSpeaker.a, 'The first claim was this.'),
        DiscussionTurn(DiscussionSpeaker.b, 'I object to this.'),
      ];
      final turns = await LlmDiscussion(
        apiKey: 'test-key',
        client: mock,
      ).generateContinuation('brain and sleep', recent);

      expect(turns, hasLength(2));
      expect(turns[0].speaker, DiscussionSpeaker.c);
      expect(turns[1].speaker, DiscussionSpeaker.d);

      expect(body, isNotNull);
      // Same model/parameters as generate.
      expect(body!['model'], 'gemini-3.8-flash');
      expect(body!['reasoning_effort'], 'low');
      expect(body!['temperature'], 0.85);
      expect(body!['max_tokens'], 3000);

      final sys = ((body!['messages'] as List)[0] as Map)['content'] as String;
      // Continuation system prompt: the DEBATE NEVER ENDS constraint + the no-repetition ban.
      expect(sys, contains('THE DISCUSSION DOES NOT END'));
      // generate's "AT LEAST 12" turn rule must NOT be in the continuation prompt
      // (continuation is at most 12 NEW turns; a fixed 12-turn requirement would be wrong).
      expect(sys, isNot(contains('AT LEAST 12')));
      // Live-API spike (internal design note) verdict: three surgical additions
      // must be present in the continuation prompt. NOTE: LLM output is not deterministic ->
      // only the prompt text is pinned (NOT the behaviour).
      // 1) The new 3-4 sentence rule in the shared _speakerRulesBlock also applies here
      //    (shared block); the old tight 140-character cap was REMOVED.
      expect(sys, contains('EVERY LINE is at least 3 and at most 4 sentences'));
      expect(sys, isNot(contains('140 karakteri GEÇMEZ')));
      //    The continuation-SPECIFIC repetition line is also pinned (the same prefix in the
      //    shared block was masking it -- oracle mutation probe M09 survived).
      expect(
        sys,
        contains('EVERY LINE again has at least 3 and at most 4 sentences'),
      );
      //    The conflicting "stays short" part from the shared block is also absent here.
      expect(sys, isNot(contains('TEK düşünce')));
      expect(sys, isNot(contains('kısa kalır')));
      // 2) ban on repeating metaphors/examples (the leak round the mechanical similarity scan missed).
      expect(sys, contains('METAPHORS'));
      // 3) ban on synthesis/consensus sentences (C's tendency to arbitrate).
      expect(sys, contains('merges both sides'));
      // PR-Q1 name fix: the continuation prompt shares the same _speakerRulesBlock,
      // so the name rule must be here too (same voices/constraints as the opening -- no drift).
      expect(sys, contains('A=Ahmet'));
      expect(
        sys,
        contains('Speakers address each other ONLY by these real names'),
      );
      // The same shared _speakerRulesBlock -> the natural-texture encouragement is also in
      // the continuation (same voices/constraints as the opening, no drift).
      expect(sys, contains('Natural speech texture'));
      // PR (interactive direction): the continuation prompt contains the listener-direction
      // rule -- if present it must be addressed in the NEXT 2-3 turns, without breaking the format.
      expect(sys, contains('LISTENER DIRECTION'));
      expect(sys, contains('2-3 lines'));

      // The user message contains the last-turn history (labelled A: ...) + the topic.
      final user = ((body!['messages'] as List)[1] as Map)['content'] as String;
      expect(user, contains('brain and sleep'));
      expect(user, contains('A: The first claim was this.'));
      expect(user, contains('B: I object to this.'));
    });

    test('C/D response is parsed into turns', () async {
      final mock = MockClient(
        (req) async =>
            _ok('A: continue one\nB: continue two\nC: continue three'),
      );
      final turns = await LlmDiscussion(apiKey: 'k', client: mock)
          .generateContinuation('topic', const [
            DiscussionTurn(DiscussionSpeaker.d, 'previous'),
          ]);
      expect(turns, hasLength(3));
      expect(turns[0].speaker, DiscussionSpeaker.a);
      expect(turns[2].speaker, DiscussionSpeaker.c);
    });

    test('HTTP != 200 -> LlmDiscussionException (shared _complete)', () async {
      final mock = MockClient(
        (req) async => http.Response('server error', 500),
      );
      await expectLater(
        LlmDiscussion(apiKey: 'k', client: mock).generateContinuation(
          'topic',
          const [DiscussionTurn(DiscussionSpeaker.a, 'x')],
        ),
        throwsA(isA<LlmDiscussionException>()),
      );
    });

    test('broken (non-JSON) 200 body -> LlmDiscussionException', () async {
      final mock = MockClient(
        (req) async => http.Response('<html>error</html>', 200),
      );
      await expectLater(
        LlmDiscussion(apiKey: 'k', client: mock).generateContinuation(
          'topic',
          const [DiscussionTurn(DiscussionSpeaker.a, 'x')],
        ),
        throwsA(isA<LlmDiscussionException>()),
      );
    });
  });
}
