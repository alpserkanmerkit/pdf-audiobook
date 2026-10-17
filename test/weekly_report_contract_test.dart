// Oracle test (#26 Weekly progress letter): weekly stats + letter contract.
// computeWeeklyStats: counts mastered (hakim), in progress (devam) and overdue
// (vadesiGecen) items from the ReviewBank state.
// parseWeeklyReportResponse: parses the LLM letter JSON.
// buildWeeklyReportPrompt: stats -> pure prompt string.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/review_scheduler.dart';
import 'package:sesli_kitap/src/review_store.dart';
import 'package:sesli_kitap/src/study_questions.dart';
import 'package:sesli_kitap/src/weekly_report_contract.dart';

ReviewBank _banka(List<ReviewItem> items) {
  return ReviewBank(
    items: items,
    questions: List.generate(
      items.length,
      (i) =>
          StudyQuestion(soru: 'S$i', cevap: 'C$i', tip: QuestionKind.olgusal),
    ),
  );
}

ReviewItem _item(int idx, int intervalIndex, int dueDay) =>
    ReviewItem(id: 'q$idx', intervalIndex: intervalIndex, dueDay: dueDay);

void main() {
  group('computeWeeklyStats', () {
    test('empty bank -> zero counts', () {
      final s = computeWeeklyStats(_banka([]), today: 100);
      expect(s.toplam, 0);
      expect(s.hakim, 0);
      expect(s.devam, 0);
      expect(s.vadesiGecen, 0);
    });

    test('mastered (intervalIndex==3) items are counted correctly', () {
      final items = [_item(0, 3, -1), _item(1, 3, -1), _item(2, 0, 101)];
      final s = computeWeeklyStats(_banka(items), today: 100);
      expect(s.toplam, 3);
      expect(s.hakim, 2);
      expect(s.devam, 0);
    });

    test('in progress (0 < intervalIndex < 3) items are counted correctly', () {
      final items = [_item(0, 1, 105), _item(1, 2, 103), _item(2, 3, -1)];
      final s = computeWeeklyStats(_banka(items), today: 100);
      expect(s.devam, 2);
      expect(s.hakim, 1);
    });

    test(
      'overdue (dueDay < today, not mastered) items are counted correctly',
      () {
        final items = [
          _item(0, 0, 90),
          _item(1, 1, 95),
          _item(2, 3, -1),
          _item(3, 0, 105),
        ];
        final s = computeWeeklyStats(_banka(items), today: 100);
        expect(s.vadesiGecen, 2);
      },
    );

    test('an item that is due in the future is not counted as overdue', () {
      final items = [_item(0, 0, 105)];
      final s = computeWeeklyStats(_banka(items), today: 100);
      expect(s.vadesiGecen, 0);
    });

    test('a mastered item is not counted as overdue', () {
      final items = [_item(0, 3, -1)];
      final s = computeWeeklyStats(_banka(items), today: 100);
      expect(s.vadesiGecen, 0);
    });
  });

  group('parseWeeklyReportResponse', () {
    test('valid JSON -> WeeklyReport.mektup is filled', () {
      final r = parseWeeklyReportResponse(
        '{"mektup": "Great progress this week!"}',
      );
      expect(r.mektup, contains('Great'));
    });

    test('empty string throws', () {
      expect(
        () => parseWeeklyReportResponse(''),
        throwsA(isA<WeeklyReportParseException>()),
      );
    });

    test('invalid JSON throws', () {
      expect(
        () => parseWeeklyReportResponse('this is not json'),
        throwsA(isA<WeeklyReportParseException>()),
      );
    });

    test('throws if the mektup field is missing', () {
      expect(
        () => parseWeeklyReportResponse('{"other": "field"}'),
        throwsA(isA<WeeklyReportParseException>()),
      );
    });

    test('mektup empty string throws', () {
      expect(
        () => parseWeeklyReportResponse('{"mektup": "   "}'),
        throwsA(isA<WeeklyReportParseException>()),
      );
    });

    test('throws if mektup is not a string', () {
      expect(
        () => parseWeeklyReportResponse('{"mektup": 42}'),
        throwsA(isA<WeeklyReportParseException>()),
      );
    });

    test('throws if the JSON is an array', () {
      expect(
        () => parseWeeklyReportResponse('[1,2,3]'),
        throwsA(isA<WeeklyReportParseException>()),
      );
    });

    test('WeeklyReportParseException.toString includes the reason', () {
      const e = WeeklyReportParseException('test reason');
      expect(e.toString(), contains('WeeklyReportParseException'));
      expect(e.toString(), contains('test reason'));
    });
  });

  group('buildWeeklyReportPrompt', () {
    test('stats appear in the prompt', () {
      const s = WeeklyStats(toplam: 20, hakim: 5, devam: 10, vadesiGecen: 3);
      final p = buildWeeklyReportPrompt(s);
      // Labeled values: a bare digit such as '5'/'3' may also appear elsewhere in
      // the text; each number must match its own label (catches field mix-ups).
      expect(p, contains('Total 20'));
      expect(p, contains('Mastered 5'));
      expect(p, contains('In progress 10'));
      expect(p, contains('Overdue 3'));
    });

    test('the JSON output instruction is present', () {
      const s = WeeklyStats(toplam: 10, hakim: 2, devam: 5, vadesiGecen: 1);
      final p = buildWeeklyReportPrompt(s);
      expect(p, contains('mektup'));
    });

    test('different stats produce a different prompt', () {
      const s1 = WeeklyStats(toplam: 10, hakim: 5, devam: 0, vadesiGecen: 0);
      const s2 = WeeklyStats(toplam: 50, hakim: 1, devam: 20, vadesiGecen: 10);
      expect(
        buildWeeklyReportPrompt(s1),
        isNot(equals(buildWeeklyReportPrompt(s2))),
      );
    });
  });
}
