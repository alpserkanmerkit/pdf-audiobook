import 'dart:convert';

import 'package:sesli_kitap/src/review_store.dart';

class WeeklyStats {
  const WeeklyStats({
    required this.toplam,
    required this.hakim,
    required this.devam,
    required this.vadesiGecen,
  });
  final int toplam;
  final int hakim;
  final int devam;
  final int vadesiGecen;
}

WeeklyStats computeWeeklyStats(ReviewBank bank, {required int today}) {
  var hakim = 0;
  var devam = 0;
  var vadesiGecen = 0;
  for (final item in bank.items) {
    if (item.intervalIndex == 3) {
      hakim++;
    } else if (item.intervalIndex > 0 && item.intervalIndex < 3) {
      devam++;
    }
    if (item.intervalIndex != 3 && item.dueDay < today) {
      vadesiGecen++;
    }
  }
  return WeeklyStats(
    toplam: bank.items.length,
    hakim: hakim,
    devam: devam,
    vadesiGecen: vadesiGecen,
  );
}

class WeeklyReport {
  const WeeklyReport({required this.mektup});
  final String mektup;
}

class WeeklyReportParseException implements Exception {
  const WeeklyReportParseException(this.neden);
  final String neden;

  @override
  String toString() => 'WeeklyReportParseException: $neden';
}

WeeklyReport parseWeeklyReportResponse(String raw) {
  if (raw.trim().isEmpty) {
    throw const WeeklyReportParseException('empty response');
  }
  final dynamic parsed;
  try {
    parsed = const JsonDecoder().convert(raw);
  } on FormatException {
    throw const WeeklyReportParseException('invalid JSON');
  }
  if (parsed is! Map<String, dynamic>) {
    throw const WeeklyReportParseException('not a JSON object');
  }
  final mektup = parsed['mektup'];
  if (mektup is! String) {
    throw const WeeklyReportParseException('mektup field is not a string');
  }
  if (mektup.trim().isEmpty) {
    throw const WeeklyReportParseException('mektup field is empty');
  }
  return WeeklyReport(mektup: mektup.trim());
}

String buildWeeklyReportPrompt(WeeklyStats stats) {
  return 'Weekly stats: Total ${stats.toplam}, '
      'Mastered ${stats.hakim}, In progress ${stats.devam}, '
      'Overdue ${stats.vadesiGecen}. '
      'Based on these stats, write a weekly progress letter in Turkish. '
      'Respond ONLY with JSON in the format {"mektup": "..."}.';
}
