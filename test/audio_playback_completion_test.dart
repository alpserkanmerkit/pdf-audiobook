import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sesli_kitap/io/audio_playback.dart';

/// FAZ 0 contract tests (25-agent review findings K20 + K22).
///
/// K20: on Windows, just_audio_windows returns Success IMMEDIATELY for a 'play'
/// request; the `_player.play()` future CANNOT be the end signal. `playToCompletion`
/// reads the end only from the state stream:
///  - processingState completed/idle → finished / no source,
///  - playing=true seen, THEN playing=false (falling edge = pause),
///  - stream closing (dispose) → resolves.
/// playerStateStream is a BehaviorSubject: it replays the LAST value to a new
/// subscriber -- a stale (false, ready) replay must not trigger a fake completion.
///
/// K22: disposeAll has a timeout, so a single hanging native dispose cannot block
/// window close indefinitely.
void main() {
  group('playToCompletion (K20)', () {
    test(
      'Windows semantics: completed is awaited even though start resolves immediately',
      () async {
        final states = StreamController<PlayerState>();
        var bitti = false;
        // start() resolves immediately (the Windows plugin's instant Success).
        final f = playToCompletion(
          states.stream,
          () async {},
        ).then((_) => bitti = true);
        states.add(PlayerState(true, ProcessingState.ready)); // playing
        await pump();
        expect(
          bitti,
          isFalse,
        ); // returning before the track ends is FORBIDDEN (K20 core)
        states.add(PlayerState(true, ProcessingState.completed));
        await pump();
        expect(bitti, isTrue);
        await f;
        await states.close();
      },
    );

    test('stale replay (false, ready) does not trigger a fake end', () async {
      final states = StreamController<PlayerState>();
      var bitti = false;
      unawaited(
        playToCompletion(states.stream, () async {}).then((_) => bitti = true),
      );
      // The BehaviorSubject's last value before play: not playing yet.
      states.add(PlayerState(false, ProcessingState.ready));
      await pump();
      expect(
        bitti,
        isFalse,
      ); // a fall does not count without a rising edge seen first
      states
        ..add(PlayerState(true, ProcessingState.ready))
        ..add(PlayerState(true, ProcessingState.completed));
      await pump();
      expect(bitti, isTrue);
      await states.close();
    });

    test('falling edge (pause/cut) resolves the waiter', () async {
      final states = StreamController<PlayerState>();
      var bitti = false;
      unawaited(
        playToCompletion(states.stream, () async {}).then((_) => bitti = true),
      );
      states.add(PlayerState(true, ProcessingState.ready)); // playing
      await pump();
      expect(bitti, isFalse);
      states.add(PlayerState(false, ProcessingState.ready)); // pause
      await pump();
      expect(bitti, isTrue);
      await states.close();
    });

    test(
      'player without source: idle state resolves immediately (does not hang)',
      () async {
        final states = StreamController<PlayerState>();
        var bitti = false;
        unawaited(
          playToCompletion(
            states.stream,
            () async {},
          ).then((_) => bitti = true),
        );
        states.add(PlayerState(false, ProcessingState.idle));
        await pump();
        expect(bitti, isTrue);
        await states.close();
      },
    );

    test('stream closing (dispose) resolves the waiter', () async {
      final states = StreamController<PlayerState>();
      var bitti = false;
      unawaited(
        playToCompletion(states.stream, () async {}).then((_) => bitti = true),
      );
      states.add(PlayerState(true, ProcessingState.ready));
      await pump();
      expect(bitti, isFalse);
      await states.close(); // dispose → onDone
      await pump();
      expect(bitti, isTrue);
    });

    test('start error propagates to the caller', () async {
      final states = StreamController<PlayerState>();
      await expectLater(
        playToCompletion(
          states.stream,
          () async => throw StateError('play failed'),
        ),
        throwsStateError,
      );
      await states.close();
    });
  });

  group('disposeAll timeout (K22)', () {
    test('a hanging native dispose does not block exit indefinitely', () async {
      final ops = _HangingDisposeOps();
      final player = GuardedAudioPlayer(ops: ops);
      // Without the timeout this await would hang forever (the test timeout would
      // fire); returning IS the success.
      await GuardedAudioPlayer.disposeAll(
        timeout: const Duration(milliseconds: 50),
      );
      expect(player.isDisposed, isTrue);
      expect(ops.disposeCalled, isTrue);
    });
  });
}

/// Drains the microtask + event queue.
Future<void> pump() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Fake whose dispose never finishes, simulating a native layer (K22 scenario).
class _HangingDisposeOps implements AudioPlayerOps {
  bool disposeCalled = false;

  @override
  Duration? get currentDuration => null;

  @override
  Duration? get currentPosition => null;

  @override
  Future<void> pause() async {}

  @override
  Future<void> setFilePath(String path, {Duration? initialPosition}) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> dispose() {
    disposeCalled = true;
    return Completer<void>().future; // never resolves
  }
}
