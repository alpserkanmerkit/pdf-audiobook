class ChapterPage {
  const ChapterPage({required this.page, required this.text});

  final int page;
  final String text;
}

class LessonPart {
  const LessonPart({
    required this.index,
    required this.fromPage,
    required this.toPage,
    required this.text,
  });

  final int index;
  final int fromPage;
  final int toPage;
  final String text;
}

class LessonSplitException implements Exception {
  LessonSplitException(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

const int kLessonMinParts = 3;
const int kLessonMaxParts = 5;
const int kLessonTargetChars = 15000;

List<LessonPart> splitChapterIntoLessons(
  List<ChapterPage> pages, {
  int targetChars = kLessonTargetChars,
}) {
  if (pages.isEmpty) {
    throw LessonSplitException('The page list must not be empty.');
  }
  if (targetChars <= 0) {
    throw LessonSplitException(
      'The target character count must be greater than zero.',
    );
  }
  for (var i = 1; i < pages.length; i++) {
    if (pages[i].page <= pages[i - 1].page) {
      throw LessonSplitException('Page numbers must be strictly increasing.');
    }
  }

  final doluPages = pages.where((p) => p.text.trim().isNotEmpty).toList();
  if (doluPages.length < kLessonMinParts) {
    throw LessonSplitException('At least 3 non-empty pages are required.');
  }

  final toplam = pages.fold<int>(0, (sum, p) => sum + p.text.trim().length);
  var n = (toplam / targetChars).ceil();
  if (n < kLessonMinParts) n = kLessonMinParts;
  if (n > kLessonMaxParts) n = kLessonMaxParts;
  if (n > doluPages.length) n = doluPages.length;
  final N = n;

  final cumChars = <int>[];
  var runningChars = 0;
  for (final page in pages) {
    runningChars += page.text.trim().length;
    cumChars.add(runningChars);
  }

  final doluAfter = List<int>.filled(pages.length, 0);
  var runningDolu = 0;
  for (var i = pages.length - 1; i >= 0; i--) {
    doluAfter[i] = runningDolu;
    if (pages[i].text.trim().isNotEmpty) {
      runningDolu++;
    }
  }

  final parts = <LessonPart>[];
  var startIndex = 0;

  for (var k = 1; k < N; k++) {
    final threshold = (k * toplam) / N;

    var maxEndIndex = startIndex;
    for (var i = pages.length - 1; i >= startIndex; i--) {
      if (doluAfter[i] >= N - k) {
        maxEndIndex = i;
        break;
      }
    }

    var endIndex = maxEndIndex;
    var hasDoluInPart = false;
    for (var i = startIndex; i <= maxEndIndex; i++) {
      if (pages[i].text.trim().isNotEmpty) {
        hasDoluInPart = true;
      }
      if (hasDoluInPart && cumChars[i] >= threshold) {
        endIndex = i;
        break;
      }
    }

    final partPages = pages.sublist(startIndex, endIndex + 1);
    final text = partPages
        .map((p) => p.text.trim())
        .where((t) => t.isNotEmpty)
        .join('\n\n');

    parts.add(
      LessonPart(
        index: k - 1,
        fromPage: pages[startIndex].page,
        toPage: pages[endIndex].page,
        text: text,
      ),
    );
    startIndex = endIndex + 1;
  }

  final lastPages = pages.sublist(startIndex);
  final lastText = lastPages
      .map((p) => p.text.trim())
      .where((t) => t.isNotEmpty)
      .join('\n\n');

  parts.add(
    LessonPart(
      index: N - 1,
      fromPage: pages[startIndex].page,
      toPage: pages.last.page,
      text: lastText,
    ),
  );

  return List.unmodifiable(parts);
}
