// Slice-0 WIRING test (§13.7 — oracle writes). Is the new app shell (AppShell)
// CONNECTED to the composition root (SesliKitapApp/main.dart), and are the 5
// bottom-nav tabs really reachable? The antidote to the field lesson "unit green
// != wired": the app_shell.dart + main.dart the worker writes turn this test green.
//
// Every placeholder tab screen carries Key('tab-<tab>') (worker contract),
// so the bottom-nav LABEL can be told apart from the screen CONTENT.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/test_app.dart';

void main() {
  testWidgets('shell opens and all 5 bottom-nav tabs are visible', (
    tester,
  ) async {
    await tester.pumpWidget(await buildTestApp());
    await tester.pumpAndSettle();

    for (final label in ['Library', 'Reader', 'Discussion', 'Quiz', 'Report']) {
      expect(
        find.text(label),
        findsWidgets,
        reason: '$label bottom-nav tab must be visible',
      );
    }
  });

  testWidgets('Library tab is active at startup', (tester) async {
    await tester.pumpWidget(await buildTestApp());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tab-library')), findsOneWidget);
  });

  testWidgets('tab switching works: tap the Rapor tab -> Rapor screen', (
    tester,
  ) async {
    await tester.pumpWidget(await buildTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tab-report')), findsOneWidget);
    // IndexedStack keeps tab state: Library is offstage but in the tree (skipOffstage:false).
    expect(
      find.byKey(const Key('tab-library'), skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('switching to the Tartisma tab works', (tester) async {
    await tester.pumpWidget(await buildTestApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discussion'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tab-discussion')), findsOneWidget);
  });

  group(
    'back button (field report: "I press the back button and it does not go back")',
    () {
      testWidgets(
        't1: the back arrow on the Okuyucu tab returns to Library (today '
        'Navigator.maybePop does NOTHING -- the Reader is an IndexedStack child, '
        'nothing is pushed, so there is no route to pop)',
        (tester) async {
          await tester.pumpWidget(await buildTestApp());
          await tester.pumpAndSettle();
          await tester.tap(find.text('Reader'));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('tab-reader')), findsOneWidget);

          await tester.tap(find.byIcon(Icons.arrow_back).first);
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('tab-library')),
            findsOneWidget,
            reason: 'the back arrow must return to the Library tab',
          );
        },
      );

      testWidgets(
        't2: the back arrow on the Tartisma tab also returns to Library (same '
        'architectural problem also affected Discussion besides Reader)',
        (tester) async {
          await tester.pumpWidget(await buildTestApp());
          await tester.pumpAndSettle();
          await tester.tap(find.text('Discussion'));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('tab-discussion')), findsOneWidget);

          await tester.tap(find.byIcon(Icons.arrow_back).first);
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('tab-library')), findsOneWidget);
        },
      );

      testWidgets(
        't3: system back (PopScope) configuration -- OUTSIDE Library canPop=false and '
        'the back callback returns to Library; ON Library canPop=true (follows the '
        'system default -- exiting the app -- is allowed)',
        (tester) async {
          await tester.pumpWidget(await buildTestApp());
          await tester.pumpAndSettle();

          // PopScope<T> is generic (T is inferred from the result type of
          // onPopInvokedWithResult -- here PopScope<Object>). find.byType looks for an
          // EXACT runtimeType match and does not match a parameterized concrete type,
          // so an 'is'-based predicate is used instead.
          PopScope popScope() => tester.widget<PopScope>(
            find.byWidgetPredicate((w) => w is PopScope),
          );

          expect(
            popScope().canPop,
            isTrue,
            reason:
                'Library is the main/root tab -- system back = exit allowed',
          );

          await tester.tap(find.text('Report'));
          await tester.pumpAndSettle();
          expect(
            popScope().canPop,
            isFalse,
            reason:
                'on a tab outside Library, system back must NOT exit the app '
                'directly',
          );

          popScope().onPopInvokedWithResult!(false, null);
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('tab-library')),
            findsOneWidget,
            reason: 'the system back callback must return to the Library tab',
          );
        },
      );
    },
  );
}
