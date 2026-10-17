import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:sesli_kitap/io/cache_store.dart';
import 'package:sesli_kitap/io/page_pipeline.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/ui/screens/add_book_screen.dart';
import 'package:sesli_kitap/ui/screens/discover_screen.dart';
import 'package:sesli_kitap/ui/screens/discussion_room_screen.dart';
import 'package:sesli_kitap/ui/screens/library_screen.dart';
import 'package:sesli_kitap/ui/screens/notebook_screen.dart';
import 'package:sesli_kitap/ui/screens/quiz_screen.dart';
import 'package:sesli_kitap/ui/screens/reader_screen.dart';
import 'package:sesli_kitap/ui/screens/report_screen.dart';
import 'package:sesli_kitap/ui/screens/settings_screen.dart';
import 'package:sesli_kitap/ui/screens/tutor_screen.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';

/// Tabs in the bottom navigation bar. The order must match EXACTLY the
/// `IndexedStack` children and the `BottomNavigationBar` items in `build`
/// (`NavTab.values[index]`). An enum-only file is excluded from lcov by the
/// `lib/src` gate rule (orphan), so it is defined here.
enum NavTab { library, reader, discussion, quiz, report }

class AppNavStore extends ChangeNotifier {
  NavTab _tab = NavTab.library;

  NavTab get tab => _tab;

