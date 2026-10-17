// PR (A6): location-aware discussion topic suggestion -- PURE text generation.
//
// Derives a "<title> — <chapter label>" discussion topic from the book the user
// is currently reading, and APPENDS a one-sentence spoiler guard to the END of
// the topic STRING ("Do NOT reveal any developments beyond the reader's progress
// (%<progressPercent>)."). This way the topic prompt sent to the LLM itself tells
// the model not to reveal parts the reader has not reached yet
// (lib/io/llm_discussion.dart is NOT touched -- the spoiler guard is already a
// PART of the topic text).
//
// Pure -- no io/state. Screen wiring: lib/ui/screens/discussion_room_screen.dart
// (_showStartDialog, PR A6).
import 'package:sesli_kitap/src/library/library_store.dart';

/// Returns a single discussion topic text for [book], containing
/// "title — chapterLabel" (only `book.title` when chapterLabel is empty or
/// whitespace) plus the spoiler-guard sentence.
String discussionTopicForBook(Book book) {
  final chapter = book.chapterLabel.trim();
  final headline = chapter.isEmpty ? book.title : '${book.title} — $chapter';
  return "$headline. Do NOT reveal any developments beyond the reader's "
      'progress (%${book.progressPercent}).';
}
