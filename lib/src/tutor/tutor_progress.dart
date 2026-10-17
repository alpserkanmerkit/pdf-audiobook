import 'dart:convert';

/// Private lesson saved progress (SPEC §7.7): the part where the user stopped
/// in a chapter, and the accumulated notes of completed parts. Stored as JSON
/// in the phone's own memory (shared_preferences).
class TutorProgress {
  const TutorProgress({
    required this.partIndex,
    required this.totalParts,
    required this.correct,
    required this.half,
    required this.wrong,
  });

  /// 0-based index of the part to resume.
  final int partIndex;

  /// Number of parts in the chapter when the record was written (the record is invalid if the split changed).
  final int totalParts;
  final int correct;
  final int half;
  final int wrong;
}

const int _kVersion = 1;

/// Prefs key specific to the book + chapter page range.
String tutorProgressKey({
  required String bookHash,
  required int startPage,
  required int endPage,
}) => 'tutor_progress_v${_kVersion}_${bookHash}_${startPage}_$endPage';

String encodeTutorProgress(TutorProgress p) => jsonEncode({
  'v': _kVersion,
  'part': p.partIndex,
  'total': p.totalParts,
  'dogru': p.correct,
  'yarim': p.half,
  'yanlis': p.wrong,
});

/// Decodes the record. Returns null if there is no record or it is corrupt;
/// it NEVER throws (the caller silently starts from the beginning).
TutorProgress? decodeTutorProgress(String? raw) {
  if (raw == null) return null;
  final Object? parsed;
  try {
    parsed = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (parsed is! Map) return null;
  final fields = [
    parsed['v'],
    parsed['part'],
    parsed['total'],
    parsed['dogru'],
    parsed['yarim'],
    parsed['yanlis'],
  ];
  if (fields.any((f) => f is! int || f < 0)) return null;
  final [version, part, total, correct, half, wrong] = fields.cast<int>();
  if (version != _kVersion || part >= total) return null;
  return TutorProgress(
    partIndex: part,
    totalParts: total,
    correct: correct,
    half: half,
    wrong: wrong,
  );
}
