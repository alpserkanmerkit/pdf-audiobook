// PURE layer (gate-tested 100%): Quiz content-source decisions. NO I/O -- the
// caller (quiz_screen) supplies the current page and the collected text, and
// these two pure functions DECIDE (same idiom as reading_stats / quiz_generation).
//
// R3 issue: the old collection went FORWARD from page 1, so the quiz ALWAYS
// consisted of the cover/colophon/preface. Fix: collect BACKWARD from the last
// READ page (quizSourcePageOrder), and block generation when the text is too
// short (hasEnoughQuizText).

/// Page order to follow while collecting quiz text: from [currentPage] BACKWARD
/// (`[currentPage, currentPage-1, ..., 1]`). Goal: the quiz is fed from the most
/// recently read pages (not the cover/colophon).
///
/// If [currentPage] < 1, a sensible clamp is applied: it returns at least `[1]`
/// (never an empty list -- the caller can always try at least the first page).
List<int> quizSourcePageOrder({required int currentPage}) {
  final start = currentPage < 1 ? 1 : currentPage;
  return [for (var p = start; p >= 1; p--) p];
}

/// Is the collected quiz text enough to produce meaningful questions? If the
/// trimmed length is below [min] (default 600) characters it is treated as
/// insufficient (prevents generating a quiz from short pieces such as the
/// cover/colophon -- R3 minimum-content guard).
bool hasEnoughQuizText(String text, {int min = 600}) =>
    text.trim().length >= min;
