import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sesli_kitap/io/llm_quiz.dart';
import 'package:sesli_kitap/io/page_pipeline.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/src/quiz_choice_machine.dart';
import 'package:sesli_kitap/src/quiz_review_bridge.dart';
import 'package:sesli_kitap/src/quiz_source.dart';
import 'package:sesli_kitap/src/review_store.dart';
import 'package:sesli_kitap/ui/screens/cards_screen.dart';
import 'package:sesli_kitap/ui/screens/quiz_choice_screen.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';

/// Quiz tab: generates 4-option questions with the LLM from the READ text of
/// the open book, then feeds [QuizChoiceScreen]. Includes the empty-key guard
/// (same contract as discussion) and the test seam (debugQuizFactory).
class QuizScreen extends StatefulWidget {
  const QuizScreen({
    super.key,
    this.book,
    this.pipeline,
    this.debugQuizFactory,
  });

  final Book? book;
  final PagePipeline? pipeline;

  /// Test seam: if provided, this factory is called instead of the real
  /// LLM/network (same pattern as discussion_room_screen's
  /// debugControllerFactory). `gatheredText` is the collected book text; it is
  /// passed so a test can verify that the text comes from the read pages (not
  /// the cover/colophon) (R3).
  final Future<List<MultipleChoiceQuestion>> Function(String gatheredText)?
  debugQuizFactory;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  List<MultipleChoiceQuestion>? _questions;
  bool _loading = false;
  String? _error;

  AppServices get _services => AppServicesScope.of(context);

  @override
  void didUpdateWidget(QuizScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the BOOK changed (the Quiz tab is kept alive in an IndexedStack),
    // RESET the generated questions -- otherwise the previous book's questions
    // could be written to the current book's reviewbank (adversarial-review
    // F3: cross-book).
    if (oldWidget.book?.hash != widget.book?.hash) {
      setState(() {
        _questions = null;
        _error = null;
        _loading = false;
      });
    }
  }

  /// SELECTS the pages closest to the last READ page (by recency), but
  /// CONCATENATES them in reading (ascending) order. Selection: BACKWARD from
  /// currentPage up to the 8000-character cap (quizSourcePageOrder -> R3: the
  /// old FORWARD selection always returned the cover/colophon/foreword).
  /// Emit: the selected pages in ASCENDING order -> the text sent to the LLM
  /// keeps reading order (multi-page window page blocks are not reversed,
  /// sentences across page breaks are not cut). Pages that have not been
  /// prepared return null and are skipped.
  Future<String> _gatherBookText() async {
    final pipeline = widget.pipeline;
    final book = widget.book;
    if (pipeline == null || book == null) return '';
    // The reader (reader_screen) clamps this key to 1..totalPages; the quiz
    // follows the same defensive contract (prevents unbounded iteration over
    // totalPages from a corrupted/injected prefs value -- adversarial-review
    // finding).
    final saved = _services.prefs.getInt('progress_${book.hash}') ?? 1;
    final total = book.totalPages < 1 ? 1 : book.totalPages;
    final currentPage = saved.clamp(1, total);
    // 1) Select BACKWARD: decide which pages to include, by recency.
    final collected = <int, String>{};
    var totalLen = 0;
    for (final p in quizSourcePageOrder(currentPage: currentPage)) {
      if (totalLen >= 8000) break;
      final t = await pipeline.cachedCleanText(p);
      if (t != null && t.trim().isNotEmpty) {
        collected[p] = t;
        totalLen += t.length;
      }
    }
    // 2) Write FORWARD (reading order): join the selected pages in ascending
    // page number.
    final pagesAsc = collected.keys.toList()..sort();
    final buf = StringBuffer();
    for (final p in pagesAsc) {
      buf.writeln(collected[p]);
    }
    return buf.toString();
  }

