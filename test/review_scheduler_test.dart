// Oracle test (spec Phase 4: spaced repetition 1-3-7 + quiz session) — PURE.
// Precedent: Readwise Mastery (active recall + spaced repetition). Two layers:
// (a) pure scheduling functions (day index int; NO DateTime — purity),
// (b) quiz session STATE MACHINE (the 3rd of the Prepare/ReaderMachine family:
//     the UI shell only executes Speak* commands).
//
// Contract decisions (oracle, 2026-06-12):
// - Intervals are FIXED [1,3,7] (spec). ReviewItem{id, intervalIndex 0..2,
//   dueDay}; intervalIndex 3 = RETIRED (dueDay is meaningless, pinned at -1).
// - planNewItem(id, today) → index 0, dueDay = today+1.
// - applyAnswer(item, knewIt, today): knew it → index+1 (after 2 it becomes RETIRED);
//   new dueDay = today + [1,3,7][newIndex]; did not know → index 0,
//   dueDay = today+1. Answering a retired item → returned unchanged (swallowed).
//   Input is NOT mutated (a new object is returned).
// - dueItems(items, today): non-retired ∧ dueDay<=today; order dueDay ascending,
//   ties by id alphabetically; the returned list is UNMODIFIABLE.
// - ReviewSession machine: phases idle/asking/revealed/done.
//   Events: SessionStarted(ids) (in idle|done; empty ids → IMMEDIATELY done, no
//   command), RevealRequested (asking→revealed + [SpeakAnswer(current)]),
//   Marked(knewIt) (revealed→ asking + [SpeakQuestion(next)] if the queue has items
//   otherwise done; knew/did-not-know counters are updated), SessionCancelled (→initial).
//   SessionStarted is IGNORED in asking|revealed (busy guard);
//   Reveal is swallowed outside asking; Marked is swallowed outside revealed.
//   AT MOST 1 command per transition; transition is PURE and the input is not mutated.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/review_scheduler.dart';

