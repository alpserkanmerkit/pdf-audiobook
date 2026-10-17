// FLOW 7: DEMO mode end-to-end. REAL demo world (lib/demo/demo_world.dart,
// the SAME path main_demo.dart sets up): sample book in library -> Reader p.1
// text + play (silent fake audio advances in real time, highlight moves,
// at the end p.2) -> Discussion (fake LLM + fake TTS) -> Quiz (5 questions) -> Tutor lesson.
// At the end: no unrecognized request; every request went to the fake server (loopback).
//
// Screenshot: if env var DEMO_SHOT_DIR is set, a PNG is taken at each main step
// with ImageMagick `import -window root` (scripts/demo-shots.sh).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/demo/demo_content.dart';
import 'package:sesli_kitap/demo/demo_wav.dart';
import 'package:sesli_kitap/demo/demo_world.dart';
import 'package:sesli_kitap/main.dart';
import 'package:sesli_kitap/src/library/library_store.dart';

import '../support/e2e_actions.dart';
import '../support/e2e_world.dart';

/// Window size (px) for screenshots: phone aspect ratio.
const Size _shotSize = Size(430, 900);

/// true when [_resizeWindow] really resized the window (xdotool available).
bool _windowResized = false;

/// Resizes the REAL window to a phone aspect ratio for screenshots (xdotool).
/// Does nothing if DEMO_SHOT_DIR is empty or xdotool is missing (the image is then the whole screen).
/// No window manager -> the window sits in the corner (0,0).
Future<void> _resizeWindow(WidgetTester tester) async {
  if ((Platform.environment['DEMO_SHOT_DIR'] ?? '').isEmpty) return;
  await tester.runAsync(() async {
    try {
      final found = await Process.run('xdotool', [
        'search',
        '--class',
        'sesli_kitap',
      ]);
      final ids = '${found.stdout}'
          .split('\n')
          .where((l) => l.trim().isNotEmpty);
      for (final id in ids) {
        await Process.run('xdotool', [
          'windowsize',
          id,
          '${_shotSize.width.toInt()}',
          '${_shotSize.height.toInt()}',
        ]);
        await Process.run('xdotool', ['windowmove', id, '0', '0']);
        _windowResized = true;
      }
    } on ProcessException {
      _windowResized = false;
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));
  });
  await tester.pump(const Duration(milliseconds: 300));
}

/// If DEMO_SHOT_DIR is set, takes a PNG at the main steps (ImageMagick `import`).
Future<void> _shot(WidgetTester tester, String name) async {
  final dir = Platform.environment['DEMO_SHOT_DIR'];
  if (dir == null || dir.isEmpty) return;
  // Short real-time wait so the frame is fully painted.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 700)),
  );
  await tester.pump(const Duration(milliseconds: 100));
  Directory(dir).createSync(recursive: true);
  final r = await tester.runAsync(
    () => Process.run('import', [
      '-window',
      'root',
      if (_windowResized) ...[
        '-crop',
        '${_shotSize.width.toInt()}x${_shotSize.height.toInt()}+0+0',
        '+repage',
      ],
      '$dir/$name.png',
    ]),
  );
  if (r == null || r.exitCode != 0) {
    fail('screenshot could not be taken ($name): ${r?.stderr}');
  }
}

/// Slow disk simulation: only the async read of [slowPath] is delayed by [delay]
/// (the `File(...).readAsBytes()` in AppShell._buildPipelineAsync);
/// every other file is REAL. Makes a late pipeline setup deterministic on a slow phone/CI.
class _SlowDiskOverrides extends IOOverrides {
  _SlowDiskOverrides(this.delay);

  final Duration delay;
  String? slowPath;

  @override
  File createFile(String path) {
    final real = super.createFile(path);
    return path == slowPath ? _SlowFile(real, delay) : real;
  }
}

class _SlowFile implements File {
  _SlowFile(this._inner, this._delay);

  final File _inner;
  final Duration _delay;

  @override
  String get path => _inner.path;

  @override
  bool existsSync() => _inner.existsSync();

