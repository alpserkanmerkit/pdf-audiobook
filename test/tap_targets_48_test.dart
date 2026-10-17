// K3a (project report K3): 48x48 dp touch target -- explicit measurement at screen level.
// test/temel/erisilebilirlik_test.dart scans the same rule across all screens with Flutter's
// androidTapTargetGuideline; this file pins the three fixed spots (library top-row icons,
// settings segment + font -/+ buttons) by SIZE (>=48) and asserts the VISUAL DID NOT CHANGE
// (44dp circle).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/ui/screens/library_screen.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';

import 'helpers/pump_fast.dart';
import 'helpers/test_app.dart';

const _dokunma = 48.0;

void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(360, 800);
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('Library: 4 top-row icon buttons >=48x48, visual circle 44dp', (
    tester,
  ) async {
    _phone(tester);
    final settings = AppSettings();
    await tester.pumpWidget(
      AppSettingsScope(
        settings: settings,
        child: MaterialApp(
          theme: buildAppTheme(settings),
          home: Scaffold(
            body: LibraryScreen(
              books: const [],
              onAddBook: () {},
              onOpenBook: (_) {},
              onOpenSettings: () {},
              onOpenNotebook: () {},
              onOpenDiscover: () {},
              onOpenTutor: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final rects = <Rect>[];
    for (final icon in [
      Icons.explore,
      Icons.school,
      Icons.bookmark_border,
      Icons.tune,
    ]) {
      final button = find.ancestor(
        of: find.byIcon(icon),
        matching: find.byType(IconButton),
      );
      expect(button, findsOneWidget, reason: '$icon must be an IconButton');
      final size = tester.getSize(button);
      expect(size.width, greaterThanOrEqualTo(_dokunma), reason: '$icon');
      expect(size.height, greaterThanOrEqualTo(_dokunma), reason: '$icon');
      rects.add(tester.getRect(button));

      // Visual unchanged: the filled circle around the icon is still 44x44.
      final daire = find.ancestor(
        of: find.byIcon(icon),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).shape == BoxShape.circle,
        ),
      );
      expect(daire, findsOneWidget, reason: '$icon circle');
      expect(tester.getSize(daire), const Size(44, 44), reason: '$icon');
    }
    // Adjacent touch areas must not overlap (risk of pressing the wrong button).
    for (var i = 0; i + 1 < rects.length; i++) {
      expect(
        rects[i].overlaps(rects[i + 1]),
        isFalse,
        reason: 'touch area of icon $i must not overlap icon ${i + 1}',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings: theme/mode segment options and font -/+ are >=48 high', (
    tester,
  ) async {
    _phone(tester);
    final services = await buildTestServices();
    await tester.pumpWidget(buildTestAppFromServices(services));
    await pumpFast(tester);
    await tester.tap(find.byIcon(Icons.tune));
    await pumpFast(tester);

    // Segment options: the GestureDetector ancestor of the label (touch target).
    for (final etiket in ['Cognac', 'Obsidian', 'Dark', 'Light']) {
      final t = find.text(etiket).first;
      await tester.ensureVisible(t);
      final hedef = find
          .ancestor(of: t, matching: find.byType(GestureDetector))
          .first;
      expect(
        tester.getSize(hedef).height,
        greaterThanOrEqualTo(_dokunma),
        reason: '$etiket segment touch target',
      );
    }
    // Font size -/+ buttons.
    for (final etiket in ['Decrease text size', 'Increase text size']) {
      final f = find.bySemanticsLabel(etiket);
      await tester.ensureVisible(f);
      final size = tester.getSize(f);
      expect(size.width, greaterThanOrEqualTo(_dokunma), reason: etiket);
      expect(size.height, greaterThanOrEqualTo(_dokunma), reason: etiket);
    }
    expect(tester.takeException(), isNull);
  });
}
