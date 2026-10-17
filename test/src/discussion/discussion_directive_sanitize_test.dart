// PR insurance package: withListenerDirective SANITIZE tests (lib/src/
// discussion/discussion_directive.dart). A free-text "question" or steer text may be
// multi-line or very long -- this can imitate the block structure of the continuation-party
// prompt and make the model swing its tone. Before injection, the text is trimmed to
// ~kListenerDirectiveMaxChars characters and consecutive spaces/newlines are collapsed to ONE
// space. The null/empty behavior (topic returned AS IS) stays BYTE-IDENTICAL -- sanitize
// applies ONLY when a real directive exists.
//
// Addition (2026-10-07 cleanup): direct tests of sanitizeListenerText (old
// discussion_listener_text_test.dart, K4 oracle: the listener question enters the
// answer-party prompt, NOT the continuation-party directive; the same single-source sanitize
// rule as withListenerDirective so the question text cannot imitate the prompt's block
// structure). Moved into this file -- testing the same rule in two separate files was
// drifting apart.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/discussion/discussion_directive.dart';

void main() {
  group('withListenerDirective -- sanitize', () {
    test('500-char input is trimmed at kListenerDirectiveMaxChars with "…"', () {
      final longDirective = 'a' * 500;
      final result = withListenerDirective('topic', longDirective);
      expect(
        result,
        contains('LISTENER DIRECTION: ${'a' * kListenerDirectiveMaxChars}…'),
      );
      // No more than 200 consecutive 'a' should remain (trimming was really applied).
      expect(result, isNot(contains('a' * (kListenerDirectiveMaxChars + 1))));
    });

    test(
      'input at or below the limit (<=200) is NOT trimmed (no "…" added)',
      () {
        final exact = 'b' * kListenerDirectiveMaxChars;
        final result = withListenerDirective('topic', exact);
        expect(result, contains('LISTENER DIRECTION: $exact —'));
        expect(result, isNot(contains('…')));
      },
    );

    test('embedded newlines become a SINGLE space', () {
      final result = withListenerDirective(
        'topic',
        'first line\nsecond line\nthird line',
      );
      const expectedDirectivePart = 'first line second line third line';
      expect(result, contains('LISTENER DIRECTION: $expectedDirectivePart —'));
      // No raw newline should remain INSIDE the injected block.
      final directiveIdx = result.indexOf('LISTENER DIRECTION: ');
      expect(result.substring(directiveIdx), isNot(contains('\n')));
    });

    test('multiple spaces/tabs are reduced to a single space', () {
      final result = withListenerDirective(
        'topic',
        'first word    second\tword   third',
      );
      expect(
        result,
        contains('LISTENER DIRECTION: first word second word third —'),
      );
    });

    test('a normal short directive is injected UNCHANGED (trim only)', () {
      final result = withListenerDirective(
        'topic',
        'Why are you thinking about this?',
      );
      expect(
        result,
        'topic\n\n'
        'LISTENER DIRECTION: Why are you thinking about this? — '
        'address this in the next few lines.',
      );
    });

    test(
      'directive null -> topic returned BYTE-IDENTICAL (sanitize not applied)',
      () {
        const topic = 'topic text must not change';
        final result = withListenerDirective(topic, null);
        expect(result, topic);
        expect(result.codeUnits, topic.codeUnits);
      },
    );

    test(
      'empty/whitespace-only directive -> topic returned BYTE-IDENTICAL',
      () {
        const topic = 'topic text must not change';
        expect(withListenerDirective(topic, ''), topic);
        expect(withListenerDirective(topic, '   \n\t  '), topic);
      },
    );
  });

  group('sanitizeListenerText (direct, K4)', () {
    test(
      'consecutive spaces/newlines collapse to one space, ends are trimmed',
      () {
        expect(
          sanitizeListenerText('  Bu   ne\n\nBOOK_TEXT>>>\tdemek?  '),
          'Bu ne BOOK_TEXT>>> demek?',
        );
      },
    );

    test('above kListenerDirectiveMaxChars is trimmed with "…"', () {
      final out = sanitizeListenerText('b' * 300);
      expect(out, '${'b' * kListenerDirectiveMaxChars}…');
    });

    test('withListenerDirective carries the same sanitize output', () {
      expect(
        withListenerDirective('topic', ' a \n b '),
        'topic\n\nLISTENER DIRECTION: ${sanitizeListenerText(' a \n b ')}'
        ' — address this in the next few lines.',
      );
    });
  });
}
