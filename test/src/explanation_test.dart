// Oracle RED tests: pure core of the "Ask" feature (lib/src/explanation).
// Word-chip extraction + LLM context window + prompt contract + JSON response
// parsing. HTTP transport is tested separately (llm_explanation_test).
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/explanation/explanation.dart';

void main() {
  group('explainableWords', () {
    test('splits on spaces, keeps the order of appearance', () {
      expect(explainableWords('Kedi mama yedi'), ['Kedi', 'mama', 'yedi']);
    });

    test('trims leading/trailing punctuation, keeps the word stem', () {
      expect(explainableWords('"Merhaba," dedi.'), ['Merhaba', 'dedi']);
    });

    test(
      'does NOT repeat the same word case-insensitively (first occurrence stays)',
      () {
        expect(explainableWords('Ev ev EV degil'), ['Ev', 'degil']);
      },
    );

    test('empty sentence -> empty list', () {
      expect(explainableWords(''), isEmpty);
    });

    test('punctuation/whitespace only -> empty list', () {
      expect(explainableWords('... !? --  '), isEmpty);
    });

    test('hyphens/apostrophes inside a word are kept (single chip)', () {
      expect(explainableWords('state-of-the-art bir sey'), [
        'state-of-the-art',
        'bir',
        'sey',
      ]);
    });

    test('Turkish characters count as word characters', () {
      expect(explainableWords('Çiçek açtı, şüphesiz.'), [
        'Çiçek',
        'açtı',
        'şüphesiz',
      ]);
    });
  });

  group('contextWindow', () {
    final five = ['s0.', 's1.', 's2.', 's3.', 's4.'];

    test('for a middle index, the +-radius neighborhood is joined', () {
      expect(contextWindow(five, 2, radius: 1), 's1. s2. s3.');
    });

    test('for a first index, the window is clipped to the start', () {
      expect(contextWindow(five, 0), 's0. s1. s2.');
    });

    test('for a last index, the window is clipped to the end', () {
      expect(contextWindow(five, 4), 's2. s3. s4.');
    });

    test('radius 0 -> only the center sentence', () {
      expect(contextWindow(five, 2, radius: 0), 's2.');
    });

    test(
      'if maxChars is exceeded the radius is narrowed (center NEVER drops)',
      () {
        final long = List.generate(5, (i) => 'c$i${'x' * 98}'); // each is 100
        // radius 2 -> 504 characters > 350; radius 1 -> 302 <= 350.
        final out = contextWindow(long, 2, maxChars: 350);
        expect(out, '${long[1]} ${long[2]} ${long[3]}');
      },
    );

    test(
      'if the center sentence alone does not fit, maxChars clips it from the start',
      () {
        final center = 'M${'y' * 59}'; // 60 characters
        final out = contextWindow([center], 0, maxChars: 20);
        expect(out, center.substring(0, 20));
        expect(out.length, 20);
      },
    );

    test('empty list -> ArgumentError', () {
      expect(() => contextWindow([], 0), throwsArgumentError);
    });

    test('out-of-range index -> ArgumentError', () {
      expect(() => contextWindow(five, 5), throwsArgumentError);
      expect(() => contextWindow(five, -1), throwsArgumentError);
    });

    test('negative radius -> ArgumentError', () {
      expect(() => contextWindow(five, 2, radius: -1), throwsArgumentError);
    });

    test('non-positive maxChars -> ArgumentError', () {
      expect(() => contextWindow(five, 2, maxChars: 0), throwsArgumentError);
    });
  });

  group('buildExplanationPrompt', () {
    test('word mode: target word is quoted + word phrase', () {
      final p = buildExplanationPrompt(
        target: 'perseverance',
        isWord: true,
        sentence: 'Her perseverance pays off eventually.',
        contextText: 'Before. Her perseverance pays off eventually. After.',
      );
      expect(p, contains('the word "perseverance"'));
      expect(p, contains('Her perseverance pays off eventually.'));
      expect(
        p,
        contains('Before. Her perseverance pays off eventually. After.'),
      );
    });

    test('sentence mode: asks what the sentence means (NO word phrase)', () {
      final p = buildExplanationPrompt(
        target: 'Her perseverance pays off eventually.',
        isWord: false,
        sentence: 'Her perseverance pays off eventually.',
        contextText: 'context',
      );
      expect(p, contains('Explain what the sentence below means'));
      expect(p, isNot(contains('the word "')));
    });

    test('both modes require a TURKISH explanation + JSON-ONLY contract', () {
      for (final isWord in [true, false]) {
        final p = buildExplanationPrompt(
          target: 'word',
          isWord: isWord,
          sentence: 'sentence',
          contextText: 'context',
        );
        expect(p, contains('MUST be in Turkish'));
        expect(p, contains('{"aciklama"'));
        expect(p, contains('SENTENCE:'));
        expect(p, contains('CONTEXT (neighboring sentences):'));
      }
    });
  });

  group('ExplanationParseException', () {
    test('toString contains the reason', () {
      expect(
        ExplanationParseException('test reason').toString(),
        contains('test reason'),
      );
    });
  });

  group('parseExplanationResponse', () {
    test('valid response: returns the explanation text (trim applied)', () {
      expect(
        parseExplanationResponse('{"aciklama":"  It means this.  "}'),
        'It means this.',
      );
    });

    test('invalid JSON -> ExplanationParseException', () {
      expect(
        () => parseExplanationResponse('this is not json'),
        throwsA(isA<ExplanationParseException>()),
      );
    });

    test('root value is not an object -> ExplanationParseException', () {
      expect(
        () => parseExplanationResponse('[1,2]'),
        throwsA(isA<ExplanationParseException>()),
      );
    });

    test('explanation field missing -> ExplanationParseException', () {
      expect(
        () => parseExplanationResponse('{"other":"field"}'),
        throwsA(isA<ExplanationParseException>()),
      );
    });

    test('explanation is not a string -> ExplanationParseException', () {
      expect(
        () => parseExplanationResponse('{"aciklama":3}'),
        throwsA(isA<ExplanationParseException>()),
      );
    });

    test('explanation empty/whitespace -> ExplanationParseException', () {
      expect(
        () => parseExplanationResponse('{"aciklama":"   "}'),
        throwsA(isA<ExplanationParseException>()),
      );
    });
  });
}
