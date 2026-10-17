class PageHeaderEntry {
  const PageHeaderEntry({required this.page, this.header});
  final int page;
  final String? header;
}

class Chapter {
  const Chapter({required this.startPage, required this.endPage, this.title});
  final String? title;
  final int startPage;
  final int endPage;
}

List<Chapter> buildChapterMap(List<PageHeaderEntry> entries) {
  if (entries.isEmpty) return const [];

  final chapters = <Chapter>[];
  final n = entries.length;

  Chapter? current;
  String? lastNormalized;
  final pending = <PageHeaderEntry>[];

  for (var i = 0; i < n; i++) {
    final entry = entries[i];
    final header = entry.header?.trim();
    final hasHeader = header != null && header.isNotEmpty;
    final normalized = hasHeader ? _normalize(header) : null;

    if (!hasHeader) {
      pending.add(entry);
      continue;
    }

    if (current == null) {
      // First header (S1): the LAST page of the pending untitled run is chapter 1's
      // untitled opening page (a running head is not printed on a chapter-start page --
      // consistent with the inner boundaries); the earlier ones become front matter.
      // Front matter = only the pages BEFORE chapter 1's real start.
      var start = entry.page;
      if (pending.isNotEmpty) {
        start = pending.last.page;
        if (pending.length > 1) {
          chapters.add(
            Chapter(
              startPage: pending.first.page,
              endPage: pending[pending.length - 2].page,
            ),
          );
        }
        pending.clear();
      }
      current = Chapter(title: header, startPage: start, endPage: entry.page);
      lastNormalized = normalized;
    } else {
      // current is not null, we have a previous header
      if (normalized == lastNormalized) {
        // Same header: pending belongs to current chapter
        current = Chapter(
          title: current.title,
          startPage: current.startPage,
          endPage: entry.page,
        );
      } else {
        // Different header: pending belongs to next chapter (the one about to start)
        chapters.add(current);
        final start = pending.isNotEmpty ? pending.first.page : entry.page;
        current = Chapter(title: header, startPage: start, endPage: entry.page);
        lastNormalized = normalized;
      }
      pending.clear();
    }
  }

  // Handle remaining pending pages at the end
  if (pending.isNotEmpty) {
    if (current == null) {
      chapters.add(
        Chapter(startPage: pending.first.page, endPage: pending.last.page),
      );
    } else {
      current = Chapter(
        title: current.title,
        startPage: current.startPage,
        endPage: pending.last.page,
      );
    }
    pending.clear();
  }

  if (current != null) chapters.add(current);

  return List<Chapter>.unmodifiable(chapters);
}

String _normalize(String s) {
  return s.toLowerCase().split(RegExp(r'\s+')).join(' ');
}
