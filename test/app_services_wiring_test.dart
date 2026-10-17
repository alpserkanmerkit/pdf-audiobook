// W0 WIRING test (§13.7 — oracle writes). Composition root: AppServices
// (prefs + data dir + CacheStore + reader/discussion players +
// ReadingSettings) — is it CONNECTED to the app tree via AppServicesScope?
// The lib/ui/state/app_services.dart + lib/main.dart that the worker writes turn
// this test green. The tests do NOT touch the path_provider platform channel:
// AppServices is built directly with a temp dir (the production path is in main.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/main.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets(
    't1: ReadingSettings loads from prefs; cache lives under dataDir',
    (tester) async {
      final services = await buildTestServices(
        prefsValues: <String, Object>{'geminiKey': 'sk-test'},
      );

      services.reading.load();

      expect(services.reading.geminiKey, 'sk-test');
      // CacheStore is built from the data dir (not path_provider).
      expect(services.cache.root.path, startsWith(services.dataDir.path));
    },
  );

  testWidgets('t2: AppServicesScope is the same instance in all 5 tabs', (
    tester,
  ) async {
    final services = await buildTestServices();
    await tester.pumpWidget(SesliKitapApp(services: services));
    await tester.pumpAndSettle();

    // Starting tab: Library (no tap needed).
    final libraryCtx = tester.element(find.byKey(const Key('tab-library')));
    expect(
      identical(AppServicesScope.of(libraryCtx), services),
      isTrue,
      reason: 'AppServicesScope must be the same instance in the Library tab',
    );

    // Remaining 4 tabs: switch to each and query the scope from the visible screen's context.
    const remaining = <(String, String)>[
      ('Reader', 'tab-reader'),
      ('Discussion', 'tab-discussion'),
      ('Quiz', 'tab-quiz'),
      ('Report', 'tab-report'),
    ];
    for (final (label, keyName) in remaining) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byKey(Key(keyName)));
      expect(
        identical(AppServicesScope.of(ctx), services),
        isTrue,
        reason: '$label tab: AppServicesScope must be the same instance',
      );
    }
  });

  testWidgets(
    't3: players are owned by the service; dispose=1 when the shell is torn down',
    (tester) async {
      final created = <RecordingAudioOps>[];
      final services = await buildTestServices(createdOps: created);
      await tester.pumpWidget(SesliKitapApp(services: services));
      await tester.pumpAndSettle();

      // Two separate players; each access returns the SAME instance (service ownership).
      final reader = services.readerPlayer;
      final discussion = services.discussionPlayer;
      expect(identical(reader, services.readerPlayer), isTrue);
      expect(identical(discussion, services.discussionPlayer), isTrue);
      expect(identical(reader, discussion), isFalse);
      expect(created, hasLength(2));

      // Tear down the shell: State.dispose -> services.disposePlayers() -> both fake
      // ops are disposed EXACTLY once (GuardedAudioPlayer is idempotent).
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      for (final ops in created) {
        expect(
          ops.disposeCalls,
          1,
          reason: 'each player ops must be disposed exactly once',
        );
      }
    },
  );
}
