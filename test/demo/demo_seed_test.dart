// Demo seed (prefs + file) and DemoWorld lifecycle. Also pins that the NORMAL path
// without a key is unchanged: it does NOT fall back to the automatic mock.
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/demo/demo_api_server.dart';
import 'package:sesli_kitap/demo/demo_world.dart';
import 'package:sesli_kitap/main.dart' show resolveInitialOnboarded;
import 'package:sesli_kitap/src/chapter_cache.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/src/llm_access.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_app.dart';

void main() {
  final pdfBytes = File('assets/demo/uc_hikaye.pdf').readAsBytesSync();
  final hash = sha256.convert(pdfBytes).toString().substring(0, 16);

  group('buildDemoSeed', () {
    final seed = buildDemoSeed(pdfBytes: pdfBytes, filePath: '/gecici/x.pdf');

    test(
      'single book: same hash formula as add_book, 21 pages, DEMO label',
      () {
        final books = decodeBooks(seed['books_v1']! as String);
        expect(books, hasLength(1));
        final b = books.single;
        expect(b.hash, hash);
        expect(b.id, hash);
        expect(b.filePath, '/gecici/x.pdf');
        expect(b.totalPages, 21);
        expect(b.title, contains('DEMO'));
        expect(b.author, 'Ömer Seyfettin');
        expect(b.language, 'tr');
      },
    );

    test('3 chapters: 1-7 Kasagi, 8-14 Forsa, 15-21 Primo', () {
      final chapters = decodeChapters(seed['chapters_$hash']! as String);
      expect(chapters.map((c) => (c.title, c.startPage, c.endPage)).toList(), [
        ('Kaşağı', 1, 7),
        ('Forsa', 8, 14),
        ('Primo Türk Çocuğu', 15, 21),
      ]);
    });

    test('fake key: LLM configured, TTS google, NO real format', () {
      expect(seed['geminiKey'], kDemoApiKey);
      expect(seed['googleKey'], kDemoApiKey);
      expect(seed['provider'], 'google');
      expect(seed['llmProvider'], LlmChoice.gemini);
      expect(kDemoApiKey, 'demo-anahtar-yok');
      final access = LlmAccess.fromSettings(
        choice: seed['llmProvider']! as String,
        geminiKey: seed['geminiKey']! as String,
      );
      expect(access.isConfigured, isTrue);
    });

    test(
      'onboarding complete: the app opens directly into the library',
      () async {
        SharedPreferences.setMockInitialValues(seed);
        final prefs = await SharedPreferences.getInstance();
        expect(resolveInitialOnboarded(prefs), isTrue);
      },
    );
  });

  test(
    'NORMAL path unchanged: empty prefs -> no LLM, tutoring LLM is null',
    () async {
      final services = await buildTestServices();
      services.reading.load();
      expect(services.reading.llmAccess.isConfigured, isFalse);
      expect(services.tutorLlm(), isNull);
      expect(services.reading.provider, 'edge');
    },
  );

  group('DemoWorld', () {
    test(
      'starts: PDF is written to disk, network is redirected; dispose restores it',
      () async {
        final before = HttpOverrides.current;
        final world = await DemoWorld.start(pdfBytes: pdfBytes);
        expect(HttpOverrides.current, isA<DemoHttpOverrides>());
        final stored = File('${world.dataDir.path}/books/$hash.pdf');
        expect(stored.existsSync(), isTrue);
        expect(stored.readAsBytesSync(), pdfBytes);

        final services = await world.buildServices();
        expect(services.reading.llmAccess.isConfigured, isTrue);
        expect(services.reading.provider, 'google');
        expect(
          decodeBooks(services.prefs.getString('books_v1')!).single.filePath,
          stored.path,
        );
        // The "Choose file" (Choose file) action hands the demo book over as bytes
        // (the real add flow).
        final picked = await services.pickPdf();
        expect(picked!.bytes, pdfBytes);
        expect(picked.path, isNull);

        final dir = world.dataDir.parent;
        await world.dispose();
        expect(HttpOverrides.current, before);
        expect(
          dir.existsSync(),
          isFalse,
          reason: 'the temp directory is cleaned up',
        );
      },
    );
  });
}
