import 'package:flutter/material.dart';
import 'package:sesli_kitap/src/onboarding/onboarding_prefs.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({required this.onFinish, super.key});

  final void Function(VoiceChoice) onFinish;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  VoiceChoice _selected = VoiceChoice.both;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 48),
                // Logo badge
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: palette.surface,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text(
                      's',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Kicker
                Text(
                  'AUDIOBOOK',
                  style: TextStyle(
                    color: palette.text2,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                // Title
                const Text(
                  'Welcome to the reading room',
                  style: TextStyle(fontSize: 29, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                // Description
                Text(
                  'Please choose the narrator you want to listen to.',
                  style: TextStyle(fontSize: 14, color: palette.text2),
                ),
                const SizedBox(height: 32),
                // Narrator selection heading
                Text(
                  'Choose a narrator voice',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 16),
                // 3 choice cards
                Row(
                  children: VoiceChoice.values.map((voice) {
                    final isSelected = _selected == voice;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: GestureDetector(
                          onTap: () => setState(() => _selected = voice),
                          child: Container(
                            height: 100,
                            decoration: BoxDecoration(
                              color: palette.surface,
                              border: Border.all(
                                color: isSelected
                                    ? palette.accent
                                    : palette.border,
                                width: isSelected ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Stack(
                              children: [
                                Center(
                                  child: Text(
                                    voiceChoiceLabel(voice),
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? palette.accent
                                          : palette.text,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Icon(
                                      Icons.check_circle,
                                      color: palette.accent,
                                      size: 20,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 40),
                // Start button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => widget.onFinish(_selected),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Start →',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
