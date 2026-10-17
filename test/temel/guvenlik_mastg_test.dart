// FOUNDATION LAYER (B) -- Mobile security, STATIC scan. No ICAT in this file; the test
// identifiers / checklist are taken from OWASP MASTG/MASVS, and each check names its
// source in the comment next to it. No Flutter widgets, no network, file system reads
// only inside the repo -> every test takes milliseconds.
//
// SOURCES
//   OWASP MASVS (checklist)         https://mas.owasp.org/MASVS/
//   OWASP MASTG (test catalog)      https://mas.owasp.org/MASTG/tests/
//     MASTG-TEST-0287 Runtime Storage of Unencrypted Data via the
//        SharedPreferences API (MASVS-STORAGE-1)
//        https://mas.owasp.org/MASTG/tests/android/MASVS-STORAGE/MASTG-TEST-0287/
//     MASTG-TEST-0001 Testing Local Storage for Sensitive Data
//        https://mas.owasp.org/MASTG/tests/android/MASVS-STORAGE/MASTG-TEST-0001/
//     MASTG-TEST-0262 References to Backup Configurations Not Excluding
//        Sensitive Data (MASVS-STORAGE-2; also MASTG-TEST-0216/0009,
//        MASTG-BEST-0004 "Exclude Sensitive Data from Backups")
//        https://mas.owasp.org/MASTG/tests/android/MASVS-STORAGE/MASTG-TEST-0262/
//     MASTG-TEST-0231 References to Logging APIs (MASVS-STORAGE-2;
//        MASTG-BEST-0002 "Remove Logging Code")
//        https://mas.owasp.org/MASTG/tests/android/MASVS-STORAGE/MASTG-TEST-0231/
//     MASTG-TEST-0233 Hardcoded HTTP URLs (MASVS-NETWORK-1)
//        https://mas.owasp.org/MASTG/tests/android/MASVS-NETWORK/MASTG-TEST-0233/
//     MASTG-TEST-0235 Android App Configurations Allowing Cleartext Traffic
//        https://mas.owasp.org/MASTG/tests/android/MASVS-NETWORK/MASTG-TEST-0235/
//     MASTG-TEST-0237 Cross-Platform Framework Configurations Allowing
//        Cleartext Traffic; MASTG-TEST-0286 NSC Allowing User-Provided CAs
//     MASTG-TEST-0212 Use of Hardcoded Cryptographic Keys in Code
//        https://mas.owasp.org/MASTG/tests/android/MASVS-CRYPTO/MASTG-TEST-0212/
//     MASTG-TEST-0226 Debuggable Flag Enabled in the AndroidManifest
//        (MASTG-BEST-0007), MASTG-TEST-0227 Debugging Enabled for WebViews,
//        MASTG-TEST-0031 Testing JavaScript Execution in WebViews
//        https://mas.owasp.org/MASTG/tests/android/MASVS-RESILIENCE/MASTG-TEST-0226/
//     MASTG-TEST-0038 Making Sure that the App is Properly Signed
//        https://mas.owasp.org/MASTG/tests/android/MASVS-RESILIENCE/MASTG-TEST-0038/
//     MASTG-TEST-0024 Testing for App Permissions / MASTG-TEST-0254 Dangerous
//        App Permissions; MASTG-TEST-0364 Exported And Unprotected Activities
//     MASTG-TEST-0006 / -0258 Keyboard cache of text input fields
//   gitleaks default rule set (secret patterns; the whole git history is
//   scanned): rule ids aws-access-token, gcp-api-key, github-pat, openai-api-key,
//   private-key, slack-bot-token, generic-api-key --
//   https://github.com/gitleaks/gitleaks/blob/master/config/gitleaks.toml
//
// RATCHET: real violations are kept in the [bilinenBulgular] map under an EXPLICIT name,
// with MASTG id, reason and recommended fix (a violation is NOT shown green, and the test
// is NOT loosened). Rule: the set of findings found == the known set. A new finding =
// RED; if a finding is fixed (dropped from the set) it is also RED ("delete the entry").
//
// CONFLICT: no other test under test/ covers these areas (grep: allowBackup,
// usesCleartextTraffic, debuggable, SharedPreferences+Key -> 0 results). The gitleaks
// in CI scans only the secret PATTERNS in git history; this file measures the STRUCTURAL
// findings gitleaks does not see (manifest flags, plain-prefs writing of the key, the
// argument of a log call, http:// literals).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Known findings (existing debt) -- TRANSPARENT RECORD
// ---------------------------------------------------------------------------

