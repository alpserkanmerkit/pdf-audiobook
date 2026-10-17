import 'dart:async';
import 'dart:typed_data';

import 'package:sesli_kitap/src/discussion/discussion_machine.dart';
import 'package:sesli_kitap/src/discussion/discussion_pace.dart';
import 'package:sesli_kitap/src/discussion/discussion_rolling_summary.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';

/// Generates a script for the given topic.
typedef ScriptGenerator = Future<List<DiscussionTurn>> Function(String topic);

/// Synthesizes a single turn into an audio buffer.
typedef TurnSynthesizer = Future<Uint8List> Function(DiscussionTurn turn);

/// Plays an audio buffer. Returns when playback finishes.
typedef AudioPlayback = Future<void> Function(Uint8List mp3);

/// Generates a continuation batch: topic + recent lines (context) -> NEW lines.
typedef ScriptContinuer =
    Future<List<DiscussionTurn>> Function(
      String topic,
      List<DiscussionTurn> recentTurns,
    );

/// Generates a short answer batch for a listener question (K4, 2026-09-30):
/// topic + question + recent lines (context) -> answer lines.
typedef QuestionAnswerer =
    Future<List<DiscussionTurn>> Function(
      String topic,
      String question,
      List<DiscussionTurn> recentTurns,
    );

/// Common signature for [DiscussionController.onScriptReady]/[DiscussionController.onScriptExtended]:
/// each call carries the FULL script known SO FAR (not a delta -- the caller always
/// gets everything, so it does not need to add up or compare with earlier calls).
typedef ScriptKnownCallback = void Function(List<DiscussionTurn> turns);

/// A2 (micro-pause): a hook that really waits for the delay to be applied BEFORE a
/// turn is played (see [turnDelivery]), and is injectable. When left NULL (DEFAULT)
/// there is NO delay/await at all -- so all tests that do not reach pauseDelay and the
/// debug-factory path keep the old behaviour BYTE-IDENTICAL (synthesis/playback/light
/// ordering does not change). ONLY the real-path setups of the screen inject the REAL
/// (device-felt) delay explicitly (lib/ui; see discussion_room_screen.dart), because a
/// real wait is a side effect, not pure logic (a layer outside the scope).
typedef TurnPauseDelay = Future<void> Function(int pauseMs);

/// Size of the recent-context window passed to continueScript when a continuation is requested.
/// DQ-4: older turns OUTSIDE this window are no longer forgotten entirely -- [withRollingSummary]
/// adds a light "previous course" summary of them to the topic argument given to
/// continueScript (see `_handleExtend`); the verbatim window itself (kRecentContextTurns) does not change.
const int kRecentContextTurns = 6;

/// Orchestrates the full discussion flow: generate script, synthesise turns,
/// play them in order with pre-synthesis of the next turn.
///
/// Single-use: create a new instance for each [run] call; a second [run] call on
/// the same instance throws a [StateError].
class DiscussionController {
  DiscussionController({
    required this.generate,
    required this.synthesize,
    required this.play,
    this.continueScript,
    this.openEnded = false,
    this.onScriptReady,
    this.onScriptExtended,
    this.onTurnAboutToPlay,
    this.pauseDelay,
    this.answerQuestion,
    this.onInterjectionAboutToPlay,
  });

  final ScriptGenerator generate;
  final TurnSynthesizer synthesize;
  final AudioPlayback play;

  /// Callback that produces a continuation batch in open-ended mode. If null, a continuation
  /// request is converted directly to ExtensionFailed (return to finite behaviour).
  final ScriptContinuer? continueScript;

  /// If true, continuation batches are fetched before the script ends (endless discussion).
  final bool openEnded;

  /// Called as soon as [generate] succeeds (the FULL script is known -- in finite mode the
  /// whole script, in endless mode the first batch). The recorder (caller) wants to see the
  /// whole script WITHOUT DELAY relative to synthesis/playback -- especially for persistence:
  /// the text of turns that are already written, though their synthesis has not come yet,
  /// can be saved thanks to this (see DiscussionSession persistence root-cause fix, Bug#1).
  final ScriptKnownCallback? onScriptReady;

  /// Called as soon as [continueScript] succeeds, with the CURRENT FULL script (old + new
  /// together). Same contract as [onScriptReady] (not a delta, everything); in endless-mode
  /// continuation batches their text can be saved before synthesis arrives.
  final ScriptKnownCallback? onScriptExtended;

