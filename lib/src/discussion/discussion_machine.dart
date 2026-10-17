// Reader-machine style state machine for the discussion feature.

/// A continuation batch is requested when the number of remaining unplayed turns
/// drops to this threshold.
const int kDiscussionLowWater = 2;

// ── phases ──────────────────────────────────────────────────────────────────

enum DiscussionPhase { idle, generating, playing, waiting, finished, failed }

// ── events ──────────────────────────────────────────────────────────────────

class ScriptRequested {
  const ScriptRequested(this.topic, {this.openEnded = false});
  final String topic;
  final bool openEnded;
}

class ScriptReady {
  const ScriptReady(this.turnCount);
  final int turnCount;
}

class ScriptFailed {
  const ScriptFailed(this.reason);
  final String reason;
}

class TurnSynthesized {
  const TurnSynthesized(this.index);
  final int index;
}

class PlaybackCompleted {
  const PlaybackCompleted(this.index);
  final int index;
}

class TurnFailed {
  const TurnFailed(this.reason);
  final String reason;
}

/// A continuation batch was added successfully (open-ended mode).
class ScriptExtended {
  const ScriptExtended(this.addedCount);
  final int addedCount;
}

/// A continuation batch could not be fetched (open-ended mode); falls back to finite behaviour.
class ExtensionFailed {
  const ExtensionFailed(this.reason);
  final String reason;
}

// ── commands ────────────────────────────────────────────────────────────────

class GenerateScript {
  const GenerateScript(this.topic);
  final String topic;
}

class SynthesizeTurn {
  const SynthesizeTurn(this.index);
  final int index;
}

class PlayTurn {
  const PlayTurn(this.index);
  final int index;
}

/// "Fetch a continuation batch" command to the controller (open-ended mode).
class RequestMoreTurns {
  const RequestMoreTurns();
}

// ── state ───────────────────────────────────────────────────────────────────

class DiscussionState {
  DiscussionState({
    required this.phase,
    this.turnCount = 0,
    this.nextToPlay = 0,
    Set<int>? synthesized,
    this.openEnded = false,
    this.extending = false,
  }) : synthesized = synthesized ?? const {};

  factory DiscussionState.initial() =>
      DiscussionState(phase: DiscussionPhase.idle);

  final DiscussionPhase phase;
  final int turnCount;
  final int nextToPlay;
  final Set<int> synthesized;

  /// Open-ended (endless) mode: a continuation batch is requested when the script runs out.
  final bool openEnded;

  /// true while a continuation batch is in flight (requested, not yet resolved).
  final bool extending;

  DiscussionState copyWith({
    DiscussionPhase? phase,
    int? turnCount,
    int? nextToPlay,
    Set<int>? synthesized,
    bool? openEnded,
    bool? extending,
  }) => DiscussionState(
    phase: phase ?? this.phase,
    turnCount: turnCount ?? this.turnCount,
    nextToPlay: nextToPlay ?? this.nextToPlay,
    synthesized: synthesized ?? this.synthesized,
    openEnded: openEnded ?? this.openEnded,
    extending: extending ?? this.extending,
  );
}

// ── result ──────────────────────────────────────────────────────────────────

class DiscussionResult {
  DiscussionResult(this.state, this.commands);
  final DiscussionState state;
  final List<Object> commands;
}

// ── transition ──────────────────────────────────────────────────────────────

