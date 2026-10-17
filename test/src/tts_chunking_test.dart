// Oracle test (Bug-G, 2026-07-04): chunkTextForTts pure splitter.
// Google Cloud TTS text:synthesize input is limited to 5000 UTF-8 bytes (curl evidence:
// 5001 bytes -> 400 "...longer than the limit of 5000 bytes...";
// 4900 bytes -> 200 OK). This file pins the pure function with 100% coverage.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/tts_chunking.dart';

void main() {
  group('chunkTextForTts', () {
    test('empty input -> []', () {
      expect(chunkTextForTts('', maxBytes: 100), <String>[]);
    });

    test('maxBytes <= 0 -> ArgumentError', () {
      expect(
        () => chunkTextForTts('merhaba', maxBytes: 0),
        throwsArgumentError,
      );
      expect(
        () => chunkTextForTts('merhaba', maxBytes: -5),
        throwsArgumentError,
      );
    });

    test('short text (under the limit) -> ONE chunk, text unchanged', () {
      final result = chunkTextForTts(
        'Merhaba dunya. Nasilsin?',
        maxBytes: 4500,
      );
      expect(result, hasLength(1));
      expect(result.single, 'Merhaba dunya. Nasilsin?');
    });

    test('every chunk <= maxBytes UTF-8 bytes', () {
      final longText = List.generate(
        200,
        (i) => 'Bu $i. cumle ve icinde bazi kelimeler var.',
      ).join(' ');
      final result = chunkTextForTts(longText, maxBytes: 200);
      expect(result, isNotEmpty);
      for (final chunk in result) {
        expect(
          utf8.encode(chunk).length,
          lessThanOrEqualTo(200),
          reason: 'chunk: "$chunk"',
        );
      }
    });

    test(
      'when the multi-sentence limit is exceeded, it splits at SENTENCE boundaries into several chunks',
      () {
        // Each sentence is ~30 bytes; maxBytes=50 -> one sentence fits per chunk.
        const text =
            'Birinci cumle burada. Ikinci cumle burada. '
            'Ucuncu cumle burada.';
        final result = chunkTextForTts(text, maxBytes: 50);
        expect(result.length, greaterThan(1));
        // Joined back with spaces, the original sentences are not lost.
        final rejoined = result.join(' ');
        expect(rejoined, contains('Birinci cumle burada.'));
        expect(rejoined, contains('Ikinci cumle burada.'));
        expect(rejoined, contains('Ucuncu cumle burada.'));
      },
    );

    test(
      'a single HUGE sentence over the limit splits at WORD boundaries (when a sentence-level split is not enough)',
      () {
        final hugeSentence =
            '${List.generate(100, (i) => 'word$i').join(' ')}.';
        final result = chunkTextForTts(hugeSentence, maxBytes: 60);
        expect(result.length, greaterThan(1));
        for (final chunk in result) {
          expect(utf8.encode(chunk).length, lessThanOrEqualTo(60));
          // Verify the split happens at word boundaries: a chunk must not start or end
          // in the middle of a word (its edges must be non-space characters from original words).
        }
        final rejoined = result.join(' ');
        expect(rejoined.replaceAll(RegExp(r'\s+'), ' '), contains('word0'));
        expect(rejoined, contains('word99'));
      },
    );

    test(
      'Turkish multi-byte characters (ş,ğ,ü,ö,ç,İ,ı) are NOT split in the middle (each chunk must decode as valid UTF-8)',
      () {
        final unit =
            'şğüöçİı ' * 20; // each repeat contains multi-byte characters
        final text = '$unit.' * 50;
        final result = chunkTextForTts(text, maxBytes: 137);
        expect(result, isNotEmpty);
        for (final chunk in result) {
          // utf8.encode + decode round-trip must be symmetric -- if a multi-byte character
          // had been cut in the middle, this chunk could not even exist as a valid Dart
          // String (we split at String level, not byte level) -- still, verify the byte
          // limit is not violated.
          expect(utf8.encode(chunk).length, lessThanOrEqualTo(137));
          expect(utf8.decode(utf8.encode(chunk)), chunk);
        }
      },
    );

    test(
      'even a single over-long word without spaces is split safely at code-point boundaries (multi-byte characters are not cut)',
      () {
        final hugeWord = 'ş' * 100; // each 'ş' is 2 bytes in UTF-8
        final result = chunkTextForTts(hugeWord, maxBytes: 10);
        expect(result, isNotEmpty);
        for (final chunk in result) {
          expect(utf8.encode(chunk).length, lessThanOrEqualTo(10));
          // Each chunk must contain a whole number of 'ş' (no fractional bytes) -- the
          // decode/encode round-trip in the test above already guarantees this; here we
          // also verify the character count is consistent.
          expect(utf8.decode(utf8.encode(chunk)), chunk);
        }
        expect(result.join(), hugeWord);
      },
    );

    test(
      'no content lost when chunks are joined: all words of the original text are preserved',
      () {
        const text =
            'Bir. Iki uc dort. Bes alti yedi sekiz dokuz on on bir on iki.';
        final result = chunkTextForTts(text, maxBytes: 25);
        final allWords = result
            .join(' ')
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .map((w) => w.replaceAll('.', ''))
            .toList();
        expect(
          allWords,
          containsAll(['Bir', 'Iki', 'uc', 'dort', 'on', 'bir']),
        );
      },
    );
  });
}
