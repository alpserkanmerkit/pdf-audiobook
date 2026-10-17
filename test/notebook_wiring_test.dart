// Slice-8 WIRING test (§13.7 — oracle). Is the Quote Notebook reachable from the library notebook icon?
//
// Field report (02.07.2026): _seed quotes were fake content that did not belong to the real user
// (always the same 2 quotes, no matter which book was opened). The fallback was REMOVED; the screen now falls
// back gracefully to its own "You have not saved any quotes yet." (You have not saved any quotes yet.) empty state
// (known limitation: the real highlight/quote-saving flow is not wired yet -- the "bookmark_add" icon in
// reader_screen is not connected).
//
// B2 (04.07.2026): the "Study cards" button was REMOVED. NotebookScreen has no book/hash
// context (only quotes -- and NotebookQuote.book is a TITLE, NOT a reviewbank_$hash key). The button unconditionally
// opened `CardsScreen()` (no bookHash) -> it ALWAYS landed in seed/dead mode. The valid spaced-repetition entry point
// already exists on the quiz path (quiz_screen.dart "Study cards" (Study cards), with the real hash). This misleading
// affordance led the user into dead mode, so it was deleted.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/ui/screens/notebook_screen.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';
import 'helpers/test_app.dart';

void main() {
  testWidgets(
    'Library notebook icon -> Quote Notebook -> NOT a fake seed quote, '
    'the explicit empty-state message is shown',
    (tester) async {
      await tester.pumpWidget(await buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.bookmark_border));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Quote Notebook'), findsWidgets);
      expect(
        find.textContaining('gerçek lüks'),
        findsNothing,
        reason: 'the old fake seed quote must NOT appear anymore',
      );
      expect(
        find.textContaining('You have not saved any quotes yet'),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'B2: NotebookScreen NO LONGER shows the misleading "Study cards" button '
    '(no bookHash -> the affordance leading to seed/dead mode was removed)',
    (tester) async {
      final settings = AppSettings();
      await tester.pumpWidget(
        AppSettingsScope(
          settings: settings,
          child: MaterialApp(
            theme: buildAppTheme(settings),
            home: const NotebookScreen(
              quotes: [
                NotebookQuote(text: 'Test quote.', page: 12, book: 'Book'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.text('Study cards'),
        findsNothing,
        reason:
            'the button leading to the dead path (seed CardsScreen) must be removed',
      );
      expect(
        find.byIcon(Icons.grid_view_rounded),
        findsNothing,
        reason: 'the icon of the removed button must not remain either',
      );
    },
  );
}
