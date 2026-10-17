// T10 RED wiring test (oracle, 2026-10-04 night). T9 plan "Out of scope":
// "On resume, if the book was deleted from the library, the discussion continues
// without the book; there is no separate warning for the user." The user cannot
// know this: a closed-box discussion silently continues WITHOUT the book text.
//
// Spec (T10):
//  U1: the saved session has a bookHash but the book is not found (not open,
//      not in the library) -> when resume starts, a SnackBar shows this text:
//      "Book not found: the discussion continues without the book text."
//      The discussion still starts (T9 R4 unchanged).
//  U2: if the book is found, there is NO warning.
//  U3: old session (bookHash null) -> NO warning (there was no book info at all;
//      no false alarm).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

const _warning =
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

/// Resumes the saved session with [bookHash]; holds the second line ('two')
/// while it plays and records what was played in [played]. The returned
/// Completer ends the discussion when completed.
Future<Completer<void>> _resumeAndHold(
  WidgetTester tester, {
  required String? bookHash,
  required List<String> played,
}) async {
  final services = await buildTestServices(
    prefsValues: {
      'books_v1': encodeBooks(const [_book]),
      'progress_hq': 2,
    },
  );
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
  // Finish the leftover SnackBar timer.
  await tester.pump(const Duration(seconds: 10));
}

void main() {
  testWidgets(
    'U1: if the saved book is not found, a warning is shown when resume '
    'starts; the discussion still continues',
    (tester) async {
      final played = <String>[];
      final gate = await _resumeAndHold(
        tester,
        bookHash: 'deleted-book',
        played: played,
      );

      expect(played, [
        'two',
      ], reason: 'the discussion must continue despite the warning');
      expect(find.text(_warning), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);

      await _finish(tester, gate);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('U2: if the saved book is found in the library, no warning', (
    tester,
  ) async {
    final played = <String>[];
    final gate = await _resumeAndHold(tester, bookHash: 'hq', played: played);

    expect(played, ['two']);
    expect(find.text(_warning), findsNothing);

    await _finish(tester, gate);
  });

  testWidgets('U3: old session (bookHash null) -> no warning', (tester) async {
    final played = <String>[];
    final gate = await _resumeAndHold(tester, bookHash: null, played: played);

    expect(played, ['two']);
    expect(find.text(_warning), findsNothing);

    await _finish(tester, gate);
  });
}
