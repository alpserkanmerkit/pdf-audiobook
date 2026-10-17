// Oracle RED (2026-06-13) — LLM skeleton pure layer.
// Spike evidence (internal design note): v4-flash
// produced a clean 20-chapter PDF-indexed skeleton from 706 headers (OCR merged, names clean,
// ordinal-number distinction in the prompt). This layer is PURE: input preparation + JSON contract parsing.
// The LLM call and its correctness are IO/e2e (llm_skeleton.dart, no gate test).
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/chapter_map.dart';
import 'package:sesli_kitap/src/chapter_skeleton.dart';

void main() {
  group(
    'stripHeaderPageNumber — strip the page number from a running header',
    () {
      test(
        'verso "12 • İnsan Doğasının Yasaları" → book title (leading number + separator)',
        () {
          expect(
            stripHeaderPageNumber('12 • İnsan Doğasının Yasaları'),
            'İnsan Doğasının Yasaları',
          );
        },
      );
      test('recto "Giriş • 13" → "Giriş" (trailing separator + number)', () {
        expect(stripHeaderPageNumber('Giriş • 13'), 'Giriş');
      });
      test('recto "Giriş »15" (attached) → "Giriş"', () {
        expect(stripHeaderPageNumber('Giriş »15'), 'Giriş');
      });
      test('real text without a separator is left untouched', () {
        expect(
          stripHeaderPageNumber('12 Eylul sabahi kent uyaniyordu'),
          '12 Eylul sabahi kent uyaniyordu',
        );
      });
      test('empty → empty', () {
        expect(stripHeaderPageNumber(''), '');
      });
    },
  );

  group('buildSkeletonInput — LLM input format', () {
    test('sNN: header (page number stripped); headerless page is empty', () {
      final input = buildSkeletonInput(const [
        PageHeaderEntry(page: 15, header: 'Giriş • 13'),
        PageHeaderEntry(page: 16, header: '14 • İnsan Doğasının Yasaları'),
        PageHeaderEntry(page: 17),
      ]);
      expect(input, contains('s15: Giriş'));
      expect(input, contains('s16: İnsan Doğasının Yasaları'));
      expect(input, contains('s17:'));
      // the printed page number inside the header must NOT leak into the input
      expect(input.contains('Giriş • 13'), isFalse);
    });
  });

  group('parseSkeletonResponse — JSON contract + validation', () {
    const total = 706;
    test('valid JSON → Chapter list', () {
      final ch = parseSkeletonResponse(
        '{"chapters":[{"title":"Giriş","startPage":15,"endPage":26},'
        '{"title":"Mantıksızlık Yasası","startPage":27,"endPage":61}]}',
        totalPages: total,
      );
      expect(ch, hasLength(2));
      expect(ch[0].title, 'Giriş');
      expect(ch[0].startPage, 15);
      expect(ch[1].endPage, 61);
    });
    test('``` fence wrapped → stripped', () {
      final ch = parseSkeletonResponse(
        '```json\n{"chapters":[{"title":"A","startPage":1,"endPage":5}]}\n```',
        totalPages: total,
      );
      expect(ch, hasLength(1));
    });
    // K1 (PHASE3b RED, 2026-07-02): a single-line fence today falls into substring(0,-1)
    // RangeError — the contract DOES tolerate the fence (same semantics as the
    // study_questions contract: ```json / plain ``` / single-line).
    test(
      'single-line fence (```json {...} ```) → stripped, NO RangeError (K1)',
      () {
        final ch = parseSkeletonResponse(
          '```json {"chapters":[{"title":"A","startPage":1,"endPage":5}]} ```',
          totalPages: total,
        );
        expect(ch, hasLength(1));
        expect(ch[0].title, 'A');
      },
    );
    test('closing fence on the same line as the JSON → stripped (K1)', () {
      final ch = parseSkeletonResponse(
        '```json\n{"chapters":[{"title":"A","startPage":1,"endPage":5}]} ```',
        totalPages: total,
      );
      expect(ch, hasLength(1));
    });
    test('missing closing fence → still parsed (no negative index)', () {
      final ch = parseSkeletonResponse(
        '```json\n{"chapters":[{"title":"A","startPage":1,"endPage":5}]}',
        totalPages: total,
      );
      expect(ch, hasLength(1));
    });
    test(
      'corrupt JSON inside a single-line fence → SkeletonParseException',
      () {
        expect(
          () => parseSkeletonResponse('```json {bozuk ```', totalPages: total),
          throwsA(isA<SkeletonParseException>()),
        );
      },
    );
    test('returned list is unmodifiable', () {
      final ch = parseSkeletonResponse(
        '{"chapters":[{"title":"A","startPage":1,"endPage":5}]}',
        totalPages: total,
      );
      expect(
        () => ch.add(const Chapter(title: 'x', startPage: 9, endPage: 9)),
        throwsUnsupportedError,
      );
    });
    test('corrupt JSON → SkeletonParseException', () {
      expect(
        () => parseSkeletonResponse('{bozuk', totalPages: total),
        throwsA(isA<SkeletonParseException>()),
      );
    });
    test('no "chapters" key → exception', () {
      expect(
        () => parseSkeletonResponse('{"x":[]}', totalPages: total),
        throwsA(isA<SkeletonParseException>()),
      );
    });
    test(
      'empty chapters → exception (meaningless skeleton, §13.5 empty set)',
      () {
        expect(
          () => parseSkeletonResponse('{"chapters":[]}', totalPages: total),
          throwsA(isA<SkeletonParseException>()),
        );
      },
    );
    test('endPage > totalPages → exception', () {
      expect(
        () => parseSkeletonResponse(
          '{"chapters":[{"title":"A","startPage":1,"endPage":999}]}',
          totalPages: total,
        ),
        throwsA(isA<SkeletonParseException>()),
      );
    });
    test('startPage < 1 → exception', () {
      expect(
        () => parseSkeletonResponse(
          '{"chapters":[{"title":"A","startPage":0,"endPage":5}]}',
          totalPages: total,
        ),
        throwsA(isA<SkeletonParseException>()),
      );
    });
    test('startPage > endPage → exception', () {
      expect(
        () => parseSkeletonResponse(
          '{"chapters":[{"title":"A","startPage":10,"endPage":5}]}',
          totalPages: total,
        ),
        throwsA(isA<SkeletonParseException>()),
      );
    });
    test('out-of-order / overlapping chapters → exception', () {
      expect(
        () => parseSkeletonResponse(
          '{"chapters":[{"title":"A","startPage":1,"endPage":10},'
          '{"title":"B","startPage":5,"endPage":20}]}',
          totalPages: total,
        ),
        throwsA(isA<SkeletonParseException>()),
      );
    });
    test('empty title → exception', () {
      expect(
        () => parseSkeletonResponse(
          '{"chapters":[{"title":"  ","startPage":1,"endPage":5}]}',
          totalPages: total,
        ),
        throwsA(isA<SkeletonParseException>()),
      );
    });
    test('title is not a string → exception', () {
      expect(
        () => parseSkeletonResponse(
          '{"chapters":[{"title":5,"startPage":1,"endPage":5}]}',
          totalPages: total,
        ),
        throwsA(isA<SkeletonParseException>()),
      );
    });
  });
}
