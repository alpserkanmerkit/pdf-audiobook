// RED-once oracle test (Wave-A / PR-A): digest MODEL layer.
// Spec: internal design note §4/§6 —
// ChapterDigest/BookDigest JSON round-trip; corrupt input -> null (not an
// exception; a cache read fails softly); version field v:1.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/digest/digest_model.dart';

ChapterDigest _ch({
  int index = 0,
  String? title = 'Giris',
  int start = 13,
  int end = 26,
  int done = 14,
  String summary = 'Chapter summary.',
}) => ChapterDigest(
  chapterIndex: index,
  title: title,
  startPage: start,
  endPage: end,
  pagesProcessed: done,
  summary: summary,
);

BookDigest _book() => BookDigest(
  bookHash: '8917891e8c17a4d5',
  createdAtMs: 1751600000000,
  chapters: [_ch(), _ch(index: 1, title: null, start: 27, end: 62, done: 36)],
  bookSummary: 'Book summary.',
);

void main() {
  group('ChapterDigest JSON', () {
    test('round-trip (through jsonEncode/jsonDecode)', () {
      const c = ChapterDigest(
        chapterIndex: 6,
        title: 'Savunuculuk Yasasi',
        startPage: 207,
        endPage: 251,
        pagesProcessed: 45,
        summary: 'Theses, key examples, concepts.',
      );
      final back = ChapterDigest.fromJson(jsonDecode(jsonEncode(c.toJson())));
      expect(back, isNotNull);
      expect(back!.chapterIndex, 6);
      expect(back.title, 'Savunuculuk Yasasi');
      expect(back.startPage, 207);
      expect(back.endPage, 251);
      expect(back.pagesProcessed, 45);
      expect(back.summary, 'Theses, key examples, concepts.');
    });

    test('title null round-trip (untitled front section)', () {
      final back = ChapterDigest.fromJson(
        jsonDecode(jsonEncode(_ch(title: null).toJson())),
      );
      expect(back, isNotNull);
      expect(back!.title, isNull);
    });

    test('corrupt body -> null (not a map / empty)', () {
      expect(ChapterDigest.fromJson(null), isNull);
      expect(ChapterDigest.fromJson('text'), isNull);
      expect(ChapterDigest.fromJson(42), isNull);
      expect(ChapterDigest.fromJson(<String, dynamic>{}), isNull);
    });

    test('wrong type or missing required field -> null', () {
      final good = _ch().toJson();
      for (final field in [
        'chapterIndex',
        'startPage',
        'endPage',
        'pagesProcessed',
        'summary',
      ]) {
        final broken = Map<String, Object?>.from(good)..[field] = false;
        expect(
          ChapterDigest.fromJson(broken),
          isNull,
          reason: '$field corrupt',
        );
        final missing = Map<String, Object?>.from(good)..remove(field);
        expect(
          ChapterDigest.fromJson(missing),
          isNull,
          reason: '$field missing',
        );
      }
    });

    test('title of wrong type -> null (null excepted)', () {
      final broken = Map<String, Object?>.from(_ch().toJson())..['title'] = 42;
      expect(ChapterDigest.fromJson(broken), isNull);
    });
  });

  group('BookDigest JSON', () {
    test('encode/decode round-trip', () {
      final d = _book();
      final back = decodeBookDigest(encodeBookDigest(d));
      expect(back, isNotNull);
      expect(back!.bookHash, '8917891e8c17a4d5');
      expect(back.createdAtMs, 1751600000000);
      expect(back.bookSummary, 'Book summary.');
      expect(back.chapters, hasLength(2));
      expect(back.chapters[0].title, 'Giris');
      expect(back.chapters[1].title, isNull);
      expect(back.chapters[1].startPage, 27);
      expect(back.chapters[1].pagesProcessed, 36);
    });

    test('version field is written (v:1)', () {
      expect(_book().toJson()['v'], 1);
      expect(BookDigest.schemaVersion, 1);
    });

    test('empty chapter list is valid (coverage layer reports the gap)', () {
      final d = BookDigest(
        bookHash: 'h',
        createdAtMs: 0,
        chapters: const [],
        bookSummary: 'k',
      );
      final back = decodeBookDigest(encodeBookDigest(d));
      expect(back, isNotNull);
      expect(back!.chapters, isEmpty);
    });

    test('corrupt JSON text -> null', () {
      expect(decodeBookDigest('corrupt { json'), isNull);
      expect(decodeBookDigest(''), isNull);
      expect(decodeBookDigest('[]'), isNull);
      expect(decodeBookDigest('"text"'), isNull);
    });

    test('fromJson non-map -> null', () {
      expect(BookDigest.fromJson(null), isNull);
      expect(BookDigest.fromJson(<Object?>[]), isNull);
    });

    test('version mismatch or missing -> null', () {
      final good = _book().toJson();
      expect(
        BookDigest.fromJson(Map<String, Object?>.from(good)..['v'] = 2),
        isNull,
      );
      expect(
        BookDigest.fromJson(Map<String, Object?>.from(good)..remove('v')),
        isNull,
      );
    });

    test('wrong type or missing required field -> null', () {
      final good = _book().toJson();
      for (final field in [
        'bookHash',
        'createdAtMs',
        'chapters',
        'bookSummary',
      ]) {
        final broken = Map<String, Object?>.from(good)..[field] = false;
        expect(BookDigest.fromJson(broken), isNull, reason: '$field corrupt');
        final missing = Map<String, Object?>.from(good)..remove(field);
        expect(BookDigest.fromJson(missing), isNull, reason: '$field missing');
      }
    });

    test(
      'one corrupt chapter element drops the WHOLE book (mechanical integrity)',
      () {
        // Coverage proof relies on a complete chain: if one chapter is corrupt, the cache
        // record is untrusted -> null (no partial acceptance; it is regenerated).
        final good = _book().toJson();
        final broken = Map<String, Object?>.from(good)
          ..['chapters'] = <Object?>[42];
        expect(BookDigest.fromJson(broken), isNull);
      },
    );

    test('chapters list is unmodifiable', () {
      final back = decodeBookDigest(encodeBookDigest(_book()))!;
      expect(() => back.chapters.add(_ch()), throwsUnsupportedError);
    });
  });
}