  /// ROOT-CAUSE FIX (device evidence, 08.07): before every turn, [_handlePlay] calls this
  /// SYNCHRONOUSLY, BEFORE [pauseDelay] starts -- so the caller (the screen) always takes
  /// "which turn is about to play" from the right turn. PREVIOUSLY the screen derived this
  /// from its own `_lastTurn` field (a shared/mutable proxy updated by the synthesis-completion
  /// side effect), which was a FRAGILE contract relying on PlayTurn(N) + SynthesizeTurn(N+1)
  /// being processed back-to-back in the SAME synchronous chain (see [_executeCommand]).
  /// When [pauseDelay] was added (A2, micro-pause) this chain was split by a REAL await:
  /// SynthesizeTurn(N+1) ran during turn N's delay and OVERWROTE _lastTurn with N+1 -- the
  /// transcript on screen went ONE TURN AHEAD (observed on the device). This hook removes that
  /// race by passing the turn index explicitly and SYNCHRONOUSLY.
  final void Function(int index)? onTurnAboutToPlay;

  /// A2 (micro-pause): before each turn, [_handlePlay] calls this (if not null). NULL (default)
  /// = no delay = old behaviour byte-identical; only the real-path setup of the screen injects
  /// the real delay (see the [TurnPauseDelay] doc).
  final TurnPauseDelay? pauseDelay;

  /// Callback that produces the answer batch for a listener question (K4). If null, [ask]
  /// REJECTS the question (false) -- the question goes nowhere and does not leak.
  final QuestionAnswerer? answerQuestion;

  /// Called SYNCHRONOUSLY, before playback, when an answer line starts to play. Answer lines
  /// are NOT added to the script: [onTurnAboutToPlay] indices and the persistence index do not
  /// shift; the screen adds the line to the transcript from this hook.
  final void Function(DiscussionTurn turn)? onInterjectionAboutToPlay;

  DiscussionState _state = DiscussionState.initial();
  List<DiscussionTurn>? _turns;
  // `late` would turn an error state into a LateInitializationError (nullable + `!` is deliberate).
  // ignore: use_late_for_private_fields_and_variables
  String? _topic;
  final Map<int, Uint8List> _audios = {};
  final Completer<void> _completer = Completer<void>();
  late final StreamController<Object> _eventController;
  bool _started = false;

  /// Index of the script line that started playing most recently (-1 = none yet);
  /// [ask] uses it to cut the answer context.
  int _playingIndex = -1;

  /// Answer batches requested via [ask] that are not yet played (in order). They do not
  /// throw: an answer-generation error is turned into an empty list (the flow does not drop).
  final List<Future<List<DiscussionTurn>>> _pendingAnswers = [];

  /// Test/diagnostic surface: how many audio buffers are currently held in memory (unplayed).
  int get bufferedAudioCount => _audios.length;

  /// Listener question (K4): the answer batch starts being generated IMMEDIATELY (while the
  /// current line is playing), and is played BEFORE the next script line once the current line
  /// ends -- in every mode (finite/endless, run/resume). Context: the current line included,
  /// the last [kRecentContextTurns] script lines.
  ///
  /// false: [answerQuestion] is absent, [run]/[resume] has not started, or the discussion has
  /// ended -- the question is rejected and held nowhere, so it cannot LEAK into the next discussion.
  bool ask(String question) {
    final answer = answerQuestion;
    if (answer == null || !_started || _completer.isCompleted) return false;
    final turns = _turns ?? const <DiscussionTurn>[];
    final upTo = _playingIndex + 1;
    final recent = turns.sublist(
      upTo > kRecentContextTurns ? upTo - kRecentContextTurns : 0,
      upTo,
    );
    _pendingAnswers.add(
      answer(
        _topic!,
        question,
        recent,
      ).then((t) => t, onError: (Object _) => const <DiscussionTurn>[]),
    );
    return true;
  }

