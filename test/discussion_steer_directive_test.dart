// ROOT-CAUSE FIX test (oracle, device evidence 08.07). User reported:
// in the discussion room it "only seems to be doing Compare". The root cause
// was traced from the code (not guessed), three separate findings:
//
//  1. _pendingListenerDirective was consumed ONLY inside continueScript/myContinue
//     (_consumePendingDirective); myGenerate (the single first generation in
//     finite mode) never called it. canExtend = openEnded && continueScript != null,
//     so in finite mode (Short/Medium/Long -- default "Medium") the continuation
//     party was NEVER triggered -> ANY chip NEVER reached the model. Seeming to
//     "do Compare" was a COINCIDENCE (the 4-opposing-stance format is already
//     comparative by nature).
//     THIS FILE fixes that: _startDiscussion now CAPTURES the pending directive
//     BEFORE the REST call and injects it into the first generation.
//  2. steerCaption (first-person line written for the UI subtitle, e.g.
//     "Going a bit deeper on this point...") was injected straight into the model.
//     It is NOT an operational instruction. The NEW steerDirective
//     (discussion_presenter.dart) separates them: the caption stays in the UI,
//     the directive sends an OPERATIONAL command to the model.
//
//  t1: a chip is pressed while idle, THEN Start -> the topic sent to the first
//      generation contains "LISTENER DIRECTION: <steerDirective>" (NOT steerCaption).
//  t2: Start without pressing any chip -> topic is BYTE-IDENTICAL (no directive).
//  t3: after a chip was pressed and ONE discussion started, a NEW discussion
//      started without a chip keeps its topic CLEAN (single-use, the cross-session
//      leak is gone again).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/discussion/discussion_controller.dart';
import 'package:sesli_kitap/src/discussion/discussion_presenter.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';
import 'package:sesli_kitap/ui/screens/discussion_room_screen.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';

import 'helpers/async_settle.dart';

Widget _wrapScreen(Widget child) {
  final settings = AppSettings();
  return AppSettingsScope(
    settings: settings,
    child: MaterialApp(theme: buildAppTheme(settings), home: child),
  );
}

Future<void> _startDiscussion(
  WidgetTester tester, {
  String topic = 'time perception',
}) async {
  await tester.tap(find.widgetWithIcon(IconButton, Icons.play_arrow));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, topic);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Start'));
  await tester.pump();
}

void main() {
  group(
    'ROOT-CAUSE FIX — steer chip is injected into the first generation (finite mode)',
    () {
      testWidgets(
        'chip pressed while idle, Start -> topic sent to the first generation '
        'contains steerDirective (NOT steerCaption)',
        (tester) async {
          final generatedTopics = <String>[];

          await tester.pumpWidget(
            _wrapScreen(
              DiscussionRoomScreen(
                debugControllerFactory: () => DiscussionController(
                  generate: (topic) async {
                    generatedTopics.add(topic);
                    return const [
                      DiscussionTurn(DiscussionSpeaker.a, 'first line'),
                    ];
                  },
                  synthesize: (turn) async =>
                      Uint8List.fromList(utf8.encode(turn.text)),
                  play: (mp3) async {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Press the chip while IDLE (BEFORE pressing Start).
          await tester.ensureVisible(find.text('Compare'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Compare'));
          await tester.pump();

          await _startDiscussion(tester);
          await tester.pumpAndSettle();

          expect(generatedTopics, hasLength(1));
          expect(
            generatedTopics.single,
            contains('LISTENER DIRECTION:'),
            reason:
                'a chip pressed while idle should have been injected into the '
                'first generation after Start (ROOT-CAUSE FIX)',
          );
          expect(
            generatedTopics.single,
            contains(steerDirective(SteerKind.karsilastir)),
            reason:
                'the injected text must be steerDirective (the OPERATIONAL '
                'instruction sent to the model) -- NOT steerCaption (UI subtitle)',
          );
          expect(
            generatedTopics.single,
            isNot(contains(steerCaption(SteerKind.karsilastir))),
          );
        },
      );

      testWidgets(
        'Start without any chip -> topic stays BYTE-IDENTICAL (no directive)',
        (tester) async {
          final generatedTopics = <String>[];

          await tester.pumpWidget(
            _wrapScreen(
              DiscussionRoomScreen(
                debugControllerFactory: () => DiscussionController(
                  generate: (topic) async {
                    generatedTopics.add(topic);
                    return const [
                      DiscussionTurn(DiscussionSpeaker.a, 'first line'),
                    ];
                  },
                  synthesize: (turn) async =>
                      Uint8List.fromList(utf8.encode(turn.text)),
                  play: (mp3) async {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await _startDiscussion(tester);
          await tester.pumpAndSettle();

          expect(
            generatedTopics,
            ['time perception'],
            reason:
                'if no chip was pressed, the topic must pass through unchanged',
          );
        },
      );

      testWidgets(
        'after a chip is pressed and discussion A starts, discussion B started '
        'without a chip stays CLEAN (single-use, no leak)',
        (tester) async {
          final generatedTopics = <String>[];
          var callCount = 0;

          await tester.pumpWidget(
            _wrapScreen(
              DiscussionRoomScreen(
                debugControllerFactory: () {
                  callCount++;
                  return DiscussionController(
                    generate: (topic) async {
                      generatedTopics.add(topic);
                      return [
                        DiscussionTurn(
                          DiscussionSpeaker.a,
                          callCount == 1 ? 'A line' : 'B line',
                        ),
                      ];
                    },
                    synthesize: (turn) async =>
                        Uint8List.fromList(utf8.encode(turn.text)),
                    play: (mp3) async {},
                  );
                },
              ),
            ),
          );
          await tester.pumpAndSettle();

          await tester.ensureVisible(find.text('Go deeper'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Go deeper'));
          await tester.pump();

          await _startDiscussion(tester, topic: 'topic A');
          await tester.pumpAndSettle();
          // Wait for the FIRST run() to FULLY finish -- same reason as the FAZ2a K10
          // pattern (see the settleAsyncChain (helpers/async_settle.dart) docs): the
          // top-bar play IconButton only reappears once run() has really closed.
          await settleAsyncChain(tester);

          expect(generatedTopics, hasLength(1));
          expect(generatedTopics[0], contains('LISTENER DIRECTION:'));

          // Second discussion (no chip pressed): press Start again on the same screen.
          await _startDiscussion(tester, topic: 'topic B');
          await tester.pumpAndSettle();

          expect(generatedTopics, hasLength(2));
          expect(
            generatedTopics[1],
            'topic B',
            reason:
                'the directive consumed in the previous discussion must not leak '
                'into a NEW discussion (single-use must hold)',
          );
        },
      );
    },
  );
}
