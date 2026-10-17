import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// Thin, crash-guarded wrapper over just_audio.
///
/// Why it exists (WER 26.06.2026, PID 13124): just_audio_windows 0.2.3 has an
/// unsynchronized race between dispose and the WinRT media-thread callbacks
/// (the player.hpp `disposed_` flag is not locked; events are sent from the
/// media thread instead of the platform thread). Overlapping stop/load/dispose
/// calls, plus a live native MediaPlayer while the window closed, produced a
/// use-after-free (0xc0000005) inside Windows.Media.dll and then a ucrtbase
/// fail-fast (0xc0000409). Upstream has no fix after 0.2.3, so this guard
/// layer is mandatory.
///
/// Rules it enforces:
///  1. ALL transitions that reach native code (pause/load/play/dispose) are
///     serialized per player in a single queue -- overlapping interop calls
///     cannot happen.
///  2. `dispose` is idempotent and stops the playing audio first; every call
///     after dispose is a silent no-op (a late call cannot cause a crash).
///  3. Live player instances are tracked; [disposeAll] is called BEFORE the
///     window closes (main.dart `AppLifecycleListener.onExitRequested`), so the
///     engine teardown never catches a playing native player.
///
/// Additional principle: interruption uses `pause`, NOT `stop` -- in
/// just_audio, `stop()` tears down the native player and rebuilds it on the
/// next load, which means a native dispose+init cycle on every sentence/turn
/// change (the pattern that triggered the crash). `pause` keeps the same native
/// player.
class GuardedAudioPlayer {
  GuardedAudioPlayer({AudioPlayerOps? ops}) : _ops = ops ?? JustAudioOps() {
    _live.add(this);
  }

  /// Players that have not been disposed yet (to close them all at exit).
  static final Set<GuardedAudioPlayer> _live = <GuardedAudioPlayer>{};

  final AudioPlayerOps _ops;
  Future<void> _chain = Future<void>.value();
  bool _disposed = false;

  bool get isDisposed => _disposed;

  /// Total duration of the active track (null if not loaded yet, or after
  /// dispose). READ-ONLY: not a transition to native, only reads the loaded
  /// metadata -- completely independent of the crash-sensitive serialization
  /// and dispose path (K20 `_chain`). The reader uses it to advance sentence
  /// highlighting by the REAL page duration instead of a fixed assumption.
  Duration? get currentDuration => _disposed ? null : _ops.currentDuration;

  /// Current playback position of the playing track (null if not loaded, or
  /// after dispose). READ-ONLY: same contract as [currentDuration] -- not a
  /// transition to native, only reads the player's current position, and is
  /// independent of the dispose path (K20 `_chain`). The reader uses it to
  /// advance karaoke highlighting by the REAL audio position (not a wall-clock
  /// stopwatch); on pause the position freezes, so the highlight freezes too
  /// (PR-K2).
  Duration? get currentPosition => _disposed ? null : _ops.currentPosition;

  /// Plays the file; waits until the track ENDS or is interrupted (stop, dispose
  /// or a new playFile). Compatible with DiscussionController's `AudioPlayback`
  /// contract: the return means playback has finished.
  ///
  /// If [startAt] is given (resume from the in-page position, A3), it is passed
  /// to the native layer as the load's start position; if not given (default
  /// null), the old behavior is kept EXACTLY -- the track plays from the start.
  Future<void> playFile(String path, {Duration? startAt}) {
    final done = Completer<void>();
    final pending =
        _enqueue(() async {
          await _ops.pause();
          await _ops.setFilePath(path, initialPosition: startAt);
          // The end-wait is DELIBERATELY outside the queue: if it waited in the
          // queue, stop/dispose would be stuck until the end of the track
          // (barge-in would die).
          unawaited(
            _ops.play().then(
              (_) {
                if (!done.isCompleted) done.complete();
              },
              onError: (Object e, StackTrace s) {
                if (!done.isCompleted) done.completeError(e, s);
              },
            ),
          );
        }).then(
          (_) {
            // If the transition fell into a no-op (dispose race), do not leave
            // the caller hanging.
            if (_disposed && !done.isCompleted) done.complete();
          },
          onError: (Object e, StackTrace s) {
            if (!done.isCompleted) done.completeError(e, s);
          },
        );
    unawaited(pending);
    return done.future;
  }

  /// Cuts the playing audio (a pending [playFile] resolves). The native player
  /// stays.
  Future<void> stop() => _enqueue(_ops.pause);

