// Oracle RED test (2026-09-30, user spec "closed box" + B4).
//
// Field measurement (phone 09-30 13:5x): "Ask" in Endless mode only went to
// the NEXT continuation discussion; in Short/Medium/Long, a question asked
// during playback never reached the current discussion at all, it landed on
// the first generation of the NEXT discussion.
//
// Oracle decision K4: a listener's question goes to the current discussion in
// EVERY mode -- even in finite mode, a short answer batch (2-4 lines) is
// generated and inserted before the next script lines. Architecture: the
// answer is played at the END of the playing turn (before the next script
// line); the machine (discussion_machine.dart) and script indices do NOT
// change (answer lines are not added to the script, they are reported via a
// separate hook) -- so persistence/resume indices do not shift.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/discussion/discussion_controller.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';

DiscussionTurn _t(String text) => DiscussionTurn(DiscussionSpeaker.a, text);

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

List<String> _texts(List<DiscussionTurn> turns) =>
    turns.map((t) => t.text).toList();

void main() {
  group('K4 -- ask(): the question goes to the current discussion', () {
    test(
      'finite mode: the answer to a question asked while turn 0 plays is '
      'played BEFORE turn 1; the answer hook is called with the answer lines',
      () async {
        final played = <String>[];
        final interjected = <String>[];
        final aboutToPlay = <int>[];
        final answerCalls = <List<Object>>[];
        final gate = Completer<void>();
        final controller = DiscussionController(
          generate: (_) async => [_t('a0'), _t('a1'), _t('a2')],
          synthesize: (turn) async => _bytes(turn.text),
          play: (mp3) async {
            final text = utf8.decode(mp3);
            played.add(text);
            if (text == 'a0') await gate.future;
          },
          answerQuestion: (topic, question, recent) async {
            answerCalls.add([topic, question, _texts(recent)]);
            return [_t('answer1'), _t('answer2')];
          },
          onInterjectionAboutToPlay: (turn) => interjected.add(turn.text),
          onTurnAboutToPlay: aboutToPlay.add,
        );

        final run = controller.run('topic');
        await pumpEventQueue();
        expect(played, ['a0']);

        expect(controller.ask('Why is it like this?'), isTrue);
        gate.complete();
        await run;

        expect(played, ['a0', 'answer1', 'answer2', 'a1', 'a2']);
        expect(interjected, ['answer1', 'answer2']);
        expect(answerCalls, [
          [
            'topic',
            'Why is it like this?',
            ['a0'],
          ],
        ]);
        expect(aboutToPlay, [
          0,
          1,
          2,
        ], reason: 'script indices do NOT shift because of the answer');
      },
    );

    test('two questions at the same boundary are answered in order', () async {
      final played = <String>[];
      final gate = Completer<void>();
      final controller = DiscussionController(
        generate: (_) async => [_t('a0'), _t('a1')],
        synthesize: (turn) async => _bytes(turn.text),
        play: (mp3) async {
          final text = utf8.decode(mp3);
          played.add(text);
          if (text == 'a0') await gate.future;
        },
        answerQuestion: (topic, question, recent) async => [
          _t('answer:$question'),
        ],
      );

      final run = controller.run('topic');
      await pumpEventQueue();
      expect(controller.ask('one'), isTrue);
      expect(controller.ask('two'), isTrue);
      gate.complete();
      await run;

      expect(played, ['a0', 'answer:one', 'answer:two', 'a1']);
    });

    test('a question asked while the first generation runs is answered after '
        'the first line (empty context)', () async {
      final played = <String>[];
      final recents = <List<String>>[];
      final script = Completer<List<DiscussionTurn>>();
      final controller = DiscussionController(
        generate: (_) => script.future,
        synthesize: (turn) async => _bytes(turn.text),
        play: (mp3) async => played.add(utf8.decode(mp3)),
        answerQuestion: (topic, question, recent) async {
          recents.add(_texts(recent));
          return [_t('answer')];
        },
      );

      final run = controller.run('topic');
      await pumpEventQueue();
      expect(controller.ask('early question'), isTrue);
      script.complete([_t('a0'), _t('a1')]);
      await run;

      expect(played, ['a0', 'answer', 'a1']);
      expect(recents, [<String>[]]);
    });

    test('context holds at most kRecentContextTurns lines (including the one '
        'playing)', () async {
      final turns = [for (var i = 0; i < 10; i++) _t('a$i')];
      final recents = <List<String>>[];
      bool? accepted;
      late DiscussionController controller;
      controller = DiscussionController(
        generate: (_) async => turns,
        synthesize: (turn) async => _bytes(turn.text),
        play: (mp3) async {},
        answerQuestion: (topic, question, recent) async {
          recents.add(_texts(recent));
          return const [];
        },
        // Ask when a7 starts playing.
        onTurnAboutToPlay: (index) {
          if (index == 7) accepted = controller.ask('question');
        },
      );
      await controller.run('topic');

      expect(accepted, isTrue);
      expect(recents.single, ['a2', 'a3', 'a4', 'a5', 'a6', 'a7']);
      expect(recents.single, hasLength(kRecentContextTurns));
    });

    test(
      'endless mode: the answer is played BEFORE the next script line',
      () async {
        final played = <String>[];
        final gate = Completer<void>();
        var continued = 0;
        final controller = DiscussionController(
          openEnded: true,
          generate: (_) async => [_t('a0'), _t('a1'), _t('a2')],
          continueScript: (topic, recent) async {
            continued++;
            throw StateError('no continuation');
          },
          synthesize: (turn) async => _bytes(turn.text),
          play: (mp3) async {
            final text = utf8.decode(mp3);
            played.add(text);
            if (text == 'a0') await gate.future;
          },
          answerQuestion: (topic, question, recent) async => [_t('answer')],
        );

        final run = controller.run('topic');
        await pumpEventQueue();
        expect(controller.ask('question'), isTrue);
        gate.complete();
        await run;

        expect(played, ['a0', 'answer', 'a1', 'a2']);
        expect(continued, greaterThanOrEqualTo(1));
      },
    );

    test(
      'on the resume path too, the question goes to the current discussion',
      () async {
        final played = <String>[];
        final gate = Completer<void>();
        final controller = DiscussionController(
          generate: (_) async =>
              throw StateError('resume must not call generate'),
          synthesize: (turn) async => _bytes(turn.text),
          play: (mp3) async {
            final text = utf8.decode(mp3);
            played.add(text);
            if (text == 'a1') await gate.future;
          },
          answerQuestion: (topic, question, recent) async {
            expect(topic, 'saved topic');
            expect(_texts(recent), ['a0', 'a1']);
            return [_t('answer')];
          },
        );

        final run = controller.resume(
          topic: 'saved topic',
          existingTurns: [_t('a0'), _t('a1'), _t('a2')],
          startIndex: 1,
        );
        await pumpEventQueue();
        expect(controller.ask('question'), isTrue);
        gate.complete();
        await run;

        expect(played, ['a1', 'answer', 'a2']);
      },
    );
  });

  group('K4 -- ask() rejection and error resilience', () {
    test(
      'false when answerQuestion is not provided (the question goes nowhere)',
      () async {
        final controller = DiscussionController(
          generate: (_) async => [_t('a0')],
          synthesize: (turn) async => _bytes(turn.text),
          play: (mp3) async {},
        );
        final run = controller.run('topic');
        expect(controller.ask('question'), isFalse);
        await run;
      },
    );

    test(
      'false before run/resume starts and after the discussion ends',
      () async {
        var answered = 0;
        final controller = DiscussionController(
          generate: (_) async => [_t('a0')],
          synthesize: (turn) async => _bytes(turn.text),
          play: (mp3) async {},
          answerQuestion: (topic, question, recent) async {
            answered++;
            return [_t('answer')];
          },
        );
        expect(controller.ask('early'), isFalse);
        await controller.run('topic');
        expect(controller.ask('late'), isFalse);
        expect(answered, 0);
      },
    );

    test('if answer generation fails, the discussion continues and no answer '
        'is played', () async {
      final played = <String>[];
      final gate = Completer<void>();
      final controller = DiscussionController(
        generate: (_) async => [_t('a0'), _t('a1')],
        synthesize: (turn) async => _bytes(turn.text),
        play: (mp3) async {
          final text = utf8.decode(mp3);
          played.add(text);
          if (text == 'a0') await gate.future;
        },
        answerQuestion: (topic, question, recent) async =>
            throw StateError('LLM failed'),
      );

      final run = controller.run('topic');
      await pumpEventQueue();
      expect(controller.ask('question'), isTrue);
      gate.complete();
      await run;

      expect(played, ['a0', 'a1']);
    });

    test('if answer synthesis fails, the rest of the answer is skipped and the '
        'discussion continues', () async {
      final played = <String>[];
      final gate = Completer<void>();
      final controller = DiscussionController(
        generate: (_) async => [_t('a0'), _t('a1')],
        synthesize: (turn) async {
          if (turn.text == 'answer2') throw StateError('TTS failed');
          return _bytes(turn.text);
        },
        play: (mp3) async {
          final text = utf8.decode(mp3);
          played.add(text);
          if (text == 'a0') await gate.future;
        },
        answerQuestion: (topic, question, recent) async => [
          _t('answer1'),
          _t('answer2'),
          _t('answer3'),
        ],
      );

      final run = controller.run('topic');
      await pumpEventQueue();
      expect(controller.ask('question'), isTrue);
      gate.complete();
      await run;

      expect(played, ['a0', 'answer1', 'a1']);
    });

    test('if the answer is stopped during playback (play error), the '
        'discussion ends with failed', () async {
      final gate = Completer<void>();
      final controller = DiscussionController(
        generate: (_) async => [_t('a0'), _t('a1')],
        synthesize: (turn) async => _bytes(turn.text),
        play: (mp3) async {
          final text = utf8.decode(mp3);
          if (text == 'a0') await gate.future;
          if (text == 'answer') throw StateError('stopped');
        },
        answerQuestion: (topic, question, recent) async => [_t('answer')],
      );

      final run = controller.run('topic');
      await pumpEventQueue();
      expect(controller.ask('question'), isTrue);
      gate.complete();
      await expectLater(run, throwsA(isA<Exception>()));
    });

    test('if the discussion ends on another path while the answer is pending, '
        'the answer is not played and no error leaks', () async {
      final played = <String>[];
      final gate = Completer<void>();
      final answer = Completer<List<DiscussionTurn>>();
      // a1's pre-synthesis fails AFTER the question is asked (oracle fix
      // 09-30: the first version failed immediately and ended the discussion
      // before ask).
      final synthFail = Completer<void>();
      final controller = DiscussionController(
        generate: (_) async => [_t('a0'), _t('a1')],
        synthesize: (turn) async {
          if (turn.text == 'a1') {
            await synthFail.future;
            throw StateError('TTS failed');
          }
          return _bytes(turn.text);
        },
        play: (mp3) async {
          final text = utf8.decode(mp3);
          played.add(text);
          if (text == 'a0') await gate.future;
        },
        answerQuestion: (topic, question, recent) => answer.future,
      );

      final run = controller.run('topic');
      await pumpEventQueue();
      expect(controller.ask('question'), isTrue);
      synthFail.complete();
      await expectLater(run, throwsA(isA<Exception>()));
      gate.complete();
      answer.complete([_t('answer')]);
      await pumpEventQueue();

      expect(played, ['a0']);
    });

    test('empty answer: nothing is played, the flow continues', () async {
      final played = <String>[];
      final gate = Completer<void>();
      final controller = DiscussionController(
        generate: (_) async => [_t('a0'), _t('a1')],
        synthesize: (turn) async => _bytes(turn.text),
        play: (mp3) async {
          final text = utf8.decode(mp3);
          played.add(text);
          if (text == 'a0') await gate.future;
        },
        answerQuestion: (topic, question, recent) async => const [],
      );

      final run = controller.run('topic');
      await pumpEventQueue();
      expect(controller.ask('question'), isTrue);
      gate.complete();
      await run;

      expect(played, ['a0', 'a1']);
    });
  });
}
