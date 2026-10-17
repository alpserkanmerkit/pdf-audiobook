// DemoAudioOps: a REAL-TIME silent player without native just_audio (no plugin on Linux).
// The contract is the same as AudioPlayerOps/GuardedAudioPlayer: play() stays
// pending until the track ends or pause()/dispose() is called; duration and
// position drive the reader's karaoke highlight.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/demo/demo_audio_ops.dart';
import 'package:sesli_kitap/demo/demo_wav.dart';
import 'package:sesli_kitap/io/audio_playback.dart';

File _wavFile(Directory dir, Duration d, [String name = 'a.wav']) =>
    File('${dir.path}/$name')..writeAsBytesSync(silentWav(duration: d));

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('demo_ops_test_'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('demo_wav', () {
    test(
      'silentWav is valid RIFF/WAVE and wavDuration reads the same duration',
      () {
        final bytes = silentWav(duration: const Duration(seconds: 3));
        expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
        expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
        final d = wavDuration(bytes)!;
        expect(d.inMilliseconds, closeTo(3000, 5));
      },
    );

    test('wavDuration returns null for non-WAV bytes', () {
      expect(wavDuration(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test(
      'demoSpeechDuration scales with characters/second and has a lower bound',
      () {
        final d = demoSpeechDuration('a' * 450);
        expect(d.inSeconds, 10);
        expect(demoSpeechDuration('a'), const Duration(milliseconds: 1500));
      },
    );
  });

  group('DemoAudioOps', () {
    test(
      'setFilePath reads the WAV duration; duration/position are null before loading',
      () async {
        final ops = DemoAudioOps();
        expect(ops.currentDuration, isNull);
        expect(ops.currentPosition, isNull);
        await ops.setFilePath(_wavFile(dir, const Duration(seconds: 2)).path);
        expect(ops.currentDuration!.inMilliseconds, closeTo(2000, 5));
        expect(ops.currentPosition, Duration.zero);
        expect(ops.loadedPaths, hasLength(1));
      },
    );

    test(
      'play() resolves when the duration elapses and the position equals the duration',
      () async {
        final ops = DemoAudioOps();
        await ops.setFilePath(
          _wavFile(dir, const Duration(milliseconds: 300)).path,
        );
        final sw = Stopwatch()..start();
        await ops.play();
        expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(250));
        expect(ops.currentPosition, ops.currentDuration);
      },
    );

    test(
      'pause() resolves the pending play() early; position freezes on pause',
      () async {
        final ops = DemoAudioOps();
        await ops.setFilePath(_wavFile(dir, const Duration(seconds: 30)).path);
        final played = ops.play();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await ops.pause();
        await played.timeout(const Duration(seconds: 2));
        final frozen = ops.currentPosition!;
        expect(frozen.inMilliseconds, inInclusiveRange(100, 1500));
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(
          ops.currentPosition,
          frozen,
          reason: 'position freezes when paused',
        );
      },
    );

    test(
      'initialPosition starts from that position and plays the remaining duration',
      () async {
        final ops = DemoAudioOps();
        await ops.setFilePath(
          _wavFile(dir, const Duration(milliseconds: 600)).path,
          initialPosition: const Duration(milliseconds: 400),
        );
        expect(ops.currentPosition, const Duration(milliseconds: 400));
        final sw = Stopwatch()..start();
        await ops.play();
        expect(sw.elapsedMilliseconds, lessThan(500));
      },
    );

    test('dispose() resolves the pending play()', () async {
      final ops = DemoAudioOps();
      await ops.setFilePath(_wavFile(dir, const Duration(seconds: 30)).path);
      final played = ops.play();
      await ops.dispose();
      await played.timeout(const Duration(seconds: 2));
    });

    test('GuardedAudioPlayer(ops: DemoAudioOps) playFile completes', () async {
      final ops = DemoAudioOps();
      final player = GuardedAudioPlayer(ops: ops);
      addTearDown(player.dispose);
      await player
          .playFile(_wavFile(dir, const Duration(milliseconds: 250)).path)
          .timeout(const Duration(seconds: 3));
      expect(ops.loadedPaths, hasLength(1));
    });

    test('a fallback duration is used for a non-WAV file (no crash)', () async {
      final f = File('${dir.path}/x.mp3')..writeAsBytesSync([0x49, 0x44, 0x33]);
      final ops = DemoAudioOps(fallbackDuration: const Duration(seconds: 4));
      await ops.setFilePath(f.path);
      expect(ops.currentDuration, const Duration(seconds: 4));
    });
  });
}
