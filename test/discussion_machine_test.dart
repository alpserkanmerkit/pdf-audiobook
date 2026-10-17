// Oracle test (Slice-1): gapless flow pure state machine. The decision is all
// here; the controller shell only executes commands (GenerateScript/
// SynthesizeTurn/PlayTurn). Kickoff section 4: "while turn i plays, turn i+1 is
// being prepared" state. Precedent: reader_machine.dart (transition(state,event)->{state,commands}).
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/discussion/discussion_machine.dart';

void main() {
  group('initial state + script generation', () {
    test('initial: idle, no turns', () {
      final s = DiscussionState.initial();
      expect(s.phase, DiscussionPhase.idle);
      expect(s.turnCount, 0);
    });

    test('idle + ScriptRequested: generating + GenerateScript(topic)', () {
      final r = discussionTransition(
        DiscussionState.initial(),
        const ScriptRequested('brain and sleep'),
      );
      expect(r.state.phase, DiscussionPhase.generating);
      expect(r.commands, hasLength(1));
      expect(r.commands.single, isA<GenerateScript>());
      expect((r.commands.single as GenerateScript).topic, 'brain and sleep');
    });

    test('generating + ScriptFailed: failed (terminal), no commands', () {
      // Slice-1.1: an error is terminal -> the controller completes the completer (no deadlock).
      final gen = discussionTransition(
        DiscussionState.initial(),
        const ScriptRequested('k'),
      ).state;
      final r = discussionTransition(gen, const ScriptFailed('network error'));
      expect(r.state.phase, DiscussionPhase.failed);
      expect(r.commands, isEmpty);
    });

    test('generating + ScriptReady(3): SynthesizeTurn(0), phase waiting', () {
      final gen = discussionTransition(
        DiscussionState.initial(),
        const ScriptRequested('k'),
      ).state;
      final r = discussionTransition(gen, const ScriptReady(3));
      expect(r.state.phase, DiscussionPhase.waiting);
      expect(r.state.turnCount, 3);
      expect(r.commands, hasLength(1));
      expect(r.commands.single, isA<SynthesizeTurn>());
      expect((r.commands.single as SynthesizeTurn).index, 0);
    });

    test('ScriptReady(0): empty dialogue -> finished', () {
      final gen = discussionTransition(
        DiscussionState.initial(),
        const ScriptRequested('k'),
      ).state;
      final r = discussionTransition(gen, const ScriptReady(0));
      expect(r.state.phase, DiscussionPhase.finished);
      expect(r.commands, isEmpty);
    });
  });

  // 3-turn happy path builder: idle -> ... -> first turn started playing.
  DiscussionState playingFirst({int n = 3}) {
    var s = discussionTransition(
      DiscussionState.initial(),
      const ScriptRequested('k'),
    ).state;
    s = discussionTransition(s, ScriptReady(n)).state; // waiting, Synth(0)
    return discussionTransition(s, const TurnSynthesized(0)).state; // playing
  }

  group('gapless flow (pre-fetch)', () {
    test(
      'waiting + TurnSynthesized(0): PlayTurn(0) + pre-SynthesizeTurn(1)',
      () {
        var s = discussionTransition(
          DiscussionState.initial(),
          const ScriptRequested('k'),
        ).state;
        s = discussionTransition(s, const ScriptReady(3)).state;
        final r = discussionTransition(s, const TurnSynthesized(0));
        expect(r.state.phase, DiscussionPhase.playing);
        expect(r.state.nextToPlay, 0);
        expect(r.commands, hasLength(2));
        expect(r.commands[0], isA<PlayTurn>());
        expect((r.commands[0] as PlayTurn).index, 0);
        expect(r.commands[1], isA<SynthesizeTurn>());
        expect((r.commands[1] as SynthesizeTurn).index, 1); // PRE-FETCH
      },
    );

    test(
      'playing + TurnSynthesized(1): pre-fetched and ready, no commands',
      () {
        final s = playingFirst();
        final r = discussionTransition(s, const TurnSynthesized(1));
        expect(r.state.phase, DiscussionPhase.playing);
        expect(r.commands, isEmpty);
      },
    );

    test(
      'playing + PlaybackCompleted(0) [turn1 ready]: PlayTurn(1) + SynthesizeTurn(2)',
      () {
        var s = playingFirst();
        s = discussionTransition(
          s,
          const TurnSynthesized(1),
        ).state; // pre-fetched and ready
        final r = discussionTransition(s, const PlaybackCompleted(0));
        expect(r.state.phase, DiscussionPhase.playing);
        expect(r.state.nextToPlay, 1);
        expect(r.commands, hasLength(2));
        expect((r.commands[0] as PlayTurn).index, 1);
        expect((r.commands[1] as SynthesizeTurn).index, 2);
      },
    );

    test(
      'PlaybackCompleted before the last turn: NO pre-synthesis (PlayTurn only)',
      () {
        // 3 turns: 0 -> 1 -> 2. PlaybackCompleted(1), turn2 ready.
        var s = playingFirst();
        s = discussionTransition(s, const TurnSynthesized(1)).state;
        s = discussionTransition(
          s,
          const PlaybackCompleted(0),
        ).state; // Play(1)+Synth(2)
        s = discussionTransition(
          s,
          const TurnSynthesized(2),
        ).state; // last one ready
        final r = discussionTransition(s, const PlaybackCompleted(1));
        expect(r.state.phase, DiscussionPhase.playing);
        expect(r.state.nextToPlay, 2);
        expect(r.commands, hasLength(1));
        expect(
          (r.commands.single as PlayTurn).index,
          2,
        ); // 2+1>=turnCount: no pre-fetch
      },
    );

    test('last turn PlaybackCompleted: finished', () {
      var s = playingFirst();
      s = discussionTransition(s, const TurnSynthesized(1)).state;
      s = discussionTransition(s, const PlaybackCompleted(0)).state;
      s = discussionTransition(s, const TurnSynthesized(2)).state;
      s = discussionTransition(s, const PlaybackCompleted(1)).state; // Play(2)
      final r = discussionTransition(s, const PlaybackCompleted(2));
      expect(r.state.phase, DiscussionPhase.finished);
      expect(r.commands, isEmpty);
    });

    test(
      'single turn: TurnSynthesized(0) PlayTurn(0) only; PlaybackCompleted(0) finished',
      () {
        var s = discussionTransition(
          DiscussionState.initial(),
          const ScriptRequested('k'),
        ).state;
        s = discussionTransition(s, const ScriptReady(1)).state;
        final r0 = discussionTransition(s, const TurnSynthesized(0));
        expect(r0.commands, hasLength(1)); // no pre-fetch (1>=turnCount)
        expect((r0.commands.single as PlayTurn).index, 0);
        final r1 = discussionTransition(r0.state, const PlaybackCompleted(0));
        expect(r1.state.phase, DiscussionPhase.finished);
      },
    );
  });

  group('latency resilience (if pre-synthesis is late)', () {
    test(
      'PlaybackCompleted but the next turn is NOT YET synthesized: waiting, no commands',
      () {
        // 2 turns. Synth(1) did not arrive BEFORE playback -> wait.
        var s = discussionTransition(
          DiscussionState.initial(),
          const ScriptRequested('k'),
        ).state;
        s = discussionTransition(s, const ScriptReady(2)).state; // Synth(0)
        s = discussionTransition(
          s,
          const TurnSynthesized(0),
        ).state; // Play(0)+Synth(1)
        final r = discussionTransition(
          s,
          const PlaybackCompleted(0),
        ); // turn1 NOT YET available
        expect(r.state.phase, DiscussionPhase.waiting);
        expect(r.state.nextToPlay, 1);
        expect(r.commands, isEmpty);
      },
    );

    test(
      'pending synthesis arrives, playback continues: waiting + TurnSynthesized(1) -> PlayTurn(1)',
      () {
        var s = discussionTransition(
          DiscussionState.initial(),
          const ScriptRequested('k'),
        ).state;
        s = discussionTransition(s, const ScriptReady(2)).state;
        s = discussionTransition(s, const TurnSynthesized(0)).state;
        s = discussionTransition(
          s,
          const PlaybackCompleted(0),
        ).state; // waiting, nextToPlay=1
        final r = discussionTransition(s, const TurnSynthesized(1));
        expect(r.state.phase, DiscussionPhase.playing);
        expect(r.commands, hasLength(1));
        expect((r.commands.single as PlayTurn).index, 1); // last: no pre-fetch
      },
    );
  });

  group('error path (Slice-1.1 resilience)', () {
    test('waiting + TurnFailed: failed (terminal), no commands', () {
      var s = discussionTransition(
        DiscussionState.initial(),
        const ScriptRequested('k'),
      ).state;
      s = discussionTransition(s, const ScriptReady(3)).state; // waiting
      final r = discussionTransition(s, const TurnFailed('edge_tts 403'));
      expect(r.state.phase, DiscussionPhase.failed);
      expect(r.commands, isEmpty);
    });

    test('playing + TurnFailed: failed (terminal)', () {
      final s = playingFirst();
      final r = discussionTransition(s, const TurnFailed('just_audio decode'));
      expect(r.state.phase, DiscussionPhase.failed);
      expect(r.commands, isEmpty);
    });

    test(
      'playing + ScriptFailed: failed (error is terminal in every phase)',
      () {
        final s = playingFirst();
        final r = discussionTransition(s, const ScriptFailed('x'));
        expect(r.state.phase, DiscussionPhase.failed);
        expect(r.commands, isEmpty);
      },
    );

    test('failed is terminal: next event is swallowed', () {
      var s = discussionTransition(
        DiscussionState.initial(),
        const ScriptRequested('k'),
      ).state;
      s = discussionTransition(s, const ScriptFailed('x')).state; // failed
      final r = discussionTransition(s, const TurnSynthesized(0));
      expect(r.state.phase, DiscussionPhase.failed);
      expect(r.commands, isEmpty);
    });
  });

  group('structural contract', () {
    test('idle + unexpected event (TurnSynthesized) is swallowed', () {
      final r = discussionTransition(
        DiscussionState.initial(),
        const TurnSynthesized(0),
      );
      expect(r.state.phase, DiscussionPhase.idle);
      expect(r.commands, isEmpty);
    });

    test('generating + unexpected event (TurnSynthesized) is swallowed', () {
      final gen = discussionTransition(
        DiscussionState.initial(),
        const ScriptRequested('k'),
      ).state;
      final r = discussionTransition(gen, const TurnSynthesized(0));
      expect(r.state.phase, DiscussionPhase.generating);
      expect(r.commands, isEmpty);
    });

    test('idle + PlaybackCompleted is swallowed (fallthrough)', () {
      final r = discussionTransition(
        DiscussionState.initial(),
        const PlaybackCompleted(0),
      );
      expect(r.state.phase, DiscussionPhase.idle);
      expect(r.commands, isEmpty);
    });

    test('transition does NOT MUTATE the input state', () {
      final s = playingFirst();
      final before = s.phase;
      discussionTransition(s, const PlaybackCompleted(0));
      expect(s.phase, before);
      expect(s.nextToPlay, 0);
    });
  });

  // ── endless (open-ended) mode ────────────────────────────────────────────────
  // The user wants it to "keep going until stopped": openEnded flag + low-water
  // trigger (RequestMoreTurns) + continuation append (ScriptExtended/ExtensionFailed).

  // openEnded playing builder: n turns, first turn started playing, openEnded carried over.
  DiscussionState playingFirstOpen({int n = 5}) {
    var s = discussionTransition(
      DiscussionState.initial(),
      const ScriptRequested('k', openEnded: true),
    ).state;
    s = discussionTransition(s, ScriptReady(n)).state;
    return discussionTransition(s, const TurnSynthesized(0)).state;
  }

  group('endless mode', () {
    test(
      'ScriptRequested(openEnded:true): generating -> waiting carries the flag',
      () {
        final r0 = discussionTransition(
          DiscussionState.initial(),
          const ScriptRequested('k', openEnded: true),
        );
        expect(r0.state.phase, DiscussionPhase.generating);
        expect(r0.state.openEnded, isTrue);
        final r1 = discussionTransition(r0.state, const ScriptReady(3));
        expect(r1.state.phase, DiscussionPhase.waiting);
        expect(
          r1.state.openEnded,
          isTrue,
          reason: 'openEnded must be copied to waiting',
        );
        expect(r1.state.extending, isFalse);
      },
    );

    test(
      'ScriptRequested default finite: openEnded false (backward compatible)',
      () {
        final r = discussionTransition(
          DiscussionState.initial(),
          const ScriptRequested('k'),
        );
        expect(r.state.openEnded, isFalse);
      },
    );

    test('ScriptReady(0) stays finished even if openEnded (degenerate)', () {
      final gen = discussionTransition(
        DiscussionState.initial(),
        const ScriptRequested('k', openEnded: true),
      ).state;
      final r = discussionTransition(gen, const ScriptReady(0));
      expect(r.state.phase, DiscussionPhase.finished);
      expect(r.commands, isEmpty);
    });

    test(
      'low-water: turnCount - nextIdx == threshold -> EXACTLY ONE RequestMoreTurns (AFTER PlayTurn), extending true',
      () {
        // n=5 openEnded; PlaybackCompleted(2) -> nextIdx=3; 5-3=2==kDiscussionLowWater.
        var s = playingFirstOpen();
        // Make turn 3 pre-fetched so the PlayTurn branch is taken.
        s = DiscussionState(
          phase: DiscussionPhase.playing,
          turnCount: 5,
          nextToPlay: 2,
          synthesized: {0, 1, 2, 3},
          openEnded: true,
        );
        final r = discussionTransition(s, const PlaybackCompleted(2));
        expect(r.state.phase, DiscussionPhase.playing);
        expect(r.state.nextToPlay, 3);
        expect(r.state.extending, isTrue);
        final more = r.commands.whereType<RequestMoreTurns>().toList();
        expect(more, hasLength(1), reason: 'exactly one continuation request');
        final playIdx = r.commands.indexWhere((c) => c is PlayTurn);
        final moreIdx = r.commands.indexWhere((c) => c is RequestMoreTurns);
        expect(playIdx, greaterThanOrEqualTo(0));
        expect(
          moreIdx,
          greaterThan(playIdx),
          reason: 'RequestMoreTurns must come AFTER PlayTurn',
        );
      },
    );

    test(
      'exactly-once: while extending, the next PlaybackCompleted does NOT produce a SECOND RequestMoreTurns',
      () {
        final s = DiscussionState(
          phase: DiscussionPhase.playing,
          turnCount: 5,
          nextToPlay: 3,
          synthesized: {0, 1, 2, 3, 4},
          openEnded: true,
          extending: true,
        );
        final r = discussionTransition(s, const PlaybackCompleted(3));
        expect(r.commands.whereType<RequestMoreTurns>(), isEmpty);
      },
    );

    test(
      'end of script + openEnded + extending -> waiting (NOT finished), nextToPlay==turnCount',
      () {
        // nextIdx>=turnCount but openEnded: must not finish, continuation is awaited.
        final s = DiscussionState(
          phase: DiscussionPhase.playing,
          turnCount: 4,
          nextToPlay: 3,
          synthesized: {0, 1, 2, 3},
          openEnded: true,
          extending: true,
        );
        final r = discussionTransition(
          s,
          const PlaybackCompleted(3),
        ); // nextIdx=4>=4
        expect(r.state.phase, DiscussionPhase.waiting);
        expect(r.state.nextToPlay, 4);
        expect(
          r.commands.whereType<RequestMoreTurns>(),
          isEmpty,
          reason: 'already extending: no new request',
        );
      },
    );

    test(
      'tiny-script: openEnded turnCount=1, PlaybackCompleted(0) -> waiting + RequestMoreTurns (NOT finished)',
      () {
        final s = DiscussionState(
          phase: DiscussionPhase.playing,
          turnCount: 1,
          synthesized: {0},
          openEnded: true,
        );
        final r = discussionTransition(
          s,
          const PlaybackCompleted(0),
        ); // nextIdx=1>=1
        expect(r.state.phase, DiscussionPhase.waiting);
        expect(r.state.nextToPlay, 1);
        expect(r.state.extending, isTrue);
        expect(r.commands.whereType<RequestMoreTurns>(), hasLength(1));
      },
    );

    test(
      'ScriptExtended(3) while playing the last-known turn: turnCount grows, extending false, SynthesizeTurn(oldCount)',
      () {
        // 3 turns, last turn (index2) is playing, chain is exhausted (nextToPlay+1==oldTurnCount).
        final s = DiscussionState(
          phase: DiscussionPhase.playing,
          turnCount: 3,
          nextToPlay: 2,
          synthesized: {0, 1, 2},
          openEnded: true,
          extending: true,
        );
        final r = discussionTransition(s, const ScriptExtended(3));
        expect(r.state.phase, DiscussionPhase.playing);
        expect(r.state.turnCount, 6);
        expect(r.state.extending, isFalse);
        final synth = r.commands.whereType<SynthesizeTurn>().toList();
        expect(synth, hasLength(1));
        expect(
          synth.single.index,
          3,
          reason: 'start synthesis from the old turnCount',
        );
      },
    );

    test('ScriptExtended(3) mid-script (chain alive): no commands', () {
      final s = DiscussionState(
        phase: DiscussionPhase.playing,
        turnCount: 5,
        nextToPlay: 1, // nextToPlay+1=2 != 5 -> chain alive
        synthesized: {0, 1, 2},
        openEnded: true,
        extending: true,
      );
      final r = discussionTransition(s, const ScriptExtended(3));
      expect(r.state.turnCount, 8);
      expect(r.state.extending, isFalse);
      expect(r.commands, isEmpty);
    });

    test(
      'ScriptExtended(2) while waiting: SynthesizeTurn(oldCount); then TurnSynthesized -> PlayTurn',
      () {
        // all turns played, waiting at the end (nextToPlay==oldTurnCount).
        final s = DiscussionState(
          phase: DiscussionPhase.waiting,
          turnCount: 3,
          nextToPlay: 3,
          synthesized: {0, 1, 2},
          openEnded: true,
          extending: true,
        );
        final r = discussionTransition(s, const ScriptExtended(2));
        expect(r.state.phase, DiscussionPhase.waiting);
        expect(r.state.turnCount, 5);
        expect(r.state.extending, isFalse);
        final synth = r.commands.whereType<SynthesizeTurn>().toList();
        expect(synth, hasLength(1));
        expect(synth.single.index, 3);
        // On the existing branch: playback continues once the new turn is synthesized.
        final r2 = discussionTransition(r.state, const TurnSynthesized(3));
        expect(r2.state.phase, DiscussionPhase.playing);
        expect((r2.commands.first as PlayTurn).index, 3);
      },
    );

    test('ScriptExtended(2) during GAP-WAIT (waiting, nextToPlay < oldCount, '
        'chain ALIVE): NO commands, extending false, turnCount grows', () {
      // Pre-synthesis was late: SynthesizeTurn for turn 2 is in flight, waiting.
      // If the continuation arrives now, the chain is alive -> no re-anchoring needed.
      final s = DiscussionState(
        phase: DiscussionPhase.waiting,
        turnCount: 3,
        nextToPlay: 2, // < oldTurnCount(3): gap-wait, not re-anchor
        synthesized: {0, 1},
        openEnded: true,
        extending: true,
      );
      final r = discussionTransition(s, const ScriptExtended(2));
      expect(r.state.phase, DiscussionPhase.waiting);
      expect(r.state.turnCount, 5);
      expect(r.state.extending, isFalse);
      expect(r.commands, isEmpty, reason: 'chain alive: no commands');
    });

    test('ScriptExtended(0) == ExtensionFailed semantics (defensive)', () {
      final s = DiscussionState(
        phase: DiscussionPhase.playing,
        turnCount: 3,
        nextToPlay: 2,
        synthesized: {0, 1, 2},
        openEnded: true,
        extending: true,
      );
      final r = discussionTransition(s, const ScriptExtended(0));
      expect(
        r.state.openEnded,
        isFalse,
        reason: 'failed continuation: fall back to finite mode',
      );
      expect(r.state.extending, isFalse);
      expect(r.state.turnCount, 3, reason: 'no growth');
    });

    test(
      'ExtensionFailed mid-script: openEnded false, same phase; the next final PlaybackCompleted -> finished (graceful)',
      () {
        final s = DiscussionState(
          phase: DiscussionPhase.playing,
          turnCount: 3,
          nextToPlay: 1,
          synthesized: {0, 1, 2},
          openEnded: true,
          extending: true,
        );
        final r = discussionTransition(s, const ExtensionFailed('LLM 401'));
        expect(r.state.phase, DiscussionPhase.playing);
        expect(r.state.openEnded, isFalse);
        expect(r.state.extending, isFalse);
        // Back to finite behavior: finished when the last turn ends.
        final s2 = discussionTransition(
          r.state,
          const PlaybackCompleted(1),
        ).state; // Play(2)
        final r3 = discussionTransition(s2, const PlaybackCompleted(2));
        expect(r3.state.phase, DiscussionPhase.finished);
      },
    );

    test(
      'ExtensionFailed while waiting (nothing to play): directly finished (deadlock guard)',
      () {
        final s = DiscussionState(
          phase: DiscussionPhase.waiting,
          turnCount: 3,
          nextToPlay: 3, // >=turnCount: only an extension was awaited
          synthesized: {0, 1, 2},
          openEnded: true,
          extending: true,
        );
        final r = discussionTransition(
          s,
          const ExtensionFailed('network error'),
        );
        expect(
          r.state.phase,
          DiscussionPhase.finished,
          reason: 'must not stay in waiting forever',
        );
      },
    );

    test(
      'finite regression: ScriptExtended/ExtensionFailed is swallowed in idle/generating/finished/failed',
      () {
        final idle = DiscussionState.initial();
        expect(
          discussionTransition(idle, const ScriptExtended(2)).state.phase,
          DiscussionPhase.idle,
        );
        expect(
          discussionTransition(idle, const ExtensionFailed('x')).state.phase,
          DiscussionPhase.idle,
        );
        final gen = discussionTransition(
          idle,
          const ScriptRequested('k'),
        ).state;
        expect(
          discussionTransition(gen, const ScriptExtended(2)).state.phase,
          DiscussionPhase.generating,
        );
        final finished = DiscussionState(
          phase: DiscussionPhase.finished,
          turnCount: 2,
        );
        expect(
          discussionTransition(finished, const ScriptExtended(2)).state.phase,
          DiscussionPhase.finished,
        );
        final failed = DiscussionState(phase: DiscussionPhase.failed);
        expect(
          discussionTransition(failed, const ExtensionFailed('x')).state.phase,
          DiscussionPhase.failed,
        );
      },
    );

    test(
      'openEnded stop path: playing + TurnFailed -> failed (terminal, unchanged)',
      () {
        final s = playingFirstOpen();
        final r = discussionTransition(s, const TurnFailed('just_audio'));
        expect(r.state.phase, DiscussionPhase.failed);
        // A late ScriptExtended is swallowed.
        expect(
          discussionTransition(r.state, const ScriptExtended(3)).state.phase,
          DiscussionPhase.failed,
        );
      },
    );
  });
}
