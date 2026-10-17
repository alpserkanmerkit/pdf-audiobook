// FOUNDATION LAYER -- Android main manifest: permissions the release APK needs.
// Why: the Flutter template puts the INTERNET permission only in the debug/ and profile/
// manifests (for hot reload / VM service); if it is missing from the main manifest, the
// RELEASE APK has NO network access (the app makes HTTP calls to Gemini/DeepSeek/NVIDIA via
// lib/io/*). It works in debug, so it is not noticed when testing by hand.
// Source: https://docs.flutter.dev/data-and-backend/networking#android
//   ("Android apps must declare their use of the internet in the Android manifest";
//   <uses-permission android:name="android.permission.INTERNET" /> in the main manifest).
// File reading only inside the repo; no network / widgets -> milliseconds.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Strips XML comments (a permission line inside a comment must not be counted).
String _yorumsuz(String xml) =>
    xml.replaceAll(RegExp('<!--.*?-->', dotAll: true), '');

/// Permission names of the `<uses-permission android:name="..."/>` elements (simple
/// parsing is enough: package:xml is not a direct dependency).
Set<String> _izinler(String xml) => RegExp(
  r'<uses-permission\s+[^>]*?android:name\s*=\s*"([^"]+)"[^>]*>',
).allMatches(_yorumsuz(xml)).map((m) => m.group(1)!).toSet();

void main() {
  group('parser (synthetic)', () {
    test('a permission inside a comment is not counted; a real one is', () {
      const xml = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <!-- <uses-permission android:name="android.permission.CAMERA"/> -->
  <uses-permission android:name="android.permission.INTERNET"/>
  <uses-permission
      android:maxSdkVersion="32" android:name="android.permission.X" />
</manifest>''';
      expect(_izinler(xml), {
        'android.permission.INTERNET',
        'android.permission.X',
      });
    });
  });

  group('android/app/src/main/AndroidManifest.xml', () {
    final xml = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    test(
      'INTERNET permission is in the main manifest (release APK network access)',
      () {
        expect(
          _izinler(xml),
          contains('android.permission.INTERNET'),
          reason:
              'a permission in the debug/profile manifests does not reach the release APK',
        );
      },
    );
  });
}
