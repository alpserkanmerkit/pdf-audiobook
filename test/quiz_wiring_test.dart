// Slice-4 WIRING test (§13.7 — oracle). Is the Quiz tab wired into app_shell,
// and is LLM 4-choice question generation wired?
//
// The quiz is now QuizScreen: it generates 4-choice questions with the LLM from
// the OPEN book's READ text (test seam: debugQuizFactory, without touching the
// real network). The empty-key guard (same contract as discussion) and the
// no-book empty state are tested.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/io/page_pipeline.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/src/quiz_choice_machine.dart';
import 'package:sesli_kitap/src/review_scheduler.dart';
import 'package:sesli_kitap/src/review_store.dart';
import 'package:sesli_kitap/src/study_questions.dart';
import 'package:sesli_kitap/ui/screens/quiz_screen.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';
import 'helpers/test_app.dart';

/// Fake pipeline (reader_wiring_test.FakePagePipeline pattern): without touching
/// the real PDF/OCR/LLM/TTS, it returns the clean text that [cachedCleanText]
/// gives per page. The R3 guard test puts very short text on page 1.
class _FakeQuizPipeline extends PagePipeline {
  _FakeQuizPipeline({required super.store, required super.bookHash})
    : super(bookBytes: Uint8List(0));

  final Map<int, String> pageText = {};

  @override
  Future<String?> cachedCleanText(int pageNo) async => pageText[pageNo];
}

const _book = Book(
  id: 'q1',
  title: 'Quiz Book',
  author: 'Y',
  chapterLabel: '',
  progressPercent: 0,
  totalPages: 10,
  coverIndex: 0,
  hash: 'qhash1',
  filePath: '/tmp/q.pdf',
);

Widget _wrapQuiz(AppServices services, Widget child) {
  final settings = AppSettings();
  return AppServicesScope(
    services: services,
    child: AppSettingsScope(
      settings: settings,
      child: MaterialApp(theme: buildAppTheme(settings), home: child),
    ),
  );
}

