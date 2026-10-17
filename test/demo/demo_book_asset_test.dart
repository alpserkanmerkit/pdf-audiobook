// Demo sample book (Ömer Seyfettin "Üç Hikâye"): asset integrity.
// The PDF is not regenerated in CI (the Chromium version changes the bytes); the
// committed binary + KAYNAK.txt + this test (page count / text / attribution) pin its integrity.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/io/pdf_text.dart';

void main() {
  final pdf = File('assets/demo/uc_hikaye.pdf');
  final source = File('assets/demo/KAYNAK.txt');

  test('PDF has 21 pages and is under 200 KB', () {
    expect(
      pdf.existsSync(),
      isTrue,
      reason: 'assets/demo/uc_hikaye.pdf is missing',
    );
    final bytes = pdf.readAsBytesSync();
    expect(bytes.length, lessThan(200 * 1024));
    expect(pdfPageCount(bytes), 21);
  });

  test(
    'the first pages of the three stories are in the right place (1 / 8 / 15)',
    () {
      final bytes = pdf.readAsBytesSync();
      expect(extractPageText(bytes, 1), contains('Ahırın avlusunda'));
      expect(extractPageText(bytes, 8), contains("Akdeniz'in"));
      expect(extractPageText(bytes, 15), contains('Serin ve karanlık eylül'));
    },
  );

  test('Turkish characters are extracted without corruption', () {
    final bytes = pdf.readAsBytesSync();
    final all = [
      for (var p = 1; p <= 21; p++) extractPageText(bytes, p),
    ].join('\n');
    for (final ch in ['ğ', 'ş', 'ı', 'İ', 'ç', 'ö', 'ü']) {
      expect(all, contains(ch), reason: '"$ch" could not be extracted');
    }
    expect(all, isNot(contains('�')));
  });

  test('KAYNAK.txt states the public-domain basis and the source', () {
    expect(source.existsSync(), isTrue, reason: 'KAYNAK.txt is missing');
    final text = source.readAsStringSync();
    expect(text, contains('kamu malı'));
    expect(text, contains('tr.wikisource.org'));
    expect(text, contains('Ömer Seyfettin'));
  });

  test('pubspec declares the assets/demo/ directory as an asset', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/demo/'));
  });
}
