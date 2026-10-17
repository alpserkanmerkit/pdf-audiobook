import 'package:flutter/material.dart';
import 'package:sesli_kitap/src/chapter_cache.dart';
import 'package:sesli_kitap/src/chapter_map.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/src/reading_stats.dart';
import 'package:sesli_kitap/src/review_store.dart';
import 'package:sesli_kitap/src/weekly_report_contract.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key});

  static const String _placeholder = '—';

  String _computeQuizAccuracy(SharedPreferences prefs) {
    var totalItems = 0;
    var totalHakim = 0;
    for (final key in prefs.getKeys()) {
      if (!key.startsWith('reviewbank_')) continue;
      final raw = prefs.getString(key);
      if (raw == null) continue;
      ReviewBank bank;
      try {
        bank = decodeReviewBank(raw);
      } on FormatException {
        continue;
      }
      final stats = computeWeeklyStats(bank, today: 0);
      totalItems += stats.toplam;
      totalHakim += stats.hakim;
    }
    if (totalItems == 0) return _placeholder;
    return '%${(totalHakim / totalItems * 100).round()}';
  }

  /// Completed chapters: DERIVED from each book's `chapters_[hash]` +
  /// `progress_[hash]` data (no new tracking needed -- computed from the existing
  /// data).
  String _completedChapters(SharedPreferences prefs) {
    final raw = prefs.getString('books_v1');
    if (raw == null) return _placeholder;
    // decodeBooks does not throw on corrupt JSON (it returns an empty list), so a
    // try is unnecessary.
    final books = decodeBooks(raw);
    if (books.isEmpty) return _placeholder;
    final data = <({int progress, List<Chapter> chapters})>[];
    for (final b in books) {
      final progress = prefs.getInt('progress_${b.hash}') ?? 0;
      var chapters = const <Chapter>[];
      final chRaw = prefs.getString('chapters_${b.hash}');
      if (chRaw != null) {
        try {
          chapters = decodeChapters(chRaw);
        } on FormatException {
          chapters = const <Chapter>[];
        }
      }
      data.add((progress: progress, chapters: chapters));
    }
    final n = computeCompletedChapters(data);
    // Consistent with the other counters: if there is data but nothing is
    // completed, show '—' (not 0).
    return n == 0 ? _placeholder : n.toString();
  }

  /// Reading streak: reading_days ('yyyy-MM-dd' list; the reader adds today on
  /// every progress save) + the number of consecutive days up to today.
  String _readingStreak(SharedPreferences prefs, DateTime now) {
    final days = (prefs.getStringList('reading_days') ?? const <String>[])
        .toSet();
    if (days.isEmpty) return _placeholder;
    final streak = computeReadingStreak(days, now);
    return streak == 0 ? _placeholder : streak.toString();
  }

  /// Discussion time: discussion_seconds (the discussion room adds the time of
  /// each full run) formatted.
  String _discussionDuration(SharedPreferences prefs) =>
      formatDiscussionDuration(prefs.getInt('discussion_seconds') ?? 0);

  int _weekReadingDays(SharedPreferences prefs, DateTime now) {
    final days = (prefs.getStringList('reading_days') ?? const <String>[])
        .toSet();
    return computeWeekReadingDays(days, now);
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final displayFamily = serifDisplayFamily(AppSettingsScope.of(context));
    final prefs = AppServicesScope.of(context).prefs;
    final quizAccuracy = _computeQuizAccuracy(prefs);
    final completedChapters = _completedChapters(prefs);
    final discussionDuration = _discussionDuration(prefs);
    final readingStreak = _readingStreak(prefs, DateTime.now());
    final weekReadingDays = _weekReadingDays(prefs, DateTime.now());
    final listeningMs = prefs.getInt('listening_ms');
    final hasListening = listeningMs != null && listeningMs > 0;
    final listeningDisplay = hasListening
        ? formatDiscussionDuration(listeningMs ~/ 1000)
        : _placeholder;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(
              'Summary',
              style: TextStyle(
                fontSize: 33,
                fontFamily: displayFamily,
                color: palette.text,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              listeningDisplay,
              style: TextStyle(
                fontSize: 52,
                fontFamily: displayFamily,
                color: palette.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Total listening',
              style: TextStyle(fontSize: 13, color: palette.text2),
            ),
            if (!hasListening) ...[
              const SizedBox(height: 24),
              Text(
                'Listening time is not tracked yet.',
                style: TextStyle(fontSize: 12, color: palette.text3),
              ),
            ],
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: palette.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WEEKLY GOAL',
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.text3,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$weekReadingDays / $kWeeklyReadingGoalDays days',
                    style: TextStyle(fontSize: 14, color: palette.text2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // 2x2 tiles: a fixed aspect ratio (GridView childAspectRatio) left a
            // tile shorter than its content on narrow screens / large text and
            // pushed the Column out (4.7 px at 360 dp). The row height now comes
            // from the content (IntrinsicHeight + stretch); both tiles have the
            // same height.
            _statRow(
              _statCard(palette, displayFamily, quizAccuracy, 'Learned'),
              _statCard(
                palette,
                displayFamily,
                completedChapters,
                'Chapters completed',
              ),
            ),
            const SizedBox(height: 16),
            _statRow(
              _statCard(
                palette,
                displayFamily,
                discussionDuration,
                'Discussion time',
              ),
              _statCard(
                palette,
                displayFamily,
                readingStreak,
                'Reading streak',
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _statRow(Widget left, Widget right) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: 16),
          Expanded(child: right),
        ],
      ),
    );
  }

  Widget _statCard(
    AppPalette palette,
    String displayFamily,
    String rakam,
    String etiket,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            rakam,
            style: TextStyle(
              fontSize: 24,
              fontFamily: displayFamily,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(etiket, style: TextStyle(fontSize: 12, color: palette.text2)),
        ],
      ),
    );
  }
}
