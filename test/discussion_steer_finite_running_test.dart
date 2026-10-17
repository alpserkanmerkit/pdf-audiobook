// Oracle RED wiring test (T7, 2026-10-04 night; bench plan "Out of scope":
// "Chip steering is still ineffective during playback in finite mode").
//
// Defect (traced from the code): in finite mode (Short/Medium/Long) there is no
// continuation party, so a chip pressed while a discussion is PLAYING waits in
// _pendingListenerDirective. It never reaches that discussion, and it also leaks
// into the FIRST generation of the NEXT discussion (_startDiscussion captures the
// pending directive before resetting it).
//
// Spec (T7):
//  S1: finite mode + chip while playing -> ask(steerDirective(kind)) goes to the
//      playing discussion's controller (same path as "Ask a question"): the answer
//      party plays BEFORE the next script line once the current line ends.
//  S2: infinite mode + chip while playing -> behavior UNCHANGED: ask is not called,
//      the directive goes to the topic of the next continuation party.
//  S3: chip while idle -> behavior UNCHANGED (discussion_steer_directive_test).
//  S4: finite mode + chip while playing, if the controller does not accept it (no
//      responder) -> the "directive could not be delivered" message is shown explicitly.
//  S5: a chip pressed while a finite-mode discussion is playing does NOT leak into
//      the next discussion (S1 and S4).
import 'dart:async';
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

Future<void> _start(
  WidgetTester tester, {
  String topic = 'topic',
  bool infinite = false,
}) async {
  await tester.tap(find.widgetWithIcon(IconButton, Icons.play_arrow));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, topic);
  if (infinite) {
    await tester.tap(find.byKey(const Key('discussion-length-mode-sonsuz')));
  }
  await tester.pumpAndSettle();
  await tester.tap(find.text('Start'));
  await tester.pump();
}

/// Presses the chip while playback is in progress. pumpAndSettle is NOT used:
/// the playing line waits on a Completer, so the screen never settles.
Future<void> _tapChipWhilePlaying(WidgetTester tester, SteerKind kind) async {
  final chip = find.text(steerLabelTr(kind));
  await tester.ensureVisible(chip);
  await tester.pump();
  await tester.tap(chip);
  await tester.pump();
}

const _script = [
  DiscussionTurn(DiscussionSpeaker.a, 'one'),
  DiscussionTurn(DiscussionSpeaker.b, 'two'),
  DiscussionTurn(DiscussionSpeaker.c, 'three'),
];

void main() {
  testWidgets(
    'S1+S5: chip pressed during finite-mode playback enters the playing '
    'discussion as an answer party; does not leak into the next discussion',
    (tester) async {
      final played = <String>[];
      final questions = <String>[];
      final topics = <String>[];
      var run = 0;
      final gate = Completer<void>();
      await tester.pumpWidget(
        _wrapScreen(
          DiscussionRoomScreen(
            debugControllerFactory: () {
              run++;
              return DiscussionController(
                generate: (topic) async {
                  topics.add(topic);
                  return _script;
                },
                synthesize: (turn) async =>
                    Uint8List.fromList(utf8.encode(turn.text)),
                play: (mp3) async {
                  final text = utf8.decode(mp3);
                  played.add(text);
                  if (run == 1 && text == 'one') await gate.future;
                },
                answerQuestion: (topic, question, recent) async {
                  questions.add(question);
                  return const [
                    DiscussionTurn(DiscussionSpeaker.d, 'answer one'),
                    DiscussionTurn(DiscussionSpeaker.a, 'answer two'),
                  ];
                },
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _start(tester, topic: 'topic A');
      await tester.pump(const Duration(milliseconds: 30));
      expect(played, ['one']);

      await _tapChipWhilePlaying(tester, SteerKind.derinles);
      gate.complete();
      await settleAsyncChain(tester);
      await settleAsyncChain(tester);

      expect(tester.takeException(), isNull);
      expect(
        questions,
        [steerDirective(SteerKind.derinles)],
        reason:
            'a chip pressed during playback should have gone through the '
            'controller.ask path of the playing discussion with steerDirective '
            '(operational instruction)',
      );
      expect(played, ['one', 'answer one', 'answer two', 'two', 'three']);

      // Second discussion (no chip pressed): the topic sent to the first generation is CLEAN.
      await _start(tester, topic: 'topic B');
      await settleAsyncChain(tester);
      await settleAsyncChain(tester);

      expect(topics, hasLength(2));
      expect(
        topics[1],
        'topic B',
        reason:
            'a chip pressed while the previous (finite) discussion was playing '
            'must not leak into the new discussion',
      );
    },
  );

  testWidgets(
    'S4+S5: in finite mode with no responder, the chip directive is explicitly '
    'reported as undeliverable and does not leak into the next discussion',
    (tester) async {
      final topics = <String>[];
      var run = 0;
      final gate = Completer<void>();
      await tester.pumpWidget(
        _wrapScreen(
          DiscussionRoomScreen(
            debugControllerFactory: () {
              run++;
              return DiscussionController(
                generate: (topic) async {
                  topics.add(topic);
                  return _script;
                },
                synthesize: (turn) async =>
                    Uint8List.fromList(utf8.encode(turn.text)),
                play: (mp3) async {
                  if (run == 1 && utf8.decode(mp3) == 'one') await gate.future;
                },
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _start(tester, topic: 'topic A');
      await tester.pump(const Duration(milliseconds: 30));

      await _tapChipWhilePlaying(tester, SteerKind.ornek);
      expect(
        find.textContaining('Direction could not be sent'),
        findsOneWidget,
      );

      gate.complete();
      await settleAsyncChain(tester);
      await settleAsyncChain(tester);

      await _start(tester, topic: 'topic B');
      await settleAsyncChain(tester);
      await settleAsyncChain(tester);

      expect(topics, hasLength(2));
      expect(topics[1], 'topic B');
    },
  );

  testWidgets(
    'S2 (pinning): chip pressed during infinite-mode playback does NOT go '
    'through the ask path; it enters the topic of the next continuation party',
    (tester) async {
      final questions = <String>[];
      final continueTopics = <String>[];
      final gate = Completer<void>();
      await tester.pumpWidget(
        _wrapScreen(
          DiscussionRoomScreen(
            debugControllerFactory: () => DiscussionController(
              openEnded: true,
              generate: (topic) async => _script,
              continueScript: (topic, recent) async {
                continueTopics.add(topic);
                throw StateError('no continuation');
              },
              synthesize: (turn) async =>
                  Uint8List.fromList(utf8.encode(turn.text)),
              play: (mp3) async {
                if (utf8.decode(mp3) == 'one') await gate.future;
              },
              answerQuestion: (topic, question, recent) async {
                questions.add(question);
                return const [];
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _start(tester, infinite: true);
      await tester.pump(const Duration(milliseconds: 30));

      await _tapChipWhilePlaying(tester, SteerKind.karsilastir);
      gate.complete();
      await settleAsyncChain(tester);
      await settleAsyncChain(tester);

      expect(questions, isEmpty);
      expect(continueTopics, isNotEmpty);
      expect(
        continueTopics.first,
        contains(steerDirective(SteerKind.karsilastir)),
      );
    },
  );
}
