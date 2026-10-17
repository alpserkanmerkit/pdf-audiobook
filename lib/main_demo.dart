// DEMO entry point: runs WITHOUT an API key, using canned (pre-written) answers
// and silent audio. Run with `make demo` (= flutter run -t lib/main_demo.dart).
// The standard app (lib/main.dart) is UNCHANGED; to try it with a real key,
// run that one instead.
//
// All HTTP requests are routed to an in-process loopback fake server (no request
// reaches a real provider); settings are kept in memory and never written to disk.
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:sesli_kitap/demo/demo_wav.dart';
import 'package:sesli_kitap/demo/demo_world.dart';
import 'package:sesli_kitap/main.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final data = await rootBundle.load(kDemoPdfAsset);
  final cps =
      double.tryParse(Platform.environment['SESLI_DEMO_CPS'] ?? '') ??
      kDemoCharsPerSecond;
  final world = await DemoWorld.start(
    pdfBytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    charsPerSecond: cps,
  );
  final services = await world.buildServices();
  // On exit, delete the temporary data directory (demo PDF + audio cache); the fake server shuts down.
  AppLifecycleListener(
    onExitRequested: () async {
      await world.dispose();
      return AppExitResponse.exit;
    },
  );
  // Same cleanup when closed from the terminal (Ctrl+C / kill).
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) async {
      await world.dispose();
      exit(0);
    });
  }
  runApp(
    SesliKitapApp(
      services: services,
      initialOnboarded: resolveInitialOnboarded(services.prefs),
    ),
  );
}
