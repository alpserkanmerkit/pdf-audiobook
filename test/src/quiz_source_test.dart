// R3 pure-layer test (oracle). Two quiz_source.dart functions are covered at 100% branch level
// (quizSourcePageOrder + hasEnoughQuizText). GREEN: pure layer ready.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/quiz_source.dart';

void main() {
  group('quizSourcePageOrder', () {
    test('currentPage 170 -> [170,169,...,1] (backwards)', () {
      final order = quizSourcePageOrder(currentPage: 170);
      expect(order, hasLength(170));
      expect(order.first, 170);
      expect(order.last, 1);
      // Continuous descending order.
      expect(order.take(3).toList(), [170, 169, 168]);
    });

    test('currentPage 1 -> [1]', () {
      expect(quizSourcePageOrder(currentPage: 1), [1]);
    });

    test('currentPage < 1 -> reasonable clamp [1] (not empty)', () {
      // currentPage < 1 branch.
      expect(quizSourcePageOrder(currentPage: 0), [1]);
      expect(quizSourcePageOrder(currentPage: -5), [1]);
    });
  });

  group('hasEnoughQuizText', () {
    test('short text -> false', () {
      expect(hasEnoughQuizText('short'), isFalse);
    });

    test('600 characters (default threshold) -> true', () {
      expect(hasEnoughQuizText('x' * 600), isTrue);
    });

    test('boundary: 599 false, 600 true (default min)', () {
      expect(hasEnoughQuizText('x' * 599), isFalse);
      expect(hasEnoughQuizText('x' * 600), isTrue);
    });

    test('trimmed: surrounding whitespace is not counted', () {
      // 600 'x' + surrounding whitespace -> 600 after trim -> true.
      expect(hasEnoughQuizText('   ${'x' * 600}   '), isTrue);
      // 599 'x' + surrounding whitespace -> 599 after trim -> false.
      expect(hasEnoughQuizText('   ${'x' * 599}   '), isFalse);
    });

    test('with a custom min threshold', () {
      expect(hasEnoughQuizText('x' * 5, min: 10), isFalse);
      expect(hasEnoughQuizText('x' * 10, min: 10), isTrue);
    });
  });
}
