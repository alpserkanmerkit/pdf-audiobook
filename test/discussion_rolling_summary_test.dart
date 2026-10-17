// DQ-4 oracle test: withRollingSummary pure function (lib/src/discussion/
// discussion_rolling_summary.dart). Design note:
// internal design note section 7, item 4 -- for long-term context in endless
// mode, a cheap "rolling summary" layer (no LLM call, pure text).
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/discussion/discussion_rolling_summary.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';

void main() {
  group('withRollingSummary', () {
    test(
      'empty olderTurns: topic is returned AS IS (byte-identical behavior)',
      () {
        expect(withRollingSummary('topic text', const []), 'topic text');
      },
    );

    test(
      'single speaker -> summary block; the speaker is added with the REAL name',
      () {
        final result = withRollingSummary('topic', const [
          DiscussionTurn(DiscussionSpeaker.a, 'first thesis'),
        ]);
        expect(result, contains('topic'));
        expect(result, contains('PREVIOUS COURSE OF THE DISCUSSION'));
        expect(result, contains('Ahmet: first thesis'));
      },
    );

    test(
      'multiple speakers -> all are added in DiscussionSpeaker order (A,B,C,D)',
      () {
        final result = withRollingSummary('topic', const [
          DiscussionTurn(DiscussionSpeaker.b, 'thesis B'),
          DiscussionTurn(DiscussionSpeaker.a, 'thesis A'),
        ]);
        final idxA = result.indexOf('Ahmet:');
        final idxB = result.indexOf('Emel:');
        expect(idxA, greaterThanOrEqualTo(0));
        expect(idxB, greaterThanOrEqualTo(0));
        expect(
          idxA,
          lessThan(idxB),
          reason: 'DiscussionSpeaker.values order (A,B,C,D) is preserved',
        );
      },
    );

    test(
      'if the same speaker has MULTIPLE turns, only the LAST one is kept',
      () {
        final result = withRollingSummary('topic', const [
          DiscussionTurn(DiscussionSpeaker.a, 'old thesis'),
          DiscussionTurn(DiscussionSpeaker.a, 'current thesis'),
        ]);
        expect(result, contains('Ahmet: current thesis'));
        expect(result, isNot(contains('old thesis')));
      },
    );

    test('a long turn is cut at kRollingSummaryMaxChars with "…"', () {
      final longText = 'x' * (kRollingSummaryMaxChars + 20);
      final result = withRollingSummary('topic', [
        DiscussionTurn(DiscussionSpeaker.a, longText),
      ]);
      expect(result, contains('${'x' * kRollingSummaryMaxChars}…'));
      expect(result, isNot(contains(longText)));
    });

    test('a short turn (under the limit) is NOT cut', () {
      final result = withRollingSummary('topic', const [
        DiscussionTurn(DiscussionSpeaker.a, 'short'),
      ]);
      expect(result, contains('Ahmet: short'));
      expect(result, isNot(contains('…')));
    });

    test('when all 4 speakers exist, all appear in order', () {
      final result = withRollingSummary('topic', const [
        DiscussionTurn(DiscussionSpeaker.a, 'thesis A'),
        DiscussionTurn(DiscussionSpeaker.b, 'thesis B'),
        DiscussionTurn(DiscussionSpeaker.c, 'thesis C'),
        DiscussionTurn(DiscussionSpeaker.d, 'thesis D'),
      ]);
      expect(result, contains('Ahmet: thesis A'));
      expect(result, contains('Emel: thesis B'));
      expect(result, contains('Deniz: thesis C'));
      expect(result, contains('Kaya: thesis D'));
    });
  });
}
