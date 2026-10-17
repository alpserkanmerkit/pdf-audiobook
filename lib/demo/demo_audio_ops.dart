// DEMO mode: just_audio has no Linux plugin -> a silent, REAL-TIME fake player.
// AudioPlayerOps contract (lib/io/audio_playback.dart): play() stays pending
// until the track ends or pause()/dispose() is called, so GuardedAudioPlayer
// (K20 logic) and the reader's karaoke highlight (duration + position reads)
// progress through the same path as with the real player.
import 'dart:async';
import 'dart:io';

import 'package:sesli_kitap/demo/demo_wav.dart';
import 'package:sesli_kitap/io/audio_playback.dart';

class DemoAudioOps implements AudioPlayerOps {
  DemoAudioOps({this.fallbackDuration = const Duration(seconds: 2)});

  /// Used when the loaded file is not a WAV (duration cannot be read).
  final Duration fallbackDuration;

  /// Loaded file paths (for tests / verification).
  final List<String> loadedPaths = <String>[];

  /// Number of [play] calls (for tests / verification).
  int playCalls = 0;

  Duration? _duration;
  Duration _base = Duration.zero;
  final Stopwatch _clock = Stopwatch();
  Timer? _timer;
  Completer<void>? _pending;

  @override
  Duration? get currentDuration => _duration;

  @override
  Duration? get currentPosition {
    final total = _duration;
    if (total == null) return null;
    final pos = _base + _clock.elapsed;
    return pos > total ? total : pos;
  }

  @override
  Future<void> setFilePath(String path, {Duration? initialPosition}) async {
    _halt();
    loadedPaths.add(path);
    Duration? d;
    try {
      d = wavDuration(File(path).readAsBytesSync());
    } on FileSystemException {
      d = null;
    }
    _duration = d ?? fallbackDuration;
    _base = initialPosition ?? Duration.zero;
    _clock.reset();
  }

  @override
  Future<void> play() {
    playCalls++;
    final total = _duration;
    if (total == null) return Future<void>.value();
    _releasePending();
    final remaining = total - _base;
    if (remaining <= Duration.zero) return Future<void>.value();
    final done = Completer<void>();
    _pending = done;
    _clock
      ..reset()
      ..start();
    _timer = Timer(remaining, () {
      _base = total;
      _clock
        ..stop()
        ..reset();
      _timer = null;
      _releasePending();
    });
    return done.future;
  }

  @override
  Future<void> pause() async => _halt();

  @override
  Future<void> dispose() async => _halt();

  /// Freezes the position, cancels the timer, and completes the pending play().
  void _halt() {
    if (_timer != null) {
      _timer!.cancel();
      _timer = null;
      final total = _duration;
      final pos = _base + _clock.elapsed;
      _base = (total != null && pos > total) ? total : pos;
    }
    _clock
      ..stop()
      ..reset();
    _releasePending();
  }

  void _releasePending() {
    final p = _pending;
    _pending = null;
    if (p != null && !p.isCompleted) p.complete();
  }
}
