// Oracle RED test (2026-09-28 night, note from the previous agent -- 4156f67):
// the error text on the discussion screen had an English prefix in front:
// "An error occurred while starting the discussion: LlmDiscussionException:
// Network error: The AI server did not respond within 90 seconds...".
// Root cause: llm_discussion.dart _complete built 'Network error: $e', and
// toString() printed the class name; the screen showed '$e' as-is.
//
// Pinned contract: the text shown to the user is clean -- no class name and
// no raw English prefix. On timeout the message from llm_client is shown
// as-is; on other network errors a fixed connection message is shown.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sesli_kitap/io/llm_client.dart';
import 'package:sesli_kitap/io/llm_discussion.dart';
import 'package:sesli_kitap/src/discussion/discussion_controller.dart';
import 'package:sesli_kitap/ui/screens/discussion_room_screen.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';

Future<String> _errorText(Object Function() thrower) async {
  // The test deliberately throws objects that are not Exception/Error.
  // ignore: only_throw_errors
  final mock = MockClient((req) async => throw thrower());
  try {
    await LlmDiscussion(apiKey: 'k', client: mock).generate('topic');
  } on LlmDiscussionException catch (e) {
    return e.toString();
  }
  fail('LlmDiscussionException bekleniyordu');
}

void main() {
  test("timeout: llm_client's message AS-IS, NO raw prefix", () async {
    final text = await _errorText(
      () => LlmTimeoutException(const Duration(seconds: 90)),
    );
    expect(
      text,
      'The AI server did not respond within 90 seconds. '
      'Check your internet connection and try again.',
    );
  });

  test('connection error: friendly message, NO raw detail', () async {
    final text = await _errorText(
      () => http.ClientException('Failed host lookup: generativelanguage'),
    );
    expect(
      text,
      'Could not connect to the AI server. '
      'Check your internet connection and try again.',
    );
  });

  testWidgets('screen: NO class name / "Network error" in the error banner', (
    tester,
  ) async {
    final settings = AppSettings();
    await tester.pumpWidget(
      AppSettingsScope(
        settings: settings,
        child: MaterialApp(
          theme: buildAppTheme(settings),
          home: DiscussionRoomScreen(
            debugControllerFactory: () => DiscussionController(
              generate: (_) async => throw LlmDiscussionException(
                'Could not connect to the AI server. '
                'Check your internet connection and try again.',
              ),
              synthesize: (turn) async =>
                  Uint8List.fromList(utf8.encode(turn.text)),
              play: (mp3) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.play_arrow));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'topic');
    await tester.tap(find.text('Start'));
    await tester.pump();
    // In a flow that finishes without any play() call, pumpAndSettle cannot
    // see completion (see the _settleAsyncChain doc in
    // discussion_wiring_test.dart): open a real waiting window, then update
    // the tree.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.textContaining('LlmDiscussionException'), findsNothing);
    expect(find.textContaining('Network error'), findsNothing);
    expect(
      find.text(
        'An error occurred while starting the discussion: Could not connect to the AI server. '
        'Check your internet connection and try again.',
      ),
      findsOneWidget,
    );
  });
}
