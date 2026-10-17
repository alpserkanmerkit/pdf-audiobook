// WIRING test for slice 5b (§13.7 — oracle). Is the reader screen wired to the reader tab in app_shell?
// (Real TTS/audio-rhythm device acceptance is PARKED; this test covers visual + interaction accessibility.)
//
// FAZ-W3 (library -> reader transition): the REAL book tapped in the library
// must move to the reader (onOpenBook no longer discards the book), progress
// (progress_<hash>) must be restored, and a missing-file state must not crash.
// When NO book is open (direct tab switch, the two pinned tests in main() below)
// behavior MUST NOT change — backward-compatibility regression boundary.
//
// FAZ-W4 (reading-loop core): reader_screen is now driven by the pure
// lib/src/reader_machine.dart state machine (when a book and pipeline exist).
// This group replaces PagePipeline with a fake subclass WITHOUT touching real
// TTS/network (an injectable pipelineFactory seam in AppShell — same pattern as
// AppServices' playerOpsFactory). t1-t8 prove the machine-execution, prefetch,
// speed-resynthesis and sentence-tracking scenarios.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sesli_kitap/io/cache_store.dart';
import 'package:sesli_kitap/io/page_pipeline.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/src/sentence_timing.dart';
import 'package:sesli_kitap/ui/app_shell.dart';
import 'package:sesli_kitap/ui/screens/reader_screen.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';

import 'helpers/test_app.dart';

/// FAZ-W4 fake pipeline: records prepareAudio/cachedCleanText calls without
/// touching the real PDF/OCR/LLM/TTS at all, and returns the results (success
/// or error) that the test predefined.
///
/// [failOnPages]: prepareAudio throws an Exception for these page numbers
/// (PrepareFailed scenario, t4).
/// [pageText]: the clean text cachedCleanText returns for each page
/// (sentence-tracking scenario, t8 — splitIntoSentences is fed from here).
class FakePagePipeline extends PagePipeline {
  FakePagePipeline({required super.store, required super.bookHash})
    : super(bookBytes: Uint8List(0));

  final List<({int page, bool force})> prepareAudioCalls = [];
  final Set<int> failOnPages = {};
  final Map<int, String> pageText = {};

  @override
  Future<String?> cachedCleanText(int pageNo) async => pageText[pageNo];

  /// Default: NO sidecar (null). The real PagePipeline.cachedTimings does REAL
  /// disk I/O through store.readTimings; flutter_test's fake-async (outside
  /// runAsync) never drains real file I/O, so the `await cachedTimings` inside
  /// _executePrepareAudio hangs forever and pumpAndSettle times out. For this
  /// reason the fake pipeline must NOT touch the store at all; scenarios that
  /// need a karaoke sidecar use [TimingFakePagePipeline] instead.
  @override
  Future<SentenceTimings?> cachedTimings(
    int pageNo,
    PipelineSettings s,
  ) async => null;

  @override
  Future<File> prepareAudio(
    int pageNo,
    PipelineSettings s, {
    bool force = false,
  }) async {
    prepareAudioCalls.add((page: pageNo, force: force));
    if (failOnPages.contains(pageNo)) {
      throw StateError('fake preparation error: page $pageNo');
    }
    final f = File('${store.root.path}/fake_audio_p$pageNo.mp3');
    if (!f.existsSync()) {
      f.writeAsBytesSync([1, 2, 3]);
    }
    return f;
  }
}

/// Subclass of [FakePagePipeline] for R1/t22: SIMULATES the real prepareText
/// writing clean text into the cache, so pageText is filled as well — this makes
/// the "preparation done, cachedCleanText is now filled but the screen was not
/// refreshed" (H-A2) scenario possible. The behavior of [FakePagePipeline],
/// shared by the other tests, is DELIBERATELY not changed.
class CacheWritingFakePagePipeline extends FakePagePipeline {
  CacheWritingFakePagePipeline({required super.store, required super.bookHash});

  @override
  Future<File> prepareAudio(
    int pageNo,
    PipelineSettings s, {
    bool force = false,
  }) async {
    final f = await super.prepareAudio(pageNo, s, force: force);
    pageText[pageNo] = 'CapturedPageText.';
    return f;
  }
}

/// Subclass of [FakePagePipeline] for R1/t23: hands the resolution of the
/// [cachedCleanText] of SELECTED pages to the test via a [Completer] — so the
/// disk-I/O ordering uncertainty is set up DETERMINISTICALLY and the
/// "late-resolving stale call" race is isolated. Non-controlled pages resolve
/// immediately (from pageText); the SHARED behavior of [FakePagePipeline] and
/// [CacheWritingFakePagePipeline] is DELIBERATELY not changed.
class RaceControlFakePagePipeline extends FakePagePipeline {
  RaceControlFakePagePipeline({required super.store, required super.bookHash});

  /// Page -> the completer that delays the cachedCleanText future of that page.
  /// The test sets up a gate with [gate(page)] and resolves it with [release(page)].
  final Map<int, Completer<String?>> _gates = {};

  /// Sets up a gate that keeps cachedCleanText for [page] pending until the test
  /// calls [release]. Once released it resolves with [value] (null = cache
  /// miss). It does not depend on the pageText value at call time.
  void gate(int page, {String? value}) {
    final c = Completer<String?>();
    _gates[page] = c;
    _gateValues[page] = value;
  }

  final Map<int, String?> _gateValues = {};

  /// Resolves the pending cachedCleanText future of [page] whose gate was set up.
  void release(int page) {
    final c = _gates.remove(page);
    final v = _gateValues.remove(page);
    if (c != null && !c.isCompleted) c.complete(v);
  }

  @override
  Future<String?> cachedCleanText(int pageNo) {
    final gate = _gates[pageNo];
    if (gate != null) return gate.future;
    return super.cachedCleanText(pageNo);
  }
}

/// Subclass of [FakePagePipeline] for PR-K2/t25-t26: SIMULATES prepareText
/// producing the sentence-timing sidecar, filling [cachedTimings] with a
/// non-proportional (unequal) [SentenceTimings]. This isolates the question of
/// whether karaoke highlighting follows the REAL audio position and the timing
/// sidecar. A timing that differs from the length-weighted fallback (uniform
/// split of equal lengths) is needed so that the difference can be observed.
/// The behavior of [FakePagePipeline], shared by other tests (cachedTimings
/// defaults to null), is DELIBERATELY not changed.
class TimingFakePagePipeline extends FakePagePipeline {
  TimingFakePagePipeline({required super.store, required super.bookHash});

  /// Page -> the sidecar timing to return for that page (null = no sidecar).
  final Map<int, SentenceTimings> pageTimings = {};

  @override
  Future<SentenceTimings?> cachedTimings(
    int pageNo,
    PipelineSettings s,
  ) async => pageTimings[pageNo];
}

/// Subclass of [TimingFakePagePipeline] for F1/F2 (t27-t28): holds SELECTED
/// prepareAudio calls (matched by the page+force signature) on a Completer that
/// the test controls. This deterministically sets up the race "the page changed
/// WHILE preparation was IN FLIGHT, so a late result must not write stale
/// fields" (the SAME class as the generation-guard race of t23, on the audio
/// path). Non-controlled calls resolve immediately; the SHARED fake behavior is
/// DELIBERATELY not changed.
class GatedTimingFakePagePipeline extends TimingFakePagePipeline {
  GatedTimingFakePagePipeline({required super.store, required super.bookHash});

  final Map<String, Completer<void>> _prepareGates = {};

  String _gateKey(int page, bool force) => '$page:$force';

  /// Sets up a gate that keeps the prepareAudio matching [page]+[force] pending
  /// until [releasePrepare] (e.g. force:true = only the speed-change path is
  /// held; the first normal preparation and the prefetches are released freely).
  void gatePrepare(int page, {required bool force}) {
    _prepareGates[_gateKey(page, force)] = Completer<void>();
  }

  /// Resolves the gated prepareAudio (simulates the LATE arrival of a stale result).
  void releasePrepare(int page, {required bool force}) {
    final c = _prepareGates.remove(_gateKey(page, force));
    if (c != null && !c.isCompleted) c.complete();
  }

  @override
  Future<File> prepareAudio(
    int pageNo,
    PipelineSettings s, {
    bool force = false,
  }) async {
    final gate = _prepareGates[_gateKey(pageNo, force)];
    if (gate != null) await gate.future;
    return super.prepareAudio(pageNo, s, force: force);
  }
}

/// FAZ-W4 test shell: wraps AppShell directly in AppServicesScope + MaterialApp
/// WITHOUT building the full SesliKitapApp (main.dart is UNTOUCHED — out of
/// scope), so the [pipelineFactory] test-injection seam of AppShell is reachable.
/// AppSettingsScope + buildAppTheme are ALSO added (IDENTICAL to the real setup
/// in main.dart). IndexedStack eagerly builds ALL tabs (including Report), and
/// screens like ReportScreen expect
/// `Theme.of(context).extension<AppPalette>()` + `AppSettingsScope.of(context)`.
/// Without them build() crashes, which shows up as unrelated-looking errors such
/// as failing to find tab-reader. That is the root cause.
Widget buildReaderTestShell({
  required AppServices services,
  required FakePagePipeline Function(Book book) pipelineFactory,
  Key? shellKey,
}) {
  final settings = AppSettings();
  return AppServicesScope(
    services: services,
    child: AppSettingsScope(
      settings: settings,
      child: MaterialApp(
        theme: buildAppTheme(settings),
        home: AppShell(
          key: shellKey,
          pipelineFactory: ({required Book book, required CacheStore store}) =>
              pipelineFactory(book),
        ),
      ),
    ),
  );
}

/// Binds reader_screen's Stopwatches (karaoke fallback + listening time) to the
/// FAKE clock of flutter_test: `pump(duration)` now also advances
/// Stopwatch.elapsed. Previously this needed the real wall clock, and a 3-second
/// runAsync wait was the reason. The production default (real Stopwatch) is
/// restored in tearDown.
void useFakeClockReaderStopwatch(WidgetTester tester) {
  final previous = readerStopwatchFactory;
  readerStopwatchFactory = tester.binding.clock.stopwatch;
  addTearDown(() => readerStopwatchFactory = previous);
}