  /// Runs the discussion for the given [topic].
  /// Completes when the entire flow finishes.
  Future<void> run(String topic) async {
    if (_started) {
      throw StateError(
        'DiscussionController is single-use; create a new instance for each run()/resume() call.',
      );
    }
    _started = true;
    _topic = topic;
    _eventController = StreamController<Object>();
    final subscription = _eventController.stream.listen(_onEvent);

    _dispatch(ScriptRequested(topic, openEnded: openEnded));

    try {
      await _completer.future;
    } finally {
      await subscription.cancel();
      await _eventController.close();
    }
  }

  /// Resume from where it stopped (DQ-W3): [existingTurns] already holds the script --
  /// [generate] is NEVER called; only the re-synthesis + playback chain from [startIndex]
  /// is set up (the machine is entered directly at the waiting phase, skipping the
  /// ScriptRequested/generating step). If openEnded=true, when the script runs out it
  /// proceeds exactly as [run] does with continueScript.
  ///
  /// If [startIndex] >= existingTurns.length (the known part of the script is used up):
  /// if [openEnded] is true AND [continueScript] was given (endless-mode root-cause fix),
  /// a new continuation batch is fetched and playback resumes from where it stopped -- just
  /// like the script-end behaviour of [run]. Otherwise (finite, genuinely finished script) it
  /// is treated as degenerate: it ends silently without publishing any command.
  Future<void> resume({
    required String topic,
    required List<DiscussionTurn> existingTurns,
    required int startIndex,
    bool openEnded = false,
  }) async {
    if (_started) {
      throw StateError(
        'DiscussionController is single-use; create a new instance for each run()/resume() call.',
      );
    }
    _started = true;
    _topic = topic;
    _turns = List<DiscussionTurn>.of(existingTurns);

    final canExtend = openEnded && continueScript != null;
    if (startIndex >= _turns!.length && !canExtend) {
      // Considered finished: a later [ask] is rejected (so it is not held).
      _completer.complete();
      return;
    }

    _eventController = StreamController<Object>();
    final subscription = _eventController.stream.listen(_onEvent);

    if (startIndex >= _turns!.length) {
      // canExtend is true (not eliminated above): the known part of the script is used up
      // but we are in endless mode -- hand-build the same script-end/openEnded branch as
      // run() and publish the continuation request directly.
      _state = DiscussionState(
        phase: DiscussionPhase.waiting,
        turnCount: _turns!.length,
        nextToPlay: startIndex,
        openEnded: true,
        extending: true,
      );
      _executeCommand(const RequestMoreTurns());
    } else {
      _state = DiscussionState(
        phase: DiscussionPhase.waiting,
        turnCount: _turns!.length,
        nextToPlay: startIndex,
        openEnded: openEnded,
      );
      _executeCommand(SynthesizeTurn(startIndex));
    }

    try {
      await _completer.future;
    } finally {
      await subscription.cancel();
      await _eventController.close();
    }
  }

  // ── internal event loop ──────────────────────────────────────────────────

  void _onEvent(Object event) {
    if (_completer.isCompleted) return;

    final result = discussionTransition(_state, event);
    _state = result.state;

    if (_state.phase == DiscussionPhase.finished) {
      _completer.complete();
      return;
    }

    if (_state.phase == DiscussionPhase.failed) {
      final reason = (event is ScriptFailed
          ? event.reason
          : event is TurnFailed
          ? event.reason
          : 'Unknown error');
      _completer.completeError(Exception(reason));
      return;
    }

    result.commands.forEach(_executeCommand);
  }

  void _dispatch(Object event) {
    // K2 guard: _completer is completed BEFORE finally closes _eventController; in-flight
    // handlers that finish after the flow ends (stragglers) would add to a closed controller
    // and leak a StateError, so they are silently dropped here.
    if (_completer.isCompleted) return;
    _eventController.add(event);
  }

  // ── command execution (all fire-and-forget, enabling concurrency) ────────

  void _executeCommand(Object cmd) {
    Future<void> handler;
    if (cmd is GenerateScript) {
      handler = _handleGenerate(cmd.topic);
    } else if (cmd is SynthesizeTurn) {
      handler = _handleSynthesize(cmd.index);
    } else if (cmd is PlayTurn) {
      handler = _handlePlay(cmd.index);
    } else if (cmd is RequestMoreTurns) {
      handler = _handleExtend();
    } else {
      return;
    }
    // Fire -- do not await; concurrency (pre-synthesis) relies on this.
    unawaited(handler);
  }

