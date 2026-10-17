// Oracle RED test (2026-10-06, private lesson D2N: persistent progress).
// Spec: internal design note §7.7.
//
// "Closing and reopening the app" = the screen is fully removed from the tree (SizedBox),
// then a NEW TutorScreen is built; nothing is carried over except the same
// AppServices.prefs (the phone's own storage, shared_preferences).
// Real path: AppServicesScope + real CacheStore + real chapter splitter + real
// TutorSession; only the LLM is fake.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/tutor/tutor_progress.dart';
import 'package:sesli_kitap/ui/screens/tutor_screen.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';

import 'helpers/tutor_helpers.dart';

Widget _wrap(AppServices services) {
  final settings = AppSettings();
  return AppServicesScope(
    services: services,
    child: AppSettingsScope(
      settings: settings,
      child: MaterialApp(
        theme: buildAppTheme(settings),
        home: const TutorScreen(books: [tutorBook]),
      ),
    ),
  );
}

Finder _key(String k) => find.byKey(Key(k));

Finder _textIn(String key, String text) =>
    find.descendant(of: _key(key), matching: find.text(text), matchRoot: true);

final String _progressKey = tutorProgressKey(
  bookHash: tutorBook.hash,
  startPage: tutorChapter.startPage,
  endPage: tutorChapter.endPage,
);

Future<void> _tap(WidgetTester tester, Finder f) async {
  expect(f, findsOneWidget, reason: 'the element to tap must be on screen');
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
}

/// Open the app (again): book -> pick chapter. Waits until a part or the resume offer
/// is visible.
Future<void> _openChapter(WidgetTester tester, AppServices services) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  await tester.pumpWidget(_wrap(services));
  await tester.pump();
  await _tap(tester, _key('tutor-book-${tutorBook.id}'));
  await pumpUntil(tester, _key('tutor-chapter-0'));
  await _tap(tester, _key('tutor-chapter-0'));
  await pumpUntil(
    tester,
    find.byWidgetPredicate(
      (w) =>
          w.key == const Key('tutor-part') ||
          w.key == const Key('tutor-resume-offer'),
    ),
  );
}

/// Answer the current part's single question, wait for the grade, press next.
Future<void> _answerAndNext(WidgetTester tester) async {
  await tester.ensureVisible(_key('tutor-answer-0'));
  await tester.enterText(_key('tutor-answer-0'), 'my answer');
  await _tap(tester, _key('tutor-submit-0'));
  await pumpUntil(tester, _key('tutor-verdict-0'));
  await _tap(tester, _key('tutor-next'));
}

Future<void> _waitHeader(WidgetTester tester, String header) =>
    pumpUntil(tester, _textIn('tutor-part-header', header));

