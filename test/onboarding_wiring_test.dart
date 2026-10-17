// Slice-13 WIRING test (§13.7 — oracle). Onboarding first-launch flow: initialOnboarded:false
// -> narrator-choice modal -> Start → -> Library (AppShell). Existing tests default to onboarded=true.
//
// FAZ-W5 (K19) additions (oracle RED): onboarding is now PERSISTED in prefs.
// Contract (the main.dart worker implementation MUST follow this):
//  - prefs key: 'onboarding' (String), value = encodeOnboarding(OnboardingPrefs).
//  - resolveInitialOnboarded(SharedPreferences) top-level PUBLIC function,
//    defined in main.dart: no key -> false; if it cannot be decoded (corrupt data)
//    -> false (decodeOnboarding already returns OnboardingPrefs.initial() on corrupt data,
//    so no extra try/catch is needed in main.dart); if valid -> OnboardingPrefs.onboarded.
//  - onFinish(VoiceChoice choice): (a) writes onboarded:true + choice to the 'onboarding'
//    key via encodeOnboarding; (b) choice -> SesliVoice mapping: emel->SesliVoice.emel,
//    ahmet->SesliVoice.ahmet, both->SesliVoice.ahmet (default/first option); (c) the mapped
//    voice is passed to services.reading.setVoice(...) via voiceId(); (d) setState.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/onboarding/onboarding_prefs.dart';
import 'package:sesli_kitap/src/voices.dart';
import 'helpers/test_app.dart';

void main() {
  testWidgets('first launch (initialOnboarded:false) shows onboarding', (
    tester,
  ) async {
    await tester.pumpWidget(await buildTestApp(initialOnboarded: false));
    await tester.pumpAndSettle();
    expect(find.textContaining('Welcome to the reading room'), findsWidgets);
    expect(find.text('Emel'), findsWidgets);
    expect(find.text('Ahmet'), findsWidgets);
    expect(find.text('Both'), findsWidgets);
  });

  testWidgets('Start -> Library (AppShell) opens', (tester) async {
    await tester.pumpWidget(await buildTestApp(initialOnboarded: false));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Start →'));
    await tester.pumpAndSettle();
    expect(find.text('Your library'), findsWidgets);
  });

  testWidgets('default (onboarded) goes straight to Library', (tester) async {
    await tester.pumpWidget(await buildTestApp());
    await tester.pumpAndSettle();
    expect(find.text('Your library'), findsWidgets);
  });

  group('FAZ-W5 (K19) — onboarding persistence', () {
    testWidgets(
      't1: empty/fresh prefs (real prefs path) -> OnboardingScreen is shown',
      (tester) async {
        await tester.pumpWidget(await buildTestAppFromPrefs());
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Welcome to the reading room'),
          findsWidgets,
        );
        expect(find.text('Your library'), findsNothing);
      },
    );

    testWidgets(
      't2: prefs pre-filled with onboarded=true -> AppShell directly',
      (tester) async {
        const seeded = OnboardingPrefs(
          onboarded: true,
          choice: VoiceChoice.emel,
        );
        await tester.pumpWidget(
          await buildTestAppFromPrefs(
            prefsValues: <String, Object>{
              'onboarding': encodeOnboarding(seeded),
            },
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Your library'), findsWidgets);
        expect(
          find.textContaining('Welcome to the reading room'),
          findsNothing,
        );
      },
    );

    testWidgets(
      't3: onboarding completes (Ahmet chosen) -> prefs are persisted, '
      'the voice is reflected in services.reading.voice, and it persists after restart',
      (tester) async {
        final app = await buildTestAppFromPrefs();
        await tester.pumpWidget(app);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Ahmet'));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Start →'));
        await tester.pumpAndSettle();

        expect(find.text('Your library'), findsWidgets);
        expect(app.services.reading.voice, voiceId(SesliVoice.ahmet));

        final rawAfter = app.services.prefs.getString('onboarding');
        expect(rawAfter, isNotNull);
        final decodedAfter = decodeOnboarding(rawAfter!);
        expect(decodedAfter.onboarded, isTrue);
        expect(decodedAfter.choice, VoiceChoice.ahmet);

        // Fresh process (same prefs backend) -- onboarding is NOT shown AGAIN,
        // the chosen voice comes through, carried over to AppServices.
        final restarted = await restartTestAppFromPrefs(app.services);
        await tester.pumpWidget(restarted);
        await tester.pumpAndSettle();
        expect(find.text('Your library'), findsWidgets);
        expect(
          find.textContaining('Welcome to the reading room'),
          findsNothing,
        );
        expect(restarted.services.reading.voice, voiceId(SesliVoice.ahmet));
      },
    );

    testWidgets(
      't4: broken/invalid onboarding value -> no crash, OnboardingScreen '
      'is shown (corrupt data = treated as not onboarded)',
      (tester) async {
        await tester.pumpWidget(
          await buildTestAppFromPrefs(
            prefsValues: const <String, Object>{
              'onboarding': 'this-is-not-valid-json {{{',
            },
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.textContaining('Welcome to the reading room'),
          findsWidgets,
        );
        expect(find.text('Your library'), findsNothing);
      },
    );
  });
}
