// Provider consolidation (P4a, decision 0610 #58): the user picks the AI provider in Settings --
// Google (Gemini), DeepSeek, NVIDIA or "all" (those with a key entered, in order; if one fails, the next).
// This file pins the PURE selection logic (no network). Keys are fake values.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/llm_access.dart';

void main() {
  group('provider specs', () {
    test('Gemini: OpenAI-compatible Google endpoint + gemini-3.8-flash', () {
      final s = llmProviderSpec(LlmProvider.gemini);
      expect(
        s.endpoint,
        'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
      );
      expect(s.model, 'gemini-3.8-flash');
      expect(s.auditorModel, 'gemini-3.8-flash');
      expect(s.extraBody, {'reasoning_effort': 'low'});
      expect(s.label, 'Google (Gemini)');
    });

    test(
      'DeepSeek: official endpoint + v4-flash, auditor v4-pro, thinking disabled',
      () {
        final s = llmProviderSpec(LlmProvider.deepseek);
        expect(s.endpoint, 'https://api.deepseek.com/chat/completions');
        expect(s.model, 'deepseek-v4-flash');
        expect(s.auditorModel, 'deepseek-v4-pro');
        expect(s.extraBody, {
          'thinking': {'type': 'disabled'},
        });
        expect(s.label, 'DeepSeek');
      },
    );

    test(
      'NVIDIA: integrate endpoint + deepseek-v4.1-flash, auditor nemotron',
      () {
        final s = llmProviderSpec(LlmProvider.nvidia);
        expect(
          s.endpoint,
          'https://integrate.api.nvidia.com/v1/chat/completions',
        );
        expect(s.model, 'deepseek-ai/deepseek-v4.1-flash');
        expect(s.auditorModel, 'nvidia/nemotron-3-ultra-550b-a55b');
        expect(s.extraBody, isEmpty);
        expect(s.label, 'NVIDIA');
      },
    );
  });

  group('choice labels', () {
    test('four choices and their Turkish labels', () {
      expect(LlmChoice.values, ['gemini', 'deepseek', 'nvidia', 'all']);
      expect(LlmChoice.label('gemini'), 'Google (Gemini)');
      expect(LlmChoice.label('deepseek'), 'DeepSeek');
      expect(LlmChoice.label('nvidia'), 'NVIDIA');
      expect(LlmChoice.label('all'), 'All (with keys entered)');
      expect(LlmChoice.label('bilinmeyen'), 'Google (Gemini)');
    });
  });

  group('LlmAccess.fromSettings', () {
    List<LlmProvider> providers(LlmAccess a) =>
        a.routes.map((r) => r.provider).toList();

    test('a single provider choice uses only its own key', () {
      final a = LlmAccess.fromSettings(
        choice: 'deepseek',
        geminiKey: 'g',
        deepseekKey: ' d ',
        nvidiaKey: 'n',
      );
      expect(providers(a), [LlmProvider.deepseek]);
      expect(a.routes.single.apiKey, 'd', reason: 'key is trimmed');
      expect(a.isConfigured, isTrue);
    });

    test(
      "if the chosen provider's key is empty there is NO access (does not fall back to another)",
      () {
        final a = LlmAccess.fromSettings(
          choice: 'nvidia',
          geminiKey: 'g',
          deepseekKey: 'd',
          nvidiaKey: '   ',
        );
        expect(a.routes, isEmpty);
        expect(a.isConfigured, isFalse);
      },
    );

    test(
      '"all": those with keys filled, order Gemini -> DeepSeek -> NVIDIA',
      () {
        final a = LlmAccess.fromSettings(
          choice: 'all',
          deepseekKey: 'd',
          nvidiaKey: 'n',
        );
        expect(providers(a), [LlmProvider.deepseek, LlmProvider.nvidia]);
        final full = LlmAccess.fromSettings(
          choice: 'all',
          geminiKey: 'g',
          deepseekKey: 'd',
          nvidiaKey: 'n',
        );
        expect(providers(full), [
          LlmProvider.gemini,
          LlmProvider.deepseek,
          LlmProvider.nvidia,
        ]);
      },
    );

    test('unknown/legacy choice -> Gemini (existing user is not broken)', () {
      final a = LlmAccess.fromSettings(choice: 'eski', geminiKey: 'g');
      expect(providers(a), [LlmProvider.gemini]);
      expect(a.routes.single.apiKey, 'g');
    });

    test('Gemini choice', () {
      final a = LlmAccess.fromSettings(choice: 'gemini', geminiKey: 'g');
      expect(providers(a), [LlmProvider.gemini]);
    });

    test('single: given provider + key as-is', () {
      final a = LlmAccess.single(LlmProvider.nvidia, 'n');
      expect(providers(a), [LlmProvider.nvidia]);
      expect(a.routes.single.apiKey, 'n');
    });
  });
}
