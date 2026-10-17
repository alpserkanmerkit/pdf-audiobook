// RED-once oracle test (Wave-A / PR-A): constants/parameter layer of digest.
// Spec: internal design note §1/§3/§6.
// Cache key formats per the sketch contract: d_<hash>_c<idx>_<ver> and
// dm_<hash>_<ver> (same sanitize idiom as cache_keys.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/digest/digest_constants.dart';

void main() {
  group('constants', () {
    test('defaults match the report values', () {
      // FACT: 14-page sample, average 2133.5 chars/page.
      expect(defaultCharsPerPage, 2133);
      // ASSUMPTION (flagged in the report): Turkish 2.5-3.0 chars/token; conservative 2.5
      // is used as default, parametric until verified with the model tokenizer.
      expect(defaultCharsPerToken, 2.5);
      // Per-call input budget: 128K window minus prompt/output headroom.
      expect(defaultMaxTokensPerCall, 100000);
      expect(digestPromptVersion, 'd1');
    });
  });

  group('cache keys', () {
    test('chapterDigestCacheKey format d_<hash>_c<idx>_<ver>', () {
      expect(
        chapterDigestCacheKey(bookHash: '8917891e8c17a4d5', chapterIndex: 7),
        'd_8917891e8c17a4d5_c7_d1',
      );
    });

    test('bookDigestCacheKey format dm_<hash>_<ver>', () {
      expect(
        bookDigestCacheKey(bookHash: '8917891e8c17a4d5'),
        'dm_8917891e8c17a4d5_d1',
      );
    });

    test('custom version parameter is applied to the key', () {
      expect(
        chapterDigestCacheKey(bookHash: 'h', chapterIndex: 0, version: 'd2'),
        'd_h_c0_d2',
      );
      expect(bookDigestCacheKey(bookHash: 'h', version: 'd2'), 'dm_h_d2');
    });

    test('unsafe characters are cleaned via hex escaping', () {
      // cache_keys.dart idiom: every rune outside [a-zA-Z0-9._-] -> x<hex>.
      expect(bookDigestCacheKey(bookHash: 'a/b'), 'dm_ax2fb_d1');
      expect(
        chapterDigestCacheKey(bookHash: 'a b', chapterIndex: 1),
        'd_ax20b_c1_d1',
      );
    });
  });
}
