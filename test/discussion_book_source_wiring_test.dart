// Oracle RED wiring test (§13.7, 2026-09-28 night): the topic that goes to the FIRST
// generation of a discussion started from a book chip must carry the book text from
// the CACHE, from the START OF THE BOOK up to the reader's position (measurement: only
// "title — chapter" was going, book content 0; S7 user decision 2026-09-28 night: the
// old 20-page look-back limit is removed). The collected range is logged with
// debugPrint (diagnostics; "discussion book text: s.<first>-<last>, <filled pages> pages, ...").
// (2026-09-30 K1: a free topic without a book no longer STARTS -- second test.)
//
// Harness: discussion_location_topic_test.dart (AppServicesScope + seed
// books_v1/progress_<hash>) + discussion_steer_directive_test.dart
// (capturing the topic sent to generate via debugControllerFactory). The cache is the
// REAL CacheStore (temp dir) -- since file I/O does not advance in testWidgets' fake
// clock, it is awaited with tester.runAsync after Start.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/io/cache_store.dart';
import 'package:sesli_kitap/io/llm_cleaner.dart';
import 'package:sesli_kitap/src/cache_keys.dart';
import 'package:sesli_kitap/src/discussion/discussion_controller.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/ui/screens/discussion_room_screen.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';
import 'helpers/test_app.dart';

const Book _book = Book(
  id: 'b1',
  title: 'Rüyaların Yorumu',
  author: 'S. Freud',
  chapterLabel: 'Chapter 2',
  progressPercent: 0,
  totalPages: 300,
  coverIndex: 0,
  hash: 'h1',
);

Widget _wrap(AppServices services, Widget child) {
  final settings = AppSettings();
  return AppServicesScope(
    services: services,
    child: AppSettingsScope(
      settings: settings,
      child: MaterialApp(theme: buildAppTheme(settings), home: child),
    ),
  );
}

Future<void> _seedPage(AppServices services, int page, String clean) =>
    services.cache.writeText(
      textCacheKey(
        bookHash: _book.hash,
        pageNo: page,
        cleanPromptVersion: cleanPromptVersion,
      ),
      TextEntry(
        raw: clean,
        clean: clean,
        promptVersion: cleanPromptVersion,
        suspicious: false,
      ),
    );

DiscussionController Function() _capturing(List<String> topics) =>
    () => DiscussionController(
      generate: (topic) async {
        topics.add(topic);
        return const [DiscussionTurn(DiscussionSpeaker.a, 'first line')];
      },
      synthesize: (turn) async => Uint8List.fromList(utf8.encode(turn.text)),
      play: (mp3) async {},
    );

Future<void> _tapStartAndSettle(
  WidgetTester tester,
  List<String> topics,
) async {
  await tester.tap(find.text('Start'));
  await tester.pump();
  // Cache reads are real file I/O: each I/O step completes in REAL time, and the
  // rest is processed with pump in fake time -- freeze (bounded) until the topic
  // reaches the first generation.
  for (var i = 0; i < 400 && topics.isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'book chip -> Start: the topic going to the first generation carries '
    "the book text FROM THE START OF THE BOOK up to the reader's position, does NOT "
    'carry later pages; the collected range is logged',
    (tester) async {
      final services = await buildTestServices(
        prefsValues: {
          'books_v1': encodeBooks(const [_book]),
          'progress_h1': 101, // reader is on page 101
        },
      );
      await tester.runAsync(() async {
        // User decision 2026-09-28 night: from the START of the book (the old 20-page
        // look-back limit left page 1 out).
        await _seedPage(services, 1, 'Önsöz: tartışma bir sanattır.');
        await _seedPage(
          services,
          100,
          'Irma rüyası hekimin kendini aklama dileğidir.',
        );
        await _seedPage(services, 101, 'Rüya bir dilek doyumudur, der yazar.');
        await _seedPage(
          services,
          102,
          'NEXT PAGE: the reader has not got here.',
        );
      });
      final topics = <String>[];
      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      try {
        await tester.pumpWidget(
          _wrap(
            services,
            DiscussionRoomScreen(debugControllerFactory: _capturing(topics)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithIcon(IconButton, Icons.play_arrow));
        await tester.pumpAndSettle();
        await tester.tap(find.text(_book.title));
        await tester.pumpAndSettle();
        await _tapStartAndSettle(tester, topics);
      } finally {
        debugPrint = originalDebugPrint;
      }

      expect(topics, hasLength(1));
      expect(topics.single, contains('Önsöz: tartışma bir sanattır.'));
      expect(
        topics.single,
        contains('Irma rüyası hekimin kendini aklama dileğidir.'),
      );
      expect(topics.single, contains('Rüya bir dilek doyumudur, der yazar.'));
      expect(topics.single, contains('s.1-101'));
      expect(topics.single, isNot(contains('NEXT PAGE')));
      // Log: range + number of filled pages (cache gap visible: in range s.1-101
      // only 3 pages have text).
      expect(
        logs.where(
          (l) => l.startsWith('discussion book text: s.1-101, 3 pages'),
        ),
        hasLength(1),
      );
    },
  );

  // K1 (oracle decision 2026-09-30, user spec "closed box"): a discussion starts only
  // with a book. If a free topic is typed by hand without a chip and without an open
  // book (field B3: book text was NEVER sent), the discussion does NOT START and an
  // explicit error is shown; the model is never called. (Free topic with an open book:
  // discussion_question_answer_test.dart.)
  testWidgets(
    'K1: no book selected (no chip, no open book), free topic typed -> '
    'the discussion does NOT START, explicit error',
    (tester) async {
      final services = await buildTestServices(
        prefsValues: {
          'books_v1': encodeBooks(const [_book]),
          'progress_h1': 101,
        },
      );
      await tester.runAsync(
        () => _seedPage(services, 101, 'Rüya bir dilek doyumudur, der yazar.'),
      );
      final topics = <String>[];

      await tester.pumpWidget(
        _wrap(
          services,
          DiscussionRoomScreen(debugControllerFactory: _capturing(topics)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.play_arrow));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'sense of time');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(
        topics,
        isEmpty,
        reason: 'a discussion without a book must NOT go to the model',
      );
      expect(
        find.textContaining(
          'Open a book or pick one from the list before starting a discussion',
        ),
        findsOneWidget,
      );
    },
  );
}
