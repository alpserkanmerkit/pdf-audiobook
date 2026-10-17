// Audit D1b: design conformance (14 narrow-screen overflows). Finding 4 (is the
// Telaffuz (pronunciation) section present?) test was removed: the W1 group in
// settings_wiring_test.dart (around line 219+) opens the same section via the
// 'Add new pronunciation' (add new pronunciation) row and exercises the dialog flow.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/test_app.dart';

void main() {
  testWidgets(
    'Settings on a narrow screen (320px) does not crash with overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(await buildTestApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
