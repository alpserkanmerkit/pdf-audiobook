class PreprocessResult {
  const PreprocessResult({
    required this.text,
    this.pageNumber,
    this.strippedHeader,
  });
  final String text;
  final int? pageNumber;
  final String? strippedHeader;
}

final RegExp _pagePattern = RegExp(r'^[\s\-—•.]*([0-9]+)[\s\-—•.]*$');

// PDF extraction artifact: font decoding produces a fake '@' (U+0040) ADJACENT
// to Unicode letters (including Turkish letters) (e.g. "zihi@n" -> "zihin").
// Only an '@' adjacent to a letter is removed; a standalone '@' surrounded by
// spaces (a rare legitimate e-mail usage) is KEPT. `unicode: true` -> \p{L}
// covers the letters of all languages.
final RegExp _letterAdjacentAt = RegExp(
  r'(?<=\p{L})@|@(?=\p{L})',
  unicode: true,
);

PreprocessResult stripPageArtifacts(String raw, {String? knownHeader}) {
  if (raw.isEmpty) {
    return const PreprocessResult(text: '');
  }

  // Character-artifact cleanup -- runs BEFORE the line/page-number/header logic
  // so that header matching and page-number detection work on the cleaned text.
  // 1) Soft hyphen (U+00AD): an invisible hyphenation mark -> remove entirely.
  // 2) Fake '@' adjacent to a letter -> remove (do not touch a standalone '@').
  final cleaned = raw.replaceAll('­', '').replaceAll(_letterAdjacentAt, '');

  final lines = cleaned.split('\n');
  int? pageNumber;
  final removeIndices = <int>{};

  // Check first line
  if (lines.isNotEmpty) {
    final trimmedFirst = lines.first.trim();
    final matchFirst = _pagePattern.firstMatch(trimmedFirst);
    if (matchFirst != null) {
      pageNumber = int.parse(matchFirst.group(1)!);
      removeIndices.add(0);
    }
  }

  // Check last line (different from first)
  if (lines.length > 1) {
    final trimmedLast = lines.last.trim();
    final matchLast = _pagePattern.firstMatch(trimmedLast);
    if (matchLast != null) {
      removeIndices.add(lines.length - 1);
      pageNumber ??= int.parse(matchLast.group(1)!);
    }
  }

  // Build remaining lines after page number removal
  final remainingLines = <String>[];
  for (var i = 0; i < lines.length; i++) {
    if (!removeIndices.contains(i)) {
      remainingLines.add(lines[i]);
    }
  }

  // Handle knownHeader
  String? strippedHeader;
  if (knownHeader != null && remainingLines.isNotEmpty) {
    final normalizedKnown = knownHeader.trim().toLowerCase();
    final firstRemainingLine = remainingLines.first;
    final trimmedLine = firstRemainingLine.trim();
    final normalizedLine = trimmedLine.toLowerCase();
    if (normalizedLine == normalizedKnown) {
      strippedHeader = trimmedLine;
      remainingLines.removeAt(0);
    }
  }

  // Strip leading/trailing empty lines using trim on joined string
  final text = remainingLines.join('\n').trim();

  return PreprocessResult(
    text: text,
    pageNumber: pageNumber,
    strippedHeader: strippedHeader,
  );
}
