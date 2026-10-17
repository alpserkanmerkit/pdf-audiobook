// T9 RED wiring test (oracle, 2026-10-04 night). Work plan "Out of scope":
// "On resume, if the book was deleted from the library, the discussion continues
// without the book; no separate warning for the user." The user cannot know
// this: a closed-box discussion silently continues WITHOUT the book text.
//
// Spec (T9):
//  R1: DiscussionSession optionally carries a bookHash (unit: discussion_session_book_test).
//  R2: persistence writes the run's source book hash (null for a run without a book).
//  R3: resume finds the book matching the saved bookHash (open book or library
//      books_v1) and adds the book text (see _gatherBookSource) to the topic of
//      the continuation batches AND of question answers (same as _startDiscussion).
//  R4: if bookHash is missing or the book is not found, resume continues without
//      the book as before; no error, the topic is passed unchanged.
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

const _pageText = 'Coffin analogy text.';

Widget _wrapScreen(Widget child) {
  final settings = AppSettings();
  return AppSettingsScope(
    settings: settings,
    child: MaterialApp(theme: buildAppTheme(settings), home: child),
  );
}

/// Services where [_book] is in the library, the reader is on page 2, and
/// page 2's clean text is in the cache.
Future<AppServices> _servicesWithBook(WidgetTester tester) async {
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
        raw: _pageText,
        clean: _pageText,
        promptVersion: cleanPromptVersion,
        suspicious: false,
      ),
    ),
  );
  return services;
}

/// Advances the async chain with a real wait window (runAsync) until [done] is
/// true or the turn limit is reached.
Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 400 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
}

Future<void> _tapResume(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('resume-discussion')));
  await tester.pump();
}

const _script = [
  DiscussionTurn(DiscussionSpeaker.a, 'one'),
  DiscussionTurn(DiscussionSpeaker.b, 'two'),
  DiscussionTurn(DiscussionSpeaker.c, 'three'),
];

void main() {
  testWidgets('R2: the saved session of a run started with an open book '
      'carries bookHash', (tester) async {
    final services = await _servicesWithBook(tester);
    final sessions = <DiscussionSession>[];
    await tester.pumpWidget(
      AppServicesScope(
        services: services,
        child: _wrapScreen(
          DiscussionRoomScreen(
            book: _book,
            debugOnSessionSaved: sessions.add,
            debugControllerFactory: () => DiscussionController(
              generate: (topic) async => _script,
              synthesize: (turn) async =>
                  Uint8List.fromList(utf8.encode(turn.text)),
              play: (mp3) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.play_arrow));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'perception of time');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pump();
    await _pumpUntil(tester, () => sessions.isNotEmpty);
    await settleAsyncChain(tester);

    expect(sessions, isNotEmpty);
    expect(sessions.last.bookHash, 'hq');
    expect(
      sessions.last.topic,
      'perception of time',
      reason: 'the topic stays plain',
    );
  });

  testWidgets(
    'R2: the saved session of a run without a book has bookHash null',
    (tester) async {
      final sessions = <DiscussionSession>[];
      await tester.pumpWidget(
        _wrapScreen(
          DiscussionRoomScreen(
            debugOnSessionSaved: sessions.add,
            debugControllerFactory: () => DiscussionController(
              generate: (topic) async => _script,
              synthesize: (turn) async =>
                  Uint8List.fromList(utf8.encode(turn.text)),
              play: (mp3) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.play_arrow));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'topic');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      await settleAsyncChain(tester);

      expect(sessions, isNotEmpty);
      expect(sessions.last.bookHash, isNull);
    },
  );

  testWidgets(
    'R3: when an endless session is resumed, the library book text is '
    'added to the topic of the continuation batch (no open book)',
    (tester) async {
      final services = await _servicesWithBook(tester);
      final continueTopics = <String>[];
      await tester.pumpWidget(
        AppServicesScope(
          services: services,
          child: _wrapScreen(
            DiscussionRoomScreen(
              debugInitialSession: const DiscussionSession(
                topic: 'perception of time',
                turns: _script,
                playedIndex: 2,
                openEnded: true,
                createdAtMs: 1,
                bookHash: 'hq',
              ),
              debugControllerFactory: () => DiscussionController(
                openEnded: true,
                generate: (topic) async => throw StateError('no generate'),
                continueScript: (topic, recent) async {
                  continueTopics.add(topic);
                  throw StateError('no continuation');
                },
                synthesize: (turn) async =>
                    Uint8List.fromList(utf8.encode(turn.text)),
                play: (mp3) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tapResume(tester);
      await _pumpUntil(tester, () => continueTopics.isNotEmpty);
      await settleAsyncChain(tester);

      expect(continueTopics, isNotEmpty);
      expect(continueTopics.first, startsWith('perception of time'));
      expect(continueTopics.first, contains(_pageText));
    },
  );

  testWidgets('R3: during a resumed finite session, the book text is added to '
      'the answer of a question asked', (tester) async {
    final services = await _servicesWithBook(tester);
    final answerTopics = <String>[];
    final played = <String>[];
    final gate = Completer<void>();
    await tester.pumpWidget(
      AppServicesScope(
        services: services,
        child: _wrapScreen(
          DiscussionRoomScreen(
            book: _book,
            debugInitialSession: const DiscussionSession(
              topic: 'perception of time',
              turns: _script,
              playedIndex: 0,
              openEnded: false,
              createdAtMs: 1,
              bookHash: 'hq',
            ),
            debugControllerFactory: () => DiscussionController(
              generate: (topic) async => throw StateError('no generate'),
              synthesize: (turn) async =>
                  Uint8List.fromList(utf8.encode(turn.text)),
              play: (mp3) async {
                final text = utf8.decode(mp3);
                played.add(text);
                if (text == 'two') await gate.future;
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
    await _tapResume(tester);
    await _pumpUntil(tester, () => played.isNotEmpty);
    await tester.pump(const Duration(milliseconds: 30));
    expect(played, ['two']);

    await tester.tap(find.byKey(const Key('steer-ask-question')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('ask-question-field')),
      'question',
    );
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pump();
    gate.complete();
    await settleAsyncChain(tester);
    await settleAsyncChain(tester);

    expect(answerTopics, hasLength(1));
    expect(answerTopics.single, startsWith('perception of time'));
    expect(answerTopics.single, contains(_pageText));
  });

  testWidgets(
    'R4: if the saved bookHash is not in the library, resume continues '
    'without the book, no error',
    (tester) async {
      final services = await _servicesWithBook(tester);
      final continueTopics = <String>[];
      await tester.pumpWidget(
        AppServicesScope(
          services: services,
          child: _wrapScreen(
            DiscussionRoomScreen(
              debugInitialSession: const DiscussionSession(
                topic: 'perception of time',
                turns: _script,
                playedIndex: 2,
                openEnded: true,
                createdAtMs: 1,
                bookHash: 'deleted-book',
              ),
              debugControllerFactory: () => DiscussionController(
                openEnded: true,
                generate: (topic) async => throw StateError('no generate'),
                continueScript: (topic, recent) async {
                  continueTopics.add(topic);
                  throw StateError('no continuation');
                },
                synthesize: (turn) async =>
                    Uint8List.fromList(utf8.encode(turn.text)),
                play: (mp3) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tapResume(tester);
      await _pumpUntil(tester, () => continueTopics.isNotEmpty);
      await settleAsyncChain(tester);

      expect(tester.takeException(), isNull);
      expect(continueTopics, ['perception of time']);
    },
  );
}
