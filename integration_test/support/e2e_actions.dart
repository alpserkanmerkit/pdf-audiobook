// Shared screen-level actions (real taps; NOT the fake server/ops).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/src/onboarding/onboarding_prefs.dart';

import 'e2e_world.dart';

/// Initial prefs with onboarding skipped (saved); fake keys can be added.
Map<String, Object> onboardedPrefs([Map<String, Object> extra = const {}]) => {
  'onboarding': encodeOnboarding(
    const OnboardingPrefs(onboarded: true, choice: VoiceChoice.ahmet),
  ),
  ...extra,
};

/// The SINGLE book in books_v1 (tests add exactly one book).
Book singleBook(E2eWorld world) {
  final books = decodeBooks(world.services.prefs.getString('books_v1') ?? '[]');
  expect(books, hasLength(1), reason: 'exactly 1 book expected in the library');
  return books.single;
}

/// Opens the book from its library card (switches to the reader tab).
///
/// [waitForPipeline] true (default): waits until the reader pipeline is set up.
/// false: returns as soon as the reader tab opens; the "Play before pipeline" case
/// (flow 7b) deliberately tries an early press in this state.
Future<void> openBookFromLibrary(
  WidgetTester tester,
  Book book, {
  bool waitForPipeline = true,
}) async {
  await tapFinder(tester, find.text(book.title));
  await pumpUntilFound(tester, find.byKey(const Key('page-indicator')));
  if (!waitForPipeline) return;
  // The reader is enabled once PagePipeline is set up (app_shell _buildPipelineAsync: file
  // read + Isolate.run running-header detection); until then the center play button is a SILENT no-op
  // (faded icon, onTap does nothing while pipeline==null). On a slow/loaded machine (GitHub runner, strace)
  // the tap comes BEFORE the pipeline and play() is never called (evidence: ag.md).
  // Wait until the faded icon goes away.
  await pumpUntil(
    tester,
    () => find
        .byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.play_arrow && w.color?.a == 0.5,
        )
        .evaluate()
        .isEmpty,
    reason: 'reader pipeline (PagePipeline) was not set up',
  );
  await tester.pump(const Duration(milliseconds: 300));
}

/// Taps the play button (center, play_arrow) in the reader.
Future<void> tapPlay(WidgetTester tester) =>
    tapFinder(tester, find.byIcon(Icons.play_arrow));

/// Taps the pause button in the reader.
Future<void> tapPause(WidgetTester tester) =>
    tapFinder(tester, find.byIcon(Icons.pause));

/// Library -> Tutor -> book -> first chapter. Waits until the lesson (tutor-part)
/// or the resume offer (tutor-resume-offer) appears; returns which one appeared.
Future<String> openTutorChapter(WidgetTester tester, Book book) async {
  await tapFinder(tester, find.byKey(const Key('library-open-tutor')));
  await pumpUntilFound(tester, find.byKey(Key('tutor-book-${book.id}')));
  await tapFinder(tester, find.byKey(Key('tutor-book-${book.id}')));
  await pumpUntilFound(tester, find.byKey(const Key('tutor-chapter-0')));
  await tapFinder(tester, find.byKey(const Key('tutor-chapter-0')));
  final part = find.byKey(const Key('tutor-part'));
  final offer = find.byKey(const Key('tutor-resume-offer'));
  final error = find.byKey(const Key('tutor-error'));
  await pumpUntil(
    tester,
    () =>
        part.evaluate().isNotEmpty ||
        offer.evaluate().isNotEmpty ||
        error.evaluate().isNotEmpty,
    reason: 'tutor showed neither a lesson, a resume offer, nor an error',
  );
  if (error.evaluate().isNotEmpty) {
    final msg = (tester.widget(error) as Text).data;
    fail('Tutor error screen: $msg');
  }
  return part.evaluate().isNotEmpty ? 'part' : 'resume-offer';
}

/// Goes back from the tutor screen to the Library.
Future<void> backToLibrary(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
  await pumpUntilFound(tester, find.text('Your library'));
}

/// Picks [label] in the provider selection dialog in Settings.
Future<void> chooseLlmProvider(WidgetTester tester, String label) async {
  await tapFinder(tester, find.text('AI provider'));
  await pumpUntilFound(tester, find.byType(SimpleDialog));
  await tapFinder(
    tester,
    find.descendant(of: find.byType(SimpleDialog), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

/// Opens the key dialog of the [rowLabel] row in Settings and saves [key].
Future<void> enterApiKey(
  WidgetTester tester,
  String rowLabel,
  String key,
) async {
  await tapFinder(tester, find.text(rowLabel));
  await pumpUntilFound(tester, find.byType(AlertDialog));
  await tester.enterText(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    ),
    key,
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tapFinder(tester, find.text('Save'));
  await tester.pumpAndSettle();
}
