import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:sesli_kitap/io/llm_cleaner.dart';
import 'package:sesli_kitap/io/pdf_text.dart';
import 'package:sesli_kitap/src/cache_keys.dart';
import 'package:sesli_kitap/src/chapter_cache.dart';
import 'package:sesli_kitap/src/chapter_map.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/src/page_preprocess.dart';
import 'package:sesli_kitap/src/tutor/chapter_pages.dart';
import 'package:sesli_kitap/src/tutor/lesson_split.dart';
import 'package:sesli_kitap/src/tutor/tutor_progress.dart';
import 'package:sesli_kitap/src/tutor/tutor_prompts.dart';
import 'package:sesli_kitap/src/tutor/tutor_session.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';

/// Stages of the tutor screen (SPEC §7.1).
enum _Phase { books, chapters, loading, resume, part, finished, error }

/// Tutor: pick a book -> pick a chapter -> part explanation + Q&A + grades ->
/// lesson summary. The lesson engine is [TutorSession] (slice 1); this screen
/// connects it to the book's cache/PDF text and to the user's taps.
///
/// F9: the LLM error text is shown AS IS; there is no switch to another provider
/// or local text, and there is no invented explanation.
class TutorScreen extends StatefulWidget {
  const TutorScreen({required this.books, super.key});

  final List<Book> books;

  @override
  State<TutorScreen> createState() => _TutorScreenState();
}

class _TutorScreenState extends State<TutorScreen> {
  _Phase _phase = _Phase.books;
  // `late` would change the error state (nullable + `!` is deliberate).
  // ignore: use_late_for_private_fields_and_variables
  Book? _book;
  List<Chapter> _chapters = const [];
  TutorSession? _session;
  String _error = '';

  // Persistent progress (SPEC §7.7): the prefs key of the selected chapter and the
  // pending chapter parts and saved record for the resume offer.
  // ignore: use_late_for_private_fields_and_variables
  String? _progressKey;
  List<LessonPart> _pendingParts = const [];
  String _pendingTitle = '';
  TutorProgress? _saved;

  // The FINAL grade of every question in finished parts (the session keeps only the
  // current part's grades; they are added here when each part ends).
  int _correct = 0;
  int _half = 0;
  int _wrong = 0;

