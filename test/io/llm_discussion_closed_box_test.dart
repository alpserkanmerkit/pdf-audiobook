// Oracle RED test (2026-09-30, user spec "closed box" discussion, B2/K3/K4).
//
// Field measurement (phone, 09-30 14:05, dokum_1405.txt): 13 lines with ad
// hominem, chip/environment, thief, court, obese doctor, asthma/chemist
// examples -- NONE of these 4 source pages contain them (grep). The prompt said
// "everyday-life examples are FREE".
//
// Unit-measurable part: the closed-box rule (a SINGLE constant, kClosedBoxRule)
// enters the system prompt of EVERY production path (first generation,
// continuation batch, listener-question answer), and the book text enters the
// user message. Whether the model FOLLOWS the rule is measured in the field
// (oracle), not here.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sesli_kitap/io/llm_client.dart' show llmRetryDelays;
import 'package:sesli_kitap/io/llm_discussion.dart';
import 'package:sesli_kitap/src/discussion/discussion_book_source.dart';
import 'package:sesli_kitap/src/discussion/discussion_budget.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';

http.Response _ok(String content) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': content},
        'finish_reason': 'stop',
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

const _source = DiscussionBookSource(
  fromPage: 1,
  toPage: 13,
  text: 'Tabut benzetmesi: Peel metni boyle anlatir.',
  pageCount: 4,
);

final String _topic = withBookSource('Madsen — Chapter 1', _source);

class _Captured {
  final bodies = <Map<String, dynamic>>[];
  String sys(int i) =>
      ((bodies[i]['messages'] as List)[0] as Map)['content'] as String;
  String user(int i) =>
      ((bodies[i]['messages'] as List)[1] as Map)['content'] as String;
}

LlmDiscussion _llm(_Captured cap, String reply) => LlmDiscussion(
  apiKey: 'k',
  client: MockClient((req) async {
    cap.bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
    return _ok(reply);
  }),
);

void main() {
  group('K3 -- closed-box rule on every generation path', () {
    test(
      'first generation (generate, every mode): the system prompt carries the '
      'rule, the user message carries the book text',
      () async {
        for (final mode in [null, ...DiscussionLengthMode.values]) {
          final cap = _Captured();
          await _llm(cap, 'A: one\nB: two').generate(_topic, mode: mode);
          expect(cap.sys(0), contains(kClosedBoxRule), reason: 'mode: $mode');
          expect(cap.user(0), contains(_source.text));
        }
      },
    );

    test(
      'continuation batch (generateContinuation): rule + book text',
      () async {
        final cap = _Captured();
        await _llm(cap, 'A: one\nB: two').generateContinuation(_topic, const [
          DiscussionTurn(DiscussionSpeaker.a, 'previous'),
        ]);
        expect(cap.sys(0), contains(kClosedBoxRule));
        expect(cap.user(0), contains(_source.text));
      },
    );

    test('the prompt does not leave out-of-text examples FREE; examples and '
        'counter-examples come FROM THE TEXT', () async {
      for (final continuation in [false, true]) {
        final cap = _Captured();
        final llm = _llm(cap, 'A: one\nB: two');
        if (continuation) {
          await llm.generateContinuation(_topic, const []);
        } else {
          await llm.generate(_topic);
        }
        final sys = cap.sys(0);
        expect(sys, isNot(contains('everyday-life examples are FREE')));
        expect(sys, isNot(contains('find a new image/example in every party')));
        expect(
          sys,
          contains('brings a concrete counter-example/evidence FROM THE TEXT'),
        );
        expect(sys, contains('a concrete example/fact FROM THE TEXT'));
      }
    });
  });

  group('K4 -- listener question answer (generateAnswer)', () {
    test('system prompt: closed-box rule + 2-4 line answer rule; user message: '
        'book text + last lines + (sanitized) question', () async {
      final cap = _Captured();
      final turns =
          await _llm(
            cap,
            'A: Dinleyicimiz soruyor.\nB: Kitapta bu geçmiyor.',
          ).generateAnswer(_topic, 'Tabut\n\nneyi   anlatıyor?', const [
            DiscussionTurn(DiscussionSpeaker.c, 'last line text'),
          ]);

      expect(_texts(turns), ['Dinleyicimiz soruyor.', 'Kitapta bu geçmiyor.']);
      final sys = cap.sys(0);
      expect(sys, contains(kClosedBoxRule));
      expect(sys, contains('AT LEAST 2 and at most 4'));
      final user = cap.user(0);
      expect(user, contains(_source.text));
      expect(user, contains('C: last line text'));
      expect(user, contains('LISTENER QUESTION: Tabut neyi anlatıyor?'));
      expect(cap.bodies.single['max_tokens'], 2000);
    });

    test(
      'if the model writes more than 4 lines, the first 4 are played',
      () async {
        final cap = _Captured();
        final turns = await _llm(
          cap,
          'A: one\nB: two\nC: three\nD: four\nA: five\nB: six',
        ).generateAnswer(_topic, 'question', const []);
        expect(_texts(turns), ['one', 'two', 'three', 'four']);
      },
    );

    test('an HTTP error throws the same typed exception as generate', () async {
      final slept = <Duration>[];
      final llm = LlmDiscussion(
        apiKey: 'k',
        client: MockClient((req) async => http.Response('quota', 429)),
        sleep: (d) async => slept.add(d),
      );
      await expectLater(
        llm.generateAnswer(_topic, 'question', const []),
        throwsA(isA<LlmDiscussionException>()),
      );
      expect(slept, llmRetryDelays);
    });
  });
}

List<String> _texts(List<DiscussionTurn> turns) =>
    turns.map((t) => t.text).toList();
