// Oracle test (Gemini TTS slice, 2026-09-28): empty-key check of the discussion
// room. The discussion now produces BOTH text AND audio with Gemini, so only the
// Gemini key is required; a Google TTS key is not requested (the second-key
// requirement for the user was removed). Harness: test/discussion_location_topic_test.dart pattern.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/ui/screens/discussion_room_screen.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';
import 'helpers/test_app.dart';

Widget _wrapScreen(Widget child) {
  final settings = AppSettings();
  return AppSettingsScope(
    settings: settings,
    child: MaterialApp(theme: buildAppTheme(settings), home: child),
  );
}

Future<void> _start(WidgetTester tester, AppServices services) async {
  // buildTestServices does NOT load settings (app_shell calls load() in the app).
  services.reading.load();
  await tester.pumpWidget(
    AppServicesScope(
      services: services,
      child: _wrapScreen(const DiscussionRoomScreen()),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithIcon(IconButton, Icons.play_arrow));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, 'perception of time');
  await tester.pumpAndSettle();
  await tester.tap(find.text('Start'));
  await tester.pump();
}

void main() {
  testWidgets(
    'Gemini key EMPTY -> friendly warning; the message asks only for the Gemini key',
    (tester) async {
      final services = await buildTestServices(
        prefsValues: const {'googleKey': 'g-key'},
      );
      await _start(tester, services);
      expect(
        find.textContaining('An API key is required for discussions'),
        findsOneWidget,
      );
      expect(find.textContaining('enter your Gemini key'), findsOneWidget);
      expect(find.textContaining('Google'), findsNothing);
    },
  );

  testWidgets(
    'Gemini key FILLED, Google key EMPTY -> no key warning (audio is also produced with Gemini, so no Google key is needed)',
    (tester) async {
      final services = await buildTestServices(
        prefsValues: const {'geminiKey': 'gm-key'},
      );
      await _start(tester, services);
      expect(
        find.textContaining('An API key is required for discussions'),
        findsNothing,
      );
      // Real-path network calls started in the background must not leak past the test.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