DiscussionResult discussionTransition(DiscussionState state, Object event) {
  DiscussionResult unchanged() => DiscussionResult(state, const <Object>[]);

  // Terminal: failed swallows all events.
  if (state.phase == DiscussionPhase.failed) {
    return unchanged();
  }

  if (state.phase == DiscussionPhase.idle && event is ScriptRequested) {
    return DiscussionResult(
      DiscussionState(
        phase: DiscussionPhase.generating,
        openEnded: event.openEnded,
      ),
      [GenerateScript(event.topic)],
    );
  }

  if (state.phase == DiscussionPhase.generating) {
    if (event is ScriptFailed) {
      return DiscussionResult(
        DiscussionState(phase: DiscussionPhase.failed),
        const <Object>[],
      );
    }
    if (event is ScriptReady) {
      final n = event.turnCount;
      if (n <= 0) {
        // Degenerate generation: stays finished even if openEnded.
        return DiscussionResult(
          DiscussionState(phase: DiscussionPhase.finished, turnCount: n),
          const <Object>[],
        );
      }
      return DiscussionResult(
        DiscussionState(
          phase: DiscussionPhase.waiting,
          turnCount: n,
          openEnded: state.openEnded,
        ),
        [const SynthesizeTurn(0)],
      );
    }
    return unchanged();
  }

  // Any error while waiting or playing -> failed.
  if ((state.phase == DiscussionPhase.waiting ||
          state.phase == DiscussionPhase.playing) &&
      (event is ScriptFailed || event is TurnFailed)) {
    return DiscussionResult(
      DiscussionState(phase: DiscussionPhase.failed),
      const <Object>[],
    );
  }

  if (event is TurnSynthesized) {
    final newSynth = Set<int>.from(state.synthesized)..add(event.index);
    if (state.phase == DiscussionPhase.waiting &&
        event.index == state.nextToPlay) {
      final commands = <Object>[PlayTurn(event.index)];
      final nextIdx = event.index + 1;
      if (nextIdx < state.turnCount) {
        commands.add(SynthesizeTurn(nextIdx));
      }
      return DiscussionResult(
        state.copyWith(
          phase: DiscussionPhase.playing,
          nextToPlay: event.index,
          synthesized: newSynth,
        ),
        commands,
      );
    }
    return DiscussionResult(
      state.copyWith(synthesized: newSynth),
      const <Object>[],
    );
  }

  if (event is PlaybackCompleted && state.phase == DiscussionPhase.playing) {
    final nextIdx = event.index + 1;

    // Combined low-water trigger: in open-ended mode, when no extension is in
    // flight yet and the remaining unplayed turns drop to the threshold, request
    // one continuation batch. In finite mode (openEnded=false) this never fires,
    // so behaviour stays byte-identical.
    var extending = state.extending;
    final extra = <Object>[];
    if (state.openEnded &&
        !extending &&
        state.turnCount - nextIdx <= kDiscussionLowWater) {
      extra.add(const RequestMoreTurns());
      extending = true;
    }

    if (nextIdx >= state.turnCount) {
      // Known end of script.
      if (state.openEnded) {
        // Do not finish: wait for a continuation (request in flight or tiny script). NOT finished.
        return DiscussionResult(
          state.copyWith(
            phase: DiscussionPhase.waiting,
            nextToPlay: nextIdx,
            extending: extending,
          ),
          extra,
        );
      }
      return DiscussionResult(
        DiscussionState(
          phase: DiscussionPhase.finished,
          turnCount: state.turnCount,
        ),
        const <Object>[],
      );
    }

    if (state.synthesized.contains(nextIdx)) {
      final commands = <Object>[PlayTurn(nextIdx)];
      final afterNext = nextIdx + 1;
      if (afterNext < state.turnCount) {
        commands.add(SynthesizeTurn(afterNext));
      }
      // RequestMoreTurns is appended AFTER the current PlayTurn/SynthesizeTurn.
      commands.addAll(extra);
      return DiscussionResult(
        state.copyWith(
          phase: DiscussionPhase.playing,
          nextToPlay: nextIdx,
          extending: extending,
        ),
        commands,
      );
    } else {
      return DiscussionResult(
        state.copyWith(
          phase: DiscussionPhase.waiting,
          nextToPlay: nextIdx,
          extending: extending,
        ),
        extra,
      );
    }
  }

  // ── open-ended mode: continuation batch results ──────────────────────────
  // Only meaningful in playing/waiting; in other phases (idle/generating/
  // finished) they are swallowed by unchanged() below, and failed swallows them at the top.

  if (event is ScriptExtended &&
      (state.phase == DiscussionPhase.playing ||
          state.phase == DiscussionPhase.waiting)) {
    if (event.addedCount <= 0) {
      // Defensive: do not trust the io layer -> an empty/negative addition means failure semantics.
      return DiscussionResult(
        state.copyWith(openEnded: false, extending: false),
        const <Object>[],
      );
    }
    final oldTurnCount = state.turnCount;
    final newState = state.copyWith(
      turnCount: oldTurnCount + event.addedCount,
      extending: false,
    );
    // Does the synthesis chain need to be restarted?
    if (state.phase == DiscussionPhase.playing &&
        state.nextToPlay + 1 == oldTurnCount) {
      // The last known turn is playing; the look-ahead synthesis chain had ended -> reconnect it.
      return DiscussionResult(newState, [SynthesizeTurn(oldTurnCount)]);
    }
    if (state.phase == DiscussionPhase.waiting &&
        state.nextToPlay == oldTurnCount) {
      // Everything was played and we were waiting at the end -> synthesize the new turn;
      // the TurnSynthesized branch (index==nextToPlay) resumes playback by itself.
      return DiscussionResult(newState, [SynthesizeTurn(oldTurnCount)]);
    }
    // Chain is live (mid-script): no command, only turnCount grows.
    return DiscussionResult(newState, const <Object>[]);
  }

  if (event is ExtensionFailed &&
      (state.phase == DiscussionPhase.playing ||
          state.phase == DiscussionPhase.waiting)) {
    // Deadlock guard: if in waiting there is nothing left to play and no
    // continuation arrives, do not wait forever -> finish directly.
    if (state.phase == DiscussionPhase.waiting &&
        state.nextToPlay >= state.turnCount) {
      return DiscussionResult(
        DiscussionState(
          phase: DiscussionPhase.finished,
          turnCount: state.turnCount,
        ),
        const <Object>[],
      );
    }
    // Otherwise fall back to finite behaviour: close openEnded/extending; phase stays the same.
    return DiscussionResult(
      state.copyWith(openEnded: false, extending: false),
      const <Object>[],
    );
  }

  return unchanged();
}
