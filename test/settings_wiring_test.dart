// Slice-7 WIRING test (§13.7 — oracle). Is the Settings screen reachable from the Library header icon
// and is the theme segment LIVE (AppSettings)?
//
// W1 ADDITIONS (oracle, this file): are the dead settings rows FUNCTIONAL and PERSISTENT?
// - t1: 'Voice provider' row -> choice -> ReadingSettings.provider + prefs persisted.
// - t2: 'Gemini API key' row -> text input -> prefs persisted (read after restart).
// - t3: 'Speech rate' row -> choice -> ReadingSettings.rate + prefs persisted, label live.
// - t4: 'Add new pronunciation' -> invalid rule shows an inline error (NOT persisted); valid rule
//   is added to the list and persisted.
// - t5: Theme fields (dyslexia + palette) are restored after restart (AppSettings persistence).
//
// Persistence proof pattern: WRITE to prefs (via widget interaction) -> the same mock prefs
// is RESTARTED with the same backing (restartTestApp/restartTestServices, setMockInitialValues
// is NOT called again) -> in the new tree / after a new ReadingSettings.load(), the value must come BACK
// This proves the difference between "widget-local state" and "actually persisted".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/main.dart';
import 'package:sesli_kitap/src/theme/palette.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'helpers/pump_fast.dart';
import 'helpers/test_app.dart';

