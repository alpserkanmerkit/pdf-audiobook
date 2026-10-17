import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/io/audio_playback.dart';

/// GuardedAudioPlayer contract tests -- pin the guards against the 26.06.2026 Windows
/// crash (just_audio_windows use-after-free). Mock boundary: no real just_audio; the
/// AudioPlayerOps fake represents the native layer.
///
/// Pinned rules:
///  1. Transition order: pause -> setFilePath -> play (never overlapping).
///  2. A cut (stop / new playFile / dispose) resolves the pending play.
///  3. dispose is idempotent; after it every call is a silent no-op.
///  4. disposeAll closes all live players.
void main() {
  test('playFile transition order: pause -> setFilePath -> play', () async {
    final ops = FakeOps();
    final player = GuardedAudioPlayer(ops: ops);

    final done = player.playFile('a.mp3');
    await pumpMicrotasks();
    ops.completeTrack();
    await done;

    expect(ops.log, ['pause', 'setFilePath:a.mp3', 'play']);
    await player.dispose();
  });

  test(
    'serialization: the second playFile does not start before the first transition finishes',
    () async {
      final ops = FakeOps()
        ..holdSetFilePath = true; // hold the first load pending
      final player = GuardedAudioPlayer(ops: ops);

      unawaited(player.playFile('a.mp3'));
      unawaited(player.playFile('b.mp3'));
      await pumpMicrotasks();

      // The first setFilePath is still pending: there must be no trace of the second transition.
      expect(ops.log, ['pause', 'setFilePath:a.mp3']);

      ops.releaseSetFilePath();
      await pumpMicrotasks();

      // Now the second transition proceeds in order.
      expect(ops.log, [
        'pause',
        'setFilePath:a.mp3',
        'play',
        'pause',
        'setFilePath:b.mp3',
        'play',
      ]);
      await player.dispose();
    },
  );

  test(
    'barge-in: a new playFile cuts the previous one, the previous future resolves',
    () async {
      final ops = FakeOps();
      final player = GuardedAudioPlayer(ops: ops);

      final first = player.playFile('a.mp3');
      await pumpMicrotasks();
      expect(ops.playing, isTrue);

      final second = player.playFile('b.mp3');
      await pumpMicrotasks();

      // The second's pause must have resolved the first's pending play.
      await first;

      ops.completeTrack();
      await second;
      await player.dispose();
    },
  );

  test('stop resolves the pending playFile future', () async {
    final ops = FakeOps();
    final player = GuardedAudioPlayer(ops: ops);

    final done = player.playFile('a.mp3');
    await pumpMicrotasks();
    expect(ops.playing, isTrue);

    await player.stop();
    await done; // must not hang

    expect(ops.playing, isFalse);
    await player.dispose();
  });

  test(
    'dispose: idempotent, cuts playback, native dispose runs ONCE',
    () async {
      final ops = FakeOps();
      final player = GuardedAudioPlayer(ops: ops);

      final done = player.playFile('a.mp3');
      await pumpMicrotasks();

      await player.dispose();
      await player.dispose(); // second call is a no-op
      await done; // playing audio was cut, the caller did not hang

      expect(ops.log.where((e) => e == 'dispose').length, 1);
      // the cut arrived before dispose:
      expect(ops.log.indexOf('dispose'), greaterThan(ops.log.indexOf('pause')));
      expect(player.isDisposed, isTrue);
    },
  );

  test('after dispose, playFile/stop are silent no-ops', () async {
    final ops = FakeOps();
    final player = GuardedAudioPlayer(ops: ops);
    await player.dispose();
    final before = List<String>.of(ops.log);

    await player.playFile('a.mp3'); // must not hang or crash
    await player.stop();

    expect(ops.log, before); // no call reached the native layer
  });

  test('dispose also cancels the work waiting in the queue', () async {
    final ops = FakeOps()..holdSetFilePath = true;
    final player = GuardedAudioPlayer(ops: ops);

    final pending = player.playFile('a.mp3');
    await pumpMicrotasks();
    final queued = player.playFile('b.mp3'); // waiting in the queue

    final disposed = player.dispose();
    ops.releaseSetFilePath();
    await disposed;
    await pending;
    await queued; // b.mp3 must resolve without ever being loaded

    expect(ops.log.contains('setFilePath:b.mp3'), isFalse);
  });

  test('disposeAll: closes all live players', () async {
    final ops1 = FakeOps();
    final ops2 = FakeOps();
    final p1 = GuardedAudioPlayer(ops: ops1);
    final p2 = GuardedAudioPlayer(ops: ops2);

    unawaited(p1.playFile('a.mp3'));
    await pumpMicrotasks();

    await GuardedAudioPlayer.disposeAll();

    expect(p1.isDisposed, isTrue);
    expect(p2.isDisposed, isTrue);
    expect(ops1.log.last, 'dispose');
    expect(ops2.log.last, 'dispose');

    await GuardedAudioPlayer.disposeAll(); // second call is a no-op
    expect(ops1.log.where((e) => e == 'dispose').length, 1);
  });

  test(
    'currentPosition delegates to the ops position; null after dispose',
    () async {
      final ops = FakeOps();
      final player = GuardedAudioPlayer(ops: ops);

      // While the ops position is null, the player also returns null (position not loaded).
      expect(player.currentPosition, isNull);

      // When ops reports a position, the player delegates it AS IS (READ-ONLY).
      ops.fakePosition = const Duration(milliseconds: 8500);
      expect(player.currentPosition, const Duration(milliseconds: 8500));

      // After dispose the getter returns null WITHOUT touching ops at all (the SAME
      // contract as currentDuration -- independent of the crash-sensitive path).
      await player.dispose();
      expect(player.currentPosition, isNull);
    },
  );

  test(
    'a play error does not break the chain: the next playFile still runs',
    () async {
      final ops = FakeOps();
      final player = GuardedAudioPlayer(ops: ops);

      final failing = player.playFile('bozuk.mp3');
      await pumpMicrotasks();
      ops.failTrack('decode error');
      await expectLater(failing, throwsA(isA<StateError>()));

      final ok = player.playFile('saglam.mp3');
      await pumpMicrotasks();
      ops.completeTrack();
      await ok;

      expect(ops.log.contains('setFilePath:saglam.mp3'), isTrue);
      await player.dispose();
    },
  );

  group('playFile startAt (A3 -- resume from an in-page position)', () {
    test(
      'if startAt is given, ops.setFilePath is CALLED with initialPosition',
      () async {
        final ops = FakeOps();
        final player = GuardedAudioPlayer(ops: ops);

        final done = player.playFile(
          'a.mp3',
          startAt: const Duration(seconds: 12, milliseconds: 500),
        );
        await pumpMicrotasks();
        ops.completeTrack();
        await done;

        expect(ops.setFilePathPositions.single, 'a.mp3');
        expect(
          ops.setFilePathInitialPositions.single,
          const Duration(seconds: 12, milliseconds: 500),
        );
        await player.dispose();
      },
    );

    test(
      'if startAt is not given (regression pin) initialPosition is passed as null -- '
      'the old behavior is kept EXACTLY',
      () async {
        final ops = FakeOps();
        final player = GuardedAudioPlayer(ops: ops);

        final done = player.playFile('a.mp3');
        await pumpMicrotasks();
        ops.completeTrack();
        await done;

        expect(ops.log, ['pause', 'setFilePath:a.mp3', 'play']);
        expect(ops.setFilePathInitialPositions.single, isNull);
        await player.dispose();
      },
    );
  });
}

