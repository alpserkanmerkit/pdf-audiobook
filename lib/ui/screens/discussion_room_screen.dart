import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:sesli_kitap/io/edge_tts.dart';
import 'package:sesli_kitap/io/gemini_tts.dart';
import 'package:sesli_kitap/io/llm_cleaner.dart';
import 'package:sesli_kitap/io/llm_discussion.dart';
import 'package:sesli_kitap/io/pdf_text.dart';
import 'package:sesli_kitap/src/cache_keys.dart';
import 'package:sesli_kitap/src/discussion/discussion_book_source.dart';
import 'package:sesli_kitap/src/discussion/discussion_budget.dart';
import 'package:sesli_kitap/src/discussion/discussion_controller.dart';
import 'package:sesli_kitap/src/discussion/discussion_directive.dart';
import 'package:sesli_kitap/src/discussion/discussion_pace.dart';
import 'package:sesli_kitap/src/discussion/discussion_presenter.dart';
import 'package:sesli_kitap/src/discussion/discussion_session.dart';
import 'package:sesli_kitap/src/discussion/discussion_topic_suggest.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';
import 'package:sesli_kitap/src/discussion/tts_synth_policy.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/src/page_preprocess.dart';
import 'package:sesli_kitap/src/voices.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';

/// DQ-W1: display label for each option in the length-mode picker.
String _lengthModeLabel(DiscussionLengthMode mode) {
  switch (mode) {
    case DiscussionLengthMode.kisa:
      return 'Short';
    case DiscussionLengthMode.orta:
      return 'Medium';
    case DiscussionLengthMode.uzun:
      return 'Long';
    case DiscussionLengthMode.sonsuz:
      return 'Endless';
  }
}

/// The error text shown to the user: the controller wraps a failure in Dart's
/// `Exception(reason)` (discussion_controller.dart), so its English
/// "Exception: " prefix is stripped; the reason (in Turkish) is kept as is.
String _userFacingError(Object e) {
  final text = e.toString();
  const prefix = 'Exception: ';
  return text.startsWith(prefix) ? text.substring(prefix.length) : text;
}

/// Prefs key for persistence (phase DQ-W3): a single, global "last discussion"
/// slot -- NOT per book (see the design note in discussion_session.dart).
const String kDiscussionSessionPrefsKey = 'discussion_session';

/// K1 (closed box, 2026-09-30): a discussion cannot start without a book.
const String kDiscussionNoBookMessage =
    'Open a book or pick one from the list before starting a discussion: '
    'the speakers only use the book text.';

/// K1/K2: the book exists, but there is no clean or raw text between page 1 and the reader's page.
const String kDiscussionNoTextMessage =
    'No readable text was found in the book up to the current page; '
    'the discussion could not be started.';

class DiscussionRoomScreen extends StatefulWidget {
  const DiscussionRoomScreen({
    super.key,
    this.debugControllerFactory,
    this.onBack,
    this.bookTitle,
    this.book,
    this.debugInitialSession,
    this.debugOnSessionSaved,
  });

  final DiscussionController Function()? debugControllerFactory;
  final VoidCallback? onBack;
  final String? bookTitle;

  /// The open book (AppShell). K1: if no book chip is picked, this book is the
  /// discussion's source; a manually typed topic counts as a "topic/question from the book".
  final Book? book;

  /// Test seam (phase DQ-W3): if given, AppServicesScope.prefs is NEVER read;
  /// this value is used directly as the "saved session" (null = no saved
  /// session). Ignored when [debugControllerFactory] is NOT set (the real path).
  final DiscussionSession? debugInitialSession;

  /// Test seam (phase DQ-W3): if given, every persistence point does NOT write
  /// to the real prefs; the computed [DiscussionSession] is passed to this
  /// callback instead. Ignored when [debugControllerFactory] is NOT set.
  final void Function(DiscussionSession)? debugOnSessionSaved;

  @override
  State<DiscussionRoomScreen> createState() => _DiscussionRoomScreenState();
}

class _DiscussionRoomScreenState extends State<DiscussionRoomScreen> {
  String _subtitle = 'Pick a direction or start directly.';
  String _attribution = '';
  SteerKind? _selectedSteer;

  bool _isRunning = false;
  bool _isStopped = false;
  String? _errorMessage;
  // Tracks the turn being played (the single source of truth for the avatar glow
  // and the pill); it comes (as an index) from the controller's SYNC onTurnAboutToPlay hook.
  DiscussionTurn? _playingTurn;
  String _activeSpeakerPill = '';
  List<MapEntry<String, String>> _playedTurns = [];

  // ── DQ-W3: resume-where-you-left-off persistence ─────────────────────────
  bool _sessionChecked = false;
  DiscussionSession? _savedSession;
  // Becomes true once the user picks ONE option on the choice screen (it never
  // shows again, even if _savedSession/isResumable change later).
  bool _resumeChoiceMade = false;
  // Metadata the current run needs for persistence.
  String _topic = '';
  bool _sessionOpenEnded = false;
  int _sessionCreatedAtMs = 0;
  String? _sessionBookHash;
  // ALL generated turns (in order) -- for persistence; kept separate from
  // _playedTurns (speaker-name+text pairs for display), which runs in PARALLEL
  // with it, so that before/after do not mix when resuming.
  List<DiscussionTurn> _allTurns = [];
  // PR-Q1 (DESIGN §5): true while the continuation party (continueScript) is
  // running. Screen-layer state only -- NO change to the machine/controller; set
  // true on entry and false on return (from the myContinue/factoryContinue wrappers).
  bool _isExtending = false;
  // DQ-W2: true while the first batch's "writer -> review -> fix" chain
  // (generateReviewed) runs. Screen-layer state only (machine/controller
  // unchanged); set true on entry and false on return in the myGenerate wrapper.
  // The reviewer runs inside the first-generation window (no turn has played
  // yet), so the pill's "preparing" state becomes "reviewing".
  bool _isReviewing = false;

  // PR (interactive participation): set with a steer chip; it is SINGLE-USE --
  // _consumePendingDirective clears it as soon as it is read, so it only affects
  // the NEXT continuation-party call (it does not interrupt current playback and
  // does not leak into later calls). K4 (2026-09-30): "Ask a question" NO LONGER
  // goes here -- the question goes directly to the playing discussion's controller
  // (_activeController.ask); an unconsumed directive is also cleared when the run ends.
  String? _pendingListenerDirective;

  // K4: the controller of the discussion currently running (questions go to it);
  // null outside a run.
  DiscussionController? _activeController;

