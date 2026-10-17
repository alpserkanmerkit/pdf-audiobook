// Oracle test (jank fix): chapter-map persistence contract (PURE, gate test).
// A 706-page map is computed once and cached; later openings read it instantly
// (the ~67s main-thread lock = "Skipped 23888 frames" is closed by this contract).
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/chapter_cache.dart';
import 'package:sesli_kitap/src/chapter_map.dart';

void main() {
  test(
    'encode/decode round-trip: null title and filled title are kept exactly',
    () {
      final chapters = [
        const Chapter(startPage: 1, endPage: 3),
        const Chapter(title: 'Birinci Bölüm', startPage: 4, endPage: 10),
      ];
      final back = decodeChapters(encodeChapters(chapters));
      expect(back.length, 2);
      expect(back[0].title, isNull);
      expect(back[0].startPage, 1);
      expect(back[0].endPage, 3);
      expect(back[1].title, 'Birinci Bölüm');
      expect(back[1].startPage, 4);
      expect(back[1].endPage, 10);
    },
  );

  test('empty list round-trip → empty list', () {
    expect(decodeChapters(encodeChapters(const [])), isEmpty);
  });

  test('Turkish title encoding survives (â ç ş)', () {
    final c = [
      const Chapter(title: 'Hikâye: çalışma', startPage: 2, endPage: 5),
    ];
    expect(decodeChapters(encodeChapters(c))[0].title, 'Hikâye: çalışma');
  });

  test('corrupt JSON/schema → FormatException (the shell regenerates)', () {
    expect(() => decodeChapters('this is never json'), throwsFormatException);
    expect(
      () => decodeChapters('{"x":1}'),
      throwsFormatException,
    ); // not a list
    expect(
      () => decodeChapters('[{"startPage":1}]'),
      throwsFormatException,
    ); // no endPage
    expect(
      () => decodeChapters('[{"startPage":"a","endPage":2}]'),
      throwsFormatException,
    ); // wrong type
    expect(
      () => decodeChapters('[{"title":5,"startPage":1,"endPage":2}]'),
      throwsFormatException,
    ); // wrong title type
  });
}