void main() {
  testWidgets(
    'closed at part 2 and reopened: offer -> resume from part 2, counts preserved',
    (tester) async {
      final fake = FakeTutorLlm();
      final services = await buildTutorServices(llm: fake.call);
      await tester.runAsync(() => seedTutorPages(services));

      await _openChapter(tester, services);
      expect(_key('tutor-resume-offer'), findsNothing, reason: 'first open');
      await _waitHeader(tester, 'Part 1/3 · p.10-10');
      await _answerAndNext(tester); // part 1 correct
      await _waitHeader(tester, 'Part 2/3 · p.11-11');
      expect(services.prefs.getString(_progressKey), isNotNull);

      // App closes / opens again.
      await _openChapter(tester, services);
      expect(_key('tutor-resume-offer'), findsOneWidget);
      expect(
        _textIn(
          'tutor-resume-info',
          'Left off at: Part 2/3 · Correct: 1 · Partial: 0 · Wrong: 0',
        ),
        findsOneWidget,
      );
      expect(
        _textIn('tutor-resume', 'Continue where you left off'),
        findsOneWidget,
      );
      expect(_textIn('tutor-restart', 'Start over'), findsOneWidget);

      final lessonCallsBefore = fake.lessonCalls.length;
      await _tap(tester, _key('tutor-resume'));
      await _waitHeader(tester, 'Part 2/3 · p.11-11');
      expect(
        _textIn('tutor-part-header', 'Part 2/3 · p.11-11'),
        findsOneWidget,
      );
      expect(fake.lessonCalls.length, lessonCallsBefore + 1);
      expect(fake.lessonCalls.last.user, contains('Part 2/3'));

      await _answerAndNext(tester); // part 2 correct
      await _waitHeader(tester, 'Part 3/3 · p.12-12');
      fake.gradeJson = '{"sonuc":"yanlis","aciklama":"Not quite."}';
      await _answerAndNext(tester); // part 3 wrong -> done
      await pumpUntil(tester, _key('tutor-finished'));
      expect(
        _textIn('tutor-summary', 'Correct: 2 · Partial: 0 · Wrong: 1'),
        findsOneWidget,
        reason: 'the part 1 grade from before closing is also counted',
      );
    },
  );

  testWidgets('start over: record deleted, part 1 and zero counts', (
    tester,
  ) async {
    final fake = FakeTutorLlm();
    final services = await buildTutorServices(llm: fake.call);
    await tester.runAsync(() => seedTutorPages(services));

    await _openChapter(tester, services);
    await _waitHeader(tester, 'Part 1/3 · p.10-10');
    await _answerAndNext(tester);
    await _waitHeader(tester, 'Part 2/3 · p.11-11');

    await _openChapter(tester, services);
    await _tap(tester, _key('tutor-restart'));
    await _waitHeader(tester, 'Part 1/3 · p.10-10');
    expect(_textIn('tutor-part-header', 'Part 1/3 · p.10-10'), findsOneWidget);
    expect(services.prefs.getString(_progressKey), isNull);

    for (var i = 0; i < 2; i++) {
      await _answerAndNext(tester);
      await _waitHeader(tester, 'Part${i + 2}/3 · p.${11 + i}-${11 + i}');
    }
    await _answerAndNext(tester);
    await pumpUntil(tester, _key('tutor-finished'));
    expect(
      _textIn('tutor-summary', 'Correct: 3 · Partial: 0 · Wrong: 0'),
      findsOneWidget,
      reason: 'the old part 1 grade is not counted',
    );
  });

  testWidgets('corrupt record: no offer, no crash, silently part 1', (
    tester,
  ) async {
    final fake = FakeTutorLlm();
    final services = await buildTutorServices(llm: fake.call);
    await tester.runAsync(() => seedTutorPages(services));
    await services.prefs.setString(_progressKey, '{bozuk');

    await _openChapter(tester, services);
    expect(_key('tutor-resume-offer'), findsNothing);
    await _waitHeader(tester, 'Part 1/3 · p.10-10');
    expect(_textIn('tutor-part-header', 'Part 1/3 · p.10-10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('record with mismatched part count: no offer, part 1', (
    tester,
  ) async {
    final fake = FakeTutorLlm();
    final services = await buildTutorServices(llm: fake.call);
    await tester.runAsync(() => seedTutorPages(services));
    await services.prefs.setString(
      _progressKey,
      encodeTutorProgress(
        const TutorProgress(
          partIndex: 3,
          totalParts: 5,
          correct: 1,
          half: 1,
          wrong: 1,
        ),
      ),
    );

    await _openChapter(tester, services);
    expect(_key('tutor-resume-offer'), findsNothing);
    await _waitHeader(tester, 'Part 1/3 · p.10-10');
    expect(_textIn('tutor-part-header', 'Part 1/3 · p.10-10'), findsOneWidget);
  });

  testWidgets('record deleted when the lesson finishes; no offer on reopen', (
    tester,
  ) async {
    final fake = FakeTutorLlm();
    final services = await buildTutorServices(llm: fake.call);
    await tester.runAsync(() => seedTutorPages(services));

    await _openChapter(tester, services);
    for (var i = 0; i < 2; i++) {
      await _waitHeader(tester, 'Part${i + 1}/3 · p.${10 + i}-${10 + i}');
      await _answerAndNext(tester);
    }
    await _waitHeader(tester, 'Part 3/3 · p.12-12');
    await _answerAndNext(tester);
    await pumpUntil(tester, _key('tutor-finished'));
    expect(_key('tutor-finished'), findsOneWidget);
    expect(services.prefs.getString(_progressKey), isNull);

    await _openChapter(tester, services);
    expect(_key('tutor-resume-offer'), findsNothing);
    await _waitHeader(tester, 'Part 1/3 · p.10-10');
    expect(_textIn('tutor-part-header', 'Part 1/3 · p.10-10'), findsOneWidget);
  });
}