  /// Idempotent shutdown: stop first, then release the native player. Second
  /// and later calls return the same future; errors are swallowed (dispose must
  /// never throw while the window closes).
  Future<void> dispose() {
    if (_disposed) return _chain;
    _disposed = true;
    _live.remove(this);
    return _chain = _chain
        .then((_) async {
          await _ops.pause();
          await _ops.dispose();
        })
        .then((_) {}, onError: (Object _, StackTrace _) {});
  }

  /// Closes all registered players. Called before the window/app closes; leaves
  /// no live native player for the engine teardown.
  ///
  /// [timeout]: if a single native dispose hangs (WinRT Close lock, a transition
  /// stuck on a resource that cannot be loaded), exit is NOT blocked forever --
  /// the hung player is skipped and the rest are closed (K22).
  static Future<void> disposeAll({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    for (final p in List<GuardedAudioPlayer>.of(_live)) {
      await p.dispose().timeout(timeout, onTimeout: () {});
    }
  }

  Future<void> _enqueue(Future<void> Function() op) {
    if (_disposed) return Future<void>.value();
    final run = _chain.then((_) async {
      if (_disposed) return; // queued, but caught by dispose
      await op();
    });
    // The chain does not break on error; the error only goes to that job's
    // caller.
    _chain = run.then((_) {}, onError: (Object _, StackTrace _) {});
    return run;
  }
}

/// Narrow interface for native player operations. Tests pin the contract with a
/// fake implementation; production uses [JustAudioOps].
abstract class AudioPlayerOps {
  /// Total duration of the loaded track (null if unknown). READ-ONLY: does NOT
  /// issue a new transition to native; only the existing metadata is read.
  Duration? get currentDuration;

  /// Current position of the player (null if unknown). READ-ONLY: does NOT issue
  /// a new transition to native; only the current position is read.
  Duration? get currentPosition;

  /// Stops playback; resolves the pending [play] future.
  Future<void> pause();

  /// If [initialPosition] is given, loading starts from that position (A3:
  /// resume from the in-page position); null (default) starts from the
  /// beginning -- the old behavior.
  Future<void> setFilePath(String path, {Duration? initialPosition});

  /// Starts playback; resolves when the track ends OR when it is interrupted by
  /// [pause]/[dispose].
  Future<void> play();

  Future<void> dispose();
}

/// Real just_audio binding. One AudioPlayer; its lifetime is tied to the
/// wrapper.
class JustAudioOps implements AudioPlayerOps {
  final AudioPlayer _player = AudioPlayer();

  @override
  Duration? get currentDuration => _player.duration;

  @override
  Duration? get currentPosition => _player.position;

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> setFilePath(String path, {Duration? initialPosition}) async {
    await _player.setFilePath(path, initialPosition: initialPosition);
  }

  @override
  Future<void> play() =>
      playToCompletion(_player.playerStateStream, _player.play);

  @override
  Future<void> dispose() => _player.dispose();
}

/// Starts playback with [start] and reads the end ONLY from the state stream.
///
/// K20 (Windows): just_audio_windows returns Success for the 'play' request
/// immediately; just_audio also completes the play() future on the platform
/// response -- so `_player.play()` resolves on Windows as soon as playback
/// STARTS, and it CANNOT be an end signal. Here the future of [start] is only
/// the ERROR channel.
///
/// End conditions:
///  - processingState completed/idle → track ended / no source,
///  - playing=true seen, THEN playing=false → pause/interruption
///    (`sawPlaying` flag: playerStateStream is a BehaviorSubject; a new
///    subscriber replays the stale `(false, ready)` value from before play --
///    a drop without a seen rising edge does not count as the end),
///  - stream closure (dispose) → resolves.
Future<void> playToCompletion(
  Stream<PlayerState> states,
  Future<void> Function() start,
) async {
  final done = Completer<void>();
  var sawPlaying = false;
  late final StreamSubscription<PlayerState> sub;
  sub = states.listen(
    (s) {
      if (s.processingState == ProcessingState.completed ||
          s.processingState == ProcessingState.idle) {
        if (!done.isCompleted) done.complete();
      } else if (s.playing) {
        sawPlaying = true;
      } else if (sawPlaying && !done.isCompleted) {
        done.complete();
      }
    },
    onDone: () {
      if (!done.isCompleted) done.complete();
    },
  );
  try {
    unawaited(
      start().then(
        (_) {}, // start acknowledgment -- NOT the end (K20)
        onError: (Object e, StackTrace st) {
          if (!done.isCompleted) done.completeError(e, st);
        },
      ),
    );
    await done.future;
  } finally {
    await sub.cancel();
  }
}
