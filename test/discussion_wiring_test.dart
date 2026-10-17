// Slice-6 WIRING test (§13.7 — oracle). Is the discussion room connected to the
// app_shell discussion tab?
// (Real LLM/TTS flow + voice input/STT device acceptance are parked; this test covers visual reachability.)
//
// W6 additions (oracle, this file): DiscussionRoomScreen takes the real orchestrator
// from the empty shell. Tests inject fake generate/synthesize/play through the
// screen's test seam (debugControllerFactory), so the full flow is proven without
// touching the real Gemini/Google-TTS/just_audio.
// Seam: DiscussionRoomScreen({debugControllerFactory}) -- when given, the screen uses
// the controller produced by this factory WITHOUT touching AppServicesScope at all
// (robustness_test.dart's scope-less isolated pump stays valid because build() never
// calls AppServicesScope.of; real services are read only when the user submits a
// topic AND debugControllerFactory is NOT given).
//
//  t1: play -> topic dialog -> submit -> turns render in order with the correct speaker names.
//  t2: play callback (the adaptor the screen builds itself) runs the full chain
//      bytes -> fake cache.writeAudio -> fake player.playFile.
//  t3: stop control halts processing of turns after the tap.
//  t4: generate error -> visible error state, no crash.
//  t5: when the first discussion ends, a SECOND one runs (FAZ2a K10 single-use guard regression).
//  t6: no visible control keeps an empty onPressed: () {} (structural sweep).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/discussion/discussion_controller.dart';
import 'package:sesli_kitap/src/discussion/discussion_presenter.dart';
import 'package:sesli_kitap/src/discussion/discussion_session.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';
import 'package:sesli_kitap/ui/screens/discussion_room_screen.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';

import 'helpers/async_settle.dart';
import 'helpers/pump_fast.dart';
import 'helpers/test_app.dart';

/// Fake in-memory cache: proves the t2 bytes -> file -> playFile chain
/// without touching the real file system.
class FakeCache {
  final Map<String, Uint8List> written = {};

  Future<String> writeAudio(String key, Uint8List bytes) async {
    if (written.containsKey(key)) {
      throw StateError(
        'cache key COLLIDED: $key (turns would overwrite the same file)',
      );
    }
    written[key] = bytes;
    return '/fake-cache/$key.mp3';
  }
}

/// Fake recording player: exposes the paths passed to playFile and the stop() calls.
class FakePlayer {
  final List<String> playedPaths = [];
  int stopCalls = 0;

  Future<void> playFile(String path) async {
    playedPaths.add(path);
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }

  // Mirrors the real player's stop() surface; not called in this file.
  // ignore: unreachable_from_main
  Future<void> stop() async {
    stopCalls++;
  }
}

/// Test-seam helper: a [DiscussionController] factory with fake generate/synthesize
/// and a play callback built in the SAME SHAPE as the real adaptor
/// (bytes -> cache.writeAudio -> player.playFile). If [cache]/[player] are not
/// given, scenarios like t1/t3/t4/t5 fall back to internal simple fakes.
DiscussionController Function() fakeControllerFactory({
  required List<String> log,
  required List<DiscussionTurn> turns,
  Object? generateThrows,
  FakeCache? cache,
  FakePlayer? player,
  bool Function()? isStopped,
  Duration playDelay = const Duration(milliseconds: 5),
  // S2 infinite mode: when openEnded + continueBatches are given, the screen runs a
  // continuation-batch chain through its OWN (stop-aware) wrappers. continueBatches
  // are consumed IN ORDER; when exhausted they THROW so every test stays FINITE
  // (pumpAndSettle never finishes against an infinite source).
  bool openEnded = false,
  List<List<DiscussionTurn>>? continueBatches,
}) {
  var turnCounter = 0;
  var batchIndex = 0;
  return () => DiscussionController(
    openEnded: openEnded,
    continueScript: continueBatches == null
        ? null
        : (topic, recent) async {
            if (isStopped?.call() ?? false) {
              throw StateError('stopped: continuation must not start');
            }
            if (batchIndex >= continueBatches.length) {
              // Source exhausted -> ExtensionFailed -> the run ends gracefully (FINITE).
              throw StateError('continuation batches exhausted');
            }
            final batch = continueBatches[batchIndex++];
            log.add('C:${batch.map((t) => t.speaker.name).join(",")}');
            return batch;
          },
    generate: (topic) async {
      log.add('G:$topic');
      // Deliberately throws the GIVEN object (including non-Exception values).
      // ignore: only_throw_errors
      if (generateThrows != null) throw generateThrows;
      return turns;
    },
    synthesize: (turn) async {
      if (isStopped?.call() ?? false) {
        throw StateError('stopped: synthesis must not start');
      }
      log.add('S:${turn.speaker.name}:${turn.text}');
      return Uint8List.fromList(utf8.encode(turn.text));
    },
    play: (mp3) async {
      if (isStopped?.call() ?? false) {
        throw StateError('stopped: playback must not start');
      }
      final text = utf8.decode(mp3);
      log.add('P:$text');
      if (cache != null && player != null) {
        final path = await cache.writeAudio('turn_${turnCounter++}', mp3);
        await player.playFile(path);
      } else {
        await Future<void>.delayed(playDelay);
      }
    },
  );
}

/// Wraps [DiscussionRoomScreen] alone (with its own theme/settings scope).
/// Same isolated-pump pattern as robustness_test.dart.
Widget _wrapScreen(Widget child) {
  final settings = AppSettings();
  return AppSettingsScope(
    settings: settings,
    child: MaterialApp(theme: buildAppTheme(settings), home: child),
  );
}

/// Opens the topic dialog (taps the top-bar play IconButton -- the idle center
/// circle carries the same Icons.play_arrow, so find.byIcon alone is ambiguous;
/// widgetWithIcon(IconButton, ...) targets only the IconButton ancestor), types
/// the topic, and submits it.
Future<void> _startDiscussion(
  WidgetTester tester, {
  String topic = 'time perception',
  bool infinite = false,
}) async {
  await tester.tap(find.widgetWithIcon(IconButton, Icons.play_arrow));
  await pumpSettle(tester);
  expect(
    find.byType(TextField),
    findsWidgets,
    reason: 'at least one TextField is expected for the topic input',
  );
  await tester.enterText(find.byType(TextField).first, topic);
  await pumpSettle(tester);
  if (infinite) {
    // DQ-W1: in the 4-way length-mode picker, choosing "Endless" is equivalent to
    // the old "infinite mode" checkbox (openEnded=true).
    await tester.tap(find.text('Endless'));
    await pumpSettle(tester);
  }
  await tester.tap(find.text('Start'));
  await tester.pump();
}

