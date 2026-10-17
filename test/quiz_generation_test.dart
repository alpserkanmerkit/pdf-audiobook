// Oracle (pure-layer gate test): LLM 4-choice quiz generation prompt + parse
// contract. No real network -- only buildQuizPrompt / parseQuizResponse.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/quiz_generation.dart';

void main() {
  group('parseQuizResponse', () {
    String jsonWith(List<Map<String, Object?>> qs) =>
        jsonEncode({'questions': qs});

    test(
      'valid response -> list of MultipleChoiceQuestion (fields + source)',
      () {
        final content = jsonWith([
          {
            'soru': '  What is the main theme of the book?  ',
            'secenekler': ['Space', 'Light', 'Rhythm', 'Balance'],
            'dogruIndex': 2,
          },
        ]);
        final qs = parseQuizResponse(content, kaynak: 'Test Book');
        expect(qs, hasLength(1));
        expect(qs.first.soru, 'What is the main theme of the book?'); // trim
        expect(qs.first.secenekler, ['Space', 'Light', 'Rhythm', 'Balance']);
        expect(qs.first.dogruIndex, 2);
        expect(qs.first.kaynak, 'Test Book');
      },
    );

    test('numeric choices are converted to strings', () {
      final content = jsonWith([
        {
          'soru': 'How many?',
          'secenekler': [1, 2, 3, 4],
          'dogruIndex': 0,
        },
      ]);
      final qs = parseQuizResponse(content, kaynak: 'k');
      expect(qs.first.secenekler, ['1', '2', '3', '4']);
    });

    test('invalid JSON -> QuizParseException', () {
      expect(
        () => parseQuizResponse('{broken', kaynak: 'k'),
        throwsA(isA<QuizParseException>()),
      );
    });

    test('root value is not an object (array) -> throws', () {
      expect(
        () => parseQuizResponse('[]', kaynak: 'k'),
        throwsA(isA<QuizParseException>()),
      );
    });

    test('no questions field -> throws', () {
      expect(
        () => parseQuizResponse(jsonEncode({'x': 1}), kaynak: 'k'),
        throwsA(isA<QuizParseException>()),
      );
    });

    test('questions empty list -> throws', () {
      expect(
        () => parseQuizResponse(jsonWith([]), kaynak: 'k'),
        throwsA(isA<QuizParseException>()),
      );
    });

    test('question item is not an object -> throws', () {
      expect(
        () => parseQuizResponse(
          jsonEncode({
            'questions': ['plain string'],
          }),
          kaynak: 'k',
        ),
        throwsA(isA<QuizParseException>()),
      );
    });

    test('question text is empty/not a string -> throws', () {
      expect(
        () => parseQuizResponse(
          jsonWith([
            {
              'soru': '   ',
              'secenekler': ['a', 'b', 'c', 'd'],
              'dogruIndex': 0,
            },
          ]),
          kaynak: 'k',
        ),
        throwsA(isA<QuizParseException>()),
      );
    });

    test('choices are not 4 -> throws', () {
      expect(
        () => parseQuizResponse(
          jsonWith([
            {
              'soru': 's',
              'secenekler': ['a', 'b', 'c'],
              'dogruIndex': 0,
            },
          ]),
          kaynak: 'k',
        ),
        throwsA(isA<QuizParseException>()),
      );
    });

    test('dogruIndex out of range -> throws', () {
      expect(
        () => parseQuizResponse(
          jsonWith([
            {
              'soru': 's',
              'secenekler': ['a', 'b', 'c', 'd'],
              'dogruIndex': 4,
            },
          ]),
          kaynak: 'k',
        ),
        throwsA(isA<QuizParseException>()),
      );
    });

    test('dogruIndex is not an int -> throws', () {
      expect(
        () => parseQuizResponse(
          jsonWith([
            {
              'soru': 's',
              'secenekler': ['a', 'b', 'c', 'd'],
              'dogruIndex': 'x',
            },
          ]),
          kaynak: 'k',
        ),
        throwsA(isA<QuizParseException>()),
      );
    });

    test('QuizParseException.toString includes the reason', () {
      expect(QuizParseException('something').toString(), contains('something'));
    });
  });

  group('buildQuizPrompt', () {
    test('includes count and the text', () {
      final p = buildQuizPrompt(bookText: 'sample book text', count: 5);
      expect(p, contains('5'));
      expect(p, contains('sample book text'));
      expect(p, contains('questions'));
      expect(p, contains('dogruIndex'));
    });

    test('text longer than 8000 characters is clipped', () {
      final long = 'a' * 9000;
      final p = buildQuizPrompt(bookText: long, count: 3);
      // Fixed prompt part + at most 8000 characters of text; 9000 must not pass in full.
      expect(p.contains('a' * 8000), isTrue);
      expect(p.contains('a' * 8001), isFalse);
    });
  });
}
