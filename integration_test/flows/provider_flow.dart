// FLOW 5: provider selection. In the Settings screen (REAL taps) DeepSeek /
// Google (Gemini) / NVIDIA are selected and a key is entered; the tutor LLM request
// goes to the SELECTED provider's REAL endpoint (host + path) with the CORRECT Bearer
// key; it does not go to the others. In "All" mode, if the first provider returns 503,
// the next one is tried.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/tutor/tutor_prompts.dart'
    show kTutorSystemPrompt;

import '../support/e2e_actions.dart';
import '../support/e2e_world.dart';
import '../support/fake_api_server.dart';

/// The provider's OFFICIAL (documented) endpoint + fake key. The values
/// are NOT read from app code: they are hand-written fixed expectations (contract).
class _Expected {
  const _Expected(this.label, this.keyRow, this.key, this.host, this.path);
  final String label;
  final String keyRow;
  final String key;
  final String host;
  final String path;
}

const _deepseek = _Expected(
  'DeepSeek',
  'DeepSeek API key',
  'test-key-deepseek',
  'api.deepseek.com',
  '/chat/completions',
);
const _gemini = _Expected(
  'Google (Gemini)',
  'Gemini API key',
  'test-key-gemini',
  'generativelanguage.googleapis.com',
  '/v1beta/openai/chat/completions',
);
const _nvidia = _Expected(
  'NVIDIA',
  'NVIDIA API key',
  'test-key-nvidia',
  'integrate.api.nvidia.com',
  '/v1/chat/completions',
);

List<RecordedRequest> _lessonRequests(E2eWorld world, int skip) => world
    .server
    .chatRequests
    .skip(skip)
    .where((r) => r.systemMessage == kTutorSystemPrompt)
    .toList();

/// Opens Settings, runs [steps], then returns.
Future<void> _inSettings(
  WidgetTester tester,
  Future<void> Function() steps,
) async {
  await tapFinder(tester, find.byIcon(Icons.tune));
  await pumpUntilFound(tester, find.text('Settings'));
  await steps();
  await tester.pageBack();
  await tester.pumpAndSettle();
  await pumpUntilFound(tester, find.text('Your library'));
}

void providerFlow() {
  testWidgets('flow 5: provider selection -- request goes to the correct '
      'endpoint with the correct Authorization', (tester) async {
    final world = await E2eWorld.create(prefs: onboardedPrefs());
    addTearDown(world.dispose);
    await world.launch(tester);
    await addBookViaUi(tester);
    final book = singleBook(world);
    expect(
      world.server.requests,
      isEmpty,
      reason: 'adding a book without a key must not hit the network',
    );

    // Enter all three keys (none is used until selected).
    await _inSettings(tester, () async {
      for (final e in [_deepseek, _gemini, _nvidia]) {
        await enterApiKey(tester, e.keyRow, e.key);
      }
    });
    expect(world.services.prefs.getString('deepseekApiKey'), _deepseek.key);
    expect(world.services.prefs.getString('geminiKey'), _gemini.key);
    expect(world.services.prefs.getString('nvidiaApiKey'), _nvidia.key);

    // For each provider: select -> start lesson -> verify the request.
    for (final e in [_deepseek, _nvidia, _gemini]) {
      final before = world.server.chatRequests.length;
      await _inSettings(tester, () => chooseLlmProvider(tester, e.label));
      expect(await openTutorChapter(tester, book), 'part');

      final lessons = _lessonRequests(world, before);
      expect(
        lessons,
        hasLength(1),
        reason: '${e.label}: exactly 1 lesson request expected',
      );
      final r = lessons.single;
      expect(r.originalHost, e.host, reason: '${e.label}: host');
      expect(r.path, e.path, reason: '${e.label}: path');
      expect(
        r.authorization,
        'Bearer ${e.key}',
        reason: '${e.label}: Authorization',
      );
      expect(r.method, 'POST');
      expect(r.json['model'], isA<String>());
      expect((r.json['model']! as String).isNotEmpty, isTrue);
      // Only the selected provider was called.
      expect(
        world.server.chatRequests.skip(before).map((x) => x.originalHost),
        everyElement(e.host),
        reason: '${e.label}: requests must not leak to another provider',
      );
      await backToLibrary(tester);
    }

    // "All": order Gemini -> DeepSeek -> NVIDIA; Gemini 503 -> DeepSeek.
    world.server.failingChatHosts.add(_gemini.host);
    final before = world.server.chatRequests.length;
    await _inSettings(
      tester,
      () => chooseLlmProvider(tester, 'All (with keys entered)'),
    );
    expect(await openTutorChapter(tester, book), 'part');
    final hosts = world.server.chatRequests
        .skip(before)
        .map((x) => x.originalHost)
        .toList();
    expect(hosts, [
      _gemini.host,
      _deepseek.host,
    ], reason: 'all: first Gemini (503), then DeepSeek (200)');
    final fallback = world.server.chatRequests.last;
    expect(fallback.authorization, 'Bearer ${_deepseek.key}');
    expect(fallback.path, _deepseek.path);
    await backToLibrary(tester);

    // Selection is persistent.
    expect(world.services.prefs.getString('llmProvider'), 'all');

    expect(world.server.unrouted, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