  Future<void> _generate() async {
    final factory = widget.debugQuizFactory;
    // Generation is ASYNC; the book may have changed by the time it finishes
    // (F3 in-flight race). Capture the starting book; if the book is different
    // when the result arrives, STOP.
    final baslangicHash = widget.book?.hash;
    if (factory == null) {
      // Empty-key guard: if the Gemini key is empty, the network is NEVER
      // called (same contract as reader/discussion).
      if (!_services.reading.llmAccess.isConfigured) {
        setState(() {
          _error =
              'A Gemini API key is required for the quiz. '
              'Enter it in Settings > ACCOUNT & API.';
        });
        return;
      }
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Gather the text on BOTH paths: it is fed to the real LLM, and also
      // passed to the test seam (so the factory can verify that the text comes
      // from the read pages -- R3 backward-window proof).
      final text = await _gatherBookText();
      final List<MultipleChoiceQuestion> qs;
      if (factory != null) {
        qs = await factory(text);
      } else {
        // Minimum-content guard (H-C2): the network is NOT called with
        // insufficient text; the user is asked to read first. No quiz is
        // generated from short parts such as the cover/colophon.
        // (On the factory path there is no network -> the guard only protects
        // the real LLM path.)
        if (!hasEnoughQuizText(text)) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error =
                'Read a little of the book first; the quiz is built from the sections you have read.';
          });
          return;
        }
        qs = await LlmQuiz(
          access: _services.reading.llmAccess,
        ).fetch(bookText: text, kaynak: widget.book!.title);
      }
      // If the book changed during generation, DISCARD the stale result (F3
      // in-flight).
      if (!mounted || widget.book?.hash != baslangicHash) return;
      setState(() {
        _questions = qs;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not generate questions: $e';
      });
    }
  }

  /// When the quiz is completed, writes the results to the open book's
  /// reviewbank_[hash]: the existing bank (if any) is decoded, the quiz results
  /// are MERGED into it (previous progress is kept), and it is re-encoded and
  /// saved. The report's 'Learned' counter and CardsScreen (spaced repetition)
  /// are fed from this bank.
  void _persistQuizResults(
    List<MultipleChoiceQuestion> sorular,
    List<bool> dogrular,
  ) {
    final book = widget.book;
    if (book == null) return;
    final prefs = _services.prefs;
    final key = 'reviewbank_${book.hash}';
    ReviewBank? mevcut;
    final raw = prefs.getString(key);
    if (raw != null) {
      try {
        mevcut = decodeReviewBank(raw);
      } on FormatException {
        mevcut = null; // corrupted record -> fresh bank
      }
    }
    final today = daysSinceEpoch(DateTime.now());
    final merged = mergeQuizIntoReviewBank(
      mevcut: mevcut,
      sorular: sorular,
      dogrular: dogrular,
      today: today,
    );
    unawaited(prefs.setString(key, encodeReviewBank(merged)));
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final questions = _questions;
    if (questions != null) {
      return QuizChoiceScreen(
        sorular: questions,
        onCompleted: (dogrular) => _persistQuizResults(questions, dogrular),
        // "Finish" -> back to the generation screen (Study cards is there; the
        // panel must not be a dead end).
        onFinish: () => setState(() => _questions = null),
      );
    }
    if (widget.book == null) {
      return _centered(
        palette,
        Icons.menu_book,
        'Open a book from the Library first; the quiz is built from that book.',
      );
    }
    return _buildGeneratePrompt(palette);
  }

  Widget _centered(AppPalette palette, IconData icon, String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: palette.text3),
            const SizedBox(height: 12),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: palette.text2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneratePrompt(AppPalette palette) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.quiz, size: 48, color: palette.accent),
            const SizedBox(height: 16),
            Text(
              'Quiz for "${widget.book!.title}"',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: palette.text),
            ),
            const SizedBox(height: 8),
            Text(
              'AI generates 4-option questions from the sections you have read.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: palette.text3),
            ),
            const SizedBox(height: 24),
            if (_loading)
              const CircularProgressIndicator()
            else
              ElevatedButton(
                key: const Key('quiz-generate'),
                onPressed: _generate,
                child: const Text('Generate questions'),
              ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            // If quizzes were already taken for this book (a reviewbank exists),
            // show the entry to spaced-repetition cards. If no card is due,
            // CardsScreen says "no cards to review today" (correct spaced
            // repetition).
            if (_services.prefs.getString('reviewbank_${widget.book!.hash}') !=
                null) ...[
              const SizedBox(height: 12),
              TextButton(
                key: const Key('quiz-review-cards'),
                onPressed: () {
                  unawaited(
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            CardsScreen(bookHash: widget.book!.hash),
                      ),
                    ),
                  );
                },
                child: const Text('Study cards'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