// Finding fields are for documentation (a record only; the test does not read them).
// ignore_for_file: unreachable_from_main
class Bulgu {
  const Bulgu({
    required this.mastg,
    required this.masvs,
    required this.gerekce,
    required this.oneri,
    required this.tarih,
  });
  final String mastg;
  final String masvs;
  final String gerekce;
  final String oneri;
  final String tarih;
}

const String _prefsGerekce =
    'The API key is written to SharedPreferences as PLAIN TEXT (Android: '
    'shared_prefs/FlutterSharedPreferences.xml, key "flutter.<name>"; '
    'Windows: user data folder JSON). It is readable with root access / from a backup / '
    'if the device is lost.';
const String _prefsOneri =
    'Store it with flutter_secure_storage (Android Keystore + EncryptedSharedPreferences, '
    'Windows DPAPI/Credential Locker); move it out of prefs and delete the old copy. '
    'NOTE: pubspec/behavior was NOT changed in this task (out of scope).';

const Map<String, Bulgu> bilinenBulgular = <String, Bulgu>{
  'depolama-duz-prefs:geminiKey': Bulgu(
    mastg: 'MASTG-TEST-0287 / MASTG-TEST-0001',
    masvs: 'MASVS-STORAGE-1',
    gerekce: _prefsGerekce,
    oneri: _prefsOneri,
    tarih: '2026-10-07',
  ),
  'depolama-duz-prefs:googleKey': Bulgu(
    mastg: 'MASTG-TEST-0287 / MASTG-TEST-0001',
    masvs: 'MASVS-STORAGE-1',
    gerekce: _prefsGerekce,
    oneri: _prefsOneri,
    tarih: '2026-10-07',
  ),
  'depolama-duz-prefs:deepseekApiKey': Bulgu(
    mastg: 'MASTG-TEST-0287 / MASTG-TEST-0001',
    masvs: 'MASVS-STORAGE-1',
    gerekce: _prefsGerekce,
    oneri: _prefsOneri,
    tarih: '2026-10-07',
  ),
  'depolama-duz-prefs:nvidiaApiKey': Bulgu(
    mastg: 'MASTG-TEST-0287 / MASTG-TEST-0001',
    masvs: 'MASVS-STORAGE-1',
    gerekce: _prefsGerekce,
    oneri: _prefsOneri,
    tarih: '2026-10-07',
  ),
  'imza:release-debug-anahtariyla-imzali': Bulgu(
    mastg: 'MASTG-TEST-0038',
    masvs: 'MASVS-RESILIENCE-2',
    gerekce:
        'android/app/build.gradle.kts release buildType '
        'signingConfig = signingConfigs.getByName("debug") (Flutter template '
        'TODO): the release APK is signed with the publicly known debug key; there is no '
        'protection against repackaging / update hijacking.',
    oneri:
        'Before release, define signingConfigs.release with your own upload keystore + '
        'key.properties (the keystore is OUTSIDE the repo).',
    tarih: '2026-10-07',
  ),
};

/// Known finding IDs that start with [kategori] (example: 'depolama-duz-prefs').
Set<String> _bilinen(String kategori) => bilinenBulgular.keys
    .where((k) => k == kategori || k.startsWith('$kategori:'))
    .toSet();

/// Ratchet verdict: found == known. New -> red (detailed); missing (improvement) -> red
/// (delete the entry).
void _beklenenBulgular(String kategori, Set<String> bulunan) {
  final bilinen = _bilinen(kategori);
  final yeni = bulunan.difference(bilinen);
  final duzelen = bilinen.difference(bulunan);
  expect(
    yeni,
    isEmpty,
    reason:
        'NEW security finding ($kategori): $yeni -- fix it; IF IT CANNOT BE FIXED, '
        'add it to bilinenBulgular with reason + MASTG id (no silent additions).',
  );
  expect(
    duzelen,
    isEmpty,
    reason:
        'IMPROVEMENT: $duzelen is no longer found -> delete the bilinenBulgular entry '
        '(strict ratchet: an old debt record cannot stay).',
  );
}

// ---------------------------------------------------------------------------
// File helpers (hermetic: reads only from the repo root)
// ---------------------------------------------------------------------------

