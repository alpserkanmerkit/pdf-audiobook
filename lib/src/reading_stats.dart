// PURE layer (gate-tested 100%): counters on the Report screen. NO I/O -- the
// caller (report_screen) supplies the data it decoded from prefs. Three counters:
//  - Completed chapters: DERIVED from chapters_<hash> + progress_<hash> (no new
//    tracking needed).
//  - Reading streak: reading_days (a set of 'yyyy-MM-dd') + computed from today.
//  - Discussion time: discussion_seconds (cumulative), formatted.
import 'package:sesli_kitap/src/chapter_map.dart';

/// In each book, a chapter counts as completed once the reading progress
/// (current page) has REACHED its end page (>= endPage); totals are summed
/// across all books.
int computeCompletedChapters(
  Iterable<({int progress, List<Chapter> chapters})> books,
) {
  var total = 0;
  for (final b in books) {
    for (final c in b.chapters) {
      if (b.progress >= c.endPage) total++;
    }
  }
  return total;
}

/// The day key of a date ('yyyy-MM-dd'). Used in the reading_days record.
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Previous calendar day. Uses calendar arithmetic instead of Duration(days:1)
/// (day 0 -> last day of the previous month) -- IMMUNE to DST/time-zone drift.
DateTime _prevDay(DateTime d) => DateTime(d.year, d.month, d.day - 1);

/// Reading streak: the number of CONSECUTIVE days read, going backward from
/// today (from yesterday if today has not been read). [days] is a set of
/// 'yyyy-MM-dd'; [today] is the current date.
int computeReadingStreak(Set<String> days, DateTime today) {
  final t = DateTime(today.year, today.month, today.day);
  DateTime cursor;
  if (days.contains(dayKey(t))) {
    cursor = t;
  } else {
    final y = _prevDay(t);
    if (days.contains(dayKey(y))) {
      cursor = y;
    } else {
      return 0;
    }
  }
  var streak = 0;
  while (days.contains(dayKey(cursor))) {
    streak++;
    cursor = _prevDay(cursor);
  }
  return streak;
}

/// Converts cumulative discussion seconds into a readable duration. 0/negative -> '—'.
String formatDiscussionDuration(int seconds) {
  if (seconds <= 0) return '—';
  final totalMin = seconds ~/ 60;
  if (totalMin < 1) return '<1 min';
  if (totalMin < 60) return '$totalMin min';
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// Fixed weekly reading goal (in days).
const int kWeeklyReadingGoalDays = 5;

/// In the calendar week starting Monday, returns how many of the days from
/// Monday up to today (today INCLUDED) are in [days].
int computeWeekReadingDays(Set<String> days, DateTime today) {
  var count = 0;
  for (var i = 0; i < today.weekday; i++) {
    final d = DateTime(today.year, today.month, today.day - i);
    if (days.contains(dayKey(d))) {
      count++;
    }
  }
  return count;
}
