// Mutation test (tool/mutation.dart) finding: tts_chunking.dart byte-boundary arithmetic. Spec (chunkTextForTts doc):
// chunk <= maxBytes; content that lands EXACTLY on the limit stays in the SAME chunk, one byte more opens a new chunk;
// the counter restarts FROM ZERO after every chunk/flush. Earlier tests did not probe either side of the limit nor the
// post-flush counter (14 mutants survived).
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/tts_chunking.dart';

void main() {
  group('sentence-level boundary', () {
    test(
      'two sentences + separator EXACTLY maxBytes -> one chunk; one byte less -> two',
      () {
        // "Aa."=3 bytes, separator=1, "Bb."=3 -> total 7.
        expect(chunkTextForTts('Aa. Bb.', maxBytes: 7), ['Aa. Bb.']);
        expect(chunkTextForTts('Aa. Bb.', maxBytes: 6), ['Aa.', 'Bb.']);
      },
    );

    test(
      'a sentence of exactly maxBytes length stays as is (inner space preserved)',
      () {
        // 7 bytes, inner double space: if it took the word-split path it would collapse to a single space.
        expect(chunkTextForTts('Aa  Bb.', maxBytes: 7), ['Aa  Bb.']);
      },
    );

    test('byte counter restarts from zero after an overlong sentence', () {
      // "Dd." is the pending chunk, the long sentence closes it; the next "Ee. Ff." (7)
      // must fit in one chunk with a fresh counter.
      expect(chunkTextForTts('Dd. Aaaa bbbb cccc. Ee. Ff.', maxBytes: 7), [
        'Dd.',
        'Aaaa',
        'bbbb',
        'cccc.',
        'Ee. Ff.',
      ]);
    });
  });

  group('word-level boundary', () {
    test('words are packed into the same chunk up to the EXACT limit', () {
      // 'aaa bbb ccc' = 11 bytes (exact limit), remainder 'ddd eee'.
      expect(chunkTextForTts('aaa bbb ccc ddd eee', maxBytes: 11), [
        'aaa bbb ccc',
        'ddd eee',
      ]);
    });

    test('counter restarts from zero after an overlong word', () {
      expect(chunkTextForTts('aa bbbbbbbbbb cc dd', maxBytes: 5), [
        'aa',
        'bbbbb',
        'bbbbb',
        'cc dd',
      ]);
    });
  });

  group('code-point-level boundary', () {
    test('a no-space ASCII string is split into exact maxBytes slices', () {
      expect(chunkTextForTts('abcdefghij', maxBytes: 4), [
        'abcd',
        'efgh',
        'ij',
      ]);
    });

    test(
      'maxBytes 1 is valid (only <= 0 is an error): each character is its own chunk',
      () {
        expect(chunkTextForTts('ab', maxBytes: 1), ['a', 'b']);
      },
    );
  });
}
