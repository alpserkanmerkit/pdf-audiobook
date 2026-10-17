// Oracle (pure-layer gate test): report counters (completed chapters, reading
// streak, discussion time). NO I/O.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/chapter_map.dart';
import 'package:sesli_kitap/src/reading_stats.dart';

void main() {
  group('computeCompletedChapters', () {
    Chapter ch(int start, int end) => Chapter(startPage: start, endPage: end);

    test('a chapter counts once progress REACHES its end page', () {
      final books = [
        (progress: 50, chapters: [ch(1, 20), ch(21, 40), ch(41, 60)]),
      ];
      // 20<=50 and 40<=50 done; 60>50 not done -> 2
      expect(computeCompletedChapters(books), 2);
    });

    test('counts are summed across several books', () {
      final books = [
        (progress: 100, chapters: [ch(1, 50), ch(51, 100)]), // 2
        (progress: 10, chapters: [ch(1, 30)]), // 0
      ];
      expect(computeCompletedChapters(books), 2);
    });

    test('no chapters / empty -> 0', () {
      expect(computeCompletedChapters([]), 0);
      expect(
        computeCompletedChapters([(progress: 5, chapters: <Chapter>[])]),
        0,
      );
    });
  });

  group('computeReadingStreak', () {
    final today = DateTime(2026, 7, 3);

    test('today + two previous days, no gaps -> 3', () {
      final days = {'2026-07-03', '2026-07-02', '2026-07-01'};
      expect(computeReadingStreak(days, today), 3);
    });

    test('not read today but read yesterday -> count from yesterday', () {
      final days = {'2026-07-02', '2026-07-01'};
      expect(computeReadingStreak(days, today), 2);
    });

    test('neither today nor yesterday read -> 0', () {
      final days = {'2026-06-30'};
      expect(computeReadingStreak(days, today), 0);
    });

    test('a gap in the days breaks the streak', () {
      // today + yesterday present, 07-01 missing, 06-30 present -> streak ends at 2
      final days = {'2026-07-03', '2026-07-02', '2026-06-30'};
      expect(computeReadingStreak(days, today), 2);
    });

    test('empty set -> 0', () {
      expect(computeReadingStreak(<String>{}, today), 0);
    });

    test('uninterrupted streak across a month/year boundary', () {
      final days = {'2026-07-01', '2026-06-30', '2026-06-29'};
      expect(computeReadingStreak(days, DateTime(2026, 7)), 3);
    });
  });

  group('dayKey', () {
    test('zero-padded yyyy-MM-dd', () {
      expect(dayKey(DateTime(2026, 3, 5)), '2026-03-05');
      expect(dayKey(DateTime(2026, 12, 25)), '2026-12-25');
    });
  });

  group('formatDiscussionDuration', () {
    test('0/negative -> dash', () {
      expect(formatDiscussionDuration(0), '—');
      expect(formatDiscussionDuration(-5), '—');
    });
    test('under 1 minute -> <1 min', () {
      expect(formatDiscussionDuration(40), '<1 min');
    });
    test('minutes', () {
      expect(formatDiscussionDuration(125), '2 min');
    });
    test('exact hour', () {
      expect(formatDiscussionDuration(3600), '1 h');
    });
    test('hours + minutes', () {
      expect(formatDiscussionDuration(3660 + 540), '1 h 10 min');
    });
  });
}
