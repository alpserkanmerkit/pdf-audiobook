// Oracle test (PHASE 4): spaced-repetition persistence contract.
// Verifies the required behavior, not a tautology.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/review_store.dart';
import 'package:sesli_kitap/src/study_questions.dart';

List<StudyQuestion> _qs(int n) => [
  for (var i = 0; i < n; i++)
    StudyQuestion(soru: 'S$i?', cevap: 'C$i', tip: QuestionKind.olgusal),
];

void main() {
  test('daysSinceEpoch: 2026-01-01=0, 2026-01-02=1 (fixed epoch)', () {
    expect(daysSinceEpoch(DateTime.utc(2026)), 0);
    expect(daysSinceEpoch(DateTime.utc(2026, 1, 2)), 1);
    expect(daysSinceEpoch(DateTime.utc(2026, 1, 2, 23, 59)), 1);
  });

  test(
    'daysSinceEpoch: LOCAL calendar day is the basis — 00:30 and 23:00 on the same day '
    'give the same index (S4)',
    () {
      // In the old toUtc-based behavior, local 00:30 at UTC+3 fell on the previous UTC day
      // (the day boundary shifted to 03:00). Local components are used;
      // the expectations below are independent of the machine time zone.
      final geceYarisiSonrasi = daysSinceEpoch(DateTime(2026, 7, 2, 0, 30));
      final aksam = daysSinceEpoch(DateTime(2026, 7, 2, 23));
      final dunAksam = daysSinceEpoch(DateTime(2026, 7, 1, 23));
      expect(geceYarisiSonrasi, aksam, reason: 'same local day = same index');
      expect(
        geceYarisiSonrasi - dunAksam,
        1,
        reason: 'previous local day is one less',
      );
    },
  );

  test(
    'newBank: each question is scheduled with its q-index (dueDay=today+1)',
    () {
      final bank = newBank(_qs(3), 10);
      expect(bank.items.length, 3);
      expect(bank.items[1].id, 'q1');
      expect(bank.items[1].intervalIndex, 0);
      expect(bank.items[1].dueDay, 11);
      expect(questionById(bank, 'q2')!.soru, 'S2?');
    },
  );

  test('questionById: unknown/out-of-range id returns null (no crash)', () {
    final bank = newBank(_qs(2), 0);
    expect(questionById(bank, 'q5'), isNull);
    expect(questionById(bank, 'x1'), isNull);
    expect(questionById(bank, 'q-1'), isNull);
  });

  test(
    'withAnswer: knew it → interval advances; did not → resets to tomorrow',
    () {
      var bank = newBank(_qs(2), 10);
      bank = withAnswer(bank, 'q0', knewIt: true, today: 11);
      expect(bank.items[0].intervalIndex, 1);
      expect(bank.items[0].dueDay, 14); // 11 + 3 (1-3-7 ladder)
      expect(bank.items[1].intervalIndex, 0); // the other item is untouched

      bank = withAnswer(bank, 'q0', knewIt: false, today: 14);
      expect(bank.items[0].intervalIndex, 0);
      expect(bank.items[0].dueDay, 15);
    },
  );

  test('dueIds: only due items, in dueItems order', () {
    var bank = newBank(_qs(3), 10); // all have dueDay=11
    bank = withAnswer(bank, 'q1', knewIt: true, today: 11); // q1 → 14
    expect(dueIds(bank, 11), ['q0', 'q2']);
    expect(dueIds(bank, 10), isEmpty);
    expect(dueIds(bank, 14), ['q0', 'q2', 'q1']);
  });

  test('encode/decode round-trip: items + questions preserved exactly', () {
    final orig = withAnswer(newBank(_qs(2), 5), 'q0', knewIt: true, today: 6);
    final back = decodeReviewBank(encodeReviewBank(orig));
    expect(back.items.length, 2);
    expect(back.items[0].id, 'q0');
    expect(back.items[0].intervalIndex, 1);
    expect(back.items[0].dueDay, orig.items[0].dueDay);
    expect(back.questions[1].cevap, 'C1');
    expect(back.questions[1].tip, QuestionKind.olgusal);
  });

  test('decodeReviewBank: corrupt JSON/schema throws FormatException', () {
    expect(() => decodeReviewBank('not json at all'), throwsFormatException);
    expect(() => decodeReviewBank('{"items": 3}'), throwsFormatException);
    expect(
      () => decodeReviewBank('{"items":[{"id":"q0"}],"questions":[]}'),
      throwsFormatException,
    );
    expect(
      () => decodeReviewBank('{"items": [], "questions": [{"soru":"s"}]}'),
      throwsFormatException,
    );
    expect(
      () => decodeReviewBank(
        '{"items": [], "questions": '
        '[{"soru":"s","cevap":"c","tip":"nosuchtype"}]}',
      ),
      throwsFormatException,
    );
  });

  test(
    'decodeReviewBank: intervalIndex outside 0..3 throws FormatException (K7)',
    () {
      // If intervalIndex 4+ were accepted when persisted, applyAnswer/dueItems
      // would overflow intervals[] (RangeError) — decode rejects it at the boundary.
      expect(
        () => decodeReviewBank(
          '{"items":[{"id":"q0","intervalIndex":4,"dueDay":5}],"questions":[]}',
        ),
        throwsFormatException,
      );
      expect(
        () => decodeReviewBank(
          '{"items":[{"id":"q0","intervalIndex":-1,"dueDay":5}],"questions":[]}',
        ),
        throwsFormatException,
      );
    },
  );

  test('decodeReviewBank: boundary values 0 and 3 are accepted (K7)', () {
    // Valid bank: items and questions have equal length; ids are positional q$i.
    final bank = decodeReviewBank(
      '{"items":[{"id":"q0","intervalIndex":0,"dueDay":5},'
      '{"id":"q1","intervalIndex":3,"dueDay":-1}],'
      '"questions":['
      '{"soru":"s0","cevap":"c0","tip":"olgusal"},'
      '{"soru":"s1","cevap":"c1","tip":"olgusal"}]}',
    );
    expect(bank.items[0].intervalIndex, 0);
    expect(bank.items[1].intervalIndex, 3);
  });

  test('decodeReviewBank: items>questions LENGTH mismatch throws FormatException '
      '(dangling item id -> prevents a CardsScreen questionById(!) crash)', () {
    // q1 maps to no question; the shell (CardsScreen/report) catches FormatException
    // and falls back to seed/skip mode -- safe instead of crashing.
    expect(
      () => decodeReviewBank(
        '{"items":[{"id":"q0","intervalIndex":0,"dueDay":5},'
        '{"id":"q1","intervalIndex":0,"dueDay":5}],'
        '"questions":[{"soru":"s0","cevap":"c0","tip":"olgusal"}]}',
      ),
      throwsFormatException,
    );
  });

  test(
    r'decodeReviewBank: item id violating the positional q$i invariant '
    'throws FormatException (id not mapped to a question -> crash prevented)',
    () {
      // id 'x0' is not q-indexed -> questionById null -> questionById(!) would crash.
      expect(
        () => decodeReviewBank(
          '{"items":[{"id":"x0","intervalIndex":0,"dueDay":5}],'
          '"questions":[{"soru":"s0","cevap":"c0","tip":"olgusal"}]}',
        ),
        throwsFormatException,
      );
    },
  );
}
