// Oracle RED wiring test (2026-09-30, user spec "closed box" voice
// discussion). Field evidence: device logs (adb dump + logcat).
//
//  B1: when a book was started, only pages whose cache held CLEAN text were
//      sent (`s.1-13, 4 pages, 1910 chars`). K2: if clean text is missing, the
//      PDF's RAW text layer (no LLM/OCR) is used; diagnostics report
//      clean/raw/skipped.
//  B4: in finite mode (Medium), a question asked during playback did not reach
//      the discussion it belonged to; it leaked into the FIRST generation of the
//      NEXT discussion.
//  B5: the "Ask question" control was at the bottom of the scrollable area; it
//      was not visible without scrolling. K5: moved to the fixed control row
//      (☰ / ■).
//
// Harness: discussion_book_source_wiring_test.dart (real CacheStore +
// runAsync loop) + discussion_steer_directive_test.dart (debugControllerFactory).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'helpers/async_settle.dart';
import 'helpers/test_app.dart';

Widget _wrapScreen(Widget child) {
  final settings = AppSettings();
  return AppSettingsScope(
    settings: settings,
    child: MaterialApp(theme: buildAppTheme(settings), home: child),
  );
}

Widget _wrap(AppServices services, Widget child) =>
    AppServicesScope(services: services, child: _wrapScreen(child));

/// A real PDF (syncfusion) with one line of ASCII text per page; the app's raw
/// text extraction (lib/io/pdf_text.dart) reads it.
Future<String> _writePdf(List<String> pages) async {
  final dir = Directory.systemTemp.createTempSync('sesli_kitap_closed_box_');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // best-effort
    }
  });
  final doc = PdfDocument();
  final font = PdfStandardFont(PdfFontFamily.helvetica, 12);
  for (final text in pages) {
    doc.pages.add().graphics.drawString(
      text,
      font,
      bounds: const Rect.fromLTWH(0, 0, 500, 40),
    );
  }
  final bytes = await doc.save();
  doc.dispose();
  final file = File('${dir.path}/book.pdf');
  await file.writeAsBytes(bytes);
  return file.path;
}

Future<void> _seedClean(
  AppServices services,
  String hash,
  int page,
  String t,
) => services.cache.writeText(
  textCacheKey(
    bookHash: hash,
    pageNo: page,
    cleanPromptVersion: cleanPromptVersion,
  ),
  TextEntry(
    raw: t,
    clean: t,
    promptVersion: cleanPromptVersion,
    suspicious: false,
  ),
);

Future<void> _openStartDialog(WidgetTester tester) async {
  await tester.tap(find.widgetWithIcon(IconButton, Icons.play_arrow));
  await tester.pumpAndSettle();
}

Future<void> _askQuestion(WidgetTester tester, String question) async {
  await tester.ensureVisible(find.byKey(const Key('steer-ask-question')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('steer-ask-question')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('ask-question-field')), question);
  await tester.pump();
  await tester.tap(find.text('Send'));
  await tester.pump();
}