String _oku(String yol) {
  final f = File(yol);
  expect(
    f.existsSync(),
    isTrue,
    reason: '$yol not found (the working directory must be the repo root)',
  );
  return f.readAsStringSync();
}

/// Files (recursive) under [dizin] whose extension is one of [uzantilar].
List<File> _dosyalar(String dizin, List<String> uzantilar) {
  final d = Directory(dizin);
  if (!d.existsSync()) return const [];
  return d
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((f) => uzantilar.any((u) => f.path.endsWith(u)))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// Strips comment lines (// and ///); keeps the line numbers.
String _yorumsuz(String src) => src
    .split('\n')
    .map((l) => l.trimLeft().startsWith('//') ? '' : l)
    .join('\n');

final List<String> _manifestler = <String>[
  'android/app/src/main/AndroidManifest.xml',
  'android/app/src/debug/AndroidManifest.xml',
  'android/app/src/profile/AndroidManifest.xml',
];

/// The android:* attributes of the `<application ...>` tag (empty if there is no tag:
/// the debug/profile manifests carry only permissions).
Map<String, String> _applicationOznitelikleri(String manifest) {
  final m = RegExp(
    r'<application\b([^>]*)>',
    dotAll: true,
  ).firstMatch(manifest);
  if (m == null) return const {};
  return {
    for (final a in RegExp(
      r'(android:\w+)\s*=\s*"([^"]*)"',
    ).allMatches(m.group(1)!))
      a.group(1)!: a.group(2)!,
  };
}

// ---------------------------------------------------------------------------
// Scanners (self-testing: synthetic positive/negative probes below)
// ---------------------------------------------------------------------------

/// Plain-text prefs writes of key-like names: `.setString('<name>'` where the name contains
/// key|token|secret|password|passwd.
Set<String> _duzPrefsSirlari(String src) => {
  for (final m in RegExp(
    r'''\.setString\(\s*['"]([^'"$]*(?:[Kk]ey|[Tt]oken|[Ss]ecret|[Pp]ass(?:wor)?d)[^'"$]*)['"]''',
  ).allMatches(_yorumsuz(src)))
    m.group(1)!,
};

/// Argument text of log calls ([print], `debugPrint`, developer.log, stdout/stderr writes)
/// (parentheses balanced, quotes respected).
List<String> _logCagriArgumanlari(String src) {
  final kod = _yorumsuz(src);
  final out = <String>[];
  final bas = RegExp(
    r'(?<![\w.])(?:print|debugPrint|debugPrintStack|developer\.log|stdout\.writeln|stdout\.write|stderr\.writeln|stderr\.write)\s*\(',
  );
  for (final m in bas.allMatches(kod)) {
    var i = m.end;
    var derinlik = 1;
    String? tirnak;
    final sb = StringBuffer();
    while (i < kod.length && derinlik > 0) {
      final c = kod[i];
      if (tirnak != null) {
        if (c == r'\') {
          sb.write(c);
          i++;
          if (i < kod.length) sb.write(kod[i]);
          i++;
          continue;
        }
        if (c == tirnak) tirnak = null;
      } else if (c == "'" || c == '"') {
        tirnak = c;
      } else if (c == '(') {
        derinlik++;
      } else if (c == ')') {
        derinlik--;
        if (derinlik == 0) break;
      }
      sb.write(c);
      i++;
    }
    out.add(sb.toString());
  }
  return out;
}

final RegExp _hassasAd = RegExp(
  '(?:api[_-]?key|apikey|authorization|bearer|geminiKey|googleKey|'
  'deepseekApiKey|nvidiaApiKey|azureKey|subscriptionKey|password|passwd|'
  r'secret|\btoken\b)',
  caseSensitive: false,
);

/// Secret patterns. Source: gitleaks default rules (ids next to them); '*' = not exactly
/// in gitleaks, a provider key format.
final List<({String id, RegExp re})> _sirKurallari = <({String id, RegExp re})>[
  (
    id: 'aws-access-token',
    re: RegExp(r'\b((?:A3T[A-Z0-9]|AKIA|ASIA|ABIA|ACCA)[A-Z2-7]{16})\b'),
  ),
  (
    id: 'gcp-api-key',
    re: RegExp(r'''\b(AIza[\w-]{35})(?:[\x60'"\s;]|\\[nr]|$)'''),
  ),
  (id: 'github-pat', re: RegExp('ghp_[0-9a-zA-Z]{36}')),
  (
    id: 'slack-bot-token',
    re: RegExp('xoxb-[0-9]{10,13}-[0-9]{10,13}[a-zA-Z0-9-]*'),
  ),
  (
    id: 'private-key',
    re: RegExp(
      '-----BEGIN[ A-Z0-9_-]{0,100}PRIVATE KEY(?: BLOCK)?-----',
      caseSensitive: false,
    ),
  ),
  (
    id: 'openai-api-key',
    re: RegExp(r'\bsk-(?:proj|svcacct|admin)-[A-Za-z0-9_-]{40,}'),
  ),
  (id: '*deepseek/openai-benzeri sk-', re: RegExp(r'''\bsk-[a-f0-9]{32}\b''')),
  (id: '*nvidia nvapi-', re: RegExp(r'\bnvapi-[A-Za-z0-9_-]{30,}')),
  (id: '*bearer-literal', re: RegExp(r'Bearer\s+[A-Za-z0-9._~+/-]{24,}=*')),
  (
    id: 'generic-api-key (sade)',
    re: RegExp(
      r'''(?:api[_-]?key|apikey|secret|passwd|password|access[_-]?token|auth[_-]?token|client[_-]?token)\w*["']?\s*[:=]\s*["']([A-Za-z0-9_\-+/=.]{20,})["']''',
      caseSensitive: false,
    ),
  ),
];

/// Two known false positives for gitleaks (NOT secrets): the Edge TTS PUBLIC client
/// constant (edge-tts, the same in all open-source clients) and a cache key constant.
final List<RegExp> _sirIzinListesi = <RegExp>[
  RegExp(r'_trustedClientToken\s*=\s*.6A5AA1D4EAFF4E9FB37E23D68491D6F4'),
  RegExp('a_abc_p5_v1_tr-TR-AhmetNeural_x2b0x25'),
];

List<String> _sirBulgulari(String yol, String metin) {
  final out = <String>[];
  for (final k in _sirKurallari) {
    for (final m in k.re.allMatches(metin)) {
      final satirBas = metin.lastIndexOf('\n', m.start) + 1;
      var satirSon = metin.indexOf('\n', m.end);
      if (satirSon < 0) satirSon = metin.length;
      final satir = metin.substring(satirBas, satirSon);
      if (_sirIzinListesi.any((a) => a.hasMatch(satir))) continue;
      out.add('$yol [${k.id}]');
    }
  }
  return out;
}

const List<String> _metinUzantilari = <String>[
  '.dart',
  '.kt',
  '.java',
  '.xml',
  '.yaml',
  '.yml',
  '.json',
  '.gradle',
  '.kts',
  '.properties',
  '.md',
  '.sh',
  '.toml',
  '.txt',
  '.cmake',
  '.cc',
  '.h',
  '.py',
  '.ps1',
  '.env',
  '.plist',
];

/// Text files to scan under the repo root (excluding build/.dart_tool/.git/coverage and
/// large / binary files).
List<File> _taranacak() {
  const haric = <String>[
    '/build/',
    '/.dart_tool/',
    '/.git/',
    '/coverage/',
    '/.pub-cache/',
  ];
  return Directory('.')
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((f) {
        final p = '/${f.path.replaceAll(r'\', '/')}/';
        if (haric.any(p.contains)) return false;
        if (!_metinUzantilari.any(f.path.endsWith)) return false;
        return f.lengthSync() < 1500000;
      })
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

void main() {
  // ---- Scanner self-test (red-probe; test-writing principles §7) ---------
  // A scanner cannot stay green by "finding nothing": here it is proven that it catches a
  // known BAD input and does not catch a known GOOD input. Fake keys are concatenated at
  // runtime (so this file does not trigger gitleaks itself).
  group('scanner red-probe (synthetic)', () {
    test('plain-prefs scanner: finds the bad, skips the good', () {
      final kotu = _duzPrefsSirlari(
        "prefs.setString('fooApiKey', v); _p.setString('x_token', t);\n"
        "// _p.setString('commentKey', 1)",
      );
      expect(kotu, {'fooApiKey', 'x_token'});
      expect(
        _duzPrefsSirlari(
          "p.setString('theme', 'dark'); p.setString('books_v1', s);",
        ),
        isEmpty,
      );
      // Variable-named (dynamic) key: its name cannot be known statically -> skipped.
      expect(_duzPrefsSirlari(r"p.setString('chapters_$hash', s)"), isEmpty);
    });

    test('log scanner: finds sensitive arguments, skips harmless ones', () {
      const kodlu = r'''
void f() {
  debugPrint('key: $apiKey');
  print(
    'Authorization: Bearer $x',
  );
  debugPrint('page ${page + 1} ready (${(a).b})');
  final y = math.log(2);
}
''';
      final args = _logCagriArgumanlari(kodlu);
      expect(
        args,
        hasLength(3),
        reason: 'math.log() is not a log call; 3 calls must be found',
      );
      final hassas = args.where(_hassasAd.hasMatch).toList();
      expect(hassas, hasLength(2));
      expect(hassas.any((a) => a.contains('Authorization')), isTrue);
      expect(hassas.any((a) => a.contains(r'$apiKey')), isTrue);
    });

    test('secret scanner: every rule catches its synthetic positive', () {
      final ornekler = <String, String>{
        'aws-access-token':
            'AKIA'
            'IOSFODNN7EXAMPL2',
        'gcp-api-key':
            "k = 'AIza"
            'SyA-1234567890abcdefghijklmnopqrstu'
            "';",
        'github-pat':
            'ghp_'
            'a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6q7R8',
        'slack-bot-token':
            'xoxb-'
            '1234567890-1234567890-abcDEF',
        'private-key':
            '-----BEGIN '
            'RSA PRIVATE KEY-----',
        '*deepseek/openai-benzeri sk-':
            'sk-'
            '0123456789abcdef0123456789abcdef',
        '*nvidia nvapi-':
            'nvapi-'
            'abcdefghijklmnopqrstuvwxyz0123456789',
        '*bearer-literal':
            'Bearer '
            'abcdefghijklmnopqrstuvwxyz012345',
        'generic-api-key (sade)':
            "final apiKey = '"
            'abcdefghijklmnopqrstuv'
            "';",
      };
      for (final e in ornekler.entries) {
        final bulgu = _sirBulgulari('sentetik.dart', e.value);
        expect(
          bulgu.any((b) => b.contains('[${e.key}]')),
          isTrue,
          reason: '${e.key} rule must catch the synthetic positive: $bulgu',
        );
      }
      // Negatives: short / placeholder values, and Bearer + a variable secret are not secrets.
      expect(
        _sirBulgulari('n.dart', "const k = 'test-key'; // apiKey = ''"),
        isEmpty,
      );
      expect(
        _sirBulgulari('n.dart', r"'Authorization': 'Bearer ${route.apiKey}'"),
        isEmpty,
      );
      // Allow list: the Edge TTS public constant is now EXEMPT from the scanner, no other hex.
      expect(
        _sirBulgulari(
          'e.dart',
          "const String _trustedClientToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';", // gitleaks:allow
        ),
        isEmpty,
      );
      expect(
        _sirBulgulari(
          'e.dart',
          "const String _trustedClientToken = '${'0' * 32}';",
        ),
        isNotEmpty,
        reason:
            'the allow list exempts only the known constant, not the name "token"',
      );
    });

    test('manifest parser: application attributes are read', () {
      final a = _applicationOznitelikleri(
        '<manifest><application android:label="x" android:allowBackup="false" '
        'android:name="n"><activity/></application></manifest>',
      );
      expect(a['android:allowBackup'], 'false');
      expect(a['android:label'], 'x');
    });
  });

  // ---- MASVS-STORAGE-1 -------------------------------------------------------
  group('MASVS-STORAGE-1 (MASTG-TEST-0287, MASTG-TEST-0001)', () {
    test('API keys are not written to SharedPreferences as plain text '
        '(known-violation ratchet)', () {
      final lib = _dosyalar('lib', ['.dart']);
      expect(
        lib,
        isNotEmpty,
        reason:
            'lib/ could not be scanned (do not let an empty set pass green)',
      );
      final bulunan = <String>{
        for (final f in lib)
          for (final ad in _duzPrefsSirlari(f.readAsStringSync()))
            'depolama-duz-prefs:$ad',
      };
      _beklenenBulgular('depolama-duz-prefs', bulunan);
    });

    test('secure storage package is NOT in pubspec (precondition of the finding; if the '
        'package is added, the entries above must be reviewed)', () {
      final pub = _oku('pubspec.yaml');
      final varMi = RegExp(
        r'^\s*flutter_secure_storage\s*:',
        multiLine: true,
      ).hasMatch(pub);
      // While the findings are open, the package being absent is CONSISTENT; if the package
      // was added but plain prefs writes remain, the test above is already red (half-done migration).
      expect(
        varMi,
        _bilinen('depolama-duz-prefs').isEmpty,
        reason:
            'inconsistency: flutter_secure_storage is ${varMi ? "PRESENT" : "ABSENT"} but '
            'the plain-prefs known findings count is ${_bilinen("depolama-duz-prefs").length}',
      );
    });

    test(
      'the API key input field is obscured (obscureText) -- MASTG-TEST-0258/0006',
      () {
        final src = _oku('lib/ui/screens/settings_screen.dart');
        final bas = src.indexOf('void _showApiKeyDialog');
        expect(bas, greaterThan(0), reason: '_showApiKeyDialog not found');
        final govde = src.substring(bas, (bas + 1600).clamp(0, src.length));
        expect(RegExp(r'TextField\(').hasMatch(govde), isTrue);
        expect(
          govde.contains('obscureText: true'),
          isTrue,
          reason:
              'the API key field must not show plain text on screen or in the keyboard cache',
        );
      },
    );
  });

  // ---- MASVS-STORAGE-2: backup --------------------------------------------
  group('MASVS-STORAGE-2 backup (MASTG-TEST-0262/0216/0009)', () {
    test('android:allowBackup="false" or backup-exclusion rules are defined '
        '(known-violation ratchet)', () {
      final a = _applicationOznitelikleri(_oku(_manifestler.first));
      expect(
        a,
        isNotEmpty,
        reason: 'the main manifest must contain <application>',
      );
      final yedekKapali = a['android:allowBackup'] == 'false';
      final kuralli =
          a.containsKey('android:dataExtractionRules') &&
          a.containsKey('android:fullBackupContent');
      final bulunan = <String>{
        if (!yedekKapali && !kuralli) 'backup:allowBackup-not-false',
      };
      _beklenenBulgular('backup', bulunan);
    });
  });

  // ---- MASVS-NETWORK-1 --------------------------------------------------------
  group('MASVS-NETWORK-1 (MASTG-TEST-0233/0235/0237/0286)', () {
    test('no manifest has usesCleartextTraffic=true', () {
      for (final yol in _manifestler) {
        final a = _applicationOznitelikleri(_oku(yol));
        expect(a['android:usesCleartextTraffic'], isNot('true'), reason: yol);
      }
    });

    test(
      'network security config (if present) grants no cleartext / user-CA trust',
      () {
        final xmlYolu = _dosyalar('android/app/src', ['.xml'])
            .where((f) => f.path.replaceAll(r'\', '/').contains('/res/xml/'))
            .toList();
        for (final f in xmlYolu) {
          final s = f.readAsStringSync();
          expect(
            s.contains('cleartextTrafficPermitted="true"'),
            isFalse,
            reason: f.path,
          );
          expect(
            RegExp(r'<certificates\s+src="user"').hasMatch(s),
            isFalse,
            reason: '${f.path}: user-CA trust (MASTG-TEST-0286)',
          );
        }
      },
    );

    test(
      'no http:// or ws:// network endpoint literal in code (XML namespace excluded)',
      () {
        // An XML/SSML namespace is an IDENTIFIER, not a network request (no request is made):
        // lib/src/tts_messages.dart SSML <speak xmlns='http://www.w3.org/2001/10/synthesis'>.
        final izinli = RegExp(r'http://www\.w3\.org/\d{4}/\d{2}/synthesis');
        final ihlal = <String>[];
        var tarananSatir = 0;
        for (final f in _dosyalar('lib', ['.dart'])) {
          final satirlar = f.readAsLinesSync();
          for (var i = 0; i < satirlar.length; i++) {
            tarananSatir++;
            final s = satirlar[i];
            if (s.trimLeft().startsWith('//')) continue;
            final temiz = s.replaceAll(izinli, '');
            if (RegExp('''["'](?:http|ws)://''').hasMatch(temiz) ||
                temiz.contains('Uri.http(')) {
              ihlal.add('${f.path}:${i + 1}');
            }
          }
        }
        expect(
          tarananSatir,
          greaterThan(1000),
          reason: 'the scan must really read the lib/ content',
        );
        expect(ihlal, isEmpty, reason: 'unencrypted network endpoint: $ihlal');
      },
    );

    test(
      'https:// / wss:// endpoints EXIST in code (an empty set is not green) and TLS '
      'verification is not disabled',
      () {
        var guvenli = 0;
        final tlsKapali = <String>[];
        for (final f in _dosyalar('lib', ['.dart'])) {
          final s = _yorumsuz(f.readAsStringSync());
          guvenli += RegExp('''["'](?:https|wss)://''').allMatches(s).length;
          if (s.contains('badCertificateCallback')) tlsKapali.add(f.path);
        }
        expect(
          guvenli,
          greaterThanOrEqualTo(5),
          reason: 'the LLM/TTS endpoints must be found',
        );
        expect(
          tlsKapali,
          isEmpty,
          reason: 'badCertificateCallback = TLS verification bypass',
        );
      },
    );
  });

  // ---- Embedded secrets -----------------------------------------------------------
  group(
    'MASVS-STORAGE/CRYPTO embedded secret (MASTG-TEST-0212; gitleaks rules)',
    () {
      test('repo text files contain no secret pattern', () {
        final dosyalar = _taranacak();
        expect(
          dosyalar.length,
          greaterThan(100),
          reason: 'scan coverage (do not let an empty set pass green)',
        );
        expect(
          dosyalar.any(
            (f) =>
                f.path.replaceAll(r'\', '/').endsWith('lib/io/edge_tts.dart'),
          ),
          isTrue,
          reason: 'the file of the allow-listed constant must be in the scan',
        );
        final bulgu = <String>[];
        for (final f in dosyalar) {
          // This file's own code contains the rule PATTERNS (not secrets); it is still scanned --
          // the patterns do not match the secret format, and if one does, it turns red.
          bulgu.addAll(_sirBulgulari(f.path, f.readAsStringSync()));
        }
        expect(bulgu, isEmpty, reason: 'possible embedded secret: $bulgu');
      });
    },
  );

  // ---- Logging -----------------------------------------------------------------
  group('MASVS-STORAGE-2 logging (MASTG-TEST-0231, MASTG-BEST-0002)', () {
    test(
      'no key / Authorization in the argument of print/debugPrint/developer.log',
      () {
        final ihlal = <String>[];
        var cagri = 0;
        for (final f in _dosyalar('lib', ['.dart'])) {
          for (final arg in _logCagriArgumanlari(f.readAsStringSync())) {
            cagri++;
            if (_hassasAd.hasMatch(arg)) ihlal.add('${f.path}: $arg');
          }
        }
        expect(
          cagri,
          greaterThanOrEqualTo(1),
          reason: 'the scanner must be able to see log calls inside lib/',
        );
        expect(
          ihlal,
          isEmpty,
          reason: 'sensitive data is written to the log: $ihlal',
        );
      },
    );

    test('key variables are not embedded in messages via string interpolation '
        '(exception: Authorization header)', () {
      final enterpolasyon = RegExp(
        r'''\$\{?[\w.]*(?:apiKey|geminiKey|googleKey|deepseekApiKey|nvidiaApiKey|azureKey|subscriptionKey)\b''',
      );
      // llm_client.dart: 'Authorization': 'Bearer ${route.apiKey}' -- an HTTP HEADER (not a
      // body / URL / log); headers are not logged (test above).
      final izin = RegExp(r"'Authorization':\s*'Bearer \$\{route\.apiKey\}'");
      final ihlal = <String>[];
      for (final f in _dosyalar('lib', ['.dart'])) {
        final satirlar = _yorumsuz(f.readAsStringSync()).split('\n');
        for (var i = 0; i < satirlar.length; i++) {
          if (enterpolasyon.hasMatch(satirlar[i]) &&
              !izin.hasMatch(satirlar[i])) {
            ihlal.add('${f.path}:${i + 1}: ${satirlar[i].trim()}');
          }
        }
      }
      expect(
        ihlal,
        isEmpty,
        reason: 'the key is embedded in text (error / log / URL risk): $ihlal',
      );
    });

    test('the API key is not carried in a URL query (key= / api_key=)', () {
      final ihlal = <String>[];
      for (final f in _dosyalar('lib', ['.dart'])) {
        final s = _yorumsuz(f.readAsStringSync());
        if (RegExp(
          '''[?&](?:key|api_key|apikey|access_token)=''',
          caseSensitive: false,
        ).hasMatch(s)) {
          ihlal.add(f.path);
        }
      }
      expect(
        ihlal,
        isEmpty,
        reason:
            'ClientException includes the URI in its message -> the key leaks',
      );
    });
  });

  // ---- Debug / WebView / signing / permissions -------------------------------------------
  group('MASVS-RESILIENCE/PLATFORM flags (MASTG-TEST-0226/0227/0031/0038/0024)', () {
    test(
      'android:debuggable="true" is in no manifest and not in the gradle release build type',
      () {
        for (final yol in _manifestler) {
          expect(
            _applicationOznitelikleri(_oku(yol))['android:debuggable'],
            isNot('true'),
            reason: yol,
          );
        }
        final gradle = _oku('android/app/build.gradle.kts');
        expect(
          RegExp(r'isDebuggable\s*=\s*true|debuggable\s+true').hasMatch(gradle),
          isFalse,
          reason: 'the release buildType must not be debuggable',
        );
      },
    );

    test('no WebView: dependency, Kotlin/Java and debug flag', () {
      final pub = _oku('pubspec.yaml') + _oku('pubspec.lock');
      for (final paket in [
        'webview_flutter',
        'flutter_inappwebview',
        'webview_windows',
        'webview_win_floating',
      ]) {
        expect(
          pub.contains(paket),
          isFalse,
          reason: '$paket: WebView surface (MASTG-TEST-0031/0227)',
        );
      }
      final yerel = _dosyalar('android/app/src', ['.kt', '.java']);
      for (final f in yerel) {
        final s = f.readAsStringSync();
        expect(s.contains('WebView'), isFalse, reason: f.path);
        expect(
          s.contains('setWebContentsDebuggingEnabled'),
          isFalse,
          reason: f.path,
        );
      }
    });

    test(
      'release code shrinking/obfuscation is enabled (isMinifyEnabled) -- MASTG-TEST-0051 regression',
      () {
        expect(
          RegExp(
            r'isMinifyEnabled\s*=\s*true',
          ).hasMatch(_oku('android/app/build.gradle.kts')),
          isTrue,
        );
      },
    );

    test(
      'release is not signed with the debug key (known-violation ratchet)',
      () {
        final gradle = _oku('android/app/build.gradle.kts');
        final rel = RegExp(
          r'release\s*\{([\s\S]*?)\n        \}',
        ).firstMatch(gradle);
        expect(rel, isNotNull, reason: 'buildTypes.release block not found');
        final bulunan = <String>{
          if (RegExp(
            r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
          ).hasMatch(rel!.group(1)!))
            'imza:release-debug-anahtariyla-imzali',
        };
        _beklenenBulgular('imza', bulunan);
      },
    );

    test(
      'the main manifest requests only permissions on the allow list (MASTG-TEST-0024/0254)',
      () {
        // INTERNET: LLM/TTS network access. A new permission (RECORD_AUDIO,
        // *_EXTERNAL_STORAGE, CAMERA, ...) needs a deliberate decision -> red until it is
        // added to the list.
        const izinli = {
          'android.permission.INTERNET',
          'android.permission.ACCESS_NETWORK_STATE',
        };
        final istenen = {
          for (final m in RegExp(
            r'<uses-permission\s+android:name="([^"]+)"',
          ).allMatches(_oku(_manifestler.first)))
            m.group(1)!,
        };
        expect(
          istenen.difference(izinli),
          isEmpty,
          reason: 'a permission not on the allow list was requested',
        );
      },
    );

    test('the only exported component is the MAIN/LAUNCHER activity', () {
      final s = _oku(_manifestler.first);
      final acik = RegExp(
        r'<(activity|service|receiver|provider)\b[^>]*android:exported="true"[^>]*>([\s\S]*?)</\1>',
      ).allMatches(s).toList();
      expect(
        acik,
        isNotEmpty,
        reason:
            'MainActivity must be exported=true (do not let an empty set pass green)',
      );
      for (final m in acik) {
        expect(
          m.group(1),
          'activity',
          reason: 'an exported service/receiver/provider is not expected',
        );
        expect(m.group(2)!.contains('android.intent.action.MAIN'), isTrue);
        expect(
          m.group(2)!.contains('android.intent.category.LAUNCHER'),
          isTrue,
        );
      }
    });
  });
}
