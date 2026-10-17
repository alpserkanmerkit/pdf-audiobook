// DQ-1 RED test (oracle). lib/src/discussion/discussion_budget.dart is written by the worker.
// Long-discussion word-budget core: word counting + target-turn rounding + closing trigger +
// length-mode constants. Pure, 100% (no io/UI, not this wave).
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/discussion/discussion_budget.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';

void main() {
  group('scriptWordCount (total words)', () {
    test('empty list -> 0', () {
      expect(scriptWordCount(const []), 0);
    });

    test('single turn -> word count', () {
      final turns = [
        const DiscussionTurn(
          DiscussionSpeaker.a,
          'bu bes kelimelik bir replik',
        ),
      ];
      expect(scriptWordCount(turns), 5);
    });

    test('multiple turns -> total words', () {
      final turns = [
        const DiscussionTurn(DiscussionSpeaker.a, 'iki kelime'),
        const DiscussionTurn(DiscussionSpeaker.b, 'uc kelime burada'),
        const DiscussionTurn(DiscussionSpeaker.c, 'tek'),
      ];
      // 2 + 3 + 1 = 6
      expect(scriptWordCount(turns), 6);
    });

    test('extra whitespace does not affect the word count', () {
      final turns = [
        const DiscussionTurn(DiscussionSpeaker.a, '  bir   iki    uc  '),
      ];
      expect(scriptWordCount(turns), 3);
    });

    test('a turn with empty text adds 0 words', () {
      final turns = [
        const DiscussionTurn(DiscussionSpeaker.a, ''),
        const DiscussionTurn(DiscussionSpeaker.b, 'tek'),
      ];
      expect(scriptWordCount(turns), 1);
    });

    test('text of whitespace only adds 0 words', () {
      final turns = [const DiscussionTurn(DiscussionSpeaker.a, '   ')];
      expect(scriptWordCount(turns), 0);
    });
  });

  group('computeTargetTurns (rough turn count, round up)', () {
    test('exact division -> exact quotient', () {
      expect(computeTargetTurns(targetWords: 1000, avgWordsPerTurn: 100), 10);
    });

    test('non-exact division -> rounded up', () {
      expect(
        computeTargetTurns(targetWords: 2150, avgWordsPerTurn: 160),
        14, // 2150/160 = 13.4375 -> 14
      );
    });

    test('even a small remainder rounds up', () {
      expect(computeTargetTurns(targetWords: 501, avgWordsPerTurn: 500), 2);
    });

    test('targetWords 0 -> 0 turns', () {
      expect(computeTargetTurns(targetWords: 0, avgWordsPerTurn: 100), 0);
    });

    test('avgWordsPerTurn zero -> ArgumentError', () {
      expect(
        () => computeTargetTurns(targetWords: 1000, avgWordsPerTurn: 0),
        throwsArgumentError,
      );
    });

    test('avgWordsPerTurn negative -> ArgumentError', () {
      expect(
        () => computeTargetTurns(targetWords: 1000, avgWordsPerTurn: -5),
        throwsArgumentError,
      );
    });
  });

  group('shouldRequestClosing (closing trigger)', () {
    test('current words below target -> false', () {
      expect(
        shouldRequestClosing(currentWords: 1000, targetWords: 2150),
        isFalse,
      );
    });

    test('current words above target -> true', () {
      expect(
        shouldRequestClosing(currentWords: 2200, targetWords: 2150),
        isTrue,
      );
    });

    test('exactly at the limit (equal) -> true', () {
      expect(
        shouldRequestClosing(currentWords: 2150, targetWords: 2150),
        isTrue,
      );
    });

    test('one below the target -> false', () {
      expect(
        shouldRequestClosing(currentWords: 2149, targetWords: 2150),
        isFalse,
      );
    });

    test('target 0 -> true even at 0 words (already full)', () {
      expect(shouldRequestClosing(currentWords: 0, targetWords: 0), isTrue);
    });
  });

  group('DiscussionLengthMode + targetWordsFor', () {
    test('4 modes, full coverage: kisa/orta/uzun/sonsuz', () {
      expect(DiscussionLengthMode.values, hasLength(4));
      expect(
        DiscussionLengthMode.values,
        containsAll(const [
          DiscussionLengthMode.kisa,
          DiscussionLengthMode.orta,
          DiscussionLengthMode.uzun,
          DiscussionLengthMode.sonsuz,
        ]),
      );
    });

    test('kisa -> 550 words target', () {
      expect(targetWordsFor(DiscussionLengthMode.kisa), 550);
    });

    test('orta -> 1100 words target', () {
      expect(targetWordsFor(DiscussionLengthMode.orta), 1100);
    });

    test('uzun -> 2150 words target', () {
      expect(targetWordsFor(DiscussionLengthMode.uzun), 2150);
    });

    test('sonsuz -> null (no target)', () {
      expect(targetWordsFor(DiscussionLengthMode.sonsuz), isNull);
    });
  });
}
