// Oracle test (DQ-2): discussion REVIEWER core -- pure JSON parsing +
// correction application + policy. The real 2nd LLM call (io wiring) is the
// NEXT wave; here only the pure layer is tested.
// Contract: internal design note §2 + internal experiment note (A2b) --
// reviewer scope is LIMITED to name + repetition + length, NO stance check
// (too sensitive); the output JSON schema is mandatory:
// {"ok":bool,"corrections":[{"index":int,"text":string}]}.
// FAIL-OPEN: parse failure -> null, the original is kept.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/discussion/discussion_review.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';

void main() {
  group('parseReviewResponse — valid inputs', () {
    test('clean JSON with corrections -> result', () {
      final r = parseReviewResponse(
        '{"ok": true, "corrections": [{"index": 1, "text": "corrected"}]}',
      );
      expect(r, isNotNull);
      expect(r!.ok, isTrue);
      expect(r.corrections, hasLength(1));
      expect(r.corrections.single.index, 1);
      expect(r.corrections.single.text, 'corrected');
    });

    test('clean JSON, empty corrections -> result', () {
      final r = parseReviewResponse('{"ok": true, "corrections": []}');
      expect(r, isNotNull);
      expect(r!.ok, isTrue);
      expect(r.corrections, isEmpty);
    });

    test('ok:false + corrections list -> result', () {
      final r = parseReviewResponse(
        '{"ok": false, "corrections": '
        '[{"index": 0, "text": "a"}, {"index": 2, "text": "b"}]}',
      );
      expect(r, isNotNull);
      expect(r!.ok, isFalse);
      expect(r.corrections, hasLength(2));
      expect(r.corrections[0].index, 0);
      expect(r.corrections[1].text, 'b');
    });

    test('code-fenced JSON (```json ... ```) -> result', () {
      final r = parseReviewResponse(
        '```json\n{"ok": true, "corrections": [{"index": 3, "text": "x"}]}\n```',
      );
      expect(r, isNotNull);
      expect(r!.corrections.single.index, 3);
    });

    test('single-line fence wrapping is also tolerated', () {
      final r = parseReviewResponse(
        '```json {"ok": true, "corrections": []} ```',
      );
      expect(r, isNotNull);
      expect(r!.ok, isTrue);
    });

    test('leading/trailing whitespace is tolerated', () {
      final r = parseReviewResponse('  \n{"ok": true, "corrections": []}\n  ');
      expect(r, isNotNull);
    });

    test('extra fields are ignored', () {
      final r = parseReviewResponse(
        '{"ok": true, "corrections": [], "extra": 1}',
      );
      expect(r, isNotNull);
    });

    test('Turkish characters are preserved in the correction text', () {
      final r = parseReviewResponse(
        '{"ok": true, "corrections": '
        '[{"index": 0, "text": "farkındalık ve şükür"}]}',
      );
      expect(r!.corrections.single.text, 'farkındalık ve şükür');
    });
  });

  group(
    'parseReviewResponse — contract violations (FAIL-OPEN: returns null)',
    () {
      test('invalid JSON -> null', () {
        expect(parseReviewResponse('this is not json'), isNull);
      });

      test('empty body -> null', () {
        expect(parseReviewResponse(''), isNull);
        expect(parseReviewResponse('   \n  '), isNull);
      });

      test('missing ok field -> null', () {
        expect(
          parseReviewResponse('{"corrections": [{"index": 0, "text": "x"}]}'),
          isNull,
        );
      });

      test('missing corrections field -> null', () {
        expect(parseReviewResponse('{"ok": true}'), isNull);
      });

      test('ok wrong type (string) -> null', () {
        expect(parseReviewResponse('{"ok": "yes", "corrections": []}'), isNull);
      });

      test('corrections wrong type (object, not list) -> null', () {
        expect(parseReviewResponse('{"ok": true, "corrections": {}}'), isNull);
      });

      test('missing index inside corrections -> null', () {
        expect(
          parseReviewResponse('{"ok": true, "corrections": [{"text": "x"}]}'),
          isNull,
        );
      });

      test('missing text inside corrections -> null', () {
        expect(
          parseReviewResponse('{"ok": true, "corrections": [{"index": 0}]}'),
          isNull,
        );
      });

      test('index wrong type (string) inside corrections -> null', () {
        expect(
          parseReviewResponse(
            '{"ok": true, "corrections": [{"index": "0", "text": "x"}]}',
          ),
          isNull,
        );
      });

      test('text wrong type (int) inside corrections -> null', () {
        expect(
          parseReviewResponse(
            '{"ok": true, "corrections": [{"index": 0, "text": 5}]}',
          ),
          isNull,
        );
      });

      test('plain JSON array (not object, top-level list) -> null', () {
        expect(parseReviewResponse('[1, 2, 3]'), isNull);
      });

      test('completely broken text (plain sentence) -> null', () {
        expect(
          parseReviewResponse('Flawless, approved, a wonderful discussion.'),
          isNull,
        );
      });
    },
  );

  group('applyReviewCorrections', () {
    const turns = [
      DiscussionTurn(DiscussionSpeaker.a, 'first line'),
      DiscussionTurn(DiscussionSpeaker.b, 'second line'),
      DiscussionTurn(DiscussionSpeaker.c, 'third line'),
    ];

    test('a valid correction is applied, speaker is preserved', () {
      final result = applyReviewCorrections(
        turns,
        const ReviewResult(
          ok: false,
          corrections: [ReviewCorrection(index: 1, text: 'new second')],
        ),
      );
      expect(result, hasLength(3));
      expect(result[0].text, 'first line');
      expect(result[1].speaker, DiscussionSpeaker.b);
      expect(result[1].text, 'new second');
      expect(result[2].text, 'third line');
    });

    test('multiple valid corrections are applied', () {
      final result = applyReviewCorrections(
        turns,
        const ReviewResult(
          ok: false,
          corrections: [
            ReviewCorrection(index: 0, text: 'new first'),
            ReviewCorrection(index: 2, text: 'new third'),
          ],
        ),
      );
      expect(result[0].text, 'new first');
      expect(result[1].text, 'second line');
      expect(result[2].text, 'new third');
    });

    test('out-of-range index (negative) is safely skipped', () {
      final result = applyReviewCorrections(
        turns,
        const ReviewResult(
          ok: false,
          corrections: [ReviewCorrection(index: -1, text: 'x')],
        ),
      );
      expect(result, orderedEquals(turns));
    });

    test('out-of-range index (>= length) is safely skipped', () {
      final result = applyReviewCorrections(
        turns,
        const ReviewResult(
          ok: false,
          corrections: [ReviewCorrection(index: 3, text: 'x')],
        ),
      );
      expect(result, orderedEquals(turns));
    });

    test(
      'with ok:true, turns are returned AS-IS even if corrections are set',
      () {
        final result = applyReviewCorrections(
          turns,
          const ReviewResult(
            ok: true,
            corrections: [ReviewCorrection(index: 0, text: 'must-not-change')],
          ),
        );
        expect(result, orderedEquals(turns));
      },
    );

    test('when corrections is empty, turns are returned AS-IS', () {
      final result = applyReviewCorrections(
        turns,
        const ReviewResult(ok: false, corrections: []),
      );
      expect(result, orderedEquals(turns));
    });

    test('mixed valid + out-of-range: only the valid one is applied', () {
      final result = applyReviewCorrections(
        turns,
        const ReviewResult(
          ok: false,
          corrections: [
            ReviewCorrection(index: 99, text: 'ignored'),
            ReviewCorrection(index: 1, text: 'new second'),
          ],
        ),
      );
      expect(result[0].text, 'first line');
      expect(result[1].text, 'new second');
      expect(result[2].text, 'third line');
    });

    test('empty text correction is safely skipped (original is kept)', () {
      final result = applyReviewCorrections(
        turns,
        const ReviewResult(
          ok: false,
          corrections: [ReviewCorrection(index: 1, text: '')],
        ),
      );
      expect(result, orderedEquals(turns));
    });

    test('whitespace-only text correction is safely skipped', () {
      final result = applyReviewCorrections(
        turns,
        const ReviewResult(
          ok: false,
          corrections: [ReviewCorrection(index: 0, text: '   \n\t ')],
        ),
      );
      expect(result, orderedEquals(turns));
    });

    test('mixed: empty correction is skipped, valid one is applied', () {
      final result = applyReviewCorrections(
        turns,
        const ReviewResult(
          ok: false,
          corrections: [
            ReviewCorrection(index: 0, text: ''),
            ReviewCorrection(index: 2, text: 'new third'),
          ],
        ),
      );
      expect(result[0].text, 'first line'); // empty, skipped
      expect(result[1].text, 'second line');
      expect(result[2].text, 'new third'); // valid, applied
    });

    test('empty turns list + any correction -> returns empty', () {
      final result = applyReviewCorrections(
        const [],
        const ReviewResult(
          ok: false,
          corrections: [ReviewCorrection(index: 0, text: 'x')],
        ),
      );
      expect(result, isEmpty);
    });
  });

  group('shouldReview — policy', () {
    test('batch 1 (batchIndex 0) is ALWAYS true', () {
      expect(shouldReview(batchIndex: 0), isTrue);
    });

    test(
      'batch 2+ (batchIndex >= 1) defaults to false (lint-gated; no lint in this layer)',
      () {
        expect(shouldReview(batchIndex: 1), isFalse);
        expect(shouldReview(batchIndex: 2), isFalse);
        expect(shouldReview(batchIndex: 10), isFalse);
      },
    );
  });

  group('reviewerPrompt — content pins (A2b scope decision)', () {
    test('name check EXISTS', () {
      expect(reviewerPrompt.toLowerCase(), contains('name'));
    });

    test('repetition check EXISTS', () {
      expect(reviewerPrompt.toLowerCase(), contains('repetition'));
    });

    test('length/character check EXISTS', () {
      final lower = reviewerPrompt.toLowerCase();
      expect(lower.contains('length') || lower.contains('karakter'), isTrue);
    });

    // User feedback (2026-09-28): instead of a one-sentence line, a 3-4
    // sentence rule -> the reviewer's LENGTH check now counts sentences
    // instead of the old fixed character ceiling (180/140) (consistency;
    // otherwise the reviewer would "fix" according to the old rule and break
    // the new one).
    test(
      'length check is sentence-count based; the old 180/140 ceiling is GONE',
      () {
        expect(reviewerPrompt, isNot(contains('180')));
        expect(reviewerPrompt, isNot(contains('140')));
        expect(reviewerPrompt, contains('sentence'));
      },
    );

    test('NO stance check (A2b: too sensitive, dropped from scope)', () {
      expect(reviewerPrompt.toLowerCase(), isNot(contains('stance')));
      expect(reviewerPrompt.toLowerCase(), isNot(contains('stance-violation')));
    });

    test('the mandatory JSON schema is stated in the prompt', () {
      // The substring 'ok' also occurs inside other words (e.g. 'book'), so the
      // entire schema line is pinned.
      expect(
        reviewerPrompt,
        contains(
          '{"ok": true|false, "corrections": '
          '[{"index": <0-based line index>, "text": ',
        ),
      );
    });
  });
}
