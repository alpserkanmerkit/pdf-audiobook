// T13-A1 RED test (oracle, 2026-10-04; user decision A1). Pure layer:
// days read this week (calendar week starting Monday, INCLUDING today)
// + fixed weekly goal (5 days). Data: 'reading_days' ('yyyy-MM-dd').
// NO I/O.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/reading_stats.dart';

void main() {
  group('computeWeekReadingDays', () {
    test('weekly goal constant is 5 days', () {
      expect(kWeeklyReadingGoalDays, 5);
    });

    test(
      'Monday + Wednesday read, last Sunday not counted (today is Thursday)',
      () {
        final days = {'2026-10-05', '2026-10-07', '2026-10-04'};
        expect(computeWeekReadingDays(days, DateTime(2026, 10, 8, 15, 30)), 2);
      },
    );

    test('the day AFTER today (future) is not counted', () {
      final days = {'2026-10-05', '2026-10-09'};
      expect(computeWeekReadingDays(days, DateTime(2026, 10, 8)), 1);
    });

    test('today is Monday: only today counts, previous Sunday does not', () {
      final days = {'2026-10-05', '2026-10-04', '2026-09-30'};
      expect(computeWeekReadingDays(days, DateTime(2026, 10, 5, 0, 1)), 1);
    });

    test('today is Sunday: all 7 days Monday..Sunday count', () {
      final days = {
        '2026-09-28',
        '2026-09-29',
        '2026-09-30',
        '2026-10-01',
        '2026-10-02',
        '2026-10-03',
        '2026-10-04',
      };
      expect(computeWeekReadingDays(days, DateTime(2026, 10, 4, 23, 59)), 7);
    });

    test('week across a month boundary: Sept Monday + Oct Thursday', () {
      final days = {'2026-09-28', '2026-10-01'};
      expect(computeWeekReadingDays(days, DateTime(2026, 10)), 2);
    });

    test('empty set -> 0', () {
      expect(computeWeekReadingDays(<String>{}, DateTime(2026, 10, 8)), 0);
    });
  });
}
