// Shared "async chain has finished" waiter (speed-3).
//
// Replaces the copied `_settleAsyncChain` (fixed 200 ms real runAsync). Rationale (old
// note in discussion_wiring_test.dart): the DiscussionController StreamController +
// unawaited() chain can finish WITHOUT forcing any frame; pumpAndSettle cannot observe
// that, so a REAL event-loop turn (runAsync) is needed. Instead of sleeping a fixed
// 200 ms, real turns are given until the chain has settled.
import 'package:flutter_test/flutter_test.dart';

/// Waits for the async chain to progress and settle; then advances the fake clock
/// (the remaining SHORT fake timers, e.g. the 5 ms playDelay, must not leave
/// "Timer is still pending" at teardown) and updates the widget tree.
///
/// One round = 1 real event-loop turn (`runAsync` + `Duration.zero`; NOT a fixed 200 ms
/// sleep) + a 10 ms fake-clock pump (short fake timers fire in their natural order).
///
/// - [until]: an observable condition showing the chain has FINISHED (e.g.
///   `() => played.length == 5`). Rounds are pumped until it holds (at most [timeout]
///   of real time), then [graceRounds] more rounds (for side effects / redraws that
///   arrive after the condition). If it never holds, it returns SILENTLY: the real
///   assertion is always the caller's `expect` (the condition is a waiting hint, not
///   an assertion).
/// - Without [until], a fixed [fallbackRounds] rounds are used (on continuously
///   animated screens `hasScheduledFrame` never goes quiet, so frame-based settling
///   cannot be measured).
Future<void> settleAsyncChain(
  WidgetTester tester, {
  bool Function()? until,
  int graceRounds = 4,
  int fallbackRounds = 10,
  Duration timeout = const Duration(seconds: 10),
}) async {
  Future<void> round() async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 10));
  }

  var rounds = fallbackRounds;
  if (until != null) {
    final clock = Stopwatch()..start();
    while (!until() && clock.elapsed < timeout) {
      await round();
    }
    rounds = graceRounds;
  }
  for (var i = 0; i < rounds; i++) {
    await round();
  }
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
}
