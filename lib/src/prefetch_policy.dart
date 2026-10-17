List<int> nextPrefetchBlock({
  required int currentPage,
  required int totalPages,
  required Set<int> ready,
  int blockSize = 3,
}) {
  final start = currentPage + 1;
  final end = (currentPage + blockSize < totalPages)
      ? currentPage + blockSize
      : totalPages;
  final result = <int>[];
  for (var page = start; page <= end; page++) {
    if (!ready.contains(page)) {
      result.add(page);
    }
  }
  return result;
}
