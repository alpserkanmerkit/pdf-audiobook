// PR-Q1 (DESIGN §4): duration label foundation. kDiscussionWordsPerMinute = 108
// A2b Experiment-1 field measurement (6 samples, 103-113 band, real device mp3s,
// 1x speed). In this PR only the constant and the finite-mode ROUGH label ("~2-3 min"
// -- for the 12-16 turn opening batch) are added; the Short/Medium/Long selector
// belongs to PR-2.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/discussion/discussion_budget.dart';
import 'package:sesli_kitap/src/discussion/discussion_pace.dart';

void main() {
  test('kDiscussionWordsPerMinute == 108 (A2b measurement, 1x speed)', () {
    expect(kDiscussionWordsPerMinute, 108);
  });

  group('discussionWordCount', () {
    test('counts the words in turn texts (whitespace split)', () {
      expect(discussionWordCount('bir iki uc'), 3);
      expect(discussionWordCount(''), 0);
      expect(discussionWordCount('   '), 0);
      expect(discussionWordCount('tek'), 1);
    });
  });

  // DQ-W1 REWORK (MINOR): discussionFiniteDurationLabel() was deleted as dead code;
  // its replacement is the mode-based discussionModeDurationLabel (below).

  // DQ-W1 RED test: "~N min" estimate for the length-mode selector.
  // targetWordsFor(mode) / kDiscussionWordsPerMinute -> rounded up to whole minutes.
  group('discussionModeDurationLabel — per-mode duration estimate', () {
    test('short (550 words) -> ~6 min (550/108 = 5.09 -> round up to 6)', () {
      expect(discussionModeDurationLabel(DiscussionLengthMode.kisa), '~6 min');
    });

    test(
      'medium (1100 words) -> ~11 min (1100/108 = 10.18 -> round up to 11)',
      () {
        expect(
          discussionModeDurationLabel(DiscussionLengthMode.orta),
          '~11 min',
        );
      },
    );

    test(
      'long (2150 words) -> ~20 min (2150/108 = 19.9 -> round up to 20)',
      () {
        expect(
          discussionModeDurationLabel(DiscussionLengthMode.uzun),
          '~20 min',
        );
      },
    );

    test('endless -> no target, fixed "Until you stop it" label', () {
      expect(
        discussionModeDurationLabel(DiscussionLengthMode.sonsuz),
        'Until you stop it',
      );
    });
  });
}
