// Oracle RED test (2026-10-06, private lesson Slice-2, G7a).
// Spec: internal design note §7.1 (screen states).
//
// The screen is tested through the REAL path: AppServicesScope + real CacheStore
// (temp dir) + real splitter + real TutorSession; only the LLM is fake (the
// AppServices.tutorLlmFactory seam). States: book selection / chapter selection
// / loading / part explanation + Q&A / error / lesson finished.
// F9: the provider error text is shown VERBATIM; no fallback path; nothing made up.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/ui/screens/tutor_screen.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';

import 'helpers/tutor_helpers.dart';

Widget _wrap(AppServices services, {List<Book> books = const [tutorBook]}) {
  final settings = AppSettings();
  return AppServicesScope(
    services: services,
    child: AppSettingsScope(
      settings: settings,
      child: MaterialApp(
        theme: buildAppTheme(settings),
        home: TutorScreen(books: books),
      ),
    ),
  );
}

Finder _key(String k) => find.byKey(Key(k));

/// The widget with [key] itself, or a descendant of it, that shows [text] exactly.
Finder _textIn(String key, String text) =>
    find.descendant(of: _key(key), matching: find.text(text), matchRoot: true);

Future<void> _tap(WidgetTester tester, Finder f) async {
  expect(f, findsOneWidget, reason: 'the tap target must be on screen');
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
}

/// Build the screen, write the pages to the cache, select the book and chapter;
/// wait until the part 1 explanation is visible.
Future<void> _openFirstPart(WidgetTester tester, AppServices services) async {
  await tester.runAsync(() => seedTutorPages(services));
  await tester.pumpWidget(_wrap(services));
  await tester.pump();
  await _tap(tester, _key('tutor-book-${tutorBook.id}'));
  await pumpUntil(tester, _key('tutor-chapter-0'));
  await _tap(tester, _key('tutor-chapter-0'));
  await pumpUntil(tester, _key('tutor-part'));
}

Future<void> _answer(WidgetTester tester, int q, String text) async {
  await tester.ensureVisible(_key('tutor-answer-$q'));
  await tester.enterText(_key('tutor-answer-$q'), text);
  await _tap(tester, _key('tutor-submit-$q'));
}

