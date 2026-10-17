// Slice-2a RED test (oracle). lib/src/library/library_store.dart is written by a worker.
// PURE book store: Book model + seed (README 8) + progress mutation + JSON encode/decode.
// Follows the highlight_store.dart pattern (encode/decode round-trip); target 100% coverage.
// FAZ2c (K8/K26): per-record decode tolerance + coverIndex clamp contract.
// FAZ-W2: hash + filePath added to Book (persistence fields of the book-add flow).
// An old seed record (NO hash/filePath) must decode backward-compatibly (K8 spirit:
// missing field = default, the record is NOT skipped); if the field IS present, a wrong type = broken record.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/library/library_store.dart';

void main() {
  group('seedBooks (exact match of README 8)', () {
    test('6 books, first is "Sessizliğin Mimarisi"', () {
      final books = seedBooks();
      expect(books, hasLength(6));
      expect(books.first.title, 'Sessizliğin Mimarisi');
      expect(books.first.author, 'D. Karaca');
      expect(books.first.progressPercent, 38);
      expect(books.first.totalPages, 318);
    });
    test(
      'each book has a unique id + valid progress (0..100) + cover index',
      () {
        final books = seedBooks();
        final ids = books.map((b) => b.id).toSet();
        expect(ids, hasLength(6), reason: 'id is unique');
        for (final b in books) {
          expect(b.progressPercent, inInclusiveRange(0, 100));
          expect(b.coverIndex, inInclusiveRange(0, 5));
        }
      },
    );
  });

  group('encode/decode round-trip', () {
    test('seed -> encode -> decode is identical', () {
      final books = seedBooks();
      final restored = decodeBooks(encodeBooks(books));
      expect(restored, hasLength(books.length));
      for (var i = 0; i < books.length; i++) {
        expect(restored[i].id, books[i].id);
        expect(restored[i].title, books[i].title);
        expect(restored[i].progressPercent, books[i].progressPercent);
        expect(restored[i].totalPages, books[i].totalPages);
      }
    });
    test('empty list -> encode -> decode is empty', () {
      expect(decodeBooks(encodeBooks(const [])), isEmpty);
    });
    test('broken JSON -> empty list (no crash)', () {
      expect(decodeBooks('this is not json'), isEmpty);
    });
    test('if root is not a list -> empty list (no crash)', () {
      expect(decodeBooks('{"book": 1}'), isEmpty);
    });
  });

  group('decodeBooks — per-record tolerance (K8)', () {
    test(
      'one broken record does not delete the library: 2 valid + 1 broken -> 2',
      () {
        final valid = seedBooks().take(2).toList();
        final entries = <Object?>[
          valid[0].toJson(),
          <String, Object?>{
            'id': 'broken',
            'title': 'Broken Record',
            'author': 'X',
            'chapterLabel': 'B1',
            'progressPercent': 'forty', // not an int -> broken record
            'totalPages': 100,
            'coverIndex': 0,
          },
          valid[1].toJson(),
        ];
        final decoded = decodeBooks(jsonEncode(entries));
        expect(
          decoded,
          hasLength(2),
          reason: 'broken one is skipped, the rest is kept',
        );
        expect(decoded.map((b) => b.id), [valid[0].id, valid[1].id]);
      },
    );

    test('non-map list element is skipped, the rest is kept', () {
      final b = seedBooks().first;
      final decoded = decodeBooks(jsonEncode([42, b.toJson()]));
      expect(decoded, hasLength(1));
      expect(decoded.single.id, b.id);
    });
  });

  group('Book.fromJson — coverIndex clamp (K26)', () {
    test('out-of-range coverIndex is clamped into 0..5', () {
      final json = seedBooks().first.toJson();
      json['coverIndex'] = 99;
      expect(Book.fromJson(json).coverIndex, 5, reason: 'kCovers 6 covers');
      json['coverIndex'] = -3;
      expect(Book.fromJson(json).coverIndex, 0);
    });

    test('valid coverIndex is kept as is', () {
      final json = seedBooks().first.toJson();
      json['coverIndex'] = 4;
      expect(Book.fromJson(json).coverIndex, 4);
    });
  });

  group('progress mutation (copyWith)', () {
    test('withProgress new percent, others kept', () {
      final b = seedBooks().first;
      final updated = b.withProgress(72);
      expect(updated.progressPercent, 72);
      expect(updated.title, b.title);
      expect(updated.id, b.id);
      expect(
        b.progressPercent,
        38,
        reason: 'original does not change (immutable)',
      );
    });
    test('withProgress clamps outside 0..100', () {
      final b = seedBooks().first;
      expect(b.withProgress(150).progressPercent, 100);
      expect(b.withProgress(-5).progressPercent, 0);
    });
  });

  group('Book.hash / Book.filePath (FAZ-W2 book-add fields)', () {
    test(
      'new book: hash + filePath passed via constructor, toJson carries them',
      () {
        const b = Book(
          id: 'wh1',
          title: 'New Book',
          author: '',
          chapterLabel: '',
          progressPercent: 0,
          totalPages: 3,
          coverIndex: 0,
          hash: 'abc123',
          filePath: '/tmp/books/abc123.pdf',
        );
        expect(b.hash, 'abc123');
        expect(b.filePath, '/tmp/books/abc123.pdf');
        final json = b.toJson();
        expect(json['hash'], 'abc123');
        expect(json['filePath'], '/tmp/books/abc123.pdf');
      },
    );

    test(
      'if hash/filePath not given, default is empty string (for backward compatibility)',
      () {
        final b = seedBooks().first;
        expect(b.hash, isEmpty);
        expect(b.filePath, isEmpty);
      },
    );

    test('encode -> decode: hash + filePath preserved exactly', () {
      const b = Book(
        id: 'wh2',
        title: 'T',
        author: 'A',
        chapterLabel: 'B1',
        progressPercent: 0,
        totalPages: 5,
        coverIndex: 1,
        hash: 'deadbeef01234567',
        filePath: '/data/books/deadbeef01234567.pdf',
      );
      final restored = decodeBooks(encodeBooks([b])).single;
      expect(restored.hash, 'deadbeef01234567');
      expect(restored.filePath, '/data/books/deadbeef01234567.pdf');
    });

    test(
      'OLD seed-style record (hash/filePath fields NOT PRESENT AT ALL): record is not skipped, '
      'decoded with empty-string defaults (backward compatibility, K8 spirit)',
      () {
        final legacyJson = seedBooks().first.toJson()
          ..remove('hash')
          ..remove('filePath');
        final decoded = decodeBooks(jsonEncode([legacyJson]));
        expect(
          decoded,
          hasLength(1),
          reason:
              'a record with a missing field must NOT be skipped (new field = backward compatibility)',
        );
        expect(decoded.single.hash, isEmpty);
        expect(decoded.single.filePath, isEmpty);
        expect(decoded.single.title, seedBooks().first.title);
      },
    );

    test(
      'if hash has the WRONG TYPE the record is considered broken and skipped (K8 consistency)',
      () {
        final valid = seedBooks().first.toJson();
        final broken = seedBooks()[1].toJson()..['hash'] = 12345; // not an int
        final decoded = decodeBooks(jsonEncode([valid, broken]));
        expect(decoded, hasLength(1), reason: 'wrong-typed hash -> skipped');
        expect(decoded.single.id, seedBooks().first.id);
      },
    );

    test(
      'if filePath has the WRONG TYPE the record is considered broken and skipped',
      () {
        final valid = seedBooks().first.toJson();
        final broken = seedBooks()[1].toJson()..['filePath'] = false;
        final decoded = decodeBooks(jsonEncode([valid, broken]));
        expect(decoded, hasLength(1));
        expect(decoded.single.id, seedBooks().first.id);
      },
    );
  });

  group('removeBookAt (delete book -- index-based)', () {
    test(
      'book at the given position is removed, order of the rest is kept',
      () {
        final books = seedBooks();
        final updated = removeBookAt(books, 2);
        expect(updated, hasLength(books.length - 1));
        expect(updated.map((b) => b.id), isNot(contains(books[2].id)));
        expect(updated.map((b) => b.id).toList(), [
          for (var i = 0; i < books.length; i++)
            if (i != 2) books[i].id,
        ]);
      },
    );

    test('out-of-range index (negative or >= length) -> list content '
        'is returned unchanged', () {
      final books = seedBooks();
      final ids = books.map((b) => b.id).toList();
      expect(removeBookAt(books, -1).map((b) => b.id).toList(), ids);
      expect(removeBookAt(books, books.length).map((b) => b.id).toList(), ids);
    });

    test('empty list -> empty list', () {
      expect(removeBookAt(const [], 0), isEmpty);
    });

    test(
      'if TWO records share the SAME id/hash, ONLY the touched index is removed -- '
      'the other survives (review-finding-2: id matching must NOT delete ALL of them)',
      () {
        const dup1 = Book(
          id: 'ortak-hash',
          title: 'First Card',
          author: '',
          chapterLabel: '',
          progressPercent: 0,
          totalPages: 10,
          coverIndex: 0,
          hash: 'ortak-hash',
          filePath: '/data/books/ortak-hash.pdf',
        );
        const dup2 = Book(
          id: 'ortak-hash',
          title: 'Second Card',
          author: '',
          chapterLabel: '',
          progressPercent: 0,
          totalPages: 10,
          coverIndex: 1,
          hash: 'ortak-hash',
          filePath: '/data/books/ortak-hash.pdf',
        );
        final updated = removeBookAt([dup1, dup2], 0);
        expect(updated, hasLength(1));
        expect(
          updated.single.title,
          'Second Card',
          reason: 'only index 0 should go, the shared id must not delete both',
        );
      },
    );
  });

  group('Book.language (Phase 2 -- language field)', () {
    test(
      'if language is not given, default is "tr" (backward compatibility)',
      () {
        final b = seedBooks().first;
        expect(b.language, 'tr');
      },
    );

    test('new book: language passed via constructor, toJson carries it', () {
      const b = Book(
        id: 'l1',
        title: 'T',
        author: '',
        chapterLabel: '',
        progressPercent: 0,
        totalPages: 3,
        coverIndex: 0,
        language: 'en',
      );
      expect(b.language, 'en');
      expect(b.toJson()['language'], 'en');
    });

    test('encode -> decode: language preserved exactly', () {
      const b = Book(
        id: 'l2',
        title: 'T',
        author: 'A',
        chapterLabel: 'B1',
        progressPercent: 0,
        totalPages: 5,
        coverIndex: 1,
        language: 'en',
      );
      final restored = decodeBooks(encodeBooks([b])).single;
      expect(restored.language, 'en');
    });

    test(
      'OLD record (language field NOT PRESENT AT ALL): record is not skipped, "tr" '
      'default is used on decode (backward compatibility, K8 spirit)',
      () {
        final legacyJson = seedBooks().first.toJson()..remove('language');
        final decoded = decodeBooks(jsonEncode([legacyJson]));
        expect(
          decoded,
          hasLength(1),
          reason: 'a record with a missing field must NOT be skipped',
        );
        expect(decoded.single.language, 'tr');
      },
    );

    test(
      'if language has the WRONG TYPE the record is considered broken and skipped '
      '(K8 consistency)',
      () {
        final valid = seedBooks().first.toJson();
        final broken = seedBooks()[1].toJson()..['language'] = 7;
        final decoded = decodeBooks(jsonEncode([valid, broken]));
        expect(
          decoded,
          hasLength(1),
          reason: 'wrong-typed language -> skipped',
        );
        expect(decoded.single.id, seedBooks().first.id);
      },
    );
  });

  group('effectiveProgressPercent (A6-fix -- real progress, page-based)', () {
    test('computes percent from page/total-pages ratio (SAME formula as '
        '_libraryBooks in app_shell.dart)', () {
      expect(effectiveProgressPercent(page: 121, totalPages: 318), 38);
    });

    test('page null -> 0 (book never read)', () {
      expect(effectiveProgressPercent(page: null, totalPages: 318), 0);
    });

    test('totalPages <= 0 -> 0 (division-by-zero / invalid data guard)', () {
      expect(effectiveProgressPercent(page: 5, totalPages: 0), 0);
      expect(effectiveProgressPercent(page: 5, totalPages: -1), 0);
    });

    test('result is clamped to 0..100 (SAME rule as withProgress)', () {
      expect(effectiveProgressPercent(page: 999, totalPages: 100), 100);
    });

    test('page == totalPages -> 100 (finished book)', () {
      expect(effectiveProgressPercent(page: 318, totalPages: 318), 100);
    });
  });
}