  // Per-question UI state for the current part.
  final Map<int, TextEditingController> _answerControllers = {};
  final Set<int> _grading = {};
  final Map<int, String> _answerErrors = {};

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    for (final c in _answerControllers.values) {
      c.dispose();
    }
    _answerControllers.clear();
  }

  TextEditingController _controllerFor(int q) =>
      _answerControllers.putIfAbsent(q, TextEditingController.new);

  void _resetPartState() {
    _disposeControllers();
    _grading.clear();
    _answerErrors.clear();
  }

  // ---- Book / chapter selection ----

  void _selectBook(Book book) {
    final services = AppServicesScope.of(context);
    final raw = services.prefs.getString('chapters_${book.hash}');
    var chapters = const <Chapter>[];
    if (raw != null) {
      try {
        chapters = decodeChapters(raw);
      } on FormatException {
        chapters = const <Chapter>[];
      }
    }
    setState(() {
      _book = book;
      _chapters = chapters;
      _phase = _Phase.chapters;
    });
  }

  // ---- Chapter -> session ----

  /// Order: API key check (before collecting text) -> loading -> page collection ->
  /// splitting -> session -> first part.
  Future<void> _startChapter(int index) async {
    // Late tap from a chapter row of an old frame: the lesson has already started.
    if (_phase != _Phase.chapters) return;
    final services = AppServicesScope.of(context);
    final book = _book!;
    final chapter = _chapters[index];
    final llm = services.tutorLlm();
    if (llm == null) {
      setState(() {
        _session = null;
        _error = 'No Gemini API key set. Enter it in Settings.';
        _phase = _Phase.error;
      });
      return;
    }
    setState(() {
      _session = null;
      _error = '';
      _correct = 0;
      _half = 0;
      _wrong = 0;
      _phase = _Phase.loading;
    });
    final List<LessonPart> parts;
    try {
      final gathered = await _gatherPages(services, book, chapter);
      if (!mounted) return;
      debugPrint(describeChapterPages(gathered));
      parts = splitChapterIntoLessons(gathered.pages);
    } on Object catch (e) {
      _showError(e);
      return;
    }
    final title = chapter.title?.trim() ?? '';
    _pendingParts = parts;
    _pendingTitle = title.isEmpty ? 'Chapter ${index + 1}' : title;
    _progressKey = tutorProgressKey(
      bookHash: book.hash,
      startPage: chapter.startPage,
      endPage: chapter.endPage,
    );
    // A corrupt record, or one that does not match today's split, is silently ignored.
    final saved = decodeTutorProgress(services.prefs.getString(_progressKey!));
    if (saved != null && saved.totalParts == parts.length) {
      setState(() {
        _saved = saved;
        _phase = _Phase.resume;
      });
      return;
    }
    await _beginSession(startIndex: 0);
  }

  /// Answer to the resume offer: [resume] true -> the saved part and counts;
  /// false -> the record is deleted, part 1 and zero counts.
  Future<void> _answerResume({required bool resume}) async {
    // Late tap on the offer button from an old frame.
    if (_phase != _Phase.resume) return;
    final saved = _saved!;
    _saved = null;
    if (resume) {
      _correct = saved.correct;
      _half = saved.half;
      _wrong = saved.wrong;
      await _beginSession(startIndex: saved.partIndex);
      return;
    }
    await AppServicesScope.of(context).prefs.remove(_progressKey!);
    if (!mounted) return;
    await _beginSession(startIndex: 0);
  }

  Future<void> _beginSession({required int startIndex}) async {
    final llm = AppServicesScope.of(context).tutorLlm()!;
    final session = TutorSession(
      parts: _pendingParts,
      llm: llm,
      bookTitle: _book!.title,
      chapterTitle: _pendingTitle,
      startIndex: startIndex,
    );
    _session = session;
    await _loadPart(session);
  }

  /// Saves progress after finished parts; deletes the record if the lesson is done.
  void _persistProgress(TutorSession session) {
    final prefs = AppServicesScope.of(context).prefs;
    final key = _progressKey!;
    if (session.isFinished) {
      unawaited(prefs.remove(key));
      return;
    }
    final pending = prefs.setString(
      key,
      encodeTutorProgress(
        TutorProgress(
          partIndex: session.currentIndex,
          totalParts: session.parts.length,
          correct: _correct,
          half: _half,
          wrong: _wrong,
        ),
      ),
    );
    unawaited(pending);
  }

  Future<ChapterPagesResult> _gatherPages(
    AppServices services,
    Book book,
    Chapter chapter,
  ) {
    // Raw text is loaded lazily: the PDF is parsed only on a first page without clean text, and
    // ONCE (1..chapter end).
    List<String>? rawPages;
    var rawLoaded = false;
    Future<String?> readRaw(int p) async {
      if (!rawLoaded) {
        rawLoaded = true;
        rawPages = await _readRawPages(book, chapter.endPage);
      }
      final texts = rawPages;
      if (texts == null || p > texts.length) return null;
      return stripPageArtifacts(texts[p - 1]).text;
    }

    return gatherChapterPages(
      fromPage: chapter.startPage,
      toPage: chapter.endPage,
      readPage: (p) async => (await services.cache.readText(
        textCacheKey(
          bookHash: book.hash,
          pageNo: p,
          cleanPromptVersion: cleanPromptVersion,
        ),
      ))?.clean,
      readRawPage: book.filePath.isEmpty ? null : readRaw,
    );
  }

  /// Raw text layer of the PDF pages 1..[lastPage]; null if the file is missing or unreadable.
  Future<List<String>?> _readRawPages(Book book, int lastPage) async {
    try {
      final bytes = await File(book.filePath).readAsBytes();
      return await extractAllPageTexts(bytes, lastPage: lastPage);
    } on Object catch (e) {
      debugPrint('tutor: could not read raw page text: $e');
      return null;
    }
  }

  /// Loads the current part of [session] (a new LLM call). Error -> error
  /// screen (the exception text as is).
  Future<void> _loadPart(TutorSession session) async {
    setState(() {
      _error = '';
      _phase = _Phase.loading;
    });
    try {
      await session.loadCurrentPart();
    } on Object catch (e) {
      _showError(e);
      return;
    }
    if (!mounted) return;
    setState(() {
      _resetPartState();
      _phase = _Phase.part;
    });
  }

  void _showError(Object e) {
    if (!mounted) return;
    setState(() {
      _error = e.toString();
      _phase = _Phase.error;
    });
  }

  void _retry() {
    // Double tap: the first tap has already moved the phase to 'loading'.
    if (_phase != _Phase.error) return;
    final session = _session;
    if (session == null) {
      setState(() => _phase = _Phase.chapters);
      return;
    }
    unawaited(_loadPart(session));
  }

  // ---- Q&A ----

  Future<void> _submit(int q) async {
    final session = _session!;
    setState(() {
      _answerErrors.remove(q);
      _grading.add(q);
    });
    try {
      await session.answer(q, _controllerFor(q).text);
      if (!mounted) return;
      setState(() => _grading.remove(q));
    } on TutorStaleStepException {
      // The lesson step changed: that question is no longer on screen; ignore it silently.
      if (!mounted) return;
      setState(() => _grading.remove(q));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _grading.remove(q);
        _answerErrors[q] = e.toString();
      });
    }
  }

  bool _canGoNext(TutorSession session) {
    final step = session.currentStep;
    if (step == null || _grading.isNotEmpty) return false;
    return List.generate(
      step.sorular.length,
      (i) => i,
    ).every(session.grades.containsKey);
  }

  void _next() {
    final session = _session!;
    // Late tap from a button of an old frame: the new part is not graded yet.
    if (_phase != _Phase.part || !_canGoNext(session)) return;
    final grades = session.grades.values.toList();
    session.nextPart();
    for (final g in grades) {
      switch (g.verdict) {
        case AnswerVerdict.dogru:
          _correct++;
        case AnswerVerdict.yarim:
          _half++;
        case AnswerVerdict.yanlis:
          _wrong++;
      }
    }
    _persistProgress(session);
    if (session.isFinished) {
      setState(() {
        _resetPartState();
        _phase = _Phase.finished;
      });
      return;
    }
    unawaited(_loadPart(session));
  }

  // ---- View ----

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back from the chapter list -> book list; in other phases, leave the screen.
      canPop: _phase != _Phase.chapters,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) setState(() => _phase = _Phase.books);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Tutor')),
        body: SafeArea(child: _body(context)),
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (_phase) {
      case _Phase.books:
        return _buildBooks();
      case _Phase.chapters:
        return _buildChapters();
      case _Phase.loading:
        return _buildLoading();
      case _Phase.resume:
        return _buildResume(context);
      case _Phase.part:
        return _buildPart(context);
      case _Phase.finished:
        return _buildFinished(context);
      case _Phase.error:
        return _buildError(context);
    }
  }

  Widget _buildBooks() {
    if (widget.books.isEmpty) {
      return const _CenteredMessage(
        key: Key('tutor-no-books'),
        text: 'Add a book to your library first.',
      );
    }
    return ListView(
      children: [
        for (final book in widget.books)
          ListTile(
            key: Key('tutor-book-${book.id}'),
            title: Text(book.title),
            subtitle: Text(book.author),
            onTap: () => _selectBook(book),
          ),
      ],
    );
  }

  Widget _buildChapters() {
    if (_chapters.isEmpty) {
      return const _CenteredMessage(
        key: Key('tutor-no-chapters'),
        text: 'This book has no chapter map. Open it once in the Reader.',
      );
    }
    return ListView(
      children: [
        for (var i = 0; i < _chapters.length; i++)
          ListTile(
            key: Key('tutor-chapter-$i'),
            title: Text(tutorChapterLabel(_chapters[i], i)),
            onTap: () => _startChapter(i),
          ),
      ],
    );
  }

  Widget _buildLoading() {
    return const Center(
      key: Key('tutor-loading'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Preparing lesson…'),
        ],
      ),
    );
  }

  Widget _buildResume(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final saved = _saved!;
    return Center(
      key: const Key('tutor-resume-offer'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Left off at: Part ${saved.partIndex + 1}/${saved.totalParts}'
              ' · Correct: ${saved.correct} · Partial: ${saved.half}'
              ' · Wrong: ${saved.wrong}',
              key: const Key('tutor-resume-info'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: palette.text),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('tutor-resume'),
              onPressed: () => _answerResume(resume: true),
              child: const Text('Continue where you left off'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('tutor-restart'),
              onPressed: () => _answerResume(resume: false),
              child: const Text('Start over'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPart(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final session = _session!;
    final step = session.currentStep!;
    final part = session.currentPart;
    final isLast = session.currentIndex == session.parts.length - 1;
    return SingleChildScrollView(
      key: const Key('tutor-part'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Part ${part.index + 1}/${session.parts.length} · '
            'p.${part.fromPage}-${part.toPage}',
            key: const Key('tutor-part-header'),
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.2,
              color: palette.text3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            step.anlatim,
            key: const Key('tutor-explanation'),
            style: TextStyle(fontSize: 16, height: 1.5, color: palette.text),
          ),
          for (var q = 0; q < step.sorular.length; q++)
            _buildQuestion(context, session, q, step.sorular[q]),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('tutor-next'),
            onPressed: _canGoNext(session) ? _next : null,
            child: Text(isLast ? 'Finish lesson' : 'Next part'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestion(
    BuildContext context,
    TutorSession session,
    int q,
    TutorQuestion question,
  ) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final grade = session.grades[q];
    final grading = _grading.contains(q);
    final error = _answerErrors[q];
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question.soru,
            key: Key('tutor-question-$q'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: Key('tutor-answer-$q'),
            controller: _controllerFor(q),
            minLines: 1,
            maxLines: 5,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Your answer',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(
                key: Key('tutor-submit-$q'),
                onPressed: grading ? null : () => _submit(q),
                child: const Text('Submit'),
              ),
              if (grading) ...[
                const SizedBox(width: 12),
                SizedBox(
                  key: Key('tutor-grading-$q'),
                  width: 20,
                  height: 20,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error,
                key: Key('tutor-answer-error-$q'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (grade != null) ...[
            const SizedBox(height: 8),
            Text(
              _verdictLabel(grade.verdict),
              key: Key('tutor-verdict-$q'),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: palette.accent,
              ),
            ),
            Text(grade.aciklama, style: TextStyle(color: palette.text2)),
          ],
        ],
      ),
    );
  }

  Widget _buildFinished(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Center(
      key: const Key('tutor-finished'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Lesson complete',
            style: TextStyle(fontSize: 28, color: palette.text),
          ),
          const SizedBox(height: 12),
          Text(
            'Correct: $_correct · Partial: $_half · Wrong: $_wrong',
            key: const Key('tutor-summary'),
            style: TextStyle(fontSize: 16, color: palette.text2),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error,
              key: const Key('tutor-error'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('tutor-retry'),
              onPressed: _retry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

String _verdictLabel(AnswerVerdict verdict) {
  switch (verdict) {
    case AnswerVerdict.dogru:
      return 'Correct';
    case AnswerVerdict.yarim:
      return 'Partial';
    case AnswerVerdict.yanlis:
      return 'Wrong';
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