void main() {
  testWidgets('book selection -> chapter list: book title and chapter label '
      'are visible', (tester) async {
    final services = await buildTutorServices(llm: FakeTutorLlm().call);
    await tester.pumpWidget(_wrap(services));
    await tester.pump();

    expect(_textIn('tutor-book-${tutorBook.id}', 'Penman FSA'), findsOneWidget);
    await _tap(tester, _key('tutor-book-${tutorBook.id}'));
    await pumpUntil(tester, _key('tutor-chapter-0'));

    expect(
      _textIn('tutor-chapter-0', 'Pricing Book Values (s.10-12)'),
      findsOneWidget,
    );
  });

  testWidgets('if there is no book in the library, the redirect text is '
      'visible', (tester) async {
    final services = await buildTutorServices(
      llm: FakeTutorLlm().call,
      withBook: false,
    );
    await tester.pumpWidget(_wrap(services, books: const []));
    await tester.pump();

    expect(
      _textIn('tutor-no-books', 'Add a book to your library first.'),
      findsOneWidget,
    );
  });

  testWidgets('if there is no chapter map, the redirect text is visible and '
      'no LLM call is made', (tester) async {
    final fake = FakeTutorLlm();
    final services = await buildTutorServices(llm: fake.call, chapters: null);
    await tester.pumpWidget(_wrap(services));
    await tester.pump();
    await _tap(tester, _key('tutor-book-${tutorBook.id}'));
    await pumpUntil(tester, _key('tutor-no-chapters'));

    expect(
      _textIn(
        'tutor-no-chapters',
        'This book has no chapter map. Open it once in the Reader.',
      ),
      findsOneWidget,
    );
    expect(fake.calls, isEmpty);
  });

  testWidgets('loading: an indicator is shown while the LLM is pending and no '
      'part; when the reply arrives, the part 1 header, explanation and '
      'question are shown verbatim', (tester) async {
    final fake = FakeTutorLlm();
    final hold = Completer<void>();
    fake.holdNext = hold;
    final services = await buildTutorServices(llm: fake.call);
    await tester.runAsync(() => seedTutorPages(services));
    await tester.pumpWidget(_wrap(services));
    await tester.pump();
    await _tap(tester, _key('tutor-book-${tutorBook.id}'));
    await pumpUntil(tester, _key('tutor-chapter-0'));
    await _tap(tester, _key('tutor-chapter-0'));
    // Real page collection (G/C): wait until the LLM call is reached.
    final llmWait = Stopwatch()..start();
    while (fake.calls.isEmpty &&
        llmWait.elapsed < const Duration(seconds: 10)) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }

    expect(fake.lessonCalls, hasLength(1));
    expect(_key('tutor-loading'), findsOneWidget);
    expect(_key('tutor-part'), findsNothing);

    hold.complete();
    await pumpUntil(tester, _key('tutor-part'));

    expect(_key('tutor-loading'), findsNothing);
    expect(_textIn('tutor-part-header', 'Part 1/3 · p.10-10'), findsOneWidget);
    expect(_textIn('tutor-explanation', 'Explanation part 1.'), findsOneWidget);
    expect(_textIn('tutor-question-0', 'Question 1 part 1?'), findsOneWidget);
  });

  testWidgets('answer: the button is locked with an indicator while waiting; '
      'when the grade arrives, "Correct" and the explanation are shown '
      'verbatim; the student answer in the prompt is trimmed', (tester) async {
    final fake = FakeTutorLlm();
    final services = await buildTutorServices(llm: fake.call);
    await _openFirstPart(tester, services);

    final hold = Completer<void>();
    fake.holdNext = hold;
    await _answer(tester, 0, '  earnings above the required return  ');

    expect(fake.gradeCalls, hasLength(1));
    expect(
      fake.gradeCalls.single.user,
      contains('STUDENT ANSWER:\nearnings above the required return'),
    );
    expect(_key('tutor-grading-0'), findsOneWidget);
    expect(isEnabled(tester, _key('tutor-submit-0')), isFalse);
    expect(isEnabled(tester, _key('tutor-next')), isFalse);

    hold.complete();
    await pumpUntil(tester, _key('tutor-verdict-0'));

    expect(_key('tutor-grading-0'), findsNothing);
    expect(_textIn('tutor-verdict-0', 'Correct'), findsOneWidget);
    expect(find.text('Well done, you got the gist.'), findsOneWidget);
  });

  testWidgets('next part: locked until every question is graded; enabled once '
      'graded; tapping loads part 2', (tester) async {
    final fake = FakeTutorLlm()..questionsPerPart = 2;
    final services = await buildTutorServices(llm: fake.call);
    await _openFirstPart(tester, services);

    expect(_textIn('tutor-next', 'Next part'), findsOneWidget);
    expect(isEnabled(tester, _key('tutor-next')), isFalse);

    await _answer(tester, 0, 'first answer');
    await pumpUntil(tester, _key('tutor-verdict-0'));
    expect(
      isEnabled(tester, _key('tutor-next')),
      isFalse,
      reason: 'no progress while question 2 is not graded',
    );

    await _answer(tester, 1, 'second answer');
    await pumpUntil(tester, _key('tutor-verdict-1'));
    expect(isEnabled(tester, _key('tutor-next')), isTrue);

    await _tap(tester, _key('tutor-next'));
    await pumpUntil(tester, _textIn('tutor-part-header', 'Part 2/3 · p.11-11'));
    expect(_textIn('tutor-part-header', 'Part 2/3 · p.11-11'), findsOneWidget);
    expect(fake.lessonCalls, hasLength(2));
    expect(_key('tutor-verdict-0'), findsNothing, reason: 'new part is clean');
  });

  testWidgets(
    'empty answer: the "Answer must not be empty." message is shown, no LLM '
    'call',
    (tester) async {
      final fake = FakeTutorLlm();
      final services = await buildTutorServices(llm: fake.call);
      await _openFirstPart(tester, services);

      await _answer(tester, 0, '   ');
      await tester.pump();

      expect(
        _textIn('tutor-answer-error-0', 'Answer must not be empty.'),
        findsOneWidget,
      );
      expect(fake.gradeCalls, isEmpty);
      expect(_key('tutor-verdict-0'), findsNothing);
    },
  );

  testWidgets('grading error (F9): provider text shown verbatim under the '
      'question, no grade, progress locked', (tester) async {
    final fake = FakeTutorLlm();
    final services = await buildTutorServices(llm: fake.call);
    await _openFirstPart(tester, services);

    fake.failGradeWith = TutorProviderDown(
      'AI server returned an error (HTTP 503).',
    );
    await _answer(tester, 0, 'an answer');
    await pumpUntil(tester, _key('tutor-answer-error-0'));

    expect(
      _textIn(
        'tutor-answer-error-0',
        'AI server returned an error (HTTP 503).',
      ),
      findsOneWidget,
    );
    expect(_key('tutor-verdict-0'), findsNothing);
    expect(isEnabled(tester, _key('tutor-next')), isFalse);
    expect(fake.gradeCalls, hasLength(1), reason: 'no hidden retry');
  });

  testWidgets('part load error (F9): error screen text verbatim; Retry makes a '
      'new call and shows the part', (tester) async {
    final fake = FakeTutorLlm()
      ..failLessonWith = TutorProviderDown(
        'Could not reach the AI server. Check your internet connection '
        'and try again.',
      );
    final services = await buildTutorServices(llm: fake.call);
    await tester.runAsync(() => seedTutorPages(services));
    await tester.pumpWidget(_wrap(services));
    await tester.pump();
    await _tap(tester, _key('tutor-book-${tutorBook.id}'));
    await pumpUntil(tester, _key('tutor-chapter-0'));
    await _tap(tester, _key('tutor-chapter-0'));
    await pumpUntil(tester, _key('tutor-error'));

    expect(
      _textIn(
        'tutor-error',
        'Could not reach the AI server. Check your internet connection '
            'and try again.',
      ),
      findsOneWidget,
    );
    expect(_key('tutor-part'), findsNothing, reason: 'no made-up explanation');
    expect(fake.lessonCalls, hasLength(1), reason: 'no hidden retry');

    fake.failLessonWith = null;
    await _tap(tester, _key('tutor-retry'));
    await pumpUntil(tester, _key('tutor-part'));

    expect(fake.lessonCalls, hasLength(2));
    expect(_textIn('tutor-part-header', 'Part 1/3 · p.10-10'), findsOneWidget);
  });

  testWidgets('lesson finished: after 3 parts, Finish lesson -> summary counts '
      "each question's last grade", (tester) async {
    final fake = FakeTutorLlm();
    final services = await buildTutorServices(llm: fake.call);
    await _openFirstPart(tester, services);

    const grades = [
      '{"sonuc":"dogru","aciklama":"OK."}',
      '{"sonuc":"yarim","aciklama":"Something is missing."}',
      '{"sonuc":"yanlis","aciklama":"Incorrect."}',
    ];
    for (var part = 0; part < 3; part++) {
      if (part == 0) {
        // Answer the same question again: only the LAST grade counts (wrong -> correct).
        fake.gradeJson = '{"sonuc":"yanlis","aciklama":"First attempt."}';
        await _answer(tester, 0, 'first attempt');
        await pumpUntil(tester, _textIn('tutor-verdict-0', 'Wrong'));
      }
      fake.gradeJson = grades[part];
      await _answer(tester, 0, 'answer $part');
      final expected = ['Correct', 'Partial', 'Wrong'][part];
      await pumpUntil(tester, _textIn('tutor-verdict-0', expected));
      expect(_textIn('tutor-verdict-0', expected), findsOneWidget);
      if (part < 2) {
        expect(_textIn('tutor-next', 'Next part'), findsOneWidget);
        await _tap(tester, _key('tutor-next'));
        await pumpUntil(
          tester,
          _textIn(
            'tutor-part-header',
            'Part ${part + 2}/3 · p.${11 + part}-${11 + part}',
          ),
        );
      }
    }
    expect(_textIn('tutor-next', 'Finish lesson'), findsOneWidget);
    await _tap(tester, _key('tutor-next'));
    await pumpUntil(tester, _key('tutor-finished'));

    expect(_key('tutor-finished'), findsOneWidget);
    expect(
      _textIn('tutor-summary', 'Correct: 1 · Partial: 1 · Wrong: 1'),
      findsOneWidget,
    );
    expect(fake.lessonCalls, hasLength(3));
  });

  // G7c (cross-review MEDIUM-1): a double tap in the same frame performs one action.
  testWidgets('double tap on a chapter row in the same frame: one lesson '
      'request, no exceptions, part 1 shows normally', (tester) async {
    final fake = FakeTutorLlm();
    final services = await buildTutorServices(llm: fake.call);
    await tester.runAsync(() => seedTutorPages(services));
    await tester.pumpWidget(_wrap(services));
    await tester.pump();
    await _tap(tester, _key('tutor-book-${tutorBook.id}'));
    await pumpUntil(tester, _key('tutor-chapter-0'));

    await tester.ensureVisible(_key('tutor-chapter-0'));
    await tester.pump();
    // No pump in between: both taps land in the same frame.
    await tester.tap(_key('tutor-chapter-0'));
    await tester.tap(_key('tutor-chapter-0'));
    await pumpUntil(tester, _key('tutor-part'));
    // Wait a bit longer so a late second load would surface if one exists.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
    expect(fake.lessonCalls, hasLength(1));
    expect(_textIn('tutor-part-header', 'Part 1/3 · p.10-10'), findsOneWidget);
  });

  testWidgets('two quick taps on the next-part button: advances one part, no '
      'exceptions', (tester) async {
    final fake = FakeTutorLlm();
    final services = await buildTutorServices(llm: fake.call);
    await _openFirstPart(tester, services);

    await _answer(tester, 0, 'an answer');
    await pumpUntil(tester, _key('tutor-verdict-0'));
    expect(isEnabled(tester, _key('tutor-next')), isTrue);

    await tester.ensureVisible(_key('tutor-next'));
    await tester.pump();
    // No pump in between: both taps land in the same frame.
    await tester.tap(_key('tutor-next'));
    await tester.tap(_key('tutor-next'));
    await pumpUntil(tester, _textIn('tutor-part-header', 'Part 2/3 · p.11-11'));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
    expect(_textIn('tutor-part-header', 'Part 2/3 · p.11-11'), findsOneWidget);
    expect(fake.lessonCalls, hasLength(2));
  });
}
