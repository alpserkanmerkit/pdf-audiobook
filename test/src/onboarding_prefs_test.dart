// Slice-13 RED test (oracle). lib/src/onboarding/onboarding_prefs.dart is written by a worker. PURE, 100%.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/onboarding/onboarding_prefs.dart';

void main() {
  group('VoiceChoice', () {
    test('3 choices + Turkish label', () {
      expect(VoiceChoice.values, hasLength(3));
      expect(voiceChoiceLabel(VoiceChoice.emel), 'Emel');
      expect(voiceChoiceLabel(VoiceChoice.ahmet), 'Ahmet');
      expect(voiceChoiceLabel(VoiceChoice.both), 'Both');
    });
  });

  group('OnboardingPrefs encode/decode', () {
    test('round-trip: onboarded + choice are preserved', () {
      const p = OnboardingPrefs(onboarded: true, choice: VoiceChoice.both);
      final restored = decodeOnboarding(encodeOnboarding(p));
      expect(restored.onboarded, isTrue);
      expect(restored.choice, VoiceChoice.both);
    });
    test('default (first launch): onboarded=false', () {
      const p = OnboardingPrefs.initial();
      expect(p.onboarded, isFalse);
      expect(p.choice, VoiceChoice.both);
    });
    test('corrupt/empty input -> initial (no crash)', () {
      final d = decodeOnboarding('broken json');
      expect(d.onboarded, isFalse);
    });
    test('invalid choice value -> both (firstWhere orElse branch)', () {
      final d = decodeOnboarding('{"onboarded":true,"choice":"invalid"}');
      expect(d.onboarded, isTrue);
      expect(d.choice, VoiceChoice.both);
    });
  });
}
