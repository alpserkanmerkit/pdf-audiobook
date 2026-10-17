// Oracle RED test (2026-10-06, private lesson D2N: persistent progress).
// Spec: internal design note §7.7.
//
// Pinned contract (pure logic):
// - encode -> decode gives the same state (part, total, correct/half/wrong).
// - A corrupt record never throws; it returns null (the caller silently starts over).
// - The key is specific to the book + the chapter's page range.
// - TutorSession(startIndex:) starts the lesson from that part; out of range -> error.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/tutor/lesson_split.dart';
import 'package:sesli_kitap/src/tutor/tutor_progress.dart';
import 'package:sesli_kitap/src/tutor/tutor_session.dart';

List<LessonPart> _parts(int n) => [
  for (var i = 0; i < n; i++)
    LessonPart(index: i, fromPage: 10 + i, toPage: 10 + i, text: 'text $i'),
];

String _json(Map<String, Object?> m) => jsonEncode(m);

Map<String, Object?> _valid() => {
  'v': 1,
  'part': 2,
  'total': 5,
  'dogru': 3,
  'yarim': 1,
  'yanlis': 2,
};

void main() {
  group('encode/decode', () {
    test('save -> load gives the same state', () {
      const p = TutorProgress(
        partIndex: 2,
        totalParts: 5,
        correct: 3,
        half: 1,
        wrong: 2,
      );
      final back = decodeTutorProgress(encodeTutorProgress(p))!;
      expect(back.partIndex, 2);
      expect(back.totalParts, 5);
      expect(back.correct, 3);
      expect(back.half, 1);
      expect(back.wrong, 2);
    });

    test('record format matches the spec JSON fields', () {
      const p = TutorProgress(
        partIndex: 1,
        totalParts: 3,
        correct: 0,
        half: 2,
        wrong: 1,
      );
      expect(jsonDecode(encodeTutorProgress(p)), {
        'v': 1,
        'part': 1,
        'total': 3,
        'dogru': 0,
        'yarim': 2,
        'yanlis': 1,
      });
    });

    test('a hand-written valid record is read', () {
      final p = decodeTutorProgress(_json(_valid()))!;
      expect(
        [p.partIndex, p.totalParts, p.correct, p.half, p.wrong],
        [2, 5, 3, 1, 2],
      );
    });

    test('no record (null) -> null', () {
      expect(decodeTutorProgress(null), isNull);
    });

    final bozuk = <String, String>{
      'empty text': '',
      'not JSON': '{bozuk',
      'list': '[1,2]',
      'number': '7',
      'version differs': _json({..._valid(), 'v': 2}),
      'version missing': _json({..._valid()}..remove('v')),
      'part missing': _json({..._valid()}..remove('part')),
      'total missing': _json({..._valid()}..remove('total')),
      'correct missing': _json({..._valid()}..remove('dogru')),
      'half missing': _json({..._valid()}..remove('yarim')),
      'wrong missing': _json({..._valid()}..remove('yanlis')),
      'part is text': _json({..._valid(), 'part': '2'}),
      'total decimal': _json({..._valid(), 'total': 5.5}),
      'correct is text': _json({..._valid(), 'dogru': 'uc'}),
      'half null': _json({..._valid(), 'yarim': null}),
      'wrong is bool': _json({..._valid(), 'yanlis': true}),
      'negative part': _json({..._valid(), 'part': -1}),
      'negative correct': _json({..._valid(), 'dogru': -1}),
      'negative half': _json({..._valid(), 'yarim': -1}),
      'negative wrong': _json({..._valid(), 'yanlis': -1}),
      'total zero': _json({..._valid(), 'part': 0, 'total': 0}),
      'part == total': _json({..._valid(), 'part': 5, 'total': 5}),
      'part > total': _json({..._valid(), 'part': 9, 'total': 5}),
    };
    for (final e in bozuk.entries) {
      test('corrupt record (${e.key}) -> null, does not throw', () {
        expect(decodeTutorProgress(e.value), isNull);
      });
    }
  });

  group('key', () {
    test('includes book hash and page range', () {
      expect(
        tutorProgressKey(bookHash: 'th1', startPage: 10, endPage: 12),
        'tutor_progress_v1_th1_10_12',
      );
    });

    test('different chapter / different book -> different key', () {
      final a = tutorProgressKey(bookHash: 'h', startPage: 1, endPage: 9);
      final b = tutorProgressKey(bookHash: 'h', startPage: 10, endPage: 19);
      final c = tutorProgressKey(bookHash: 'g', startPage: 1, endPage: 9);
      expect({a, b, c}, hasLength(3));
    });
  });

  group('TutorSession startIndex', () {
    Future<String> llm({required String system, required String user}) async =>
        jsonEncode({
          'anlatim': 'A',
          'sorular': [
            {'soru': 'S?', 'beklenen': 'B'},
          ],
        });

    test('default 0', () {
      final s = TutorSession(
        parts: _parts(3),
        llm: llm,
        bookTitle: 'K',
        chapterTitle: 'B',
      );
      expect(s.currentIndex, 0);
    });

    test('starts at the given startIndex part and loads that part', () async {
      final users = <String>[];
      final s = TutorSession(
        parts: _parts(3),
        llm: ({required system, required user}) {
          users.add(user);
          return llm(system: system, user: user);
        },
        bookTitle: 'K',
        chapterTitle: 'B',
        startIndex: 2,
      );
      expect(s.currentIndex, 2);
      expect(s.currentPart.fromPage, 12);
      await s.loadCurrentPart();
      expect(users.single, contains('Part 3/3'));
    });

    for (final bad in [-1, 3, 7]) {
      test('out-of-range startIndex ($bad) -> ArgumentError', () {
        expect(
          () => TutorSession(
            parts: _parts(3),
            llm: llm,
            bookTitle: 'K',
            chapterTitle: 'B',
            startIndex: bad,
          ),
          throwsArgumentError,
        );
      });
    }
  });
}
