// Package A1 RED test (oracle). lib/ui/screens/discussion_room_screen.dart
// is fixed by the worker. TTS SYNTHESIS RESILIENCE wiring: in
// discussion_machine.dart, a SINGLE TurnFailed during playing/waiting drops the
// WHOLE discussion into the 'failed' phase (red banner; a 300-turn run dies from
// one TTS glitch). The screen layer now wraps synthesis with
// runSynthAttempts/synthAttemptPlan (see lib/src/discussion/tts_synth_policy.dart):
// original -> 1 retry -> fallback. This file ONLY proves the wiring (the screen's
// wrapping behavior); the pure policy itself is already 100% covered in
// test/src/discussion/tts_synth_policy_test.dart.
//
// Harness pattern TAKEN from test/discussion_wiring_test.dart (that file is NEVER
// EDITED -- _wrapScreen/_startDiscussion/settleAsyncChain (helpers/async_settle.dart)
// are small, self-contained copies below).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/discussion/discussion_controller.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';
import 'package:sesli_kitap/ui/screens/discussion_room_screen.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';

import 'helpers/async_settle.dart';

/// See test/discussion_wiring_test.dart _wrapScreen (same pattern, copy --
/// that file is not edited).
Widget _wrapScreen(Widget child) {
  final settings = AppSettings();
  return AppSettingsScope(
    settings: settings,
    child: MaterialApp(theme: buildAppTheme(settings), home: child),
  );
}

/// See test/discussion_wiring_test.dart _startDiscussion (same pattern, a reduced
/// copy without the infinite-mode option -- this file does not need it).
Future<void> _startDiscussion(
  WidgetTester tester, {
  String topic = 'time perception',
}) async {
  await tester.tap(find.widgetWithIcon(IconButton, Icons.play_arrow));
  await tester.pumpAndSettle();
  expect(find.byType(TextField), findsWidgets);
  await tester.enterText(find.byType(TextField).first, topic);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Start'));
  await tester.pump();
}

void main() {
  group('Package A1 -- TTS synthesis resilience (screen wiring)', () {
    testWidgets(
      'first synthesis attempt throws, second succeeds -> discussion does NOT '
      'become FAILED, both turns play in order (retry recovers silently)',
      (tester) async {
        final log = <String>[];
        const turns = [
          DiscussionTurn(DiscussionSpeaker.a, 'first line'),
          DiscussionTurn(DiscussionSpeaker.b, 'second line'),
        ];
        var synthCalls = 0;

        DiscussionController factory() => DiscussionController(
          generate: (topic) async {
            log.add('G:$topic');
            return turns;
          },
          synthesize: (turn) async {
            synthCalls++;
            // Package A1 scenario: the FIRST call of the injected fake synthesis
            // function throws (e.g. a temporary Google TTS glitch) -- the screen's
            // resilience wrapper must SWALLOW it and retry.
            if (synthCalls == 1) {
              throw Exception('temporary tts error');
            }
            log.add('S:${turn.speaker.name}');
            return Uint8List.fromList(utf8.encode(turn.text));
          },
          play: (mp3) async {
            log.add('P:${utf8.decode(mp3)}');
          },
        );

        await tester.pumpWidget(
          _wrapScreen(DiscussionRoomScreen(debugControllerFactory: factory)),
        );
        await tester.pumpAndSettle();

        await _startDiscussion(tester);
        await settleAsyncChain(tester);

        expect(tester.takeException(), isNull);
        // CORE CLAIM: even though the first attempt threw, NO TurnFailed reached
        // discussion_machine.dart -- the screen did NOT drop into the 'failed'
        // phase (no red error banner) AND both turns were played in order.
        expect(
          find.textContaining('error', findRichText: true),
          findsNothing,
          reason:
              'the retry recovered it, so NO visible error message should appear '
              '-- a single TTS glitch must not kill the whole run (VERIFIED PROBLEM)',
        );
        expect(
          log.where((e) => e.startsWith('P:')).toList(),
          ['P:first line', 'P:second line'],
          reason:
              'both turns must have been played (INCLUDING the turn whose first '
              'attempt threw -- the retry must have recovered it)',
        );
        expect(
          synthCalls,
          greaterThanOrEqualTo(2),
          reason:
              'at least one failed first attempt plus one retry is expected',
        );
      },
    );

    testWidgets(
      'HAPPY PATH: if synthesis never throws, behavior is BYTE-IDENTICAL to today '
      '(EXACTLY one synthesis call per turn)',
      (tester) async {
        final log = <String>[];
        const turns = [
          DiscussionTurn(DiscussionSpeaker.a, 'first line'),
          DiscussionTurn(DiscussionSpeaker.b, 'second line'),
        ];
        var synthCalls = 0;

        DiscussionController factory() => DiscussionController(
          generate: (topic) async => turns,
          synthesize: (turn) async {
            synthCalls++;
            log.add('S:${turn.speaker.name}');
            return Uint8List.fromList(utf8.encode(turn.text));
          },
          play: (mp3) async => log.add('P:${utf8.decode(mp3)}'),
        );

        await tester.pumpWidget(
          _wrapScreen(DiscussionRoomScreen(debugControllerFactory: factory)),
        );
        await tester.pumpAndSettle();

        await _startDiscussion(tester);
        await settleAsyncChain(tester);

        expect(tester.takeException(), isNull);
        expect(find.textContaining('error', findRichText: true), findsNothing);
        expect(
          synthCalls,
          2,
          reason:
              'HAPPY PATH: EXACTLY one synthesis call per turn -- the resilience '
              'wrapper must NOT ADD extra calls (byte-identity proof)',
        );
        expect(log.where((e) => e.startsWith('P:')).toList(), [
          'P:first line',
          'P:second line',
        ]);
      },
    );

    testWidgets(
      'if synthesis throws on EVERY attempt (plan exhausted), the discussion '
      'still ends GRACEFULLY with a visible error -- no crash',
      (tester) async {
        const turns = [DiscussionTurn(DiscussionSpeaker.a, 'single line')];
        DiscussionController factory() => DiscussionController(
          generate: (topic) async => turns,
          synthesize: (turn) async => throw Exception('permanent tts error'),
          play: (mp3) async {},
        );

        await tester.pumpWidget(
          _wrapScreen(DiscussionRoomScreen(debugControllerFactory: factory)),
        );
        await tester.pumpAndSettle();

        await _startDiscussion(tester);
        await settleAsyncChain(tester);

        expect(tester.takeException(), isNull);
        expect(
          find.textContaining('error', findRichText: true),
          findsWidgets,
          reason:
              'once the plan is EXHAUSTED (all attempts failed) TurnFailed must '
              'finally fire -> a visible error message is expected (behavior is '
              'deliberately KEPT, only its appearance is delayed)',
        );
      },
    );
  });
}
