// FLOW 2: read / listen. Real book (PDF) -> Reader -> play:
// REAL PagePipeline: PDF text -> LLM cleaner (fake server, Gemini endpoint)
// -> Google TTS (fake server) -> audio file cached -> player ops.
// Audio output is fake (RecordingAudioOps): "played" = the ops got the file path
// and the file carries the bytes returned by the fake server.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/e2e_actions.dart';
import '../support/e2e_world.dart';
import '../support/fake_api_server.dart';

void readingFlow() {
  testWidgets('flow 2: read/listen -- PDF text reaches LLM and TTS with the '
      'correct key; the audio file goes to the player and the next '
      'page plays when it ends', (tester) async {
    final world = await E2eWorld.create(
      prefs: onboardedPrefs({
        'provider': 'google',
        'googleKey': 'test-key-google',
        'geminiKey': 'test-key-gemini',
      }),
    );
    addTearDown(world.dispose);
    await world.launch(tester);
    await addBookViaUi(tester, startReading: true);
    await pumpUntilFound(tester, find.byKey(const Key('page-indicator')));
    expect(find.text('Page 1 / 4'), findsOneWidget);

    await tapPlay(tester);

    // Preparation -> player: the audio file path is handed to ops and play starts.
    await pumpUntil(
      tester,
      () => world.ops.isNotEmpty && world.ops.first.playCalls >= 1,
      reason: 'player play() was not called (preparation/TTS path blocked?)',
    );
    final ops = world.ops.first;
    expect(ops.loadedPaths, isNotEmpty);
    final played = File(ops.loadedPaths.first);
    expect(played.existsSync(), isTrue, reason: 'audio file must exist');
    expect(
      played.readAsBytesSync(),
      kFakeAudioBytes,
      reason: 'played file = bytes returned by the fake TTS server',
    );

    // With a key set, adding a book also sends the LLM a chapter-skeleton request
    // (add_book_screen); the cleaner request is the one carrying page 1 text.
    final chat = world.server.chatRequests.toList();
    expect(chat, isNotEmpty, reason: 'LLM requests must be sent');
    final cleaner = chat
        .where((r) => r.userMessage.contains(kPage1Marker))
        .toList();
    expect(
      cleaner,
      isNotEmpty,
      reason: 'page 1 text must be sent to the cleaner',
    );
    for (final r in chat) {
      expect(r.originalHost, 'generativelanguage.googleapis.com');
      expect(r.path, '/v1beta/openai/chat/completions');
      expect(r.authorization, 'Bearer test-key-gemini');
    }

    // TTS: Google endpoint, X-Goog-Api-Key, synthesized text = page 1.
    final tts = world.server.ttsRequests.toList();
    expect(tts, isNotEmpty);
    expect(tts.first.originalHost, 'texttospeech.googleapis.com');
    expect(tts.first.headers['x-goog-api-key'], 'test-key-google');
    expect(tts.first.ttsText, contains(kPage1Marker));

    // Text on screen (karaoke lines).
    await pumpUntilFound(
      tester,
      find.textContaining('Residual earnings measure'),
      timeout: const Duration(seconds: 10),
      reason: 'page 1 sentences did not appear in the reader',
    );
    expect(find.byIcon(Icons.pause), findsOneWidget);

    // Track ends naturally -> next page is prepared and played.
    ops.completeCurrentPlay();
    await pumpUntil(
      tester,
      () => ops.loadedPaths.length >= 2,
      reason: 'page 2 was not loaded into the player after page 1 ended',
    );
    expect(find.text('Page 2 / 4'), findsOneWidget);
    expect(
      world.server.ttsRequests.any((r) => r.ttsText.contains(kPage2Marker)),
      isTrue,
      reason: 'page 2 text must go to TTS',
    );

    // Pause: the player receives pause.
    final pausesBefore = ops.pauseCalls;
    await tapPause(tester);
    await pumpUntil(
      tester,
      () => ops.pauseCalls > pausesBefore,
      reason: 'pause did not reach the player',
    );

    expect(
      world.server.unrouted,
      isEmpty,
      reason: 'unknown endpoint requests: ${world.server.unrouted}',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });
}
