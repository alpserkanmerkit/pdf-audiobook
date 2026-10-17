import 'dart:convert';

enum VoiceChoice { emel, ahmet, both }

String voiceChoiceLabel(VoiceChoice c) {
  switch (c) {
    case VoiceChoice.emel:
      return 'Emel';
    case VoiceChoice.ahmet:
      return 'Ahmet';
    case VoiceChoice.both:
      return 'Both';
  }
}

class OnboardingPrefs {
  const OnboardingPrefs({required this.onboarded, required this.choice});

  const OnboardingPrefs.initial()
    : onboarded = false,
      choice = VoiceChoice.both;
  final bool onboarded;
  final VoiceChoice choice;

  Map<String, dynamic> toJson() => {
    'onboarded': onboarded,
    'choice': choice.name,
  };
}

String encodeOnboarding(OnboardingPrefs p) => jsonEncode(p.toJson());

OnboardingPrefs decodeOnboarding(String raw) {
  try {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final c = VoiceChoice.values.firstWhere(
      (v) => v.name == m['choice'],
      orElse: () => VoiceChoice.both,
    );
    return OnboardingPrefs(onboarded: m['onboarded'] == true, choice: c);
  } on Object catch (_) {
    return const OnboardingPrefs.initial();
  }
}
