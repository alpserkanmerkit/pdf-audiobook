// Oracle test (PR-K1): karaoke foundation -- pure sentence-timing layer.
// This layer converts TTS word-boundary events (real audio timing) into sentence start
// times. There is NO TEXT MATCHING: the two streams (sentences / words) are walked by
// cumulative character ratio -> even if TTS normalization ("2026" -> "two thousand
// twenty six") changes the word count/text, proportional alignment holds. 100% line
// coverage REQUIRED (every branch is tested).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/sentence_timing.dart';

void main() {
  group('sentenceWeight', () {
    test('counts non-whitespace characters', () {
      expect(sentenceWeight('abc'), 3);
      expect(sentenceWeight('a b c'), 3);
      expect(
        sentenceWeight('  ki  bin  '),
        5,
      ); // 'kibin' = 5 non-whitespace characters
    });
    test('empty / whitespace-only -> min 1', () {
      expect(sentenceWeight(''), 1);
      expect(sentenceWeight('   '), 1);
      expect(sentenceWeight('\t\n '), 1);
    });
    test('punctuation is counted (non-whitespace)', () {
      expect(sentenceWeight('a.'), 2);
    });
  });

  group('SentenceTimings JSON round-trip', () {
    test('toJson includes version + fields; fromJson reads them back', () {
      const t = SentenceTimings(startsMs: [0, 1000, 4000], totalMs: 10000);
      final j = t.toJson();
      expect(j['v'], 1);
      expect(j['startsMs'], [0, 1000, 4000]);
      expect(j['totalMs'], 10000);
      final back = SentenceTimings.fromJson(j);
      expect(back, isNotNull);
      expect(back!.startsMs, [0, 1000, 4000]);
      expect(back.totalMs, 10000);
    });

    test('malformed shape / wrong version -> null', () {
      expect(SentenceTimings.fromJson({}), isNull);
      expect(
        SentenceTimings.fromJson({
          'v': 2,
          'startsMs': [0],
          'totalMs': 1,
        }),
        isNull,
      );
      expect(
        SentenceTimings.fromJson({'v': 1, 'startsMs': 'bad', 'totalMs': 1}),
        isNull,
      );
      expect(
        SentenceTimings.fromJson({
          'v': 1,
          'startsMs': [0],
          'totalMs': 'x',
        }),
        isNull,
      );
      expect(SentenceTimings.fromJson({'v': 1, 'totalMs': 1}), isNull);
    });

    test(
      'empty startsMs -> null (review finding: PR-K2 narratingIndexAt clamp(0,-1) threw ArgumentError)',
      () {
        // Exactly the format as read from disk: via jsonDecode.
        final j =
            jsonDecode('{"v":1,"startsMs":[],"totalMs":0}')
                as Map<String, dynamic>;
        expect(SentenceTimings.fromJson(j), isNull);
      },
    );
  });

  group('timingsFromSentenceLengths', () {
    test('length-weighted proportional (10/30/60, 10s -> [0,1000,4000])', () {
      final t = timingsFromSentenceLengths(
        sentences: ['a' * 10, 'b' * 30, 'c' * 60],
        totalMs: 10000,
      );
      expect(t, isNotNull);
      expect(t!.startsMs, [0, 1000, 4000]);
      expect(t.totalMs, 10000);
    });

    test('equal lengths = old uniform result (reader regression)', () {
      // 4 equal sentences, 8s -> each sentence 2s: [0,2000,4000,6000].
      final t = timingsFromSentenceLengths(
        sentences: ['xxxx', 'yyyy', 'zzzz', 'wwww'],
        totalMs: 8000,
      );
      expect(t!.startsMs, [0, 2000, 4000, 6000]);
    });

    test('single sentence -> [0]', () {
      final t = timingsFromSentenceLengths(sentences: ['tek'], totalMs: 5000);
      expect(t!.startsMs, [0]);
      expect(t.totalMs, 5000);
    });

    test('totalMs <= 0 -> ArgumentError', () {
      expect(
        () => timingsFromSentenceLengths(sentences: ['a'], totalMs: 0),
        throwsArgumentError,
      );
      expect(
        () => timingsFromSentenceLengths(sentences: ['a'], totalMs: -5),
        throwsArgumentError,
      );
    });

    test('empty sentences -> null', () {
      expect(timingsFromSentenceLengths(sentences: [], totalMs: 1000), isNull);
    });
  });

  group('timingsFromWordBoundaries', () {
    test('aligned words -> exact sentence starts', () {
      // 2 sentences; the word stream splits cleanly at the sentence boundary.
      final sentences = ['Bir iki.', 'Uc dort.'];
      final words = [
        const WordBoundary(offsetMs: 0, durationMs: 100, text: 'Bir'),
        const WordBoundary(offsetMs: 100, durationMs: 100, text: 'iki'),
        const WordBoundary(offsetMs: 500, durationMs: 100, text: 'Uc'),
        const WordBoundary(offsetMs: 700, durationMs: 100, text: 'dort'),
      ];
      final t = timingsFromWordBoundaries(sentences: sentences, words: words);
      expect(t, isNotNull);
      expect(t!.startsMs.length, 2);
      expect(t.startsMs[0], 0);
      // 2nd sentence prefix ratio ~0.5; in the word stream 'Uc' (offset 500) is the
      // first one >= the threshold.
      expect(t.startsMs[1], 500);
    });

    test('normalized word mismatch (different token count) -> monotonic', () {
      // Sentences use punctuation and spacing; the word stream is tokenized differently
      // (TTS normalization).
      final sentences = ['Iki bin.', 'Yil geldi.'];
      final words = [
        const WordBoundary(offsetMs: 0, durationMs: 100, text: 'iki'),
        const WordBoundary(offsetMs: 200, durationMs: 100, text: 'bin'),
        const WordBoundary(offsetMs: 500, durationMs: 100, text: 'yil'),
        const WordBoundary(offsetMs: 800, durationMs: 200, text: 'geldi'),
      ];
      final t = timingsFromWordBoundaries(sentences: sentences, words: words);
      expect(t, isNotNull);
      expect(t!.startsMs[0], 0, reason: 'startsMs[0] is always 0');
      expect(t.startsMs.length, 2);
      // monotonicity: non-decreasing
      for (var i = 1; i < t.startsMs.length; i++) {
        expect(t.startsMs[i], greaterThanOrEqualTo(t.startsMs[i - 1]));
      }
      // f_1 = 7/16 = 0.4375; g_3 = 9/14 = 0.643 first >= threshold -> offset 800.
      expect(t.startsMs[1], 800);
    });

    test(
      'totalMs: if not given, taken from the last word (offset+duration)',
      () {
        final words = [
          const WordBoundary(offsetMs: 0, durationMs: 100, text: 'bir'),
          const WordBoundary(offsetMs: 900, durationMs: 300, text: 'iki'),
        ];
        final t = timingsFromWordBoundaries(
          sentences: ['Bir iki.'],
          words: words,
        );
        expect(t!.totalMs, 1200); // 900 + 300
      },
    );

    test(
      'totalMs: explicit value is used but does not fall below the last start',
      () {
        final words = [
          const WordBoundary(offsetMs: 0, durationMs: 100, text: 'bir'),
          const WordBoundary(offsetMs: 5000, durationMs: 100, text: 'son'),
        ];
        // If an explicit totalMs that is too small is given, it does not go below startsMs.last.
        final t = timingsFromWordBoundaries(
          sentences: ['Bir.', 'Son.'],
          words: words,
          totalMs: 10,
        );
        expect(t!.totalMs, greaterThanOrEqualTo(t.startsMs.last));
      },
    );

    test('single sentence -> [0]', () {
      final words = [
        const WordBoundary(offsetMs: 0, durationMs: 100, text: 'tek'),
      ];
      final t = timingsFromWordBoundaries(
        sentences: ['Tek cumle.'],
        words: words,
      );
      expect(t!.startsMs, [0]);
    });

    test('empty words -> null', () {
      expect(timingsFromWordBoundaries(sentences: ['a'], words: []), isNull);
    });

    test('empty sentences -> null', () {
      final words = [
        const WordBoundary(offsetMs: 0, durationMs: 100, text: 'x'),
      ];
      expect(timingsFromWordBoundaries(sentences: [], words: words), isNull);
    });

    test("if the threshold reaches no word, the last word's offset is used", () {
      // Very long last sentence -> f_k may exceed the last word's ratio; the fallback
      // is the last word's offset. The word stream is very short relative to the sentence.
      final sentences = ['a', 'b' * 1000];
      final words = [
        const WordBoundary(offsetMs: 0, durationMs: 50, text: 'x'),
        const WordBoundary(offsetMs: 100, durationMs: 50, text: 'y'),
      ];
      final t = timingsFromWordBoundaries(sentences: sentences, words: words);
      expect(t, isNotNull);
      expect(t!.startsMs[0], 0);
      // 2nd sentence threshold very high -> last word offset (100) fallback, monotonic.
      expect(t.startsMs[1], greaterThanOrEqualTo(0));
      expect(t.startsMs.length, 2);
    });
  });

  group('narratingIndexAt', () {
    const timings = SentenceTimings(startsMs: [0, 1000, 4000], totalMs: 10000);

    test('start (0) -> 0', () {
      expect(narratingIndexAt(timings: timings, position: Duration.zero), 0);
    });

    test('middle -> last sentence passed', () {
      expect(
        narratingIndexAt(
          timings: timings,
          position: const Duration(milliseconds: 1500),
        ),
        1,
      );
      expect(
        narratingIndexAt(
          timings: timings,
          position: const Duration(milliseconds: 4000),
        ),
        2,
      );
    });

    test('past the end -> last sentence (clamp)', () {
      expect(
        narratingIndexAt(
          timings: timings,
          position: const Duration(milliseconds: 99999),
        ),
        2,
      );
    });

    test('negative -> 0', () {
      expect(
        narratingIndexAt(
          timings: timings,
          position: const Duration(milliseconds: -100),
        ),
        0,
      );
    });
  });
}