void main() {
  testWidgets('B1/K2: book start -> pages with no clean text in the cache are '
      "sent with the PDF's raw text; later pages are not sent; diagnostics "
      'count clean/raw/skipped', (tester) async {
    final pdfPath = await tester.runAsync(
      () => _writePdf([
        'Cover page raw text',
        'Raw page two: the straw man fallacy.',
        'Raw page three: appeal to authority.',
        'FUTURE PAGE the reader has not reached.',
      ]),
    );
    final book = Book(
      id: 'b1',
      title: 'Safsatalar',
      author: 'Madsen',
      chapterLabel: 'Chapter 1',
      progressPercent: 0,
      totalPages: 4,
      coverIndex: 0,
      hash: 'hpdf',
      filePath: pdfPath!,
    );
    final services = await buildTestServices(
      prefsValues: {
        'books_v1': encodeBooks([book]),
        'progress_hpdf': 3,
      },
    );
    await tester.runAsync(
      () => _seedClean(services, 'hpdf', 1, 'Foreword: clean text.'),
    );

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
          DiscussionRoomScreen(
            debugControllerFactory: () => DiscussionController(
              generate: (topic) async {
                topics.add(topic);
                return const [DiscussionTurn(DiscussionSpeaker.a, 'turn')];
              },
              synthesize: (turn) async =>
                  Uint8List.fromList(utf8.encode(turn.text)),
              play: (mp3) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openStartDialog(tester);
      await tester.tap(find.text(book.title));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
      await tester.pump();
      for (var i = 0; i < 400 && topics.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
    } finally {
      debugPrint = originalDebugPrint;
    }

    expect(topics, hasLength(1));
    final topic = topics.single;
    expect(topic, contains('Foreword: clean text.'));
    expect(
      topic,
      isNot(contains('Cover page raw text')),
      reason: 'raw text must NOT be used for a page that has clean text',
    );
    expect(topic, contains('the straw man fallacy'));
    expect(topic, contains('appeal to authority'));
    expect(topic, isNot(contains('FUTURE PAGE')));
    expect(topic, contains('s.1-3'));
    expect(
      logs.where(
        (l) => l.startsWith(
          'discussion book text: s.1-3, 3 pages (clean 1, raw 2, skipped 0)',
        ),
      ),
      hasLength(1),
      reason: 'logs: $logs',
    );
  });

  testWidgets('B4: in finite mode (Medium), a question asked during playback '
      'does NOT leak into the first generation of the NEXT discussion', (
    tester,
  ) async {
    final topics = <String>[];
    var run = 0;
    final firstRunGate = Completer<void>();
    await tester.pumpWidget(
      _wrapScreen(
        DiscussionRoomScreen(
          debugControllerFactory: () {
            run++;
            final thisRun = run;
            return DiscussionController(
              generate: (topic) async {
                topics.add(topic);
                return const [
                  DiscussionTurn(DiscussionSpeaker.a, 'one'),
                  DiscussionTurn(DiscussionSpeaker.b, 'two'),
                ];
              },
              synthesize: (turn) async =>
                  Uint8List.fromList(utf8.encode(turn.text)),
              play: (mp3) async {
                if (thisRun == 1 && utf8.decode(mp3) == 'one') {
                  await firstRunGate.future;
                }
              },
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openStartDialog(tester);
    await tester.enterText(find.byType(TextField).first, 'first topic');
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    await _askQuestion(tester, 'Is my uncle pregnant?');
    firstRunGate.complete();
    await settleAsyncChain(tester);
    await settleAsyncChain(tester);

    await _openStartDialog(tester);
    await tester.enterText(find.byType(TextField).first, 'second topic');
    await tester.tap(find.text('Start'));
    await tester.pump();
    await settleAsyncChain(tester);

    expect(tester.takeException(), isNull);
    expect(topics, hasLength(2));
    expect(topics[1], isNot(contains('Is my uncle pregnant?')));
    expect(topics[1], isNot(contains('LISTENER DIRECTION')));
  });

  testWidgets('B5/K5: "Ask question" is on the fixed control row -- NOT inside '
      'the scrollable area; visible on the phone screen without scrolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final gate = Completer<void>();
    await tester.pumpWidget(
      _wrapScreen(
        DiscussionRoomScreen(
          debugControllerFactory: () => DiscussionController(
            generate: (topic) async => const [
              DiscussionTurn(DiscussionSpeaker.a, 'one'),
            ],
            synthesize: (turn) async =>
                Uint8List.fromList(utf8.encode(turn.text)),
            play: (mp3) => gate.future,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openStartDialog(tester);
    await tester.enterText(find.byType(TextField).first, 'topic');
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    final ask = find.byKey(const Key('steer-ask-question'));
    expect(ask, findsOneWidget);
    expect(
      find.ancestor(of: ask, matching: find.byType(SingleChildScrollView)),
      findsNothing,
      reason: 'must not be inside the scrollable area',
    );
    final stop = find.byKey(const Key('discussion-stop-control'));
    expect(
      tester.getCenter(ask).dy,
      closeTo(tester.getCenter(stop).dy, 60),
      reason: 'same row as ■',
    );
    final rect = tester.getRect(ask);
    expect(rect.bottom, lessThanOrEqualTo(640));
    expect(rect.top, greaterThanOrEqualTo(0));

    gate.complete();
    await settleAsyncChain(tester);
  });
}
