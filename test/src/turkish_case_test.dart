// FAZ5 K17 (oracle RED): a locale-insensitive .toUpperCase() turns the dotted 'i'
// into 'I' in Turkish ('S. Demir' -> 'S. DEMIR'). turkishUpper must keep the
// dotted/dotless distinction: i -> İ, ı -> I; remaining characters are uppercased normally.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/turkish_case.dart';

void main() {
  test('turkishUpper: dotted i -> İ (S. Demir -> S. DEMİR)', () {
    expect(turkishUpper('S. Demir'), 'S. DEMİR');
  });

  test('turkishUpper: dotless ı -> I (ışık -> IŞIK)', () {
    expect(turkishUpper('ışık'), 'IŞIK');
  });

  test(
    'turkishUpper: mixed dotted/dotless + ASCII + other Turkish letters',
    () {
      expect(turkishUpper('iı Iİ abc'), 'İI Iİ ABC');
      expect(turkishUpper('E. Aydın'), 'E. AYDIN');
      expect(turkishUpper('M. Şahin'), 'M. ŞAHİN');
      expect(turkishUpper('çağrı öğüt'), 'ÇAĞRI ÖĞÜT');
    },
  );

  test(
    'turkishUpper: empty string and already-uppercase input stay unchanged',
    () {
      expect(turkishUpper(''), '');
      expect(turkishUpper('IŞIK'), 'IŞIK');
      expect(turkishUpper('S. DEMİR'), 'S. DEMİR');
    },
  );
}