  void go(NavTab t) {
    if (_tab == t) return;
    _tab = t;
    notifyListeners();
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.pipelineFactory});

  final PagePipeline Function({required Book book, required CacheStore store})?
  pipelineFactory;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final AppNavStore _store = AppNavStore();
  Book? _openBook;
  PagePipeline? _pipeline;
  bool _pipelineFailed = false;
  VoidCallback? _readerPauseHandle;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    setState(() {});
  }

  void _startOpenBook(Book book) {
    setState(() {
      _openBook = book;
      _pipelineFailed = false;
      if (widget.pipelineFactory != null) {
        _pipeline = widget.pipelineFactory!(
          book: book,
          store: AppServicesScope.of(context).cache,
        );
      } else {
        _pipeline = null;
      }
    });
    _store.go(NavTab.reader);
    if (widget.pipelineFactory == null) {
      unawaited(_buildPipelineAsync(book));
    }
  }

  /// Book deletion request from the library screen (long-press + confirm).
  /// Removes ONLY the touched [index] from books_v1 (NOT id matching -- review
  /// finding 2: if two records share the same file, id matching would remove both).
  /// Deletes the owned PDF copy from disk on a best-effort basis, but only if NO
  /// other record shares the same path, and clears the chapter-map cache
  /// (chapters_[hash]). progress_[hash]/reviewbank_[hash] are DELIBERATELY left
  /// alone -- if the same file is added again, progress and learning state must
  /// not be lost. If the deleted book is the one currently open (review finding 1:
  /// a "ghost session" -- Reader/Quiz kept running on the in-memory PagePipeline),
  /// the reader state is cleared as well.
  Future<void> _deleteBook(BuildContext context, int index, Book book) async {
    final services = AppServicesScope.of(context);
    final raw = services.prefs.getString('books_v1') ?? '[]';
    final books = decodeBooks(raw);
    final updated = removeBookAt(books, index);
    await services.prefs.setString('books_v1', encodeBooks(updated));
    await services.prefs.remove('chapters_${book.hash}');
    final stillReferenced =
        book.filePath.isNotEmpty &&
        updated.any((b) => b.filePath == book.filePath);
    if (book.filePath.isNotEmpty && !stillReferenced) {
      try {
        final file = File(book.filePath);
        if (file.existsSync()) file.deleteSync();
      } on Object catch (_) {
        // best-effort cleanup; does not break the delete flow.
      }
    }
    if (_openBook?.id == book.id) {
      _openBook = null;
      _pipeline = null;
      _pipelineFailed = false;
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _buildPipelineAsync(Book book) async {
    final services = AppServicesScope.of(context);
    try {
      final bytes = await File(book.filePath).readAsBytes();
      // K4: the running header is detected while the book is being added and
      // passed to the reading pipeline too, so it is not read aloud as part of
      // every page's text (same detectRunningHeader as add_book_screen).
      final header = await _detectRunningHeaderOffThread(
        book.filePath,
        book.totalPages,
      );
      if (!mounted) return;
      setState(() {
        _pipeline = PagePipeline(
          store: services.cache,
          bookBytes: bytes,
          bookHash: book.hash,
          knownHeader: header,
        );
      });
    } on Object {
      if (!mounted || _openBook?.id != book.id) return;
      setState(() {
        _pipeline = null;
        _pipelineFailed = true;
      });
    }
  }

  /// [PagePipeline.detectRunningHeader] parses the PDF from the start for two
  /// separate pages (seconds for a large book). It runs in a separate isolate so
  /// the main thread does not ANR (same reason as add_book_screen). If detection
  /// fails, the header is treated as absent: the reading pipeline is not broken.
  Future<String?> _detectRunningHeaderOffThread(
    String path,
    int totalPages,
  ) async {
    try {
      return await Isolate.run(
        () => PagePipeline.detectRunningHeader(
          File(path).readAsBytesSync(),
          totalPages,
        ),
      );
    } on Object catch (_) {
      return null;
    }
  }

  /// Stops the audio that is playing when LEAVING the Reader tab (tapping another
  /// tab or the back gesture/button). IndexedStack moves ReaderScreen offstage and
  /// does NOT dispose it (it only hides it), so a tab switch alone never cuts the
  /// sound -- field report: after going back to the Library with the back button,
  /// the audio kept playing in the background.
  ///
  /// ReaderScreen's OWN interruption-marking logic (_suspendForNavigation) is called
  /// SYNCHRONOUSLY -- a second device finding: stopping AppServices.readerPlayer
  /// directly from here (old code) bypassed ReaderScreen's _playGeneration/
  /// _readerState bookkeeping; GuardedAudioPlayer.stop() DELIBERATELY emits the same
  /// "finished" signal as pause() (K20), so the reader took it as "page finished
  /// naturally" and kept preparing and playing the following pages forever in the
  /// background (proven with dumpsys audio).
  void _stopReaderAudioIfLeaving(NavTab target) {
    if (_store.tab == NavTab.reader && target != NavTab.reader) {
      _readerPauseHandle?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    // The Reader/Discussion/Quiz/Report tabs are fixed IndexedStack children and
    // are never pushed onto the Navigator -- so the system back button/gesture
    // normally finds no route to pop (it silently does nothing or closes the app).
    // While on a tab OTHER than Library, back first returns to Library; while on
    // Library (the root/"home" tab) the system default is allowed (exit the app).
    return PopScope(
      canPop: store.tab == NavTab.library,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _stopReaderAudioIfLeaving(NavTab.library);
        store.go(NavTab.library);
      },
      child: Scaffold(
        body: IndexedStack(
          index: store.tab.index,
          children: [
            _placeholder(context, NavTab.library),
            _placeholder(context, NavTab.reader),
            _placeholder(context, NavTab.discussion),
            _placeholder(context, NavTab.quiz),
            _placeholder(context, NavTab.report),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: store.tab.index,
          onTap: (index) {
            final target = NavTab.values[index];
            _stopReaderAudioIfLeaving(target);
            store.go(target);
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.library_books),
              label: 'Library',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.menu_book),
              label: 'Reader',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.forum),
              label: 'Discussion',
            ),
            BottomNavigationBarItem(icon: Icon(Icons.quiz), label: 'Quiz'),
            BottomNavigationBarItem(
              icon: Icon(Icons.insights),
              label: 'Report',
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context, NavTab tab) {
    return KeyedSubtree(
      key: Key('tab-${tab.name}'),
      child: switch (tab) {
        NavTab.library => LibraryScreen(
          books: _libraryBooks(context),
          onAddBook: () async {
            final added = await Navigator.of(context).push<Book?>(
              MaterialPageRoute<Book?>(builder: (_) => const AddBookScreen()),
            );
            if (added != null) {
              _startOpenBook(added);
            } else if (mounted) {
              // The user may have reached the "Ready" phase and left with the
              // top-bar back button (the book is already saved) -- refresh the Library.
              setState(() {});
            }
          },
          onOpenBook: _startOpenBook,
          onDeleteBook: (index, book) => _deleteBook(context, index, book),
          onOpenSettings: () {
            unawaited(
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              ),
            );
          },
          onOpenNotebook: () {
            unawaited(
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const NotebookScreen()),
              ),
            );
          },
          onOpenTutor: () {
            unawaited(
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TutorScreen(books: _libraryBooks(context)),
                ),
              ),
            );
          },
          onOpenDiscover: () {
            final pending = Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (discoverContext) => DiscoverScreen(
                  books: _libraryBooks(context),
                  onOpenBook: (book) {
                    Navigator.of(discoverContext).pop();
                    _startOpenBook(book);
                  },
                ),
              ),
            );
            unawaited(pending);
          },
        ),
        NavTab.reader => ReaderScreen(
          sentences: const [],
          book: _openBook,
          pipeline: _pipeline,
          pipelineFailed: _pipelineFailed,
          onBack: () => _store.go(NavTab.library),
          onAttachPauseHandle: (handle) => _readerPauseHandle = handle,
        ),
        NavTab.discussion => DiscussionRoomScreen(
          onBack: () => _store.go(NavTab.library),
          bookTitle: _openBook?.title,
          // K1 (closed box): if no chip is selected, the discussion source is the open book.
          book: _openBook,
        ),
        NavTab.quiz => QuizScreen(book: _openBook, pipeline: _pipeline),
        // The Report tab must be read FRESH from prefs every time it is shown. A const
        // ReportScreen as the IndexedStack child is a canonical single instance, so on
        // an AppShell rebuild Widget.canUpdate saw it as identical and skipped build()
        // -> the counters were only read at app launch and went stale during the session
        // (after a discussion or reading) (proven on device). A ValueKey tied to the
        // selected tab state recreates the element when Report becomes visible -> fresh
        // read; it does not rebuild while hidden (no wasted work in the IndexedStack).
        NavTab.report => ReportScreen(
          key: ValueKey(_store.tab == NavTab.report),
        ),
      },
    );
  }

  List<Book> _libraryBooks(BuildContext context) {
    final services = AppServicesScope.of(context);
    final raw = services.prefs.getString('books_v1') ?? '[]';
    final books = decodeBooks(raw);
    // The Reader writes progress as progress_<hash> (current PAGE number); the library
    // shows Book.progressPercent. These two sources were NEVER synced before -> a book
    // being read always showed 0% in the library (field finding). Merged at read time
    // (the write path is unchanged): current page / total pages -> percent.
    return books.map((b) {
      final page = services.prefs.getInt('progress_${b.hash}');
      if (page == null || b.totalPages <= 0) return b;
      final percent = ((page / b.totalPages) * 100).round();
      return b.withProgress(percent);
    }).toList();
  }
}
