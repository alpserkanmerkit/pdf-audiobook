// Slice-3 WIRING test (§13.7 — oracle). Is the report screen wired to the app_shell report tab?
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/chapter_cache.dart';
import 'package:sesli_kitap/src/chapter_map.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/src/review_scheduler.dart';
import 'package:sesli_kitap/src/review_store.dart';
import 'package:sesli_kitap/src/study_questions.dart';
import 'helpers/test_app.dart';

/// W8 test helper: a ReviewBank with 'toplam' (total) questions and the given intervalIndex/dueDay
/// pattern, encoded with encodeReviewBank into a prefs-ready
/// String (used as the value of a `reviewbank_`-prefixed key).
String _bankaJson(List<(int intervalIndex, int dueDay)> desen) {
  final items = <ReviewItem>[
    for (var i = 0; i < desen.length; i++)
      ReviewItem(id: 'q$i', intervalIndex: desen[i].$1, dueDay: desen[i].$2),
  ];
  final questions = List.generate(
    desen.length,
    (i) => StudyQuestion(soru: 'S$i', cevap: 'C$i', tip: QuestionKind.olgusal),
  );
  return encodeReviewBank(ReviewBank(items: items, questions: questions));
}

void main() {
  testWidgets('Weekly summary is visible on the Report tab', (tester) async {
    await tester.pumpWidget(await buildTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    // T13-B1 (user decision 04.10): title "Summary" (counters are all-time).
    expect(find.text('Summary'), findsOneWidget);
    // "6 h 42 min" is split into a big number + small unit (README 6.6); fixed anchor:
    expect(find.text('Total listening'), findsWidgets);
    expect(find.byKey(const Key('tab-report')), findsOneWidget);
  });

  testWidgets(
    'report counters are computed from real data: completed chapters (chapters+'
    'progress) and discussion time (discussion_seconds)',
    (tester) async {
      const book = Book(
        id: 'r1',
        title: 'Report Book',
        author: '',
        chapterLabel: '',
        progressPercent: 0,
        totalPages: 60,
        coverIndex: 0,
        hash: 'rhash1',
        filePath: '/tmp/r.pdf',
      );
      final chapters = encodeChapters(const [
        Chapter(startPage: 1, endPage: 20),
        Chapter(startPage: 21, endPage: 40),
        Chapter(startPage: 41, endPage: 60),
      ]);
      final services = await buildTestServices(
        prefsValues: {
          'books_v1': encodeBooks([book]),
          'chapters_rhash1': chapters,
          'progress_rhash1': 60, // all 3 chapters done (endPage<=60)
          'discussion_seconds': 3660, // -> '1 h 1 min'
        },
      );
      await tester.pumpWidget(buildTestAppFromServices(services));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();

      // Discussion time: unique format, globally verifiable.
      expect(
        find.text('1 h 1 min'),
        findsOneWidget,
        reason: 'discussion_seconds=3660 -> "1 h 1 min"',
      );
      // Completed chapters: the '3' digit in the 'Chapters completed' card (broad find).
      final card = find
          .ancestor(
            of: find.text('Chapters completed'),
            matching: find.byType(Container),
          )
          .first;
      expect(
        find.descendant(of: card, matching: find.text('3')),
        findsOneWidget,
        reason: 'progress=60, 3 chapters -> completed chapters = 3',
      );
    },
  );

  testWidgets(
    'book exists but no chapter completed -> "Chapters completed" shows "—" '
    '(NOT 0; consistent with reading streak/discussion time)',
    (tester) async {
      const book = Book(
        id: 'r2',
        title: 'New Book',
        author: '',
        chapterLabel: '',
        progressPercent: 0,
        totalPages: 60,
        coverIndex: 0,
        hash: 'rhash2',
        filePath: '/tmp/r2.pdf',
      );
      final chapters = encodeChapters(const [
        Chapter(startPage: 1, endPage: 60),
      ]);
      final services = await buildTestServices(
        prefsValues: {
          'books_v1': encodeBooks([book]),
          'chapters_rhash2': chapters,
          'progress_rhash2': 10, // 10 < 60 -> 0 completed
        },
      );
      await tester.pumpWidget(buildTestAppFromServices(services));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();

      final card = find
          .ancestor(
            of: find.text('Chapters completed'),
            matching: find.byType(Container),
          )
          .first;
      expect(
        find.descendant(of: card, matching: find.text('0')),
        findsNothing,
        reason: 'should show — instead of 0 (consistent with other counters)',
      );
      expect(
        find.descendant(of: card, matching: find.text('—')),
        findsOneWidget,
        reason: 'data exists but none completed -> —',
      );
    },
  );

  testWidgets(
    'the dead "Aksam hatirlatmasi" switch\'i is NOT present (onChanged '
    'empty, no notification infrastructure -- dead affordance removed)',
    (tester) async {
      await tester.pumpWidget(await buildTestApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('hatırlat'),
        findsNothing,
        reason: 'fake evening-reminder row (no backend) must be removed',
      );
    },
  );

  group('W8: quiz accuracy aggregation', () {
    testWidgets(
      't1: single reviewbank_ key -> the real computed percentage is shown',
      (tester) async {
        // 4 questions: 2 mastered (intervalIndex==3), 2 not -> mastered/total = %50.
        final json = _bankaJson([(3, -1), (3, -1), (0, 200), (1, 200)]);
        final services = await buildTestServices(
          prefsValues: {'reviewbank_abc123': json},
        );
        await tester.pumpWidget(buildTestAppFromServices(services));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Report'));
        await tester.pumpAndSettle();

        // The old hard-coded '%86' must NOT appear anymore; the real value '%50' must.
        expect(find.text('%86'), findsNothing);
        expect(find.text('%50'), findsOneWidget);
        // Label 'Ogrenilen' (mastery rate = intervalIndex==3); the old misleading
        // 'Quiz dogrulugu' (it was assumed to be session accuracy) was removed.
        expect(find.text('Learned'), findsOneWidget);
        expect(find.text('Quiz doğruluğu'), findsNothing);
      },
    );

    testWidgets(
      't2: two reviewbank_ keys -> statistics are summed across both',
      (tester) async {
        // Bank 1: 4 questions, 1 mastered -> total=4, mastered=1.
        final json1 = _bankaJson([(3, -1), (0, 200), (1, 200), (2, 200)]);
        // Bank 2: 4 questions, 3 mastered -> total=4, mastered=3.
        final json2 = _bankaJson([(3, -1), (3, -1), (3, -1), (0, 200)]);
        // Sum: total=8, mastered=4 -> %50.
        final services = await buildTestServices(
          prefsValues: {'reviewbank_kitap1': json1, 'reviewbank_kitap2': json2},
        );
        await tester.pumpWidget(buildTestAppFromServices(services));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Report'));
        await tester.pumpAndSettle();

        expect(find.text('%50'), findsOneWidget);
      },
    );

    testWidgets('t3: no reviewbank_ key -> neutral placeholder, no crash', (
      tester,
    ) async {
      final services = await buildTestServices();
      await tester.pumpWidget(buildTestAppFromServices(services));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();

      // total==0 -> no division-by-zero crash; a neutral placeholder is shown.
      expect(tester.takeException(), isNull);
      expect(find.text('%86'), findsNothing);
      expect(find.text('—'), findsWidgets);
    });

    testWidgets(
      't4: one key has corrupt JSON, the other is valid -> the valid one is still shown',
      (tester) async {
        // Valid bank: 2 questions, 1 mastered -> total=2, mastered=1 -> %50.
        final gecerli = _bankaJson([(3, -1), (0, 200)]);
        final services = await buildTestServices(
          prefsValues: {
            'reviewbank_bozuk': 'this is not valid JSON {{{',
            'reviewbank_saglam': gecerli,
          },
        );
        await tester.pumpWidget(buildTestAppFromServices(services));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Report'));
        await tester.pumpAndSettle();

        // A corrupt key must not crash the whole report; the healthy bank's stats must show.
        expect(tester.takeException(), isNull);
        expect(find.text('%50'), findsOneWidget);
      },
    );

    testWidgets(
      't5: old fake counters ("12"/"1s 18d"/"9 gün") are no longer shown',
      (tester) async {
        final services = await buildTestServices();
        await tester.pumpWidget(buildTestAppFromServices(services));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Report'));
        await tester.pumpAndSettle();

        // These four values (the "Chapters completed"/"Discussion time"/"Reading streak" cards)
        // were the OLD hard-coded fake numbers (no tracking
        // infrastructure exists anywhere) — this proves they were removed.
        expect(find.text('12'), findsNothing);
        expect(find.text('1s 18d'), findsNothing);
        expect(find.text('9 gün'), findsNothing);
        // The card labels (context) must still be there — only the fake
        // numbers were removed; the cards themselves were not deleted.
        expect(find.text('Chapters completed'), findsOneWidget);
        expect(find.text('Discussion time'), findsOneWidget);
        expect(find.text('Reading streak'), findsOneWidget);
      },
    );

    testWidgets('t6: old hard-coded "this week" counters (date range/duration/'
        'trend/daily chart/most productive day/weekly goal) are no longer shown, '
        'replaced by explicit placeholders (field report: after 02.07.2026 the date '
        'always showed "23-29 Haziran")', (tester) async {
      final services = await buildTestServices();
      await tester.pumpWidget(buildTestAppFromServices(services));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // The old fixed date range (always showed "23-29 Haziran", regardless of today's
      // date) must no longer appear.
      expect(find.text('23 – 29 HAZİRAN'), findsNothing);
      // Old fixed total-listening numbers.
      expect(find.text('↑ %12'), findsNothing);
      expect(find.text('En verimli gün · Cumartesi, 1 sa 35 dk'), findsNothing);
      expect(find.text("8 saatin 6s 42d'si"), findsNothing);
      // Explicit placeholder messages are in place.
      expect(
        find.textContaining('Listening time is not tracked yet'),
        findsWidgets,
      );
      // T13-A1 (user decision 04.10): the weekly goal card is now data-driven;
      // with no reading record it shows "0 / 5 days" (old placeholder removed).
      expect(find.text('0 / 5 days'), findsOneWidget);
    });
  });

  testWidgets(
    'report tab reads counters FRESH from prefs on every visit (in-session '
    'update; const ReportScreen inside IndexedStack was not rebuilt -- '
    'field report: time stayed "—" after a discussion, but after an app relaunch '
    'it showed "1 min")',
    (tester) async {
      final services = await buildTestServices(
        prefsValues: {'discussion_seconds': 60}, // -> '1 min'
      );
      await tester.pumpWidget(buildTestAppFromServices(services));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();
      expect(
        find.text('1 min'),
        findsOneWidget,
        reason: 'first value 60s -> "1 min"',
      );

      // WITHIN a session (without relaunching the app) discussion time grows --
      // typical flow: the user runs a session in the discussion room, then checks Report.
      // discussion_seconds is updated on the same prefs instance.
      await services.prefs.setInt('discussion_seconds', 3660); // -> '1 h 1 min'

      // Switch to another tab and back to Report (a tab switch rebuilds AppShell).
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();

      expect(
        find.text('1 h 1 min'),
        findsOneWidget,
        reason:
            'current prefs (3660) -> "1 h 1 min"; the Report tab reads prefs FRESH on every visit '
            '(not stale)',
      );
      expect(
        find.text('1 min'),
        findsNothing,
        reason: 'the stale "1 min" (60s) value must no longer be shown',
      );
    },
  );
}