void main() {
  testWidgets('Library settings icon -> Settings screen -> theme segment', (
    tester,
  ) async {
    await tester.pumpWidget(await buildTestApp());
    await pumpFast(tester);

    await tester.tap(find.byIcon(Icons.tune));
    await pumpFast(tester);

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Cognac'), findsWidgets);
    expect(find.text('Obsidian'), findsWidgets);
  });

  testWidgets(
    'the fake "Account" row (ornek.hesap + dead chevron) is NOT present '
    '(mock data + non-tappable chevron removed)',
    (tester) async {
      await tester.pumpWidget(await buildTestApp());
      await pumpFast(tester);
      await tester.tap(find.byIcon(Icons.tune));
      await pumpFast(tester);
      expect(
        find.textContaining('ornek.hesap'),
        findsNothing,
        reason: 'fake account row (mock email + dead chevron) must be removed',
      );
    },
  );

  group('W1 — Voice provider row', () {
    testWidgets('choice -> ReadingSettings.provider live + prefs persisted', (
      tester,
    ) async {
      final services = await buildTestServices();
      await tester.pumpWidget(
        SesliKitapApp(services: services..reading.load()),
      );
      await pumpFast(tester);
      await tester.tap(find.byIcon(Icons.tune));
      await pumpFast(tester);

      await tester.tap(find.text('Voice provider'));
      await pumpFast(tester);

      expect(
        find.text('Google'),
        findsOneWidget,
        reason: 'Google option should appear in the provider choice list',
      );
      await tester.tap(find.text('Google'));
      await pumpFast(tester);

      expect(services.reading.provider, 'google');

      // Persistence: restart, then read back from the same prefs backing.
      final restarted = await restartTestServices(services);
      restarted.reading.load();
      expect(restarted.reading.provider, 'google');
    });
  });

  group('W1 — API key (Gemini) row', () {
    testWidgets('text input -> prefs persisted (read after restart)', (
      tester,
    ) async {
      final services = await buildTestServices();
      await tester.pumpWidget(
        SesliKitapApp(services: services..reading.load()),
      );
      await pumpFast(tester);
      await tester.tap(find.byIcon(Icons.tune));
      await pumpFast(tester);

      await tester.ensureVisible(find.text('Gemini API key'));
      await pumpFast(tester);
      await tester.tap(find.text('Gemini API key'));
      await pumpFast(tester);

      expect(
        find.byType(TextField),
        findsWidgets,
        reason: 'API key dialog should contain at least one TextField',
      );
      await tester.enterText(find.byType(TextField).first, 'sk-test-12345');
      await pumpFast(tester);

      // Confirm: a button labeled 'Save' is expected (consistent with
      // the buttons of the earlier dialogs/sheets in the design).
      await tester.tap(find.text('Save'));
      await pumpFast(tester);

      expect(services.reading.geminiKey, 'sk-test-12345');

      final restarted = await restartTestServices(services);
      restarted.reading.load();
      expect(restarted.reading.geminiKey, 'sk-test-12345');
    });
  });

  group('W1 — Speech rate row', () {
    testWidgets('choice -> ReadingSettings.rate live + prefs persisted', (
      tester,
    ) async {
      final services = await buildTestServices();
      await tester.pumpWidget(
        SesliKitapApp(services: services..reading.load()),
      );
      await pumpFast(tester);
      await tester.tap(find.byIcon(Icons.tune));
      await pumpFast(tester);

      // No hardcoded '1×' at start; the live label comes from ReadingSettings.rate
      // (default 1.0 -> shows '1×').
      expect(find.text('1×'), findsOneWidget);

      await tester.tap(find.text('Speech rate'));
      await pumpFast(tester);

      expect(find.text('1.5×'), findsWidgets);
      await tester.tap(find.text('1.5×').last);
      await pumpFast(tester);

      expect(services.reading.rate, 1.5);
      expect(find.text('1.5×'), findsOneWidget);

      final restarted = await restartTestServices(services);
      restarted.reading.load();
      expect(restarted.reading.rate, 1.5);
    });
  });

  group('DEPTH — Server voices row', () {
    testWidgets('choice -> ReadingSettings.voice live + prefs persisted', (
      tester,
    ) async {
      final services = await buildTestServices();
      await tester.pumpWidget(
        SesliKitapApp(services: services..reading.load()),
      );
      await pumpFast(tester);
      await tester.tap(find.byIcon(Icons.tune));
      await pumpFast(tester);

      await tester.tap(find.text('Server voices'));
      await pumpFast(tester);

      expect(
        find.text('Ahmet'),
        findsOneWidget,
        reason: 'Ahmet option should appear in the voice choice list',
      );
      await tester.tap(find.text('Ahmet'));
      await pumpFast(tester);

      expect(services.reading.voice, 'tr-TR-AhmetNeural');

      final restarted = await restartTestServices(services);
      restarted.reading.load();
      expect(restarted.reading.voice, 'tr-TR-AhmetNeural');
    });
  });

  group('Phase 2 -- English server voice row', () {
    testWidgets('choice -> ReadingSettings.voiceEn live + prefs persisted', (
      tester,
    ) async {
      final services = await buildTestServices();
      await tester.pumpWidget(
        SesliKitapApp(services: services..reading.load()),
      );
      await pumpFast(tester);
      await tester.tap(find.byIcon(Icons.tune));
      await pumpFast(tester);

      await tester.tap(find.text('English server voice'));
      await pumpFast(tester);

      expect(
        find.text('David'),
        findsOneWidget,
        reason: 'David option should appear in the English voice choice list',
      );
      expect(find.text('Sarah'), findsOneWidget);
      await tester.tap(find.text('Sarah'));
      await pumpFast(tester);

      expect(services.reading.voiceEn, 'en-US-Wavenet-F');

      final restarted = await restartTestServices(services);
      restarted.reading.load();
      expect(restarted.reading.voiceEn, 'en-US-Wavenet-F');
    });
  });

  group('W1 — Pronunciation dictionary', () {
    testWidgets('invalid rule: inline error, NOT persisted', (tester) async {
      final services = await buildTestServices();
      await tester.pumpWidget(
        SesliKitapApp(services: services..reading.load()),
      );
      await pumpFast(tester);
      await tester.tap(find.byIcon(Icons.tune));
      await pumpFast(tester);

      await tester.ensureVisible(find.text('Add new pronunciation'));
      await pumpFast(tester);
      await tester.tap(find.text('Add new pronunciation'));
      await pumpFast(tester);

      expect(
        find.byType(TextField),
        findsNWidgets(2),
        reason:
            'pronunciation dialog should contain two fields (misread / correct)',
      );
      // The 'Misread word' field is left EMPTY -> parsePronRules throws on an empty from
      // PronRuleParseException (see pronunciation_rules.dart).
      await tester.enterText(find.byType(TextField).at(0), '');
      await tester.enterText(find.byType(TextField).at(1), 'something');
      await pumpFast(tester);

      await tester.tap(find.text('Save'));
      await pumpFast(tester);

      // NOT persisted: the invalid rule must not be written to prefs/ReadingSettings.
      expect(
        services.reading.pronRulesRaw,
        isEmpty,
        reason: 'invalid rule must not be persisted',
      );
      // The dialog must stay OPEN (the error is shown inline, the user can
      // fix it and retry) -- the input fields are still on screen.
      expect(
        find.byType(TextField),
        findsNWidgets(2),
        reason: 'dialog must stay open on invalid input (inline error)',
      );
    });

    testWidgets('valid rule: added to the list and persisted', (tester) async {
      final services = await buildTestServices();
      await tester.pumpWidget(
        SesliKitapApp(services: services..reading.load()),
      );
      await pumpFast(tester);
      await tester.tap(find.byIcon(Icons.tune));
      await pumpFast(tester);

      // With the default (empty pronRulesRaw), the GPT/Nietzsche examples
      // are shown only while no rule is stored.
      expect(find.text('GPT'), findsOneWidget);
      expect(find.text('Nietzsche'), findsOneWidget);

      await tester.ensureVisible(find.text('Add new pronunciation'));
      await pumpFast(tester);
      await tester.tap(find.text('Add new pronunciation'));
      await pumpFast(tester);

      await tester.enterText(find.byType(TextField).at(0), 'Foo');
      await tester.enterText(find.byType(TextField).at(1), 'Fu');
      await pumpFast(tester);

      await tester.tap(find.text('Save'));
      await pumpFast(tester);

      expect(services.reading.pronRulesRaw, contains('Foo'));
      expect(services.reading.pronRulesRaw, contains('Fu'));
      expect(find.text('Foo'), findsOneWidget);

      final restarted = await restartTestServices(services);
      restarted.reading.load();
      expect(restarted.reading.pronRulesRaw, contains('Foo=Fu'));
    });
  });

  group('W1 — Theme persistence', () {
    testWidgets('dyslexia on + Obsidian palette -> restored after restart', (
      tester,
    ) async {
      final services = await buildTestServices();
      await tester.pumpWidget(
        SesliKitapApp(services: services..reading.load()),
      );
      await pumpFast(tester);
      await tester.tap(find.byIcon(Icons.tune));
      await pumpFast(tester);

      // Palette: pick Obsidian.
      await tester.tap(find.text('Obsidian'));
      await pumpFast(tester);

      // Turn on dyslexia-friendly reading (the ONLY Switch in the row).
      final dyslexiaRow = find.ancestor(
        of: find.text('Dyslexia-friendly reading'),
        matching: find.byType(Row),
      );
      final dyslexiaSwitch = find.descendant(
        of: dyslexiaRow.first,
        matching: find.byType(Switch),
      );
      await tester.ensureVisible(dyslexiaSwitch);
      await pumpFast(tester);
      await tester.tap(dyslexiaSwitch);
      await pumpFast(tester);

      final settingsCtxBefore = tester.element(find.text('Settings').first);
      expect(AppSettingsScope.of(settingsCtxBefore).theme, AppTheme.obsidian);
      expect(AppSettingsScope.of(settingsCtxBefore).dyslexia, isTrue);

      // Restart: a new SesliKitapApp with the SAME prefs backing.
      // First fully unmount the old tree (prevent Navigator/State reuse
      // -- it simulates a real app relaunch).
      final restartedApp = await restartTestApp(services);
      await tester.pumpWidget(const SizedBox());
      await pumpFast(tester);
      await tester.pumpWidget(restartedApp);
      await pumpFast(tester);
      await tester.tap(find.byIcon(Icons.tune));
      await pumpFast(tester);

      final settingsCtxAfter = tester.element(find.text('Settings').first);
      expect(
        AppSettingsScope.of(settingsCtxAfter).theme,
        AppTheme.obsidian,
        reason: 'palette choice must be restored after restart',
      );
      expect(
        AppSettingsScope.of(settingsCtxAfter).dyslexia,
        isTrue,
        reason: 'dyslexia switch must be restored after restart',
      );
    });
  });
}
