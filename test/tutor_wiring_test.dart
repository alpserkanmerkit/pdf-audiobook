// Oracle RED WIRING test (§13.7, 2026-10-06, private lesson Slice-2, G7a).
// Spec: internal design note §7.1/1, §7.3.
//
// Antidote to "unit green != wired": the Slice-1 engine (TutorSession) was 100%
// complete at the gate, but it was not connected to any screen. These tests
// enter through the composition root (SesliKitapApp): Library -> "Tutor"
// -> book -> chapter -> part 1.
// The prompt sent to the fake LLM must be exactly the prompt that the REAL cache
// + REAL splitter + REAL TutorSession would produce (spy, test writing principles §8).
// The keyless real path (no seam) shows the error without going to the network.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/tutor/lesson_split.dart';
import 'package:sesli_kitap/src/tutor/tutor_prompts.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';

import 'helpers/test_app.dart';
import 'helpers/tutor_helpers.dart';

Finder _key(String k) => find.byKey(Key(k));

Future<void> _tap(WidgetTester tester, Finder f) async {
  expect(f, findsOneWidget, reason: 'the tap target must be on screen');
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
}

/// Build the app and tap the "Tutor" button in the Library.
Future<void> _openTutorFromLibrary(
  WidgetTester tester,
  AppServices services,
) async {
  await tester.pumpWidget(buildTestAppFromServices(services));
  await tester.pumpAndSettle();
  expect(
    _key('library-open-tutor'),
    findsOneWidget,
    reason: 'the tutor button must be in the Library header row',
  );
  await _tap(tester, _key('library-open-tutor'));
  await pumpUntil(tester, _key('tutor-book-${tutorBook.id}'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Library -> "Tutor" button opens the lesson screen (the book '
      'list comes from the library)', (tester) async {
    final services = await buildTutorServices(llm: FakeTutorLlm().call);
    await _openTutorFromLibrary(tester, services);

    expect(_key('tutor-book-${tutorBook.id}'), findsOneWidget);
    expect(
      find.descendant(
        of: _key('tutor-book-${tutorBook.id}'),
        matching: find.text('Penman FSA'),
        matchRoot: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'screen is wired to the REAL TutorSession + splitter + cache: the '
    'first prompt sent to the LLM = kTutorSystemPrompt + '
    'buildLessonPrompt(part 1/3, the s.10 text in the cache)',
    (tester) async {
      final fake = FakeTutorLlm();
      final services = await buildTutorServices(llm: fake.call);
      await tester.runAsync(() => seedTutorPages(services));
      await _openTutorFromLibrary(tester, services);

      await _tap(tester, _key('tutor-book-${tutorBook.id}'));
      await pumpUntil(tester, _key('tutor-chapter-0'));
      await _tap(tester, _key('tutor-chapter-0'));
      await pumpUntil(tester, _key('tutor-part'));

      expect(_key('tutor-part'), findsOneWidget);
      expect(fake.lessonCalls, hasLength(1));
      final call = fake.lessonCalls.single;
      expect(call.system, kTutorSystemPrompt);
      expect(
        call.user,
        buildLessonPrompt(
          part: LessonPart(
            index: 0,
            fromPage: 10,
            toPage: 10,
            text: tutorPageTexts[10]!,
          ),
          totalParts: 3,
          bookTitle: tutorBook.title,
          chapterTitle: tutorChapter.title!,
        ),
      );
    },
  );

  testWidgets(
    'keyless REAL path (no seam): tapping a chapter shows the "No Gemini API key set" error and makes no network call',
    (tester) async {
      final services = await buildTutorServices();
      await tester.runAsync(() => seedTutorPages(services));
      await _openTutorFromLibrary(tester, services);

      await _tap(tester, _key('tutor-book-${tutorBook.id}'));
      await pumpUntil(tester, _key('tutor-chapter-0'));
      await _tap(tester, _key('tutor-chapter-0'));
      await pumpUntil(tester, _key('tutor-error'));

      expect(
        find.descendant(
          of: _key('tutor-error'),
          matching: find.text('No Gemini API key set. Enter it in Settings.'),
          matchRoot: true,
        ),
        findsOneWidget,
      );
      expect(_key('tutor-part'), findsNothing);
    },
  );

  test('AppServices.tutorLlm: returns the seam if present; null without a key; '
      'a real LlmTutor with a key', () async {
    final fake = FakeTutorLlm();
    final fn = fake.call;
    final withSeam = await buildTutorServices(llm: fn);
    expect(identical(withSeam.tutorLlm(), fn), isTrue);

    final noKey = await buildTutorServices();
    expect(noKey.tutorLlm(), isNull);

    final blankKey = await buildTutorServices(geminiKey: '   ');
    expect(blankKey.tutorLlm(), isNull);

    final withKey = await buildTutorServices(geminiKey: 'test-key');
    // The keyed path is NOT the seam: it produces a real LlmTutor tear-off.
    final real = withKey.tutorLlm();
    expect(real, isNotNull);
    expect(identical(real, fn), isFalse);
  });
}