/// Drains the microtask queue (so chained thens can run).
Future<void> pumpMicrotasks() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Fake native layer. Imitates the just_audio contract: play() resolves when the
/// track ends ([completeTrack]) OR on pause/dispose.
class FakeOps implements AudioPlayerOps {
  final List<String> log = [];
  bool playing = false;
  bool holdSetFilePath = false;

  /// These contract tests do not use the duration; returns null to satisfy the
  /// interface's new read-only getter (duration not loaded).
  @override
  Duration? get currentDuration => null;

  /// Position: null by default (position not loaded). The delegation test assigns a
  /// value and verifies that GuardedAudioPlayer.currentPosition passes it through AS IS.
  Duration? fakePosition;

  @override
  Duration? get currentPosition => fakePosition;

  Completer<void>? _track;
  Completer<void>? _setFilePathGate;

  /// For the startAt delegation tests: the paths and initialPosition values passed to
  /// setFilePath are recorded in order (the SAME order as log).
  final List<String> setFilePathPositions = [];
  final List<Duration?> setFilePathInitialPositions = [];

  @override
  Future<void> pause() async {
    log.add('pause');
    playing = false;
    _track?.complete();
    _track = null;
  }

  @override
  Future<void> setFilePath(String path, {Duration? initialPosition}) async {
    log.add('setFilePath:$path');
    setFilePathPositions.add(path);
    setFilePathInitialPositions.add(initialPosition);
    if (holdSetFilePath) {
      _setFilePathGate = Completer<void>();
      await _setFilePathGate!.future;
    }
  }

  @override
  Future<void> play() {
    log.add('play');
    playing = true;
    _track = Completer<void>();
    return _track!.future;
  }

  @override
  Future<void> dispose() async {
    log.add('dispose');
    playing = false;
    _track?.complete();
    _track = null;
  }

  /// Imitates the track's natural end.
  void completeTrack() {
    playing = false;
    _track?.complete();
    _track = null;
  }

  /// Imitates the track failing with an error.
  void failTrack(String reason) {
    playing = false;
    _track?.completeError(StateError(reason));
    _track = null;
  }

  void releaseSetFilePath() {
    holdSetFilePath = false;
    _setFilePathGate?.complete();
    _setFilePathGate = null;
  }
}
