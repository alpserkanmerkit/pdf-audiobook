// Provider merge (P4a, decision 0610 #58): in Settings > ACCOUNT & API,
// "AI provider" is picked (Google (Gemini) / DeepSeek / NVIDIA / All (with keys entered));
// DeepSeek and NVIDIA keys are entered on separate rows. Choice + keys
// are persisted; ReadingSettings.llmAccess is built from the choice. Keys are fake.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/main.dart';
import 'package:sesli_kitap/src/llm_access.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/pump_fast.dart';
import 'helpers/test_app.dart';

void main() {
  test('choice + DeepSeek/NVIDIA keys persisted; default is Gemini', () async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final fresh = ReadingSettings(prefs)..load();
    expect(fresh.llmChoice, 'gemini');

    ReadingSettings(prefs)
      ..setLlmChoice('all')
      ..setDeepseekApiKey('ds-fake')
      ..setNvidiaApiKey('nv-fake');

    final reopened = ReadingSettings(prefs)..load();
    expect(reopened.llmChoice, 'all');
    expect(reopened.deepseekApiKey, 'ds-fake');
    expect(reopened.nvidiaApiKey, 'nv-fake');
    expect(reopened.llmAccess.routes.map((r) => r.provider).toList(), [
      LlmProvider.deepseek,
      LlmProvider.nvidia,
    ]);
  });

  test('old migration pin kept: old deepseekKey/nvidiaKey are still removed, '
      'new key names are distinct', () async {
    SharedPreferences.setMockInitialValues(const {
      'deepseekKey': 'old',
      'nvidiaKey': 'old',
      'deepseekApiKey': 'new-d',
    });
    final prefs = await SharedPreferences.getInstance();
    final s = ReadingSettings(prefs)..load();
    expect(prefs.containsKey('deepseekKey'), isFalse);
    expect(prefs.containsKey('nvidiaKey'), isFalse);
    expect(s.deepseekApiKey, 'new-d');
  });

  test('tutor LLM: only DeepSeek selected with a key -> NOT null', () async {
    final services = await buildTestServices();
    services.reading
      ..load()
      ..setLlmChoice('deepseek')
      ..setDeepseekApiKey('ds-fake');
    expect(services.tutorLlm(), isNotNull);
    services.reading.setLlmChoice('nvidia');
    expect(services.tutorLlm(), isNull, reason: 'no NVIDIA key');
  });

  testWidgets(
    'Settings: provider choice "All (with keys entered)" -> persisted',
    (tester) async {
      final services = await buildTestServices();
      await tester.pumpWidget(
        SesliKitapApp(services: services..reading.load()),
      );
      await pumpFast(tester);
      await tester.tap(find.byIcon(Icons.tune));
      await pumpFast(tester);

      await tester.ensureVisible(find.text('AI provider'));
      await pumpFast(tester);
      expect(find.text('Google (Gemini)'), findsOneWidget);
      await tester.tap(find.text('AI provider'));
      await pumpFast(tester);

      for (final c in LlmChoice.values) {
        expect(find.text(LlmChoice.label(c)), findsWidgets);
      }
      await tester.tap(find.text('All (with keys entered)').last);
      await pumpFast(tester);

      expect(services.reading.llmChoice, 'all');
      expect(find.text('All (with keys entered)'), findsOneWidget);
      final restarted = await restartTestServices(services);
      restarted.reading.load();
      expect(restarted.reading.llmChoice, 'all');
    },
  );

  for (final row in const [
    ('DeepSeek API key', 'deepseek'),
    ('NVIDIA API key', 'nvidia'),
  ]) {
    testWidgets('Settings: ${row.$1} row -> persisted', (tester) async {
      final services = await buildTestServices();
      await tester.pumpWidget(
        SesliKitapApp(services: services..reading.load()),
      );
      await pumpFast(tester);
      await tester.tap(find.byIcon(Icons.tune));
      await pumpFast(tester);

      await tester.ensureVisible(find.text(row.$1));
      await pumpFast(tester);
      await tester.tap(find.text(row.$1));
      await pumpFast(tester);
      await tester.enterText(find.byType(TextField).first, 'fake-key');
      await tester.tap(find.text('Save'));
      await pumpFast(tester);

      final restarted = await restartTestServices(services);
      restarted.reading.load();
      final saved = row.$2 == 'deepseek'
          ? restarted.reading.deepseekApiKey
          : restarted.reading.nvidiaApiKey;
      expect(saved, 'fake-key');
    });
  }
}