  Future<void> _handleGenerate(String topic) async {
    try {
      final turns = await generate(topic);
      _turns = turns;
      onScriptReady?.call(turns);
      _dispatch(ScriptReady(turns.length));
    } on Object catch (e) {
      _dispatch(ScriptFailed(e.toString()));
    }
  }

  Future<void> _handleSynthesize(int index) async {
    try {
      final turn = _turns![index];
      final mp3 = await synthesize(turn);
      _audios[index] = mp3;
      _dispatch(TurnSynthesized(index));
    } on Object catch (e) {
      _dispatch(TurnFailed(e.toString()));
    }
  }

  Future<void> _handlePlay(int index) async {
    try {
      // ROOT-CAUSE FIX: SYNCHRONOUS, BEFORE any await/delay -- the caller takes the
      // "turn N is about to play" information here, inside the command processing order
      // of PlayTurn(N) itself (see the [onTurnAboutToPlay] doc).
      _playingIndex = index;
      onTurnAboutToPlay?.call(index);
      // A2 (micro-pause): give the mandatory '...' beat marker the author prompt requires (or
      // an interruption opener) a REAL delivery gap -- computed from the turns[index-1]/[index]
      // pair (the first turn has no prev -> 0ms, see turnDelivery).
      // pauseDelay is injected ONLY in the screen's real-path (device) setup; when it is null
      // (all tests + the debug-factory path) there is NO await/yield at all -> the
      // synthesis/playback/avatar-light ordering stays BYTE-IDENTICAL to the old behaviour
      // (the micro-pause is felt only on the device).
      final delay = pauseDelay;
      if (delay != null) {
        final prev = index > 0 ? _turns![index - 1] : null;
        final pauseMs = turnDelivery(prev, _turns![index]).pauseMs;
        await delay(pauseMs);
        // STOP flag: while the delay runs, the flow (in another branch) may have failed or
        // completed -- this prevents a now-irrelevant play()/dispatch.
        if (_completer.isCompleted) return;
      }
      await play(_audios[index]!);
      // Eviction: the played buffer is freed -> at most 2 buffers stay alive
      // (the playing one + the pre-synthesized one). BEFORE the PlaybackCompleted dispatch.
      _audios.remove(index);
      // K4: pending listener-question answers are played HERE, BEFORE the next script line
      // (the machine sees this as a "single long line"; indices and the pre-synthesis chain
      // do not change).
      await _playPendingAnswers();
      _dispatch(PlaybackCompleted(index));
    } on Object catch (e) {
      _dispatch(TurnFailed(e.toString()));
    }
  }

  /// Synthesizes and plays the pending answer batches in order. A synthesis error skips the
  /// REST of that answer (the discussion continues); a playback error (e.g. Stop) propagates
  /// up -> the calling [_handlePlay] turns it into TurnFailed.
  Future<void> _playPendingAnswers() async {
    while (_pendingAnswers.isNotEmpty) {
      final turns = await _pendingAnswers.removeAt(0);
      for (final turn in turns) {
        if (_completer.isCompleted) return;
        final Uint8List audio;
        try {
          audio = await synthesize(turn);
        } on Object catch (_) {
          break;
        }
        onInterjectionAboutToPlay?.call(turn);
        await play(audio);
      }
    }
  }

  Future<void> _handleExtend() async {
    try {
      final cont = continueScript;
      if (cont == null) throw StateError('continueScript was not provided');
      final turns = _turns!;
      final recent = turns.length <= kRecentContextTurns
          ? List<DiscussionTurn>.of(turns)
          : turns.sublist(turns.length - kRecentContextTurns);
      // DQ-4: the older turns OUTSIDE the last-6 window (if any) are added to the topic as a
      // light summary -- recent (the verbatim window) does not change.
      final older = turns.length <= kRecentContextTurns
          ? const <DiscussionTurn>[]
          : turns.sublist(0, turns.length - kRecentContextTurns);
      final topicWithContext = withRollingSummary(_topic!, older);
      final more = await cont(topicWithContext, recent);
      // COPY: tests may inject a const (unmodifiable) list.
      _turns = [...turns, ...more];
      onScriptExtended?.call(_turns!);
      _dispatch(ScriptExtended(more.length));
    } on Object catch (e) {
      _dispatch(ExtensionFailed(e.toString()));
    }
  }
}
