// FLOW 3: tutor lesson. Real book -> tutor lesson -> chapter: REAL
// TutorSession + chapter splitter + PDF raw text reading; the LLM (Gemini endpoint)
// is a fake server. The lesson opens, a question is answered (grading request),
// we move to the next part, and progress is written to prefs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/tutor/tutor_progress.dart';
import 'package:sesli_kitap/src/tutor/tutor_prompts.dart'
    show kTutorSystemPrompt;

import '../support/e2e_actions.dart';
import '../support/e2e_world.dart';

String _textOf(WidgetTester tester, String key) =>
    (tester.widget(find.byKey(Key(key))) as Text).data!;

void tutorFlow() {
  testWidgets('flow 3: tutor lesson -- lesson opens, answer is graded, '
      'progress is written to prefs', (tester) async {
    final world = await E2eWorld.create(
      prefs: onboardedPrefs({'geminiKey': 'test-key-gemini'}),
    );
    addTearDown(world.dispose);
    await world.launch(tester);
    await addBookViaUi(tester);
    final book = singleBook(world);
    final skeletonCalls = world.server.chatRequests.length;

    expect(await openTutorChapter(tester, book), 'part');

    // Lesson screen: fake LLM explanation + question + part heading.
    expect(_textOf(tester, 'tutor-explanation'), 'E2E explanation part 1.');
    expect(_textOf(tester, 'tutor-question-0'), 'E2E question part 1?');
    final header = _textOf(tester, 'tutor-part-header');
    final m = RegExp(r'^Part 1/(\d+) · p\.1-').firstMatch(header);
    expect(
      m,
      isNotNull,
      reason: 'part heading is not in the expected format: $header',
    );
    final totalParts = int.parse(m!.group(1)!);
    expect(
      totalParts,
      inInclusiveRange(3, 5),
      reason: 'lesson is split into 3-5 parts (SPEC kLessonMinParts..MaxParts)',
    );

    // LLM request: lesson system prompt, part 1, page-1 text from the PDF,
    // correct endpoint + Authorization.
    final lessonCalls = world.server.chatRequests
        .skip(skeletonCalls)
        .where((r) => r.systemMessage == kTutorSystemPrompt)
        .toList();
    expect(lessonCalls, hasLength(1));
    final lesson = lessonCalls.single;
    expect(lesson.originalHost, 'generativelanguage.googleapis.com');
    expect(lesson.path, '/v1beta/openai/chat/completions');
    expect(lesson.authorization, 'Bearer test-key-gemini');
    expect(lesson.userMessage, contains('Part 1/$totalParts'));
    expect(
      lesson.userMessage,
      contains(kPage1Marker),
      reason: 'the REAL PDF text of the book must go into the lesson prompt',
    );

    // Answer -> grading request -> correct score.
    await tester.enterText(
      find.byKey(const Key('tutor-answer-0')),
      'My answer: expected residual gain',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tapFinder(tester, find.byKey(const Key('tutor-submit-0')));
    await pumpUntilFound(tester, find.byKey(const Key('tutor-verdict-0')));
    expect(
      find.textContaining('E2E: Well done, you got the gist.'),
      findsOneWidget,
    );
    final grade = world.server.chatRequests
        .where((r) => r.userMessage.contains('STUDENT ANSWER:'))
        .toList();
    expect(grade, hasLength(1));
    expect(
      grade.single.userMessage,
      contains('My answer: expected residual gain'),
    );
    expect(grade.single.authorization, 'Bearer test-key-gemini');

    // Part not finished yet -> no progress record.
    final progressKey = tutorProgressKey(
      bookHash: book.hash,
      startPage: 1,
      endPage: 4,
    );
    expect(world.services.prefs.getString(progressKey), isNull);

    // Next part: progress is written, part 2 loads.
    await tapFinder(tester, find.byKey(const Key('tutor-next')));
    await pumpUntil(
      tester,
      () =>
          find.byKey(const Key('tutor-part-header')).evaluate().isNotEmpty &&
          _textOf(tester, 'tutor-part-header').startsWith('Part 2/'),
      reason: 'part 2 did not load',
    );
    expect(_textOf(tester, 'tutor-explanation'), 'E2E explanation part 2.');
    final saved = decodeTutorProgress(
      world.services.prefs.getString(progressKey),
    );
    expect(saved, isNotNull, reason: 'progress must be written to prefs');
    expect(saved!.partIndex, 1, reason: 'part 2 is next (0-based index 1)');
    expect(saved.totalParts, totalParts);
    expect(saved.correct, 1);
    expect(saved.half, 0);
    expect(saved.wrong, 0);

    expect(world.server.unrouted, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