void main() {
  testWidgets(
    'With no book open, the Quiz tab shows an explicit "open a book" message, '
    'NOT a fake demo',
    (tester) async {
      await tester.pumpWidget(await buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Quiz'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tab-quiz')), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('boşluk (negatif mekân)'),
        findsNothing,
        reason: 'the old fake demo question must NOT appear anymore',
      );
      expect(
        find.textContaining('Open a book'),
        findsWidgets,
        reason: 'without a book, the quiz requires a source book',
      );
    },
  );

  testWidgets(
    'With a book open, "Generate questions" -> the generated questions are shown '
    '(via debugQuizFactory, NO real network)',
    (tester) async {
      final services = await buildTestServices();
      final soru = MultipleChoiceQuestion(
        soru: 'Generated test question?',
        secenekler: ['Choice A', 'Choice B', 'Choice C', 'Choice D'],
        dogruIndex: 1,
        kaynak: 'Quiz Book',
      );
      await tester.pumpWidget(
        _wrapQuiz(
          services,
          QuizScreen(book: _book, debugQuizFactory: (_) async => [soru]),
        ),
      );
      await tester.pumpAndSettle();

      // Before generation the question is not visible; the button is.
      expect(find.textContaining('Generated test question'), findsNothing);
      expect(find.byKey(const Key('quiz-generate')), findsOneWidget);

      await tester.tap(find.byKey(const Key('quiz-generate')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Generated test question'),
        findsWidgets,
        reason: 'the generated question must be shown with QuizChoiceScreen',
      );
      expect(find.text('Choice A'), findsWidgets);
    },
  );

  testWidgets(
    'Gemini key EMPTY + "Generate questions" -> no network call, a friendly '
    '"API key" warning is shown (same contract as the discussion guard)',
    (tester) async {
      final services = await buildTestServices(); // geminiKey empty
      expect(services.reading.geminiKey, isEmpty);

      await tester.pumpWidget(
        _wrapQuiz(services, const QuizScreen(book: _book)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('quiz-generate')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('API key', findRichText: true),
        findsWidgets,
        reason:
            'with an empty key a friendly warning must show (not a raw error)',
      );
    },
  );

  testWidgets(
    'when the quiz is completed, results are written to reviewbank_<hash> '
    '(correct -> advances, wrong -> resets to zero); the report "Learned" '
    'counter is fed from this bank',
    (tester) async {
      final services = await buildTestServices();
      final q0 = MultipleChoiceQuestion(
        soru: 'First question?',
        secenekler: const ['y0', 'd0', 'z0', 'w0'],
        dogruIndex: 1, // correct = 'd0'
        kaynak: 'Quiz Book',
      );
      final q1 = MultipleChoiceQuestion(
        soru: 'Second question?',
        secenekler: const ['y1', 'z1', 'd1', 'w1'],
        dogruIndex: 2, // correct = 'd1'
        kaynak: 'Quiz Book',
      );
      await tester.pumpWidget(
        _wrapQuiz(
          services,
          QuizScreen(book: _book, debugQuizFactory: (_) async => [q0, q1]),
        ),
      );
      await tester.pumpAndSettle();

      // Before generation there is no reviewbank.
      expect(services.prefs.getString('reviewbank_qhash1'), isNull);

      await tester.tap(find.byKey(const Key('quiz-generate')));
      await tester.pumpAndSettle();

      // q0 CORRECT answer ('d0'), then Next.
      await tester.tap(find.text('d0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next →'));
      await tester.pumpAndSettle();

      // q1 WRONG answer ('y1' -> index0, correct index2), then Next (ends).
      await tester.tap(find.text('y1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next →'));
      await tester.pumpAndSettle();

      // The completion panel is visible ('Quiz completed').
      expect(
        find.textContaining('completed', findRichText: true),
        findsWidgets,
        reason:
            'the completion panel must show when the quiz ends (not a loop)',
      );

      // reviewbank_<hash> was written and can be decoded.
      final raw = services.prefs.getString('reviewbank_qhash1');
      expect(
        raw,
        isNotNull,
        reason: 'quiz result must be written to reviewbank_<hash>',
      );
      final bank = decodeReviewBank(raw!);
      expect(bank.items, hasLength(2));
      // q0 correct -> intervalIndex 1; q1 wrong -> intervalIndex 0.
      expect(bank.items[0].intervalIndex, 1, reason: 'q0 correct -> advanced');
      expect(bank.items[1].intervalIndex, 0, reason: 'q1 wrong -> at zero');
      expect(bank.questions[0].soru, 'First question?');
      expect(
        bank.questions[0].cevap,
        'd0',
        reason: 'answer = text of the correct choice',
      );
    },
  );

  testWidgets(
    'the quiz resets when the BOOK CHANGES -- old book questions cannot be '
    'written to the new book (adversarial-review F3: IndexedStack keep-alive '
    'cross-book)',
    (tester) async {
      final services = await buildTestServices();
      final soruA = MultipleChoiceQuestion(
        soru: 'Book A question?',
        secenekler: const ['a', 'b', 'c', 'd'],
        dogruIndex: 0,
        kaynak: 'A',
      );
      // Generate a quiz for book A.
      await tester.pumpWidget(
        _wrapQuiz(
          services,
          QuizScreen(book: _book, debugQuizFactory: (_) async => [soruA]),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quiz-generate')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Book A question'), findsWidgets);

      // Switch to book B at the same position (imitates the IndexedStack keep-alive).
      const bookB = Book(
        id: 'q2',
        title: 'Book B',
        author: 'Y',
        chapterLabel: '',
        progressPercent: 0,
        totalPages: 10,
        coverIndex: 0,
        hash: 'qhash2',
        filePath: '/tmp/b.pdf',
      );
      await tester.pumpWidget(
        _wrapQuiz(
          services,
          QuizScreen(book: bookB, debugQuizFactory: (_) async => [soruA]),
        ),
      );
      await tester.pumpAndSettle();

      // Book changed -> old book questions are NOT visible; regeneration is requested.
      expect(
        find.textContaining('Book A question'),
        findsNothing,
        reason:
            'when the book changes, the previous book questions must be cleared',
      );
      expect(
        find.byKey(const Key('quiz-generate')),
        findsOneWidget,
        reason: 'the generation button must be visible for the new book',
      );
    },
  );

  testWidgets('if the book changes DURING generation the result is DROPPED '
      '(adversarial-review F3 in-flight race: when the pending fetch finishes, '
      'old book questions are NOT attributed to the NEW book)', (tester) async {
    final services = await buildTestServices();
    final completer = Completer<List<MultipleChoiceQuestion>>();
    final soruA = MultipleChoiceQuestion(
      soru: 'Book A delayed question?',
      secenekler: const ['a', 'b', 'c', 'd'],
      dogruIndex: 0,
      kaynak: 'A',
    );

    // Book A: generation stays PENDING (completer not resolved yet).
    await tester.pumpWidget(
      _wrapQuiz(
        services,
        QuizScreen(book: _book, debugQuizFactory: (_) => completer.future),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quiz-generate')));
    await tester.pump(); // generation in-flight (loading)

    // Switch to book B before generation finishes.
    const bookB = Book(
      id: 'q2',
      title: 'Book B',
      author: 'Y',
      chapterLabel: '',
      progressPercent: 0,
      totalPages: 10,
      coverIndex: 0,
      hash: 'qhash2',
      filePath: '/tmp/b.pdf',
    );
    await tester.pumpWidget(
      _wrapQuiz(
        services,
        QuizScreen(book: bookB, debugQuizFactory: (_) => completer.future),
      ),
    );
    await tester.pump();

    // Now A's generation COMPLETES (the book is already B).
    completer.complete([soruA]);
    await tester.pumpAndSettle();

    // A's question must NOT be visible under B (stale result dropped).
    expect(
      find.textContaining('Book A delayed question'),
      findsNothing,
      reason:
          'when the book changes, the pending generation result must be dropped',
    );
    expect(find.byKey(const Key('quiz-generate')), findsOneWidget);
  });

  testWidgets(
    'with reviewbank present, the "Study cards" button on the generation screen '
    'opens CardsScreen (spaced-repetition entry point)',
    (tester) async {
      // A bank containing a card due today (dueDay 0 <= today).
      final bank = ReviewBank(
        items: const [ReviewItem(id: 'q0', intervalIndex: 0, dueDay: 0)],
        questions: [
          StudyQuestion(
            soru: 'Card question text?',
            cevap: 'answer',
            tip: QuestionKind.olgusal,
          ),
        ],
      );
      final services = await buildTestServices(
        prefsValues: {'reviewbank_qhash1': encodeReviewBank(bank)},
      );
      await tester.pumpWidget(
        _wrapQuiz(services, const QuizScreen(book: _book)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('quiz-review-cards')),
        findsOneWidget,
        reason: 'if reviewbank exists, the cards entry button must be visible',
      );
      await tester.tap(find.byKey(const Key('quiz-review-cards')));
      await tester.pumpAndSettle();

      // CardsScreen opened: app bar title + the due card question.
      expect(find.textContaining('Spaced repetition'), findsWidgets);
      expect(find.textContaining('Card question text'), findsWidgets);
    },
  );

  testWidgets('without reviewbank the "Study cards" button is NOT visible', (
    tester,
  ) async {
    final services = await buildTestServices();
    await tester.pumpWidget(_wrapQuiz(services, const QuizScreen(book: _book)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quiz-review-cards')), findsNothing);
  });

  testWidgets(
    'the completion panel does NOT lack an exit: "Finish" returns to the '
    'generation screen (device finding: the panel had no exit, Study cards was '
    'unreachable)',
    (tester) async {
      final services = await buildTestServices();
      final q0 = MultipleChoiceQuestion(
        soru: 'Single question?',
        secenekler: const ['a', 'b', 'c', 'd'],
        dogruIndex: 0,
        kaynak: 'K',
      );
      await tester.pumpWidget(
        _wrapQuiz(
          services,
          QuizScreen(book: _book, debugQuizFactory: (_) async => [q0]),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quiz-generate')));
      await tester.pumpAndSettle();

      // Single question: answer + Next -> completion panel.
      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next →'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('completed', findRichText: true),
        findsWidgets,
      );

      // The "Finish" button is on the panel and returns to the generation screen.
      expect(
        find.byKey(const Key('quiz-finish')),
        findsOneWidget,
        reason: 'the completion panel must include an exit button',
      );
      await tester.tap(find.byKey(const Key('quiz-finish')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('quiz-generate')),
        findsOneWidget,
        reason:
            'Finish -> returns to the generation screen (Study cards is reached here)',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // R3 tests: the quiz must ask about the book's CONTENT (not cover/colophon/preface).
  //   H-C1 (back-window): gathering must go BACKWARD from the last READ page.
  //   H-C2 (min-guard): generation must be BLOCKED on very short/insufficient text.
  // After integration both pass (GREEN).
  // ---------------------------------------------------------------------------

  testWidgets(
    'R3 min-guard: with very short read text, "Generate questions" -> NO network '
    'call, a friendly "read a bit more" warning is shown (hasEnoughQuizText, H-C2)',
    (tester) async {
      // geminiKey must be FILLED so the empty-key guard does NOT trigger; the real
      // check is the min-content guard. No debugQuizFactory -> the real gathering path runs.
      final services = await buildTestServices(
        prefsValues: {'geminiKey': 'sk-filled-key', 'progress_qhash1': 1},
      );
      services.reading.load();
      expect(services.reading.geminiKey, isNotEmpty);

      final pipeline = _FakeQuizPipeline(
        store: services.cache,
        bookHash: _book.hash,
      )..pageText[1] = 'Cover'; // very short (insufficient) content

      await tester.pumpWidget(
        _wrapQuiz(services, QuizScreen(book: _book, pipeline: pipeline)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('quiz-generate')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // hasEnoughQuizText('Cover') false -> NO LLM call, friendly warning.
      expect(
        find.textContaining('Read a little', findRichText: true),
        findsWidgets,
        reason:
            'with insufficient read text there must be no network call; the user must be told to read first',
      );
    },
  );

  testWidgets(
    'R3 back-window: quiz text is gathered BACKWARD from the LAST read pages -- '
    'not cover/colophon (page 1); the read page content is used (H-C1)',
    (tester) async {
      // Book has 170 pages; reading is at 170. Page 1 = colophon, page 170 = read content.
      const bigBook = Book(
        id: 'q1',
        title: 'Quiz Book',
        author: 'Y',
        chapterLabel: '',
        progressPercent: 0,
        totalPages: 170,
        coverIndex: 0,
        hash: 'qhash1',
        filePath: '/tmp/q.pdf',
      );
      final services = await buildTestServices(
        prefsValues: {'progress_qhash1': 170},
      );

      final pipeline = _FakeQuizPipeline(
        store: services.cache,
        bookHash: bigBook.hash,
      );
      // Page 1: colophon/cover (quiz must NOT be built from this).
      pipeline.pageText[1] = 'COLOPHON-COVER-TEXT ${'x' * 400}';
      // Page 170: last read content (quiz MUST be built from this). Large enough
      // to exceed the 8000 ceiling -> backward gathering stops BEFORE reaching page 1 (colophon).
      pipeline.pageText[170] = 'READ-CONTENT-170 ${'y' * 8200}';

      // Capture the gathered text via the test seam (from the argument passed to the factory).
      String? gathered;
      await tester.pumpWidget(
        _wrapQuiz(
          services,
          QuizScreen(
            book: bigBook,
            pipeline: pipeline,
            debugQuizFactory: (text) async {
              gathered = text;
              return [
                MultipleChoiceQuestion(
                  soru: 'X?',
                  secenekler: const ['a', 'b', 'c', 'd'],
                  dogruIndex: 0,
                  kaynak: 'K',
                ),
              ];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('quiz-generate')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        gathered,
        isNotNull,
        reason: 'the factory must receive the gathered text',
      );
      expect(
        gathered,
        contains('READ-CONTENT-170'),
        reason: 'gathering must start from the LAST read page (170)',
      );
      expect(
        gathered,
        isNot(contains('COLOPHON-COVER-TEXT')),
        reason:
            'page 1 (colophon/cover) must not come in BEFORE hitting the 8000 ceiling -- '
            'backward gathering prioritizes the read page (R3 fix)',
      );
    },
  );

  testWidgets(
    'R3 multi-page: pages are SELECTED by recency but the text is JOINED in READING '
    '(ascending) order -- s8, s9, s10 in that order; colophon (s1) excluded '
    '(adversarial-review: select backward, write forward)',
    (tester) async {
      const bigBook = Book(
        id: 'q1',
        title: 'Quiz Book',
        author: 'Y',
        chapterLabel: '',
        progressPercent: 0,
        totalPages: 20,
        coverIndex: 0,
        hash: 'qhash1',
        filePath: '/tmp/q.pdf',
      );
      final services = await buildTestServices(
        prefsValues: {'progress_qhash1': 10},
      );

      final pipeline = _FakeQuizPipeline(
        store: services.cache,
        bookHash: bigBook.hash,
      );
      // Read window: s8, s9, s10 -- small, distinctive markers.
      pipeline.pageText[8] = 'CONTENT-S8 ${'a' * 100}';
      pipeline.pageText[9] = 'CONTENT-S9 ${'b' * 100}';
      pipeline.pageText[10] = 'CONTENT-S10 ${'c' * 100}';
      // s7: large filler exceeding the 8000 ceiling -> backward gathering
      // stops BEFORE reaching s1 (colophon stays outside the recency window).
      pipeline.pageText[7] = 'CONTENT-S7 ${'d' * 8000}';
      // s1: colophon -- must NOT enter the gathered text even if it is cached.
      pipeline.pageText[1] = 'COLOPHON-COVER-TEXT ${'z' * 200}';

      String? gathered;
      await tester.pumpWidget(
        _wrapQuiz(
          services,
          QuizScreen(
            book: bigBook,
            pipeline: pipeline,
            debugQuizFactory: (text) async {
              gathered = text;
              return [
                MultipleChoiceQuestion(
                  soru: 'X?',
                  secenekler: const ['a', 'b', 'c', 'd'],
                  dogruIndex: 0,
                  kaynak: 'K',
                ),
              ];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('quiz-generate')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        gathered,
        isNotNull,
        reason: 'the factory must receive the gathered text',
      );
      final g = gathered!;
      // All three pages were SELECTED.
      expect(g, contains('CONTENT-S8'));
      expect(g, contains('CONTENT-S9'));
      expect(g, contains('CONTENT-S10'));
      // READING (ascending) order: s8 before s9; s9 before s10. This pins
      // "select backward, write forward" -- a raw backward emit (s10,s9,s8) would BREAK this.
      final i8 = g.indexOf('CONTENT-S8');
      final i9 = g.indexOf('CONTENT-S9');
      final i10 = g.indexOf('CONTENT-S10');
      expect(
        i8 < i9 && i9 < i10,
        isTrue,
        reason:
            'selected pages must be joined in READING (ascending) order '
            '(s8<s9<s10); a backward emit reverses the page blocks',
      );
      // Colophon (s1), even if cached, is outside the recency window -> excluded.
      expect(
        g,
        isNot(contains('COLOPHON-COVER-TEXT')),
        reason:
            'the 8000 ceiling filled up before reaching s1; the colophon must not be gathered',
      );
    },
  );
}
