// Oracle test (PHASE 4 wiring): do pronunciation rules flow from the settings
// object into the cache stamp? (The core pronRulesTag/CacheStamp is already
// gated by tests; this test verifies the LINK: settings → stamp.pronTag.)
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/io/page_pipeline.dart';
import 'package:sesli_kitap/src/pronunciation_rules.dart';
import 'package:sesli_kitap/src/voices.dart';

void main() {
  test(
    'PipelineSettings.stamp: with no rules pronTag is empty (old key preserved)',
    () {
      const s = PipelineSettings(
        geminiKey: 'k',
        voice: SesliVoice.ahmet,
        rate: 1,
        provider: 'edge',
      );
      expect(s.stamp.pronTag, '');
    },
  );

  test('PipelineSettings.stamp: rules enter the stamp via pronRulesTag', () {
    final rules = parsePronRules('Mir=Miir\n# comment\nGoethe=Göte');
    final s = PipelineSettings(
      geminiKey: 'k',
      voice: SesliVoice.ahmet,
      rate: 1,
      provider: 'edge',
      pronRules: rules,
    );
    expect(s.stamp.pronTag, pronRulesTag(rules));
    expect(s.stamp.pronTag.length, 8);

    // A rule change alters the stamp (the audio cache goes stale -- the intent of the spec).
    final other = PipelineSettings(
      geminiKey: 'k',
      voice: SesliVoice.ahmet,
      rate: 1,
      provider: 'edge',
      pronRules: parsePronRules('Mir=Mir'),
    );
    expect(other.stamp.pronTag, isNot(s.stamp.pronTag));
  });

  // PHASE-W4 (K24-pipeline): googleKey default is empty. The "carried if given"
  // half (old withGoogle echo) was removed: page_pipeline_provider_test.dart
  // :100 (prepareAudio) and :306 (resolveTtsProvider with FILLED googleKey ->
  // GoogleTts) prove behaviorally that the key really reaches dispatch.
  test('PipelineSettings.googleKey: default is empty', () {
    const withDefault = PipelineSettings(
      geminiKey: 'k',
      voice: SesliVoice.ahmet,
      rate: 1,
      provider: 'edge',
    );
    expect(withDefault.googleKey, '');
  });
}