  @override
  Future<Uint8List> readAsBytes() async {
    await Future<void>.delayed(_delay);
    return _inner.readAsBytes();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_SlowFile: ${invocation.memberName}');
}

Finder _inTab(String tab, Finder matching) =>
    find.descendant(of: find.byKey(Key('tab-$tab')), matching: matching);

void demoFlow() {
  testWidgets('flow 7: demo -- library, reader+play, discussion, quiz, tutor '
      'lesson runs on fake answers; no request leaves loopback', (
    tester,
  ) async {
    await _resizeWindow(tester);
    final data = await rootBundle.load(kDemoPdfAsset);
    final world = await tester.runAsync(
      () => DemoWorld.start(
        pdfBytes: data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        ),
        // Fast demo speech: ~7 s per page (does not lengthen the test; a window that is enough for the screenshot).
        charsPerSecond: 200,
      ),
    );
    addTearDown(world!.dispose);
    final services = await tester.runAsync(world.buildServices);
    await tester.pumpWidget(
      SesliKitapApp(
        key: const ValueKey('demo-app'),
        services: services!,
        initialOnboarded: resolveInitialOnboarded(services.prefs),
      ),
    );
    await tester.pumpAndSettle();

    // 1) Library: sample book.
    await pumpUntilFound(tester, find.text('Your library'));
    expect(find.text(kDemoBookTitle), findsWidgets);
    expect(find.text('Ömer Seyfettin'), findsWidgets);
    await _shot(tester, 'kutuphane');

    // 2) Reader: open the book, p.1 text, play.
    final book = decodeBooks(services.prefs.getString('books_v1')!).single;
    await openBookFromLibrary(tester, book);
    expect(find.text('Page 1 / 21'), findsOneWidget);
    await tapPlay(tester);
    await pumpUntil(
      tester,
      () => world.ops.isNotEmpty && world.ops.first.playCalls >= 1,
      reason: 'fake player got no play() (preparation/TTS path blocked?)',
    );
    final ops = world.ops.first;
    expect(ops.loadedPaths, isNotEmpty);
    final audio = File(ops.loadedPaths.first);
    expect(audio.existsSync(), isTrue);
    final spoken = wavDuration(audio.readAsBytesSync());
    expect(spoken, isNotNull, reason: 'fake TTS must return a VALID WAV');
    expect(spoken!.inSeconds, greaterThanOrEqualTo(2));
    await pumpUntilFound(
      tester,
      find.textContaining('Ahırın avlusunda'),
      timeout: const Duration(seconds: 10),
      reason: 'p.1 text did not appear in the reader',
    );
    expect(find.byIcon(Icons.pause), findsOneWidget);
    // Progress: the position increases in real time.
    final p1 = ops.currentPosition!;
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 900)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      ops.currentPosition,
      greaterThan(p1),
      reason: 'position must advance',
    );
    await _shot(tester, 'okuyucu');
    // When the page ends naturally, p.2 is prepared and played.
    await pumpUntilFound(
      tester,
      find.text('Page 2 / 21'),
      timeout: const Duration(seconds: 40),
      reason: 'p.2 did not arrive after p.1 ended',
    );
    // Once p.2 text is visible, audio may still be preparing (spinner,
    // no pause icon): wait until playback starts, then pause.
    await pumpUntilFound(
      tester,
      find.byIcon(Icons.pause),
      reason: 'p.2 audio did not start playing',
    );
    await tapPause(tester);
    await tester.pump(const Duration(milliseconds: 300));

