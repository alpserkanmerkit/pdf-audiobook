// A3 RED tests (oracle): pure layer for the in-page audio position.
// Field finding on resume: the page was remembered, but the audio position
// was never saved. This file pins the parseAudioPos/formatAudioPos round-trip
// and the shouldResumeAt rule (same page + >=3s threshold).
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/audio_position.dart';

void main() {
  group('parseAudioPos', () {
    test('parses a valid "page:ms" string', () {
      final r = parseAudioPos('7:12345');
      expect(r, isNotNull);
      expect(r!.page, 7);
      expect(r.pos, const Duration(milliseconds: 12345));
    });

    test('null input -> null', () {
      expect(parseAudioPos(null), isNull);
    });

    test('empty string -> null', () {
      expect(parseAudioPos(''), isNull);
    });

    test('not two parts -> null', () {
      expect(parseAudioPos('7'), isNull);
      expect(parseAudioPos('7:12:34'), isNull);
    });

    test('non-numeric part -> null', () {
      expect(parseAudioPos('abc:123'), isNull);
      expect(parseAudioPos('7:abc'), isNull);
    });

    test('page < 1 -> null', () {
      expect(parseAudioPos('0:1000'), isNull);
      expect(parseAudioPos('-1:1000'), isNull);
    });

    test('negative ms -> null', () {
      expect(parseAudioPos('7:-500'), isNull);
    });

    test('ms zero is accepted (page-start record is a valid shape)', () {
      final r = parseAudioPos('3:0');
      expect(r, isNotNull);
      expect(r!.pos, Duration.zero);
    });
  });

  group('formatAudioPos + round-trip', () {
    test('formats and parses back (round-trip)', () {
      final formatted = formatAudioPos(
        page: 12,
        pos: const Duration(milliseconds: 98765),
      );
      expect(formatted, '12:98765');
      final parsed = parseAudioPos(formatted);
      expect(parsed, (page: 12, pos: const Duration(milliseconds: 98765)));
    });
  });

  group('shouldResumeAt', () {
    test('different page -> null', () {
      final r = shouldResumeAt(
        savedPage: 3,
        currentPage: 4,
        savedPos: const Duration(seconds: 10),
      );
      expect(r, isNull);
    });

    test('below threshold (<3s) -> null', () {
      final r = shouldResumeAt(
        savedPage: 3,
        currentPage: 3,
        savedPos: const Duration(seconds: 2),
      );
      expect(r, isNull);
    });

    test('exactly at threshold (3s) -> position returned (>= rule)', () {
      final r = shouldResumeAt(
        savedPage: 3,
        currentPage: 3,
        savedPos: const Duration(seconds: 3),
      );
      expect(r, const Duration(seconds: 3));
    });

    test('normal case: same page + above threshold -> position returned', () {
      final r = shouldResumeAt(
        savedPage: 5,
        currentPage: 5,
        savedPos: const Duration(seconds: 45, milliseconds: 250),
      );
      expect(r, const Duration(seconds: 45, milliseconds: 250));
    });

    test('zero position (page start) -> null (below threshold)', () {
      final r = shouldResumeAt(
        savedPage: 1,
        currentPage: 1,
        savedPos: Duration.zero,
      );
      expect(r, isNull);
    });
  });
}
