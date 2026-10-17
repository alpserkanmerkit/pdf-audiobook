// Slice-9 WIRING test (§13.7 — oracle). Is Discover reachable from the Library discover icon?
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/ui/screens/discover_screen.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';
import 'helpers/test_app.dart';

void main() {
  testWidgets(
    'Library discover icon -> Discover -> recommendations are visible',
    (tester) async {
      await tester.pumpWidget(await buildTestApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.explore));
      await tester.pumpAndSettle();
      expect(find.textContaining('For you'), findsWidgets);
      expect(
        find.textContaining('Recommended', skipOffstage: false),
        findsWidgets,
      );
    },
  );

  testWidgets('tapping a Discover cover calls onOpenBook with that book '
      '(covers used to be non-tappable -- dead affordance cleanup)', (
    tester,
  ) async {
    const book = Book(
      id: 'd1',
      title: 'Discover Book',
      author: 'Author',
      chapterLabel: '',
      progressPercent: 0,
      totalPages: 10,
      coverIndex: 0,
      hash: 'dhash1',
      filePath: '/tmp/d.pdf',
    );
    Book? opened;
    final settings = AppSettings();
    await tester.pumpWidget(
      AppSettingsScope(
        settings: settings,
        child: MaterialApp(
          theme: buildAppTheme(settings),
          home: DiscoverScreen(
            books: const [book],
            onOpenBook: (b) => opened = b,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('discover-dhash1')));
    await tester.pumpAndSettle();

    expect(opened, isNotNull, reason: 'tapping the cover must call onOpenBook');
    expect(opened!.hash, 'dhash1');
  });
}
