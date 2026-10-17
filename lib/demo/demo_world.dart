// DEMO "world": hermetic prefs (in memory) + temporary data dir + fake server +
// fake audio. lib/main_demo.dart sets this up; tests use the same path.
//
// REAL: SesliKitapApp/AppShell/all screens, AppServices, PagePipeline,
// CacheStore, PDF text extraction (syncfusion), the LlmXxx/GoogleTts/GeminiTts
// classes and the real http.Client path, persistence logic.
// FAKE: (1) network endpoint (DemoApiServer, loopback; answers are pre-written),
// (2) audio output (DemoAudioOps, silent), (3) file picker (supplies the book
// as bytes), (4) shared_preferences (in-memory store: NOTHING is written to
// disk, and any entered key is not persisted).
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sesli_kitap/demo/demo_api_server.dart';
import 'package:sesli_kitap/demo/demo_audio_ops.dart';
import 'package:sesli_kitap/demo/demo_llm_router.dart';
import 'package:sesli_kitap/demo/demo_wav.dart';
import 'package:sesli_kitap/src/chapter_cache.dart';
import 'package:sesli_kitap/src/chapter_map.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/src/llm_access.dart';
import 'package:sesli_kitap/src/onboarding/onboarding_prefs.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Asset path (pubspec: assets/demo/).
const String kDemoPdfAsset = 'assets/demo/uc_hikaye.pdf';

/// FAKE key value: NOT in a real provider's format. It exists only so that
/// `LlmAccess.isConfigured` is true; it is never actually sent anywhere
/// (requests go to the loopback fake server).
const String kDemoApiKey = 'demo-anahtar-yok';

/// Library title of the demo book.
const String kDemoBookTitle = 'Üç Hikâye (DEMO)';

/// 1-based page ranges of the demo book (PDF: 21 pages).
const List<({String title, int start, int end})> kDemoChapters = [
  (title: 'Kaşağı', start: 1, end: 7),
  (title: 'Forsa', start: 8, end: 14),
  (title: 'Primo Türk Çocuğu', start: 15, end: 21),
];

/// SAME formula as add_book_screen: first 16 hex chars of sha256(bytes).
String demoBookHash(Uint8List pdfBytes) =>
    sha256.convert(pdfBytes).toString().substring(0, 16);

/// First-launch prefs: onboarding done, one book, 3 chapters, fake keys,
/// reader TTS set to `google` (never goes to the Edge WebSocket).
Map<String, Object> buildDemoSeed({
  required Uint8List pdfBytes,
  required String filePath,
}) {
  final hash = demoBookHash(pdfBytes);
  final book = Book(
    id: hash,
    title: kDemoBookTitle,
    author: 'Ömer Seyfettin',
    chapterLabel: kDemoChapters.first.title,
    progressPercent: 0,
    totalPages: 21,
    coverIndex: 0,
    hash: hash,
    filePath: filePath,
  );
  return <String, Object>{
    'onboarding': encodeOnboarding(
      const OnboardingPrefs(onboarded: true, choice: VoiceChoice.ahmet),
    ),
    'books_v1': encodeBooks([book]),
    'chapters_$hash': encodeChapters([
      for (final c in kDemoChapters)
        Chapter(title: c.title, startPage: c.start, endPage: c.end),
    ]),
    'geminiKey': kDemoApiKey,
    'llmProvider': LlmChoice.gemini,
    'provider': 'google',
    'googleKey': kDemoApiKey,
  };
}

class DemoWorld {
  DemoWorld._(
    this.server,
    this.dataDir,
    this.pdfBytes,
    this.pdfFile,
    this.router,
    this._previousOverrides,
  );

  final DemoApiServer server;
  final DemoLlmRouter router;
  final Directory dataDir;
  final Uint8List pdfBytes;
  final File pdfFile;
  final HttpOverrides? _previousOverrides;

  /// Silent players created by [buildServices] (for tests / verification).
  final List<DemoAudioOps> ops = <DemoAudioOps>[];

  /// Opens the fake server, redirects all HTTP to it, and writes the demo PDF
  /// into the data dir. [charsPerSecond]: fake speech rate ([kDemoCharsPerSecond]).
  static Future<DemoWorld> start({
    required Uint8List pdfBytes,
    double charsPerSecond = kDemoCharsPerSecond,
  }) async {
    final router = DemoLlmRouter();
    final server = await DemoApiServer.start(
      chatResponder: router.respond,
      charsPerSecond: charsPerSecond,
    );
    final previous = HttpOverrides.current;
    HttpOverrides.global = DemoHttpOverrides(server.port);
    final root = Directory.systemTemp.createTempSync('sesli_kitap_demo_');
    final dataDir = Directory('${root.path}/app_data')..createSync();
    final booksDir = Directory('${dataDir.path}/books')..createSync();
    final pdf = File('${booksDir.path}/${demoBookHash(pdfBytes)}.pdf')
      ..writeAsBytesSync(pdfBytes);
    return DemoWorld._(server, dataDir, pdfBytes, pdf, router, previous);
  }

  /// The counterpart of main()'s production setup (prefs -> AppServices..reading.load());
  /// only the seams are injected: silent audio ops + a file picker that yields bytes.
  Future<AppServices> buildServices() async {
    // In-memory store: real user settings/disk are NOT touched (same as e2e).
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(
      buildDemoSeed(pdfBytes: pdfBytes, filePath: pdfFile.path),
    );
    // Drop the previous instance: the seed is always read fresh.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.resetStatic();
    final prefs = await SharedPreferences.getInstance();
    return AppServices(
      prefs: prefs,
      dataDir: dataDir,
      playerOpsFactory: () {
        final o = DemoAudioOps();
        ops.add(o);
        return o;
      },
      pickPdf: () async => PickedBook(name: kDemoBookTitle, bytes: pdfBytes),
    )..reading.load();
  }

  Future<void> dispose() async {
    HttpOverrides.global = _previousOverrides;
    await server.close();
    try {
      dataDir.parent.deleteSync(recursive: true);
    } on FileSystemException {
      // temp dir cleanup is best-effort
    }
  }
}
