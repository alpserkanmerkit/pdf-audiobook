// Slice-1b WIRING test (§13.7 -- oracle). Is the theme system CONNECTED to the
// composition root (SesliKitapApp), and do theme/mode/high-contrast changes go LIVE
// across the whole app? Antidote to "unit green but not connected": palette.dart works
// alone; the real question is whether, when AppSettings changes, the AppPalette color in
// the whole MaterialApp actually changes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/theme/palette.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';

import 'helpers/test_app.dart';

AppPalette _palOf(WidgetTester tester) {
  final ctx = tester.element(find.byKey(const Key('tab-library')));
  return Theme.of(ctx).extension<AppPalette>()!;
}

void main() {
  testWidgets(
    'AppPalette.bg changes live when the mode changes (cognac dark->light)',
    (tester) async {
      await tester.pumpWidget(await buildTestApp());
      await tester.pumpAndSettle();
      final darkBg = _palOf(tester).bg;
      expect(darkBg, const Color(0xFF15100C));

      final ctx = tester.element(find.byKey(const Key('tab-library')));
      AppSettingsScope.of(ctx).setMode(AppMode.light);
      await tester.pumpAndSettle();

      final lightBg = _palOf(tester).bg;
      expect(lightBg, const Color(0xFFEDE3D1));
      expect(lightBg, isNot(darkBg));
    },
  );

  testWidgets('accent changes live when the theme changes (cognac->obsidian)', (
    tester,
  ) async {
    await tester.pumpWidget(await buildTestApp());
    await tester.pumpAndSettle();
    expect(_palOf(tester).accent, const Color(0xFFC99A52));

    final ctx = tester.element(find.byKey(const Key('tab-library')));
    AppSettingsScope.of(ctx).setTheme(AppTheme.obsidian);
    await tester.pumpAndSettle();
    expect(_palOf(tester).accent, const Color(0xFFD9C59B));
  });

  testWidgets('enabling high contrast raises the text color', (tester) async {
    await tester.pumpWidget(await buildTestApp());
    await tester.pumpAndSettle();
    final before = _palOf(tester).text;

    final ctx = tester.element(find.byKey(const Key('tab-library')));
    AppSettingsScope.of(ctx).toggleHighContrast();
    await tester.pumpAndSettle();

    expect(_palOf(tester).text, const Color(0xFFFCF5E9));
    expect(_palOf(tester).text, isNot(before));
  });
}