    // 3) Discussion: fake LLM scenario + fake TTS.
    await tapFinder(tester, find.text('Discussion'));
    await tapFinder(
      tester,
      _inTab('discussion', find.byIcon(Icons.play_arrow)),
    );
    await pumpUntilFound(tester, find.byType(AlertDialog));
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Why did the child lie in the Kaşağı story?',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tapFinder(tester, find.text('Start'));
    await pumpUntilFound(
      tester,
      _inTab('discussion', find.textContaining('Dadaruh')),
      timeout: const Duration(seconds: 40),
      reason: 'the first fake discussion line did not appear',
    );
    expect(
      world.server.geminiTtsRequests,
      isNotEmpty,
      reason: 'discussion audio must reach the fake Gemini TTS endpoint',
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1500)),
    );
    await _shot(tester, 'tartisma');
    await tapFinder(
      tester,
      _inTab('discussion', find.byKey(const Key('discussion-stop-control'))),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 4) Quiz: fake 4-choice questions.
    await tapFinder(tester, find.text('Quiz'));
    await tapFinder(tester, find.byKey(const Key('quiz-generate')));
    await pumpUntilFound(
      tester,
      find.textContaining('Hasan'),
      timeout: const Duration(seconds: 20),
      reason: 'quiz questions did not arrive',
    );
    expect(find.textContaining(kDemoQuiz.first.$1), findsWidgets);

    // 5) Tutor lesson: Kasagi chapter, fake teacher explanation.
    await tapFinder(tester, find.text('Library'));
    expect(await openTutorChapter(tester, book), 'part');
    final explanation =
        (tester.widget(find.byKey(const Key('tutor-explanation'))) as Text)
            .data;
    expect(explanation, kDemoLessons['Kaşağı']!.first.$1);
    await _shot(tester, 'ozel_ders');

    // 6) Network discipline: all requests go to the fake server; NO unrecognized ones.
    expect(world.server.unrouted, isEmpty, reason: '${world.server.unrouted}');
    expect(world.router.unrouted, isEmpty);
    expect(world.server.requests, isNotEmpty);
    for (final r in world.server.requests) {
      expect(
        r.originalHost,
        isNotNull,
        reason: 'direct (not redirected) request: $r',
      );
    }
    expect(
      world.server.requests.map((r) => r.originalHost).toSet(),
      everyElement(
        isIn(<String>{
          'generativelanguage.googleapis.com',
          'texttospeech.googleapis.com',
        }),
      ),
      reason: 'no request may go to edge/other providers',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });
  testWidgets('flow 7b: Play before pipeline (slow disk) is NOT DROPPED '
      '-- feedback + queue; play() still arrives when ready', (tester) async {
    final slow = _SlowDiskOverrides(const Duration(seconds: 3));
    await IOOverrides.runWithIOOverrides(() async {
      final data = await rootBundle.load(kDemoPdfAsset);
      final world = await tester.runAsync(
        () => DemoWorld.start(
          pdfBytes: data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          ),
          charsPerSecond: 200,
        ),
      );
      addTearDown(world!.dispose);
      final services = await tester.runAsync(world.buildServices);
      await tester.pumpWidget(
        SesliKitapApp(
          key: const ValueKey('demo-app-slow'),
          services: services!,
          initialOnboarded: resolveInitialOnboarded(services.prefs),
        ),
      );
      await tester.pumpAndSettle();
      await pumpUntilFound(tester, find.text('Your library'));

      final book = decodeBooks(services.prefs.getString('books_v1')!).single;
      slow.slowPath = book.filePath;
      await openBookFromLibrary(tester, book, waitForPipeline: false);

      // Pipeline NOT ready yet (disk delayed 3 s): the press must be queued.
      await tapPlay(tester);
      expect(
        find.byIcon(Icons.hourglass_top),
        findsOneWidget,
        reason:
            'press was not queued (if the pipeline was set up early the test '
            'should increase the delay)',
      );
      expect(find.textContaining('Book is being prepared'), findsOneWidget);
      expect(world.ops.isEmpty || world.ops.first.playCalls == 0, isTrue);

      // Once the pipeline is set up, the queued request runs: the fake player receives play().
      await pumpUntil(
        tester,
        () => world.ops.isNotEmpty && world.ops.first.playCalls >= 1,
        timeout: const Duration(seconds: 40),
        reason: 'queued Play was not executed (play() did not arrive)',
      );
      await pumpUntilFound(
        tester,
        find.byIcon(Icons.pause),
        reason: 'phase must be playing once the pipeline is ready',
      );
      expect(find.byIcon(Icons.hourglass_top), findsNothing);
      expect(world.ops.first.playCalls, 1, reason: 'the request runs ONCE');
      // As in flow 7: playing audio is stopped cleanly, then the tree is torn down.
      await tapPause(tester);
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 200));
    }, slow);
  });
}