/// Returns the BoxDecoration of the 72x72 Container circle of the avatar labeled [name].
/// The visual marker of being active is `decoration.boxShadow` in `_buildSingleAvatar`
/// (set while active, null otherwise). find.byType matches the EXACT runtimeType, so
/// there is no generic trap (Container/Column are not generic); the nearest ancestor
/// Column is the root of `_buildSingleAvatar`, and its FIRST Container child is the circle.
BoxDecoration _avatarDecoration(WidgetTester tester, String name) {
  final avatarColumn = find
      .ancestor(of: find.text(name), matching: find.byType(Column))
      .first;
  final circle = tester.widget<Container>(
    find.descendant(of: avatarColumn, matching: find.byType(Container)).first,
  );
  return circle.decoration! as BoxDecoration;
}

void main() {
  testWidgets('Discussion tab shows the four speakers and the routing chips', (
    tester,
  ) async {
    await tester.pumpWidget(await buildTestApp());
    await pumpSettle(tester);

    await tester.tap(find.text('Discussion'));
    await pumpSettle(tester);

    expect(find.byKey(const Key('tab-discussion')), findsOneWidget);
    // FOUR speakers (4 people — each speaker has their own face)
    expect(find.text('Ahmet'), findsWidgets);
    expect(find.text('Emel'), findsWidgets);
    expect(find.text('Deniz'), findsWidgets);
    expect(find.text('Kaya'), findsWidgets);
    // routing chips
    expect(find.textContaining('Go deeper'), findsWidgets);
    expect(find.textContaining('Compare'), findsWidgets);
  });

  group('W6 — t1: startup flow', () {
    testWidgets(
      'play -> enter topic -> submit -> turns render in order with the correct speaker',
      (tester) async {
        final log = <String>[];
        const turns = [
          DiscussionTurn(
            DiscussionSpeaker.a,
            'The first line belongs to Ahmet.',
          ),
          DiscussionTurn(DiscussionSpeaker.b, 'Now Emel steps in.'),
        ];
        await tester.pumpWidget(
          _wrapScreen(
            DiscussionRoomScreen(
              debugControllerFactory: fakeControllerFactory(
                log: log,
                turns: turns,
                // Leave a visible gap between turns so t0's VISIBLE state can be
                // captured with a BOUNDED pump before t1 overwrites it
                // (pumpAndSettle would run the whole flow to the end in one go --
                // the t0/t1 VISIBLE states are only observable as an intermediate
                // step with a bounded pump; DiscussionController is FROZEN/single-use,
                // so inserting another pumpAndSettle here would jump ahead to t1).
                playDelay: const Duration(milliseconds: 60),
              ),
            ),
          ),
        );
        await pumpSettle(tester);

        await _startDiscussion(tester);
        // BOUNDED pump: t0's play has started (setState done) but t1's play has NOT
        // started yet (playDelay=60ms >> this window).
        await tester.pump(const Duration(milliseconds: 20));

        expect(log, contains('G:time perception'));
        expect(
          find.textContaining('The first line belongs to Ahmet.'),
          findsOneWidget,
        );
        // DQ-W1: the pill now shows the turn counter in EVERY mode ("Ahmet is speaking ·
        // 1. turn") -- we pin the distinctive prefix with textContaining.
        expect(find.textContaining('Ahmet is speaking'), findsOneWidget);

        // Now advance enough for t0's playback to finish AND t1 to start, but NOT a
        // full settle -- just a small bounded window so t1's play also starts.
        await tester.pump(const Duration(milliseconds: 80));
        expect(find.textContaining('Now Emel steps in.'), findsOneWidget);
        expect(find.textContaining('Emel is speaking'), findsOneWidget);

        // Finish the flow (let t1's play conclude too; controller.run() need not be
        // awaited -- bounded pumps are enough to clear the remaining timers, there is
        // no real timeout).
        await tester.pump(const Duration(milliseconds: 100));

        expect(log.where((e) => e.startsWith('P:')).toList(), [
          'P:The first line belongs to Ahmet.',
          'P:Now Emel steps in.',
        ]);
      },
    );
  });

  group('W6 — t2: bytes -> cache -> playFile adaptor chain', () {
    testWidgets(
      'play callback runs the fake cache.writeAudio + player.playFile chain in full',
      (tester) async {
        final log = <String>[];
        final cache = FakeCache();
        final player = FakePlayer();
        const turns = [DiscussionTurn(DiscussionSpeaker.a, 'one line')];

        await tester.pumpWidget(
          _wrapScreen(
            DiscussionRoomScreen(
              debugControllerFactory: fakeControllerFactory(
                log: log,
                turns: turns,
                cache: cache,
                player: player,
              ),
            ),
          ),
        );
        await pumpSettle(tester);

        await _startDiscussion(tester);
        await pumpSettle(tester);

        expect(
          cache.written,
          hasLength(1),
          reason: 'one turn -> cache must be written exactly once',
        );
        final writtenBytes = cache.written.values.single;
        expect(utf8.decode(writtenBytes), 'one line');

        expect(
          player.playedPaths,
          hasLength(1),
          reason:
              'playFile must be called with the RESULT (file path) of cache.writeAudio',
        );
        expect(player.playedPaths.single, startsWith('/fake-cache/'));
        expect(player.playedPaths.single, endsWith('.mp3'));
      },
    );
  });

  group('W6 — t3: stop control', () {
    testWidgets('stop -> turns after the tap are not processed', (
      tester,
    ) async {
      final log = <String>[];
      const turns = [
        DiscussionTurn(DiscussionSpeaker.a, 'first'),
        DiscussionTurn(DiscussionSpeaker.b, 'second'),
        DiscussionTurn(DiscussionSpeaker.c, 'third'),
        DiscussionTurn(DiscussionSpeaker.d, 'fourth'),
      ];
      var stopped = false;
      await tester.pumpWidget(
        _wrapScreen(
          DiscussionRoomScreen(
            debugControllerFactory: fakeControllerFactory(
              log: log,
              turns: turns,
              isStopped: () => stopped,
              playDelay: const Duration(milliseconds: 40),
            ),
          ),
        ),
      );
      await pumpSettle(tester);

      await _startDiscussion(tester);
      // First turn starts playing (S:a + P:first logged) but must NOT finish.
      await tester.pump(const Duration(milliseconds: 15));

      expect(
        log.where((e) => e.startsWith('P:')).toList(),
        ['P:first'],
        reason:
            'before stopping, only the first turn should have started playing',
      );

      // Tap the stop control (center circle, acts as stop while running).
      stopped = true;
      await tester.tap(find.byKey(const Key('discussion-stop-control')));
      await tester.pump();
      // Let the remaining timers/futures run.
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        log.where((e) => e.startsWith('P:')).toList(),
        ['P:first'],
        reason:
            'after stop, NO new turn may be played (no second/third/fourth)',
      );
      expect(
        log.where((e) => e.startsWith('S:')).length,
        lessThan(turns.length),
        reason: 'after stop, not all remaining turns can have been synthesized',
      );
    });
  });

  group('W6 — t4: error state', () {
    testWidgets('generate error produces a visible error state, no crash', (
      tester,
    ) async {
      final log = <String>[];
      await tester.pumpWidget(
        _wrapScreen(
          DiscussionRoomScreen(
            debugControllerFactory: fakeControllerFactory(
              log: log,
              turns: const [],
              generateThrows: Exception('LLM 500'),
            ),
          ),
        ),
      );
      await pumpSettle(tester);

      await _startDiscussion(tester);
      // generate() throws IMMEDIATELY -> no play() is triggered -> pumpAndSettle alone
      // cannot observe completion (see settleAsyncChain in helpers/async_settle.dart).
      // Open a real waiting window, then update the tree with pump.
      // Once the error text appears (the real assertion below) exit with a short
      // grace; if it never appears, turns are pumped for up to 10 s and the expect
      // below fails.
      await settleAsyncChain(
        tester,
        until: () => find
            .textContaining('error', findRichText: true)
            .evaluate()
            .isNotEmpty,
      );

      expect(tester.takeException(), isNull);
      // A visible error indicator must show (SnackBar/text/banner) -- the exact text
      // contract is left to the worker; we only look for visible text containing the
      // the word "error", matching the screen's wording.
      expect(
        find.textContaining('error', findRichText: true),
        findsWidgets,
        reason: 'after a generate error, a visible error message is expected',
      );
    });
  });

  group('W6 — t5: second discussion (FAZ2a K10 regression pin)', () {
    testWidgets(
      'when the first discussion ends, a SECOND one runs (a new controller is built)',
      (tester) async {
        final log = <String>[];
        const turnsA = [DiscussionTurn(DiscussionSpeaker.a, 'first turn')];
        const turnsB = [DiscussionTurn(DiscussionSpeaker.b, 'second turn')];
        var callCount = 0;
        DiscussionController factory() {
          callCount++;
          final turns = callCount == 1 ? turnsA : turnsB;
          return fakeControllerFactory(log: log, turns: turns)();
        }

        await tester.pumpWidget(
          _wrapScreen(DiscussionRoomScreen(debugControllerFactory: factory)),
        );
        await pumpSettle(tester);

        await _startDiscussion(tester, topic: 'first topic');
        await pumpSettle(tester);
        expect(find.textContaining('first turn'), findsOneWidget);
        // Wait until the first run() has FULLY finished (the screen going back to
        // _isRunning=false, so the top-bar play IconButton is visible again).
        // See settleAsyncChain (helpers/async_settle.dart): after the last play(),
        // the controller.run() closing itself (subscription/controller close) forces
        // no frame, and pumpAndSettle cannot observe it alone. The exact condition
        // is: the play IconButton has come back.
        await settleAsyncChain(
          tester,
          until: () => find
              .widgetWithIcon(IconButton, Icons.play_arrow)
              .evaluate()
              .isNotEmpty,
        );

        // Start a SECOND discussion on the same screen -- a naive implementation that
        // calls run() again on the same DiscussionController would throw StateError
        // (K10 guard); this test proves it does NOT.
        await _startDiscussion(tester, topic: 'second topic');
        await settleAsyncChain(
          tester,
          until: () => find.textContaining('second turn').evaluate().isNotEmpty,
        );

        expect(tester.takeException(), isNull);
        expect(find.textContaining('second turn'), findsOneWidget);
        expect(log, containsAllInOrder(['G:first topic', 'G:second topic']));
        expect(
          callCount,
          2,
          reason: 'a NEW controller must be built for every run()',
        );
      },
    );
  });

  group('W6 — t6: dead affordance sweep', () {
    testWidgets('no IconButton carries an empty onPressed: () {}', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapScreen(
          DiscussionRoomScreen(
            debugControllerFactory: fakeControllerFactory(
              log: [],
              turns: const [DiscussionTurn(DiscussionSpeaker.a, 'x')],
            ),
          ),
        ),
      );
      await pumpSettle(tester);

      // In the idle state the non-back IconButtons must be exactly {start, list}
      // (if a new control is added, this set test breaks -> it too must be pinned by
      // behavior). Each one is actually tapped and a visible effect is expected:
      // an empty `onPressed: () {}` / null does nothing, so checking only `isNotNull`
      // is not enough -- the behavior itself is proven.
      final icons = tester
          .widgetList<IconButton>(find.byType(IconButton))
          .map((w) => (w.icon as Icon).icon)
          .where((i) => i != Icons.arrow_back)
          .toSet();
      expect(icons, {Icons.play_arrow, Icons.list});

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));

      // Start -> topic dialog (text field + hint text) opens.
      await tester.tap(find.widgetWithIcon(IconButton, Icons.play_arrow));
      await pumpSettle(tester);
      expect(find.byType(TextField), findsOneWidget);
      expect(
        find.text('Write a topic or question from the book...'),
        findsOneWidget,
      );
      navigator.pop();
      await pumpSettle(tester);
      expect(find.byType(TextField), findsNothing);

      // Discussion list -> bottom sheet opens (no turns yet -> empty-state text).
      await tester.tap(find.widgetWithIcon(IconButton, Icons.list));
      await pumpSettle(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('No conversation yet.'), findsOneWidget);
    });
  });

  group('W6 — t7: empty-key guard (real path, no debugControllerFactory)', () {
    testWidgets(
      'with the Gemini/Google key EMPTY, Start -> NO network call is made and a '
      'friendly "API key" warning is shown (extends the PR#32 "do not hit the '
      'network when the key is empty" contract from the reader to the discussion path)',
      (tester) async {
        // Real services with an empty key (ReadingSettings defaults '').
        final services = await buildTestServices();
        expect(
          services.reading.geminiKey,
          isEmpty,
          reason: 'precondition: this test sets up the empty-key scenario',
        );

        await tester.pumpWidget(
          AppServicesScope(
            services: services,
            child: _wrapScreen(const DiscussionRoomScreen()),
          ),
        );
        await pumpSettle(tester);

        await _startDiscussion(tester, topic: 'trial topic');
        await settleAsyncChain(
          tester,
          until: () => find
              .textContaining('API key', findRichText: true)
              .evaluate()
              .isNotEmpty,
        );

        expect(tester.takeException(), isNull);
        expect(
          find.textContaining('API key', findRichText: true),
          findsWidgets,
          reason:
              'with an empty key, starting should show a friendly API-key warning '
              '(not a raw "HTTP 401")',
        );
      },
    );
  });

  group('H-B1 — t7: the avatar light must follow the SPEAKING speaker', () {
    testWidgets(
      'while turn 0 (Ahmet) plays and turn 1 (Emel) is pre-synthesized, the light '
      'must be on Ahmet, NOT on Emel; the pill must also name the correct person (Ahmet)',
      (tester) async {
        final log = <String>[];
        const turns = [
          DiscussionTurn(DiscussionSpeaker.a, 'Ahmet takes the first word.'),
          DiscussionTurn(DiscussionSpeaker.b, 'Emel is next.'),
          DiscussionTurn(DiscussionSpeaker.c, 'Deniz will close.'),
        ];
        // play is BLOCKED at a test-controlled gate: turn 0 stays "playing" pending.
        // The machine fires [PlayTurn(0), SynthesizeTurn(1)] together on
        // TurnSynthesized(0) (pre-synthesis), and the controller runs them without
        // awaiting; so turn 1's synthesis has already started while turn 0's audio
        // is still playing.
        final playGate = Completer<void>();
        DiscussionController factory() => DiscussionController(
          generate: (topic) async => turns,
          synthesize: (turn) async {
            log.add('S:${turn.speaker.name}');
            return Uint8List.fromList(utf8.encode(turn.text));
          },
          play: (mp3) async {
            log.add('P:${utf8.decode(mp3)}');
            await playGate.future;
          },
        );

        await tester.pumpWidget(
          _wrapScreen(DiscussionRoomScreen(debugControllerFactory: factory)),
        );
        await pumpSettle(tester);

        await _startDiscussion(tester, topic: 'pre-synthesis race');
        // The microtask wave runs within a single pump: G -> S:a -> P(turn 0, pending
        // at the gate) -> S:b. Extra pumps only refresh the frame.
        await tester.pump();
        await tester.pump();

        // PRECONDITION (proof the race is really set up): turn 0 has started playing
        // AND turn 1's pre-synthesis has already been requested.
        expect(
          log,
          containsAllInOrder(['S:a', 'P:Ahmet takes the first word.', 'S:b']),
          reason:
              'precondition: while turn 0 plays, turn 1 pre-synthesis must have '
              'started (pre-synthesis race window open)',
        );

        // The pill names the CORRECT person (true today -- regression pin: the fix must
        // not break the pill). DQ-W1: a turn counter was added to the pill
        // ("Ahmet is speaking · 1. turn") -- pinned with textContaining.
        expect(
          find.textContaining('Ahmet is speaking'),
          findsOneWidget,
          reason: 'the pill must name the SPEAKING person (Ahmet)',
        );

        // MAIN CLAIM: the activity light (boxShadow) must be on the SPEAKING person...
        expect(
          _avatarDecoration(tester, 'Ahmet').boxShadow,
          isNotNull,
          reason:
              'speaking person is Ahmet -- the activity light (boxShadow) must be on '
              'him; if the light drifts to the NEXT pre-synthesized speaker the user '
              'would think the wrong face is talking',
        );
        // ...and must NOT be on the next speaker, who is only pre-synthesized.
        expect(
          _avatarDecoration(tester, 'Emel').boxShadow,
          isNull,
          reason:
              'Emel is not speaking yet (only pre-synthesis) -- the light must not be on her',
        );

        // Cleanup: open the gate and let the remaining turns finish (same real waiting
        // window as the t5 closing check).
        playGate.complete();
        await pumpSettle(tester);
        await settleAsyncChain(tester);
        expect(tester.takeException(), isNull);
      },
    );
  });

  // ── PR-Q1: small loading indicator (DESIGN §5) ────────────────────────────
  group('PR-Q1 — t11: pill shows the preparing state during the first generation', () {
    testWidgets(
      'while generate() runs (no play yet) the pill shows the preparing text '
      '"Preparing discussion…", and the early wrong "Ahmet is speaking" is NO LONGER visible',
      (tester) async {
        // generate() is held at a test-controlled gate so the INTERMEDIATE state
        // "generation running but no turn played yet" can be observed with a BOUNDED
        // pump (same technique as the playGate pattern in H-B1).
        final generateGate = Completer<List<DiscussionTurn>>();
        DiscussionController factory() => DiscussionController(
          generate: (topic) async => generateGate.future,
          synthesize: (turn) async =>
              Uint8List.fromList(utf8.encode(turn.text)),
          play: (mp3) async {},
        );

        await tester.pumpWidget(
          _wrapScreen(DiscussionRoomScreen(debugControllerFactory: factory)),
        );
        await pumpSettle(tester);

        await _startDiscussion(tester, topic: 'loading test');
        // generate() has not resolved yet -> no play() was triggered -> the pill must
        // be in the "preparing" INTERMEDIATE state.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));

        expect(
          find.textContaining('Preparing discussion'),
          findsWidgets,
          reason:
              'while the first generation runs, the pill should show a small loading '
              'indicator (spinner + "Preparing discussion…")',
        );
        expect(
          find.text('Ahmet is speaking'),
          findsNothing,
          reason:
              'earlier bug: with no turn played yet the pill said "Ahmet is speaking" '
              '-- it must NOT be visible now (this is the behavior before the fix)',
        );
        expect(
          find.byType(CircularProgressIndicator),
          findsOneWidget,
          reason: '12x12 small spinner expected (does not fill the screen)',
        );

        // Cleanup: open the gate, finish the run.
        generateGate.complete(const [
          DiscussionTurn(DiscussionSpeaker.a, 'arrived'),
        ]);
        await pumpSettle(tester);
        await settleAsyncChain(tester);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group(
    'PR-Q1 — t12: pill shows extra text while a continuation batch is generating',
    () {
      testWidgets('infinite run + continuation batch (continueScript) in progress: the pill gets '
          '" · next part is being prepared" appended', (tester) async {
        final log = <String>[];
        const turns = [
          DiscussionTurn(DiscussionSpeaker.a, 'starter one'),
          DiscussionTurn(DiscussionSpeaker.b, 'starter two'),
          DiscussionTurn(DiscussionSpeaker.c, 'starter three'),
        ];
        // continueScript is held at a test-controlled gate so the INTERMEDIATE state
        // "continuation being generated, not yet arrived" can be observed.
        final continueGate = Completer<List<DiscussionTurn>>();
        var continueCalled = false;
        var continueCalls = 0;
        await tester.pumpWidget(
          _wrapScreen(
            DiscussionRoomScreen(
              debugControllerFactory: () => DiscussionController(
                openEnded: true,
                generate: (topic) async {
                  log.add('G:$topic');
                  return turns;
                },
                continueScript: (topic, recent) async {
                  continueCalls++;
                  if (continueCalls > 1) {
                    // Source exhausted -> ExtensionFailed -> the run ends gracefully
                    // (FINITE) -- every continuation request after the first stops here,
                    // so the test does not run forever.
                    throw StateError('continuation batches exhausted');
                  }
                  continueCalled = true;
                  return continueGate.future;
                },
                synthesize: (turn) async =>
                    Uint8List.fromList(utf8.encode(turn.text)),
                play: (mp3) async {
                  final text = utf8.decode(mp3);
                  log.add('P:$text');
                  await Future<void>.delayed(const Duration(milliseconds: 5));
                },
              ),
            ),
          ),
        );
        await pumpSettle(tester);

        await _startDiscussion(
          tester,
          topic: 'continuation indicator',
          infinite: true,
        );
        // Wait for the 3 starting turns to be called (the low-water trigger starts the
        // continuation request); continueScript stays hanging at the gate.
        await tester.pump(const Duration(milliseconds: 30));
        await tester.pump(const Duration(milliseconds: 30));

        expect(
          continueCalled,
          isTrue,
          reason:
              'precondition: a continuation request must have been triggered',
        );
        expect(
          find.textContaining('next part is being prepared'),
          findsWidgets,
          reason:
              'while the continuation is generated, extra text should show on the pill '
              '(machine/controller unchanged -- only screen state)',
        );

        // Cleanup.
        continueGate.complete(const [
          DiscussionTurn(DiscussionSpeaker.d, 'continuation one'),
        ]);
        await pumpSettle(tester);
        await settleAsyncChain(tester);
        expect(tester.takeException(), isNull);
      });
    },
  );

  // ── PR-Q1: duration-label basis (DESIGN §4) ───────────────────────────────
  // DQ-W1: the old fixed "~2-3 min" opening-batch label was replaced by a "~11 min"
  // label computed for the DEFAULT mode (Medium) in the dialog once the mode picker
  // arrived (discussionModeDurationLabel, pinned in discussion_pace_test.dart).
  group('DQ-W1 — t13: rough duration label in the length-mode dialog', () {
    testWidgets(
      'the start dialog shows a rough duration label for the default (Medium) mode',
      (tester) async {
        await tester.pumpWidget(
          _wrapScreen(
            DiscussionRoomScreen(
              debugControllerFactory: fakeControllerFactory(
                log: [],
                turns: const [DiscussionTurn(DiscussionSpeaker.a, 'x')],
              ),
            ),
          ),
        );
        await pumpSettle(tester);

        await tester.tap(find.widgetWithIcon(IconButton, Icons.play_arrow));
        await pumpSettle(tester);

        expect(
          find.textContaining('~11 min'),
          findsWidgets,
          reason:
              'the start dialog should show a rough duration label for the default '
              'Medium mode (1100 words / 108 words per minute -> ~11 min)',
        );
      },
    );
  });

  // ── DQ-W1: length-mode picker (Short/Medium/Long/Infinite = Kisa/Medium/Long/Endless) ──
  group('DQ-W1 — length-mode picker', () {
    testWidgets(
      'the dialog shows 4 mode options; the "~N min" label changes when the selection changes',
      (tester) async {
        await tester.pumpWidget(
          _wrapScreen(
            DiscussionRoomScreen(
              debugControllerFactory: fakeControllerFactory(
                log: [],
                turns: const [DiscussionTurn(DiscussionSpeaker.a, 'x')],
              ),
            ),
          ),
        );
        await pumpSettle(tester);

        await tester.tap(find.widgetWithIcon(IconButton, Icons.play_arrow));
        await pumpSettle(tester);

        // The 4 mode options must be visible.
        expect(find.text('Short'), findsOneWidget);
        expect(find.text('Medium'), findsOneWidget);
        expect(find.text('Long'), findsOneWidget);
        expect(find.text('Endless'), findsOneWidget);

        // Default (Medium) -> ~11 min.
        expect(find.textContaining('~11 min'), findsWidgets);

        // Choosing Short (Short) should change the label to ~6 min.
        await tester.tap(find.text('Short'));
        await pumpSettle(tester);
        expect(find.textContaining('~6 min'), findsWidgets);

        // Choosing Long (Long) should change the label to ~20 min.
        await tester.tap(find.text('Long'));
        await pumpSettle(tester);
        expect(find.textContaining('~20 min'), findsWidgets);

        // Choosing Endless (Infinite) -> the label must be "Until you stop it"
        // ("until you stop it"); there is no duration.
        await tester.tap(find.text('Endless'));
        await pumpSettle(tester);
        expect(find.textContaining('Until you stop it'), findsWidgets);
      },
    );

    testWidgets(
      'choosing Endless and tapping Start -> runs with the openEnded=true '
      'behavior (a continuation batch is requested)',
      (tester) async {
        final log = <String>[];
        const turns = [
          DiscussionTurn(DiscussionSpeaker.a, 'starter one'),
          DiscussionTurn(DiscussionSpeaker.b, 'starter two'),
          DiscussionTurn(DiscussionSpeaker.c, 'starter three'),
        ];
        await tester.pumpWidget(
          _wrapScreen(
            DiscussionRoomScreen(
              debugControllerFactory: fakeControllerFactory(
                log: log,
                turns: turns,
                openEnded: true,
                continueBatches: const [
                  [DiscussionTurn(DiscussionSpeaker.d, 'continuation one')],
                ],
              ),
            ),
          ),
        );
        await pumpSettle(tester);

        await tester.tap(find.widgetWithIcon(IconButton, Icons.play_arrow));
        await pumpSettle(tester);
        await tester.tap(find.text('Endless'));
        await pumpSettle(tester);
        await tester.enterText(
          find.byType(TextField).first,
          'infinite mode picker',
        );
        await pumpSettle(tester);
        await tester.tap(find.text('Start'));
        await tester.pump();

        await pumpSettle(tester);
        await settleAsyncChain(tester);

        expect(tester.takeException(), isNull);
        expect(
          log.where((e) => e.startsWith('C:')).isNotEmpty,
          isTrue,
          reason:
              'the Endless selector must keep its openEnded=true behavior '
              '(a continuation batch must have been requested)',
        );
      },
    );

    testWidgets(
      'in normal (finite) mode the pill also gets a turn counter (same behavior as infinite mode)',
      (tester) async {
        final log = <String>[];
        const turns = [
          DiscussionTurn(DiscussionSpeaker.a, 'first'),
          DiscussionTurn(DiscussionSpeaker.b, 'second'),
        ];
        await tester.pumpWidget(
          _wrapScreen(
            DiscussionRoomScreen(
              debugControllerFactory: fakeControllerFactory(
                log: log,
                turns: turns,
                playDelay: const Duration(milliseconds: 60),
              ),
            ),
          ),
        );
        await pumpSettle(tester);

        await _startDiscussion(tester, topic: 'turn counter test');
        await tester.pump(const Duration(milliseconds: 20));

        expect(
          find.textContaining('1. turn'),
          findsWidgets,
          reason:
              'in normal (finite) mode the pill should show the turn counter too '
              '(FAZ-3 note: infinite mode showed it, normal mode did not)',
        );

        await tester.pump(const Duration(milliseconds: 200));
      },
    );
  });

  // ── S2: infinite-mode io+UI wiring ────────────────────────────────────────

  group('S2 — t8: infinite-mode selection (DQ-W1: checkbox -> 4-way picker)', () {
    testWidgets(
      'the start dialog shows the "Endless" option; if it is NOT selected (default '
      'Medium), finite behavior is kept (t1 regression)',
      (tester) async {
        final log = <String>[];
        const turns = [
          DiscussionTurn(
            DiscussionSpeaker.a,
            'The first line belongs to Ahmet.',
          ),
          DiscussionTurn(DiscussionSpeaker.b, 'Now Emel steps in.'),
        ];
        await tester.pumpWidget(
          _wrapScreen(
            DiscussionRoomScreen(
              debugControllerFactory: fakeControllerFactory(
                log: log,
                turns: turns,
                continueBatches: const [
                  [DiscussionTurn(DiscussionSpeaker.c, 'should-not-appear')],
                ],
              ),
            ),
          ),
        );
        await pumpSettle(tester);

        // Open the dialog -> the 4-way length-mode picker must be VISIBLE.
        await tester.tap(find.widgetWithIcon(IconButton, Icons.play_arrow));
        await pumpSettle(tester);
        expect(
          find.text('Endless'),
          findsOneWidget,
          reason: 'the Endless mode option must be in the start dialog',
        );
        // Default mode is Medium (NOT Endless) -> duration label ~11 min.
        expect(
          find.textContaining('~11 min'),
          findsWidgets,
          reason:
              'default mode must not be Endless (a finite duration label is shown)',
        );

        // Send WITHOUT selecting Endless -> finite flow (identical to t1).
        await tester.enterText(find.byType(TextField).first, 'time perception');
        await pumpSettle(tester);
        await tester.tap(find.text('Start'));
        await tester.pump();
        await pumpSettle(tester);
        await settleAsyncChain(tester);

        expect(tester.takeException(), isNull);
        // Only the two starting turns played; the continuation batch (C) was NEVER
        // requested.
        expect(log.where((e) => e.startsWith('P:')).toList(), [
          'P:The first line belongs to Ahmet.',
          'P:Now Emel steps in.',
        ]);
        expect(
          log.where((e) => e.startsWith('C:')),
          isEmpty,
          reason:
              'in unmarked finite mode a continuation batch must NEVER be requested',
        );
      },
    );
  });

  group('S2 — t9: infinite-mode continuation chain', () {
    testWidgets(
      'Endless SELECTED -> starting turns + continuation turns play IN ORDER; '
      'when the continuation source runs out the run ends gracefully (FINITE)',
      (tester) async {
        final log = <String>[];
        // 3 starting turns (the low-water trigger kDiscussionLowWater=2 starts the
        // continuation); a single continuation batch is given, then the source runs out.
        const turns = [
          DiscussionTurn(DiscussionSpeaker.a, 'starter one'),
          DiscussionTurn(DiscussionSpeaker.b, 'starter two'),
          DiscussionTurn(DiscussionSpeaker.c, 'starter three'),
        ];
        await tester.pumpWidget(
          _wrapScreen(
            DiscussionRoomScreen(
              debugControllerFactory: fakeControllerFactory(
                log: log,
                turns: turns,
                openEnded: true,
                continueBatches: const [
                  [
                    DiscussionTurn(DiscussionSpeaker.d, 'continuation one'),
                    DiscussionTurn(DiscussionSpeaker.a, 'continuation two'),
                  ],
                ],
              ),
            ),
          ),
        );
        await pumpSettle(tester);

        await _startDiscussion(tester, topic: 'infinite topic', infinite: true);
        // No infinite source (it throws when batches run out) -> the whole chain is finite.
        await pumpSettle(tester);
        await settleAsyncChain(tester);
        await pumpSettle(tester);

        expect(tester.takeException(), isNull);
        // 3 starting turns + the 2 turns of the continuation batch played IN ORDER.
        expect(log.where((e) => e.startsWith('P:')).toList(), [
          'P:starter one',
          'P:starter two',
          'P:starter three',
          'P:continuation one',
          'P:continuation two',
        ]);
        // At least one continuation batch must have been requested (C: logged).
        expect(
          log.where((e) => e.startsWith('C:')).isNotEmpty,
          isTrue,
          reason:
              'in infinite mode at least one continuation batch must have been requested',
        );
      },
    );
  });

  group('S2 — t10: stop during an infinite run', () {
    testWidgets('infinite run + stop -> NO new turn is played after the stop', (
      tester,
    ) async {
      final log = <String>[];
      const turns = [
        DiscussionTurn(DiscussionSpeaker.a, 'first'),
        DiscussionTurn(DiscussionSpeaker.b, 'second'),
        DiscussionTurn(DiscussionSpeaker.c, 'third'),
      ];
      var stopped = false;
      await tester.pumpWidget(
        _wrapScreen(
          DiscussionRoomScreen(
            debugControllerFactory: fakeControllerFactory(
              log: log,
              turns: turns,
              isStopped: () => stopped,
              openEnded: true,
              // Looks infinite but the source is FINITE: only one batch. The real
              // terminator must be the STOP (the test stays finite even if the batch
              // runs out).
              continueBatches: const [
                [DiscussionTurn(DiscussionSpeaker.d, 'continuation-turn')],
              ],
              playDelay: const Duration(milliseconds: 40),
            ),
          ),
        ),
      );
      await pumpSettle(tester);

      await _startDiscussion(tester, topic: 'infinite topic', infinite: true);
      // The first turn starts playing but must not finish.
      await tester.pump(const Duration(milliseconds: 15));
      final playedBeforeStop = log.where((e) => e.startsWith('P:')).length;
      expect(
        playedBeforeStop,
        greaterThanOrEqualTo(1),
        reason:
            'before stopping, at least the first turn must have started playing',
      );

      // Stop.
      stopped = true;
      await tester.tap(find.byKey(const Key('discussion-stop-control')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await settleAsyncChain(tester);

      final playedAfterStop = log.where((e) => e.startsWith('P:')).length;
      expect(
        playedAfterStop,
        playedBeforeStop,
        reason: 'after stop, NO new turn may be played',
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ── DQ-W3: resume-where-you-left-off / new-discussion choice screen ──────
  group('DQ-W3 — resume-where-you-left-off choice screen', () {
    const savedSession = DiscussionSession(
      topic: 'half-finished topic',
      turns: [
        DiscussionTurn(DiscussionSpeaker.a, 'first spoken'),
        DiscussionTurn(DiscussionSpeaker.b, 'second spoken'),
        DiscussionTurn(DiscussionSpeaker.a, 'third -- NOT YET PLAYED'),
      ],
      playedIndex:
          1, // first two turns were already played, the third is pending
      openEnded: false,
      createdAtMs: 1000,
    );

    testWidgets(
      'if a resumable session exists, the "Continue where you left off" / "New '
      'discussion" choice screen is shown, and the normal empty state is NOT shown',
      (tester) async {
        await tester.pumpWidget(
          _wrapScreen(
            DiscussionRoomScreen(
              debugControllerFactory: fakeControllerFactory(
                log: [],
                turns: const [],
              ),
              debugInitialSession: savedSession,
            ),
          ),
        );
        await pumpSettle(tester);

        expect(find.text('Continue where you left off'), findsOneWidget);
        expect(find.text('New discussion'), findsOneWidget);
        expect(
          find.text('Pick a direction or start directly.'),
          findsNothing,
          reason:
              'the normal empty state must NOT be visible before a choice is made',
        );
      },
    );

    testWidgets(
      'if NO resumable session exists (debugInitialSession not given) the choice '
      'screen is never shown -- current behavior unchanged',
      (tester) async {
        await tester.pumpWidget(
          _wrapScreen(
            DiscussionRoomScreen(
              debugControllerFactory: fakeControllerFactory(
                log: [],
                turns: const [DiscussionTurn(DiscussionSpeaker.a, 'x')],
              ),
            ),
          ),
        );
        await pumpSettle(tester);

        expect(find.text('Continue where you left off'), findsNothing);
        expect(find.text('New discussion'), findsNothing);
      },
    );

    testWidgets(
      '"New discussion" -> choice screen disappears, the normal flow (a new topic can '
      'be entered) works',
      (tester) async {
        final log = <String>[];
        await tester.pumpWidget(
          _wrapScreen(
            DiscussionRoomScreen(
              debugControllerFactory: fakeControllerFactory(
                log: log,
                turns: const [
                  DiscussionTurn(DiscussionSpeaker.a, 'turn of the new topic'),
                ],
              ),
              debugInitialSession: savedSession,
            ),
          ),
        );
        await pumpSettle(tester);

        await tester.tap(find.text('New discussion'));
        await pumpSettle(tester);

        expect(find.text('Continue where you left off'), findsNothing);
        expect(
          find.text('Pick a direction or start directly.'),
          findsOneWidget,
          reason: 'after "New discussion" the normal empty state should show',
        );

        await _startDiscussion(tester, topic: 'fresh topic');
        await settleAsyncChain(
          tester,
          until: () => find
              .textContaining('turn of the new topic')
              .evaluate()
              .isNotEmpty,
        );

        expect(tester.takeException(), isNull);
        expect(log, contains('G:fresh topic'));
        expect(find.textContaining('turn of the new topic'), findsOneWidget);
      },
    );

    testWidgets(
      '"Continue where you left off" -> generate is NEVER called, only the REMAINING '
      'turn(s) play in order (already-played turns are NOT played again)',
      (tester) async {
        final log = <String>[];
        await tester.pumpWidget(
          _wrapScreen(
            DiscussionRoomScreen(
              debugControllerFactory: fakeControllerFactory(
                log: log,
                turns:
                    const [], // generate must NOT be called; even if it returned empty, no problem
              ),
              debugInitialSession: savedSession,
            ),
          ),
        );
        await pumpSettle(tester);

        await tester.tap(find.text('Continue where you left off'));
        await tester.pump();
        await settleAsyncChain(tester);

        expect(tester.takeException(), isNull);
        expect(
          log.where((e) => e.startsWith('G:')),
          isEmpty,
          reason: 'resume must NOT call generate() (the script already exists)',
        );
        expect(
          log.where((e) => e.startsWith('S:')).toList(),
          ['S:a:third -- NOT YET PLAYED'],
          reason:
              'only the remaining (not-yet-played) turn must be re-synthesized',
        );
        expect(
          log.where((e) => e.startsWith('P:')).toList(),
          ['P:third -- NOT YET PLAYED'],
          reason:
              'the already-played first two turns must NOT be played AGAIN; only the '
              'remaining turn should play',
        );
        // The previously played turns must also be visible in the list (List sheet).
        expect(find.textContaining('third -- NOT YET PLAYED'), findsOneWidget);
      },
    );

    testWidgets(
      'persistence: each time a turn starts playing, debugOnSessionSaved is '
      'called with a CURRENT DiscussionSession (topic+turns+playedIndex)',
      (tester) async {
        final saved = <DiscussionSession>[];
        final log = <String>[];
        const turns = [
          DiscussionTurn(DiscussionSpeaker.a, 'one'),
          DiscussionTurn(DiscussionSpeaker.b, 'two'),
        ];
        await tester.pumpWidget(
          _wrapScreen(
            DiscussionRoomScreen(
              debugControllerFactory: fakeControllerFactory(
                log: log,
                turns: turns,
              ),
              debugOnSessionSaved: saved.add,
            ),
          ),
        );
        await pumpSettle(tester);

        await _startDiscussion(tester, topic: 'persistence topic');
        await settleAsyncChain(
          tester,
          until: () =>
              saved.isNotEmpty && saved.last.playedIndex == turns.length - 1,
        );

        expect(tester.takeException(), isNull);
        expect(
          saved,
          isNotEmpty,
          reason: 'at least one save must have been triggered',
        );
        final last = saved.last;
        expect(last.topic, 'persistence topic');
        expect(last.turns, turns);
        expect(
          last.playedIndex,
          turns.length - 1,
          reason: 'in the last save BOTH turns must have been played',
        );
      },
    );

    testWidgets(
      'ROOT-CAUSE REGRESSION (adversarial-review Bug#1): isResumable must be '
      'true even when the turn has JUST STARTED -- previously, under the real persist '
      'timing, turns.length always equaled (playedIndex+1) (a mid-state snapshot caught '
      'in the real _persistSession/_onTurnStartingToPlay flow, not a ready fixture)',
      (tester) async {
        final saved = <DiscussionSession>[];
        final log = <String>[];
        const turns = [
          DiscussionTurn(DiscussionSpeaker.a, 'one'),
          DiscussionTurn(DiscussionSpeaker.b, 'two'),
          DiscussionTurn(DiscussionSpeaker.a, 'three'),
        ];
        await tester.pumpWidget(
          _wrapScreen(
            DiscussionRoomScreen(
              debugControllerFactory: fakeControllerFactory(
                log: log,
                turns: turns,
              ),
              debugOnSessionSaved: saved.add,
            ),
          ),
        );
        await pumpSettle(tester);

        await _startDiscussion(tester, topic: 'root-cause topic');
        await settleAsyncChain(tester, until: () => saved.isNotEmpty);

        expect(tester.takeException(), isNull);
        expect(saved, isNotEmpty);
        // FIRST save: taken only when turn 1 has JUST started playing (playedIndex=0) --
        // but in finite mode the FULL script (3 turns) is already known at generate()
        // time (onScriptReady), not only the part synthesized so far.
        final firstSave = saved.first;
        expect(firstSave.playedIndex, 0);
        expect(
          firstSave.turns.length,
          3,
          reason:
              'in finite mode the full script must be known at generate() time -- '
              'not just the number of turns synthesized so far',
        );
        expect(
          isResumable(firstSave),
          isTrue,
          reason:
              'root-cause fix: the script is known and 2 more turns remain to play -> '
              'it must be resumable (in the old code this ALWAYS came out false)',
        );
      },
    );

    testWidgets(
      'ROOT-CAUSE REGRESSION (Round-2 adversarial-review): during resume, _allTurns '
      'must contain the FULL persisted script text (not only the already-played prefix) '
      '-- otherwise as playedIndex grows it passes the turns length, and at the next '
      'decode the session is judged corrupt and is FULLY lost',
      (tester) async {
        final saved = <DiscussionSession>[];
        final log = <String>[];
        const fullSession = DiscussionSession(
          topic: 'ongoing topic',
          turns: [
            DiscussionTurn(DiscussionSpeaker.a, 'one'),
            DiscussionTurn(DiscussionSpeaker.b, 'two'),
            DiscussionTurn(DiscussionSpeaker.a, 'three'),
            DiscussionTurn(DiscussionSpeaker.b, 'four'),
            DiscussionTurn(DiscussionSpeaker.a, 'five'),
          ],
          playedIndex: 1, // first two turns (one, two) were already played
          openEnded: false,
          createdAtMs: 1000,
        );
        await tester.pumpWidget(
          _wrapScreen(
            DiscussionRoomScreen(
              debugControllerFactory: fakeControllerFactory(
                log: log,
                turns: const [],
              ),
              debugInitialSession: fullSession,
              debugOnSessionSaved: saved.add,
            ),
          ),
        );
        await pumpSettle(tester);

        await tester.tap(find.text('Continue where you left off'));
        await tester.pump();
        await settleAsyncChain(tester);

        expect(tester.takeException(), isNull);
        expect(saved, isNotEmpty);
        // On EVERY save playedIndex must be a VALID value inside the range (not exceeding
        // the turns length) -- otherwise the Bug#2 fix would judge this session corrupt
        // at the next decode and reject it entirely (lost).
        for (final s in saved) {
          expect(
            s.playedIndex,
            lessThan(s.turns.length),
            reason:
                'if playedIndex exceeds the turns length, the session is judged corrupt '
                'at the next decode and is FULLY lost',
          );
        }
        // Last save: the script was played to the end (five turns), the FULL script
        // (5 turns) must be kept -- not only the starting prefix.
        final last = saved.last;
        expect(
          last.playedIndex,
          4,
          reason: 'the script must have been played to the end',
        );
        expect(
          last.turns.length,
          5,
          reason:
              'the FULL script must be kept (not only the pre-resume prefix)',
        );
      },
    );
  });

  // ── PR: interactive participation (steer chip/question -> continuation batch injection) ──
  group('PR — interactive steering injection', () {
    testWidgets('tapping a steer chip injects a listener directive (LISTENER DIRECTION '
        'marker) ONLY into the NEXT continuation call; neither the previous '
        'nor the later call is affected', (tester) async {
      const turns = [
        DiscussionTurn(DiscussionSpeaker.a, 'starter one'),
        DiscussionTurn(DiscussionSpeaker.b, 'starter two'),
        DiscussionTurn(DiscussionSpeaker.c, 'starter three'),
      ];
      final topics = <String>[];
      final continueGate = Completer<List<DiscussionTurn>>();
      var continueCalls = 0;

      await tester.pumpWidget(
        _wrapScreen(
          DiscussionRoomScreen(
            debugControllerFactory: () => DiscussionController(
              openEnded: true,
              generate: (topic) async => turns,
              continueScript: (topic, recent) async {
                topics.add(topic);
                continueCalls++;
                if (continueCalls == 1) return continueGate.future;
                if (continueCalls == 2) {
                  return const [
                    DiscussionTurn(DiscussionSpeaker.a, 'continuation two'),
                  ];
                }
                throw StateError('continuation batches exhausted');
              },
              synthesize: (turn) async =>
                  Uint8List.fromList(utf8.encode(turn.text)),
              play: (mp3) async {},
            ),
          ),
        ),
      );
      await pumpSettle(tester);

      await _startDiscussion(tester, topic: 'steering test', infinite: true);
      // The first continuation request is triggered (left hanging at the gate).
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pump(const Duration(milliseconds: 30));

      expect(
        topics,
        hasLength(1),
        reason:
            'precondition: the first continuation request must have been triggered',
      );
      expect(
        topics.first,
        isNot(contains('LISTENER DIRECTION')),
        reason: 'no directive should be injected yet',
      );

      // Tap the steer chip -- it must affect the NEXT call, which has NOT been
      // triggered yet. ensureVisible: the chip may sit below the scroll area in the
      // default test viewport (800x600) -- first make it visible, then tap.
      await tester.ensureVisible(find.text('Go deeper'));
      await pumpSettle(tester);
      await tester.tap(find.text('Go deeper'));
      await tester.pump();

      // Release the first continuation -> the second continuation request is triggered.
      continueGate.complete(const [
        DiscussionTurn(DiscussionSpeaker.d, 'continuation one'),
      ]);
      await pumpSettle(tester);
      await settleAsyncChain(tester);

      expect(tester.takeException(), isNull);
      expect(topics.length, greaterThanOrEqualTo(3));
      expect(
        topics[1],
        contains('LISTENER DIRECTION'),
        reason:
            'the steer chip must inject its directive into the NEXT continuation call',
      );
      // ROOT-CAUSE FIX (device proof 08.07): the text sent to the model is NOW
      // steerDirective (an operational instruction) -- steerCaption is ONLY the UI
      // caption, see the steerDirective doc.
      expect(topics[1], contains(steerDirective(SteerKind.derinles)));
      expect(
        topics[2],
        isNot(contains('LISTENER DIRECTION')),
        reason:
            'the directive is SINGLE-USE -- it must NOT leak into the NEXT call',
      );
    });

    testWidgets(
      'a directive banked in a context where it cannot be consumed does NOT leak into a '
      'FRESH discussion (adversarial-review finding: the new-run reset block clears the directive)',
      (tester) async {
        // Root cause: _pendingListenerDirective was cleared only when a continuation
        // batch closed (_consumePendingDirective). Steer chips render UNCONDITIONALLY
        // when !_showResumeChoice (including idle); in finite mode / after Stop / while
        // idle, a directive banked this way is NEVER consumed, it stays hanging in the
        // field and leaked into the FIRST continuation of the NEXT Endless session --
        // violating the "identical behavior when no directive is given" invariant.
        // This test catches that leak with an idle-banking case (idle == finite ==
        // after-Stop: all are "banking in a context that cannot consume", fixed by the
        // same reset-block code).
        final topics = <String>[];
        await tester.pumpWidget(
          _wrapScreen(
            DiscussionRoomScreen(
              debugControllerFactory: () => DiscussionController(
                openEnded: true,
                generate: (topic) async => const [
                  DiscussionTurn(DiscussionSpeaker.a, 'starter one'),
                  DiscussionTurn(DiscussionSpeaker.b, 'starter two'),
                  DiscussionTurn(DiscussionSpeaker.c, 'starter three'),
                ],
                continueScript: (topic, recent) async {
                  topics.add(topic);
                  throw StateError('continuation batches exhausted');
                },
                synthesize: (turn) async =>
                    Uint8List.fromList(utf8.encode(turn.text)),
                play: (mp3) async {},
              ),
            ),
          ),
        );
        await pumpSettle(tester);

        // While IDLE (before any discussion starts) tap a steer chip: the directive is
        // banked but cannot be consumed (there is no active continuation).
        await tester.ensureVisible(find.text('Go deeper'));
        await pumpSettle(tester);
        await tester.tap(find.text('Go deeper'));
        await tester.pump();

        // Now start a FRESH Infinite discussion.
        await _startDiscussion(tester, topic: 'fresh topic', infinite: true);
        await settleAsyncChain(tester, until: () => topics.isNotEmpty);

        expect(tester.takeException(), isNull);
        expect(
          topics,
          isNotEmpty,
          reason:
              'a fresh Infinite run should have requested at least one continuation',
        );
        expect(
          topics.first,
          isNot(contains('LISTENER DIRECTION')),
          reason:
              'a directive banked in the previous context must NOT leak into the FRESH '
              'session -- when no directive is given, behavior must be identical',
        );
      },
    );
  });
}
