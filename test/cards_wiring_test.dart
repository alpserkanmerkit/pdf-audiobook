// (B2 test 'Notebook study-cards button is absent' was removed: notebook_wiring_test.dart:44-72
// NotebookScreen makes the same claim with text + icon.)
// Slice-11 WIRING test (§13.7 — oracle). Is Study Cards reachable from the Notebook?
// W7: review-bank persistence / due date / return / empty state — CardsScreen now
// (when bookHash is given) reads and updates the real ReviewBank in prefs.
//
// Field report (02.07.2026): when bookHash was not passed (today's only real entry
// point -- the Notebook), the default call always showed the same 4 fake questions.
// The `cards` default was changed to `const []`; t4/t5 now prove that the screen
// falls back gracefully to the existing "No study cards yet." empty state.
// Known limitation: a real entry point with a bookHash (e.g. "this book's cards"
// from the reader) is not wired yet and needs separate approval.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/review_scheduler.dart';
import 'package:sesli_kitap/src/review_store.dart';
import 'package:sesli_kitap/src/study_questions.dart';
import 'package:sesli_kitap/ui/screens/cards_screen.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';
import 'helpers/test_app.dart';

/// W7 test helper (local — without touching out-of-scope files): pumps CardsScreen
/// directly with the SAME wrapping AppShell's _placeholder uses (AppServicesScope +
/// buildAppTheme + MaterialApp). Full-app navigation (buildTestApp + tap chain) does
/// not pass bookHash through any screen, so this narrower seam keeps the scope
/// limited to cards_screen.dart.
Future<void> _pumpCardsScreen(
  WidgetTester tester, {
  required Map<String, Object> prefsValues,
  String? bookHash,
}) async {
  final services = await buildTestServices(prefsValues: prefsValues);
  final settings = AppSettings();
  await tester.pumpWidget(
    AppServicesScope(
      services: services,
      child: AppSettingsScope(
        settings: settings,
        child: MaterialApp(
          theme: buildAppTheme(settings),
          home: CardsScreen(bookHash: bookHash),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<StudyQuestion> _qs(int n) => [
  for (var i = 0; i < n; i++)
    StudyQuestion(
      soru: 'Question $i?',
      cevap: 'Answer $i',
      tip: QuestionKind.olgusal,
    ),
];

void main() {
  group('W7: review-bank wiring', () {
    const hash = 'kitap123';

    testWidgets("t1: if prefs hold 2 due cards, the first card's question "
        'is visible (not the seed data)', (tester) async {
      final today = daysSinceEpoch(DateTime.now());
      final bank = newBank(_qs(2), today - 1); // dueDay = today, both are due
      await _pumpCardsScreen(
        tester,
        prefsValues: {'reviewbank_$hash': encodeReviewBank(bank)},
        bookHash: hash,
      );

      expect(find.text('Question 0?'), findsOneWidget);
      expect(find.textContaining('boşluk (negatif mekân)'), findsNothing);
    });

    testWidgets(
      't2: flip -> answer is visible; "I knew it" -> progress is persisted '
      'and the next due card is shown',
      (tester) async {
        final today = daysSinceEpoch(DateTime.now());
        final bank = newBank(_qs(2), today - 1);
        const key = 'reviewbank_$hash';
        await _pumpCardsScreen(
          tester,
          prefsValues: {key: encodeReviewBank(bank)},
          bookHash: hash,
        );

        // Flip: the answer becomes visible.
        await tester.tap(find.text('Question 0?'));
        await tester.pumpAndSettle();
        expect(find.text('Answer 0'), findsOneWidget);

        // "I knew it" -> q0 advances, the next one (q1) is shown.
        await tester.tap(find.text('I knew it'));
        await tester.pumpAndSettle();
        expect(find.text('Question 1?'), findsOneWidget);

        final services = AppServicesScope.of(
          tester.element(find.byType(CardsScreen)),
        );
        final raw = services.prefs.getString(key);
        expect(raw, isNotNull);
        final persisted = decodeReviewBank(raw!);
        final q0 = persisted.items.firstWhere((i) => i.id == 'q0');
        expect(
          q0.intervalIndex,
          1,
          reason: 'applyAnswer(knewIt:true) should advance 0 -> 1',
        );
        // Same ladder as the pin in review_store_test.dart: the 0->1 step
        // uses intervals[1]=3 (the SECOND rung of the 1-3-7 ladder).
        expect(q0.dueDay, today + 3);
      },
    );

    testWidgets('t3: when no card is due, a clear empty-state message '
        'is shown, no crash', (tester) async {
      final today = daysSinceEpoch(DateTime.now());
      // dueDay = today + 100 -> none are due.
      final bank = newBank(_qs(3), today + 99);
      await _pumpCardsScreen(
        tester,
        prefsValues: {'reviewbank_$hash': encodeReviewBank(bank)},
        bookHash: hash,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Question 0?'), findsNothing);
      expect(
        find.textContaining('No cards due for review today'),
        findsWidgets,
      );
    });

    testWidgets(
      "t4: no bank in prefs (no bookHash either -- today's default call) "
      '-> a clear empty-state message is shown (NOT the fake demo card)',
      (tester) async {
        await _pumpCardsScreen(tester, prefsValues: const {});

        expect(tester.takeException(), isNull);
        expect(
          find.textContaining('boşluk (negatif mekân) neyi temsil eder?'),
          findsNothing,
          reason: 'the old fake demo card must NOT be visible anymore',
        );
        expect(find.textContaining('No study cards yet'), findsWidgets);
      },
    );

    testWidgets(
      't5: the bank in prefs is corrupt (decodeReviewBank throws FormatException) '
      '-> no crash, gracefully falls back to the same empty-state message (same path as t4)',
      (tester) async {
        await _pumpCardsScreen(
          tester,
          prefsValues: {'reviewbank_$hash': 'this is never valid json'},
          bookHash: hash,
        );

        expect(tester.takeException(), isNull);
        expect(find.textContaining('No study cards yet'), findsWidgets);
      },
    );

    testWidgets(
      't6 (A1): "Review again" (did not know) -> item.intervalIndex returns to 0 and '
      "prefs are updated (spaced repetition's wrong-answer reset is "
      'reachable from the UI)',
      (tester) async {
        final today = daysSinceEpoch(DateTime.now());
        const key = 'reviewbank_$hash';
        // Set q0 as advanced (intervalIndex=1) but due today, so that tapping
        // "Review again" resets 1 -> 0 and the change is OBSERVABLE. newBank starts
        // every item at index 0, so we build the bank by hand (q0 advanced, q1 fresh).
        final bank = ReviewBank(
          items: List.unmodifiable([
            ReviewItem(id: 'q0', intervalIndex: 1, dueDay: today),
            ReviewItem(id: 'q1', intervalIndex: 0, dueDay: today),
          ]),
          questions: List.unmodifiable(_qs(2)),
        );
        await _pumpCardsScreen(
          tester,
          prefsValues: {key: encodeReviewBank(bank)},
          bookHash: hash,
        );

        // The first card, q0 (intervalIndex=1), is shown.
        expect(find.text('Question 0?'), findsOneWidget);

        // "Review again" (did not know) -> q0 intervalIndex
        // resets to 0, prefs are written.
        await tester.tap(find.text('Review again'));
        await tester.pumpAndSettle();

        final services = AppServicesScope.of(
          tester.element(find.byType(CardsScreen)),
        );
        final raw = services.prefs.getString(key);
        expect(
          raw,
          isNotNull,
          reason: 'setString on reviewbank_ must be called',
        );
        final persisted = decodeReviewBank(raw!);
        final q0 = persisted.items.firstWhere((i) => i.id == 'q0');
        expect(
          q0.intervalIndex,
          0,
          reason: 'applyAnswer(knewIt:false) must reset intervalIndex 1 -> 0',
        );
        expect(
          q0.dueDay,
          today + 1,
          reason: '"Review again" must make the card due tomorrow (today+1)',
        );
      },
    );
  });
}
