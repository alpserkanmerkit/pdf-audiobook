// T13 A1 + B1 RED wiring test (oracle, 2026-10-04; user decision).
//  A1: the "WEEKLY GOAL" (weekly goal) card shows days read this week vs a fixed 5-day
//      goal: "<n> / 5 days"; the old "no tracking data yet" text is removed.
//      (the '0 / 5 gun' empty-state test was removed: report_wiring_test.dart:302 asserts
//      the same claim; the 'Henuz izleme verisi yok' text no longer exists in lib.)
//  B1: report title "Summary" replaces "Bu Hafta" (counters are all-time totals;
//      the week-range line ("29 – 5 Ekim"-style) is removed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/reading_stats.dart';

import 'helpers/test_app.dart';

Future<void> _openReport(WidgetTester tester, Map<String, Object> prefs) async {
  final services = await buildTestServices(prefsValues: prefs);
  await tester.pumpWidget(buildTestAppFromServices(services));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Report'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('A1: if read today, the goal card shows "1 / 5 days"', (
    tester,
  ) async {
    await _openReport(tester, {
      'reading_days': [dayKey(DateTime.now())],
    });

    expect(find.text('1 / 5 days'), findsOneWidget);
    expect(find.text('Henüz izleme verisi yok'), findsNothing);
  });

  testWidgets(
    'B1: title is "Summary"; "Bu Hafta" and the week-range line are absent',
    (tester) async {
      await _openReport(tester, {});

      expect(find.text('Summary'), findsOneWidget);
      expect(find.text('Bu Hafta'), findsNothing);
      final weekRange = RegExp(r'^\d{1,2}( \S+)? – \d{1,2} \S+$');
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && w.data != null && weekRange.hasMatch(w.data!),
        ),
        findsNothing,
        reason: 'B1: the week-range line must be removed',
      );
    },
  );
}
