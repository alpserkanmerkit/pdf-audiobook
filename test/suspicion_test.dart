// Oracle test (Phase 2): conditional-auditor heuristics (spec §6) -- PLAIN CODE, not AI.
// Three rules: (1) word alignment: a letter fix INSIDE a word is NORMAL (OCR);
// insertion / deletion / full replacement is SUSPICIOUS; joining a hyphenated line
// break is NORMAL (this is the spec §5 task itself; false positives are forbidden).
// (2) length limit of +/-15%. (3) odd non-Turkish characters in the output. Reasons
// are reported with fixed keys: 'silme' (deletion) | 'ekleme' (insertion) |
// 'degisim' (replacement) | 'uzunluk' (length) | 'karakter' (character), for diagnosability.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/suspicion.dart';

void main() {
  group('assessClean — NORMAL (no suspicion; false positives forbidden)', () {
    test('identical text is clean', () {
      final v = assessClean(
        raw: 'Atina sanat ve bilim konusunda altın çağına girdi.',
        clean: 'Atina sanat ve bilim konusunda altın çağına girdi.',
      );
      expect(v.suspicious, isFalse);
      expect(v.reasons, isEmpty);
    });
    test('in-word OCR correction is normal', () {
      final v = assessClean(
        raw: 'Bu kitap farkmdahk üzerine yazılmıştır ve hayatm anlamını arar.',
        clean:
            'Bu kitap farkındalık üzerine yazılmıştır ve hayatın anlamını '
            'arar.',
      );
      expect(v.suspicious, isFalse);
    });
    test(
      'hyphen line-break joining is normal (spec §5 is the task itself)',
      () {
        final v = assessClean(
          raw: 'Kentte bü- yük bir coşku vardı ve insanlar mutluydu.',
          clean: 'Kentte büyük bir coşku vardı ve insanlar mutluydu.',
        );
        expect(v.suspicious, isFalse);
      },
    );
    test('whitespace / line-end normalization is not suspicious', () {
      final v = assessClean(
        raw: 'Birinci   cümle.\nİkinci    cümle burada.',
        clean: 'Birinci cümle. İkinci cümle burada.',
      );
      expect(v.suspicious, isFalse);
    });
    test('hyphen + line break left unmerged in clean gives no false positive '
        '(device finding p41/p415/p174)', () {
      final v = assessClean(
        raw:
            'Cihazın beyni ya da lim-\nbik beyin vardır ve karar verir '
            'burada hemen.',
        clean:
            'Cihazın beyni ya da lim-\nbik beyin vardır ve karar verir '
            'burada hemen.',
      );
      expect(v.suspicious, isFalse);
      expect(v.reasons, isEmpty);
    });
    test(
      'hyphen + space line-break pattern (clean not merged) gives no false positive',
      () {
        final v = assessClean(
          raw:
              'Bilinçaltından -fiziksel ya da psikolojik- olarak anne '
              'çok önemlidir bugün.',
          clean:
              'Bilinçaltından -fiziksel ya da psikolojik- olarak anne '
              'çok önemlidir bugün.',
        );
        expect(v.suspicious, isFalse);
        expect(v.reasons, isEmpty);
      },
    );
    test(
      'Turkish special letters (ğüşıöçİ) are NOT counted as odd characters',
      () {
        final v = assessClean(
          raw: 'Şükür, gönül ve ışık üzerine düşünceler çoğalıyordu.',
          clean: 'Şükür, gönül ve ışık üzerine düşünceler çoğalıyordu.',
        );
        expect(v.suspicious, isFalse);
      },
    );
  });

  group('assessClean — SUSPICIOUS', () {
    test('sentence deleted -> deletion reason', () {
      final v = assessClean(
        raw:
            'Pericles meclise hitap etti. Savaş kararını anlattı. '
            'Halk dikkatle dinliyordu.',
        clean: 'Pericles meclise hitap etti. Halk dikkatle dinliyordu.',
      );
      expect(v.suspicious, isTrue);
      expect(v.reasons.join(','), contains('silme'));
    });
    // REGRESSION PIN: a real insertion must still be caught (the hyphen-merge fix
    // must not mask it -- see the hyphen-joined tests above).
    test('words not present in raw were inserted -> insertion reason', () {
      final v = assessClean(
        raw: 'Atina kenti güzelleşiyordu.',
        clean: 'Atina kenti her geçen gün daha da fazla güzelleşiyordu.',
      );
      expect(v.suspicious, isTrue);
      expect(v.reasons.join(','), contains('ekleme'));
    });
    test('word fully replaced -> replacement reason', () {
      final v = assessClean(
        raw: 'Atina ordusu savaşa hazırlanıyordu.',
        clean: 'Sparta ordusu savaşa hazırlanıyordu.',
      );
      expect(v.suspicious, isTrue);
      expect(v.reasons.join(','), contains('degisim'));
    });
    test('length deviated by more than 15% (shortened) -> length reason', () {
      final raw = List.filled(40, 'kelime').join(' ');
      final clean = List.filled(20, 'kelime').join(' ');
      final v = assessClean(raw: raw, clean: clean);
      expect(v.suspicious, isTrue);
      expect(v.reasons.join(','), contains('uzunluk'));
    });
    test('replacement/odd character in output -> character reason', () {
      final v = assessClean(
        raw: 'Temiz bir paragraf burada.',
        clean: 'Temiz bir paragra\u{FFFD} burada.',
      );
      expect(v.suspicious, isTrue);
      expect(v.reasons.join(','), contains('karakter'));
    });
    test('Cyrillic letters leaked -> character reason', () {
      final v = assessClean(
        raw: 'Akşam olunca herkes evine gitti.',
        clean: 'Akşam olunca herkes evine gitti. Спасибо.',
      );
      expect(v.suspicious, isTrue);
      expect(v.reasons.join(','), contains('karakter'));
    });
    test('empty output is suspicious', () {
      final v = assessClean(raw: 'Dolu bir sayfa metni.', clean: '');
      expect(v.suspicious, isTrue);
    });
    test('multiple reasons are reported together', () {
      final raw = List.filled(40, 'sözcük').join(' ');
      final v = assessClean(raw: raw, clean: 'kısa \u{FFFD} çıktı');
      expect(v.suspicious, isTrue);
      expect(v.reasons.length, greaterThanOrEqualTo(2));
    });
  });
}
