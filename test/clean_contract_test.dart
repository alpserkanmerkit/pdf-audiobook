// Oracle test (PHASE 1): JSON contract of the LLM cleanup answer (spec §5).
// Expected output: {"metin": "..."} -- nothing else. The parser tolerates the model's
// possible deviations (fence wrapping) but EXPLICITLY throws on a contract violation
// (no silent empty return: empty text cannot be spoken, so the error must be visible).
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/clean_contract.dart';

void main() {
  group('parseCleanResponse — valid inputs', () {
    test('plain JSON: returns the metin field', () {
      final r = parseCleanResponse('{"metin": "Temiz bir sayfa."}');
      expect(r.metin, 'Temiz bir sayfa.');
    });
    test('leading/trailing whitespace is tolerated', () {
      final r = parseCleanResponse('  \n{"metin": "abc"}\n  ');
      expect(r.metin, 'abc');
    });
    test('markdown fence wrapping is tolerated', () {
      final r = parseCleanResponse('```json\n{"metin": "abc"}\n```');
      expect(r.metin, 'abc');
    });
    // K1 sibling scenario (PHASE3b RED, 2026-07-02): a single-line fence today fails
    // with CleanParseException because of the fence residue; the contract DOES tolerate
    // the fence (same semantics as study_questions: single-line included).
    test('single-line fence wrapping is tolerated too (K1)', () {
      final r = parseCleanResponse('```json {"metin": "abc"} ```');
      expect(r.metin, 'abc');
    });
    test('extra fields are ignored', () {
      final r = parseCleanResponse('{"metin": "abc", "ek": 1}');
      expect(r.metin, 'abc');
    });
    test('inner whitespace and Turkish characters are kept as-is', () {
      final r = parseCleanResponse('{"metin": "farkındalık  ve  şükür"}');
      expect(r.metin, 'farkındalık  ve  şükür');
    });
  });

  group('parseCleanResponse — contract violations (CleanParseException)', () {
    test('throws on invalid JSON', () {
      expect(
        () => parseCleanResponse('this is not json'),
        throwsA(isA<CleanParseException>()),
      );
    });
    test('throws when the metin field is missing', () {
      expect(
        () => parseCleanResponse('{"text": "wrong key"}'),
        throwsA(isA<CleanParseException>()),
      );
    });
    test('throws when metin is not a string', () {
      expect(
        () => parseCleanResponse('{"metin": 42}'),
        throwsA(isA<CleanParseException>()),
      );
    });
    test(
      'throws on empty / whitespace-only text (silent empty is forbidden)',
      () {
        expect(
          () => parseCleanResponse('{"metin": ""}'),
          throwsA(isA<CleanParseException>()),
        );
        expect(
          () => parseCleanResponse(r'{"metin": "   \n  "}'),
          throwsA(isA<CleanParseException>()),
        );
      },
    );
    test(
      'the error message carries the reason (file:line discipline, diagnosability)',
      () {
        try {
          parseCleanResponse('{"text": "x"}');
          fail('CleanParseException was expected');
        } on CleanParseException catch (e) {
          expect(e.toString(), contains('metin'));
        }
      },
    );
  });
}