void main() {
  testWidgets(
    'Reader tab with no book open shows the explicit empty-state message, '
    'not fake sentences (field report: fake text must not be shown without a '
    'real PDF)',
    (tester) async {
      await tester.pumpWidget(await buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reader'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tab-reader')), findsOneWidget);
      expect(
        find.textContaining('duvarların kendisi'),
        findsNothing,
        reason: 'the old fake demo sentence must NOT be visible anymore',
      );
      expect(find.textContaining('No book is open yet'), findsWidgets);
    },
  );

  testWidgets(
    'no play/pause control is visible while no book is open (the old fake '
    '"_simplePlaying" demo button was removed, there is no real control)',
    (tester) async {
      await tester.pumpWidget(await buildTestApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reader'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(find.byIcon(Icons.pause), findsNothing);
    },
  );

  group('FAZ-W3: library -> reader book + progress handover', () {
    // Two real books: t3 proves the claim "whichever book is tapped is the one
    // shown" more strongly than a single-book scenario (it catches stale-closure
    // regressions). First w3One is made VISIBLE in the grid and the continue
    // card, then w3Two is tapped (ONLY in the grid, as a unique widget). With no
    // ambiguity about the tap target, the claim "it opened THIS one, not the
    // other" is cleanly proven.
    const w3One = Book(
      id: 'w3r-1',
      title: 'Notebook of the Wind',
      author: 'N. Aksoy',
      chapterLabel: 'Chapter 1',
      progressPercent: 10,
      totalPages: 120,
      coverIndex: 0,
      hash: 'w3rhash0011111111',
      filePath: '/tmp/w3r/nonexistent-one.pdf',
    );
    const w3Two = Book(
      id: 'w3r-2',
      title: 'Map of the Lost City',
      author: 'F. Erol',
      chapterLabel: 'Chapter 3',
      progressPercent: 55,
      totalPages: 200,
      coverIndex: 1,
      hash: 'w3rhash0022222222',
      filePath: '/tmp/w3r/nonexistent-two.pdf',
    );

    testWidgets(
      't3: after tapping a SPECIFIC one of two real books, the reader shows '
      'THAT book title (not the other one, not the demo placeholder)',
      (tester) async {
        final raw = encodeBooks([w3One, w3Two]);
        final services = await buildTestServices(
          prefsValues: {'books_v1': raw},
        );
        await tester.pumpWidget(buildTestAppFromServices(services));
        await tester.pumpAndSettle();

        // w3Two is visible ONLY in the grid (the continue card shows the first book, -w3One-).
        // The grid may sit below the scrollable area; bring it into view first.
        await tester.ensureVisible(find.text(w3Two.title));
        await tester.pumpAndSettle();
        await tester.tap(find.text(w3Two.title));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('tab-reader')), findsOneWidget);
        expect(
          find.text(w3Two.title),
          findsWidgets,
          reason: 'the reader must show the title of the tapped book (w3Two)',
        );
        expect(
          find.text(w3One.title),
          findsNothing,
          reason:
              'the reader must NOT show the title of the wrong book (w3One)',
        );
        expect(
          find.text('Book Title'),
          findsNothing,
          reason:
              'a fixed demo placeholder must not remain when a real book exists',
        );
      },
    );

    testWidgets(
      't4: if progress_<hash>=42 exists for the tapped book, the reader '
      'shows page 42',
      (tester) async {
        final raw = encodeBooks([w3One]);
        final services = await buildTestServices(
          prefsValues: {'books_v1': raw, 'progress_${w3One.hash}': 42},
        );
        await tester.pumpWidget(buildTestAppFromServices(services));
        await tester.pumpAndSettle();

        // w3One is the only book, so it appears three times (continue card
        // cover + content + grid). All of them trigger a single onOpenBook(book)
        // for the same book, so .first is a safe unique target.
        await tester.tap(find.text(w3One.title).first);
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Page 42'),
          findsWidgets,
          reason: 'the restored progress_<hash>=42 page must be shown',
        );
        expect(
          find.textContaining('Page 121'),
          findsNothing,
          reason: 'the old fixed demo page number must not remain',
        );
      },
    );

    testWidgets(
      't5: if there is NO progress_<hash> key for the tapped book, the reader '
      'shows page 1 by default',
      (tester) async {
        final raw = encodeBooks([w3One]);
        final services = await buildTestServices(
          prefsValues: {'books_v1': raw},
        );
        await tester.pumpWidget(buildTestAppFromServices(services));
        await tester.pumpAndSettle();

        await tester.tap(find.text(w3One.title).first);
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Page 1'),
          findsWidgets,
          reason: 'without progress_<hash>, the default page 1 must be shown',
        );
        expect(
          find.textContaining('Page 121'),
          findsNothing,
          reason: 'the old fixed demo page number must not remain',
        );
      },
    );

    testWidgets('t6: if the filePath of the tapped book is MISSING on disk, the '
        'reader shows an error state without crashing', (tester) async {
      final missing = File(
        '${Directory.systemTemp.path}/w3_kesinlikle_yok_${DateTime.now().microsecondsSinceEpoch}.pdf',
      );
      expect(
        missing.existsSync(),
        isFalse,
        reason: 'the fixture path must really not exist',
      );
      final ghostBook = Book(
        id: 'w3r-ghost',
        title: 'Ghost Book',
        author: 'None',
        chapterLabel: 'B1',
        progressPercent: 0,
        totalPages: 10,
        coverIndex: 2,
        hash: 'w3rhashghost',
        filePath: missing.path,
      );
      final raw = encodeBooks([ghostBook]);
      final services = await buildTestServices(prefsValues: {'books_v1': raw});
      await tester.pumpWidget(buildTestAppFromServices(services));
      await tester.pumpAndSettle();

      await tester.tap(find.text(ghostBook.title).first);
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'a missing file must not lead to a crash',
      );
      expect(
        find.byKey(const Key('tab-reader')),
        findsOneWidget,
        reason: 'the switch to the reader tab must still happen',
      );
      // Error indicator: text or icon (left open to the implementation;
      // only "something is shown" + "no crash" is asserted).
      expect(
        find.byIcon(Icons.error_outline).evaluate().isNotEmpty ||
            find.textContaining('not found').evaluate().isNotEmpty ||
            find.textContaining('File').evaluate().isNotEmpty,
        isTrue,
        reason:
            'a visual error indicator must exist for the missing-file state',
      );
    });
  });

  group('FAZ-W3b: library progress sync (progress_<hash> -> percent)', () {
    testWidgets(
      'a book with progress_<hash>=2 and totalPages=4 shows 50% in the library '
      '(the reader writes progress_<hash>; the library used to always show 0% '
      'from Book.progressPercent -- the two sources were never synced, field finding)',
      (tester) async {
        const b = Book(
          id: 'wpb-1',
          title: 'Progress Book',
          author: 'T. Test',
          chapterLabel: 'Chapter 1',
          progressPercent: 0,
          totalPages: 4,
          coverIndex: 0,
          hash: 'wpbhash000001',
          filePath: '/tmp/wpb/x.pdf',
        );
        final services = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks([b]),
            'progress_${b.hash}': 2,
          },
        );
        await tester.pumpWidget(buildTestAppFromServices(services));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('%50'),
          findsWidgets,
          reason:
              'progress_<hash>=2/4 -> the library must show 50% (reading-time '
              'sync); it used to show Book.progressPercent (0)',
        );
        expect(
          find.textContaining('%0'),
          findsNothing,
          reason: 'the old unsynced behavior (always 0%) must not remain',
        );
      },
    );
  });

  group('FAZ-W4: reading-loop core (reader_machine execution)', () {
    const w4Book = Book(
      id: 'w4r-1',
      title: 'Loop Book',
      author: 'T. Test',
      chapterLabel: 'Chapter 1',
      progressPercent: 0,
      totalPages: 5,
      coverIndex: 0,
      hash: 'w4hash000001',
      filePath:
          '/tmp/w4r/does-not-matter.pdf', // pipelineFactory takes over, the real file is NOT read
    );

    /// Taps w4Book in the library to open the reader; waits for one extra pump
    /// until the fake pipeline is ready (FutureBuilder/async construction).
    Future<FakePagePipeline> openW4Book(
      WidgetTester tester, {
      AppServices? services,
      Set<int> failOnPages = const {},
      Map<int, String> pageText = const {},
    }) async {
      final svc =
          services ??
          await buildTestServices(
            prefsValues: {
              'books_v1': encodeBooks([w4Book]),
            },
          );
      late FakePagePipeline fake;
      await tester.pumpWidget(
        buildReaderTestShell(
          services: svc,
          pipelineFactory: (book) {
            return fake =
                FakePagePipeline(store: svc.cache, bookHash: book.hash)
                  ..failOnPages.addAll(failOnPages)
                  ..pageText.addAll(pageText);
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(w4Book.title).first);
      await tester.pumpAndSettle();
      return fake;
    }

    testWidgets(
      't1: pressing play on a ready book runs PrepareAudio; on success '
      'SaveProgress writes to prefs and the player is CALLED with playFile',
      (tester) async {
        final svc = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks([w4Book]),
          },
        );
        final fake = await openW4Book(tester, services: svc);

        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();

        expect(
          fake.prepareAudioCalls.map((c) => c.page),
          contains(1),
          reason: 'ready+Toggle -> PrepareAudio(1) must run',
        );
        expect(
          svc.prefs.getInt('progress_${w4Book.hash}'),
          1,
          reason: 'PrepareSucceeded -> SaveProgress(1) must write to prefs',
        );
        expect(
          find.byIcon(Icons.pause),
          findsWidgets,
          reason:
              'in the playing phase the center button must show the pause icon',
        );
      },
    );

    testWidgets(
      't2: the playFile "completed" signal -> AudioCompleted -> the page advances '
      'and PrepareAudio(next-page) is triggered automatically',
      (tester) async {
        final createdOps = <RecordingAudioOps>[];
        final svc = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks([w4Book]),
          },
          createdOps: createdOps,
        );
        final fake = await openW4Book(tester, services: svc);

        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();
        expect(fake.prepareAudioCalls.map((c) => c.page), contains(1));

        expect(
          createdOps,
          isNotEmpty,
          reason:
              'readerPlayer must create real ops on the first playFile call',
        );
        createdOps.single.completeCurrentPlay();
        await tester.pumpAndSettle();

        expect(
          fake.prepareAudioCalls.map((c) => c.page),
          contains(2),
          reason:
              'after AudioCompleted, the automatic advance must trigger PrepareAudio(2)',
        );
      },
    );

    testWidgets(
      't3: pausing while playing calls player pause/stop; a playFile future '
      'resolved by the interruption does NOT trigger a WRONG AudioCompleted (K20 '
      'race -- on resume the page must stay the SAME, not skip ahead)',
      (tester) async {
        final createdOps = <RecordingAudioOps>[];
        final svc = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks([w4Book]),
          },
          createdOps: createdOps,
        );
        final fake = await openW4Book(tester, services: svc);

        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();
        // Page 1 is prepared AND PrepareSucceeded triggers Prefetch(1) within
        // the same transition (fire-and-forget) -- nextPrefetchBlock
        // (currentPage:1, total:5, blockSize:3) => pages 2,3,4 are prepared too.
        // This is legitimate behavior (t6 verifies it separately). To isolate
        // the K20 race here, we use the STABLE SET of pages prepared after the
        // first successful play as the reference, and prove that PAUSING adds
        // NOTHING NEW on top of it.
        final pagesAfterInitialPlay = fake.prepareAudioCalls
            .map((c) => c.page)
            .toSet();
        expect(
          pagesAfterInitialPlay,
          contains(1),
          reason: 'the current page (1) must have been prepared',
        );

        // Pause: playing -> paused, PauseAudio -> player.stop() -> ops.pause()
        // -- this also resolves the pending playFile future inside the fake ops
        // (the SAME race as the playing=true->false transition in the real
        // just_audio playToCompletion). Wiring must NOT count this as
        // AudioCompleted (page 5 -- the last page, not 2 -- must not come, and
        // no more pages than before may be prepared).
        await tester.tap(find.byIcon(Icons.pause).first);
        await tester.pumpAndSettle();

        expect(
          createdOps.single.pauseCalls,
          greaterThanOrEqualTo(1),
          reason: 'duraklatma player.pause() cagirmali',
        );
        expect(
          fake.prepareAudioCalls.map((c) => c.page).toSet(),
          pagesAfterInitialPlay,
          reason:
              'the playFile resolved by the interruption must NOT WRONGLY '
              'trigger the automatic advance (after the first play+prefetch, '
              'no MORE pages than the set may be prepared)',
        );

        // Resume: paused -> playing, PlayAudio (does not re-prepare).
        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();
        expect(
          fake.prepareAudioCalls.map((c) => c.page).toSet(),
          pagesAfterInitialPlay,
          reason: 'paused->playing must NOT trigger PrepareAudio again',
        );
      },
    );

    testWidgets(
      't4: if prepareAudio throws, the error surfaces (text/snackbar), the '
      'phase does NOT get STUCK in preparing, and there is no crash',
      (tester) async {
        final fake = await openW4Book(tester, failOnPages: {1});

        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'the error must not lead to a crash',
        );
        expect(fake.prepareAudioCalls.map((c) => c.page), [1]);
        expect(
          find.byIcon(Icons.play_arrow),
          findsWidgets,
          reason:
              'PrepareFailed -> returns to ready (the play icon must come back, must NOT stay stuck in preparing)',
        );
      },
    );

    testWidgets(
      't5: AudioCompleted of the last page sets the phase to finished, and no more '
      'PrepareAudio is TRIGGERED',
      (tester) async {
        const lastPageBook = Book(
          id: 'w4r-last',
          title: 'Last Page Book',
          author: 'T. Test',
          chapterLabel: 'Last',
          progressPercent: 0,
          totalPages: 1,
          coverIndex: 0,
          hash: 'w4hashlast',
          filePath: '/tmp/w4r/last.pdf',
        );
        final createdOps = <RecordingAudioOps>[];
        final svc = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks([lastPageBook]),
          },
          createdOps: createdOps,
        );
        late FakePagePipeline fake;
        await tester.pumpWidget(
          buildReaderTestShell(
            services: svc,
            pipelineFactory: (book) {
              return fake = FakePagePipeline(
                store: svc.cache,
                bookHash: book.hash,
              );
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(lastPageBook.title).first);
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();
        expect(fake.prepareAudioCalls.map((c) => c.page), [1]);

        createdOps.single.completeCurrentPlay();
        await tester.pumpAndSettle();

        expect(
          fake.prepareAudioCalls.map((c) => c.page),
          [1],
          reason:
              'after the last page ends, no other PrepareAudio must be TRIGGERED',
        );
      },
    );

    testWidgets(
      't6: after successful playback starts, Prefetch is triggered for the next '
      'pages (fire-and-forget, the same pages as nextPrefetchBlock)',
      (tester) async {
        final fake = await openW4Book(tester);

        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();

        final pages = fake.prepareAudioCalls.map((c) => c.page).toSet();
        expect(pages, contains(1), reason: 'the current page must be prepared');
        expect(
          pages.intersection({2, 3, 4}),
          isNotEmpty,
          reason:
              'prefetch via nextPrefetchBlock(currentPage:1,total:5) must also '
              'prepare the next pages (fire-and-forget)',
        );
      },
    );

    testWidgets(
      't6b: a prefetch error does NOT affect the current playback, and no error '
      'surfaces at all (best-effort)',
      (tester) async {
        // Page 2 (in the prefetch block) throws; page 1 (current) must stay
        // successful, and there must be no crash or error indicator.
        final fake = await openW4Book(tester, failOnPages: {2});

        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          fake.prepareAudioCalls.map((c) => c.page),
          contains(1),
          reason: 'the current page must NOT be affected by a prefetch error',
        );
        expect(
          find.byIcon(Icons.pause),
          findsWidgets,
          reason: 'page 1 must keep playing successfully',
        );
      },
    );

    testWidgets(
      't7: tapping a speed chip updates services.reading.rate AND the current '
      'page is RE-SYNTHESIZED with force:true',
      (tester) async {
        final svc = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks([w4Book]),
          },
        );
        final fake = await openW4Book(tester, services: svc);
        final oldRate = svc.reading.rate;

        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();
        final callsBeforeSpeedChange = fake.prepareAudioCalls.length;

        // Speed chip: we tap the current label text (speedLabels[1]='1×'
        // matches the default _speedIndex).
        await tester.tap(find.text('1×'));
        await tester.pumpAndSettle();

        expect(
          svc.reading.rate,
          isNot(oldRate),
          reason:
              'the speed chip must change services.reading.rate (persistence)',
        );
        expect(
          fake.prepareAudioCalls.length,
          greaterThan(callsBeforeSpeedChange),
          reason:
              'when the speed changes, the current page must be re-synthesized',
        );
        expect(
          fake.prepareAudioCalls.last.force,
          isTrue,
          reason:
              're-synthesis must be called with force:true (cache bypassed)',
        );
        expect(
          fake.prepareAudioCalls.last.page,
          1,
          reason: 're-synthesis must be for the CURRENT page',
        );
      },
    );

    testWidgets(
      't8: during playback the sentence-tracking index advances as time passes '
      '(periodic estimate) and the widget leaves no pending Timer on dispose',
      (tester) async {
        useFakeClockReaderStopwatch(tester);
        final fake = await openW4Book(
          tester,
          pageText: {
            1:
                'Bir. Iki. Uc. Dort. Bes. Alti. Yedi. Sekiz. Dokuz. On. '
                'Onbir. Oniki. Onuc. Ondort. Onbes.',
          },
        );

        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();
        expect(fake.prepareAudioCalls.map((c) => c.page), contains(1));

        // Checks whether a sentence is in the "narrating" visual state, by
        // whether the Container ancestor of its Text is painted with the
        // highlight color (reader_screen sentence-list -> visualStateFor -> bgColor).
        bool isHighlighted(String sentenceText) {
          final textFinder = find.text(sentenceText);
          if (textFinder.evaluate().isEmpty) return false;
          final container = tester.widget<Container>(
            find
                .ancestor(of: textFinder, matching: find.byType(Container))
                .first,
          );
          final decoration = container.decoration;
          return decoration is BoxDecoration && decoration.color != null;
        }

        // At t0 no time has passed yet: the first sentence ("Bir.") is
        // highlighted, a distant sentence ("Onbes.") is NOT highlighted.
        expect(isHighlighted('Bir.'), isTrue);
        expect(isHighlighted('Onbes.'), isFalse);

        // Advance time: the periodic estimate must move forward in order.
        // IMPORTANT: this progress relies on a REAL Stopwatch inside
        // reader_screen.dart (the Stopwatch uses the wall clock and does NOT
        // follow the FAKE pump(duration) clock of flutter_test -- verified: even
        // after a 10s fake pump loop, Stopwatch.elapsed stays ~2ms). So here real
        // time is spent via tester.runAsync (Timer.periodic also fires for REAL).
        // With estimatedPageDuration=30s + 15 sentences, ~3 real seconds is enough
        // to move the ratio to >=1/15 (the index advances from 0). The exact target
        // index depends on the estimation coefficient (estimateNarratingSentenceIndex
        // is already a gated pure function), so only "THE TIMER REALLY FIRED and the
        // highlight MOVED AWAY from the FIRST SENTENCE" is asserted here.
        await tester.pump(const Duration(seconds: 3));
        // The Timer's setState may have fired during the real wait; the widget
        // tree needs at least one pump to reflect it. A single pump was observed
        // to be insufficient (frame timing), so two pumps are applied for a safe margin.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          isHighlighted('Bir.'),
          isFalse,
          reason:
              '3 real seconds later the highlight must NOT remain on the first '
              'sentence (if the periodic Timer does not advance it, this claim is '
              'wrong -> FAIL)',
        );

        // No pending-timer error must occur on dispose (leaving the widget tree).
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason:
              'the Timer must be cancelled on dispose (no pending-timer error)',
        );
      },
    );

    testWidgets(
      't9: if playFile (playback, NOT preparation) throws, the error surfaces '
      'through a visible SnackBar and is not silently swallowed (the second -- '
      'non-prepare -- end of the user field report: "no sound, and I see no error")',
      (tester) async {
        final createdOps = <RecordingAudioOps>[];
        final svc = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks([w4Book]),
          },
          createdOps: createdOps,
        );
        await openW4Book(tester, services: svc);

        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();
        expect(
          createdOps,
          isNotEmpty,
          reason: 'real ops must have been created by the first play',
        );

        // On pause, the next resume call on the same ops (readerPlayer is a
        // singleton) throws an error. As t3 already proved, paused->playing does
        // NOT repeat PrepareAudio; it calls playFile directly again.
        createdOps.single.playError = StateError('fake playback error');
        await tester.tap(find.byIcon(Icons.pause).first);
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'the playback error must not lead to a crash',
        );
        expect(
          find.textContaining('Playback error', findRichText: true),
          findsWidgets,
          reason:
              'the playFile error must surface with a visible SnackBar/text '
              '(today .then() handles only the success branch, the error is silently swallowed)',
        );
      },
    );

    testWidgets(
      't10: tapping ANOTHER TAB from the reader tab STOPS the playing audio '
      '(field report: switching tabs did not stop the audio, it kept playing in '
      'the background -- an IndexedStack offstage child is NOT disposed)',
      (tester) async {
        final createdOps = <RecordingAudioOps>[];
        final svc = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks([w4Book]),
          },
          createdOps: createdOps,
        );
        await openW4Book(tester, services: svc);

        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();
        expect(createdOps, isNotEmpty);
        final pauseCallsWhilePlaying = createdOps.single.pauseCalls;

        await tester.tap(find.text('Report'));
        await tester.pumpAndSettle();

        expect(
          createdOps.single.pauseCalls,
          greaterThan(pauseCallsWhilePlaying),
          reason:
              'the audio playing must be stopped when switching to another tab',
        );
      },
    );

    testWidgets(
      't11: on the reader tab, SYSTEM BACK (PopScope) ALSO STOPS the playing '
      'audio',
      (tester) async {
        final createdOps = <RecordingAudioOps>[];
        final svc = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks([w4Book]),
          },
          createdOps: createdOps,
        );
        await openW4Book(tester, services: svc);

        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();
        expect(createdOps, isNotEmpty);
        final pauseCallsWhilePlaying = createdOps.single.pauseCalls;

        final popScope = tester.widget<PopScope>(
          find.byWidgetPredicate((w) => w is PopScope),
        );
        popScope.onPopInvokedWithResult!(false, null);
        await tester.pumpAndSettle();

        expect(
          createdOps.single.pauseCalls,
          greaterThan(pauseCallsWhilePlaying),
          reason: 'the audio playing must also be stopped by system back',
        );
      },
    );

    testWidgets(
      't12: DEVICE FINDING -- when the tab changes, the playFile that was cut must '
      'NOT be taken as a "natural page end" and must NOT start preparing/playing '
      'the next page automatically (AppShell was calling readerPlayer.stop() '
      'directly, WITHOUT going through the _playGeneration/_readerState bookkeeping '
      'of ReaderScreen -- proven on a real device with dumpsys audio: after '
      'returning to the Library, new AudioTrack players kept starting)',
      (tester) async {
        final createdOps = <RecordingAudioOps>[];
        final svc = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks([w4Book]),
          },
          createdOps: createdOps,
        );
        final fake = await openW4Book(tester, services: svc);

        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();
        final callsAfterInitialPlay = fake.prepareAudioCalls.length;
        expect(
          fake.prepareAudioCalls.map((c) => c.page),
          contains(1),
          reason: 'the current page (1) must have been prepared',
        );

        await tester.tap(find.text('Report'));
        await tester.pumpAndSettle();

        expect(
          fake.prepareAudioCalls.length,
          callsAfterInitialPlay,
          reason:
              'the playFile cut by the tab switch must NOT be taken as a fake '
              'completion under the playToCompletion "pause=end" contract, and '
              'must NOT automatically advance to the next page (background-playback '
              'bug -- the interruption must be marked with gen/phase bookkeeping)',
        );
      },
    );

    // ===== FAZ-W5: manual page navigation (page selector + prev/next) =====
    // The reader_machine PageEntered event is ALREADY covered by tests
    // (reader_machine_test), but it was NEVER dispatched from the UI. This group
    // verifies the UI wiring: tap the indicator -> Slider selector -> PageEntered;
    // prev/next buttons; while PLAYING, a jump first goes through a SYNCHRONOUS
    // suspend (PR#34 gen/phase safety).
    testWidgets(
      't13: tapping the progress indicator opens the page selector (Slider)',
      (tester) async {
        await openW4Book(tester);
        expect(find.byKey(const Key('page-indicator')), findsOneWidget);
        await tester.tap(find.byKey(const Key('page-indicator')));
        await tester.pumpAndSettle();
        expect(
          find.byType(Slider),
          findsOneWidget,
          reason: 'tapping the indicator must open the page-selector Slider',
        );
      },
    );

    testWidgets(
      't14: in the ready phase, jumping to page 3 with the selector shows the '
      'page-3 indicator ("Page 3"), loads page-3 content, and the jump ALONE '
      'does NOT produce prepareAudio',
      (tester) async {
        final fake = await openW4Book(tester, pageText: {3: 'ThirdPageText.'});
        final callsBefore = fake.prepareAudioCalls.length;

        await tester.tap(find.byKey(const Key('page-indicator')));
        await tester.pumpAndSettle();
        final slider = tester.widget<Slider>(find.byType(Slider));
        slider.onChanged!(3);
        await tester.pump();
        await tester.tap(find.byKey(const Key('page-go')));
        await tester.pumpAndSettle();

        expect(find.textContaining('Page 3'), findsWidgets);
        expect(
          find.textContaining('ThirdPageText'),
          findsWidgets,
          reason: 'the content of the jumped-to page (3) must be loaded',
        );
        expect(
          fake.prepareAudioCalls.length,
          callsBefore,
          reason:
              'in the ready phase a page jump ALONE does NOT produce PrepareAudio '
              '(a Toggle is needed to continue)',
        );
      },
    );

    testWidgets(
      't15: jumping with the selector WHILE PLAYING first does a SYNCHRONOUS '
      'suspend (pause), the phase becomes paused, and the cut playFile does NOT '
      'WRONGLY trigger AudioCompleted',
      (tester) async {
        final createdOps = <RecordingAudioOps>[];
        final svc = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks([w4Book]),
          },
          createdOps: createdOps,
        );
        final fake = await openW4Book(
          tester,
          services: svc,
          pageText: {3: 'ThirdPageText.'},
        );

        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();
        final pagesAfterPlay = fake.prepareAudioCalls
            .map((c) => c.page)
            .toSet();
        final pauseBefore = createdOps.single.pauseCalls;

        await tester.tap(find.byKey(const Key('page-indicator')));
        await tester.pumpAndSettle();
        final slider = tester.widget<Slider>(find.byType(Slider));
        slider.onChanged!(3);
        await tester.pump();
        await tester.tap(find.byKey(const Key('page-go')));
        await tester.pumpAndSettle();

        expect(
          createdOps.single.pauseCalls,
          greaterThan(pauseBefore),
          reason:
              'a jump while playing must first do a synchronous interruption (stop/pause)',
        );
        expect(
          find.byIcon(Icons.play_arrow),
          findsWidgets,
          reason:
              'after the jump the phase must be paused (the play icon comes back)',
        );

        createdOps.single.completeCurrentPlay();
        await tester.pumpAndSettle();
        expect(
          fake.prepareAudioCalls.map((c) => c.page).toSet(),
          pagesAfterPlay,
          reason:
              'the cut playFile must NOT be taken as a fake completion and must '
              'NOT automatically advance to the next page (PR#34 gen/phase safety)',
        );
      },
    );

    testWidgets(
      't16: the next button moves to the next page (indicator "Page 2", content '
      'is loaded)',
      (tester) async {
        await openW4Book(tester, pageText: {2: 'SecondPageText.'});
        await tester.tap(find.byKey(const Key('page-next')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Page 2'), findsWidgets);
        expect(
          find.textContaining('SecondPageText'),
          findsWidgets,
          reason: 'next must load the content of the next page',
        );
      },
    );

    testWidgets(
      't17: the back button is DISABLED on page 1, and the next button is DISABLED on the last page',
      (tester) async {
        await openW4Book(tester);
        final prev = tester.widget<IconButton>(
          find.byKey(const Key('page-prev')),
        );
        expect(
          prev.onPressed,
          isNull,
          reason: 'back must be disabled on the first page',
        );

        // Jump to the last page (5)
        await tester.tap(find.byKey(const Key('page-indicator')));
        await tester.pumpAndSettle();
        final slider = tester.widget<Slider>(find.byType(Slider));
        slider.onChanged!(5);
        await tester.pump();
        await tester.tap(find.byKey(const Key('page-go')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Page 5'), findsWidgets);

        final next = tester.widget<IconButton>(
          find.byKey(const Key('page-next')),
        );
        expect(
          next.onPressed,
          isNull,
          reason: 'next must be disabled on the last page',
        );
      },
    );

    testWidgets(
      't18: a page jump in the ready phase does NOT call SaveProgress '
      '(progress_<hash> prefs are NOT changed -- only a page that was prepared and played is persisted)',
      (tester) async {
        final svc = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks([w4Book]),
          },
        );
        await openW4Book(tester, services: svc);
        expect(
          svc.prefs.getInt('progress_${w4Book.hash}'),
          isNull,
          reason: 'with no playback, progress must not have been written yet',
        );

        await tester.tap(find.byKey(const Key('page-next')));
        await tester.pumpAndSettle();

        expect(
          svc.prefs.getInt('progress_${w4Book.hash}'),
          isNull,
          reason:
              'a page jump must NOT call SaveProgress (prefs must be preserved)',
        );
      },
    );

    testWidgets(
      't19: play -> jump to ANOTHER page -> play, the audio of the SKIPPED-TO page '
      'is prepared and played (the stale _lastPreparedAudioPath does NOT replay '
      'the page-1 audio, and the page is NOT skipped -- adversarial-review finding)',
      (tester) async {
        final createdOps = <RecordingAudioOps>[];
        final svc = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks([w4Book]),
          },
          createdOps: createdOps,
        );
        final fake = await openW4Book(
          tester,
          services: svc,
          pageText: {3: 'ThirdPageText.'},
        );

        // Play page 1
        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();
        expect(
          createdOps.single.loadedPaths.last,
          endsWith('fake_audio_p1.mp3'),
          reason: 'the page 1 audio must have played first',
        );

        // Skip to page 3 (while playing -> synchronous suspend -> paused)
        await tester.tap(find.byKey(const Key('page-next'))); // -> 2
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('page-next'))); // -> 3
        await tester.pumpAndSettle();
        expect(find.textContaining('Page 3'), findsWidgets);

        final page3Before = fake.prepareAudioCalls
            .where((c) => c.page == 3)
            .length;

        // Press play -> the SKIPPED page (3) must be prepared and played
        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();

        expect(
          fake.prepareAudioCalls.where((c) => c.page == 3).length,
          greaterThan(page3Before),
          reason:
              'pressing play on the skipped page (3) must prepare THAT page again '
              '(the stale page-1 audio must NOT play again)',
        );
        expect(
          createdOps.single.loadedPaths.last,
          endsWith('fake_audio_p3.mp3'),
          reason:
              'the played audio must be the SKIPPED page (3) audio, NOT the stale page-1 one',
        );
      },
    );

    testWidgets('t20: the reader top bar has NO dead icons (brush/bookmark_add/'
        'text_fields) (tappable affordances that did nothing were removed)', (
      tester,
    ) async {
      await openW4Book(tester);
      expect(find.byIcon(Icons.brush), findsNothing);
      expect(find.byIcon(Icons.bookmark_add), findsNothing);
      expect(find.byIcon(Icons.text_fields), findsNothing);
    });

    // ===== R1: content freshness after a page jump (H-A1/H-A2) =====
    // H-A1: cachedCleanText returns null on a cache miss, and _loadPageContent
    // does NOT handle the null branch -> the previous page's text stays hanging
    // on screen and the user sees no placeholder. H-A2: content is loaded only
    // while newPage != _currentDisplayPage -> even if play fills the cache after
    // a jump, the screen is NOT refreshed (audio plays, text does not appear).
    testWidgets(
      't21: when jumping to a page whose text has NOT been produced yet, the '
      'previous page text does NOT stay hanging, and the "This page has not been prepared yet" placeholder '
      'is shown (H-A1)',
      (tester) async {
        await openW4Book(tester, pageText: {1: 'FirstPageText.'});
        expect(
          find.textContaining('FirstPageText'),
          findsWidgets,
          reason: 'precondition: the page 1 text must be loaded on open',
        );

        // Jump with the selector to page 3, which is NOT in pageText (t14 idiom).
        await tester.tap(find.byKey(const Key('page-indicator')));
        await tester.pumpAndSettle();
        final slider = tester.widget<Slider>(find.byType(Slider));
        slider.onChanged!(3);
        await tester.pump();
        await tester.tap(find.byKey(const Key('page-go')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Page 3'), findsWidgets);

        expect(
          find.textContaining('FirstPageText'),
          findsNothing,
          reason:
              'while the jumped-to page (3) has no text, the PREVIOUS page (1) '
              'text must NOT stay hanging on screen (stale-text bug: '
              '_loadPageContent does not handle the cache-miss/null branch)',
        );
        expect(
          find.textContaining('This page has not been prepared yet'),
          findsWidgets,
          reason:
              'on a page whose text is not produced yet, the placeholder '
              '"This page has not been prepared yet" must be shown (NOT an empty or stale body)',
        );
      },
    );

    testWidgets(
      't22: jump to a page with no text + play -> once the preparation writes the '
      "text into the cache, the SCREEN is refreshed too and the skipped page's text "
      'appears (H-A2: today the audio plays but the text does NOT come)',
      (tester) async {
        final svc = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks([w4Book]),
          },
        );
        // t5 idiom: instead of openW4Book's shared FakePagePipeline, a cache-writing
        // subclass is injected (the fakes of the other tests stay intact).
        late CacheWritingFakePagePipeline fake;
        await tester.pumpWidget(
          buildReaderTestShell(
            services: svc,
            pipelineFactory: (book) {
              return fake = CacheWritingFakePagePipeline(
                store: svc.cache,
                bookHash: book.hash,
              );
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(w4Book.title).first);
        await tester.pumpAndSettle();

        // pageText is EMPTY -> page 3 is a miss. Jump with the selector (t14 idiom).
        await tester.tap(find.byKey(const Key('page-indicator')));
        await tester.pumpAndSettle();
        final slider = tester.widget<Slider>(find.byType(Slider));
        slider.onChanged!(3);
        await tester.pump();
        await tester.tap(find.byKey(const Key('page-go')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Page 3'), findsWidgets);
        expect(
          find.textContaining('CapturedPageText'),
          findsNothing,
          reason:
              'precondition: before play, the page 3 text is NOT in the cache yet',
        );

        // Play: PrepareAudio(3) fills pageText[3] in the fake (simulates the real
        // prepareText writing to the cache).
        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();

        expect(
          fake.prepareAudioCalls.map((c) => c.page),
          contains(3),
          reason: 'precondition: play must have prepared the skipped page (3)',
        );
        expect(
          find.textContaining('CapturedPageText'),
          findsWidgets,
          reason:
              'after the preparation writes text into the cache, the SCREEN must '
              'refresh (today content loads only when the page NUMBER changes -> '
              'in this flow, which stays on the same page, audio plays and no text comes)',
        );
      },
    );

    testWidgets(
      't23: a late-resolving STALE cachedCleanText call does NOT overwrite the '
      'text of a fresh page loaded later (generation-guard race -- adversarial-review '
      'finding: jump to a miss page, then to a hit page; when the miss resolves LATE '
      'its placeholder must not overwrite the stale text and wipe the fresh content)',
      (tester) async {
        final svc = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks([w4Book]),
          },
        );
        late RaceControlFakePagePipeline fake;
        await tester.pumpWidget(
          buildReaderTestShell(
            services: svc,
            pipelineFactory: (book) {
              return fake = RaceControlFakePagePipeline(
                store: svc.cache,
                bookHash: book.hash,
              )..pageText.addAll({1: 'FirstPageText.'});
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(w4Book.title).first);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('FirstPageText'),
          findsWidgets,
          reason: 'precondition: the page 1 text must be loaded',
        );

        // Set up the race: page 2 = MISS (null), page 3 = HIT (text). Hand the
        // resolution of both cachedCleanText calls to the test (sets the I/O order).
        fake
          ..gate(2) // page 2: cache miss (will resolve late)
          ..gate(3, value: 'ThirdPageText.'); // page 3: cache hit

        // 1 -> 2 (miss call A stays pending) -> 3 (hit call B stays pending).
        await tester.tap(find.byKey(const Key('page-next'))); // -> 2
        await tester.pump();
        await tester.tap(find.byKey(const Key('page-next'))); // -> 3
        await tester.pump();
        expect(find.textContaining('Page 3'), findsWidgets);

        // FIRST the fresh page (3, hit) resolves -> its text appears on screen.
        fake.release(3);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('ThirdPageText'),
          findsWidgets,
          reason: 'once the fresh page (3, hit) resolves, its text must appear',
        );

        // THEN the stale page (2, miss) resolves LATE. Without the generation
        // guard, it would unconditionally emit the placeholder and wipe the fresh
        // text (BUG). With the guard, a late stale call does no setState at all.
        fake.release(2);
        await tester.pumpAndSettle();

        expect(
          find.textContaining('ThirdPageText'),
          findsWidgets,
          reason:
              'the late-resolving stale miss call must NOT overwrite the FRESH page '
              'text (without the generation guard the placeholder would wipe the '
              'fresh content -> FAIL)',
        );
        expect(
          find.textContaining('This page has not been prepared yet'),
          findsNothing,
          reason:
              'the user is on the hit page (3, text ready) -- the stale placeholder '
              'must NOT be visible',
        );
      },
    );

    // ===== HIGHLIGHT-SYNC: sentence highlight follows the REAL audio duration =====
    // FIELD FINDING: "when the text arrives, the read-aloud does not highlight
    // where it is reading." Root cause: _startSentenceTimer assumed every page
    // lasts a FIXED 30s (estimatedPageDuration: const Duration(seconds: 30)).
    // Real pages vary from 10-90s -> on a short page the highlight lags behind, and
    // on a long page it jumps to the last sentence at 30s and GETS STUCK. Fix: use
    // the player's REAL duration (AudioPlayerOps.currentDuration).
    //
    // This test sets the player's duration to 2s (short page). After ~3s of real time:
    //   - With the REAL duration (2s): ratio=clamp(3/2)=0.999 -> index=floor(0.999*15)
    //     =14 -> the LAST sentence ("Onbes.") is highlighted.
    //   - With the old FIXED 30s: ratio=3/30=0.1 -> index=floor(0.1*15)=1 -> the
    //     highlight is still at the START (an early sentence), NOT the last one.
    // So the claim "after 3s the LAST sentence is highlighted" fails (RED) unless
    // the reader uses the player's duration.
    testWidgets(
      't24: sentence highlight follows the player REAL duration -- on a short (2s) '
      'page, after ~3s of real time the highlight reaches the LAST sentence (with '
      'the fixed-30s assumption it would still be at the START -> out of sync with '
      'the audio, field finding)',
      (tester) async {
        useFakeClockReaderStopwatch(tester);
        final createdOps = <RecordingAudioOps>[];
        final svc = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks([w4Book]),
          },
          createdOps: createdOps,
        );
        final fake = await openW4Book(
          tester,
          services: svc,
          pageText: {
            1:
                'Bir. Iki. Uc. Dort. Bes. Alti. Yedi. Sekiz. Dokuz. On. '
                'Onbir. Oniki. Onuc. Ondort. Onbes.',
          },
        );

        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();
        expect(fake.prepareAudioCalls.map((c) => c.page), contains(1));

        // The player reports the REAL duration of this page: 2s (short page).
        // (In production this is just_audio `_player.duration`; here it comes from the fake ops.)
        expect(
          createdOps,
          isNotEmpty,
          reason: 'play must have created real reader ops',
        );
        createdOps.single.fakeDuration = const Duration(seconds: 2);

        // Same idiom as t8: reader_screen uses a REAL Stopwatch (it does not follow
        // the fake pump clock), so real time is spent.
        bool isHighlighted(String sentenceText) {
          final textFinder = find.text(sentenceText);
          if (textFinder.evaluate().isEmpty) return false;
          final container = tester.widget<Container>(
            find
                .ancestor(of: textFinder, matching: find.byType(Container))
                .first,
          );
          final decoration = container.decoration;
          return decoration is BoxDecoration && decoration.color != null;
        }

        await tester.pump(const Duration(seconds: 3));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          isHighlighted('Onbes.'),
          isTrue,
          reason:
              'with a 2s player duration, after ~3s of real time the highlight must '
              'be on the LAST sentence (if the reader uses the REAL duration, '
              'ratio>=0.999). If the fixed-30s assumption is still in place, '
              'ratio=3/30=0.1 -> the highlight stays near the start -> this claim FAILS (RED).',
        );
        expect(
          isHighlighted('Bir.'),
          isFalse,
          reason:
              'on the short page, after 3s the FIRST sentence must NO LONGER be '
              'highlighted (if the real duration is used, the highlight must have advanced)',
        );

        // No pending-timer error on dispose.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    // ===== KARAOKE (PR-K2): highlight follows the REAL audio position + timing sidecar =====
    // FIELD FINDING (continued): the PR-K1 word-boundary timing sidecar IS produced,
    // but the reader NEVER CONSUMED it -- the highlight still relied on the
    // wall-clock Stopwatch plus a length-weighted uniform estimate. In real TTS,
    // sentences take disproportionate time (short ones fast, long ones slow, with
    // pauses); the sidecar knows this. Fix: the reader selects the highlight index
    // with narratingIndexAt, using (1) the player's REAL position (currentPosition;
    // frozen while paused) and (2) the cachedTimings sidecar.

    /// Reads whether a sentence is in the "narrating" visual state, by whether the
    /// Container ancestor of its Text carries the highlight color (bgColor)
    /// (same idiom as t8/t24).
    bool isHighlighted(WidgetTester tester, String sentenceText) {
      final textFinder = find.text(sentenceText);
      if (textFinder.evaluate().isEmpty) return false;
      final container = tester.widget<Container>(
        find.ancestor(of: textFinder, matching: find.byType(Container)).first,
      );
      final decoration = container.decoration;
      return decoration is BoxDecoration && decoration.color != null;
    }

    /// Shell for t25/t26: injects a [TimingFakePagePipeline] (instead of the
    /// shared FakePagePipeline), opens the book and returns the fake. The ops are
    /// read from the createdOps list of [services] (t24 idiom).
    Future<TimingFakePagePipeline> openW4BookTiming(
      WidgetTester tester, {
      required AppServices services,
      required Map<int, String> pageText,
      required Map<int, SentenceTimings> pageTimings,
    }) async {
      late TimingFakePagePipeline fake;
      await tester.pumpWidget(
        buildReaderTestShell(
          services: services,
          pipelineFactory: (book) {
            return fake =
                TimingFakePagePipeline(
                    store: services.cache,
                    bookHash: book.hash,
                  )
                  ..pageText.addAll(pageText)
                  ..pageTimings.addAll(pageTimings);
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(w4Book.title).first);
      await tester.pumpAndSettle();
      return fake;
    }

    testWidgets('t25: the highlight is chosen from the timing sidecar (which DIFFERS from the '
        'length-weighted estimate) and the REAL player position -- for 3 similar-length '
        'sentences with disproportionate startsMs[0,8000,9000]/total10000, at position '
        '8500ms the highlight must be on the MIDDLE sentence (without the fix: '
        'stopwatch~0 -> FIRST sentence -> FAIL)', (tester) async {
      final createdOps = <RecordingAudioOps>[];
      final svc = await buildTestServices(
        prefsValues: {
          'books_v1': encodeBooks([w4Book]),
        },
        createdOps: createdOps,
      );
      final fake = await openW4BookTiming(
        tester,
        services: svc,
        // Three similar-length sentences: the length-weighted fallback would split
        // them into ~EQUAL shares (8.5/10 -> last quarter -> LAST sentence). The
        // sidecar instead covers the 8000-9000ms range for the MIDDLE sentence, so
        // 8500ms is MIDDLE.
        pageText: {1: 'Aaaa bbbb. Cccc dddd. Eeee ffff.'},
        pageTimings: {
          1: const SentenceTimings(startsMs: [0, 8000, 9000], totalMs: 10000),
        },
      );

      await tester.tap(find.byIcon(Icons.play_arrow).first);
      await tester.pumpAndSettle();
      expect(fake.prepareAudioCalls.map((c) => c.page), contains(1));

      expect(
        createdOps,
        isNotEmpty,
        reason: 'play must have set up the reader-player ops',
      );

      // The player reports the REAL state: duration 10s, position 8500ms. This
      // POSITION is independent of the wall clock (fake pump) -> if the reader uses
      // currentPosition, it reads this when the timer fires under the fake pump.
      createdOps.single
        ..fakeDuration = const Duration(seconds: 10)
        ..fakePosition = const Duration(milliseconds: 8500);

      // Fire the periodic timer (250ms) on the fake clock. currentPosition is a
      // fake position, NOT the wall clock, so a fake pump is enough.
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        isHighlighted(tester, 'Cccc dddd.'),
        isTrue,
        reason:
            'the position 8500ms lies in the sidecar MIDDLE sentence range '
            '(startsMs[1]=8000<=8500<9000) -> the highlight must be on the MIDDLE '
            'sentence. Without the fix the highlight stays on the FIRST sentence '
            '(stopwatch~0) -> FAIL.',
      );
      expect(
        isHighlighted(tester, 'Aaaa bbbb.'),
        isFalse,
        reason:
            'the position advanced to the MIDDLE sentence -> the FIRST sentence '
            'must NO LONGER be highlighted',
      );
      expect(
        isHighlighted(tester, 'Eeee ffff.'),
        isFalse,
        reason:
            'the position (8500) has NOT reached the LAST sentence startsMs (9000) '
            '-> the LAST sentence must NOT be highlighted yet (if the sidecar is consumed)',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('t26: while the player position is FROZEN (stuck at 200ms), the highlight stays '
        'on the FIRST sentence even though real time passes -- on pause the position '
        'freezes and so does the highlight (without the fix the old Stopwatch advances '
        'real time -> FAIL)', (tester) async {
      useFakeClockReaderStopwatch(tester);
      final createdOps = <RecordingAudioOps>[];
      final svc = await buildTestServices(
        prefsValues: {
          'books_v1': encodeBooks([w4Book]),
        },
        createdOps: createdOps,
      );
      final fake = await openW4BookTiming(
        tester,
        services: svc,
        pageText: {1: 'Aaaa bbbb. Cccc dddd. Eeee ffff.'},
        pageTimings: {
          1: const SentenceTimings(startsMs: [0, 2000, 4000], totalMs: 5000),
        },
      );

      await tester.tap(find.byIcon(Icons.play_arrow).first);
      await tester.pumpAndSettle();
      expect(fake.prepareAudioCalls.map((c) => c.page), contains(1));

      createdOps.single
        ..fakeDuration = const Duration(seconds: 5)
        // Position FROZEN at 200ms: startsMs[0]=0 <= 200 < startsMs[1]=2000 ->
        // narratingIndexAt=0 -> FIRST sentence. As long as the position does not
        // advance (pause simulation), the highlight MUST stay on the first sentence.
        ..fakePosition = const Duration(milliseconds: 200);

      // Let ~3 REAL seconds pass (the old Stopwatch advances this; the new
      // position-based path reads the REAL position -- frozen at 200ms -- and does
      // not advance). Timers must fire for real: runAsync + pump (t8/t24 idiom).
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        isHighlighted(tester, 'Aaaa bbbb.'),
        isTrue,
        reason:
            'the player position is FROZEN at 200ms -> the highlight must STAY on '
            'the FIRST sentence (even if real time passes). Without the fix the old '
            'Stopwatch advances 3s, ratio 3/5 -> it moves to the MIDDLE/LAST sentence '
            '-> this claim FAILS.',
      );
      expect(
        isHighlighted(tester, 'Eeee ffff.'),
        isFalse,
        reason:
            'at the frozen position (200ms) the LAST sentence (start 4000ms) must NOT be highlighted',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // ===== F1/F2 (adversarial-review): a stale preparation result must NOT be =====
    // written to the NEW page. The await chain inside _executePrepareAudio (F1) and
    // the speed-chip force path (F2) (prepareAudio -> cachedTimings) has NO
    // generation guard: if the user jumps to another page while preparation is
    // running, the late result is written by a mounted-only setState into the
    // _pageTimings + _lastPreparedAudioPath of the OLD page, onto the NEW page. If
    // the sentence counts happen to match, the startsMs-length guard in the tick is
    // MASKED and wrong karaoke positions get driven. This is the audio-path
    // counterpart of the late-resolving stale call race fought in t23.
    //
    // Setup (shared by both tests): page 1 and page 2 have the SAME sentence count
    // (3 each, equal length -- DELIBERATELY, so the stale timing gets past the length
    // guard). Only page 1 has a sidecar, and it is DELIBERATELY disproportionate:
    // [0,8000,9000]/10000. While page 2 plays with position 8500ms and duration 10s:
    //   - CORRECT (page-2 fallback, equal weights [0,3333,6667]): the LAST sentence.
    //   - STALE (page-1 sidecar leaked): 8000<=8500<9000 -> the MIDDLE sentence.
    // The claim "LAST highlighted, not MIDDLE" FAILS without the fix -> RED.
    testWidgets(
      't27: switching to page 2 while the page-1 preparation is IN FLIGHT -- the '
      'late-resolving preparation must NOT let the OLD page timing sidecar be '
      'CONSUMED by the NEW page (F1 generation guard; without the fix the stale T1 '
      'is written and the highlight moves to the MIDDLE sentence -> RED)',
      (tester) async {
        final createdOps = <RecordingAudioOps>[];
        final svc = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks([w4Book]),
          },
          createdOps: createdOps,
        );
        late GatedTimingFakePagePipeline fake;
        await tester.pumpWidget(
          buildReaderTestShell(
            services: svc,
            pipelineFactory: (book) {
              return fake =
                  GatedTimingFakePagePipeline(
                      store: svc.cache,
                      bookHash: book.hash,
                    )
                    ..pageText.addAll({
                      1: 'Gggg hhhh. Iiii jjjj. Kkkk llll.',
                      2: 'Aaaa bbbb. Cccc dddd. Eeee ffff.',
                    })
                    ..pageTimings.addAll({
                      1: const SentenceTimings(
                        startsMs: [0, 8000, 9000],
                        totalMs: 10000,
                      ),
                    });
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(w4Book.title).first);
        await tester.pumpAndSettle();

        // Hold the page-1 preparation and press play -> it stays in preparing.
        // Do NOT use pumpAndSettle: the preparing spinner is a continuous animation.
        fake.gatePrepare(1, force: false);
        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pump();
        await tester.pump();

        // Switch to page 2 WHILE the preparation is IN FLIGHT (suspend -> paused ->
        // ready; the page change nulls _pageTimings/_lastPreparedAudioPath).
        await tester.tap(find.byKey(const Key('page-next')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Page 2'), findsWidgets);

        // Play page 2: the preparation resolves immediately, there is NO sidecar
        // (null) -> the correct behavior is the length-weighted fallback.
        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.pause), findsWidgets);

        // NOW the stale page-1 preparation resolves LATE. Without the fix, the
        // mounted-only setState writes page 1's path+T1 WHILE PAGE 2 IS PLAYING (in
        // the playing phase the late PrepareSucceeded is absorbed by the machine --
        // the contamination is only in the fields, exactly the F1 concern).
        fake.releasePrepare(1, force: false);
        await tester.pumpAndSettle();

        createdOps.single
          ..fakeDuration = const Duration(seconds: 10)
          ..fakePosition = const Duration(milliseconds: 8500);
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          isHighlighted(tester, 'Eeee ffff.'),
          isTrue,
          reason:
              'page 2 has NO sidecar -> the fallback must highlight the LAST sentence '
              '(8500 >= 6667). If the stale page-1 T1 leaked, 8500 falls into '
              '[8000,9000) -> the MIDDLE sentence is highlighted -> RED '
              '(F1 generation guard missing).',
        );
        expect(
          isHighlighted(tester, 'Cccc dddd.'),
          isFalse,
          reason:
              'a MIDDLE-sentence highlight is proof that the stale page-1 sidecar was '
              'consumed (the late preparation was written to the new page) -> RED',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      't28: switching to page 2 while the speed-change FORCE re-preparation is IN '
      'FLIGHT -- the late force result must NOT let the OLD page timing be CONSUMED '
      'by the NEW page (F2; the speed-chip version of t27, RED without the fix)',
      (tester) async {
        final createdOps = <RecordingAudioOps>[];
        final svc = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks([w4Book]),
          },
          createdOps: createdOps,
        );
        late GatedTimingFakePagePipeline fake;
        await tester.pumpWidget(
          buildReaderTestShell(
            services: svc,
            pipelineFactory: (book) {
              return fake =
                  GatedTimingFakePagePipeline(
                      store: svc.cache,
                      bookHash: book.hash,
                    )
                    ..pageText.addAll({
                      1: 'Gggg hhhh. Iiii jjjj. Kkkk llll.',
                      2: 'Aaaa bbbb. Cccc dddd. Eeee ffff.',
                    })
                    ..pageTimings.addAll({
                      1: const SentenceTimings(
                        startsMs: [0, 8000, 9000],
                        totalMs: 10000,
                      ),
                    });
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(w4Book.title).first);
        await tester.pumpAndSettle();

        // Play page 1 NORMALLY (no gate): playing; _pageTimings=T1 is legitimate.
        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.pause), findsWidgets);

        // Hold the speed-change force re-preparation and tap the chip (only the
        // force:true signature is held; the phase stays playing, no spinner).
        fake.gatePrepare(1, force: true);
        await tester.tap(find.text('1×'));
        await tester.pump();

        // Switch to page 2 while the force is IN FLIGHT; then play page 2 (no
        // sidecar -> the fallback is the correct behavior).
        await tester.tap(find.byKey(const Key('page-next')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Page 2'), findsWidgets);
        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.pause), findsWidgets);

        // The stale force result resolves LATE: without the fix, the .then path
        // writes page 1's path+T1 WHILE PAGE 2 IS PLAYING (F2).
        fake.releasePrepare(1, force: true);
        await tester.pumpAndSettle();

        createdOps.single
          ..fakeDuration = const Duration(seconds: 10)
          ..fakePosition = const Duration(milliseconds: 8500);
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          isHighlighted(tester, 'Eeee ffff.'),
          isTrue,
          reason:
              'page 2 fallback must highlight the LAST sentence; if the stale force '
              'result (page-1 T1) leaked, it moves to the MIDDLE sentence -> RED (F2 '
              'generation guard missing).',
        );
        expect(
          isHighlighted(tester, 'Cccc dddd.'),
          isFalse,
          reason:
              'a MIDDLE-sentence highlight is proof that the stale force result was '
              'written to the new page -> RED',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    // ===== Bug-F candidate: stale PrepareSucceeded phase-switch window =====
    // _executePrepareAudio (F1 itself) dispatches PrepareSucceeded WITHOUT a token
    // (see the reader_screen.dart comment: a stale PrepareSucceeded is already
    // absorbed by the machine through the phase bookkeeping of
    // _suspendForNavigation; the token only prevents FIELD contamination). This
    // assumption BREAKS when preparing is re-entered in the SAME phase for a
    // different page/generation: reader_machine.dart transition() looks only at the
    // PHASE (phase == preparing) and does not know which page/generation it is for.
    //
    // Setup: page 1 preparation (gen=1) held in flight while jumping to page 2
    // (suspend -> paused -> ready, gen=2). Re-enter preparing for page 2 with Toggle
    // (gen=3, also held). NOW the OLD page-1 preparation (gen=1) resolves LATE: the
    // field guard (gen==_prepareGeneration) works (path/timings are NOT written),
    // but the unguarded _dispatch(PrepareSucceeded()) is ACCEPTED because the phase
    // is preparing (expected for page 2, gen=3). The machine moves to playing early
    // while _lastPreparedAudioPath is STILL null (page 2's real preparation gen=3
    // has not finished). _executePlayAudio is a silent no-op when path==null, so
    // play() is NEVER called, yet the phase stays "playing" (pause icon). When page
    // 2's real preparation (gen=3) finishes later, the fields are written but the
    // phase is ALREADY playing, so the second PrepareSucceeded is absorbed ->
    // _executePlayAudio is NEVER called again -> the audio SILENTLY never plays
    // (the user sees the pause icon, with no sound).
    testWidgets('Bug-F: if page 2 is entered and preparing is RE-ENTERED while the page-1 '
        'preparation is in flight, the LATE stale page-1 PrepareSucceeded cannot switch '
        'page 2 preparing phase to playing EARLY (without the fix: the pause icon shows '
        'without play() ever being called -> RED)', (tester) async {
      final createdOps = <RecordingAudioOps>[];
      final svc = await buildTestServices(
        prefsValues: {
          'books_v1': encodeBooks([w4Book]),
        },
        createdOps: createdOps,
      );
      late GatedTimingFakePagePipeline fake;
      await tester.pumpWidget(
        buildReaderTestShell(
          services: svc,
          pipelineFactory: (book) {
            return fake = GatedTimingFakePagePipeline(
              store: svc.cache,
              bookHash: book.hash,
            )..pageText.addAll({1: 'Bir iki.', 2: 'Uc dort.'});
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(w4Book.title).first);
      await tester.pumpAndSettle();

      // Hold the page-1 preparation and press play -> it stays in preparing
      // (gen=1 in flight). Do NOT use pumpAndSettle: the preparing spinner is a
      // continuous animation.
      fake.gatePrepare(1, force: false);
      await tester.tap(find.byIcon(Icons.play_arrow).first);
      await tester.pump();
      await tester.pump();

      // Switch to page 2 while the preparation (gen=1) is IN FLIGHT (suspend ->
      // paused -> ready; _navigateToPage ends in the ready phase and
      // _prepareGeneration increments (gen=2, unused -- nobody has started a
      // preparation yet)).
      await tester.tap(find.byKey(const Key('page-next')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Page 2'), findsWidgets);

      // Re-enter preparing for page 2 (gen=3) -- hold it too, so that the
      // "same phase (preparing), different page/generation" window stays open.
      fake.gatePrepare(2, force: false);
      await tester.tap(find.byIcon(Icons.play_arrow).first);
      await tester.pump();
      await tester.pump();

      final playCallsBefore = createdOps.isEmpty
          ? 0
          : createdOps.map((o) => o.playCalls).reduce((a, b) => a + b);

      // NOW the stale page-1 preparation (gen=1) resolves LATE. The field guard
      // works (path/timings are NOT written to page 2), but the unguarded dispatch
      // is ACCEPTED because the phase is preparing -> the machine moves to playing
      // early.
      fake.releasePrepare(1, force: false);
      await tester.pump();
      await tester.pump();

      final playCallsAfterStalePrepare = createdOps.isEmpty
          ? 0
          : createdOps.map((o) => o.playCalls).reduce((a, b) => a + b);

      expect(
        find.byIcon(Icons.pause),
        findsNothing,
        reason:
            'the stale page-1 PrepareSucceeded must NOT switch page 2 preparing '
            'phase to playing EARLY (page 2 REAL preparation gen=3 has not finished) '
            '-> without the fix the pause icon shows early -> RED (residual '
            'phase-switch window).',
      );
      expect(
        playCallsAfterStalePrepare,
        equals(playCallsBefore),
        reason:
            'if the phase switched to playing early, _executePlayAudio does NOT '
            'call play() because _lastPreparedAudioPath==null -- this is the proof '
            'of the silent breakage: "pause icon but no sound at all" (without the '
            'fix playCalls stay unchanged while the phase shows playing).',
      );

      // Cleanup: release the held page-2 preparation (so no pending Future is
      // left hanging during dispose).
      fake.releasePrepare(2, force: false);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // ===== A3: resume from the in-page audio position (continue where you left off) =====
    // FIELD FINDING: the page number (progress_<hash>) was remembered, but the audio
    // position INSIDE the page was never saved -- even after quitting and reopening
    // the app, and even on pause->resume, playFile always reloaded the clip from the
    // START. Fix: on pause/suspend, "audiopos_<hash>" = "page:ms" is written to
    // prefs; on the same page and above the threshold (3s), resume starts with
    // playFile(startAt: saved). AudioCompleted or a switch to another page clears it.
    group('A3: resume from the in-page audio position', () {
      testWidgets('A3-t1: pausing while playing writes the current page+position to '
          'prefs as "audiopos_<hash>"', (tester) async {
        final createdOps = <RecordingAudioOps>[];
        final svc = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks([w4Book]),
          },
          createdOps: createdOps,
        );
        final fake = await openW4Book(tester, services: svc);

        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();
        expect(fake.prepareAudioCalls.map((c) => c.page), contains(1));
        expect(createdOps, isNotEmpty);

        // The player reports the REAL position: 9500ms (above the 3s threshold).
        createdOps.single.fakePosition = const Duration(milliseconds: 9500);
        // One fake pump is enough for the periodic tick to read the position (t25 idiom).
        await tester.pump(const Duration(milliseconds: 300));

        await tester.tap(find.byIcon(Icons.pause).first);
        await tester.pumpAndSettle();

        expect(
          svc.prefs.getString('audiopos_${w4Book.hash}'),
          '1:9500',
          reason:
              'pausing must write the current page+position to the "audiopos_<hash>" '
              'key as "page:ms" (RED: today it is never written)',
        );
      });

      testWidgets(
        'A3-t2: after a cold restart, pressing play on the SAME page resumes from '
        'the saved position (playFile is CALLED with startAt=saved)',
        (tester) async {
          final createdOps1 = <RecordingAudioOps>[];
          final svc = await buildTestServices(
            prefsValues: {
              'books_v1': encodeBooks([w4Book]),
            },
            createdOps: createdOps1,
          );
          await openW4Book(tester, services: svc);

          await tester.tap(find.byIcon(Icons.play_arrow).first);
          await tester.pumpAndSettle();
          createdOps1.single.fakePosition = const Duration(milliseconds: 15750);
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.byIcon(Icons.pause).first);
          await tester.pumpAndSettle();
          expect(svc.prefs.getString('audiopos_${w4Book.hash}'), '1:15750');

          // Cold-restart simulation: a NEW AppServices + widget tree on the SAME prefs
          // mock backing (restartTestServices pattern, W1 oracle).
          final createdOps2 = <RecordingAudioOps>[];
          final restarted = await restartTestServices(
            svc,
            createdOps: createdOps2,
          );
          late FakePagePipeline fakeAfterRestart;
          await tester.pumpWidget(
            buildReaderTestShell(
              // Force a NEW AppShell state: without a key, pumpWidget would KEEP the old
              // AppShell's State (including the 'reader' tab/pipeline from the previous
              // test). Element.canUpdate treats a same-type, null-key widget as an
              // update, which would BREAK the restart SIMULATION (a real restart on the
              // device has no such "old state").
              shellKey: UniqueKey(),
              services: restarted,
              pipelineFactory: (book) {
                return fakeAfterRestart = FakePagePipeline(
                  store: restarted.cache,
                  bookHash: book.hash,
                );
              },
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text(w4Book.title).first);
          await tester.pumpAndSettle();
          // After the restart progress_<hash> is restored, so the opening page is 1.
          expect(find.textContaining('Page 1'), findsWidgets);

          await tester.tap(find.byIcon(Icons.play_arrow).first);
          await tester.pumpAndSettle();

          expect(
            fakeAfterRestart.prepareAudioCalls.map((c) => c.page),
            contains(1),
          );
          expect(createdOps2, isNotEmpty);
          expect(
            createdOps2.single.loadedInitialPositions,
            contains(const Duration(milliseconds: 15750)),
            reason:
                'after a cold restart, resuming on the same page must start from the '
                'saved position (RED: today playFile is always called with startAt=null '
                'and the clip reloads from the START)',
          );
        },
      );

      testWidgets(
        'A3-t3: the record is cleared when the page COMPLETES (AudioCompleted)',
        (tester) async {
          const lastPageBook = Book(
            id: 'a3-last',
            title: 'A3 Last Page Book',
            author: 'T. Test',
            chapterLabel: 'Last',
            progressPercent: 0,
            totalPages: 1,
            coverIndex: 0,
            hash: 'a3hashlast',
            filePath: '/tmp/a3/last.pdf',
          );
          final createdOps = <RecordingAudioOps>[];
          final svc = await buildTestServices(
            prefsValues: {
              'books_v1': encodeBooks([lastPageBook]),
            },
            createdOps: createdOps,
          );
          await tester.pumpWidget(
            buildReaderTestShell(
              services: svc,
              pipelineFactory: (book) {
                return FakePagePipeline(store: svc.cache, bookHash: book.hash);
              },
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text(lastPageBook.title).first);
          await tester.pumpAndSettle();

          await tester.tap(find.byIcon(Icons.play_arrow).first);
          await tester.pumpAndSettle();
          createdOps.single.fakePosition = const Duration(seconds: 20);
          await tester.pump(const Duration(milliseconds: 300));
          // Pause -> the record is written (precondition).
          await tester.tap(find.byIcon(Icons.pause).first);
          await tester.pumpAndSettle();
          expect(
            svc.prefs.getString('audiopos_${lastPageBook.hash}'),
            isNotNull,
            reason: 'precondition: the pause must have written the record',
          );

          // Resume and simulate the natural end (AudioCompleted -> finished).
          await tester.tap(find.byIcon(Icons.play_arrow).first);
          await tester.pumpAndSettle();
          createdOps.single.completeCurrentPlay();
          await tester.pumpAndSettle();

          expect(
            svc.prefs.getString('audiopos_${lastPageBook.hash}'),
            isNull,
            reason:
                'when the page ends naturally (AudioCompleted) the record must be '
                'cleared (RED: today there is no record at all, so this test is only '
                'meaningful once A3-t1 is implemented)',
          );
        },
      );

      testWidgets(
        'A3-t4: when going to a DIFFERENT page, the old page record is not used '
        '(the new page plays FROM THE START)',
        (tester) async {
          final createdOps = <RecordingAudioOps>[];
          final svc = await buildTestServices(
            prefsValues: {
              'books_v1': encodeBooks([w4Book]),
            },
            createdOps: createdOps,
          );
          final fake = await openW4Book(
            tester,
            services: svc,
            pageText: {2: 'SecondPageText.'},
          );

          // Play and pause on page 1 -> the record is written.
          await tester.tap(find.byIcon(Icons.play_arrow).first);
          await tester.pumpAndSettle();
          createdOps.single.fakePosition = const Duration(seconds: 12);
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.byIcon(Icons.pause).first);
          await tester.pumpAndSettle();
          expect(svc.prefs.getString('audiopos_${w4Book.hash}'), '1:12000');

          // Go to page 2 and play.
          await tester.tap(find.byKey(const Key('page-next')));
          await tester.pumpAndSettle();
          expect(find.textContaining('Page 2'), findsWidgets);
          await tester.tap(find.byIcon(Icons.play_arrow).first);
          await tester.pumpAndSettle();

          expect(
            fake.prepareAudioCalls.map((c) => c.page),
            contains(2),
            reason: 'page 2 must have been prepared and played',
          );
          final lastIdx = createdOps.single.loadedPaths.length - 1;
          expect(
            createdOps.single.loadedInitialPositions[lastIdx],
            anyOf(isNull, Duration.zero),
            reason:
                'when moving to a DIFFERENT page (2), the OLD page (1) record must NOT '
                'be used -- the new page must play FROM THE START (before the RED: there '
                'is no record/consumption yet, so this test must pass definitively AFTER '
                'the fix)',
          );
        },
      );
    }); // A3 grup sonu
  }); // FAZ-W4 group end (A3 was moved here -- w4Book/openW4Book scope)

  // Bug-H (2026-07-04, device finding): when the phone is rotated to landscape,
  // a "bottom overflowed by 51 pixels" error appears. Root cause, proven with a
  // widget test + FlutterError capture: _buildPageNotReady (reader_screen.dart:560)
  // asks its Column for a natural height larger than what Expanded can leave in the
  // short (landscape) viewport (e.g. 37.7px) -> RenderFlex overflow. This group pins
  // the overflow in the UNFIXED state (tester.takeException() is FILLED); after the
  // fix it MUST be null.
  group(
    'Bug-H: reader "This page has not been prepared yet" placeholder does not overflow in landscape',
    () {
      const hBook = Book(
        id: 'bugh-1',
        title: 'Landscape Test Book',
        author: 'T. Test',
        chapterLabel: 'Chapter 1',
        progressPercent: 0,
        totalPages: 5,
        coverIndex: 0,
        hash: 'bughash000001',
        filePath: '/tmp/bugh/does-not-matter.pdf',
      );

      testWidgets(
        'landscape (short) viewport + a page whose text is not produced yet -> there '
        'must be NO RenderFlex overflow (today the _buildPageNotReady Column overflows)',
        (tester) async {
          tester.view.physicalSize = const Size(2628, 1224);
          tester.view.devicePixelRatio = 3.5;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final svc = await buildTestServices(
            prefsValues: {
              'books_v1': encodeBooks([hBook]),
            },
          );
          await tester.pumpWidget(
            buildReaderTestShell(
              services: svc,
              // pageText is left EMPTY -> page 1 is a cache miss -> the _pageNotReady
              // placeholder is shown (the exact spot of Bug-H).
              pipelineFactory: (book) =>
                  FakePagePipeline(store: svc.cache, bookHash: book.hash),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text(hBook.title).first);
          await tester.pumpAndSettle();

          expect(
            find.textContaining('This page has not been prepared yet'),
            findsWidgets,
            reason: 'precondition: the placeholder must really be visible',
          );
          expect(
            tester.takeException(),
            isNull,
            reason:
                'in landscape mode the "This page has not been prepared yet" placeholder must '
                'NOT overflow with a RenderFlex (device finding: "bottom overflowed '
                'by 51 pixels")',
          );
        },
      );
    },
  );

  // Bug-I (2026-07-04, FAZ-3 acceptance-round finding): karaoke highlighting
  // follows the REAL audio position correctly (_sentenceIndex = narratingIndexAt(...),
  // always clamped within range -- see sentence_timing.dart:155), BUT the body
  // SingleChildScrollView never uses a ScrollController or ensureVisible. On a long
  // page (19-24 sentences) the highlighted sentence drops BELOW THE FOLD as the
  // audio advances and is no longer visible. This group starts playback on a
  // multi-sentence page, drives narratingIndex (via sidecar timing) to a distant
  // sentence (idx 15), and verifies that the scroll offset changes from 0 and the
  // sentence comes into the visible area. Without the fix there is no auto-scroll,
  // the offset stays 0 -> RED.
  group('Bug-I: reader auto-scrolls to the highlighted sentence', () {
    const iBook = Book(
      id: 'bugi-1',
      title: 'Long Page Book',
      author: 'T. Test',
      chapterLabel: 'Chapter 1',
      progressPercent: 0,
      totalPages: 1,
      coverIndex: 0,
      hash: 'bugihash000001',
      filePath: '/tmp/bugi/does-not-matter.pdf',
    );

    // 24 short sentences: enough to wrap and overflow in the narrow test viewport
    // (800x600 default), so the ScrollView is scrollable.
    String buildManySentences(int count) =>
        List.generate(count, (i) => 'Cumle ${i + 1}.').join(' ');

    testWidgets(
      'while playing, when narratingIndex advances to a distant sentence '
      '(idx 15) the body is AUTO-SCROLLED (scroll offset changes from 0)',
      (tester) async {
        final createdOps = <RecordingAudioOps>[];
        final svc = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks([iBook]),
          },
          createdOps: createdOps,
        );
        late TimingFakePagePipeline fake;
        await tester.pumpWidget(
          buildReaderTestShell(
            services: svc,
            pipelineFactory: (book) {
              return fake =
                  TimingFakePagePipeline(store: svc.cache, bookHash: book.hash)
                    ..pageText[1] = buildManySentences(24)
                    ..pageTimings[1] = const SentenceTimings(
                      startsMs: [
                        0,
                        1000,
                        2000,
                        3000,
                        4000,
                        5000,
                        6000,
                        7000,
                        8000,
                        9000,
                        10000,
                        11000,
                        12000,
                        13000,
                        14000,
                        15000,
                        16000,
                        17000,
                        18000,
                        19000,
                        20000,
                        21000,
                        22000,
                        23000,
                      ],
                      totalMs: 24000,
                    );
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(iBook.title).first);
        await tester.pumpAndSettle();

        expect(find.byType(Scrollable), findsWidgets);
        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        expect(
          scrollable.position.pixels,
          0,
          reason:
              'precondition: the scroll must be at the top when the page opens',
        );

        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();
        expect(fake.prepareAudioCalls.map((c) => c.page), contains(1));
        expect(createdOps, isNotEmpty);

        // Move the position into the idx 15 range (15000ms); fire the periodic timer
        // (250ms) on the fake clock -- t25 idiom (currentPosition is a fake position,
        // not the wall clock, so a fake pump is enough).
        createdOps.single
          ..fakeDuration = const Duration(seconds: 24)
          ..fakePosition = const Duration(milliseconds: 15500);
        await tester.pump(const Duration(milliseconds: 300));
        // Auto-scroll (if any) is triggered by a postFrameCallback + animation;
        // pumpAndSettle is needed for the animation to COMPLETE (a single pump(300ms)
        // only covers the trigger, not the animation itself).
        await tester.pumpAndSettle();

        expect(
          find.text('Cumle 16.'),
          findsOneWidget,
          reason:
              'precondition: idx 15 (Cumle 16.) must be rendered in the body',
        );

        final offsetAfterHighlightMove = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels;
        expect(
          offsetAfterHighlightMove,
          greaterThan(0),
          reason:
              'when the highlighted sentence (idx 15) advances to a distant sentence '
              'the body must AUTO-SCROLL (without auto-scroll the offset stays 0 -> '
              'RED; field finding: on a long page the highlight dropped below the fold '
              'and was NOT visible)',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    // Bug-I regression (adversarial-review #69, verified experimentally): if two
    // consecutive pages have the SAME sentence count (24), _sentenceKeysLength does
    // NOT change -> _keysFor does not reset the auto-scroll suppression guard
    // (_lastAutoScrolledIndex) -> after scrolling to idx 15 on page 1, the scroll for
    // the highlight moving to idx 15 again on page 2 is SILENTLY suppressed (by the
    // guard's _lastAutoScrolledIndex==15 equality). This is the page-transition variant
    // of the problem the fix solved. Fix: when the page/content changes,
    // _lastAutoScrolledIndex is reset to null. Without the fix: RED (page 2 offset
    // stays 0); with the fix: GREEN.
    const iBook2 = Book(
      id: 'bugi-2',
      title: 'Two Page Book',
      author: 'T. Test',
      chapterLabel: 'Chapter 1',
      progressPercent: 0,
      totalPages: 2,
      coverIndex: 0,
      hash: 'bugihash000002',
      filePath: '/tmp/bugi/two-pages.pdf',
    );

    // Same startsMs/totalMs as page 1 -> same sentence count (24) + same timing;
    // _sentenceKeysLength does not change, so the guard stays stale (without the fix).
    const sameTimings = SentenceTimings(
      startsMs: [
        0,
        1000,
        2000,
        3000,
        4000,
        5000,
        6000,
        7000,
        8000,
        9000,
        10000,
        11000,
        12000,
        13000,
        14000,
        15000,
        16000,
        17000,
        18000,
        19000,
        20000,
        21000,
        22000,
        23000,
      ],
      totalMs: 24000,
    );

    testWidgets(
      'SAME sentence count (24) on both pages: auto-scroll works on both pages -- '
      'page 1 idx 15 -> page 2 idx 15 the body is scrolled too (_lastAutoScrolledIndex '
      'must not stay stale across a page change -> RED regression)',
      (tester) async {
        final createdOps = <RecordingAudioOps>[];
        final svc = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks([iBook2]),
          },
          createdOps: createdOps,
        );
        late TimingFakePagePipeline fake;
        await tester.pumpWidget(
          buildReaderTestShell(
            services: svc,
            pipelineFactory: (book) {
              return fake =
                  TimingFakePagePipeline(store: svc.cache, bookHash: book.hash)
                    ..pageText[1] = buildManySentences(24)
                    ..pageText[2] = buildManySentences(24)
                    ..pageTimings[1] = sameTimings
                    ..pageTimings[2] = sameTimings;
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(iBook2.title).first);
        await tester.pumpAndSettle();

        // --- PAGE 1: scroll to idx 15 (existing behavior, precondition) ---
        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();
        expect(fake.prepareAudioCalls.map((c) => c.page), contains(1));
        expect(createdOps, isNotEmpty);

        createdOps.single
          ..fakeDuration = const Duration(seconds: 24)
          ..fakePosition = const Duration(milliseconds: 15500);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        final page1Scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        expect(
          page1Scrollable.position.pixels,
          greaterThan(0),
          reason:
              'precondition: the idx 15 auto-scroll must have run on page 1',
        );

        // --- Go to PAGE 2 (forward while playing: synchronous suspend first) ---
        await tester.tap(find.byKey(const Key('page-next')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Page 2'), findsWidgets);

        // Play page 2 from the start; then manually bring the scroll to the top (after
        // a page change the offset may be preserved -- to GUARANTEE that the test needs
        // a fresh scroll to idx 15, jumpTo 0).
        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();
        expect(
          fake.prepareAudioCalls.map((c) => c.page),
          contains(2),
          reason: 'precondition: page 2 must have been prepared and played',
        );

        final page2Scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        page2Scrollable.position.jumpTo(0);
        await tester.pump();
        expect(
          page2Scrollable.position.pixels,
          0,
          reason:
              'precondition: the page 2 scroll was manually brought to the top',
        );

        // --- PAGE 2: advance to idx 15 again ---
        createdOps.last
          ..fakeDuration = const Duration(seconds: 24)
          ..fakePosition = const Duration(milliseconds: 15500);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .pixels,
          greaterThan(0),
          reason:
              'on page 2 too, the body must AUTO-SCROLL for the highlight advancing to '
              'idx 15. Without the fix: _lastAutoScrolledIndex stays stale at 15 across '
              'the page change -> the guard SILENTLY suppresses the scroll -> offset '
              'stays 0 -> RED (page-transition regression)',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Ask extension: onLongPress wiring (adversarial-review finding)', () {
    const askBook = Book(
      id: 'ask-1',
      title: 'Ask Book',
      author: 'T. Test',
      chapterLabel: 'Chapter 1',
      progressPercent: 0,
      totalPages: 3,
      coverIndex: 0,
      hash: 'askhash00001',
      filePath: '/tmp/ask/does-not-matter.pdf',
    );

    Future<FakePagePipeline> openAskBook(
      WidgetTester tester, {
      required AppServices services,
    }) async {
      late FakePagePipeline fake;
      await tester.pumpWidget(
        buildReaderTestShell(
          services: services,
          pipelineFactory: (book) {
            return fake = FakePagePipeline(
              store: services.cache,
              bookHash: book.hash,
            )..pageText.addAll({1: 'This is a test sentence.'});
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(askBook.title).first);
      await tester.pumpAndSettle();
      return fake;
    }

    testWidgets(
      'adversarial-review finding 2: long-press on a sentence while the Gemini key '
      'is EMPTY -- a friendly SnackBar is shown AND the playing audio is NOT paused '
      '(the key check must come BEFORE the suspend call; if the sheet will not open '
      'anyway, it must not interrupt the audio needlessly)',
      (tester) async {
        final svc = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks([askBook]),
          },
        );
        // geminiKey is deliberately left EMPTY (ReadingSettings default).
        await openAskBook(tester, services: svc);

        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();
        expect(
          find.byIcon(Icons.pause),
          findsWidgets,
          reason: 'precondition: the page must have started playing',
        );

        await tester.longPress(find.text('This is a test sentence.'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('A Gemini API key is required'),
          findsOneWidget,
          reason: 'if the key is empty, a friendly SnackBar must be shown',
        );
        expect(
          find.byIcon(Icons.pause),
          findsWidgets,
          reason:
              'BEFORE THE FIX: _suspendForNavigation ran BEFORE the key check -> with an '
              'empty key (the sheet would not open anyway) the audio was needlessly '
              'paused (it went back to the play icon). The key check must come FIRST -- '
              'if the sheet will not open, the audio must stay UNTOUCHED.',
        );
      },
    );
  });
  // Early Play press: if the center Play is pressed before AppShell._buildPipelineAsync
  // (file read + isolate) finishes, the press used to be SILENTLY swallowed (on a
  // slow phone: "I press it, it does not play"). Expected: visible feedback (SnackBar)
  // and the press is QUEUED; once the pipeline arrives it runs exactly once.
  group('Early Play press (pipeline not set up yet)', () {
    const queueBook = Book(
      id: 'q-1',
      title: 'Queue Book',
      author: 'T. Test',
      chapterLabel: 'Chapter 1',
      progressPercent: 0,
      totalPages: 5,
      coverIndex: 0,
      hash: 'queuehash001',
      filePath: '/tmp/q/does-not-matter.pdf',
    );
    const otherBook = Book(
      id: 'q-2',
      title: 'Other Book',
      author: 'T. Test',
      chapterLabel: 'Chapter 1',
      progressPercent: 0,
      totalPages: 5,
      coverIndex: 0,
      hash: 'queuehash002',
      filePath: '/tmp/q/other.pdf',
    );
    const preparingMsg =
        'Book is being prepared… playback will start once it is ready.';
    const cancelledMsg = 'Playback request cancelled';
    const failedMsg = 'The book could not be prepared. Please reopen the book.';

    /// Builds ReaderScreen directly, without AppShell. Calling it again with the same
    /// [settings] updates the pumpWidget tree IN PLACE (didUpdateWidget) -- it mimics
    /// the AppShell "pipeline arrives later" setState exactly.
    Widget app(
      AppServices services,
      AppSettings settings,
      Book? book,
      PagePipeline? pipeline, {
      bool pipelineFailed = false,
    }) => AppServicesScope(
      services: services,
      child: AppSettingsScope(
        settings: settings,
        child: MaterialApp(
          theme: buildAppTheme(settings),
          home: Scaffold(
            body: ReaderScreen(
              sentences: const [],
              book: book,
              pipeline: pipeline,
              pipelineFailed: pipelineFailed,
            ),
          ),
        ),
      ),
    );

    Future<
      ({AppServices svc, AppSettings settings, List<RecordingAudioOps> ops})
    >
    setUpEarly(WidgetTester tester) async {
      useFakeClockReaderStopwatch(tester);
      final ops = <RecordingAudioOps>[];
      final svc = await buildTestServices(createdOps: ops);
      final settings = AppSettings();
      addTearDown(settings.dispose);
      await tester.pumpWidget(app(svc, settings, queueBook, null));
      await tester.pumpAndSettle();
      return (svc: svc, settings: settings, ops: ops);
    }

    FakePagePipeline newPipeline(AppServices svc, Book book) =>
        FakePagePipeline(store: svc.cache, bookHash: book.hash)
          ..pageText.addAll({1: 'This is a test sentence.'});

    int playCalls(List<RecordingAudioOps> ops) =>
        ops.fold(0, (a, o) => a + o.playCalls);

    testWidgets(
      'E1: with no pipeline, Play -> SnackBar is visible; when the pipeline arrives '
      'the pending request runs ONCE (PrepareAudio -> player.play)',
      (tester) async {
        final env = await setUpEarly(tester);

        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pump();
        expect(
          find.text(preparingMsg),
          findsOneWidget,
          reason: 'no silent swallowing: visible feedback must be shown',
        );
        expect(
          find.byIcon(Icons.hourglass_top),
          findsOneWidget,
          reason:
              'while queued, the center icon must show the static "waiting" state',
        );

        final fake = newPipeline(env.svc, queueBook);
        await tester.pumpWidget(app(env.svc, env.settings, queueBook, fake));
        await tester.pumpAndSettle();

        expect(
          fake.prepareAudioCalls.map((c) => c.page),
          contains(1),
          reason:
              'when the pipeline arrives, the queued Play -> PrepareAudio(1)',
        );
        expect(playCalls(env.ops), 1, reason: 'player.play() exactly once');
        expect(find.byIcon(Icons.pause), findsWidgets);
        expect(find.byIcon(Icons.hourglass_top), findsNothing);

        // An extra rebuild (same pipeline) must NOT execute the request again.
        await tester.pumpWidget(app(env.svc, env.settings, queueBook, fake));
        await tester.pumpAndSettle();
        expect(playCalls(env.ops), 1);
      },
    );

    testWidgets(
      'E2: a second press CANCELS the queue (small SnackBar); when the pipeline '
      'arrives it does NOT play',
      (tester) async {
        final env = await setUpEarly(tester);

        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pump();
        expect(find.text(preparingMsg), findsOneWidget);
        await tester.tap(find.byIcon(Icons.hourglass_top).first);
        await tester.pump();
        expect(find.text(cancelledMsg), findsOneWidget);
        expect(find.byIcon(Icons.hourglass_top), findsNothing);
        expect(find.byIcon(Icons.play_arrow), findsWidgets);

        final fake = newPipeline(env.svc, queueBook);
        await tester.pumpWidget(app(env.svc, env.settings, queueBook, fake));
        await tester.pumpAndSettle();

        expect(fake.prepareAudioCalls, isEmpty);
        expect(playCalls(env.ops), 0);
        expect(find.byIcon(Icons.pause), findsNothing);
      },
    );

    testWidgets(
      'E3: if the book changes, the queue is cleared (the new book does NOT play '
      'by itself)',
      (tester) async {
        final env = await setUpEarly(tester);

        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pump();
        expect(find.byIcon(Icons.hourglass_top), findsOneWidget);

        final fake = newPipeline(env.svc, otherBook);
        await tester.pumpWidget(app(env.svc, env.settings, otherBook, fake));
        await tester.pumpAndSettle();

        expect(fake.prepareAudioCalls, isEmpty);
        expect(playCalls(env.ops), 0);
        expect(find.byIcon(Icons.pause), findsNothing);
        expect(find.byIcon(Icons.hourglass_top), findsNothing);
      },
    );

    testWidgets(
      'E4: if the pipeline NEVER arrives the screen does not lock: pumpAndSettle '
      "finishes, the icon stays a static 'waiting', the Semantics label 'Play' is kept",
      (tester) async {
        final semantics = tester.ensureSemantics();
        // addTearDown runs AFTER the end-of-test verification (if the handle is still
        // open at that point it raises a "SemanticsHandle was active" error); so on the
        // normal path it is disposed at the end, and addTearDown is only a safety net
        // for an early exit (a failed expect).
        var semanticsDisposed = false;
        addTearDown(() {
          if (!semanticsDisposed) semantics.dispose();
        });
        await setUpEarly(tester);

        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester
            .pumpAndSettle(); // times out if there is an infinite animation
        expect(find.text(preparingMsg), findsNothing); // SnackBar closed
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
        expect(find.bySemanticsLabel('Play'), findsOneWidget);
        semanticsDisposed = true;
        semantics.dispose();
      },
    );

    testWidgets(
      'E5: if the widget is disposed while queued, it is cleaned up silently '
      '(nothing runs afterwards, no error)',
      (tester) async {
        final env = await setUpEarly(tester);
        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pump();

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(playCalls(env.ops), 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'E7: if the pipeline preparation FAILS, the queue is dropped, no hourglass '
      'remains, and a visible error message appears; it does NOT play even if the '
      'pipeline arrives later',
      (tester) async {
        final env = await setUpEarly(tester);

        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pump();
        expect(find.byIcon(Icons.hourglass_top), findsOneWidget);

        await tester.pumpWidget(
          app(env.svc, env.settings, queueBook, null, pipelineFailed: true),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.text(failedMsg),
          findsOneWidget,
          reason: 'the failure must not be silent: a visible error message',
        );
        expect(find.byIcon(Icons.hourglass_top), findsNothing);
        expect(find.byIcon(Icons.play_arrow), findsWidgets);
        expect(playCalls(env.ops), 0);

        await tester.pumpAndSettle();
        final fake = newPipeline(env.svc, queueBook);
        await tester.pumpWidget(app(env.svc, env.settings, queueBook, fake));
        await tester.pumpAndSettle();
        expect(
          fake.prepareAudioCalls,
          isEmpty,
          reason: 'the queue had been dropped',
        );
        expect(playCalls(env.ops), 0);
        expect(find.byIcon(Icons.hourglass_top), findsNothing);
      },
    );

    testWidgets(
      "E8: when the pipeline is ready, the 'preparing' SnackBar CLOSES and the "
      'queued play runs',
      (tester) async {
        final env = await setUpEarly(tester);

        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pump();
        expect(find.text(preparingMsg), findsOneWidget);

        final fake = newPipeline(env.svc, queueBook);
        await tester.pumpWidget(app(env.svc, env.settings, queueBook, fake));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          find.text(preparingMsg),
          findsNothing,
          reason:
              'pipeline ready -> the "preparing" message is no longer correct and must close',
        );
        await tester.pumpAndSettle();
        expect(playCalls(env.ops), 1, reason: 'the queued play still runs');
        expect(find.byIcon(Icons.pause), findsWidgets);
      },
    );

    testWidgets(
      'E6: when the pipeline is ALREADY READY, a normal press is unchanged (no '
      'SnackBar, directly PrepareAudio + play)',
      (tester) async {
        useFakeClockReaderStopwatch(tester);
        final ops = <RecordingAudioOps>[];
        final svc = await buildTestServices(createdOps: ops);
        final settings = AppSettings();
        addTearDown(settings.dispose);
        final fake = newPipeline(svc, queueBook);
        await tester.pumpWidget(app(svc, settings, queueBook, fake));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.play_arrow).first);
        await tester.pumpAndSettle();

        expect(find.text(preparingMsg), findsNothing);
        expect(fake.prepareAudioCalls.map((c) => c.page), contains(1));
        expect(playCalls(ops), 1);
        expect(find.byIcon(Icons.pause), findsWidgets);
      },
    );
  });
}
