enum SentenceVisualState { narrating, highlighted, plain }

/// highlightedIndexes.contains(index) -> highlighted; index==narratingIndex -> narrating; else plain.
SentenceVisualState visualStateFor({
  required int index,
  required int narratingIndex,
  required Set<int> highlightedIndexes,
}) {
  if (highlightedIndexes.contains(index)) {
    return SentenceVisualState.highlighted;
  }
  if (index == narratingIndex) return SentenceVisualState.narrating;
  return SentenceVisualState.plain;
}
