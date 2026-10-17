// W0 test helper (oracle). SesliKitapApp now takes AppServices from the
// composition root; so that wiring tests can build the app WITHOUT touching
// the real platform channels (path_provider / just_audio), it provides mock
// prefs, a temporary data dir and a fake audio ops factory.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/io/audio_playback.dart';
import 'package:sesli_kitap/main.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake [AudioPlayerOps] that records calls: no native channel; call counters
/// are visible to the wiring tests.
///
/// PHASE W4: [play] now stays pending like the real just_audio (it does not
/// return immediately). The future returned by GuardedAudioPlayer.playFile is
/// not resolved by this fake until the track finishes or is cut off. Tests
/// tell a "natural end" (via [completeCurrentPlay]) apart from an
/// "interruption" (via the [pause] call, which the upper layer of playFile
/// triggers with stop()). This is the fake counterpart of the K20
/// playToCompletion contract: seeing play=true followed by false = end.
class RecordingAudioOps implements AudioPlayerOps {
  int pauseCalls = 0;
  int playCalls = 0;
  int disposeCalls = 0;
  final List<String> loadedPaths = <String>[];

  /// A3: initialPosition values passed to setFilePath, in the SAME order as
  /// [loadedPaths] (indexes match). Reader wiring tests verify the claim
  /// "which position did playFile want to resume from" against this list.
  final List<Duration?> loadedInitialPositions = <Duration?>[];

  /// If set, the next [play] call throws it (no pending completer is
  /// created). Used to test whether a playback error propagates to the caller
  /// (GuardedAudioPlayer.playFile -> reader_screen onError).
  Object? playError;

  /// Fake player duration (equivalent of just_audio `_player.duration`).
  /// null = duration not loaded yet (default) -> the reader falls back to its
  /// 30 s fallback = old behavior (existing tests do not break). If a test
  /// sets a value, the reader is expected to measure its sentence-highlight
  /// estimate against this REAL duration.
  Duration? fakeDuration;

  /// Fake playback position (equivalent of just_audio `_player.position`).
  /// null = position unknown (default) -> the reader falls back to its old
  /// Stopwatch fallback (existing tests do not break). If a test sets a value,
  /// the reader is expected to advance the karaoke highlight according to this
  /// REAL position. If the value is left FROZEN (pause simulation), the
  /// highlight must freeze too.
  Duration? fakePosition;

  @override
  Duration? get currentDuration => fakeDuration;

  @override
  Duration? get currentPosition => fakePosition;

  Completer<void>? _pending;

  @override
  Future<void> pause() async {
    pauseCalls++;
    // In real just_audio, pause() cuts the track and playToCompletion treats
    // this as an "end" (it sees playing=true, then false).
    final p = _pending;
    if (p != null && !p.isCompleted) {
      _pending = null;
      p.complete();
    }
  }

  @override
  Future<void> setFilePath(String path, {Duration? initialPosition}) async {
    loadedPaths.add(path);
    loadedInitialPositions.add(initialPosition);
  }

  @override
  Future<void> play() {
    playCalls++;
    final err = playError;
    if (err != null) {
      return Future<void>.error(err);
    }
    final completer = Completer<void>();
    _pending = completer;
    return completer.future;
  }

  /// The test's "track ended naturally" signal: resolves the future returned
  /// by the most recent [play] call. No-op if it was already cut or replaced.
  void completeCurrentPlay() {
    final p = _pending;
    if (p != null && !p.isCompleted) {
      _pending = null;
      p.complete();
    }
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

/// Test services: mock prefs + temporary data dir + fake ops factory.
/// If [createdOps] is given, every ops instance the factory produces is also
/// added to it (player-ownership tests read the dispose counter from there).
/// If [pickPdf] is given it is injected into AppServices (W2: tests the "pick
/// file" flow with a fake selection, without touching the real file_picker
/// channel).
Future<AppServices> buildTestServices({
  Map<String, Object> prefsValues = const <String, Object>{},
  List<RecordingAudioOps>? createdOps,
  Future<PickedBook?> Function()? pickPdf,
}) async {
  SharedPreferences.setMockInitialValues(prefsValues);
  final prefs = await SharedPreferences.getInstance();
  final dir = Directory.systemTemp.createTempSync('sesli_kitap_w0_');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // temp dir cleanup is best-effort; it must not fail the test
    }
  });
  return AppServices(
    prefs: prefs,
    dataDir: dir,
    playerOpsFactory: () {
      final ops = RecordingAudioOps();
      createdOps?.add(ops);
      return ops;
    },
    pickPdf: pickPdf,
  );
}

