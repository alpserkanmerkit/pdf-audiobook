// FLOW 4: resume where you left off. The app is CLOSED and REOPENED with the same
// prefs store + same dataDir (SharedPreferences.resetStatic -> new AppServices -> new widget tree):
// only what is persistent comes back:
//  (a) reader: in-page audio position + page number + library percentage +
//      the audio cache on disk (the same page is not synthesized again)
//  (b) tutor lesson: resume offer -> "Continue where you left off" -> saved part
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/tutor/tutor_prompts.dart'
    show kTutorSystemPrompt;

import '../support/e2e_actions.dart';
import '../support/e2e_world.dart';

String _textOf(WidgetTester tester, String key) =>
    (tester.widget(find.byKey(Key(key))) as Text).data!;

void resumeFlow() {
  testWidgets('flow 4a: reader -- after close/reopen, page + audio position '
      'and audio cache are kept', (tester) async {
    final world = await E2eWorld.create(
      prefs: onboardedPrefs({
        'provider': 'google',
        'googleKey': 'test-key-google',
      }),
    );
    addTearDown(world.dispose);
    await world.launch(tester);
    await addBookViaUi(tester, startReading: true);
    final book = singleBook(world);

    // Play page 1, pause at second 12.
    await tapPlay(tester);
    await pumpUntil(
      tester,
      () => world.ops.isNotEmpty && world.ops.first.playCalls >= 1,
      reason: 'playback did not start in the first session',
    );
    world.ops.first.fakePosition = const Duration(seconds: 12);
    await tester.pump(const Duration(milliseconds: 600)); // position tick
    await tapPause(tester);
    await pumpUntil(
      tester,
      () => world.services.prefs.getString('audiopos_${book.hash}') != null,
      reason: 'audiopos was not saved on pause',
    );
    expect(world.services.prefs.getString('audiopos_${book.hash}'), '1:12000');
    final page1Synth = world.server.ttsRequests
        .where((r) => r.ttsText.contains(kPage1Marker))
        .length;
    expect(page1Synth, greaterThanOrEqualTo(1));

    // CLOSE -> REOPEN.
    await world.launch(tester);
    expect(world.ops, hasLength(1), reason: 'new session needs new ops');
    // Library: book percentage page 1/4 = %25.
    expect(find.textContaining('%25'), findsWidgets);
    await openBookFromLibrary(tester, book);
    expect(find.text('Page 1 / 4'), findsOneWidget);

    await tapPlay(tester);
    await pumpUntil(
      tester,
      () => world.ops.length >= 2 && world.ops.last.loadedPaths.isNotEmpty,
      reason: 'player did not load the file on reopen',
    );
    expect(
      world.ops.last.loadedInitialPositions,
      contains(const Duration(seconds: 12)),
      reason: 'must resume from the saved position (12 s)',
    );
    expect(
      world.server.ttsRequests
          .where((r) => r.ttsText.contains(kPage1Marker))
          .length,
      page1Synth,
      reason: 'page 1 audio is cached on disk: must not be synthesized again',
    );

    // Go to the next page -> close/reopen -> opens at page 2.
    await tapPause(tester);
    await tester.pump(const Duration(milliseconds: 300));
    await tapFinder(tester, find.byKey(const Key('page-next')));
    await pumpUntilFound(tester, find.text('Page 2 / 4'));
    // App contract: progress is written when the page's audio STARTS playing
    // (reader_machine SaveProgress); merely turning the page does not save it.
    await tapPlay(tester);
    await pumpUntil(
      tester,
      () => world.services.prefs.getInt('progress_${book.hash}') == 2,
      reason: 'progress_ must be 2 once page 2 starts playing',
    );
    await tapPause(tester);
    await tester.pump(const Duration(milliseconds: 300));

    await world.launch(tester);
    expect(find.textContaining('%50'), findsWidgets);
    await openBookFromLibrary(tester, book);
    expect(find.text('Page 2 / 4'), findsOneWidget);

    expect(world.server.unrouted, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('flow 4b: tutor lesson -- after close/reopen, resume offer and '
      'resuming from the saved part', (tester) async {
    final world = await E2eWorld.create(
      prefs: onboardedPrefs({'geminiKey': 'test-key-gemini'}),
    );
    addTearDown(world.dispose);
    await world.launch(tester);
    await addBookViaUi(tester);
    final book = singleBook(world);

    expect(await openTutorChapter(tester, book), 'part');
    await tester.enterText(
      find.byKey(const Key('tutor-answer-0')),
      'expected answer',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tapFinder(tester, find.byKey(const Key('tutor-submit-0')));
    await pumpUntilFound(tester, find.byKey(const Key('tutor-verdict-0')));
    await tapFinder(tester, find.byKey(const Key('tutor-next')));
    await pumpUntil(
      tester,
      () =>
          find.byKey(const Key('tutor-part-header')).evaluate().isNotEmpty &&
          _textOf(tester, 'tutor-part-header').startsWith('Part 2/'),
      reason: 'part 2 did not load',
    );

    // CLOSE -> REOPEN.
    await world.launch(tester);
    final callsBefore = world.server.chatRequests.length;
    expect(await openTutorChapter(tester, book), 'resume-offer');
    final info = _textOf(tester, 'tutor-resume-info');
    expect(info, startsWith('Left off at: Part 2/'));
    expect(info, contains('Correct: 1 · Partial: 0 · Wrong: 0'));
    expect(
      world.server.chatRequests.length,
      callsBefore,
      reason: 'LLM must not be called while the offer is shown',
    );

    await tapFinder(tester, find.byKey(const Key('tutor-resume')));
    await pumpUntilFound(tester, find.byKey(const Key('tutor-part')));
    expect(_textOf(tester, 'tutor-part-header'), startsWith('Part 2/'));
    expect(_textOf(tester, 'tutor-explanation'), 'E2E explanation part 2.');
    final resumed = world.server.chatRequests
        .skip(callsBefore)
        .where((r) => r.systemMessage == kTutorSystemPrompt)
        .toList();
    expect(resumed, hasLength(1));
    expect(resumed.single.userMessage, contains('Part 2/'));

    expect(world.server.unrouted, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
