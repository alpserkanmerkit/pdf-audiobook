// Slice-12 WIRING test (§13.7 — oracle). Does the share sheet open from a Notebook quote?
//
// The seedBooks-like _seed fallback in NotebookScreen was removed (02.07.2026
// field report); AppShell never passes real quotes to the Notebook, so
// (no highlight-saving flow is wired yet) this test now pumps NotebookScreen
// directly with a fixture quote (same pattern as _pumpCardsScreen in
// cards_wiring_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/ui/screens/notebook_screen.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';

void main() {
  testWidgets('Notebook -> share quote -> share sheet (Close)', (tester) async {
    final settings = AppSettings();
    await tester.pumpWidget(
      AppSettingsScope(
        settings: settings,
        child: MaterialApp(
          theme: buildAppTheme(settings),
          home: const NotebookScreen(
            quotes: [
              NotebookQuote(text: 'Test quote.', page: 12, book: 'Test Book'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Share').first);
    await tester.pumpAndSettle();
    expect(find.text('Close'), findsWidgets);
  });
}