/// One-line setup for the existing wiring tests:
/// `await tester.pumpWidget(await buildTestApp());`
/// If [pickPdf] is given it is passed straight to AppServices (W2 book-adding
/// tests).
Future<SesliKitapApp> buildTestApp({
  bool initialOnboarded = true,
  Future<PickedBook?> Function()? pickPdf,
}) async {
  return SesliKitapApp(
    services: await buildTestServices(pickPdf: pickPdf),
    initialOnboarded: initialOnboarded,
  );
}

/// W2: wraps the app around an [AppServices] instance that the test built
/// beforehand (for persistence tests: after the pump, t2/t3/t5 read the same
/// prefs/dataDir to verify what was written).
SesliKitapApp buildTestAppFromServices(
  AppServices services, {
  bool initialOnboarded = true,
}) {
  return SesliKitapApp(services: services, initialOnboarded: initialOnboarded);
}

/// W1 test helper (oracle): the "restart the app" scenario.
/// Builds a NEW [AppServices] + [SesliKitapApp] on the SAME
/// [SharedPreferences] mock backend (setMockInitialValues is NOT called again,
/// so the same InMemorySharedPreferencesStore is kept). Values written by the
/// previous tree therefore appear as the values read on "reopen" (for
/// persistence tests: write -> restart -> read).
///
/// If [createdOps] is given (A3: in-page position cold-restart test), every
/// fake ops instance created by the new service is also added to it. The
/// position that playFile was called with after the restart is read from here.
Future<AppServices> restartTestServices(
  AppServices previous, {
  List<RecordingAudioOps>? createdOps,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final dir = Directory.systemTemp.createTempSync('sesli_kitap_w1_restart_');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // temp dir cleanup is best-effort; it must not fail the test
    }
  });
  return AppServices(
    prefs: prefs,
    dataDir: dir,
    playerOpsFactory: createdOps == null
        ? null
        : () {
            final ops = RecordingAudioOps();
            createdOps.add(ops);
            return ops;
          },
  );
}

/// [restartTestServices] + [SesliKitapApp] in one line: new services are
/// built, ReadingSettings.load() reads from prefs (the SAME as the production
/// path in main.dart), and a new widget tree is returned.
Future<SesliKitapApp> restartTestApp(
  AppServices previous, {
  bool initialOnboarded = true,
}) async {
  final services = await restartTestServices(previous);
  services.reading.load();
  return SesliKitapApp(services: services, initialOnboarded: initialOnboarded);
}

/// W5 test helper (oracle): uses the REAL prefs-derivation path of main()
/// (initialOnboarded is NOT overridden explicitly: [resolveInitialOnboarded]
/// reads it from prefs, the SAME as the production code in main.dart; single
/// source of truth). Onboarding persistence tests should use this function.
/// All other wiring tests (unrelated to onboarding) keep using an explicit
/// override via [buildTestApp]. Both modes are tests and do not break each
/// other.
Future<SesliKitapApp> buildTestAppFromPrefs({
  Map<String, Object> prefsValues = const <String, Object>{},
}) async {
  final services = await buildTestServices(prefsValues: prefsValues);
  return SesliKitapApp(
    services: services,
    initialOnboarded: resolveInitialOnboarded(services.prefs),
  );
}

/// [restartTestServices] + prefs-derived [SesliKitapApp]: the W5 (onboarding
/// persistence) version of the "restart the app" scenario. initialOnboarded is
/// NOT given explicitly; [resolveInitialOnboarded] reads it from the SAME
/// (restarted) prefs backend. Used to prove that onboarding, once completed, is
/// not shown again in a fresh process.
Future<SesliKitapApp> restartTestAppFromPrefs(AppServices previous) async {
  final services = await restartTestServices(previous);
  services.reading.load();
  return SesliKitapApp(
    services: services,
    initialOnboarded: resolveInitialOnboarded(services.prefs),
  );
}
