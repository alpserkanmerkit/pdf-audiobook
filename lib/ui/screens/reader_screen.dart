import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sesli_kitap/io/llm_explanation.dart';
import 'package:sesli_kitap/io/page_pipeline.dart';
import 'package:sesli_kitap/src/audio_position.dart';
import 'package:sesli_kitap/src/explanation/explanation.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/src/prefetch_policy.dart';
import 'package:sesli_kitap/src/pronunciation_rules.dart';
import 'package:sesli_kitap/src/reader_highlight_view.dart';
import 'package:sesli_kitap/src/reader_machine.dart';
import 'package:sesli_kitap/src/reading_stats.dart';
import 'package:sesli_kitap/src/sentence_split.dart';
import 'package:sesli_kitap/src/sentence_timing.dart';
import 'package:sesli_kitap/src/voices.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';
import 'package:sesli_kitap/ui/widgets/explanation_sheet.dart';
import 'package:sesli_kitap/ui/widgets/min_tap_area.dart';

/// Test hook: produces the reader's Stopwatch instances (the karaoke fallback
/// page clock + the listening-time counter). The production default is the
/// REAL wall-clock [Stopwatch] (do not change); tests inject the fake-async
/// clock (`tester.binding.clock.stopwatch`) so that `pump(duration)` advances
/// time -- no need to wait for real seconds.
@visibleForTesting
Stopwatch Function() readerStopwatchFactory = Stopwatch.new;

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    required this.sentences,
    super.key,
    this.book,
    this.pipeline,
    this.pipelineFailed = false,
    this.onBack,
    this.onAttachPauseHandle,
  });
  final List<String> sentences;
  final Book? book;
  final PagePipeline? pipeline;

  /// AppShell could not set up the reading pipeline (file read failed / parse
  /// error). A pending Play request in the queue is dropped and a visible
  /// error is shown.
  final bool pipelineFailed;
  final VoidCallback? onBack;

  /// Gives AppShell a synchronous callback to really stop the playing audio
  /// when switching tabs or pressing back (see
  /// [_ReaderScreenState._suspendForNavigation]).
  ///
  /// WHY this is needed (device finding): AppShell used to stop
  /// AppServices.readerPlayer DIRECTLY -- but GuardedAudioPlayer.stop()
  /// deliberately raises the same "finished" signal as pause() (K20
  /// playToCompletion contract), so an interruption that does not go through
  /// ReaderScreen's own _playGeneration/_readerState bookkeeping was taken as
  /// "page finished naturally", and reader_machine prepared and started the
  /// next page automatically -- even after switching tabs it would play in
  /// the background forever. This callback lets AppShell route the stop
  /// through ReaderScreen's own interruption marking (race-free, called
  /// synchronously).
  final ValueChanged<VoidCallback>? onAttachPauseHandle;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  ReaderState _readerState = ReaderState.initial();
  int _playGeneration = 0;
  int _speedIndex = 1;
  int _sentenceIndex = 0;
  String? _lastPreparedAudioPath;

  /// Karaoke timing sidecar of the prepared page (PR-K1 produces it, PR-K2
  /// consumes it). On a successful prepareAudio it is filled in the SAME
  /// setState as [_lastPreparedAudioPath]; it is nulled together with it on
  /// page change/skip. When null (old mp3 without a sidecar, or not arrived
  /// yet) the tick falls back to the length-weighted estimate. If the sentence
  /// count is MISMATCHED (clean-text/sidecar drift) the tick also uses the
  /// fallback.
  SentenceTimings? _pageTimings;

  /// Monotonic audio-preparation generation (adversarial-review F1/F2; the
  /// audio-path counterpart of the [_loadGeneration] pattern). If the page
  /// changes while the prepareAudio -> cachedTimings await chain is IN FLIGHT,
  /// a late-resolving result could write the OLD page's path/timing into the
  /// NEW page: every preparation start takes and increments a token, and every
  /// invalidation point (page change, skip, machine setup) also increments;
  /// after the awaits, setState happens only if the token is STILL current.
  /// If the sentence counts happen to match, the startsMs-length guard in the
  /// tick is MASKED -- this token closes that gap. It is NOT reset in
  /// [_initMachine] (stays monotonic): the old machine's in-flight preparation
  /// can never claim a token in the new machine.
  int _prepareGeneration = 0;
  Timer? _sentenceTimer;
  Stopwatch? _pageStopwatch;
  final Stopwatch _listeningStopwatch = readerStopwatchFactory();
  int? _currentDisplayPage;
  List<String> _currentSentences = [];

  /// Bug-I (2026-07-04, FAZ-3 acceptance review finding): the karaoke highlight
  /// correctly follows the REAL audio position (_sentenceIndex =
  /// narratingIndexAt(...)) but the body had no ScrollController/ensureVisible
  /// at all -- on a long page (19-24 sentences) the highlighted sentence went
  /// out of view below the fold as the audio advanced. This controller is
  /// attached to the body SingleChildScrollView. Auto-scroll is triggered ONLY
  /// when _sentenceIndex CHANGES while playback is active (see
  /// _maybeAutoScrollToSentence below), not on every tick -- so the user's
  /// MANUAL scroll (when paused / touching) is not overridden.
  final ScrollController _scrollController = ScrollController();

  /// GlobalKey for each sentence Container (the Scrollable.ensureVisible
  /// target). When the sentence list changes (page/skip) [_sentenceKeys] is
  /// regenerated as well (see _keysFor) -- the old page's keys never mix with
  /// the new page's context.
  List<GlobalKey> _sentenceKeys = [];

  /// Sentence count [_sentenceKeys] was last generated for -- to rebuild the
  /// list only when the length changes, not on every build.
  int _sentenceKeysLength = -1;

  /// Index auto-scroll was last triggered for -- do not trigger again for the
  /// same index (only when the index CHANGES, not on every tick).
  int? _lastAutoScrolledIndex;

  /// The current page's clean text is NOT in the cache yet (not generated) ->
  /// the body shows a placeholder ("This page has not been prepared yet");
  /// stale text is NOT kept.
  bool _pageNotReady = false;

  /// Monotonic content-load generation. [_loadPageContent] is async
  /// (cachedCleanText disk I/O), so during rapid successive skips several calls
  /// can be IN FLIGHT and their resolution order is NOT guaranteed. Each call
  /// increments it at the start; the .then body calls setState only if ITS
  /// generation is still current -- so a late-resolving stale call cannot
  /// overwrite the content/placeholder of a freshly loaded page (race guard,
  /// adversarial-review finding).
  int _loadGeneration = 0;
  bool _initialized = false;

  /// "Ask" explanation-audio generation token (adversarial-review finding; the
  /// SAME idiom as F1/F2). Incremented on every long-press and every sheet
  /// close; _speakExplanation reaches discussionPlayer.playFile only if the
  /// token it was given is still current.
  int _explanationGeneration = 0;

  static const List<String> speedLabels = [
    '0,75×',
    '1×',
    '1,25×',
    '1,5×',
    '2×',
  ];
  static const List<double> speedValues = [0.75, 1.0, 1.25, 1.5, 2.0];

  AppServices? _servicesCache;
  AppServices get _services => _servicesCache ??= AppServicesScope.of(context);

  /// Adds the listening time to the 'listening_ms' key in SharedPreferences
  /// and resets the stopwatch. To avoid double counting, it only writes a
  /// positive duration.
  void _flushListeningTime() {
    if (_listeningStopwatch.isRunning) {
      _listeningStopwatch.stop();
    }
    final elapsed = _listeningStopwatch.elapsedMilliseconds;
    if (elapsed > 0) {
      _listeningStopwatch.reset();
      final prefs = _servicesCache?.prefs ?? _services.prefs;
      final current = prefs.getInt('listening_ms') ?? 0;
      unawaited(prefs.setInt('listening_ms', current + elapsed));
    }
  }

  /// Center Play was pressed while the pipeline was not set up yet (AppShell is
  /// reading the file + isolate): the request waits in the queue, and
  /// [didUpdateWidget] runs it once when the pipeline arrives. A second press
  /// cancels it; it is cleared when the book changes or on dispose.
  bool _playQueued = false;

  @override
  void initState() {
    super.initState();
    widget.onAttachPauseHandle?.call(_suspendForNavigation);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _servicesCache = AppServicesScope.of(context);
    if (!_initialized) {
      _initialized = true;
      _initMachine();
    }
  }

  @override
  void didUpdateWidget(covariant ReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Book changed -> any pending Play request left from the previous book is
    // dropped.
    if (oldWidget.book != widget.book) _playQueued = false;
    if (oldWidget.book != widget.book ||
        oldWidget.pipeline != widget.pipeline) {
      _initMachine();
    }
    // Pipeline setup failed: the queue is released (the hourglass does not
    // spin forever) and a visible error is shown to the user.
    if (widget.pipelineFailed &&
        !oldWidget.pipelineFailed &&
        widget.pipeline == null) {
      if (_playQueued) {
        _playQueued = false;
        // ScaffoldMessenger cannot be changed during build -> after the frame.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showNotice(_pipelineFailedMsg, _failedDuration);
        });
      }
      return;
    }
    // The pipeline was just set up and the user had pressed Play during
    // preparation: the request runs ONCE via the same path (TogglePressed ->
    // PrepareAudio). The machine was set up with BookLoaded in _initMachine.
    if (_playQueued && widget.pipeline != null) {
      _playQueued = false;
      // The "Preparing" message is now wrong: the pipeline is ready, playback
      // is starting. (ScaffoldMessenger cannot be changed during build -> after
      // the frame.)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
      });
      _dispatch(TogglePressed());
    }
  }

  @override
  void dispose() {
    _playQueued = false;
    _flushListeningTime();
    _sentenceTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _initMachine() {
    _readerState = ReaderState.initial();
    _playGeneration = 0;
    _lastPreparedAudioPath = null;
    _pageTimings = null;
    // INCREMENT, do not RESET: so the old machine's in-flight preparation (if
    // any) cannot claim a token in the new machine (F1 generation guard, see
    // the field comment).
    _prepareGeneration++;
    _sentenceTimer?.cancel();
    _sentenceTimer = null;
    _pageStopwatch = null;
    _currentDisplayPage = null;
    _currentSentences = [];
    _sentenceIndex = 0;
    // Bug-I regression (adversarial-review #69): new machine/book -> clear the
    // auto-scroll suppression guard (if the new book's first page happens to
    // have the same sentence count, a stale guard must not remain).
    _lastAutoScrolledIndex = null;
    _pageNotReady = false;

    if (widget.book != null && widget.pipeline != null) {
      final totalPages = widget.book!.totalPages;
      final startPage =
          _services.prefs.getInt('progress_${widget.book!.hash}') ?? 1;
      final clampedStart = startPage.clamp(1, totalPages);
      final result = transition(
        _readerState,
        BookLoaded(totalPages: totalPages, startPage: clampedStart),
      );
      setState(() {
        _readerState = result.state;
      });
      _executeCommands(result.commands);
      _loadPageContent(clampedStart);
    }
  }

  void _loadPageContent(int page) {
    if (widget.pipeline == null) return;
    final gen = ++_loadGeneration;
    final pending = widget.pipeline!.cachedCleanText(page).then((cleanText) {
      // Race guard: proceed only if THIS call is still the latest load. A
      // late-resolving stale call (invalidated by a newer skip) does no
      // setState -> it does NOT overwrite the fresh content/placeholder.
      if (!mounted || gen != _loadGeneration) return;
      if (cleanText != null) {
        setState(() {
          _currentDisplayPage = page;
          _currentSentences = splitIntoSentences(cleanText);
          _sentenceIndex = 0;
          // Bug-I regression (adversarial-review #69): when the page changes
          // _sentenceIndex returns to 0, but if the auto-scroll suppression
          // guard (_lastAutoScrolledIndex) is NOT reset, and two consecutive
          // pages have the SAME sentence count (_sentenceKeysLength does not
          // change -> _keysFor does not reset), the scroll for the highlight
          // advancing to the same index on the new page is SILENTLY
          // suppressed. Clear the guard when the content changes.
          _lastAutoScrolledIndex = null;
          _pageNotReady = false;
        });
      } else {
        // Cache miss: this page's clean text has NOT been generated yet. Do NOT
        // leave the previous page's sentences on screen (stale-text bug H-A1)
        // -- clear them and switch to the "preparing" placeholder. When the
        // text is generated (prepare finishes) _loadPageContent is called again
        // (H-A2).
        setState(() {
          _currentDisplayPage = page;
          _currentSentences = [];
          _sentenceIndex = 0;
          // Bug-I regression (adversarial-review #69): content changed ->
          // clear the auto-scroll suppression guard (same reason as the branch
          // above).
          _lastAutoScrolledIndex = null;
          _pageNotReady = true;
        });
      }
    });
    unawaited(pending);
  }

  void _executeCommands(List<Object> commands) {
    for (final cmd in commands) {
      if (cmd is PrepareAudio) {
        unawaited(_executePrepareAudio(cmd.page));
      } else if (cmd is SaveProgress) {
        _executeSaveProgress(cmd.page);
      } else if (cmd is PlayAudio) {
        _executePlayAudio();
      } else if (cmd is PauseAudio) {
        _executePauseAudio();
      } else if (cmd is Prefetch) {
        _executePrefetch(cmd.fromPage);
      }
    }
  }

  Future<void> _executePrepareAudio(int page) async {
    if (widget.pipeline == null) return;
    // F1 generation token: taken BEFORE the awaits. A page change/skip/new
    // preparation increments the generation; below, fields are written only if
    // the token is still current (a late-resolving stale preparation cannot
    // corrupt the new page; t27).
    final gen = ++_prepareGeneration;
    try {
      final settings = _pipelineSettingsFromReadingSettings();
      final file = await widget.pipeline!.prepareAudio(page, settings);
      // Karaoke sidecar (PR-K2): if it could be produced, prepareAudio also
      // wrote the sentence-timing sidecar. Fetch it from the audio path with the
      // SAME settings and assign it in the SAME setState as
      // _lastPreparedAudioPath -> audio + timing are one atomic update (the
      // timer sees both consistently). If there is no sidecar, null (fallback).
      final timings = await widget.pipeline!.cachedTimings(page, settings);
      if (mounted && gen == _prepareGeneration) {
        setState(() {
          _lastPreparedAudioPath = file.path;
          _pageTimings = timings;
        });
      }
      // Bug-F (residual phase-switch window, 2026-07-05): dispatch is NO LONGER
      // token-less. The earlier assumption ("a stale PrepareSucceeded is already
      // swallowed by the phase lock of _suspendForNavigation") only held when
      // "the skipped page did not start any new preparation". If page 1 is still
      // preparing, the user skips to page 2 and ENTERS preparing again for page
      // 2, reader_machine.dart transition() only looks at the PHASE (phase ==
      // preparing) -- it does not know which page/generation it is. So page 1's
      // late, stale PrepareSucceeded could ACCEPT page 2's (different generation)
      // preparing phase and move it to playing early -- while
      // _lastPreparedAudioPath is still null (page 2's real preparation has not
      // finished), _executePlayAudio silently becomes a no-op, play() is never
      // called, and the phase stays "playing" forever (pause icon shown, audio
      // never starts). Fix: PrepareSucceeded/PrepareFailed dispatch is ALSO tied
      // to the SAME condition with the token guard (gen == _prepareGeneration) --
      // a stale event can no longer trigger a phase transition.
      if (mounted && gen == _prepareGeneration) {
        _dispatch(PrepareSucceeded());
      }
      // prepareAudio also wrote the clean text to the cache (via prepareText).
      // If the prepared page is still the one on screen AND the body is still
      // on the placeholder (it was skipped with a cache miss), load the fresh
      // text now (H-A2: audio plays but no text bug). Only called while really
      // on the placeholder -> no double setState/loop in the normal playback
      // flow.
      if (mounted &&
          gen == _prepareGeneration &&
          _pageNotReady &&
          page == _readerState.currentPage &&
          _readerState.phase != ReaderPhase.preparing) {
        _loadPageContent(page);
      }
    } on Object catch (e) {
      // Same Bug-F class: a stale error too (the old page's prepare failed, but
      // a different page/generation is now in preparing) could drop the phase
      // wrongly to ready -- the same guard applies here.
      if (mounted && gen == _prepareGeneration) {
        _dispatch(PrepareFailed(e.toString()));
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Preparation error: $e')));
      }
    }
  }

  void _executeSaveProgress(int page) {
    unawaited(_services.prefs.setInt('progress_${widget.book!.hash}', page));
    _recordReadingDay();
  }

  /// Adds today to the 'reading_days' list (for the reading-streak counter). The
  /// same day is not added twice; the list is capped at the last 400 days
  /// (guard against unbounded growth).
  void _recordReadingDay() {
    final key = dayKey(DateTime.now());
    final days = _services.prefs.getStringList('reading_days') ?? <String>[];
    if (days.contains(key)) return;
    days.add(key);
    if (days.length > 400) {
      days.removeRange(0, days.length - 400);
    }
    unawaited(_services.prefs.setStringList('reading_days', days));
  }

  /// A3 (resume where you left off): prefs key for the saved audio position of
  /// the current page. It is kept only for the LAST page (when the page changes
  /// the old one becomes meaningless -- shouldResumeAt already returns null on a
  /// different page, and this key is also deleted on AudioCompleted).
  String get _audioPosKey => 'audiopos_${widget.book!.hash}';

  /// Writes the current playback position (if any) under [_audioPosKey] as
  /// "page:ms". If the position is not loaded yet (null -- like an interruption
  /// in the preparing phase) it does NOT write (see the
  /// GuardedAudioPlayer.currentPosition contract: READ-ONLY, independent of
  /// native transitions, null even after dispose).
  void _savePlaybackPosition() {
    final pos = _services.readerPlayer.currentPosition;
    if (pos == null) return;
    unawaited(
      _services.prefs.setString(
        _audioPosKey,
        formatAudioPos(page: _readerState.currentPage, pos: pos),
      ),
    );
  }

  /// Clears the saved in-page position (when the page finishes naturally --
  /// AudioCompleted -- there is no "half-done" position left to resume).
  void _clearPlaybackPosition() {
    unawaited(_services.prefs.remove(_audioPosKey));
  }

  void _executePlayAudio() {
    final path = _lastPreparedAudioPath;
    if (path == null) return;
    final gen = _playGeneration;
    // A3: the saved position is used as the resume point ONLY if it is on the
    // same page and above the threshold (shouldResumeAt rule); otherwise
    // playback starts from the beginning -- the old behavior is kept EXACTLY
    // (startAt null -> JustAudioOps.setFilePath is called without
    // initialPosition).
    final saved = parseAudioPos(_services.prefs.getString(_audioPosKey));
    final startAt = saved == null
        ? null
        : shouldResumeAt(
            savedPage: saved.page,
            currentPage: _readerState.currentPage,
            savedPos: saved.pos,
          );
    final pending = _services.readerPlayer
        .playFile(path, startAt: startAt)
        .then(
          (_) {
            if (gen == _playGeneration &&
                _readerState.phase == ReaderPhase.playing) {
              _flushListeningTime();
              _clearPlaybackPosition();
              _dispatch(AudioCompleted());
            }
          },
          onError: (Object e, StackTrace st) {
            _flushListeningTime();
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Playback error: $e')));
            }
          },
        );
    unawaited(pending);
    if (_pageStopwatch == null) {
      _pageStopwatch = readerStopwatchFactory()..start();
    } else {
      _pageStopwatch!.start();
    }
    _flushListeningTime();
    _listeningStopwatch.start();
    _startSentenceTimer();
  }

  void _executePauseAudio() {
    _playGeneration++;
    _flushListeningTime();
    _savePlaybackPosition();
    unawaited(_services.readerPlayer.stop());
    _pageStopwatch?.stop();
    _sentenceTimer?.cancel();
  }

  /// Called SYNCHRONOUSLY from AppShell (tab switch / back button). Same order
  /// as _executePauseAudio (first increment the generation, THEN stop) -- so
  /// when playFile's future, resolved by the interruption, reaches the
  /// .then() callback, the generation mismatch is ALREADY in place (no race:
  /// everything happens in one synchronous call stack). In the preparing phase
  /// TogglePressed is a no-op (see reader_machine.dart) -- so the phase is set to
  /// paused BY HAND here, and a late PrepareSucceeded/PrepareFailed is silently
  /// swallowed because the phase does not match.
  ///
  /// A3: the position is saved here too, for the same reason as
  /// _executePauseAudio -- a tab switch / back press is also an interruption
  /// that creates the expectation of "resume where you left off" (not only the
  /// Toggle pause).
  void _suspendForNavigation() {
    final phase = _readerState.phase;
    if (phase != ReaderPhase.playing && phase != ReaderPhase.preparing) return;
    _playGeneration++;
    _flushListeningTime();
    if (phase == ReaderPhase.playing) _savePlaybackPosition();
    _pageStopwatch?.stop();
    _sentenceTimer?.cancel();
    unawaited(_services.readerPlayer.stop());
    setState(() {
      _readerState = ReaderState(
        ReaderPhase.paused,
        _readerState.currentPage,
        _readerState.totalPages,
      );
    });
  }

  void _executePrefetch(int fromPage) {
    final total = widget.book?.totalPages ?? 0;
    if (widget.pipeline == null || total == 0) return;
    final pages = nextPrefetchBlock(
      currentPage: fromPage,
      totalPages: total,
      ready: {},
    );
    final settings = _pipelineSettingsFromReadingSettings();
    for (final page in pages) {
      // fire-and-forget prefetch; swallow errors silently
      final pending = () async {
        try {
          await widget.pipeline!.prepareAudio(page, settings);
        } on Object catch (_) {
          // best-effort prefetch; an error must not affect the current playback
        }
      }();
      unawaited(pending);
    }
  }

  void _dispatch(Object event) {
    final result = transition(_readerState, event);
    setState(() {
      _readerState = result.state;
      final newPage = result.state.currentPage;
      if (newPage != _currentDisplayPage && widget.pipeline != null) {
        _currentDisplayPage = newPage;
        _loadPageContent(newPage);
        _flushListeningTime();
        _pageStopwatch?.reset();
        _sentenceIndex = 0;
        // Bug-I regression (adversarial-review #69): page changed -> clear the
        // auto-scroll suppression guard (if the same index advances on a
        // consecutive page with the same sentence count, the scroll must not be
        // suppressed).
        _lastAutoScrolledIndex = null;
        // The new page's audio/timing is NOT ready yet: invalidate the stale
        // sidecar (of the previous page) -> the tick falls back until
        // _executePrepareAudio fetches the fresh sidecar. If a preparation is in
        // flight, its token is also invalidated (F1: a late result cannot be
        // written to this new page).
        _pageTimings = null;
        _prepareGeneration++;
      }
    });
    _executeCommands(result.commands);
  }

  void _startSentenceTimer() {
    _sentenceTimer?.cancel();
    _sentenceTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_readerState.phase != ReaderPhase.playing) return;
      if (_currentSentences.isEmpty) return;

      // (1) POSITION: the karaoke highlight must advance according to the REAL
      // audio position (field finding: wall-clock / fixed assumption -> highlight
      // out of sync with the audio; especially on pause the wall clock keeps
      // moving while the position stays frozen). just_audio gives the position
      // READ-ONLY via currentPosition. If it is NOT LOADED YET (null), the old
      // Stopwatch is ONLY a fallback -- the real position arrives a few ticks
      // later.
      final pos = _services.readerPlayer.currentPosition;
      final elapsed = pos ?? _pageStopwatch?.elapsed ?? Duration.zero;

      // (2) TIMING: if the PR-K1 sidecar (real sentence times produced from word
      // boundaries) exists and is COMPATIBLE with the sentence count, use it. If
      // it is incompatible (clean-text/sidecar drift) or absent, fall back to the
      // length-weighted proportional estimate (with equal lengths it gives the
      // same result as the old uniform one).
      final t = _pageTimings;
      final effective =
          (t != null && t.startsMs.length == _currentSentences.length)
          ? t
          : timingsFromSentenceLengths(
              sentences: _currentSentences,
              // currentDuration ?? 30s; timingsFromSentenceLengths throws
              // ArgumentError at totalMs<=0 -> always give a positive value.
              totalMs: _estimatedPageTotalMs(),
            );
      if (effective == null) return;

      final newIndex = narratingIndexAt(timings: effective, position: elapsed);
      final indexChanged = newIndex != _sentenceIndex;
      setState(() {
        _sentenceIndex = newIndex;
      });
      // Bug-I: scroll the body ONLY when the index actually CHANGES (not on
      // every tick) -- so we do not needlessly override the user's manual
      // scroll.
      if (indexChanged) {
        _maybeAutoScrollToSentence(newIndex);
      }
    });
  }

  /// Scrolls the sentence at [index] into view (via its key, if any). Triggered
  /// ONLY while playback is active (ReaderPhase.playing) -- on pause / manual
  /// scroll the user's position is NOT forced. If the key does not exist yet
  /// (a frame may be needed after build), it is deferred with
  /// postFrameCallback.
  void _maybeAutoScrollToSentence(int index) {
    if (_readerState.phase != ReaderPhase.playing) return;
    if (_lastAutoScrolledIndex == index) return;
    _lastAutoScrolledIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (index < 0 || index >= _sentenceKeys.length) return;
      final ctx = _sentenceKeys[index].currentContext;
      if (ctx == null) return;
      unawaited(
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          alignment: 0.3,
          curve: Curves.easeInOut,
        ),
      );
    });
  }

  /// Regenerates [_sentenceKeys] for the given [length] if needed (if the length
  /// changed -- all keys are regenerated so that old keys after a page/skip do
  /// not mix with the new sentence list).
  List<GlobalKey> _keysFor(int length) {
    if (_sentenceKeysLength != length) {
      _sentenceKeys = List.generate(length, (_) => GlobalKey());
      _sentenceKeysLength = length;
      _lastAutoScrolledIndex = null;
    }
    return _sentenceKeys;
  }

  /// Total page duration (ms) for the length-weighted fallback, always positive.
  /// If the player reports the REAL duration (currentDuration) it is used;
  /// otherwise the old 30s estimate is used. timingsFromSentenceLengths throws
  /// at totalMs<=0.
  int _estimatedPageTotalMs() {
    final dur = _services.readerPlayer.currentDuration;
    if (dur != null && dur > Duration.zero) return dur.inMilliseconds;
    return const Duration(seconds: 30).inMilliseconds;
  }

  /// Phase 2 (English TTS support): the ENTIRE decision of which voice+provider
  /// to use lives in resolveReadingVoice (lib/src, pure, unit-tested) -- this is
  /// a thin wrapper. If widget.book.language is 'en', the provider automatically
  /// switches to google (English voices currently exist only there).
  PipelineSettings _pipelineSettingsFromReadingSettings() {
    final r = _services.reading;
    final resolved = resolveReadingVoice(
      bookLanguage: widget.book?.language ?? 'tr',
      preferredVoiceId: r.voice,
      preferredProvider: r.provider,
      preferredEnglishVoiceId: r.voiceEn,
    );
    return PipelineSettings(
      geminiKey: r.geminiKey,
      voice: resolved.voice,
      rate: r.rate,
      provider: resolved.provider,
      googleKey: r.googleKey,
      llmAccess: r.llmAccess,
      pronRules: parsePronRules(r.pronRulesRaw),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final book = widget.book;
    final pipeline = widget.pipeline;

    if (book == null) {
      return SafeArea(
        child: Column(
          children: [
            _buildTopBar(palette, book),
            Expanded(child: _buildEmptyState(palette)),
          ],
        ),
      );
    }

    final sentences = (_currentSentences.isNotEmpty && pipeline != null)
        ? _currentSentences
        : widget.sentences;
    final fileMissing =
        book.filePath.isNotEmpty && !File(book.filePath).existsSync();

    return SafeArea(
      child: Column(
        children: [
          if (fileMissing)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red),
                  SizedBox(width: 8),
                  // Flexible: does not overflow on a narrow screen + large text
                  // scale (test/reader_overflow_test.dart, 320 px / 1.3).
                  Flexible(
                    child: Text(
                      'File not found',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          _buildTopBar(palette, book),
          _buildKicker(palette),
          if (_pageNotReady && pipeline != null)
            Expanded(child: _buildPageNotReady(palette))
          else
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(sentences.length, (i) {
                    final sentenceKeys = _keysFor(sentences.length);
                    final state = visualStateFor(
                      index: i,
                      narratingIndex: _sentenceIndex,
                      highlightedIndexes: {},
                    );
                    final Color textColor;
                    final Color? bgColor;
                    switch (state) {
                      case SentenceVisualState.narrating:
                      case SentenceVisualState.highlighted:
                        textColor = palette.accent;
                        bgColor = palette.accentSoft;
                      case SentenceVisualState.plain:
                        textColor = palette.text2;
                        bgColor = null;
                    }
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _sentenceIndex = i;
                        });
                      },
                      onLongPress: () => _onSentenceLongPress(sentences, i),
                      child: Container(
                        key: sentenceKeys[i],
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 8,
                        ),
                        decoration: bgColor != null
                            ? BoxDecoration(
                                color: bgColor.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(4),
                              )
                            : null,
                        child: Text(
                          sentences[i],
                          style: TextStyle(
                            fontSize: 17,
                            color: textColor.withValues(alpha: 1),
                            height: 1.5,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          _buildProgress(palette, sentences.length, book),
          _buildControlBar(palette),
        ],
      ),
    );
  }

  /// Placeholder shown while the current page's clean text has not been
  /// generated yet (cache miss). Instead of stale/previous-page text, it gives a
  /// clear "preparing" state; the user-visible text MUST contain exactly "This
  /// page has not been prepared yet" (the text freshness test t21 expects it).
  ///
  /// Bug-H (device finding, landscape mode): the natural height of this Column
  /// can, in a landscape/short viewport, be larger than the space the Expanded
  /// above can leave (e.g. 37.7px) -> RenderFlex "bottom overflowed" error.
  /// SingleChildScrollView scrolls the content that does not fit instead of
  /// overflowing (visual design unchanged -- in normal/portrait mode it fits, so
  /// no scrolling is needed).
  Widget _buildPageNotReady(AppPalette palette) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_empty, size: 40, color: palette.text3),
              const SizedBox(height: 12),
              Text(
                'This page has not been prepared yet',
                style: TextStyle(fontSize: 15, color: palette.text2),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Once playback starts, the text of this page will be prepared and '
                'shown here.',
                style: TextStyle(fontSize: 13, color: palette.text3),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppPalette palette) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book, size: 40, color: palette.text3),
            const SizedBox(height: 12),
            Text(
              'No book is open yet',
              style: TextStyle(fontSize: 15, color: palette.text2),
            ),
            const SizedBox(height: 4),
            Text(
              'Open a book from the library to start listening.',
              style: TextStyle(fontSize: 13, color: palette.text3),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(AppPalette palette, Book? book) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: palette.accent),
            tooltip: 'Back',
            onPressed: widget.onBack ?? () => Navigator.maybePop(context),
          ),
          // Field (device, 2026-09-28): the title had UNBOUNDED width between two
          // Spacers; because the book name comes from the PDF file name it can be
          // long ("Sigmund Freud - Rüyaların Yorumu (Tam Metin)") -> "RIGHT
          // OVERFLOWED BY 251 PIXELS". Fixed with Expanded + single line + ellipsis.
          Expanded(
            child: book != null
                ? Column(
                    children: [
                      Text(
                        book.chapterLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: palette.accent,
                        ),
                      ),
                      Text(
                        book.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: palette.text2),
                      ),
                    ],
                  )
                : Text(
                    'Reader',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: palette.accent,
                    ),
                  ),
          ),
          // Empty space the width of the back button: the title stays in the
          // middle of the screen (same centering as the old two-Spacer layout).
          const SizedBox(width: kMinInteractiveDimension),
        ],
      ),
    );
  }

  Widget _buildKicker(AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            'NARRATING —',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: palette.accent,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(AppPalette palette, int totalSentences, Book? book) {
    final progress = totalSentences > 1
        ? _sentenceIndex / (totalSentences - 1)
        : 0.0;
    if (book == null) {
      return const SizedBox.shrink();
    }
    // If the machine is set up (pipeline present -> BookLoaded -> phase is not
    // idle), the current page is read from the STATE MACHINE, so a manual skip
    // (PageEntered) shows immediately. If the machine is not set up (pipeline
    // null: file missing / being set up) the old behavior is kept -> from the
    // progress_<hash> prefs (backward-compat boundary for t4/t5).
    final pageNumber = _readerState.phase == ReaderPhase.idle
        ? (_services.prefs.getInt('progress_${book.hash}') ?? 1)
        : _readerState.currentPage;
    final progressText = 'Page $pageNumber / ${book.totalPages}';
    final canSelect = widget.pipeline != null && book.totalPages > 1;
    return GestureDetector(
      key: const Key('page-indicator'),
      behavior: HitTestBehavior.opaque,
      onTap: canSelect ? () => _showPageSelector(book) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              progressText,
              style: TextStyle(fontSize: 12, color: palette.text2),
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: palette.text2.withValues(alpha: 0.2),
              color: palette.accent,
              minHeight: 3,
            ),
          ],
        ),
      ),
    );
  }

  /// Goes to a specific page. While PLAYING/PREPARING it first goes through the
  /// owner's SYNCHRONOUS interruption path (_suspendForNavigation: increment the
  /// generation, then stop, set the phase to paused) -- so the PR#34 race (an
  /// interrupted playFile mistaken for a fake completion that auto-advances)
  /// does NOT happen. Then PageEntered is dispatched; the machine changes the
  /// page in the ready/paused/finished phases (it produces NO commands --
  /// re-preparation is left to the user's Toggle).
  void _navigateToPage(int page) {
    final total = _readerState.totalPages > 0
        ? _readerState.totalPages
        : (widget.book?.totalPages ?? 1);
    final target = page.clamp(1, total);
    if (target == _readerState.currentPage) return;
    final phase = _readerState.phase;
    if (phase == ReaderPhase.playing || phase == ReaderPhase.preparing) {
      _suspendForNavigation();
    }
    _dispatch(PageEntered(target));
    // The skipped page's audio is NOT ready YET. Invalidate the stale
    // _lastPreparedAudioPath (the previous page's audio); otherwise the
    // `paused -> Toggle` shortcut (PlayAudio, NOT PrepareAudio) would play the
    // previous page's audio AGAIN and, after AudioCompleted, one page would be
    // SKIPPED (adversarial-review finding). By switching the paused phase to
    // `ready`, the next Toggle produces PrepareAudio(skipped page) (ready/finished
    // already re-prepare on Toggle; only the paused shortcut was unsafe).
    _lastPreparedAudioPath = null;
    // The previous page's karaoke sidecar is also invalid together with the stale
    // audio path -> set it to null (the skipped page gets a fresh sidecar on
    // re-preparation; _dispatch(PageEntered) also nulls it on the page-change
    // branch -- it is re-confirmed here by hand for the paused-shortcut path).
    // The preparation token in flight is also invalidated (F1 generation guard,
    // same reasoning).
    _pageTimings = null;
    _prepareGeneration++;
    if (_readerState.phase == ReaderPhase.paused) {
      setState(() {
        _readerState = ReaderState(
          ReaderPhase.ready,
          _readerState.currentPage,
          _readerState.totalPages,
        );
      });
    }
  }

  /// "Ask" (long-press on a sentence): first the playing/preparing audio is
  /// stopped through ReaderScreen's OWN synchronous interruption path
  /// (_suspendForNavigation -- the SAME contract as a tab switch/skip, the PR#34
  /// race does not occur), then the explanation bottom sheet opens. If the Gemini
  /// key is empty, the LLM is NOT called at all; a friendly guidance message is
  /// shown instead (same empty-key contract as the other LLM features).
  ///
  /// The key check is intentionally done BEFORE the suspend call (adversarial-review
  /// finding, pinned test): if the sheet is not going to open anyway, pausing the
  /// playing audio has no benefit -- it would only interrupt the user for nothing.
  Future<void> _onSentenceLongPress(List<String> sentences, int index) async {
    if (!_services.reading.askEnabled) return;
    if (index < 0 || index >= sentences.length) return;
    final access = _services.reading.llmAccess;
    if (!access.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A Gemini API key is required for the Ask feature. '
            'Enter it under Settings > ACCOUNT & API.',
          ),
        ),
      );
      return;
    }
    final phase = _readerState.phase;
    if (phase == ReaderPhase.playing || phase == ReaderPhase.preparing) {
      _suspendForNavigation();
    }
    // Explanation-audio generation token (the SAME idiom as
    // _prepareGeneration/_playGeneration): INCREMENTED when the sheet closes. If
    // a synthesis/speech is in flight (adversarial-review finding: unawaited
    // speak() is independent of the sheet's lifecycle), this token prevents a
    // late-resolving result from starting to play with NO owner (see the
    // _speakExplanation guard).
    final gen = ++_explanationGeneration;
    final sentence = sentences[index];
    final contextText = contextWindow(sentences, index);
    final llm = LlmExplanation(access: access);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ExplanationSheet(
        sentence: sentence,
        fetchExplanation: ({required String target, required bool isWord}) =>
            llm.fetch(
              target: target,
              isWord: isWord,
              sentence: sentence,
              contextText: contextText,
            ),
        speak: (text) => _speakExplanation(text, generation: gen),
      ),
    );
    // The sheet closed -> this explanation session is now STALE (the token is
    // invalidated, so any in-flight synthesis can never reach playFile), and the
    // playing audio (if any) is stopped (stop is queued and idempotent; when
    // nothing is playing it is a no-op pause).
    _explanationGeneration++;
    await _services.discussionPlayer.stop();
  }

  /// Speaks the explanation with the user's selected TTS provider and voice --
  /// the proven path of the discussion feature (cache.writeAudio ->
  /// discussionPlayer.playFile -> best-effort delete). It does NOT touch
  /// readerPlayer: the reading-state bookkeeping (phase/generation) is not
  /// disturbed (GuardedAudioPlayer is a separate instance). Same contract as the
  /// reading pipeline: the text to be spoken also goes through applyPronRules
  /// (same as prepareAudio in page_pipeline.dart -- the user's pronunciation
  /// dictionary must apply to explanation audio too).
  ///
  /// [generation]: the token obtained by [_onSentenceLongPress]. When the sheet
  /// closes (_explanationGeneration is incremented) and the token is NO LONGER
  /// current after these awaits, playFile is NOT called at all -- so audio with
  /// no owner that cannot be stopped (adversarial-review finding) cannot be
  /// created.
  Future<void> _speakExplanation(String text, {required int generation}) async {
    final settings = _pipelineSettingsFromReadingSettings();
    final tts = resolveTtsProvider(settings);
    final spoken = applyPronRules(text, settings.pronRules);
    final bytes = await tts.synthesize(
      text: spoken,
      voice: settings.voice,
      rate: settings.rate,
    );
    if (generation != _explanationGeneration) return;
    final file = await _services.cache.writeAudio(
      'explanation_${DateTime.now().microsecondsSinceEpoch}',
      bytes,
    );
    if (generation != _explanationGeneration) {
      try {
        await file.delete();
      } on Object catch (_) {
        // best-effort cleanup; if a stale file remains, the cache sweep catches it
      }
      return;
    }
    await _services.discussionPlayer.playFile(file.path);
    try {
      await file.delete();
    } on Object catch (_) {
      // best-effort cleanup (same contract as the discussion path)
    }
  }

  Future<void> _showPageSelector(Book book) async {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final total = book.totalPages;
    var selected = _readerState.currentPage.clamp(1, total);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Go to page'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Page $selected / $total',
                    style: TextStyle(color: palette.text2),
                  ),
                  Slider(
                    min: 1,
                    max: total.toDouble(),
                    divisions: total > 1 ? total - 1 : 1,
                    value: selected.toDouble(),
                    label: '$selected',
                    onChanged: (v) {
                      setDialogState(() => selected = v.round());
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  key: const Key('page-go'),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _navigateToPage(selected);
                  },
                  child: const Text('Go'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildControlBar(AppPalette palette) {
    final currentPage = _readerState.currentPage;
    final total = _readerState.totalPages;
    final canPrev = widget.pipeline != null && currentPage > 1;
    final canNext = widget.pipeline != null && total > 0 && currentPage < total;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Speed chip (48dp touch target: the visual chip is unchanged, the
          // area is invisible)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() {
                _speedIndex = (_speedIndex + 1) % 5;
              });
              _services.reading.setRate(speedValues[_speedIndex]);
              if (widget.pipeline != null &&
                  _lastPreparedAudioPath != null &&
                  _readerState.phase == ReaderPhase.playing) {
                final page = _readerState.currentPage;
                final newSettings = _pipelineSettingsFromReadingSettings();
                // F2 generation token: taken at the moment of the tap; if the
                // page changes during the two awaits (the token is stale), a
                // stale result is not written (t28).
                final gen = ++_prepareGeneration;
                final pending = widget.pipeline!
                    .prepareAudio(page, newSettings, force: true)
                    .then((newFile) async {
                      // New speed = new audio = new sentence-timing sidecar. Fetch
                      // the sidecar with the same (new) settings and assign it in
                      // the SAME setState as the audio path -> the highlight
                      // advances consistently at the new tempo.
                      final newTimings = await widget.pipeline!.cachedTimings(
                        page,
                        newSettings,
                      );
                      if (mounted && gen == _prepareGeneration) {
                        setState(() {
                          _lastPreparedAudioPath = newFile.path;
                          _pageTimings = newTimings;
                        });
                      }
                    })
                    .catchError((_) {});
                unawaited(pending);
              }
            },
            child: MinTapArea(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: palette.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  speedLabels[_speedIndex],
                  style: TextStyle(
                    color: palette.accent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          // Previous page
          IconButton(
            key: const Key('page-prev'),
            icon: Icon(Icons.chevron_left, color: palette.accent),
            tooltip: 'Previous page',
            onPressed: canPrev ? () => _navigateToPage(currentPage - 1) : null,
          ),
          // Center button
          Semantics(
            button: true,
            label: _readerState.phase == ReaderPhase.playing ? 'Pause' : 'Play',
            child: GestureDetector(
              onTap: _onCenterTap,
              child: Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      palette.accent,
                      palette.accent.withValues(alpha: 0.7),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: palette.accent.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(child: _buildCenterIcon(palette)),
              ),
            ),
          ),
          // Next page
          IconButton(
            key: const Key('page-next'),
            icon: Icon(Icons.chevron_right, color: palette.accent),
            tooltip: 'Next page',
            onPressed: canNext ? () => _navigateToPage(currentPage + 1) : null,
          ),
        ],
      ),
    );
  }

  /// Center Play/Pause tap. If the pipeline is ready it goes to the machine.
  /// When it is not ready (book open, pipeline being set up) the tap is NOT
  /// silently swallowed: it is reported with a SnackBar and queued; a second tap
  /// cancels the queue. With no book at all, the old behavior (no-op) is kept.
  void _onCenterTap() {
    if (widget.pipeline != null) {
      _dispatch(TogglePressed());
      return;
    }
    if (widget.book == null) return;
    if (widget.pipelineFailed) {
      _showNotice(_pipelineFailedMsg, _failedDuration);
      return;
    }
    setState(() => _playQueued = !_playQueued);
    _showNotice(
      _playQueued
          ? 'Book is being prepared… playback will start once it is ready.'
          : 'Playback request cancelled',
      const Duration(seconds: 4),
    );
  }

  static const Duration _failedDuration = Duration(seconds: 5);
  static const String _pipelineFailedMsg =
      'The book could not be prepared. Please reopen the book.';

  /// Temporary notice SnackBar. The dismissal time is measured with a
  /// frame-driven [AnimationController] (see [_TransientNotice]): the SnackBar's
  /// own Timer does not schedule frames, so `pumpAndSettle` returns as soon as
  /// the entry animation ends and the message would look like it stays on screen
  /// forever (E4).
  void _showNotice(String text, Duration duration) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: duration + const Duration(seconds: 1),
          content: _TransientNotice(text: text, duration: duration),
        ),
      );
  }

  Widget _buildCenterIcon(AppPalette palette) {
    if (widget.pipeline == null) {
      // The book is open but the pipeline is not set up yet (it may be being set
      // up, OR the setup may have permanently failed -- there is no signal to
      // tell the two apart). A spinner of indeterminate duration is NOT used (on
      // permanent failure it would spin forever, and in tests pumpAndSettle would
      // never finish); a fixed, disabled-looking play icon is enough. If a request
      // is waiting in the queue, a fixed "waiting" icon is shown.
      if (_playQueued) {
        return const Icon(Icons.hourglass_top, color: Colors.white, size: 28);
      }
      return Icon(
        Icons.play_arrow,
        color: Colors.white.withValues(alpha: 0.5),
        size: 28,
      );
    }
    switch (_readerState.phase) {
      case ReaderPhase.playing:
        return const Icon(Icons.pause, color: Colors.white, size: 28);
      case ReaderPhase.preparing:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        );
      case ReaderPhase.idle:
      case ReaderPhase.ready:
      case ReaderPhase.paused:
      case ReaderPhase.finished:
        return const Icon(Icons.play_arrow, color: Colors.white, size: 28);
    }
  }
}

/// SnackBar body: closes itself after [duration] (frame-driven counter).
class _TransientNotice extends StatefulWidget {
  const _TransientNotice({required this.text, required this.duration});

  final String text;
  final Duration duration;

  @override
  State<_TransientNotice> createState() => _TransientNoticeState();
}

class _TransientNoticeState extends State<_TransientNotice>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
        }
      })
      ..forward().ignore();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(widget.text);
}
