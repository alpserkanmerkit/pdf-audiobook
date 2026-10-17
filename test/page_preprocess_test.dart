// Oracle test (PHASE 2): page-artifact stripping (spec §3 regex layer).
// Rule: this layer ONLY strips artifacts (page-number line + running header);
// paragraph merging/OCR correction is LLM work. The running header is returned
// as metadata BEFORE it is removed (Phase 3 chapter-map input, spec §3).
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/page_preprocess.dart';

void main() {
  group('stripPageArtifacts — page number', () {
    test('a digits-only first line is stripped and pageNumber is returned', () {
      final r = stripPageArtifacts('12\nBirinci paragraf.\nIkinci satir.');
      expect(r.pageNumber, 12);
      expect(r.text, 'Birinci paragraf.\nIkinci satir.');
    });
    test('decoration variants are stripped: "- 12 -", "— 12 —", "• 12"', () {
      expect(stripPageArtifacts('- 12 -\nMetin.').pageNumber, 12);
      expect(stripPageArtifacts('— 12 —\nMetin.').pageNumber, 12);
      expect(stripPageArtifacts('• 12\nMetin.').pageNumber, 12);
      expect(stripPageArtifacts('- 12 -\nMetin.').text, 'Metin.');
    });
    test('the page number on the last line is stripped too', () {
      final r = stripPageArtifacts('Metin burada biter.\n47');
      expect(r.pageNumber, 47);
      expect(r.text, 'Metin burada biter.');
    });
    test(
      'both first and last digit-lines: both are removed, pageNumber=first',
      () {
        final r = stripPageArtifacts('12\nGovde metni.\n12');
        expect(r.pageNumber, 12);
        expect(r.text, 'Govde metni.');
      },
    );
    test('a real text line starting with digits is NOT touched', () {
      final r = stripPageArtifacts('12 Eylul sabahi kent uyaniyordu.\nDevam.');
      expect(r.pageNumber, isNull);
      expect(r.text, '12 Eylul sabahi kent uyaniyordu.\nDevam.');
    });
    test('no digit-line: pageNumber null, text stays as is', () {
      final r = stripPageArtifacts('Sade metin.\nIkinci satir.');
      expect(r.pageNumber, isNull);
      expect(r.text, 'Sade metin.\nIkinci satir.');
    });
  });

  group('stripPageArtifacts — running header (knownHeader)', () {
    test(
      'first line matching knownHeader is removed + metadata is returned',
      () {
        final r = stripPageArtifacts(
          'INSAN DOGASININ YASALARI\nGercek paragraf.',
          knownHeader: 'INSAN DOGASININ YASALARI',
        );
        expect(r.strippedHeader, 'INSAN DOGASININ YASALARI');
        expect(r.text, 'Gercek paragraf.');
      },
    );
    test('matching is tolerant of case and edge whitespace', () {
      final r = stripPageArtifacts(
        '  insan dogasinin yasalari  \nParagraf.',
        knownHeader: 'INSAN DOGASININ YASALARI',
      );
      expect(r.strippedHeader, isNotNull);
      expect(r.text, 'Paragraf.');
    });
    test(
      'if the first line differs, the header is NOT removed (false positives forbidden)',
      () {
        final r = stripPageArtifacts(
          'Bu bir baslik degil normal cumle.\nDevami.',
          knownHeader: 'INSAN DOGASININ YASALARI',
        );
        expect(r.strippedHeader, isNull);
        expect(r.text, 'Bu bir baslik degil normal cumle.\nDevami.');
      },
    );
    test('page number + header together: both are stripped', () {
      final r = stripPageArtifacts(
        '13\nINSAN DOGASININ YASALARI\nAsil metin.',
        knownHeader: 'INSAN DOGASININ YASALARI',
      );
      expect(r.pageNumber, 13);
      expect(r.strippedHeader, isNotNull);
      expect(r.text, 'Asil metin.');
    });
    test('no header is searched for when knownHeader is not given', () {
      final r = stripPageArtifacts('KISA SATIR\nMetin.');
      expect(r.strippedHeader, isNull);
      expect(r.text, 'KISA SATIR\nMetin.');
    });
  });

  group('stripPageArtifacts — PDF character artifacts (font decoding)', () {
    test("fake @ attached to a letter is removed (the user's real book)", () {
      // Robert Greene, Insan Dogasinin Yasalari — PDF extraction produces a
      // fake @ before every n/k. Raw: "zihi@n" -> correct: "zihin".
      final r = stripPageArtifacts('"zihi@n" ya da "ze@kâ" a@nlamı@na');
      expect(r.text, '"zihin" ya da "zekâ" anlamına');
    });
    test('soft hyphen (U+00AD) hyphenation mark is fully removed', () {
      final r = stripPageArtifacts('zi­hin');
      expect(r.text, 'zihin');
    });
    test(
      'word-initial @ attached to a letter is removed (@kaynagi -> kaynagi)',
      () {
        final r = stripPageArtifacts('@kaynağı');
        expect(r.text, 'kaynağı');
      },
    );
    test('standalone @ surrounded by spaces is KEPT (legitimate use)', () {
      // Regression safety: an @ not attached to a letter is not a font artifact.
      final r = stripPageArtifacts('e-posta: a @ b');
      expect(r.text, 'e-posta: a @ b');
    });
    test('artifact cleanup runs BEFORE header matching', () {
      // Match the header against the cleaned text (including the soft-hyphenated header).
      final r = stripPageArtifacts(
        'INSAN DOGASI­NIN YASALARI\nGercek paragraf.',
        knownHeader: 'INSAN DOGASININ YASALARI',
      );
      expect(r.strippedHeader, isNotNull);
      expect(r.text, 'Gercek paragraf.');
    });
  });

  group('stripPageArtifacts — boundaries', () {
    test('empty input: empty text + null fields', () {
      final r = stripPageArtifacts('');
      expect(r.text, '');
      expect(r.pageNumber, isNull);
      expect(r.strippedHeader, isNull);
    });
    test("lines within a paragraph are not merged (not this layer's job)", () {
      final r = stripPageArtifacts('Satir bir\nsatir iki\nsatir uc');
      expect(r.text, 'Satir bir\nsatir iki\nsatir uc');
    });
  });
}