  // Index of the SCRIPT line that started playing last (for persistence). Answer
  // lines (K4) are not added to the script, so this is kept SEPARATE from the
  // _playedTurns length.
  int _lastPlayedIndex = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sessionChecked) return;
    _sessionChecked = true;
    if (widget.debugControllerFactory != null) {
      // Test path: the real AppServicesScope is NEVER touched (consistent with the
      // existing debug-path contract) -- only the explicitly given value is used.
      _savedSession = widget.debugInitialSession;
      return;
    }
    // Isolated tests such as robustness_test.dart/ui_accessibility_test.dart build
    // this screen WITHOUT AppServicesScope (regression: using .of() asserted and
    // crashed with "AppServicesScope not found"). Null-safe lookup: if there is no
    // scope, the saved-session check is skipped silently.
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppServicesScope>();
    if (scope == null) {
      _savedSession = null;
      return;
    }
    _savedSession = sessionFromJsonString(
      scope.services.prefs.getString(kDiscussionSessionPrefsKey),
    );
  }

  bool get _showResumeChoice =>
      !_isRunning && !_resumeChoiceMade && isResumable(_savedSession);

  /// Computes the current run's DiscussionSession (including the part already
  /// played) and writes it to the persistence target: the test seam if present,
  /// otherwise the real prefs when NOT on the debug path; on the debug path with
  /// no seam it does nothing, so existing tests behave the same.
  void _persistSession() {
    final session = DiscussionSession(
      topic: _topic,
      turns: List<DiscussionTurn>.of(_allTurns),
      playedIndex: _lastPlayedIndex,
      openEnded: _sessionOpenEnded,
      createdAtMs: _sessionCreatedAtMs,
      bookHash: _sessionBookHash,
    );
    final onSaved = widget.debugOnSessionSaved;
    if (onSaved != null) {
      onSaved(session);
      return;
    }
    if (widget.debugControllerFactory != null) {
      return;
    }
    final services = AppServicesScope.of(context);
    unawaited(
      services.prefs.setString(
        kDiscussionSessionPrefsKey,
        sessionToJsonString(session),
      ),
    );
  }

  /// CALLED when script line [index] starts playing (the common point of the
  /// four near-identical play callbacks for run/resume on the debug and real paths):
  /// updates the visible state AND writes persistence.
  void _onTurnStartingToPlay(int index) {
    _lastPlayedIndex = index;
    _showPlayingTurn(_allTurns[index]);
    _persistSession();
  }

  /// K4: when an answer line to a listener question starts playing, the visible
  /// state (subtitle/pill/transcript) is updated; it does NOT go into the script or persistence.
  void _onInterjectionStartingToPlay(DiscussionTurn turn) {
    if (!mounted || _isStopped) return;
    setState(() => _showPlayingTurn(turn));
  }

  /// Visible state for the line now playing (script or answer): subtitle/
  /// attribution/pill/playedTurns.
  void _showPlayingTurn(DiscussionTurn turn) {
    _playingTurn = turn;
    _subtitle = turn.text;
    _attribution = '— ${speakerName(turn.speaker)}';
    _activeSpeakerPill = '${speakerName(turn.speaker)} is speaking';
    _playedTurns.add(MapEntry(speakerName(turn.speaker), turn.text));
  }

  void _onSteerTap(SteerKind kind) {
    final isPlaying = _isRunning && !_isStopped && _activeController != null;
    final isFinite = !_sessionOpenEnded;

    if (isPlaying && isFinite) {
      final accepted = _activeController!.ask(steerDirective(kind));
      setState(() {
        _selectedSteer = kind;
        if (accepted) {
          _subtitle = steerCaption(kind);
          _attribution = '— You (answer before the next line)';
        } else {
          _subtitle =
              'Direction could not be sent: the discussion cannot take directions right now.';
          _attribution = '';
        }
      });
    } else {
      setState(() {
        _selectedSteer = kind;
        // ROOT-CAUSE FIX (device proof 08.07): the UI subtitle (steerCaption,
        // first-person line text) and the instruction sent to the model
        // (steerDirective, operational) are NOW SEPARATE -- see the steerDirective doc.
        _subtitle = steerCaption(kind);
        _attribution = '— Emel';
        _pendingListenerDirective = steerDirective(kind);
      });
    }
  }

  /// Interactive participation (K4, 2026-09-30): a free-text listener question.
  /// The question goes to the controller of the playing discussion
  /// ([DiscussionController.ask]): when the current line ends, a short answer
  /// party cuts in BEFORE the next script line -- in EVERY mode. If no run is
  /// active, or the controller does not accept the question, the user is told
  /// explicitly; the question is never held anywhere and never leaks into the
  /// next discussion.
  void _showAskQuestionDialog() {
    final controller = TextEditingController();
    final pending = showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ask a question'),
        content: TextField(
          key: const Key('ask-question-field'),
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Type a question or direction for the discussion...',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () {
              final question = controller.text.trim();
              if (question.isNotEmpty) {
                Navigator.of(ctx).pop();
                final accepted = _activeController?.ask(question) ?? false;
                setState(() {
                  if (accepted) {
                    _subtitle = question;
                    _attribution = '— You (answer before the next line)';
                  } else {
                    _subtitle =
                        'Question could not be sent: the discussion cannot take questions right now.';
                    _attribution = '';
                  }
                });
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
    unawaited(pending);
  }

  /// Injects the pending listener directive (if any) into the [topic] argument
  /// AND clears it so it is SINGLE-USE (so it does not leak into the next call).
  /// Both the real path (myContinue) and the debug path (factory wrapper) call
  /// THIS method, so wiring tests can observe the injection with debugControllerFactory too.
  String _consumePendingDirective(String topic) {
    final directive = _pendingListenerDirective;
    _pendingListenerDirective = null;
    return withListenerDirective(topic, directive);
  }

  /// Collects the text from the discussion's source book (chip or open book -- K1)
  /// from the START of the book up to the reader's current page (see
  /// discussion_book_source.dart; never later pages). Per page, the cached clean
  /// text is used first, otherwise the PDF's RAW text layer (K2; no LLM/OCR).
  /// Returns null if there is no book or no service.
  Future<DiscussionBookSource?> _gatherBookSource(
    AppServices? services,
    Book? book,
  ) async {
    if (services == null || book == null || book.hash.isEmpty) return null;
    final total = book.totalPages < 1 ? 1 : book.totalPages;
    final page = (services.prefs.getInt('progress_${book.hash}') ?? 1).clamp(
      1,
      total,
    );
    // Raw text is loaded lazily: the PDF is parsed only ONCE (1..page), and only
    // when the first page without clean text needs it.
    List<String>? rawPages;
    var rawLoaded = false;
    Future<String?> readRaw(int p) async {
      if (!rawLoaded) {
        rawLoaded = true;
        rawPages = await _readRawPages(book, page);
      }
      final texts = rawPages;
      if (texts == null || p > texts.length) return null;
      return stripPageArtifacts(texts[p - 1]).text;
    }

    return gatherDiscussionSource(
      currentPage: page,
      readPage: (p) async => (await services.cache.readText(
        textCacheKey(
          bookHash: book.hash,
          pageNo: p,
          cleanPromptVersion: cleanPromptVersion,
        ),
      ))?.clean,
      readRawPage: readRaw,
    );
  }

  /// K2: the raw text layer of the PDF for 1..[lastPage]; null if the file is
  /// missing or unreadable (pages without clean text are then skipped and counted).
  Future<List<String>?> _readRawPages(Book book, int lastPage) async {
    if (book.filePath.isEmpty) return null;
    try {
      final bytes = await File(book.filePath).readAsBytes();
      return await extractAllPageTexts(bytes, lastPage: lastPage);
    } on Object catch (e) {
      debugPrint('discussion raw text could not be read: $e');
      return null;
    }
  }

  Future<void> _startDiscussion(
    String topic, {
    DiscussionLengthMode mode = DiscussionLengthMode.orta,
    Book? sourceBook,
  }) async {
    if (topic.trim().isEmpty) return;

    // MINOR-5: openEnded is derived from the mode as the single source of truth
    // (there is NO separate param); only Endless mode runs open-ended (with continuation parties).
    final openEnded = mode == DiscussionLengthMode.sonsuz;

    // Discussion time counter: measures the time spent in a real run (without
    // debugControllerFactory) and adds it to discussion_seconds. recordServices is
    // assigned only on the real path (AppServicesScope is reached); it stays null on the fake-test path.
    AppServices? recordServices;
    final runStopwatch = Stopwatch();

    // ROOT-CAUSE FIX (device proof 08.07, Bug#1): a finite mode (Short/Medium/Long)
    // NEVER calls a continuation party (canExtend = openEnded &&
    // continueScript != null -- discussion_controller.dart), so
    // _consumePendingDirective (which runs ONLY inside continueScript) was NEVER
    // triggered in finite mode -- a chip pressed while idle never reached the
    // model. CAPTURE the pending value HERE, before the reset below: like the
    // read-then-null pattern of _consumePendingDirective, it is injected into the
    // FIRST generation (myGenerate) of this run -- it stays single-use (the reset
    // clears it at the same time, so no leak).
    final initialDirective = _pendingListenerDirective;
    final book = sourceBook ?? widget.book;
    final bookHash = (book != null && book.hash.isNotEmpty) ? book.hash : null;

    setState(() {
      _isRunning = true;
      _isStopped = false;
      _errorMessage = null;
      _playingTurn = null;
      _activeSpeakerPill = '';
      _playedTurns = [];
      _isExtending = false;
      _isReviewing = false;
      _lastPlayedIndex = -1;
      // PR (interactive participation) -- cross-session leak guard: a fresh run
      // does NOT start with a pending listener directive. In finite mode (no
      // continuation party ever happens), after Stop, or when a directive was
      // banked while idle and NEVER CONSUMED, it would otherwise leak into this
      // run's first continuation party (adversarial-review finding). When no
      // direction is given, behavior must stay exactly the same. (initialDirective
      // was already captured ABOVE -- this line makes sure it does not leak into
      // later runs after it has been injected into THIS run's first generation.)
      _pendingListenerDirective = null;
      // DQ-W3: fresh run -- persistence metadata starts from scratch.
      _topic = topic;
      _sessionOpenEnded = openEnded;
      _sessionCreatedAtMs = DateTime.now().millisecondsSinceEpoch;
      _sessionBookHash = bookHash;
      _allTurns = [];
    });

    // Book text: the service is captured BEFORE the first await; the text is
    // collected right before controller.run and added to the topic of the first
    // generation, the continuation parties and the question answers (_topic and
    // persistence stay LEAN).
    // K1 (closed box): the source book = the chip picked in the dialog, otherwise
    // the OPEN book; a manually typed topic also goes with the book text.
    final sourceServices = context
        .getInheritedWidgetOfExactType<AppServicesScope>()
        ?.services;
    DiscussionBookSource? bookSource;
    DiscussionController? runController;

    try {
      DiscussionController controller;

      if (widget.debugControllerFactory != null) {
        final factoryCtrl = widget.debugControllerFactory!();
        final generate = factoryCtrl.generate;
        final synthesize = factoryCtrl.synthesize;
        final play = factoryCtrl.play;
        // S2: the factory also carries the endless-mode configuration; the screen
        // rebuilds it with ITS OWN stop-aware wrappers (a continuation call after
        // Stop -> StateError -> ExtensionFailed -> graceful end).
        final factoryContinue = factoryCtrl.continueScript;
        final factoryAnswer = factoryCtrl.answerQuestion;

        controller = DiscussionController(
          openEnded: factoryCtrl.openEnded,
          continueScript: factoryContinue == null
              ? null
              : (t, r) async {
                  if (_isStopped) throw StateError('stopped');
                  final directedTopic = _consumePendingDirective(t);
                  if (mounted) setState(() => _isExtending = true);
                  try {
                    return await factoryContinue(
                      withBookSource(directedTopic, bookSource),
                      r,
                    );
                  } finally {
                    if (mounted) setState(() => _isExtending = false);
                  }
                },
          // K4: question answers are also closed to the same book text.
          answerQuestion: factoryAnswer == null
              ? null
              : (t, q, r) => factoryAnswer(withBookSource(t, bookSource), q, r),
          onInterjectionAboutToPlay: _onInterjectionStartingToPlay,
          // ROOT-CAUSE FIX (Bug#1): a direction pending while idle (if any) is
          // injected into the FIRST generation of this run -- see the initialDirective
          // capture comment above.
          generate: (topic) => generate(
            withBookSource(
              withListenerDirective(topic, initialDirective),
              bookSource,
            ),
          ),
          // Package A1 (TTS synthesis resilience): the debug-factory path has NO provider
          // split (the injected function is fake), but it is wrapped with the SAME retry
          // count (synthAttemptPlan -> 3) so that a single synthesis throw does not drop
          // the whole run into the 'failed' dead phase (see tts_synth_policy.dart
          // runSynthAttempts). HAPPY PATH (first attempt succeeds) is BYTE-IDENTICAL to
          // before: a single call, retry is NEVER triggered.
          synthesize: (turn) async {
            final voice = voiceForSpeaker(turn.speaker);
            return runSynthAttempts(
              synthAttemptPlan(voice),
              (_) => synthesize(turn),
            );
          },
          play: (bytes) async {
            if (_isStopped) throw StateError('stopped');
            await play(bytes);
          },
          // ROOT-CAUSE FIX (08.07, device proof): "which turn plays next" now comes
          // from the controller's SYNC onTurnAboutToPlay hook (index). The old
          // `_lastTurn` proxy could be overwritten while SynthesizeTurn(N+1) was
          // still delayed by the A2 (micro-pause) pauseDelay (the transcript ran one turn ahead).
          onTurnAboutToPlay: (index) {
            if (!mounted || _isStopped) return;
            setState(() => _onTurnStartingToPlay(index));
          },
          // ROOT-CAUSE FIX (Bug#1): as soon as the script(s) are FULLY known (not a
          // delta), _allTurns is updated as a whole -- so the text of lines whose
          // synthesis has not come yet is also included in persistence.
          onScriptReady: (turns) => _allTurns = List<DiscussionTurn>.of(turns),
          onScriptExtended: (turns) =>
              _allTurns = List<DiscussionTurn>.of(turns),
        );
      } else {
        final services = AppServicesScope.of(context);
        // Empty-key guard: a discussion needs BOTH the LLM (script) AND Google TTS
        // (all 4 speakers use Google voices -> voiceForSpeaker) keys. Consistent with
        // the reader's PR#32 contract (page_pipeline _cleanOrFallback): if the key is
        // empty, NOTHING is called; a friendly message is shown instead of a raw "HTTP 401".
        if (!services.reading.llmAccess.isConfigured) {
          setState(() {
            _isRunning = false;
            _errorMessage =
                'An API key is required for discussions. Go to Settings > ACCOUNT & API '
                'and enter your Gemini key.';
          });
          return;
        }
        recordServices = services;
        // S2: at run start, sweep the temporary audio leftovers of the previous
        // discussion (best-effort, does not block the flow).
        unawaited(services.cache.sweepAudio('discussion_turn_'));
        final llm = LlmDiscussion(access: services.reading.llmAccess);
        final geminiKey = services.reading.geminiKey;
        var turnCounter = 0;

        Future<List<DiscussionTurn>> myGenerate(String topic) async {
          // DQ-W1: pass the target word/turn count of the selected length mode to
          // the first script generation (no-op for Endless; the existing opening
          // rule stays -- see LlmDiscussion._lengthRuleFor / _openingLengthRule).
          // DQ-W2: the first batch goes through the "writer -> review -> fix" chain
          // (generateReviewed); while the reviewer runs, a small screen state
          // (_isReviewing) is shown. If the reviewer fails, generateReviewed
          // fails open and returns the original script (the flow does not break).
          // ROOT-CAUSE FIX (Bug#1): a direction pending while idle (if any) is
          // injected into the FIRST generation of this run.
          final directedTopic = withListenerDirective(topic, initialDirective);
          if (mounted) setState(() => _isReviewing = true);
          try {
            return await llm.generateReviewed(
              withBookSource(directedTopic, bookSource),
              mode: mode,
            );
          } finally {
            if (mounted) setState(() => _isReviewing = false);
          }
        }

        Future<List<DiscussionTurn>> myContinue(
          String topic,
          List<DiscussionTurn> recent,
        ) async {
          if (_isStopped) throw StateError('stopped');
          final directedTopic = _consumePendingDirective(topic);
          if (mounted) setState(() => _isExtending = true);
          try {
            return await llm.generateContinuation(
              withBookSource(directedTopic, bookSource),
              recent,
            );
          } finally {
            if (mounted) setState(() => _isExtending = false);
          }
        }

        Future<Uint8List> mySynthesize(DiscussionTurn turn) async {
          final voice = voiceForSpeaker(turn.speaker);
          // Package A1 (TTS synthesis resilience -- VERIFIED PROBLEM: in discussion_
          // machine.dart a single TurnFailed during playing/waiting drops the WHOLE
          // discussion into 'failed', and unlike ExtensionFailed it does NOT degrade
          // gracefully). The asymmetry is closed HERE, in the SYNTHESIS layer, without
          // touching discussion_machine.dart (FROZEN): primary (Gemini) -> 1 Gemini
          // retry -> Edge fallback (see tts_synth_policy.dart).
          // Gemini TTS slice (user, 2026-09-28): the 4 speakers' voices use
          // geminiVoiceName (Charon/Aoede/Gacrux/Puck), one single-speaker request per
          // line; the returned bytes are WAV (detected from the file content).
          return runSynthAttempts(synthAttemptPlan(voice), (attempt) {
            if (attempt.provider == SynthProvider.gemini) {
              return GeminiTts(
                apiKey: geminiKey,
              ).synthesize(text: turn.text, voice: voice);
            }
            // Edge fallback: attempt.voiceId (edgeVoiceId) is ALWAYS the ahmet/emel
            // counterpart (gender-matched) -- since EdgeTts.synthesize uses the raw
            // voiceId() (there is NO internal conversion like Google's), it is resolved
            // back to a VALID edge-native SesliVoice.
            final edgeVoice = SesliVoice.values.firstWhere(
              (v) => voiceId(v) == attempt.voiceId,
            );
            return EdgeTts().synthesize(text: turn.text, voice: edgeVoice);
          });
        }

        Future<void> myPlay(Uint8List bytes) async {
          if (_isStopped) throw StateError('stopped');
          final file = await services.cache.writeAudio(
            'discussion_turn_${DateTime.now().millisecondsSinceEpoch}_${turnCounter++}',
            bytes,
          );
          await services.discussionPlayer.playFile(file.path);
          // Audio recording persistence (user request): a played mp3 is NOT deleted
          // right away -- it stays on the phone as a local recording. The run-start
          // sweepAudio (above) cleans leftovers of the previous discussion when a NEW
          // discussion starts; resume continues the same session, so it does NOT call
          // its own sweepAudio (see _resumeDiscussion).
        }

        controller = DiscussionController(
          // A2 (mikro-duraklama): GERCEK-yol -- prod gecikmesini ACIKCA enjekte
          // et (varsayilan test-guvenli _immediatePauseDelay ANINDA doner).
          pauseDelay: (ms) => Future<void>.delayed(Duration(milliseconds: ms)),
          openEnded: openEnded,
          continueScript: myContinue,
          // K4: listener question -> short answer party, closed to the book text.
          answerQuestion: (t, q, r) =>
              llm.generateAnswer(withBookSource(t, bookSource), q, r),
          onInterjectionAboutToPlay: _onInterjectionStartingToPlay,
          generate: myGenerate,
          synthesize: mySynthesize,
          play: myPlay,
          // ROOT-CAUSE FIX (08.07, device proof): "which turn plays next" now comes
          // from the controller's SYNC onTurnAboutToPlay hook (index) -- the old
          // `_lastTurn` proxy (which relied on PlayTurn(N) being processed synchronously
          // BEFORE SynthesizeTurn(N+1)) was a FRAGILE contract; A2 (micro-pause) pauseDelay
          // kicks in, SynthesizeTurn(N+1) was still delayed and ran concurrently and
          // overwrote _lastTurn with N+1 -- the transcript ran one turn ahead on the
          // screen (observed on the device, see the onTurnAboutToPlay doc in discussion_controller.dart).
          onTurnAboutToPlay: (index) {
            if (!mounted || _isStopped) return;
            setState(() => _onTurnStartingToPlay(index));
          },
          onScriptReady: (turns) => _allTurns = List<DiscussionTurn>.of(turns),
          onScriptExtended: (turns) =>
              _allTurns = List<DiscussionTurn>.of(turns),
        );
      }

      bookSource = await _gatherBookSource(sourceServices, book);
      // Diagnostics: range + clean/raw/skipped pages + characters (one line).
      final gathered = bookSource;
      if (gathered != null) {
        debugPrint(describeDiscussionSource(gathered));
      }
      // K1 (closed box): in the app (when AppServices exists) a discussion with no book
      // or no text does NOT start -- the model is never called. A setup WITHOUT
      // AppServices is only the test debug-factory path (book text cannot be read anyway).
      if (sourceServices != null && gathered == null) {
        if (mounted) {
          setState(() {
            _isRunning = false;
            _errorMessage = book == null
                ? kDiscussionNoBookMessage
                : kDiscussionNoTextMessage;
          });
        }
        return;
      }
      _activeController = runController = controller;
      runStopwatch.start();
      await controller.run(topic);
    } on Object catch (e) {
      if (mounted && !_isStopped) {
        setState(() {
          _isRunning = false;
          _errorMessage =
              'An error occurred while starting the discussion: ${_userFacingError(e)}';
        });
      }
    } finally {
      _endRun(runController);
      if (mounted && !_isStopped) {
        setState(() {
          _isRunning = false;
        });
      }
      final rs = recordServices;
      final secs = runStopwatch.elapsed.inSeconds;
      if (rs != null && secs > 0) {
        final prev = rs.prefs.getInt('discussion_seconds') ?? 0;
        unawaited(rs.prefs.setInt('discussion_seconds', prev + secs));
      }
    }
  }

  /// K4: run ended -- questions no longer go to this controller, and an unconsumed
  /// chip directive does not leak into the NEXT discussion. If a new discussion was
  /// started right after Stop, the OLD run's closing does not touch the new one.
  void _endRun(DiscussionController? runController) {
    if (!identical(_activeController, runController)) return;
    _activeController = null;
    _pendingListenerDirective = null;
  }

  /// DQ-W3: resume where you left off. Identical to [_startDiscussion] (including the
  /// empty-key guard, myContinue/mySynthesize/myPlay, cache sweep and discussion_seconds
  /// accounting) -- the ONLY difference: controller.resume() is called instead of
  /// generate() (the script is already in `session.turns`, it is NEVER regenerated).
  Future<void> _resumeDiscussion(DiscussionSession session) async {
    AppServices? recordServices;
    final runStopwatch = Stopwatch();

    setState(() {
      _isRunning = true;
      _isStopped = false;
      _errorMessage = null;
      _playingTurn = null;
      _activeSpeakerPill = '';
      _isExtending = false;
      _isReviewing = false;
      // Cross-session leak guard (see _startDiscussion): a run being resumed also
      // does NOT start with a pending listener directive.
      _pendingListenerDirective = null;
      _topic = session.topic;
      _sessionOpenEnded = session.openEnded;
      _sessionCreatedAtMs = session.createdAtMs;
      _sessionBookHash = session.bookHash;
      // ROOT-CAUSE FIX (Round-2 adversarial review): _allTurns is seeded with the
      // FULL persisted script (not only the played prefix) -- onScriptReady is NEVER
      // triggered for resume() (generate() is not called), and onScriptExtended fires
      // only for NEW continuation parties; neither covers the queue ALREADY in
      // session.turns (not yet played). Seeding only the prefix would let playedIndex
      // pass turns.length as resume advances (treated as corrupt data, dropping the
      // WHOLE session on the next decode).
      _allTurns = List<DiscussionTurn>.of(session.turns);
      _lastPlayedIndex = session.playedIndex;
      final alreadyPlayed = session.turns.take(session.playedIndex + 1);
      _playedTurns = [
        for (final t in alreadyPlayed) MapEntry(speakerName(t.speaker), t.text),
      ];
    });
    final startIndex = session.playedIndex + 1;
    final sourceServices = context
        .getInheritedWidgetOfExactType<AppServicesScope>()
        ?.services;

    Book? resolveBook() {
      final hash = session.bookHash;
      if (hash == null || hash.isEmpty) return null;
      if (widget.book != null && widget.book!.hash == hash) {
        return widget.book;
      }
      final raw = sourceServices?.prefs.getString('books_v1');
      if (raw == null || raw.isEmpty) return null;
      final books = decodeBooks(raw);
      for (final b in books) {
        if (b.hash == hash) return b;
      }
      return null;
    }

    final book = resolveBook();
    if (session.bookHash != null &&
        session.bookHash!.isNotEmpty &&
        book == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Book not found: the discussion continues without the book text.',
          ),
        ),
      );
    }
    DiscussionBookSource? bookSource;
    DiscussionController? runController;

    try {
      DiscussionController controller;

      if (widget.debugControllerFactory != null) {
        final factoryCtrl = widget.debugControllerFactory!();
        final synthesize = factoryCtrl.synthesize;
        final play = factoryCtrl.play;
        final factoryContinue = factoryCtrl.continueScript;
        final factoryAnswer = factoryCtrl.answerQuestion;

        controller = DiscussionController(
          openEnded: session.openEnded,
          continueScript: factoryContinue == null
              ? null
              : (t, r) async {
                  if (_isStopped) throw StateError('stopped');
                  final directedTopic = _consumePendingDirective(t);
                  if (mounted) setState(() => _isExtending = true);
                  try {
                    return await factoryContinue(
                      withBookSource(directedTopic, bookSource),
                      r,
                    );
                  } finally {
                    if (mounted) setState(() => _isExtending = false);
                  }
                },
          // K4 + T9: question answers are also closed to the same book text.
          answerQuestion: factoryAnswer == null
              ? null
              : (t, q, r) => factoryAnswer(withBookSource(t, bookSource), q, r),
          onInterjectionAboutToPlay: _onInterjectionStartingToPlay,
          generate: (_) async =>
              throw StateError('resume() generate cagirmamali'),
          // Package A1 (TTS synthesis resilience): see the SAME debug-factory wrapper
          // comment in _startDiscussion -- there is NO provider split (fake function),
          // but it is wrapped with the SAME retry count so that a single
          // synthesis throw does not drop the whole run into 'failed'.
          synthesize: (turn) async {
            final voice = voiceForSpeaker(turn.speaker);
            return runSynthAttempts(
              synthAttemptPlan(voice),
              (_) => synthesize(turn),
            );
          },
          play: (bytes) async {
            if (_isStopped) throw StateError('stopped');
            await play(bytes);
          },
          // ROOT-CAUSE FIX (08.07): see the SAME hook comment in _startDiscussion --
          // the old `_lastTurn` proxy vs. A2 (micro-pause)
          // pauseDelay'iyle yarisiyordu.
          onTurnAboutToPlay: (index) {
            if (!mounted || _isStopped) return;
            setState(() => _onTurnStartingToPlay(index));
          },
          // resume() never calls generate(), so onScriptReady is never triggered;
          // in endless mode, if a continuation party arrives, onScriptExtended
          // carries the FULL script (old + new).
          onScriptExtended: (turns) =>
              _allTurns = List<DiscussionTurn>.of(turns),
        );
      } else {
        final services = AppServicesScope.of(context);
        if (!services.reading.llmAccess.isConfigured) {
          setState(() {
            _isRunning = false;
            _errorMessage =
                'An API key is required for discussions. Go to Settings > ACCOUNT & API '
                'and enter your Gemini key.';
          });
          return;
        }
        recordServices = services;
        // NO sweep: resume must NOT delete the audio recordings of the PREVIOUS
        // session -- we are continuing the same session (a new discussion /
        // _startDiscussion already does its own sweep).
        final llm = LlmDiscussion(access: services.reading.llmAccess);
        final geminiKey = services.reading.geminiKey;
        var turnCounter = 0;

        Future<List<DiscussionTurn>> myContinue(
          String topic,
          List<DiscussionTurn> recent,
        ) async {
          if (_isStopped) throw StateError('stopped');
          final directedTopic = _consumePendingDirective(topic);
          if (mounted) setState(() => _isExtending = true);
          try {
            return await llm.generateContinuation(
              withBookSource(directedTopic, bookSource),
              recent,
            );
          } finally {
            if (mounted) setState(() => _isExtending = false);
          }
        }

        Future<Uint8List> mySynthesize(DiscussionTurn turn) async {
          final voice = voiceForSpeaker(turn.speaker);
          // Package A1 (TTS synthesis resilience -- VERIFIED PROBLEM: in discussion_
          // machine.dart a single TurnFailed during playing/waiting drops the WHOLE
          // discussion into 'failed', and unlike ExtensionFailed it does NOT degrade
          // gracefully). The asymmetry is closed HERE, in the SYNTHESIS layer, without
          // touching discussion_machine.dart (FROZEN): primary (Gemini) -> 1 Gemini
          // retry -> Edge fallback (see tts_synth_policy.dart).
          // Gemini TTS slice (user, 2026-09-28): the 4 speakers' voices use
          // geminiVoiceName (Charon/Aoede/Gacrux/Puck), one single-speaker request per
          // line; the returned bytes are WAV (detected from the file content).
          return runSynthAttempts(synthAttemptPlan(voice), (attempt) {
            if (attempt.provider == SynthProvider.gemini) {
              return GeminiTts(
                apiKey: geminiKey,
              ).synthesize(text: turn.text, voice: voice);
            }
            // Edge fallback: attempt.voiceId (edgeVoiceId) is ALWAYS the ahmet/emel
            // counterpart (gender-matched) -- since EdgeTts.synthesize uses the raw
            // voiceId() (there is NO internal conversion like Google's), it is resolved
            // back to a VALID edge-native SesliVoice.
            final edgeVoice = SesliVoice.values.firstWhere(
              (v) => voiceId(v) == attempt.voiceId,
            );
            return EdgeTts().synthesize(text: turn.text, voice: edgeVoice);
          });
        }

        Future<void> myPlay(Uint8List bytes) async {
          if (_isStopped) throw StateError('stopped');
          final file = await services.cache.writeAudio(
            'discussion_turn_${DateTime.now().millisecondsSinceEpoch}_${turnCounter++}',
            bytes,
          );
          await services.discussionPlayer.playFile(file.path);
          // Audio recording persistence: see _startDiscussion.myPlay -- same
          // reason, the file is NOT deleted anymore.
        }

        controller = DiscussionController(
          // A2 (mikro-duraklama): GERCEK-yol -- prod gecikmesini ACIKCA enjekte et.
          pauseDelay: (ms) => Future<void>.delayed(Duration(milliseconds: ms)),
          openEnded: session.openEnded,
          continueScript: myContinue,
          // K4 + T9: on resume too, questions are bound to the book at that moment.
          answerQuestion: (t, q, r) =>
              llm.generateAnswer(withBookSource(t, bookSource), q, r),
          onInterjectionAboutToPlay: _onInterjectionStartingToPlay,
          generate: (_) async =>
              throw StateError('resume() generate cagirmamali'),
          synthesize: mySynthesize,
          play: myPlay,
          // ROOT-CAUSE FIX (08.07): see the SAME hook comment in _startDiscussion --
          // the old `_lastTurn` proxy raced with the A2 pauseDelay.
          onTurnAboutToPlay: (index) {
            if (!mounted || _isStopped) return;
            setState(() => _onTurnStartingToPlay(index));
          },
          onScriptExtended: (turns) =>
              _allTurns = List<DiscussionTurn>.of(turns),
        );
      }

      bookSource = await _gatherBookSource(sourceServices, book);
      if (book != null && bookSource == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Book text could not be read: the discussion continues without the book text.',
            ),
          ),
        );
      }
      final gathered = bookSource;
      if (gathered != null) {
        debugPrint(describeDiscussionSource(gathered));
      }
      _activeController = runController = controller;
      runStopwatch.start();
      await controller.resume(
        topic: session.topic,
        existingTurns: session.turns,
        startIndex: startIndex,
        openEnded: session.openEnded,
      );
    } on Object catch (e) {
      if (mounted && !_isStopped) {
        setState(() {
          _isRunning = false;
          _errorMessage =
              'An error occurred while resuming the discussion: '
              '${_userFacingError(e)}';
        });
      }
    } finally {
      _endRun(runController);
      if (mounted && !_isStopped) {
        setState(() {
          _isRunning = false;
        });
      }
      final rs = recordServices;
      final secs = runStopwatch.elapsed.inSeconds;
      if (rs != null && secs > 0) {
        final prev = rs.prefs.getInt('discussion_seconds') ?? 0;
        unawaited(rs.prefs.setInt('discussion_seconds', prev + secs));
      }
    }
  }

  void _stopDiscussion() {
    setState(() {
      _isStopped = true;
    });
    if (widget.debugControllerFactory == null) {
      try {
        final services = AppServicesScope.of(context);
        unawaited(services.discussionPlayer.stop());
      } on Object catch (_) {}
    }
  }

  void _showStartDialog() {
    final controller = TextEditingController();
    // DQ-W1: the length-mode choice is local to the dialog (default Medium). The old
    // "Endless mode" checkbox was replaced by a 4-way picker -- choosing Endless is
    // EQUIVALENT to the old checked box (openEnded=true). StatefulBuilder redraws the
    // selection without closing the dialog.
    var selectedMode = DiscussionLengthMode.orta;
    // If a book chip was tapped, that book is used; on Start the book TEXT is collected
    // from it. Without a chip the OPEN book (widget.book) is the source (K1): a manually
    // typed topic counts as a "topic/question from the book", and the text is added anyway.
    Book? chosenBook;
    // PR (A6): location-aware topic suggestions. Like getInheritedWidgetOfExactType
    // .of() it does NOT assert (null-safe) -- many existing wiring tests build this
    // screen WITHOUT AppServicesScope (same reason as the null-safe lookup in
    // didChangeDependencies for _showResumeChoice). If there is no scope, or books_v1
    // is missing/empty, or no book has progress >0, the list stays empty -> the
    // `if (suggestedBooks.isNotEmpty)` block below is NEVER drawn, and the dialog
    // stays byte-identical to its old body.
    var suggestedBooks = const <Book>[];
    final scope = context.getInheritedWidgetOfExactType<AppServicesScope>();
    if (scope != null) {
      final raw = scope.services.prefs.getString('books_v1');
      if (raw != null) {
        // ROOT-CAUSE FIX (device proof 08.07): the raw Book.progressPercent (books_v1)
        // is NEVER updated at write time -- it is ALWAYS 0. Real progress comes from
        // progress_<hash> (page number) (see the effectiveProgressPercent doc, the SAME
        // read-time merge as app_shell.dart _libraryBooks). Without using it, this
        // block NEVER showed a chip on the device.
        suggestedBooks = decodeBooks(raw)
            .map((b) {
              final page = scope.services.prefs.getInt('progress_${b.hash}');
              return b.withProgress(
                effectiveProgressPercent(page: page, totalPages: b.totalPages),
              );
            })
            .where((b) => b.progressPercent > 0)
            .toList();
      }
    }
    final pending = showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('New Discussion'),
          // ROOT-CAUSE FIX (device proof 08.07): AlertDialog.content was a Column with NO
          // SingleChildScrollView -- with the keyboard open (TextField autofocus:true) and
          // the A6 book-suggestion chips ADDED, the content exceeded the remaining vertical
          // space and threw a "BOTTOM OVERFLOWED" RenderFlex error; overflowing children
          // (the Endless chip) were drawn OUTSIDE the dialog boundary, looking like they
          // had escaped the template (a second symptom of the same bug, not a separate
          // error). SingleChildScrollView keeps the size byte-identical to before when the
          // content fits (no book suggestions); when it does not fit, it scrolls instead of overflowing.
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: 'Write a topic or question from the book...',
                  ),
                  autofocus: true,
                ),
                // PR (A6): a small list of suggestion chips for books with progress >0.
                // If empty (no scope / no book / none started), this block is NEVER
                // drawn -- the dialog stays byte-identical to its old body.
                if (suggestedBooks.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Suggested topics from the book',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).extension<AppPalette>()!.text2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: suggestedBooks.map((book) {
                      return ActionChip(
                        key: Key('discussion-topic-book-${book.id}'),
                        label: Text(book.title),
                        onPressed: () {
                          controller.text = discussionTopicForBook(book);
                          chosenBook = book;
                        },
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Length',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(ctx).extension<AppPalette>()!.text2,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: DiscussionLengthMode.values.map((mode) {
                    return ChoiceChip(
                      key: Key('discussion-length-mode-${mode.name}'),
                      label: Text(_lengthModeLabel(mode)),
                      selected: selectedMode == mode,
                      onSelected: (_) =>
                          setDialogState(() => selectedMode = mode),
                    );
                  }).toList(),
                ),
                // DQ-W1 (DESIGN §4/§8): rough time estimate for the selected mode
                // (108 words/min from the A2b measurement; uses the word-budget core of
                // targetWordsFor/computeTargetTurns). Endless shows a fixed label.
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Estimated time: ${discussionModeDurationLabel(selectedMode)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).extension<AppPalette>()!.text2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                final topic = controller.text.trim();
                if (topic.isNotEmpty) {
                  Navigator.of(ctx).pop();
                  unawaited(
                    _startDiscussion(
                      topic,
                      mode: selectedMode,
                      sourceBook: chosenBook,
                    ),
                  );
                }
              },
              child: const Text('Start'),
            ),
          ],
        ),
      ),
    );
    unawaited(pending);
  }

  void _showListSheet() {
    final pending = showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        if (_playedTurns.isEmpty) {
          return const SizedBox(
            height: 100,
            child: Center(child: Text('No conversation yet.')),
          );
        }
        return ListView.builder(
          itemCount: _playedTurns.length,
          itemBuilder: (ctx, index) {
            final turn = _playedTurns[index];
            return ListTile(title: Text(turn.key), subtitle: Text(turn.value));
          },
        );
      },
    );
    unawaited(pending);
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(palette),
            const SizedBox(height: 8),
            if (_showResumeChoice)
              Expanded(child: _buildResumeChoice(palette))
            else ...[
              _buildStatusPill(palette),
              if (_errorMessage != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: Colors.redAccent.withValues(alpha: 0.2),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.redAccent),
                    textAlign: TextAlign.center,
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      _buildAvatars(palette),
                      const SizedBox(height: 16),
                      _buildSubtitleArea(palette),
                      const SizedBox(height: 16),
                      _buildSteerChips(palette),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              _buildControlRow(palette),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// DQ-W3: resume / new-discussion choice screen. Shown ONLY while
  /// [_showResumeChoice] is true (a resumable saved session exists AND the user
  /// has not chosen yet).
  Widget _buildResumeChoice(AppPalette palette) {
    final session = _savedSession!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'You have an unfinished discussion',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: palette.text,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '«${session.topic}»',
              style: TextStyle(fontSize: 14, color: palette.text2),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              key: const Key('resume-discussion'),
              onPressed: () {
                setState(() => _resumeChoiceMade = true);
                unawaited(_resumeDiscussion(session));
              },
              child: const Text('Continue where you left off'),
            ),
            const SizedBox(height: 12),
            TextButton(
              key: const Key('new-discussion'),
              onPressed: () => setState(() => _resumeChoiceMade = true),
              child: const Text('New discussion'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'VOICE DISCUSSION',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  widget.bookTitle != null
                      ? '«${widget.bookTitle}»'
                      : 'General discussion',
                  style: TextStyle(fontSize: 12, color: palette.text2),
                ),
              ],
            ),
          ),
          if (!_isRunning)
            IconButton(
              icon: const Icon(Icons.play_arrow),
              tooltip: 'Start discussion',
              onPressed: _showStartDialog,
            ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(AppPalette palette) {
    // PR-Q1 (DESIGN §5): while the first generation runs (no turn has played yet),
    // a small loading indicator (spinner + "preparing") is shown instead of the
    // premature "Ahmet is speaking".
    final isPreparingFirstTurn =
        _isRunning && !_isStopped && _playedTurns.isEmpty;

    String pillText;
    if (isPreparingFirstTurn) {
      // DQ-W2: while the reviewer (generateReviewed) runs inside the first-generation window
      // pill "inceleniyor" der; kucuk spinner (isPreparingFirstTurn) aynen
      // kalir. Reviewer bitip sentez/oynatim baslayinca normal akisa doner.
      pillText = _isReviewing
          ? 'Reviewing discussion…'
          : 'Preparing discussion…';
    } else if (_isRunning && !_isStopped) {
      pillText = _activeSpeakerPill.isNotEmpty
          ? _activeSpeakerPill
          : 'Ahmet is speaking';
      // S2/DQ-W1: add the played-turn counter to the pill (feedback to the user:
      // "still going, we are on turn N"). Originally it was shown only in endless
      // mode; DQ-W1 polish: the same feedback is useful in normal (finite) mode too,
      // so it is now shown in EVERY mode.
      if (_playedTurns.isNotEmpty) {
        pillText = '$pillText · ${_playedTurns.length}. turn';
      }
      // PR-Q1: extra text while a continuation party (continueScript) runs -- the
      // machine/controller do not change; only the screen state (_isExtending).
      if (_isExtending) {
        pillText = '$pillText · next part is being prepared';
      }
    } else if (_isStopped) {
      pillText = 'Stopped';
    } else {
      pillText = 'Ahmet is speaking';
    }
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.surface2.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isPreparingFirstTurn)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isRunning && !_isStopped
                      ? palette.accent
                      : palette.text3,
                ),
              ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                pillText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: palette.text),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatars(AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.9,
        ),
        itemCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index) {
          final speaker = DiscussionSpeaker.values[index];
          // The glow follows the turn that is PLAYING (_playingTurn, which comes
          // synchronously from onTurnAboutToPlay) -- NOT the next (N+1) turn that was
          // pre-synthesized; the light must stay on the speaker who is talking (H-B1).
          final isActive =
              _isRunning &&
              !_isStopped &&
              _playingTurn != null &&
              _playingTurn!.speaker == speaker;
          return _buildSingleAvatar(
            speaker: speaker,
            isActive: isActive,
            palette: palette,
          );
        },
      ),
    );
  }

  Widget _buildSingleAvatar({
    required DiscussionSpeaker speaker,
    required bool isActive,
    required AppPalette palette,
  }) {
    final letter = switch (speaker) {
      DiscussionSpeaker.a => 'A',
      DiscussionSpeaker.b => 'E',
      DiscussionSpeaker.c => 'D',
      DiscussionSpeaker.d => 'K',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive
                ? palette.accent2.withValues(alpha: 0.5)
                : palette.surface2.withValues(alpha: 0.3),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: palette.accent.withValues(alpha: 0.4),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            letter,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: palette.text,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          speakerName(speaker),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: palette.text,
          ),
        ),
        Text('Host', style: TextStyle(fontSize: 11, color: palette.text3)),
      ],
    );
  }

  Widget _buildSubtitleArea(AppPalette palette) {
    return Container(
      constraints: const BoxConstraints(minHeight: 78),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _subtitle,
            style: TextStyle(
              fontFamily: serifTextFamily(AppSettingsScope.of(context)),
              fontSize: 17,
            ),
          ),
          if (_attribution.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _attribution,
              style: TextStyle(
                fontFamily: serifTextFamily(AppSettingsScope.of(context)),
                fontSize: 14,
                color: palette.text2,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSteerChips(AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ...SteerKind.values.map((kind) {
            final isSelected = _selectedSteer == kind;
            final isKarsilastir = kind == SteerKind.karsilastir;
            return InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _onSteerTap(kind),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isKarsilastir
                        ? palette.accent
                        : palette.surface2.withValues(alpha: 0.5),
                  ),
                  borderRadius: BorderRadius.circular(20),
                  color: isSelected ? palette.surface : Colors.transparent,
                ),
                child: Text(
                  steerLabelTr(kind),
                  style: TextStyle(
                    fontSize: 13,
                    color: isKarsilastir ? palette.accent : palette.text,
                    fontWeight: isKarsilastir
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  /// K5 (field test 09-30: the button was under the scrollable area and the user said
  /// "send does not go through"): "Ask a question" sits on the fixed control row (☰ / ■),
  /// and is shown only while a discussion is playing (the question goes to the playing discussion -- K4).
  Widget _buildAskQuestionButton(AppPalette palette) {
    return InkWell(
      key: const Key('steer-ask-question'),
      borderRadius: BorderRadius.circular(20),
      onTap: _showAskQuestionDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: palette.accent),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 16, color: palette.accent),
            const SizedBox(width: 4),
            Text('Ask', style: TextStyle(fontSize: 13, color: palette.accent)),
          ],
        ),
      ),
    );
  }

  Widget _buildControlRow(AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: const Icon(Icons.list),
            tooltip: 'Conversation list',
            onPressed: _playedTurns.isNotEmpty || !_isRunning
                ? _showListSheet
                : _showListSheet,
          ),
          if (_isRunning && !_isStopped)
            Semantics(
              button: true,
              label: 'Stop discussion',
              child: GestureDetector(
                key: const Key('discussion-stop-control'),
                onTap: _stopDiscussion,
                child: Container(
                  width: 94,
                  height: 94,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [palette.accent, palette.accent2],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.stop, size: 40, color: Colors.white),
                ),
              ),
            )
          else
            Semantics(
              button: true,
              label: 'Start discussion',
              child: GestureDetector(
                onTap: _showStartDialog,
                child: Container(
                  width: 94,
                  height: 94,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [palette.accent, palette.accent2],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.play_arrow,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          if (_isRunning && !_isStopped) _buildAskQuestionButton(palette),
        ],
      ),
    );
  }
}
