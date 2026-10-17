// Per-page audio position: pure parse/serialize + resume rule.
//
// Field finding: the page number (progress_<hash>) was remembered, but the audio
// position INSIDE the page was never saved -- resume always started from the page
// START (after closing and reopening, AND on pause->resume too).
// This layer parses the "page:milliseconds" value stored under the prefs key and
// decides "should we resume now, and from which position".

/// Parsed in-page audio position.
typedef AudioPos = ({int page, Duration pos});

/// Parses the prefs value ("page:milliseconds"). Malformed, missing or negative
/// input -> null (never throws -- the caller stays safe with a null check).
AudioPos? parseAudioPos(String? raw) {
  if (raw == null) return null;
  final parts = raw.split(':');
  if (parts.length != 2) return null;
  final page = int.tryParse(parts[0]);
  final ms = int.tryParse(parts[1]);
  if (page == null || ms == null) return null;
  if (page < 1 || ms < 0) return null;
  return (page: page, pos: Duration(milliseconds: ms));
}

/// Converts an [AudioPos] to the "page:milliseconds" format written to prefs.
/// Round-trips with [parseAudioPos] (guaranteed).
String formatAudioPos({required int page, required Duration pos}) {
  return '$page:${pos.inMilliseconds}';
}

/// Determines the position to resume from; null when resuming should not happen.
///
/// Rules:
///  - If [savedPage] belongs to a different page (the current page has changed) -> null
///    (another page's position is never leaked onto this page).
///  - If [savedPos] is under the threshold (< [threshold], default 3s) -> null
///    (a position right at the page start is effectively "from the start"; resuming
///    gains nothing, so the simpler fallback is used).
///  - Otherwise [savedPos] is returned as-is, unchanged.
Duration? shouldResumeAt({
  required int savedPage,
  required int currentPage,
  required Duration savedPos,
  Duration threshold = const Duration(seconds: 3),
}) {
  if (savedPage != currentPage) return null;
  if (savedPos < threshold) return null;
  return savedPos;
}
