// Oracle test (2026-09-28, audit finding "save() is dead code"):
// In the app, settings are persisted NOT via ReadingSettings.save() but by each setter
// writing to prefs immediately (settings_screen.dart setGeminiKey /
// setGoogleKey / setProvider / setVoice / setVoiceEn / setRate /
// setPronRulesRaw / setAskEnabled call it; save() was never called in lib).
// This test pins the REAL path: setter -> a new ReadingSettings.load() reads the same
// value. The old M13 pin (LLM key stored as 'geminiKey', the old
// 'nvidiaKey' is NOT written) was moved from save() to this real path.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('every setting is written via its setter; a new ReadingSettings.load() '
      'reads back the same value (app restart)', () async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    ReadingSettings(prefs)
      ..setGeminiKey('g-key')
      ..setGoogleKey('go-key')
      ..setProvider('google')
      ..setVoice('tr-TR-AhmetNeural')
      ..setVoiceEn('en-US-Wavenet-D')
      ..setRate(1.25)
      ..setPronRulesRaw('Freud=Froyd')
      ..setAskEnabled(false);

    final reopened = ReadingSettings(prefs)..load();
    expect(reopened.geminiKey, 'g-key');
    expect(reopened.googleKey, 'go-key');
    expect(reopened.provider, 'google');
    expect(reopened.voice, 'tr-TR-AhmetNeural');
    expect(reopened.voiceEn, 'en-US-Wavenet-D');
    expect(reopened.rate, 1.25);
    expect(reopened.pronRulesRaw, 'Freud=Froyd');
    expect(reopened.askEnabled, isFalse);
  });

  test('LLM key is written as geminiKey; old nvidiaKey is not written '
      '(M13 pin on the real path)', () async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    ReadingSettings(prefs).setGeminiKey('g-key');
    expect(prefs.getString('geminiKey'), 'g-key');
    expect(prefs.containsKey('nvidiaKey'), isFalse);
  });
}
