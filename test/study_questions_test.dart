// Oracle test (spec Phase 4 start): chapter question-bank contract -- PURE.
// Spec: 8-12 questions per chapter (factual + conceptual + applied). A SEPARATE LLM
// pass; the parse is the third twin of clean/study_contract.
//
// Contract decisions (oracle, 2026-06-12):
// - QuestionKind { olgusal, kavramsal, uygulamali }
// - StudyQuestion { soru, cevap: non-empty String; tip: QuestionKind }
// - parseQuestionsResponse(raw) -> List<StudyQuestion>: fence tolerance (```json,
//   plain ``` and single-line -- same semantics as study_contract); {"sorular": [...]}
//   root; 8-12 items; missing / wrong-type / empty field -> violation; a tip value
//   that is not one of the three names -> violation; violation = QuestionsParseException
//   (carries the reason). The returned list is UNMODIFIABLE.
// - buildQuestionsPrompt({chapterText, chapterTitle?}): contains the text; '8-12' and
//   the three type names appear; schema keys (sorular/soru/cevap/tip) appear; a null
//   title does not appear.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/study_questions.dart';

String q(int i, [String tip = 'olgusal']) =>
    '{"soru": "Question $i?", "cevap": "Answer $i.", "tip": "$tip"}';

String bank(int n, [String tip = 'olgusal']) =>
    '{"sorular": [${List.generate(n, (i) => q(i, tip)).join(',')}]}';

void main() {
  group('parseQuestionsResponse — valid', () {
    test('8 questions: fields and type are returned', () {
      final list = parseQuestionsResponse(bank(8, 'kavramsal'));
      expect(list, hasLength(8));
      expect(list[0].soru, 'Question 0?');
      expect(list[0].cevap, 'Answer 0.');
      expect(list[0].tip, QuestionKind.kavramsal);
    });

    test('12 questions accepted; all three types are recognized', () {
      final raw =
          '{"sorular": [${List.generate(10, q).join(',')},'
          '${q(10, 'kavramsal')},${q(11, 'uygulamali')}]}';
      final list = parseQuestionsResponse(raw);
      expect(list, hasLength(12));
      expect(list[10].tip, QuestionKind.kavramsal);
      expect(list[11].tip, QuestionKind.uygulamali);
    });

    test('fence tolerance: ```json, plain ``` and single-line', () {
      expect(parseQuestionsResponse('```json\n${bank(8)}\n```'), hasLength(8));
      expect(parseQuestionsResponse('```\n${bank(8)}\n```'), hasLength(8));
      expect(parseQuestionsResponse('```${bank(8)}```'), hasLength(8));
    });

    test('returned list is unmodifiable', () {
      final list = parseQuestionsResponse(bank(8));
      expect(() => list.removeAt(0), throwsUnsupportedError);
    });
  });

  group('parseQuestionsResponse — violations', () {
    test('7 or 13 questions -> throws (8-12 limit)', () {
      expect(
        () => parseQuestionsResponse(bank(7)),
        throwsA(isA<QuestionsParseException>()),
      );
      expect(
        () => parseQuestionsResponse(bank(13)),
        throwsA(isA<QuestionsParseException>()),
      );
    });

    test('invalid JSON / not an object / no "sorular" field -> throws', () {
      expect(
        () => parseQuestionsResponse('not json'),
        throwsA(isA<QuestionsParseException>()),
      );
      expect(
        () => parseQuestionsResponse('[1,2]'),
        throwsA(isA<QuestionsParseException>()),
      );
      expect(
        () => parseQuestionsResponse('{"baska": []}'),
        throwsA(isA<QuestionsParseException>()),
      );
    });

    test('"sorular" not a list / item not an object -> throws', () {
      expect(
        () => parseQuestionsResponse('{"sorular": "not a list"}'),
        throwsA(isA<QuestionsParseException>()),
      );
      final objeDegil = '{"sorular": [${List.generate(7, q).join(',')}, 42]}';
      expect(
        () => parseQuestionsResponse(objeDegil),
        throwsA(isA<QuestionsParseException>()),
      );
    });

    test('item with missing / empty field or unrecognized type -> throws', () {
      final eksik =
          '{"sorular": [${List.generate(7, q).join(',')},'
          '{"soru": "S?", "tip": "olgusal"}]}';
      expect(
        () => parseQuestionsResponse(eksik),
        throwsA(isA<QuestionsParseException>()),
      );
      final bos =
          '{"sorular": [${List.generate(7, q).join(',')},'
          '{"soru": "  ", "cevap": "C.", "tip": "olgusal"}]}';
      expect(
        () => parseQuestionsResponse(bos),
        throwsA(isA<QuestionsParseException>()),
      );
      final yanlisTip =
          '{"sorular": [${List.generate(7, q).join(',')},'
          '{"soru": "S?", "cevap": "C.", "tip": "philosophical"}]}';
      expect(
        () => parseQuestionsResponse(yanlisTip),
        throwsA(isA<QuestionsParseException>()),
      );
    });

    test('error message carries the reason', () {
      try {
        parseQuestionsResponse(bank(7));
        fail('should have thrown');
      } on QuestionsParseException catch (e) {
        expect(e.toString(), contains('8'));
      }
    });
  });

  group('buildQuestionsPrompt', () {
    test('text + count limit + three type names + schema keys', () {
      final p = buildQuestionsPrompt(chapterText: 'Chapter text goes here.');
      expect(p, contains('Chapter text goes here.'));
      expect(p, contains('8-12'));
      expect(p, contains('olgusal'));
      expect(p, contains('kavramsal'));
      expect(p, contains('uygulamali'));
      expect(p, contains('sorular'));
      expect(p, contains('soru'));
      expect(p, contains('cevap'));
      expect(p, contains('tip'));
    });

    test('title is included when given; not included when null', () {
      final pt = buildQuestionsPrompt(
        chapterText: 'm',
        chapterTitle: 'Origins',
      );
      expect(pt, contains('Origins'));
      final pn = buildQuestionsPrompt(chapterText: 'm');
      expect(pn, isNot(contains('Origins')));
    });
  });
}
