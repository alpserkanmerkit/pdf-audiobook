import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sesli_kitap/io/audio_playback.dart';
import 'package:sesli_kitap/src/onboarding/onboarding_prefs.dart';
import 'package:sesli_kitap/src/theme/palette.dart' show AppMode, AppTheme;
import 'package:sesli_kitap/src/voices.dart';
import 'package:sesli_kitap/ui/app_shell.dart';
import 'package:sesli_kitap/ui/screens/onboarding_screen.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads the onboarding state from SharedPreferences.
/// Returns false if the 'onboarding' key is missing or cannot be decoded.
bool resolveInitialOnboarded(SharedPreferences prefs) {
  final raw = prefs.getString('onboarding');
  if (raw == null) return false;
  return decodeOnboarding(raw).onboarded;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final dataDir = await getApplicationDocumentsDirectory();
  runApp(
    SesliKitapApp(
      services: AppServices(prefs: prefs, dataDir: dataDir)..reading.load(),
      initialOnboarded: resolveInitialOnboarded(prefs),
    ),
  );
}

class SesliKitapApp extends StatefulWidget {
  const SesliKitapApp({
    required this.services,
    super.key,
    this.initialOnboarded = true,
  });

  final AppServices services;
  final bool initialOnboarded;

  @override
  State<SesliKitapApp> createState() => _SesliKitapAppState();
}

class _SesliKitapAppState extends State<SesliKitapApp> {
  late final AppSettings _settings;
  late bool _onboarded = widget.initialOnboarded;
  // Crash guard (WER 26.06.2026, Windows.Media.dll use-after-free):
  // On Windows the window close is turned into a cancellable exit; native
  // players are closed by the Dart side BEFORE the engine teardown.
  late final AppLifecycleListener _lifecycle;

  void _persistSettings() {
    final p = widget.services.prefs;
    unawaited(p.setString('theme', _settings.theme.name));
    unawaited(p.setString('mode', _settings.mode.name));
    unawaited(p.setBool('highContrast', _settings.highContrast));
    unawaited(p.setBool('dyslexia', _settings.dyslexia));
    unawaited(p.setDouble('fontScale', _settings.fontScale));
    unawaited(p.setBool('sonic', _settings.sonic));
    unawaited(p.setBool('daylight', _settings.daylight));
  }

  @override
  void initState() {
    super.initState();
    final p = widget.services.prefs;
    final themeStr = p.getString('theme');
    final modeStr = p.getString('mode');
    _settings = AppSettings(
      theme: themeStr != null
          ? AppTheme.values.byName(themeStr)
          : AppTheme.cognac,
      mode: modeStr != null ? AppMode.values.byName(modeStr) : AppMode.dark,
      highContrast: p.getBool('highContrast') ?? false,
      dyslexia: p.getBool('dyslexia') ?? false,
      fontScale: p.getDouble('fontScale') ?? 1.0,
      sonic: p.getBool('sonic') ?? true,
      daylight: p.getBool('daylight') ?? true,
      onChanged: _persistSettings,
    );
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await GuardedAudioPlayer.disposeAll();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _settings.dispose();
    unawaited(widget.services.disposePlayers());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppServicesScope(
      services: widget.services,
      child: AppSettingsScope(
        settings: _settings,
        child: ListenableBuilder(
          listenable: _settings,
          builder: (context, _) => MaterialApp(
            title: 'Audiobook',
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(_settings),
            // S5: the "Text size" setting from Settings is applied here; since it sits
            // inside the ListenableBuilder, a change is LIVE-propagated to the whole app.
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(_settings.fontScale)),
              child: child!,
            ),
            home: _onboarded
                ? const AppShell()
                : OnboardingScreen(
                    onFinish: (choice) {
                      unawaited(
                        widget.services.prefs.setString(
                          'onboarding',
                          encodeOnboarding(
                            OnboardingPrefs(onboarded: true, choice: choice),
                          ),
                        ),
                      );
                      final mappedVoice = switch (choice) {
                        VoiceChoice.emel => SesliVoice.emel,
                        VoiceChoice.ahmet => SesliVoice.ahmet,
                        VoiceChoice.both => SesliVoice.ahmet,
                      };
                      widget.services.reading.setVoice(voiceId(mappedVoice));
                      setState(() => _onboarded = true);
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
