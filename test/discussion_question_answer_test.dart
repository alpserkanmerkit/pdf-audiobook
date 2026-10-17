// Oracle RED wiring test (2026-09-30, user spec "closed box", B3/B4).
//
//  B4/K4: "Ask question" goes to the CURRENT discussion in EVERY mode: when the
//         playing turn ends, a short answer party is inserted BEFORE the next
//         script turn (screen: DiscussionController.ask -> answerQuestion).
//         Answer turns are visible in the transcript (☰); the persistence index
//         (playedIndex) stays tied to the script (answer turns are not added to
//         the script).
//  B3/K1: a topic typed BY HAND while a book is open counts as "topic/question
//         from the book" -- book text is ALWAYS added (field evidence: book text
//         was never sent for hand-typed topics). The answer party is also bound
//         to the same book text.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/io/cache_store.dart';
import 'package:sesli_kitap/io/llm_cleaner.dart';
import 'package:sesli_kitap/src/cache_keys.dart';
import 'package:sesli_kitap/src/discussion/discussion_controller.dart';
import 'package:sesli_kitap/src/discussion/discussion_session.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/ui/screens/discussion_room_screen.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';

import 'helpers/async_settle.dart';
import 'helpers/test_app.dart';

const Book _book = Book(
  id: 'b1',
  title: 'Safsatalar',
  author: 'Madsen',
  chapterLabel: 'Chapter 1',
  progressPercent: 0,
  totalPages: 20,
  coverIndex: 0,
  hash: 'hq',
);

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

Future<void> _ask(WidgetTester tester, String question) async {
  await tester.tap(find.byKey(const Key('steer-ask-question')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('ask-question-field')), question);
  await tester.pump();
  await tester.tap(find.text('Send'));
  await tester.pump();
}

const _script = [
  DiscussionTurn(DiscussionSpeaker.a, 'one'),
  DiscussionTurn(DiscussionSpeaker.b, 'two'),
  DiscussionTurn(DiscussionSpeaker.c, 'three'),
];

void main() {
  for (final infinite in [false, true]) {
    final label = infinite ? 'Endless' : 'Medium (finite)';
    testWidgets(
      'B4/K4 $label: a question asked while turn 0 is playing is answered '
      'BEFORE turn 1; visible in the transcript; persistence index does not shift',
      (tester) async {
        final played = <String>[];
        final questions = <String>[];
        final sessions = <DiscussionSession>[];
        final gate = Completer<void>();
        await tester.pumpWidget(
          _wrapScreen(
            DiscussionRoomScreen(
              debugOnSessionSaved: sessions.add,
              debugControllerFactory: () => DiscussionController(
                openEnded: infinite,
                generate: (topic) async => _script,
                continueScript: infinite
                    ? (topic, recent) async =>
                          throw StateError('no continuation')
                    : null,
                synthesize: (turn) async =>
                    Uint8List.fromList(utf8.encode(turn.text)),
                play: (mp3) async {
                  final text = utf8.decode(mp3);
                  played.add(text);
                  if (text == 'one') await gate.future;
                },
                answerQuestion: (topic, question, recent) async {
                  questions.add(question);
                  return const [
                    DiscussionTurn(DiscussionSpeaker.d, 'answer one'),
                    DiscussionTurn(DiscussionSpeaker.a, 'answer two'),
                  ];
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _start(tester, infinite: infinite);
        await tester.pump(const Duration(milliseconds: 30));
        expect(played, ['one']);

        await _ask(tester, 'What is the coffin about?');
        gate.complete();
        await settleAsyncChain(tester);
        await settleAsyncChain(tester);

        expect(tester.takeException(), isNull);
        expect(questions, ['What is the coffin about?']);
        expect(played, ['one', 'answer one', 'answer two', 'two', 'three']);
        // Persistence: the script has 3 turns; the last played script index is 2.
        expect(sessions.last.turns.map((t) => t.text), ['one', 'two', 'three']);
        expect(sessions.last.playedIndex, 2);

        await tester.tap(find.widgetWithIcon(IconButton, Icons.list));
        await tester.pumpAndSettle();
        expect(find.text('answer one'), findsOneWidget);
        expect(find.text('answer two'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'K4: if the question cannot be accepted (e.g. no answerer), the user '
    'is told explicitly',
    (tester) async {
      final gate = Completer<void>();
      await tester.pumpWidget(
        _wrapScreen(
          DiscussionRoomScreen(
            debugControllerFactory: () => DiscussionController(
              generate: (topic) async => _script,
              synthesize: (turn) async =>
                  Uint8List.fromList(utf8.encode(turn.text)),
              play: (mp3) => gate.future,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _start(tester);
      await tester.pump(const Duration(milliseconds: 30));
      await _ask(tester, 'question');
      await tester.pump();

      expect(find.textContaining('Question could not be sent'), findsOneWidget);
      gate.complete();
      await settleAsyncChain(tester);
      await settleAsyncChain(tester);
    },
  );

  testWidgets(
    'B3/K1: topic typed BY HAND with a book open -> book text is added '
    'to the first generation and to the question answer',
    (tester) async {
      final services = await buildTestServices(
        prefsValues: {
          'books_v1': encodeBooks(const [_book]),
          'progress_hq': 2,
        },
      );
      await tester.runAsync(
        () => services.cache.writeText(
          textCacheKey(
            bookHash: _book.hash,
            pageNo: 2,
            cleanPromptVersion: cleanPromptVersion,
          ),
          const TextEntry(
            raw: 'Coffin analogy text.',
            clean: 'Coffin analogy text.',
            promptVersion: cleanPromptVersion,
            suspicious: false,
          ),
        ),
      );
      final topics = <String>[];
      final answerTopics = <String>[];
      final gate = Completer<void>();
      await tester.pumpWidget(
        AppServicesScope(
          services: services,
          child: _wrapScreen(
            DiscussionRoomScreen(
              book: _book,
              debugControllerFactory: () => DiscussionController(
                generate: (topic) async {
                  topics.add(topic);
                  return _script;
                },
                synthesize: (turn) async =>
                    Uint8List.fromList(utf8.encode(turn.text)),
                play: (mp3) async {
                  if (utf8.decode(mp3) == 'one') await gate.future;
                },
                answerQuestion: (topic, question, recent) async {
                  answerTopics.add(topic);
                  return const [];
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _start(tester, topic: 'perception of time');
      for (var i = 0; i < 400 && topics.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 30));

      expect(topics, hasLength(1));
      expect(topics.single, startsWith('perception of time'));
      expect(topics.single, contains('Coffin analogy text.'));

      await _ask(tester, 'question');
      gate.complete();
      await settleAsyncChain(tester);
      await settleAsyncChain(tester);

      expect(answerTopics, hasLength(1));
      expect(answerTopics.single, contains('Coffin analogy text.'));
    },
  );
}
