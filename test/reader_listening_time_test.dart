// T12 RED wiring test (oracle, 2026-10-04). User decision (14:10, option A):
// "Total listening" = the actual played book audio duration; pauses and tab
// switches are not counted; a single total; discussion audio is excluded.
//
// Spec (T12):
//  L1: time spent playing in the reader is ADDED to prefs 'listening_ms'
//      (milliseconds, int) when paused.
//  L2: paused waiting is not counted.
//  L3: multiple play/pause cycles accumulate (the previous total is kept).
//  L4: switching to another tab while playing (the reader is suspended) also
//      writes the accumulated time.
//  R1: the report screen shows the big "Total listening" number from
//      listening_ms (formatDiscussionDuration(listening_ms ~/ 1000) format;
//      125000 ms -> "2 min") and the "Listening time is not tracked yet." note is
//      NOT shown then.
//  R2: if listening_ms is absent, "—" and the note remain (today's view).
// Note: reader time is measured with a Stopwatch; the tests use a Stopwatch
// bound to flutter_test's FAKE clock (readerStopwatchFactory seam) +
// pump(duration), and verify with a lower bound (>= 250 ms).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';

import 'helpers/test_app.dart';
import 'reader_wiring_test.dart'
    show FakePagePipeline, buildReaderTestShell, useFakeClockReaderStopwatch;

const _book = Book(
  id: 'lt-1',
  title: 'Listening Book',
  author: 'T. Test',
  chapterLabel: 'Chapter 1',
  progressPercent: 0,
  totalPages: 5,
  coverIndex: 0,
  hash: 'lthash000001',
  filePath: '/tmp/lt/does-not-matter.pdf',
);

Future<AppServices> _openBook(WidgetTester tester) async {
  useFakeClockReaderStopwatch(tester);
  final svc = await buildTestServices(
    prefsValues: {
      'books_v1': encodeBooks([_book]),
    },
    createdOps: [],
  );
  await tester.pumpWidget(
    buildReaderTestShell(
      services: svc,
      pipelineFactory: (book) =>
          FakePagePipeline(store: svc.cache, bookHash: book.hash),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(_book.title).first);
  await tester.pumpAndSettle();
  return svc;
}

/// The reader's Stopwatch is bound to flutter_test's FAKE clock (see
/// [useFakeClockReaderStopwatch]) -> pump(duration) advances the elapsed time;
/// no real waiting is needed and the measurement is deterministic.
Future<void> _realWait(WidgetTester tester, int ms) async {
  await tester.pump(Duration(milliseconds: ms));
}

Future<void> _play(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.play_arrow).first);
  await tester.pumpAndSettle();
}

Future<void> _pause(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.pause).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('L1+L2+L3: played time accumulates on pause; paused waiting is '
      'not counted; the second cycle is added to the total', (tester) async {
    final svc = await _openBook(tester);
    expect(svc.prefs.getInt('listening_ms'), isNull);

    await _play(tester);
    await _realWait(tester, 300);
    await _pause(tester);
    final first = svc.prefs.getInt('listening_ms');
    expect(first, isNotNull, reason: 'L1: time must be written on pause');
    expect(first, greaterThanOrEqualTo(250));

    await _realWait(tester, 300);
    expect(
      svc.prefs.getInt('listening_ms'),
      first,
      reason: 'L2: paused waiting must not be counted',
    );

    await _play(tester);
    await _realWait(tester, 300);
    await _pause(tester);
    final second = svc.prefs.getInt('listening_ms')!;
    expect(
      second,
      greaterThanOrEqualTo(first! + 250),
      reason: 'L3: the second cycle must be ADDED on top of the previous one',
    );
    expect(
      second,
      lessThan(first + 5000),
      reason:
          'L2: the 300 ms paused time or double counting must not enter the total',
    );
  });

  testWidgets(
    'L4: switching to the Report tab while playing writes the accumulation',
    (tester) async {
      final svc = await _openBook(tester);

      await _play(tester);
      await _realWait(tester, 300);
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();

      expect(svc.prefs.getInt('listening_ms'), greaterThanOrEqualTo(250));
    },
  );

  testWidgets('R1: report "Total listening" is shown from listening_ms', (
    tester,
  ) async {
    final services = await buildTestServices(
      prefsValues: {'listening_ms': 125000},
    );
    await tester.pumpWidget(buildTestAppFromServices(services));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    expect(find.text('2 min'), findsOneWidget);
    expect(find.text('Listening time is not tracked yet.'), findsNothing);
  });

  testWidgets('R2: if listening_ms is absent, the current empty view remains', (
    tester,
  ) async {
    final services = await buildTestServices(prefsValues: {});
    await tester.pumpWidget(buildTestAppFromServices(services));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    expect(find.text('Listening time is not tracked yet.'), findsOneWidget);
  });
}
