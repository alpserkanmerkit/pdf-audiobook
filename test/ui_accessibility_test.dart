// FAZ5 (oracle RED) — live UI bugs:
//  S5:  AppSettings.fontScale is not consumed anywhere -> the text-size slider
//       ("Text size") in Settings is a no-op. MaterialApp.builder must apply
//       the MediaQuery textScaler (live).
//  R6:  16 hard-coded 'Libre Caslon *' literals in 8 files override the dyslexia
//       font swap (Lexend) in app_theme. The serif family must come from the token.
//  K18: discussion_room uses palette.surface2 as a TEXT color in 3 places
//       (~1.25:1 contrast, unreadable). It must be text2/text3.
//  K17: a locale-insensitive toUpperCase garbles the author name
//       ('S. Demir' -> 'S. DEMIR'; the correct result is 'S. DEMİR').
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/ui/screens/discussion_room_screen.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';

import 'helpers/test_app.dart';

/// K17 fixture: a REAL book whose author name has a lowercase 'i' (for the
/// Turkish uppercase test). Since seedBooks() was removed, these tests must
/// supply their own data fixture.
const _k17Book = Book(
  id: 'k17-1',
  title: 'Test Book',
  author: 'S. Demir',
  chapterLabel: 'Chapter 1',
  progressPercent: 10,
  totalPages: 100,
  coverIndex: 0,
  hash: 'k17hash0001',
);

void main() {
  testWidgets(
    'S5: fontScale=1.4 becomes the textScaler under MaterialApp (live)',
    (tester) async {
      await tester.pumpWidget(await buildTestApp());
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byKey(const Key('tab-library')));
      expect(MediaQuery.textScalerOf(ctx).scale(10), 10.0);

      AppSettingsScope.of(ctx).setFontScale(1.4);
      await tester.pumpAndSettle();

      final ctx2 = tester.element(find.byKey(const Key('tab-library')));
      expect(MediaQuery.textScalerOf(ctx2).scale(10), closeTo(14.0, 1e-9));
    },
  );

  testWidgets('R6: dyslexia ON -> serif title becomes Lexend (Library)', (
    tester,
  ) async {
    await tester.pumpWidget(await buildTestApp());
    await tester.pumpAndSettle();

    Text title() => tester.widget<Text>(find.text('Your library'));
    expect(title().style?.fontFamily, 'Libre Caslon Display');

    final ctx = tester.element(find.byKey(const Key('tab-library')));
    AppSettingsScope.of(ctx).toggleDyslexia();
    await tester.pumpAndSettle();

    expect(title().style?.fontFamily, 'Lexend');
  });

  testWidgets('K18: discussion_room text color is text2/text3, not surface2', (
    tester,
  ) async {
    final settings = AppSettings();
    await tester.pumpWidget(
      AppSettingsScope(
        settings: settings,
        child: MaterialApp(
          theme: buildAppTheme(settings),
          home: const DiscussionRoomScreen(bookTitle: 'Test Book'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final ctx = tester.element(find.byType(DiscussionRoomScreen));
    final palette = Theme.of(ctx).extension<AppPalette>()!;

    Color? colorOf(String text) =>
        tester.widget<Text>(find.text(text)).style?.color;
    // Subtitle: text2, like the neighboring texts in the hierarchy.
    expect(colorOf('«Test Book»'), palette.text2);

    // Attribution (hidden in the empty state at the start): to get a real value,
    // tap a steering chip, which sets _attribution to '— Emel'. The chip may be
    // off-screen inside a SingleChildScrollView, so bring it into view first
    // (same ensureVisible pattern as reader_wiring_test.dart).
    final steerChip = find.textContaining('Go deeper');
    await tester.ensureVisible(steerChip);
    await tester.pumpAndSettle();
    await tester.tap(steerChip);
    await tester.pumpAndSettle();
    expect(colorOf('— Emel'), palette.text2);

    // Label ('Host', 4 avatars): text3.
    for (final t in tester.widgetList<Text>(find.text('Host'))) {
      expect(t.style?.color, palette.text3);
    }
    // Global sweep: no Text is painted with the unreadable-contrast surface2.
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      expect(t.style?.color, isNot(palette.surface2));
    }
  });

  testWidgets(
    'K17: library author name is uppercased with Turkish rules (S. DEMİR)',
    (tester) async {
      final services = await buildTestServices(
        prefsValues: {
          'books_v1': encodeBooks([_k17Book]),
        },
      );
      await tester.pumpWidget(buildTestAppFromServices(services));
      await tester.pumpAndSettle();

      expect(find.text('S. DEMIR'), findsNothing);
      expect(find.text('S. DEMİR'), findsOneWidget);
    },
  );

  testWidgets('K17: discover author name is uppercased with Turkish rules', (
    tester,
  ) async {
    final services = await buildTestServices(
      prefsValues: {
        'books_v1': encodeBooks([_k17Book]),
      },
    );
    await tester.pumpWidget(buildTestAppFromServices(services));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.explore));
    await tester.pumpAndSettle();

    expect(find.text('S. DEMIR'), findsNothing);
    expect(find.text('S. DEMİR'), findsWidgets);
  });
}
