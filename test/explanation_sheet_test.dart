// Oracle RED tests: widget flow of the ExplanationSheet ("Ask" sub-page).
// fetch/speak are faked via DI (the real LLM/TTS reader wiring is verified by the
// review + device layer, per the gate hierarchy).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';
import 'package:sesli_kitap/ui/widgets/explanation_sheet.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildAppTheme(AppSettings()),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('selection stage: ask-sentence button + word chips are visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ExplanationSheet(
          sentence: 'Kedi mama yedi.',
          fetchExplanation: ({required target, required isWord}) async => 'x',
        ),
      ),
    );
    expect(find.byKey(const Key('ask-sentence')), findsOneWidget);
    expect(find.byKey(const Key('word-chip-0')), findsOneWidget);
    expect(find.text('Kedi'), findsOneWidget);
    expect(find.text('mama'), findsOneWidget);
    expect(find.text('yedi'), findsOneWidget);
  });

  testWidgets('ask the sentence: loading -> answer is shown + spoken', (
    tester,
  ) async {
    final calls = <(String, bool)>[];
    final spoken = <String>[];
    final gate = Completer<String>();
    await tester.pumpWidget(
      _wrap(
        ExplanationSheet(
          sentence: 'Kedi mama yedi.',
          fetchExplanation: ({required target, required isWord}) {
            calls.add((target, isWord));
            return gate.future;
          },
          speak: (text) async => spoken.add(text),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('ask-sentence')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete('This sentence explains something.');
    await tester.pumpAndSettle();
    expect(find.text('This sentence explains something.'), findsOneWidget);
    expect(calls, [('Kedi mama yedi.', false)]);
    expect(spoken, ['This sentence explains something.']);
  });

  testWidgets('word chip: fetch is called with isWord:true + the target word', (
    tester,
  ) async {
    final calls = <(String, bool)>[];
    await tester.pumpWidget(
      _wrap(
        ExplanationSheet(
          sentence: 'Kedi mama yedi.',
          fetchExplanation: ({required target, required isWord}) async {
            calls.add((target, isWord));
            return 'word meaning';
          },
        ),
      ),
    );
    await tester.tap(find.text('mama'));
    await tester.pumpAndSettle();
    expect(calls, [('mama', true)]);
    expect(find.text('word meaning'), findsOneWidget);
  });

  testWidgets(
    'answer is still shown when speak is not given (speaking is optional)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          ExplanationSheet(
            sentence: 'Tek cumle.',
            fetchExplanation: ({required target, required isWord}) async =>
                'silent answer',
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('ask-sentence')));
      await tester.pumpAndSettle();
      expect(find.text('silent answer'), findsOneWidget);
    },
  );

  testWidgets('fetch error: error state + recovery via retry', (tester) async {
    var attempt = 0;
    await tester.pumpWidget(
      _wrap(
        ExplanationSheet(
          sentence: 'Tek cumle.',
          fetchExplanation: ({required target, required isWord}) async {
            attempt++;
            if (attempt == 1) throw Exception('network dropped');
            return 'second attempt answer';
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('ask-sentence')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ask-retry')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ask-retry')));
    await tester.pumpAndSettle();
    expect(find.text('second attempt answer'), findsOneWidget);
    expect(attempt, 2);
  });

  testWidgets('after the answer, the speak-again button calls speak again', (
    tester,
  ) async {
    final spoken = <String>[];
    await tester.pumpWidget(
      _wrap(
        ExplanationSheet(
          sentence: 'Tek cumle.',
          fetchExplanation: ({required target, required isWord}) async =>
              'answer text',
          speak: (text) async => spoken.add(text),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('ask-sentence')));
    await tester.pumpAndSettle();
    expect(spoken, ['answer text']);

    await tester.tap(find.byKey(const Key('speak-again')));
    await tester.pumpAndSettle();
    expect(spoken, ['answer text', 'answer text']);
  });

  testWidgets('speech error does NOT block the answer (best-effort)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ExplanationSheet(
          sentence: 'Tek cumle.',
          fetchExplanation: ({required target, required isWord}) async =>
              'visible answer',
          speak: (text) async => throw Exception('TTS blew up'),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('ask-sentence')));
    await tester.pumpAndSettle();
    expect(find.text('visible answer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
