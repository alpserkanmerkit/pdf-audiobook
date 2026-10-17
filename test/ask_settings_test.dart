// Oracle RED tests: the "Ask" feature on/off setting (ReadingSettings.askEnabled)
// persistence in prefs -- same as the existing ReadingSettings field pattern (voice/rate).
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('askEnabled default: on (true)', () async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final reading = ReadingSettings(prefs)..load();
    expect(reading.askEnabled, isTrue);
  });

  test(
    'setAskEnabled(false) writes to prefs and notifies the listener',
    () async {
      SharedPreferences.setMockInitialValues(const {});
      final prefs = await SharedPreferences.getInstance();
      final reading = ReadingSettings(prefs);
      var notified = 0;
      reading
        ..addListener(() => notified++)
        ..setAskEnabled(false);
      expect(reading.askEnabled, isFalse);
      expect(prefs.getBool('askEnabled'), isFalse);
      expect(notified, 1);
    },
  );

  test('load(): the saved off value in prefs is read', () async {
    SharedPreferences.setMockInitialValues(const {'askEnabled': false});
    final prefs = await SharedPreferences.getInstance();
    final reading = ReadingSettings(prefs)..load();
    expect(reading.askEnabled, isFalse);
  });

  // (2026-09-28) save() tests removed: save() was never called in the app (dead code, deleted).
  // Persistence and the M13 pin are tested on the real path (setter -> load) in
  // test/settings_persistence_test.dart.
}
