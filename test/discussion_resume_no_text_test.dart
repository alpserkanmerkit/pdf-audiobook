// T11 RED wiring test (oracle, 2026-10-04 night). T10 plan "Out of scope":
// "If the book is found but its text cannot be gathered (no cache/PDF), there is
// no separate warning." A NEW discussion in the same situation fails loudly and
// does not start (K1, kDiscussionNoTextMessage); a RESUME, however, silently
// continues WITHOUT the book text.
//
// Spec (T11):
//  V1: on resume the book IS found but its text cannot be gathered
//      (_gatherBookSource null) -> SnackBar: "Book text could not be read: the discussion continues without the book text."
//      The discussion still continues.
//  V2: if the book is found and its text is gathered, there is NO warning.
//  V3: if the book is not found at all, only the T10 warning ("Book not found: ...")
//      is shown; this warning is NOT shown a second time or in addition.
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

const _noTextWarning =
    'Book text could not be read: the discussion continues without the book text.';
const _noBookWarning =
    'Book not found: the discussion continues without the book text.';

const _script = [
  DiscussionTurn(DiscussionSpeaker.a, 'one'),
  DiscussionTurn(DiscussionSpeaker.b, 'two'),
  DiscussionTurn(DiscussionSpeaker.c, 'three'),
];

Widget _wrapScreen(Widget child) {
  final settings = AppSettings();
  return AppSettingsScope(
    settings: settings,
    child: MaterialApp(theme: buildAppTheme(settings), home: child),
  );
}

/// [_book] is in the library (no file path -> the PDF raw text cannot be read).
/// The reader is on page 2. If [withCachedText] is true, page 2's clean text is
/// in the cache. The saved session is resumed with [bookHash]; it waits while
/// 'two' plays.
Future<Completer<void>> _resumeAndHold(
  WidgetTester tester, {
  required String bookHash,
  required bool withCachedText,
  required List<String> played,
}) async {
  final services = await buildTestServices(
    prefsValues: {
      'books_v1': encodeBooks(const [_book]),
      'progress_hq': 2,
    },
  );
  if (withCachedText) {
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
  }
  final gate = Completer<void>();
  await tester.pumpWidget(
    AppServicesScope(
      services: services,
      child: _wrapScreen(
        DiscussionRoomScreen(
          debugInitialSession: DiscussionSession(
            topic: 'perception of time',
            turns: _script,
            playedIndex: 0,
            openEnded: false,
            createdAtMs: 1,
            bookHash: bookHash,
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
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('resume-discussion')));
  await tester.pump();
  for (var i = 0; i < 400 && played.isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  // SnackBar entry animation.
  await tester.pump(const Duration(milliseconds: 500));
  return gate;
}

Future<void> _finish(WidgetTester tester, Completer<void> gate) async {
  gate.complete();
  for (var i = 0; i < 2; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
  // Finish the leftover SnackBar timers.
  await tester.pump(const Duration(seconds: 10));
  await tester.pump(const Duration(seconds: 10));
}

void main() {
  testWidgets('V1: book found but its text cannot be read -> warning is shown, '
      'the discussion still continues', (tester) async {
    final played = <String>[];
    final gate = await _resumeAndHold(
      tester,
      bookHash: 'hq',
      withCachedText: false,
      played: played,
    );

    expect(played, [
      'two',
    ], reason: 'the discussion must continue despite the warning');
    expect(find.text(_noTextWarning), findsOneWidget);
    expect(find.text(_noBookWarning), findsNothing);

    await _finish(tester, gate);
    expect(tester.takeException(), isNull);
  });

  testWidgets('V2: book found and its text read -> no warning', (tester) async {
    final played = <String>[];
    final gate = await _resumeAndHold(
      tester,
      bookHash: 'hq',
      withCachedText: true,
      played: played,
    );

    expect(played, ['two']);
    expect(find.text(_noTextWarning), findsNothing);
    expect(find.text(_noBookWarning), findsNothing);

    await _finish(tester, gate);
  });

  testWidgets(
    'V3: if the book is not found at all, only the "Book not found" warning is shown',
    (tester) async {
      final played = <String>[];
      final gate = await _resumeAndHold(
        tester,
        bookHash: 'deleted-book',
        withCachedText: false,
        played: played,
      );

      expect(played, ['two']);
      expect(find.text(_noBookWarning), findsOneWidget);
      expect(find.text(_noTextWarning), findsNothing);

      await _finish(tester, gate);
    },
  );
}
