// A2 (micro-pause) RED-first test: the author prompt already forces every "beat"
// to be marked with '...', but the gapless player was silently swallowing these
// between turns. The pure turnDelivery function gives these '...' marks a REAL
// landing duration; an interruption reply enters without waiting. This file covers
// both the pure function (100% coverage) and the wiring of the delay hook injected
// into DiscussionController -- without TOUCHING discussion_controller_test.dart,
// with its own harness.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/discussion/discussion_controller.dart';
import 'package:sesli_kitap/src/discussion/discussion_pace.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';

void main() {
  group('turnDelivery (pure function)', () {
    test('first turn: prev null -> pauseMs=0, rateDelta=0.0', () {
      final result = turnDelivery(
        null,
        const DiscussionTurn(DiscussionSpeaker.a, 'Merhaba, baslayalim'),
      );
      expect(result.pauseMs, 0);
      expect(result.rateDelta, 0.0);
    });

    test(
      '"..." landing: if prev ends with "..." a natural landing time is returned '
      '(within the 500-800ms band)',
      () {
        final result = turnDelivery(
          const DiscussionTurn(DiscussionSpeaker.a, 'Bir dusuneyim...'),
          const DiscussionTurn(DiscussionSpeaker.b, 'Evet, haklisin'),
        );
        expect(result.pauseMs, kEllipsisLandingPauseMs);
        expect(result.pauseMs, inInclusiveRange(500, 800));
      },
    );

    test(
      'default: without a special mark, a small fixed gap (~180ms) is returned',
      () {
        final result = turnDelivery(
          const DiscussionTurn(DiscussionSpeaker.a, 'Onceki soz boyle bitti'),
          const DiscussionTurn(
            DiscussionSpeaker.b,
            'Sonraki soz boyle basliyor',
          ),
        );
        expect(result.pauseMs, kDefaultTurnPauseMs);
        expect(result.rateDelta, 0.0);
      },
    );

    group('interruption fast path', () {
      for (final word in ['Dur', 'Ama', 'Hayır', 'Bir dakika']) {
        test(
          'turn opening with "$word" -> pauseMs=0 (enters before the speech fully ends)',
          () {
            final result = turnDelivery(
              const DiscussionTurn(DiscussionSpeaker.a, 'Onceki soz'),
              DiscussionTurn(DiscussionSpeaker.b, '$word, boyle degil'),
            );
            expect(result.pauseMs, 0);
          },
        );
      }

      test('case-insensitive: lowercase/UPPERCASE/Capitalized all match', () {
        for (final variant in ['dur', 'DUR', 'Dur', 'dUr']) {
          final result = turnDelivery(
            const DiscussionTurn(DiscussionSpeaker.a, 'Onceki soz'),
            DiscussionTurn(DiscussionSpeaker.b, '$variant, boyle degil'),
          );
          expect(
            result.pauseMs,
            0,
            reason: '"$variant" should be recognized as an interruption word',
          );
        }
      });

      test(
        'word boundary: "Durum"/"Duracagim" are NOT mistaken for an interruption '
        '(only the whole word "Dur")',
        () {
          final result = turnDelivery(
            const DiscussionTurn(DiscussionSpeaker.a, 'Onceki soz'),
            const DiscussionTurn(
              DiscussionSpeaker.b,
              'Durum aslinda cok farkli',
            ),
          );
          expect(
            result.pauseMs,
            kDefaultTurnPauseMs,
            reason:
                '"Durum" is not an interruption; the default path should run',
          );
        },
      );

      test(
        'priority: even if prev ends with "..." and next opens with an interruption word, '
        'the interruption WINS (0ms) -- the speaker enters without waiting for the landing',
        () {
          final result = turnDelivery(
            const DiscussionTurn(DiscussionSpeaker.a, 'Bir dusuneyim...'),
            const DiscussionTurn(DiscussionSpeaker.b, 'Dur, oyle degil'),
          );
          expect(result.pauseMs, 0);
        },
      );
    });

    group('HARD-CLAMP bands', () {
      test('"..." landing path: pauseMs is always within 0..800', () {
        final result = turnDelivery(
          const DiscussionTurn(DiscussionSpeaker.a, 'Bir dusuneyim...'),
          const DiscussionTurn(DiscussionSpeaker.b, 'Evet'),
        );
        expect(result.pauseMs, greaterThanOrEqualTo(0));
        expect(result.pauseMs, lessThanOrEqualTo(kMaxTurnPauseMs));
        expect(kMaxTurnPauseMs, 800);
      });

      test(
        'default/interruption paths: pauseMs is always within 0..450 (narrower ceiling)',
        () {
          final normal = turnDelivery(
            const DiscussionTurn(DiscussionSpeaker.a, 'Onceki soz'),
            const DiscussionTurn(DiscussionSpeaker.b, 'Sonraki soz'),
          );
          final interrupt = turnDelivery(
            const DiscussionTurn(DiscussionSpeaker.a, 'Onceki soz'),
            const DiscussionTurn(DiscussionSpeaker.b, 'Dur, boyle degil'),
          );
          expect(normal.pauseMs, inInclusiveRange(0, kMaxNonEllipsisPauseMs));
          expect(
            interrupt.pauseMs,
            inInclusiveRange(0, kMaxNonEllipsisPauseMs),
          );
          expect(kMaxNonEllipsisPauseMs, 450);
        },
      );
    });

    group('rateDelta values (NOT wired in this wave; only computed)', () {
      test('first turn: rateDelta 0.0', () {
        final result = turnDelivery(
          null,
          const DiscussionTurn(DiscussionSpeaker.a, 'Merhaba'),
        );
        expect(result.rateDelta, 0.0);
      });

      test('default path: rateDelta 0.0 (neutral)', () {
        final result = turnDelivery(
          const DiscussionTurn(DiscussionSpeaker.a, 'Onceki soz'),
          const DiscussionTurn(DiscussionSpeaker.b, 'Sonraki soz'),
        );
        expect(result.rateDelta, 0.0);
      });

      test(
        '"..." landing path: rateDelta is negative (slowing down -- settling gently into the landing)',
        () {
          final result = turnDelivery(
            const DiscussionTurn(DiscussionSpeaker.a, 'Bir dusuneyim...'),
            const DiscussionTurn(DiscussionSpeaker.b, 'Evet'),
          );
          expect(result.rateDelta, lessThan(0.0));
        },
      );

      test(
        'interruption path: rateDelta is positive (speeding up -- rushing in to speak)',
        () {
          final result = turnDelivery(
            const DiscussionTurn(DiscussionSpeaker.a, 'Onceki soz'),
            const DiscussionTurn(DiscussionSpeaker.b, 'Ama boyle degil'),
          );
          expect(result.rateDelta, greaterThan(0.0));
        },
      );
    });
  });

  group('DiscussionController wiring (only pauseMs is connected)', () {
    test('_handlePlay: before every PlayTurn, turnDelivery(prev,next).pauseMs '
        'is forwarded in order to the injected pauseDelay', () async {
      final delayCalls = <int>[];
      final controller = DiscussionController(
        generate: (_) async => const [
          DiscussionTurn(DiscussionSpeaker.a, 'Bir dusuneyim...'),
          DiscussionTurn(DiscussionSpeaker.b, 'Evet haklisin'),
          DiscussionTurn(DiscussionSpeaker.a, 'Dur, oyle degil'),
        ],
        synthesize: (turn) async => Uint8List.fromList(utf8.encode(turn.text)),
        play: (_) async {},
        pauseDelay: (ms) async {
          delayCalls.add(ms);
        },
      );

      await controller.run('topic');

      expect(delayCalls, [
        0, // turn0: first turn, no prev
        kEllipsisLandingPauseMs, // turn1: turn0 ends with "..." -> landing
        0, // turn2: opens with "Dur," -> interruption fast path
      ]);
    });

    test(
      'BYTE-IDENTITY: when pauseDelay=(_) => Future.value() is injected, '
      'playback order/content is the SAME as the old behavior without injection',
      () async {
        final log = <String>[];
        final controller = DiscussionController(
          generate: (_) async => const [
            DiscussionTurn(DiscussionSpeaker.a, 't0'),
            DiscussionTurn(DiscussionSpeaker.b, 't1'),
            DiscussionTurn(DiscussionSpeaker.a, 't2'),
          ],
          synthesize: (turn) async =>
              Uint8List.fromList(utf8.encode(turn.text)),
          play: (mp3) async => log.add(utf8.decode(mp3)),
          pauseDelay: (_) => Future<void>.value(),
        );

        await controller.run('topic');

        expect(log, ['t0', 't1', 't2']);
      },
    );

    test(
      'constructor does not blow up if pauseDelay is not given (opt-in design '
      '-- the real Future.delayed default kicks in)',
      () async {
        final log = <String>[];
        final controller = DiscussionController(
          generate: (_) async => const [
            DiscussionTurn(DiscussionSpeaker.a, 't0'),
          ],
          synthesize: (turn) async =>
              Uint8List.fromList(utf8.encode(turn.text)),
          play: (mp3) async => log.add(utf8.decode(mp3)),
          // pauseDelay NOT GIVEN -- the default is used.
        );

        await controller.run('topic');

        expect(log, ['t0']);
      },
    );

    test(
      'ROOT-CAUSE FIX (device proof, 08.07): onTurnAboutToPlay(index) is ALWAYS called '
      "SYNCHRONOUSLY, while pauseDelay has NOT yet finished AND BEFORE the next turn's "
      'synthesis starts -- so the screen does not lose the "which turn is playing" info '
      'during the delay in a RACE (earlier, relying on a shared/mutable field like _lastTurn, '
      'once the pauseDelay kicked in, the transcript on screen ran 1 turn AHEAD -- observed '
      'on a real device; this test reproduces exactly that scenario)',
      () async {
        final events = <String>[];
        final controller = DiscussionController(
          generate: (_) async => const [
            DiscussionTurn(DiscussionSpeaker.a, 'turn0'),
            DiscussionTurn(DiscussionSpeaker.b, 'turn1'),
          ],
          synthesize: (turn) async {
            events.add('synth-start:${turn.text}');
            return Uint8List.fromList(utf8.encode(turn.text));
          },
          play: (mp3) async => events.add('play:${utf8.decode(mp3)}'),
          onTurnAboutToPlay: (index) => events.add('about-to-play:$index'),
          // turn0 pauseMs=0 -> passes immediately; even at 0ms, about-to-play(0) must be
          // triggered synchronously BEFORE turn0's play() is called.
          // The real scenario: while turn0 is playing, turn1's PRE-SYNTHESIS runs
          // (with concurrency PlayTurn(0)+SynthesizeTurn(1) are triggered TOGETHER) -- in this
          // test there is no pauseDelay (instant default) so the pure ordering (synchronous
          // call order) is verified; the real proof is in the second test below
          // (with a real delay).
        );

        await controller.run('topic');

        expect(
          events.indexOf('about-to-play:0'),
          lessThan(events.indexOf('synth-start:turn1')),
          reason:
              'turn0 "playing" info must reach the screen BEFORE turn1 synthesis starts',
        );
      },
    );

    test(
      'ROOT-CAUSE FIX -- REAL/pending delay: while turn0 is pausing, '
      'onTurnAboutToPlay(0) is ALREADY triggered -- before the delay is RELEASED '
      '(before play:turn0 is called) AND before turn1 synthesis starts (the real device-bug '
      'scenario: earlier _lastTurn had already been overwritten to turn1 by this point)',
      () async {
        final events = <String>[];
        final pause0Gate = Completer<void>();
        final controller = DiscussionController(
          generate: (_) async => const [
            DiscussionTurn(DiscussionSpeaker.a, 'turn0'),
            DiscussionTurn(DiscussionSpeaker.b, 'turn1'),
            DiscussionTurn(DiscussionSpeaker.a, 'turn2'),
          ],
          synthesize: (turn) async {
            events.add('synth-start:${turn.text}');
            return Uint8List.fromList(utf8.encode(turn.text));
          },
          play: (mp3) async => events.add('play:${utf8.decode(mp3)}'),
          onTurnAboutToPlay: (index) => events.add('about-to-play:$index'),
          // turn0 (first turn, no prev) returned pauseMs=0 (see turnDelivery) -- but the test
          // locks it behind a PENDING gate anyway so that we can actually observe the
          // "delay still in progress" state.
          pauseDelay: (_) => pause0Gate.future,
        );

        final runFuture = controller.run('topic');
        // Drain the microtask queue: the synchronous chain (about-to-play(0) +
        // pauseDelay call) runs, but the gate has NOT been opened yet.
        await Future<void>.delayed(Duration.zero);

        expect(
          events,
          contains('about-to-play:0'),
          reason:
              'about-to-play(0) must already have been triggered synchronously while the '
              'delay is still running (gate closed)',
        );
        expect(
          events,
          isNot(contains('play:turn0')),
          reason: 'play() must not be called before the delay gate opens',
        );

        pause0Gate.complete();
        await runFuture;

        expect(
          events.indexOf('about-to-play:0'),
          lessThan(events.indexOf('synth-start:turn1')),
          reason:
              'ROOT CAUSE: about-to-play(0) must be triggered BEFORE turn1 synthesis starts '
              '(earlier _lastTurn had been overwritten to turn1 by this point)',
        );
      },
    );

    test('STOP-flag: if the flow fails while the injected delay is running, play() is '
        'NEVER called even after the delay is released later', () async {
      final pause1Gate = Completer<void>();
      final playLog = <String>[];
      final controller = DiscussionController(
        generate: (_) async => const [
          DiscussionTurn(DiscussionSpeaker.a, 'Bir dusuneyim...'),
          DiscussionTurn(DiscussionSpeaker.b, 'Evet haklisin'),
          DiscussionTurn(DiscussionSpeaker.a, 'Son soz'),
        ],
        synthesize: (turn) async {
          if (turn.text == 'Son soz') {
            throw Exception('edge_tts 500 (turn 2)');
          }
          return Uint8List.fromList(utf8.encode(turn.text));
        },
        play: (mp3) async => playLog.add(utf8.decode(mp3)),
        // turn0 pauseMs=0 -> passes immediately; turn1 pauseMs>0 -> locked behind a test-controlled gate.
        pauseDelay: (ms) => ms == 0 ? Future<void>.value() : pause1Gate.future,
      );

      final future = controller.run('topic');

      // turn2 synthesis fails (while turn1's delay is running; with concurrency
      // PlayTurn(1) + SynthesizeTurn(2) are triggered together) -> run() rejects.
      await expectLater(future, throwsA(isA<Exception>()));
      expect(
        playLog,
        isNot(contains('Evet haklisin')),
        reason:
            'turn1 delay has NOT been released yet, play must not be called',
      );

      // Release the gate now: without the guard, play() would still be called AFTER the delay
      // (the stop-flag re-check must prevent this).
      pause1Gate.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        playLog,
        isNot(contains('Evet haklisin')),
        reason:
            'the flow had already failed (_completer completed) -- the flag re-checked '
            'after the delay must block play()',
      );
    });
  });
}
