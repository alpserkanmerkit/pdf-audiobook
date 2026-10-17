// AI provider selection (pure logic, no network).
// The user picks in Settings: Google (Gemini), DeepSeek, NVIDIA, or "all"
// (providers with a key entered, in order; if one fails the next is tried --
// the attempt happens in lib/io/llm_client.dart). Endpoint/model values were
// carried over from two older apps: DeepSeek (old sesli-kitap), NVIDIA
// (dc0e588), Gemini (bc21932).

enum LlmProvider { gemini, deepseek, nvidia }

class LlmProviderSpec {
  const LlmProviderSpec({
    required this.label,
    required this.endpoint,
    required this.model,
    required this.auditorModel,
    this.extraBody = const {},
  });

  final String label;
  final String endpoint;
  final String model;
  final String auditorModel;

  /// Provider-specific body fields; they OVERRIDE the caller's body.
  final Map<String, Object?> extraBody;
}

const LlmProviderSpec _gemini = LlmProviderSpec(
  label: 'Google (Gemini)',
  endpoint:
      'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
  model: 'gemini-3.8-flash',
  auditorModel: 'gemini-3.8-flash',
  // Measured: the default thinking budget cuts the text off early.
  extraBody: {'reasoning_effort': 'low'},
);

const LlmProviderSpec _deepseek = LlmProviderSpec(
  label: 'DeepSeek',
  endpoint: 'https://api.deepseek.com/chat/completions',
  model: 'deepseek-v4-flash',
  auditorModel: 'deepseek-v4-pro',
  // v4-flash enables thinking by default (latency); it was off in the old app.
  extraBody: {
    'thinking': {'type': 'disabled'},
  },
);

const LlmProviderSpec _nvidia = LlmProviderSpec(
  label: 'NVIDIA',
  endpoint: 'https://integrate.api.nvidia.com/v1/chat/completions',
  model: 'deepseek-ai/deepseek-v4.1-flash',
  auditorModel: 'nvidia/nemotron-3-ultra-550b-a55b',
);

LlmProviderSpec llmProviderSpec(LlmProvider p) => switch (p) {
  LlmProvider.gemini => _gemini,
  LlmProvider.deepseek => _deepseek,
  LlmProvider.nvidia => _nvidia,
};

/// Selection values stored in settings.
abstract final class LlmChoice {
  static const String gemini = 'gemini';
  static const String deepseek = 'deepseek';
  static const String nvidia = 'nvidia';
  static const String all = 'all';

  static const List<String> values = [gemini, deepseek, nvidia, all];

  static String label(String choice) => switch (choice) {
    deepseek => _deepseek.label,
    nvidia => _nvidia.label,
    all => 'All (with keys entered)',
    _ => _gemini.label,
  };
}

class LlmRoute {
  const LlmRoute(this.provider, this.apiKey);

  final LlmProvider provider;
  final String apiKey;
}

/// Providers an LLM request will be tried against, in order.
class LlmAccess {
  const LlmAccess(this.routes);

  /// Single provider, key AS-IS (the equivalent of the old `apiKey:` calls).
  LlmAccess.single(LlmProvider provider, String apiKey)
    : routes = [LlmRoute(provider, apiKey)];

  /// From the settings choice. A provider with an empty (trimmed) key is
  /// skipped; for a single choice, an empty key means NO access (it does not
  /// fall back to another provider). Unknown choice = Gemini (old users are
  /// not broken).
  factory LlmAccess.fromSettings({
    required String choice,
    String geminiKey = '',
    String deepseekKey = '',
    String nvidiaKey = '',
  }) {
    final keys = {
      LlmProvider.gemini: geminiKey.trim(),
      LlmProvider.deepseek: deepseekKey.trim(),
      LlmProvider.nvidia: nvidiaKey.trim(),
    };
    final wanted = switch (choice) {
      LlmChoice.all => LlmProvider.values,
      LlmChoice.deepseek => const [LlmProvider.deepseek],
      LlmChoice.nvidia => const [LlmProvider.nvidia],
      _ => const [LlmProvider.gemini],
    };
    return LlmAccess([
      for (final p in wanted)
        if (keys[p]!.isNotEmpty) LlmRoute(p, keys[p]!),
    ]);
  }

  final List<LlmRoute> routes;

  bool get isConfigured => routes.isNotEmpty;
}
