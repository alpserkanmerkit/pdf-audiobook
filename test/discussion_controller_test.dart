// Oracle test (Slice-1, section 13.7 WIRING): drives the pure DiscussionController
// state machine with REAL dependencies (generate/synthesize/play). "Not a label,
// a real feature": the controller's pre-synthesis is ACTUALLY performed, which the
// call order of the fake deps proves (a naive sequential impl CANNOT pass this
// test). Device acceptance is separate (section 13.8); this gate test pins the
// correctness of orchestration. Mock boundary: no real LLM/edge_tts/just_audio.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/discussion/discussion_controller.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';

void main() {
  group('DiscussionController flow', () {
    test(
      'run: generate is called once with the topic; all turns are played in order',
      () async {
        final log = <String>[];
        String? generatedTopic;
        final controller = DiscussionController(
          generate: (topic) async {
            generatedTopic = topic;
            return const [
              DiscussionTurn(DiscussionSpeaker.a, 't0'),
              DiscussionTurn(DiscussionSpeaker.b, 't1'),
              DiscussionTurn(DiscussionSpeaker.a, 't2'),
            ];
          },
          synthesize: (turn) async {
            log.add('S:${turn.text}');
            return Uint8List.fromList(utf8.encode(turn.text));
          },
          play: (mp3) async {
            final text = utf8.decode(mp3);
            log.add('P_start:$text');
            await Future<void>.delayed(const Duration(milliseconds: 20));
            log.add('P_done:$text');
          },
        );

        await controller.run('brain and sleep');

        expect(generatedTopic, 'brain and sleep');
        // Each turn is synthesized exactly once (order: t0,t1,t2).
        expect(log.where((e) => e.startsWith('S:')).toList(), [
          'S:t0',
          'S:t1',
          'S:t2',
        ]);
        // Each turn is played exactly once, in the right order.
        expect(log.where((e) => e.startsWith('P_start:')).toList(), [
          'P_start:t0',
          'P_start:t1',
          'P_start:t2',
        ]);
        expect(log.where((e) => e.startsWith('P_done:')).toList(), [
          'P_done:t0',
          'P_done:t1',
          'P_done:t2',
        ]);
      },
    );

    test(
      'PRE-SYNTHESIS PROOF: turn 1 synthesis starts before turn 0 finishes playing',
      () async {
        final log = <String>[];
        final controller = DiscussionController(
          generate: (_) async => const [
            DiscussionTurn(DiscussionSpeaker.a, 't0'),
            DiscussionTurn(DiscussionSpeaker.b, 't1'),
          ],
          synthesize: (turn) async {
            log.add('S:${turn.text}');
            return Uint8List.fromList(utf8.encode(turn.text));
          },
          play: (mp3) async {
            final text = utf8.decode(mp3);
            log.add('P_start:$text');
            await Future<void>.delayed(const Duration(milliseconds: 30));
            log.add('P_done:$text');
          },
        );

        await controller.run('topic');

        // Overlap: the t1 synthesis must have been triggered before t0 finished playing.
        final s1 = log.indexOf('S:t1');
        final p0done = log.indexOf('P_done:t0');
        expect(s1, greaterThanOrEqualTo(0), reason: 't1 was not synthesized');
        expect(p0done, greaterThanOrEqualTo(0), reason: 't0 was not played');
        expect(
          s1,
          lessThan(p0done),
          reason:
              'no pre-synthesis: t1 was synthesized only after t0 finished (creates a gap)',
        );
      },
    );

    test(
      'empty dialogue (generate returns an empty list): play is NEVER called, no error',
      () async {
        var playCalls = 0;
        final controller = DiscussionController(
          generate: (_) async => const <DiscussionTurn>[],
          synthesize: (turn) async => Uint8List(0),
          play: (_) async => playCalls++,
        );
        await controller.run('topic');
        expect(playCalls, 0);
      },
    );
  });

  group('error path (Slice-1.1: no deadlock, run() throws)', () {
    test(
      'synthesize throws -> run() throws an exception (not swallowed)',
      () async {
        final controller = DiscussionController(
          generate: (_) async => const [
            DiscussionTurn(DiscussionSpeaker.a, 't0'),
          ],
          synthesize: (_) async => throw Exception('edge_tts 403'),
          play: (_) async {},
        );
        await expectLater(controller.run('topic'), throwsA(isA<Exception>()));
      },
    );

    test('play throws -> run() throws an exception (not swallowed)', () async {
      final controller = DiscussionController(
        generate: (_) async => const [
          DiscussionTurn(DiscussionSpeaker.a, 't0'),
        ],
        synthesize: (_) async => Uint8List.fromList(const [1, 2, 3]),
        play: (_) async => throw Exception('just_audio decode'),
      );
      await expectLater(controller.run('topic'), throwsA(isA<Exception>()));
    });

    test(
      'generate throws -> run() throws an exception (not an idle deadlock)',
      () async {
        final controller = DiscussionController(
          generate: (_) async => throw Exception('LLM 401'),
          synthesize: (_) async => Uint8List(0),
          play: (_) async {},
        );
        await expectLater(controller.run('topic'), throwsA(isA<Exception>()));
      },
    );
  });

  group('lifecycle guards (PHASE 2a: K2+K10)', () {
    test('K2 straggler: a play that finishes AFTER run() was rejected is silently '
        'dropped (no dispatch leak into a closed controller)', () async {
      final playGate = Completer<void>();
      final controller = DiscussionController(
        generate: (_) async => const [
          DiscussionTurn(DiscussionSpeaker.a, 't0'),
          DiscussionTurn(DiscussionSpeaker.b, 't1'),
        ],
        synthesize: (turn) async {
          if (turn.text == 't1') {
            throw Exception('edge_tts 500 (turn 1)');
          }
          return Uint8List.fromList(utf8.encode(turn.text));
        },
        // t0 playback is locked to a test-controlled gate (straggler).
        play: (_) => playGate.future,
      );

      // Turn-1 synthesis fails -> run() rejects; t0 is still "playing" (in-flight).
      await expectLater(controller.run('topic'), throwsA(isA<Exception>()));

      // Release the straggler: _handlePlay tries to dispatch PlaybackCompleted.
      // Without the guard, add() on a CLOSED StreamController leaks
      // 'Bad state: Cannot add event after closing' as an uncaught async error
      // and turns this test RED. With the guard, it is silently dropped.
      playGate.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    });

    test(
      'K10 single-use: a second run() on the same instance throws a descriptive StateError',
      () async {
        final controller = DiscussionController(
          generate: (_) async => const [
            DiscussionTurn(DiscussionSpeaker.a, 't0'),
          ],
          synthesize: (_) async => Uint8List.fromList(const [1]),
          play: (_) async {},
        );
        await controller.run('topic');

        // Today: `late final _eventController` is reassigned -> LateInitializationError
        // (an unexplained crash). Expected contract: a StateError that SAYS it is single-use.
        await expectLater(
          controller.run('topic'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('single-use'),
            ),
          ),
        );
      },
    );
  });

  group('endless (open-ended) mode', () {
    test(
      'openEnded happy path: continuation returns 2 turns on the 1st call, throws on the 2nd -> run() ends normally; sequential playback',
      () async {
        final log = <String>[];
        final contextSlices = <List<String>>[];
        var contCalls = 0;
        final controller = DiscussionController(
          generate: (_) async => const [
            DiscussionTurn(DiscussionSpeaker.a, 't0'),
            DiscussionTurn(DiscussionSpeaker.b, 't1'),
            DiscussionTurn(DiscussionSpeaker.a, 't2'),
          ],
          synthesize: (turn) async {
            log.add('S:${turn.text}');
            return Uint8List.fromList(utf8.encode(turn.text));
          },
          play: (mp3) async {
            final text = utf8.decode(mp3);
            log.add('P:$text');
            await Future<void>.delayed(const Duration(milliseconds: 5));
          },
          openEnded: true,
          continueScript: (topic, recent) async {
            contCalls++;
            contextSlices.add(recent.map((t) => t.text).toList());
            if (contCalls == 1) {
              return const [
                DiscussionTurn(DiscussionSpeaker.b, 't3'),
                DiscussionTurn(DiscussionSpeaker.a, 't4'),
              ];
            }
            throw Exception('LLM 429 (stop)');
          },
        );

        await controller.run('brain');

        // t0..t4 played in order (continuation turns included).
        expect(log.where((e) => e.startsWith('P:')).toList(), [
          'P:t0',
          'P:t1',
          'P:t2',
          'P:t3',
          'P:t4',
        ]);
        expect(
          contCalls,
          greaterThanOrEqualTo(2),
          reason: 'at least one success + one throw to stop',
        );
        // continueScript received the topic and the last-K context slice.
        expect(contextSlices.first, isNotEmpty);
        expect(contextSlices.first.last, anyOf('t2', 't4'));
      },
    );

    test(
      'context slice: 8 initial turns -> the continuation call gets EXACTLY the last 6',
      () async {
        List<String>? seenRecent;
        final controller = DiscussionController(
          generate: (_) async => const [
            DiscussionTurn(DiscussionSpeaker.a, 't0'),
            DiscussionTurn(DiscussionSpeaker.b, 't1'),
            DiscussionTurn(DiscussionSpeaker.a, 't2'),
            DiscussionTurn(DiscussionSpeaker.b, 't3'),
            DiscussionTurn(DiscussionSpeaker.a, 't4'),
            DiscussionTurn(DiscussionSpeaker.b, 't5'),
            DiscussionTurn(DiscussionSpeaker.a, 't6'),
            DiscussionTurn(DiscussionSpeaker.b, 't7'),
          ],
          synthesize: (turn) async =>
              Uint8List.fromList(utf8.encode(turn.text)),
          play: (_) async {},
          openEnded: true,
          continueScript: (topic, recent) async {
            seenRecent ??= recent.map((t) => t.text).toList();
            throw Exception('stop');
          },
        );

        await controller.run('topic');

        expect(seenRecent, [
          't2',
          't3',
          't4',
          't5',
          't6',
          't7',
        ], reason: 'kRecentContextTurns==6, exactly the last 6');
      },
    );

    test(
      'DQ-4 long context: 8 initial turns -> the continueScript topic argument '
      'contains the rolling summary of the turns OUTSIDE the last 6 (t0,t1)',
      () async {
        String? seenTopic;
        final controller = DiscussionController(
          generate: (_) async => const [
            DiscussionTurn(DiscussionSpeaker.a, 't0'),
            DiscussionTurn(DiscussionSpeaker.b, 't1'),
            DiscussionTurn(DiscussionSpeaker.a, 't2'),
            DiscussionTurn(DiscussionSpeaker.b, 't3'),
            DiscussionTurn(DiscussionSpeaker.a, 't4'),
            DiscussionTurn(DiscussionSpeaker.b, 't5'),
            DiscussionTurn(DiscussionSpeaker.a, 't6'),
            DiscussionTurn(DiscussionSpeaker.b, 't7'),
          ],
          synthesize: (turn) async =>
              Uint8List.fromList(utf8.encode(turn.text)),
          play: (_) async {},
          openEnded: true,
          continueScript: (topic, recent) async {
            seenTopic ??= topic;
            throw Exception('stop');
          },
        );

        await controller.run('original topic');

        expect(seenTopic, isNotNull);
        expect(seenTopic, contains('original topic'));
        expect(seenTopic, contains('PREVIOUS COURSE OF THE DISCUSSION'));
        // t0 (Ahmet) and t1 (Emel) fall OUTSIDE the last-6 window (last 6 = t2..t7).
        expect(seenTopic, contains('t0'));
        expect(seenTopic, contains('t1'));
      },
    );

    test(
      'DQ-4 long context: if the total turn count does not exceed kRecentContextTurns, '
      'the continueScript topic argument is EXACTLY the original topic (no summary added)',
      () async {
        String? seenTopic;
        final controller = DiscussionController(
          generate: (_) async => const [
            DiscussionTurn(DiscussionSpeaker.a, 't0'),
            DiscussionTurn(DiscussionSpeaker.b, 't1'),
          ],
          synthesize: (turn) async =>
              Uint8List.fromList(utf8.encode(turn.text)),
          play: (_) async {},
          openEnded: true,
          continueScript: (topic, recent) async {
            seenTopic ??= topic;
            throw Exception('stop');
          },
        );

        await controller.run('original topic');

        expect(
          seenTopic,
          'original topic',
          reason: 'short-run behavior must stay byte-identical',
        );
      },
    );

    test(
      'const-list safety: generate returns a const list; appending the continuation does NOT throw',
      () async {
        final controller = DiscussionController(
          generate: (_) async => const [
            DiscussionTurn(DiscussionSpeaker.a, 't0'),
          ],
          synthesize: (turn) async =>
              Uint8List.fromList(utf8.encode(turn.text)),
          play: (_) async {},
          openEnded: true,
          continueScript: (topic, recent) async {
            // 1st call: if appending to a const list is not possible, it throws here.
            return const [DiscussionTurn(DiscussionSpeaker.b, 't1')];
          },
        );
        // If it throws (immutable list mutation), this await fails.
        // No 2nd call is required after continuation: when continueScript is called
        // a second time it returns the same const list -> stop with a small counter
        // so it does not run forever.
        var calls = 0;
        final c2 = DiscussionController(
          generate: (_) async => const [
            DiscussionTurn(DiscussionSpeaker.a, 't0'),
          ],
          synthesize: (turn) async =>
              Uint8List.fromList(utf8.encode(turn.text)),
          play: (_) async {},
          openEnded: true,
          continueScript: (topic, recent) async {
            calls++;
            if (calls == 1) {
              return const [DiscussionTurn(DiscussionSpeaker.b, 't1')];
            }
            throw Exception('stop');
          },
        );
        await c2.run('topic');
        expect(calls, greaterThanOrEqualTo(1));
        // Use the controller reference (avoid analyzer unused warning).
        expect(controller, isNotNull);
      },
    );

    test('eviction: bufferedAudioCount == 0 at the end of the run', () async {
      final controller = DiscussionController(
        generate: (_) async => const [
          DiscussionTurn(DiscussionSpeaker.a, 't0'),
          DiscussionTurn(DiscussionSpeaker.b, 't1'),
          DiscussionTurn(DiscussionSpeaker.a, 't2'),
        ],
        synthesize: (turn) async => Uint8List.fromList(utf8.encode(turn.text)),
        play: (_) async {},
      );
      await controller.run('topic');
      expect(
        controller.bufferedAudioCount,
        0,
        reason: 'played audio buffers must be cleared',
      );
    });

    test('eviction mid-run: at most 2 buffers alive', () async {
      var maxBuffered = 0;
      late final DiscussionController controller;
      controller = DiscussionController(
        generate: (_) async => const [
          DiscussionTurn(DiscussionSpeaker.a, 't0'),
          DiscussionTurn(DiscussionSpeaker.b, 't1'),
          DiscussionTurn(DiscussionSpeaker.a, 't2'),
          DiscussionTurn(DiscussionSpeaker.b, 't3'),
        ],
        synthesize: (turn) async => Uint8List.fromList(utf8.encode(turn.text)),
        play: (_) async {
          // Inside the gated play: at most playing + pre-synthesized = 2.
          if (controller.bufferedAudioCount > maxBuffered) {
            maxBuffered = controller.bufferedAudioCount;
          }
          await Future<void>.delayed(const Duration(milliseconds: 3));
        },
      );
      await controller.run('topic');
      expect(maxBuffered, lessThanOrEqualTo(2));
    });

    test(
      'finite default: even if continueScript is given, with openEnded false it is NEVER called',
      () async {
        var contCalls = 0;
        final controller = DiscussionController(
          generate: (_) async => const [
            DiscussionTurn(DiscussionSpeaker.a, 't0'),
            DiscussionTurn(DiscussionSpeaker.b, 't1'),
          ],
          synthesize: (turn) async =>
              Uint8List.fromList(utf8.encode(turn.text)),
          play: (_) async {},
          // openEnded not given -> default false.
          continueScript: (topic, recent) async {
            contCalls++;
            return const [];
          },
        );
        await controller.run('topic');
        expect(contCalls, 0);
      },
    );

    test(
      'openEnded but continueScript null: the continuation request becomes '
      'ExtensionFailed; run() ends normally (falls back to finite behavior)',
      () async {
        var playCalls = 0;
        final controller = DiscussionController(
          generate: (_) async => const [
            DiscussionTurn(DiscussionSpeaker.a, 't0'),
            DiscussionTurn(DiscussionSpeaker.b, 't1'),
          ],
          synthesize: (turn) async =>
              Uint8List.fromList(utf8.encode(turn.text)),
          play: (_) async => playCalls++,
          openEnded: true,
          // continueScript not given (null) -> RequestMoreTurns hits a StateError
          // and becomes ExtensionFailed; the machine moves to finished (not thrown).
        );
        await controller.run('topic');
        expect(
          playCalls,
          2,
          reason: 'two turns played, then it ended gracefully',
        );
      },
    );

    test('open-ended eviction: including the re-anchor path, at most 2 buffers '
        'mid-run and 0 at the end of the run', () async {
      // continueScript is SLOW (30ms), play is FAST (5ms): the script end arrives
      // while a continuation is in flight -> the waiting-in-flight re-anchor path
      // also runs.
      final playLog = <String>[];
      var maxBuffered = 0;
      var contCalls = 0;
      late final DiscussionController controller;
      controller = DiscussionController(
        generate: (_) async => const [
          DiscussionTurn(DiscussionSpeaker.a, 't0'),
          DiscussionTurn(DiscussionSpeaker.b, 't1'),
          DiscussionTurn(DiscussionSpeaker.a, 't2'),
        ],
        synthesize: (turn) async => Uint8List.fromList(utf8.encode(turn.text)),
        play: (mp3) async {
          playLog.add(utf8.decode(mp3));
          if (controller.bufferedAudioCount > maxBuffered) {
            maxBuffered = controller.bufferedAudioCount;
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
        },
        openEnded: true,
        continueScript: (topic, recent) async {
          contCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 30));
          if (contCalls == 1) {
            return const [
              DiscussionTurn(DiscussionSpeaker.b, 't3'),
              DiscussionTurn(DiscussionSpeaker.a, 't4'),
            ];
          }
          throw Exception('stop');
        },
      );

      await controller.run('topic');

      expect(playLog, ['t0', 't1', 't2', 't3', 't4']);
      expect(maxBuffered, lessThanOrEqualTo(2));
      expect(
        controller.bufferedAudioCount,
        0,
        reason: 'in open-ended runs too, all buffers must be cleared',
      );
    });

    test(
      'TWO consecutive SUCCESSFUL extensions then exhaustion: all turns are played in order',
      () async {
        final playLog = <String>[];
        var contCalls = 0;
        final controller = DiscussionController(
          generate: (_) async => const [
            DiscussionTurn(DiscussionSpeaker.a, 't0'),
            DiscussionTurn(DiscussionSpeaker.b, 't1'),
          ],
          synthesize: (turn) async =>
              Uint8List.fromList(utf8.encode(turn.text)),
          play: (mp3) async {
            playLog.add(utf8.decode(mp3));
            await Future<void>.delayed(const Duration(milliseconds: 5));
          },
          openEnded: true,
          continueScript: (topic, recent) async {
            contCalls++;
            if (contCalls == 1) {
              return const [
                DiscussionTurn(DiscussionSpeaker.a, 't2'),
                DiscussionTurn(DiscussionSpeaker.b, 't3'),
              ];
            }
            if (contCalls == 2) {
              return const [
                DiscussionTurn(DiscussionSpeaker.a, 't4'),
                DiscussionTurn(DiscussionSpeaker.b, 't5'),
              ];
            }
            throw Exception('exhausted');
          },
        );

        await controller.run('topic');

        expect(
          playLog,
          ['t0', 't1', 't2', 't3', 't4', 't5'],
          reason:
              'continuity of the second extension: 6 turns in order, no gap',
        );
        expect(contCalls, 3, reason: '2 successful + 1 exhaustion call');
      },
    );
  });

  group('resume (continue where left off, Phase DQ-W3)', () {
    test(
      'startIndex in the middle: only the REMAINING turns are synthesized and '
      'played in order; generate is NEVER called (script already exists)',
      () async {
        var generateCalls = 0;
        final log = <String>[];
        final controller = DiscussionController(
          generate: (_) async {
            generateCalls++;
            return const <DiscussionTurn>[];
          },
          synthesize: (turn) async {
            log.add('S:${turn.text}');
            return Uint8List.fromList(utf8.encode(turn.text));
          },
          play: (mp3) async {
            log.add('P:${utf8.decode(mp3)}');
          },
        );

        await controller.resume(
          topic: 'resumed topic',
          existingTurns: const [
            DiscussionTurn(DiscussionSpeaker.a, 't0'),
            DiscussionTurn(DiscussionSpeaker.b, 't1'),
            DiscussionTurn(DiscussionSpeaker.a, 't2'),
          ],
          startIndex: 1, // t0 was already played
        );

        expect(
          generateCalls,
          0,
          reason: 'script already exists, generate is NOT needed',
        );
        expect(log, ['S:t1', 'P:t1', 'S:t2', 'P:t2']);
      },
    );

    test(
      'openEnded=true resume: once the remaining turns finish, continueScript '
      'takes over (same continuity as run())',
      () async {
        final playLog = <String>[];
        var contCalls = 0;
        final controller = DiscussionController(
          generate: (_) async => const <DiscussionTurn>[],
          synthesize: (turn) async =>
              Uint8List.fromList(utf8.encode(turn.text)),
          play: (mp3) async => playLog.add(utf8.decode(mp3)),
          openEnded: true,
          continueScript: (topic, recent) async {
            contCalls++;
            if (contCalls == 1) {
              return const [DiscussionTurn(DiscussionSpeaker.b, 't2')];
            }
            throw Exception('stop');
          },
        );

        await controller.resume(
          topic: 'endless topic',
          existingTurns: const [
            DiscussionTurn(DiscussionSpeaker.a, 't0'),
            DiscussionTurn(DiscussionSpeaker.b, 't1'),
          ],
          startIndex: 0,
          openEnded: true,
        );

        expect(playLog, ['t0', 't1', 't2']);
        expect(contCalls, greaterThanOrEqualTo(1));
      },
    );

    test('degenerate: startIndex >= turns.length -> no synthesis/play is called; '
        'resume() ends silently (without throwing)', () async {
      var synthCalls = 0;
      var playCalls = 0;
      final controller = DiscussionController(
        generate: (_) async => const <DiscussionTurn>[],
        synthesize: (_) async {
          synthCalls++;
          return Uint8List(0);
        },
        play: (_) async => playCalls++,
      );

      await controller.resume(
        topic: 'topic',
        existingTurns: const [DiscussionTurn(DiscussionSpeaker.a, 't0')],
        startIndex:
            1, // only one turn exists and it was already played (would be isResumable=false)
      );

      expect(synthCalls, 0);
      expect(playCalls, 0);
    });

    test('single-use: a second resume() after resume() throws a descriptive '
        "StateError (resume()'s OWN guard)", () async {
      final controller = DiscussionController(
        generate: (_) async => const <DiscussionTurn>[],
        synthesize: (turn) async => Uint8List.fromList(utf8.encode(turn.text)),
        play: (_) async {},
      );
      await controller.resume(
        topic: 'topic',
        existingTurns: const [DiscussionTurn(DiscussionSpeaker.a, 't0')],
        startIndex: 0,
      );

      await expectLater(
        controller.resume(
          topic: 'other topic',
          existingTurns: const [DiscussionTurn(DiscussionSpeaker.a, 'x')],
          startIndex: 0,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('single-use'),
          ),
        ),
      );
    });

    test('single-use: a second run() after resume() throws a descriptive '
        "StateError (run()'s guard)", () async {
      final controller = DiscussionController(
        generate: (_) async => const <DiscussionTurn>[],
        synthesize: (turn) async => Uint8List.fromList(utf8.encode(turn.text)),
        play: (_) async {},
      );
      await controller.resume(
        topic: 'topic',
        existingTurns: const [DiscussionTurn(DiscussionSpeaker.a, 't0')],
        startIndex: 0,
      );

      await expectLater(
        controller.run('other topic'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('single-use'),
          ),
        ),
      );
    });

    test(
      'error path: synthesize throws -> resume() throws an exception',
      () async {
        final controller = DiscussionController(
          generate: (_) async => const <DiscussionTurn>[],
          synthesize: (_) async => throw Exception('edge_tts 500'),
          play: (_) async {},
        );
        await expectLater(
          controller.resume(
            topic: 'topic',
            existingTurns: const [
              DiscussionTurn(DiscussionSpeaker.a, 't0'),
              DiscussionTurn(DiscussionSpeaker.b, 't1'),
            ],
            startIndex: 0,
          ),
          throwsA(isA<Exception>()),
        );
      },
    );

    test(
      'ROOT-CAUSE FIX: degenerate (startIndex>=turns.length) BUT openEnded + '
      'continueScript present -> a continuation batch is fetched and playback '
      'continues (the endless-mode fix -- previously nothing happened silently here)',
      () async {
        final playLog = <String>[];
        var contCalls = 0;
        final controller = DiscussionController(
          generate: (_) async => const <DiscussionTurn>[],
          synthesize: (turn) async =>
              Uint8List.fromList(utf8.encode(turn.text)),
          play: (mp3) async => playLog.add(utf8.decode(mp3)),
          openEnded: true,
          continueScript: (topic, recent) async {
            contCalls++;
            if (contCalls == 1) {
              return const [DiscussionTurn(DiscussionSpeaker.a, 't1')];
            }
            throw Exception('stop');
          },
        );

        await controller.resume(
          topic: 'endless topic',
          existingTurns: const [DiscussionTurn(DiscussionSpeaker.a, 't0')],
          startIndex:
              1, // t0 was already played, script has only this much -- endless mode
          openEnded: true,
        );

        expect(
          playLog,
          ['t1'],
          reason:
              'a new batch must be fetched and played (t0 was already played '
              'and must not be replayed)',
        );
        expect(contCalls, greaterThanOrEqualTo(1));
      },
    );

    test(
      'ROOT-CAUSE FIX: degenerate + openEnded BUT continueScript null -> still '
      'ends silently (cannot be extended; old behavior kept)',
      () async {
        var synthCalls = 0;
        var playCalls = 0;
        final controller = DiscussionController(
          generate: (_) async => const <DiscussionTurn>[],
          synthesize: (_) async {
            synthCalls++;
            return Uint8List(0);
          },
          play: (_) async => playCalls++,
          openEnded: true,
          // continueScript not given.
        );

        await controller.resume(
          topic: 'topic',
          existingTurns: const [DiscussionTurn(DiscussionSpeaker.a, 't0')],
          startIndex: 1,
          openEnded: true,
        );

        expect(synthCalls, 0);
        expect(playCalls, 0);
      },
    );

    test(
      'ROOT-CAUSE FIX: degenerate + openEnded + continueScript throws IMMEDIATELY '
      '-> resume() completes gracefully (finished), the error does not escape',
      () async {
        final controller = DiscussionController(
          generate: (_) async => const <DiscussionTurn>[],
          synthesize: (_) async => Uint8List(0),
          play: (_) async {},
          openEnded: true,
          continueScript: (topic, recent) async => throw Exception('LLM 429'),
        );

        // If it completes without the await throwing, it proves the machine went to finished.
        await controller.resume(
          topic: 'topic',
          existingTurns: const [DiscussionTurn(DiscussionSpeaker.a, 't0')],
          startIndex: 1,
          openEnded: true,
        );
      },
    );
  });

  group(
    'onScriptReady / onScriptExtended (DQ-W3-fix: root-cause information flow)',
    () {
      test(
        'onScriptReady: once generate succeeds, the FULL script is passed out of the '
        'controller (in finite mode the whole script is reported to the screen early)',
        () async {
          List<DiscussionTurn>? seen;
          final controller = DiscussionController(
            generate: (_) async => const [
              DiscussionTurn(DiscussionSpeaker.a, 't0'),
              DiscussionTurn(DiscussionSpeaker.b, 't1'),
            ],
            synthesize: (turn) async =>
                Uint8List.fromList(utf8.encode(turn.text)),
            play: (_) async {},
            onScriptReady: (turns) => seen = turns,
          );
          await controller.run('topic');
          expect(seen?.map((t) => t.text).toList(), ['t0', 't1']);
        },
      );

      test('onScriptReady: NOT called at all if generate throws', () async {
        var calls = 0;
        final controller = DiscussionController(
          generate: (_) async => throw Exception('LLM 401'),
          synthesize: (_) async => Uint8List(0),
          play: (_) async {},
          onScriptReady: (_) => calls++,
        );
        await expectLater(controller.run('topic'), throwsA(isA<Exception>()));
        expect(calls, 0);
      });

      test(
        'onScriptExtended: once continuation succeeds, the CURRENT FULL script '
        '(old + new) is passed out',
        () async {
          final seenSnapshots = <List<String>>[];
          var contCalls = 0;
          final controller = DiscussionController(
            generate: (_) async => const [
              DiscussionTurn(DiscussionSpeaker.a, 't0'),
            ],
            synthesize: (turn) async =>
                Uint8List.fromList(utf8.encode(turn.text)),
            play: (_) async {},
            openEnded: true,
            continueScript: (topic, recent) async {
              contCalls++;
              if (contCalls == 1) {
                return const [DiscussionTurn(DiscussionSpeaker.b, 't1')];
              }
              throw Exception('stop');
            },
            onScriptExtended: (turns) =>
                seenSnapshots.add(turns.map((t) => t.text).toList()),
          );
          await controller.run('topic');
          expect(seenSnapshots, [
            ['t0', 't1'],
          ]);
        },
      );

      test(
        'onScriptExtended: NOT called if the continuation fails (ExtensionFailed)',
        () async {
          var calls = 0;
          final controller = DiscussionController(
            generate: (_) async => const [
              DiscussionTurn(DiscussionSpeaker.a, 't0'),
            ],
            synthesize: (turn) async =>
                Uint8List.fromList(utf8.encode(turn.text)),
            play: (_) async {},
            openEnded: true,
            continueScript: (topic, recent) async => throw Exception('stop'),
            onScriptExtended: (_) => calls++,
          );
          await controller.run('topic');
          expect(calls, 0);
        },
      );
    },
  );
}
