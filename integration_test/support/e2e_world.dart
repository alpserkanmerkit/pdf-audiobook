// E2E "world": hermetic prefs + data dir + fake server + fake audio ops.
//
// REAL: SesliKitapApp/AppShell/all screens, AppServices, PagePipeline,
// CacheStore, PDF text extraction (syncfusion), LlmTutor/GoogleTts/
// postChatCompletion (real http.Client), persistence (prefs + files).
// FAKE: (1) network endpoints (DemoApiServer, loopback), (2) audio output
// (RecordingAudioOps -- no native just_audio), (3) file picker
// (AppServices.pickPdf seam), (4) shared_preferences (in-memory store;
// so the developer's real settings are NOT touched).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sesli_kitap/main.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../test/helpers/test_app.dart' show RecordingAudioOps;
import 'fake_api_server.dart';

/// First step shared by all tests: IntegrationTestWidgetsFlutterBinding.
void initE2eBinding() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
}

/// Fixture PDF: each inner list holds one page's lines (top to bottom).
Uint8List buildPdf(List<List<String>> pages) {
  final doc = PdfDocument();
  final font = PdfStandardFont(PdfFontFamily.helvetica, 12);
  for (final lines in pages) {
    final page = doc.pages.add();
    var y = 0.0;
    for (final line in lines) {
      page.graphics.drawString(
        line,
        font,
        bounds: Rect.fromLTWH(0, y, 400, 16),
      );
      y += 24;
    }
  }
  final bytes = Uint8List.fromList(doc.saveSync());
  doc.dispose();
  return bytes;
}

/// The book's first sentences (tests search for these in the server request body).
const String kPage1Marker = 'Residual earnings measure value creation.';
const String kPage2Marker =
    'Growth in residual earnings drives continuing value.';

/// 4 pages; the first line of pages 2 and 4 is the same running header -> the app's
/// real header detection yields one chapter (1-4) -> tutor lesson with 3+ filled pages.
const String kRunningHeader = 'Pricing Book Values';

Uint8List e2eBookPdf() => buildPdf([
  [
    kRunningHeader,
    kPage1Marker,
    'Book value is the starting point of valuation.',
    'Analysts forecast future earnings carefully.',
  ],
  [
    kRunningHeader,
    kPage2Marker,
    'Discount rates reflect the required return on equity.',
    'Persistence of abnormal profit matters greatly.',
  ],
  [
    kRunningHeader,
    'Accounting conservatism understates reported book value.',
    'Unrecorded intangibles create a gap against market price.',
    'Investors adjust the numbers before valuing the firm.',
  ],
  [
    kRunningHeader,
    'Terminal value dominates the sum of discounted flows.',
    'Sensitivity tests expose fragile assumptions quickly.',
    'A margin of safety protects against forecast error.',
  ],
]);

class E2eWorld {
  E2eWorld._(this.server, this.dataDir, this.pdfFile, this._previousOverrides);

  final DemoApiServer server;
  final Directory dataDir;
  final File pdfFile;
  final HttpOverrides? _previousOverrides;

  /// Fake audio ops created by each `launch`/`restart` (in order).
  final List<RecordingAudioOps> ops = <RecordingAudioOps>[];

  late AppServices services;
  int _generation = 0;

  /// [prefs]: persistent settings before the first launch (e.g. fake API keys).
  static Future<E2eWorld> create({
    Map<String, Object> prefs = const <String, Object>{},
  }) async {
    final server = await startE2eServer();
    final previous = HttpOverrides.current;
    HttpOverrides.global = DemoHttpOverrides(server.port);
    final dir = Directory.systemTemp.createTempSync('sesli_kitap_e2e_');
    final pdf = File('${dir.path}/fixture_kitap.pdf')
      ..writeAsBytesSync(e2eBookPdf());
    // Books are copied under dataDir/books; the fixture is in a separate subdirectory.
    final dataDir = Directory('${dir.path}/app_data')..createSync();
    SharedPreferences.setMockInitialValues(prefs);
    return E2eWorld._(server, dataDir, pdf, previous);
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

  /// IDENTICAL to main()'s production setup (prefs -> AppServices..reading.load()
  /// -> resolveInitialOnboarded); only the seams are injected: audio ops + pickPdf.
  Future<void> _buildServices() async {
    // Cold start: drop the previous SharedPreferences instance, re-read from the same (in-memory)
    // store -> only what is PERSISTENT comes back.
    SharedPreferences.resetStatic();
    final prefs = await SharedPreferences.getInstance();
    services = AppServices(
      prefs: prefs,
      dataDir: dataDir,
      playerOpsFactory: () {
        final o = RecordingAudioOps();
        ops.add(o);
        return o;
      },
      pickPdf: () async =>
          PickedBook(name: 'fixture_kitap.pdf', path: pdfFile.path),
    )..reading.load();
  }

  /// (Re)opens the app. A previous tree is torn down first (dispose runs),
  /// then a new tree is built with NEW services = close-reopen.
  Future<void> launch(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await _buildServices();
    _generation++;
    await tester.pumpWidget(
      SesliKitapApp(
        key: ValueKey('e2e-app-$_generation'),
        services: services,
        initialOnboarded: resolveInitialOnboarded(services.prefs),
      ),
    );
    await tester.pumpAndSettle();
  }
}

/// Waits in real time (live binding) for the condition; if it is not met,
/// it FAILS with [reason] (no silent pass).
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      fail('Timed out (${timeout.inSeconds}s): $reason');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
  String? reason,
}) => pumpUntil(
  tester,
  () => finder.evaluate().isNotEmpty,
  timeout: timeout,
  reason: reason ?? 'not found: $finder',
);

Future<void> tapFinder(WidgetTester tester, Finder finder) async {
  expect(finder, findsAtLeastNWidgets(1), reason: 'no widget to tap');
  await tester.ensureVisible(finder.first);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(finder.first);
  await tester.pump(const Duration(milliseconds: 100));
}

/// Gets past first-launch onboarding with the real "Start →" button.
Future<void> finishOnboarding(WidgetTester tester) async {
  await pumpUntilFound(tester, find.textContaining('Start →'));
  await tapFinder(tester, find.textContaining('Start →'));
  await pumpUntilFound(tester, find.text('Your library'));
}

/// Library -> Add book -> Choose file (fake picker, REAL path-based isolate
/// import) -> "Ready". If [startReading] is true, then "Start reading".
Future<void> addBookViaUi(
  WidgetTester tester, {
  bool startReading = false,
}) async {
  await tapFinder(tester, find.textContaining('Add book'));
  await pumpUntilFound(tester, find.textContaining('Choose file'));
  await tapFinder(tester, find.textContaining('Choose file'));
  await pumpUntilFound(
    tester,
    find.textContaining('Start reading'),
    reason: 'book import did not reach the "Ready" phase',
  );
  if (startReading) {
    await tapFinder(tester, find.textContaining('Start reading'));
  } else {
    await tapFinder(tester, find.byIcon(Icons.arrow_back));
  }
  await tester.pumpAndSettle();
}
