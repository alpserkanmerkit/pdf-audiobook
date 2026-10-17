// FLOW 0: REAL main() startup. The production entry point with no injected seams (main.dart):
// WidgetsFlutterBinding + SharedPreferences + path_provider + runApp.
//
// Precondition (scripts/e2e.sh provides it): on Linux, path_provider finds the documents dir
// via `xdg-user-dir DOCUMENTS`; if that tool is missing or misconfigured, main() throws.
// The script points XDG_DOCUMENTS_DIR at a temp dir and puts a fake `xdg-user-dir` on PATH
// -> nothing is written to the developer's real Documents folder.
// (On Windows/macOS, a local `flutter test -d windows` uses the real Documents dir;
// this flow only draws the onboarding screen and writes no files.)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/e2e_world.dart';

void bootFlow() {
  testWidgets('flow 0: real main() shows onboarding on first launch', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await app.main();
    await pumpUntilFound(
      tester,
      find.textContaining('Welcome to the reading room'),
      reason: 'onboarding screen did not appear after main()',
    );
    expect(find.text('Emel'), findsWidgets);
    expect(find.text('Ahmet'), findsWidgets);
    expect(find.text('Both'), findsWidgets);
    expect(find.text('Your library'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink()); // dispose the tree
  });
}
