class ReviewItem {
  const ReviewItem({
    required this.id,
    required this.intervalIndex,
    required this.dueDay,
  });
  final String id;
  final int intervalIndex;
  final int dueDay;
}

ReviewItem planNewItem(String id, int today) {
  return ReviewItem(id: id, intervalIndex: 0, dueDay: today + 1);
}

ReviewItem applyAnswer(
  ReviewItem item, {
  required bool knewIt,
  required int today,
}) {
  // K7 defense: 3 = retired; 4+ (may leak from an old or corrupt record) is also
  // swallowed like retired -- an intervals[] overflow (RangeError) is structurally closed.
  if (item.intervalIndex >= 3) {
    return item;
  }
  if (knewIt) {
    final newIndex = item.intervalIndex + 1;
    if (newIndex == 3) {
      return ReviewItem(id: item.id, intervalIndex: 3, dueDay: -1);
    }
    const intervals = [1, 3, 7];
    return ReviewItem(
      id: item.id,
      intervalIndex: newIndex,
      dueDay: today + intervals[newIndex],
    );
  } else {
    return ReviewItem(id: item.id, intervalIndex: 0, dueDay: today + 1);
  }
}

List<ReviewItem> dueItems(List<ReviewItem> items, int today) {
  final filtered =
      items
          .where((item) => item.intervalIndex != 3 && item.dueDay <= today)
          .toList()
        ..sort((a, b) {
          final dueCmp = a.dueDay.compareTo(b.dueDay);
          if (dueCmp != 0) return dueCmp;
          return a.id.compareTo(b.id);
        });
  return List.unmodifiable(filtered);
}

enum ReviewPhase { idle, asking, revealed, done }

class ReviewSessionState {
  const ReviewSessionState({
    required this.phase,
    required this.remaining,
    required this.knownCount,
    required this.unknownCount,
    this.current,
  });

  ReviewSessionState.initial()
    : phase = ReviewPhase.idle,
      remaining = const [],
      current = null,
      knownCount = 0,
      unknownCount = 0;
  final ReviewPhase phase;
  final List<String> remaining;
  final String? current;
  final int knownCount;
  final int unknownCount;
}

sealed class ReviewEvent {
  const ReviewEvent();
}

class SessionStarted extends ReviewEvent {
  const SessionStarted(this.ids);
  final List<String> ids;
}

class RevealRequested extends ReviewEvent {
  const RevealRequested();
}

class Marked extends ReviewEvent {
  const Marked({required this.knewIt});
  final bool knewIt;
}

class SessionCancelled extends ReviewEvent {
  const SessionCancelled();
}

class SpeakQuestion {
  const SpeakQuestion(this.id);
  final String id;
}

class SpeakAnswer {
  const SpeakAnswer(this.id);
  final String id;
}

class TransitionResult {
  const TransitionResult(this.state, this.commands);
  final ReviewSessionState state;
  final List<Object> commands;
}

TransitionResult reviewTransition(ReviewSessionState state, ReviewEvent event) {
  switch (event) {
    case SessionCancelled():
      return TransitionResult(ReviewSessionState.initial(), const []);
    case SessionStarted():
      if (state.phase == ReviewPhase.idle || state.phase == ReviewPhase.done) {
        if (event.ids.isEmpty) {
          return const TransitionResult(
            ReviewSessionState(
              phase: ReviewPhase.done,
              remaining: [],
              knownCount: 0,
              unknownCount: 0,
            ),
            [],
          );
        }
        final first = event.ids.first;
        final rest = event.ids.sublist(1);
        return TransitionResult(
          ReviewSessionState(
            phase: ReviewPhase.asking,
            remaining: rest,
            current: first,
            knownCount: 0,
            unknownCount: 0,
          ),
          [SpeakQuestion(first)],
        );
      } else {
        return TransitionResult(state, const []);
      }
    case RevealRequested():
      if (state.phase == ReviewPhase.asking) {
        return TransitionResult(
          ReviewSessionState(
            phase: ReviewPhase.revealed,
            remaining: state.remaining,
            current: state.current,
            knownCount: state.knownCount,
            unknownCount: state.unknownCount,
          ),
          [SpeakAnswer(state.current!)],
        );
      } else {
        return TransitionResult(state, const []);
      }
    case Marked():
      if (state.phase == ReviewPhase.revealed) {
        final newKnown = state.knownCount + (event.knewIt ? 1 : 0);
        final newUnknown = state.unknownCount + (event.knewIt ? 0 : 1);
        if (state.remaining.isNotEmpty) {
          final next = state.remaining.first;
          final newRest = state.remaining.sublist(1);
          return TransitionResult(
            ReviewSessionState(
              phase: ReviewPhase.asking,
              remaining: newRest,
              current: next,
              knownCount: newKnown,
              unknownCount: newUnknown,
            ),
            [SpeakQuestion(next)],
          );
        } else {
          return TransitionResult(
            ReviewSessionState(
              phase: ReviewPhase.done,
              remaining: const [],
              knownCount: newKnown,
              unknownCount: newUnknown,
            ),
            const [],
          );
        }
      } else {
        return TransitionResult(state, const []);
      }
  }
}
