// Chapter map persistence contract (PURE — no IO, gate-tested).
// Why: building the map for a 706-page book (706x headerEntry) locked the main
// thread for ~67s (measured on device: Skipped 23888 frames). Fix: compute it ONCE
// per bookHash, write it as JSON; later launches read it instantly. The shell
// (reader_screen) carries encode/decode + SharedPreferences; the first computation is async-chunked.
import 'dart:convert';

import 'package:sesli_kitap/src/chapter_map.dart';

String encodeChapters(List<Chapter> chapters) {
  return jsonEncode([
    for (final c in chapters)
      {'title': c.title, 'startPage': c.startPage, 'endPage': c.endPage},
  ]);
}

/// Corrupt or incomplete record → FormatException (the shell catches it and rebuilds the map).
List<Chapter> decodeChapters(String raw) {
  final Object decoded;
  try {
    decoded = jsonDecode(raw) as Object;
  } on FormatException {
    throw const FormatException('chapter cache: invalid JSON');
  }
  if (decoded is! List) {
    throw const FormatException('chapter cache: list expected');
  }
  final out = <Chapter>[];
  for (final e in decoded) {
    if (e is! Map || e['startPage'] is! int || e['endPage'] is! int) {
      throw const FormatException('chapter cache: corrupt record');
    }
    final t = e['title'];
    if (t != null && t is! String) {
      throw const FormatException('chapter cache: title type');
    }
    out.add(
      Chapter(
        title: t as String?,
        startPage: e['startPage'] as int,
        endPage: e['endPage'] as int,
      ),
    );
  }
  return List<Chapter>.unmodifiable(out);
}
