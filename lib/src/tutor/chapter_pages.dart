// Private lesson: gathers a chapter's page text -- PURE layer (no I/O; page
// readers are injected). Spec: internal design note §7.2.
//
// For each page, the CLEAN text from the cache is used first; if missing, the
// raw PDF text. If neither exists, the page enters the range with empty text
// (the splitter does not add empty pages to the text, but page numbers stay strictly increasing).
import 'package:sesli_kitap/src/chapter_map.dart';
import 'package:sesli_kitap/src/discussion/discussion_book_source.dart'
    show CachedPageReader;
import 'package:sesli_kitap/src/tutor/lesson_split.dart';

/// [gatherChapterPages] sonucu: sayfalar + kaynak dagilimi sayaclari.
class ChapterPagesResult {
  const ChapterPagesResult({
    required this.pages,
    required this.cleanCount,
    required this.rawCount,
    required this.emptyCount,
  });

  final List<ChapterPage> pages;
  final int cleanCount;
  final int rawCount;
  final int emptyCount;
}

/// For every page from [fromPage] to [toPage] (inclusive), in ascending order,
/// calls [readPage] exactly ONCE. If the clean text (trimmed) is empty or null
/// and [readRawPage] is given, the raw reader is called. Invalid range ->
/// [ArgumentError] (no reader is called).
Future<ChapterPagesResult> gatherChapterPages({
  required int fromPage,
  required int toPage,
  required CachedPageReader readPage,
  CachedPageReader? readRawPage,
}) async {
  if (fromPage < 1 || toPage < fromPage) {
    throw ArgumentError('Invalid page range: $fromPage-$toPage');
  }
  final pages = <ChapterPage>[];
  var cleanCount = 0;
  var rawCount = 0;
  var emptyCount = 0;
  for (var p = fromPage; p <= toPage; p++) {
    final clean = (await readPage(p))?.trim() ?? '';
    if (clean.isNotEmpty) {
      pages.add(ChapterPage(page: p, text: clean));
      cleanCount++;
      continue;
    }
    final raw = readRawPage == null ? '' : (await readRawPage(p))?.trim() ?? '';
    if (raw.isNotEmpty) {
      pages.add(ChapterPage(page: p, text: raw));
      rawCount++;
      continue;
    }
    pages.add(ChapterPage(page: p, text: ''));
    emptyCount++;
  }
  return ChapterPagesResult(
    pages: List<ChapterPage>.unmodifiable(pages),
    cleanCount: cleanCount,
    rawCount: rawCount,
    emptyCount: emptyCount,
  );
}

/// One-line field diagnostic: page range, source breakdown, characters.
String describeChapterPages(ChapterPagesResult r) {
  if (r.pages.isEmpty) return 'tutor text: empty';
  final chars = r.pages.fold<int>(0, (sum, p) => sum + p.text.length);
  return 'tutor text: s.${r.pages.first.page}-${r.pages.last.page}, '
      '${r.pages.length} pages (clean ${r.cleanCount}, raw ${r.rawCount}, '
      'empty ${r.emptyCount}), $chars ch';
}

/// Chapter list row text: `<title> (s.<start>-<end>)`; if the title is missing
/// or empty, `Chapter <index+1>`.
String tutorChapterLabel(Chapter chapter, int index) {
  final title = chapter.title?.trim() ?? '';
  final name = title.isEmpty ? 'Chapter ${index + 1}' : title;
  return '$name (s.${chapter.startPage}-${chapter.endPage})';
}
