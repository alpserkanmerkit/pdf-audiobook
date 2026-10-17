// Oracle RED (2026-07-02, FAZ3b K1): a single shared helper for stripping LLM code fences.
// The repo had 3 copies (chapter_skeleton, clean_contract, study_questions._unwrapFence) doing the same job with
// DIFFERENT robustness; a single-line fence ('```json {...} ```') in chapter_skeleton produced a substring(0,-1)
// RangeError (K1). Contract: fence tolerance (```json / plain ``` / single-line -- same semantics as the
// study_questions contract); string operations can NEVER produce a negative index; without a fence, only trim.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/llm_fence.dart';

void main() {
  group('stripCodeFence', () {
    test('no fence -> trim only', () {
      expect(stripCodeFence('  {"a": 1}\n'), '{"a": 1}');
      expect(stripCodeFence('plain text'), 'plain text');
    });
    test('multi-line ```json fence is stripped', () {
      expect(stripCodeFence('```json\n{"a": 1}\n```'), '{"a": 1}');
    });
    test('multi-line plain ``` fence is stripped (no language tag)', () {
      expect(stripCodeFence('```\nhello world\n```'), 'hello world');
    });
    test(
      'single-line fence (K1 crash scenario) is stripped, NO RangeError',
      () {
        expect(stripCodeFence('```json {"a": 1} ```'), '{"a": 1}');
      },
    );
    test('adjacent fence (```content```) is stripped', () {
      expect(stripCodeFence('```{"a": 1}```'), '{"a": 1}');
    });
    test('closing fence on the same line as the JSON -> stripped', () {
      expect(stripCodeFence('```json\n{"a": 1} ```'), '{"a": 1}');
    });
    test(
      'missing closing fence -> opening is still stripped (no negative index)',
      () {
        expect(stripCodeFence('```json\n{"a": 1}'), '{"a": 1}');
      },
    );
    test('empty / fence-only inputs return empty', () {
      expect(stripCodeFence(''), '');
      expect(stripCodeFence('```'), '');
      expect(stripCodeFence('``````'), '');
    });
  });
}