void main() {
  group('scheduling — planNewItem / applyAnswer', () {
    test('new item: index 0, due tomorrow', () {
      final it = planNewItem('s1', 10);
      expect(it.id, 's1');
      expect(it.intervalIndex, 0);
      expect(it.dueDay, 11);
    });

    test('knew-it ladder: 1 → 3 → 7 → retired', () {
      var it = planNewItem('s1', 10);
      it = applyAnswer(it, knewIt: true, today: 11);
      expect(it.intervalIndex, 1);
      expect(it.dueDay, 14); // 11 + 3
      it = applyAnswer(it, knewIt: true, today: 14);
      expect(it.intervalIndex, 2);
      expect(it.dueDay, 21); // 14 + 7
      it = applyAnswer(it, knewIt: true, today: 21);
      expect(it.intervalIndex, 3); // RETIRED
      expect(it.dueDay, -1);
    });

    test('did not know: index 0 + tomorrow from any level', () {
      var it = planNewItem('s1', 0);
      it = applyAnswer(it, knewIt: true, today: 1);
      it = applyAnswer(it, knewIt: true, today: 4);
      expect(it.intervalIndex, 2);
      it = applyAnswer(it, knewIt: false, today: 11);
      expect(it.intervalIndex, 0);
      expect(it.dueDay, 12);
    });

    test('answering a retired item is swallowed (returned unchanged)', () {
      var it = planNewItem('s1', 0);
      for (final d in [1, 2, 9]) {
        it = applyAnswer(it, knewIt: true, today: d);
      }
      expect(it.intervalIndex, 3);
      final sonra = applyAnswer(it, knewIt: false, today: 99);
      expect(sonra.intervalIndex, 3);
      expect(sonra.dueDay, -1);
    });

    test(
      'out-of-range intervalIndex (4+) is swallowed like retired — not RangeError '
      '(K7 defensive)',
      () {
        // decodeReviewBank rejects values outside 0..3; even so, an index of 4+ from an old record
        // must not overflow intervals[] inside applyAnswer.
        const it = ReviewItem(id: 's1', intervalIndex: 4, dueDay: -1);
        final sonra = applyAnswer(it, knewIt: true, today: 10);
        expect(sonra.intervalIndex, 4);
        expect(sonra.dueDay, -1);
      },
    );

    test('applyAnswer does not mutate its input', () {
      final once = planNewItem('s1', 10);
      applyAnswer(once, knewIt: true, today: 11);
      expect(once.intervalIndex, 0);
      expect(once.dueDay, 11);
    });
  });

  group('scheduling — dueItems', () {
    test('only due items; retired and future items are filtered out', () {
      final items = [
        const ReviewItem(id: 'a', intervalIndex: 0, dueDay: 5),
        const ReviewItem(id: 'b', intervalIndex: 1, dueDay: 9),
        const ReviewItem(id: 'c', intervalIndex: 3, dueDay: -1), // retired
        const ReviewItem(id: 'd', intervalIndex: 2, dueDay: 3),
      ];
      final due = dueItems(items, 5);
      expect(due.map((e) => e.id), ['d', 'a']); // dueDay ascending
    });

    test('equal dueDay → id alphabetical; returned list is unmodifiable', () {
      final items = [
        const ReviewItem(id: 'z', intervalIndex: 0, dueDay: 2),
        const ReviewItem(id: 'a', intervalIndex: 0, dueDay: 2),
      ];
      final due = dueItems(items, 2);
      expect(due.map((e) => e.id), ['a', 'z']);
      expect(
        () => due.add(const ReviewItem(id: 'x', intervalIndex: 0, dueDay: 0)),
        throwsUnsupportedError,
      );
    });

    test('empty input → empty; if none is due today → empty', () {
      expect(dueItems(const [], 5), isEmpty);
      expect(
        dueItems(const [ReviewItem(id: 'a', intervalIndex: 0, dueDay: 9)], 5),
        isEmpty,
      );
    });
  });

  group('ReviewSession machine', () {
    test('initial: idle, empty queue, counters at zero', () {
      final s = ReviewSessionState.initial();
      expect(s.phase, ReviewPhase.idle);
      expect(s.remaining, isEmpty);
      expect(s.knownCount, 0);
      expect(s.unknownCount, 0);
    });

    test('SessionStarted: asking + SpeakQuestion for the FIRST question', () {
      final r = reviewTransition(
        ReviewSessionState.initial(),
        const SessionStarted(['s1', 's2']),
      );
      expect(r.state.phase, ReviewPhase.asking);
      expect(r.state.current, 's1');
      expect(r.commands, hasLength(1));
      expect((r.commands.single as SpeakQuestion).id, 's1');
    });

    test('SessionStarted with empty ids: IMMEDIATELY done, no command', () {
      final r = reviewTransition(
        ReviewSessionState.initial(),
        const SessionStarted([]),
      );
      expect(r.state.phase, ReviewPhase.done);
      expect(r.commands, isEmpty);
    });

    test('Reveal: asking→revealed + SpeakAnswer(current)', () {
      final s = reviewTransition(
        ReviewSessionState.initial(),
        const SessionStarted(['s1']),
      ).state;
      final r = reviewTransition(s, const RevealRequested());
      expect(r.state.phase, ReviewPhase.revealed);
      expect((r.commands.single as SpeakAnswer).id, 's1');
    });

    test('Marked: moves to the next question + updates the counter', () {
      var s = reviewTransition(
        ReviewSessionState.initial(),
        const SessionStarted(['s1', 's2']),
      ).state;
      s = reviewTransition(s, const RevealRequested()).state;
      final r = reviewTransition(s, const Marked(knewIt: true));
      expect(r.state.phase, ReviewPhase.asking);
      expect(r.state.current, 's2');
      expect(r.state.knownCount, 1);
      expect((r.commands.single as SpeakQuestion).id, 's2');
    });

    test('Marked on the last question: done, no command, counters correct', () {
      var s = reviewTransition(
        ReviewSessionState.initial(),
        const SessionStarted(['s1']),
      ).state;
      s = reviewTransition(s, const RevealRequested()).state;
      final r = reviewTransition(s, const Marked(knewIt: false));
      expect(r.state.phase, ReviewPhase.done);
      expect(r.state.unknownCount, 1);
      expect(r.commands, isEmpty);
    });

    test('done + SessionStarted: a new session starts', () {
      final s = reviewTransition(
        ReviewSessionState.initial(),
        const SessionStarted([]),
      ).state;
      expect(s.phase, ReviewPhase.done);
      final r = reviewTransition(s, const SessionStarted(['s9']));
      expect(r.state.phase, ReviewPhase.asking);
      expect(r.state.current, 's9');
    });

    test('busy guard: SessionStarted is swallowed in asking/revealed', () {
      final asking = reviewTransition(
        ReviewSessionState.initial(),
        const SessionStarted(['s1']),
      ).state;
      final r1 = reviewTransition(asking, const SessionStarted(['other']));
      expect(r1.state.current, 's1');
      expect(r1.commands, isEmpty);
      final revealed = reviewTransition(asking, const RevealRequested()).state;
      final r2 = reviewTransition(revealed, const SessionStarted(['other']));
      expect(r2.state.phase, ReviewPhase.revealed);
      expect(r2.commands, isEmpty);
    });

    test('Reveal/Marked in the wrong phase are swallowed', () {
      final idle = ReviewSessionState.initial();
      expect(reviewTransition(idle, const RevealRequested()).commands, isEmpty);
      expect(
        reviewTransition(idle, const Marked(knewIt: true)).state.phase,
        ReviewPhase.idle,
      );
      final asking = reviewTransition(idle, const SessionStarted(['s1'])).state;
      final r = reviewTransition(asking, const Marked(knewIt: true));
      expect(r.state.phase, ReviewPhase.asking);
      expect(r.state.knownCount, 0);
    });

    test('done + Reveal is swallowed (remaining combination class)', () {
      final done = reviewTransition(
        ReviewSessionState.initial(),
        const SessionStarted([]),
      ).state;
      final r = reviewTransition(done, const RevealRequested());
      expect(r.state.phase, ReviewPhase.done);
      expect(r.commands, isEmpty);
    });

    test('SessionCancelled: from any phase back to initial', () {
      var s = reviewTransition(
        ReviewSessionState.initial(),
        const SessionStarted(['s1', 's2']),
      ).state;
      s = reviewTransition(s, const RevealRequested()).state;
      final r = reviewTransition(s, const SessionCancelled());
      expect(r.state.phase, ReviewPhase.idle);
      expect(r.state.remaining, isEmpty);
      expect(r.commands, isEmpty);
    });

    test(
      'transition is PURE: same input twice gives same result; input is not mutated',
      () {
        final s = reviewTransition(
          ReviewSessionState.initial(),
          const SessionStarted(['s1', 's2']),
        ).state;
        final r1 = reviewTransition(s, const RevealRequested());
        final r2 = reviewTransition(s, const RevealRequested());
        expect(r1.state.phase, r2.state.phase);
        expect(s.phase, ReviewPhase.asking); // not mutated
        expect(s.current, 's1');
      },
    );

    test('structural: no transition produces more than 1 command', () {
      var s = ReviewSessionState.initial();
      final olaylar = <ReviewEvent>[
        const SessionStarted(['s1', 's2']),
        const RevealRequested(),
        const Marked(knewIt: true),
        const RevealRequested(),
        const Marked(knewIt: false),
      ];
      for (final e in olaylar) {
        final r = reviewTransition(s, e);
        expect(r.commands.length, lessThanOrEqualTo(1));
        s = r.state;
      }
      expect(s.phase, ReviewPhase.done);
      expect(s.knownCount, 1);
      expect(s.unknownCount, 1);
    });
  });
}
