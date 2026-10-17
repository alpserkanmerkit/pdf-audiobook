import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:sesli_kitap/io/llm_client.dart';
import 'package:sesli_kitap/src/discussion/discussion_book_source.dart';
import 'package:sesli_kitap/src/discussion/discussion_budget.dart';
import 'package:sesli_kitap/src/discussion/discussion_directive.dart';
import 'package:sesli_kitap/src/discussion/discussion_name_lint.dart';
import 'package:sesli_kitap/src/discussion/discussion_review.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';

/// Exception thrown when the LLM discussion call fails.
class LlmDiscussionException implements Exception {
  LlmDiscussionException(this.reason);
  final String reason;

  /// The discussion screen shows this EXACTLY to the user ('... error: $e')
  /// -> only the reason; the class name (English, developer info) is not printed.
  @override
  String toString() => reason;
}

/// User-facing text for a network-layer error: for a timeout, llm_client's own
/// message; for other connection errors (DNS, socket, ClientException -- their
/// raw text is in English) a fixed message.
String _networkErrorText(Exception e) => e is LlmTimeoutException
    ? e.toString()
    : 'Could not connect to the AI server. '
          'Check your internet connection and try again.';

/// Generates a four-voice discussion script for a given topic using LLM.
class LlmDiscussion {
  LlmDiscussion({
    this.apiKey = '',
    LlmAccess? access,
    http.Client? client,
    LlmSleep sleep = llmRealSleep,
  }) : access = access ?? LlmAccess.single(LlmProvider.gemini, apiKey),
       _client = client ?? http.Client(),
       _sleep = sleep;

  /// Legacy single Gemini key; used when [access] is not given.
  final String apiKey;

  /// Providers to try in order (from the Settings choice).
  final LlmAccess access;
  final http.Client _client;
  final LlmSleep _sleep;

  /// Common block of speaker stance + group dynamics + format/forbidden rules.
  /// Both [_systemPromptTemplate] and [_continuationSystemPrompt] are built from
  /// it, so the opening and the continuation share the same voices/constraints
  /// (no drift).
  /// CLOSED BOX (2026-09-30): [kClosedBoxRule] is at the START of this common
  /// block -> the first generation, the continuation batch and the listener-
  /// question answer all carry it verbatim.
  static const String _speakerRulesBlock =
      '''
$kClosedBoxRule

FOUR speakers: A, B, C and D. Each has a SEPARATE and CONFLICTING stance -- all four defend their own thesis, nobody is a referee.

SPEAKER STANCES (each TAKES ONE SIDE, defends it, never backs down):
- A -- Claimant: throws out a controversial, bold thesis and defends it to the end. Curious, impatient. Does not start with "Kesinlikle/Aynen/Evet" ("Absolutely/Exactly/Yes").
- B -- Opponent: rejects A's thesis; brings a concrete counter-example/evidence FROM THE TEXT. Does not ask abstract rhetorical questions.
- C -- Third front: puts forward a THIRD thesis that both A and B are wrong about, and DEFENDS it. May say "İkiniz de şunu atlıyorsunuz" ("You both skip this") but then MUST state its own position and stand behind it. NEVER says "ikiniz de haklısınız", "asıl mesele dengede", "çözüm yok" or similar referee/conciliatory talk -- C is also a SIDE, inside the fight.
- D -- Concretizer: brings the discussion down to earth with a concrete example/fact FROM THE TEXT and uses this data to refute the previous claim. At least once, turns to an earlier speaker (A or B) rather than the immediately preceding one, and targets their claim too.

REAL NAMES OF THE SPEAKERS: A=Ahmet, B=Emel, C=Deniz, D=Kaya. Speakers address each other ONLY by these real names; the letters A/B/C/D NEVER appear inside the speech (the line labels "A:"/"B:"/"C:"/"D:" stay AS THEY ARE; those letters are labels, not part of the line text). When replying to the previous speaker, use THEIR name; if it is unclear whom you reply to, do not use a name. A speaker NEVER addresses themselves (no talking to oneself).

GROUP DYNAMICS (break the round-robin and the hanging axis):
- A strict A->B->C->D->A turnstile is FORBIDDEN. Speakers interrupt each other, come back, and attack an earlier claim again.
- When C or D opens a new axis/claim, A or B explicitly takes it up within the NEXT 2 turns (attacks or refutes it). A new axis must NOT hang in the air -- if nobody answers, that thesis is dead weight, do not write it.
- EVERY speaker, at least once, explicitly refers to someone OTHER than the speaker immediately before them ("az önce Ahmet şunu dedi ama...").

GENERAL RULES:
- EVERY LINE is at least 3 and at most 4 sentences. Sentences connect: the speaker bridges what was said before and their own idea, and gives their reasoning and example in an explanatory tone. A one-sentence line is FORBIDDEN; but a monologue longer than 4 sentences is also FORBIDDEN.
- NO BRACKETS AT ALL -- neither square [] nor round (). Stage directions / narration / "(turning to A)" / "(interrupting)" are STRICTLY FORBIDDEN. Whoever turns to or interrupts whom must say so INSIDE the line ("Dur Ahmet, sözünü keseceğim...").
- Use only "..." for pauses.
- Natural speech texture: now and then (NOT in every line) a short filler like "yani", "dur", "aslında" may be used; do not slide into everyday chatter.
- The discussion is built on the claims, concepts and examples of the BOOK TEXT: EVERY line rests on a concrete claim, concept or example in the text and states it clearly ("metin rüyayı bir dilek doyumu sayıyor ama..."). To explain or refute an idea in the text, use ONLY the examples in the text (CLOSED BOX); general chat disconnected from the text is FORBIDDEN.
- You may mention the book's title, its author, and the thinkers and researchers named in the book.
- STYLE DIRECT AND HARSH: every line directly opposes the previous one or tries to refute it. You may target the opponent's ARGUMENT harshly, sarcastically, dismissively ("Bu tamamen saçma, çünkü metin tam tersini söylüyor..."). The discussion may end unresolved and tense.
- NO approval, conciliation or politeness filler ANYWHERE in the discussion: "haklısın", "haklısın ama", "güzel nokta", "katılıyorum" (you're right / good point / I agree), meeting in the middle, "barışalım", "iyilik olsun", "birbirimizi anlayalım" (let's make peace / well-wishes / let's understand each other), moral lessons, well-wishes.
- Boundary: no profanity, no personal insults, no hate speech -- attacks target the ARGUMENT, not the person.
- Write all dialogue in Turkish (the book is in Turkish). Use Turkish characters (ç, ş, ı, ğ, ü, ö) correctly and completely.

FORBIDDEN PATTERNS (I will reject them if I see them):
- A speaker paraphrasing the previous one and approving it.
- Approval/conciliation/politeness filler, moral lessons, reconciliation -- at the end or in the middle.
- C acting as an impartial referee/moderator (just saying "dengeliyorum" -- "I'm balancing" -- without holding a position).
- A sequential four-monologue (everyone adds their point, nobody touches anybody).
- Nobody answering an opened axis (hanging axis).
- Any brackets. Clichés ("madalyonun iki yüzü", "tarih tekerrür ediyor").''';

  /// System prompt - Dilim-2 v2 4-voice director prompt (converged).
  ///
  /// DQ-W1 REWORK: the LENGTH rule is now mode-dependent ([_lengthRuleFor]).
  /// In finite mode (Short/Medium/Long) one consistent target comes from the
  /// mode; the strict "12-16 lines" limit applies ONLY to infinite/null (the
  /// opening party).
  /// $_lengthRulePlaceholder is replaced at runtime with the mode rule.
  static const String _systemPromptTemplate =
      '''
You write a voice discussion script. $_speakerRulesBlock

GOAL: A lively, harsh, natural GROUP debate that argues a topic from four different stances. The listener must feel "four people are really arguing at the same table" -- not four monologues taken in turn, and not a neutral moderator.

$_lengthRulePlaceholder

CLOSING (MANDATORY CONSTRAINT):
- The conversation does NOT close with vague conciliation or referee summaries. The last line ends by EXPLICITLY NAMING an unresolved contradiction or a counter-evidence.
- Surrender or referee closings starting or ending with "belki", "tamam", "haklısın", "herkes haklı", "sonuçta hepimiz", "çözüm yok", "asıl mesele dengede" are FORBIDDEN.
- Meta-summaries in the last line ("hepimiz farklı açıdan baktık", "güzel tartışmaydı") or surrender are FORBIDDEN.

THE TOPIC AND SOURCE MATERIAL are given in the user message (book text, if any, is there in brackets).

If the topic/source material contains a line starting with "LISTENER DIRECTION:", the discussion works it into its flow from the start -- ignoring it is FORBIDDEN; but it must do so naturally, without breaking the discussion format.

Write ONLY the dialogue. No title/explanation/numbering. Use the line labels A:, B:, C:, D:.''';

  /// Placeholder inside [_systemPromptTemplate] where the mode-dependent LENGTH rule goes.
  static const String _lengthRulePlaceholder = '{{UZUNLUK_KURALI}}';

  /// The old strict LENGTH rule for infinite/null (opening party). In finite
  /// modes the mode target is used INSTEAD of this (to avoid contradiction).
  static const String _openingLengthRule =
      'LENGTH: AT LEAST 12, at most 16 lines. Each of the four speakers speaks at least 3 times.';

  /// Observed average length of LLM lines is ~65 words, with the 3-4 sentence
  /// line rule. computeTargetTurns derives the target turn count from it; the
  /// duration label (~N min) is word-based and stays consistent.
  static const int _avgWordsPerTurn = 65;

  /// System prompt for the continuation party (infinite mode). Shares the same
  /// voices/constraints, BUT: it does not rewrite the given lines, and the
  /// discussion does NOT end.
  static const String _continuationSystemPrompt =
      '''
You are a scenario writer who continues an ongoing voice discussion FROM WHERE IT LEFT OFF. $_speakerRulesBlock

CONTINUATION RULES (MANDATORY):
- Write AT LEAST 8 and at most 12 NEW lines. Return ONLY the NEW lines.
- Do NOT rewrite, paraphrase or summarize the previous lines given to you.
- Repeating the same argument is FORBIDDEN -- every new line brings a new example, front or counter-evidence from the text.
- THE DISCUSSION DOES NOT END: no closing, farewell, summary, conciliation or referee verdict; wrap-up phrases such as "toparlarsak" and "sonuç olarak" are FORBIDDEN.
- The last line leaves a NEW claim or counter-example waiting for an answer -- wrap nothing up.
- Surrender/conciliation with "belki", "tamam", "haklısın", "herkes haklı", "çözüm yok", "asıl mesele dengede" is FORBIDDEN.
- EVERY LINE again has at least 3 and at most 4 sentences (in continuation parties line length tends to grow over time; do not exceed 4 sentences).
- Do NOT reuse the examples and METAPHORS from earlier lines from the same angle -- move to another example in the text; if no new example is left in the text, treat the same text example from a different angle, and do NOT INVENT images or examples from outside the text.
- A sentence that merges both sides, partly justifying both ("ikisi de gerekli", "ikisi birlikte") is also FORBIDDEN -- EVERY speaker, C included, keeps defending ONE clear thesis.
- If the material below contains a line starting with "LISTENER DIRECTION:", the speakers address it within the NEXT 2-3 lines explicitly -- ignoring it is FORBIDDEN; but without breaking the discussion format, as a natural reply from one of them.

Write ONLY the NEW dialogue. No title/explanation/numbering. Use the line labels A:, B:, C:, D:.''';

  /// Listener-question answer party system prompt (K4, 2026-09-30). The same
  /// common block (including the closed box) + short answer rules.
  static const String _answerSystemPrompt =
      '''
You are a scenario writer. When a question arrives from the listener during an ongoing voice discussion, you write a short answer segment that enters the MIDDLE of the discussion. $_speakerRulesBlock

ANSWER RULES (MANDATORY):
- Write AT LEAST 2 and at most 4 NEW lines. Return ONLY the NEW lines.
- The first line briefly mentions the listener's question and starts answering it; the speakers answer the question from their own stances.
- The answer relies ONLY on the BOOK TEXT; if the text does not answer the question, the speaker says so explicitly (in Turkish: "kitapta bu geçmiyor" -- "this is not in the book") and does not speculate.
- The last line ties the discussion back to where it was left; no closing, farewell or summary.
- Do NOT rewrite the previous lines given to you.

Write ONLY the NEW dialogue. No title/explanation/numbering. Use the line labels A:, B:, C:, D:.''';

  /// Maximum number of lines played for the answer party (if the model writes
  /// more, the rest is dropped -- so the discussion is not interrupted for long).
  static const int _answerMaxTurns = 4;

  /// Generates a discussion for the given [topicAndSource].
  ///
  /// If [mode] is given (DQ-W1: length-mode selector) and it has a finite target
  /// (Short/Medium/Long), the LENGTH rule is REPLACED by the mode target (the
  /// strict 12-16 limit is NOT added -- to avoid contradiction) and max_tokens
  /// scales with the mode. If [mode] is not given OR is [DiscussionLengthMode.sonsuz]
  /// (infinite), the old opening-party rule (12-16 lines) and the 3000 token ceiling are used.
  /// Returns a list of [DiscussionTurn]s parsed from the LLM response.
  Future<List<DiscussionTurn>> generate(
    String topicAndSource, {
    DiscussionLengthMode? mode,
  }) {
    final sys = _systemPromptTemplate.replaceFirst(
      _lengthRulePlaceholder,
      _lengthRuleFor(mode),
    );
    return _complete([
      {'role': 'system', 'content': sys},
      {
        'role': 'user',
        'content': 'TOPIC AND SOURCE MATERIAL:\n$topicAndSource',
      },
    ], maxTokens: _maxTokensFor(mode));
  }

  /// DQ-W2: "author -> review -> fix" chain. First [generate] produces the
  /// author's script; then, per the [shouldReview] policy, batch 1 (batchIndex 0)
  /// ALWAYS goes through the reviewer: a second LLM call with [reviewerPrompt],
  /// the reply is parsed with [parseReviewResponse] and [applyReviewCorrections]
  /// is applied (name/repetition/length fixes). FAIL-OPEN: if the reviewer call/
  /// parse fails in ANY way (HTTP error, broken body, off-schema reply) the
  /// original (uncorrected) script is returned AS IS; the flow NEVER breaks.
  /// If the author call fails (no script produced) the same typed-exception
  /// contract as [generate] is kept ([LlmDiscussionException] surfaces).
  ///
  /// [generate]/[generateContinuation] are NOT modified -- this new public method
  /// adds the review layer on top of them.
  Future<List<DiscussionTurn>> generateReviewed(
    String topicAndSource, {
    DiscussionLengthMode? mode,
  }) async {
    // Author call: its failure leaks the same typed exception as generate
    // (there is no script to review).
    final turns = await generate(topicAndSource, mode: mode);

    // Batch-1 policy: the first batch is ALWAYS reviewed (first impression + the
    // most critical moment for the name rule). Later layers (io/controller) may
    // apply the lint-gated review branch for later batches.
    if (!shouldReview(batchIndex: 0)) return turns;

    // FAIL-OPEN: if the reviewer call/parse fails, keep the original.
    // Rule-based name findings (lintDiscussionNames) go to the reviewer as
    // numbered "AUTOMATIC FLAGS" (like undeletable self-address -- measurement:
    // the reviewer alone caught 0/4 without flags).
    final reviewContent = await _reviewRawContent(
      turns,
      lintDiscussionNames(turns),
    );
    if (reviewContent == null) return turns;

    final review = parseReviewResponse(reviewContent);
    if (review == null) return turns;

    // The reviewer itself can also produce self-address (measurement T3) ->
    // a final deterministic pass is applied to the corrected text too.
    return removeSelfAddress(applyReviewCorrections(turns, review));
  }

  /// Reviewer call: the [reviewerPrompt] system message + the batch text as the
  /// user message go to the LLM; returns the raw `content` string. FAIL-OPEN:
  /// HTTP != 200, network error, non-JSON body or empty content -> null (the
  /// caller reads null as "do not trust the reviewer, keep the original"); no
  /// exception escapes. Kept SEPARATE from [generate]'s typed-exception chain,
  /// because the reviewer returns JSON, not an A:/B: script.
  Future<String?> _reviewRawContent(
    List<DiscussionTurn> turns,
    List<DiscussionNameLintIssue> hints,
  ) async {
    // Each line is numbered with a 0-based "#<index>": in an unnumbered batch the
    // model counted the lines itself and got it wrong (measurement T3: 35 instead of #36).
    final party = [
      for (var i = 0; i < turns.length; i++)
        '#$i ${turns[i].speaker.name.toUpperCase()}: ${turns[i].text}',
    ].join('\n');
    final hintBlock = hints.isEmpty
        ? ''
        : '\n\nAUTOMATIC FLAGS (rule-based; may be false alarms, fix only if truly wrong):\n'
              '${hints.map((h) => '- #${h.turnIndex} ${h.category.name}: ${h.detail}').join('\n')}';
    final http.Response resp;
    try {
      resp = await postChatCompletion(
        _client,
        access: access,
        sleep: _sleep,
        body: {
          'messages': [
            {'role': 'system', 'content': reviewerPrompt},
            {'role': 'user', 'content': 'SEGMENT:\n$party$hintBlock'},
          ],
          'stream': false,
          'temperature': 0.2,
          'top_p': 1,
          'max_tokens': 3000,
          // JSON mode (same as cleaner/auditor; proven live on Gemini):
          // in a live measurement the reviewer wrote a line-by-line audit list
          // instead of JSON and hit the ceiling (agent3 L1) -> parsing failed.
          'response_format': {'type': 'json_object'},
        },
      );
    } on Exception {
      return null;
    }

    if (resp.statusCode != 200) return null;

    final Object? data;
    try {
      data = jsonDecode(utf8.decode(resp.bodyBytes));
    } on FormatException {
      return null;
    }
    if (data is! Map<String, dynamic>) return null;

    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final message = first['message'];
    final content = (message is Map) ? message['content'] : null;
    if (content is! String || content.trim().isEmpty) return null;
    return content;
  }

  /// Mode-dependent LENGTH rule. In finite mode (Short/Medium/Long) one
  /// consistent target comes from the mode: target words + a rough turn count
  /// (using the [_avgWordsPerTurn] average). Infinite/null -> the old strict
  /// 12-16 opening rule.
  String _lengthRuleFor(DiscussionLengthMode? mode) {
    final targetWords = mode == null ? null : targetWordsFor(mode);
    if (targetWords == null) return _openingLengthRule;
    final targetTurns = computeTargetTurns(
      targetWords: targetWords,
      avgWordsPerTurn: _avgWordsPerTurn,
    );
    return 'TARGET WORDS: The total line word target for this discussion is '
        '~$targetWords words (~$targetTurns lines). All four speakers speak in a '
        'balanced way; produce enough lines to approach this target, do not close early.';
  }

  /// max_tokens scales with the mode. Measurement (2026-09-28, 5 live runs,
  /// gemini-3.8-flash): the model EXCEEDS the word target by 17-29%, tokens/word
  /// 2.12-2.23; the old Long ceiling (6000) was filled in 2/2 runs (one was cut
  /// off mid-way). Ceiling = target words x 1.3 (overshoot) x 2.25 (tokens/word)
  /// x 1.2 (margin), rounded to 500: Short 550->2000, Medium 1100->4000,
  /// Long 2150->8000. Unused ceiling is not billed; the model stops by itself near the target.
  /// Infinite/null -> the old 2000 opening ceiling was too short for longer lines (measured).
  int _maxTokensFor(DiscussionLengthMode? mode) {
    switch (mode) {
      case DiscussionLengthMode.kisa:
        return 2000;
      case DiscussionLengthMode.orta:
        return 4000;
      case DiscussionLengthMode.uzun:
        return 8000;
      case DiscussionLengthMode.sonsuz:
      case null:
        return 3000;
    }
  }

  /// Infinite mode: produces a NEW continuation party given the topic + recent
  /// lines as context; returns only the NEW lines.
  /// [recentTurns] is the last-K lines (context).
  Future<List<DiscussionTurn>> generateContinuation(
    String topicAndSource,
    List<DiscussionTurn> recentTurns,
  ) {
    final history = recentTurns
        .map((t) => '${t.speaker.name.toUpperCase()}: ${t.text}')
        .join('\n');
    return _complete([
      {'role': 'system', 'content': _continuationSystemPrompt},
      {
        'role': 'user',
        'content':
            'TOPIC AND SOURCE MATERIAL:\n$topicAndSource\n\n'
            'LAST LINES SO FAR:\n$history\n\n'
            'Continue from where it left off. Write only the NEW lines.',
      },
    ]);
  }

  /// Listener question (K4): with the topic + book text + recent lines + the
  /// question, produces a short answer party of 2-4 lines (including the closed-box
  /// rule). The question is reduced to a single line with [sanitizeListenerText]
  /// so it cannot imitate the prompt's block structure. Returns at most [_answerMaxTurns] lines.
  Future<List<DiscussionTurn>> generateAnswer(
    String topicAndSource,
    String question,
    List<DiscussionTurn> recentTurns,
  ) async {
    final history = recentTurns
        .map((t) => '${t.speaker.name.toUpperCase()}: ${t.text}')
        .join('\n');
    final turns = await _complete([
      {'role': 'system', 'content': _answerSystemPrompt},
      {
        'role': 'user',
        'content':
            'TOPIC AND SOURCE MATERIAL:\n$topicAndSource\n\n'
            'LAST LINES SO FAR:\n$history\n\n'
            'LISTENER QUESTION: ${sanitizeListenerText(question)}\n\n'
            'Write only the answer lines.',
      },
    ], maxTokens: 2000);
    return turns.take(_answerMaxTurns).toList();
  }

  /// Shared HTTP/parse chain: [messages] -> LLM -> parse -> turns.
  /// generate and generateContinuation share the same typed-exception contract.
  /// [maxTokens] scales with the mode (default 3000 -- continuation/opening ceiling).
  Future<List<DiscussionTurn>> _complete(
    List<Map<String, String>> messages, {
    int maxTokens = 3000,
  }) async {
    final http.Response resp;
    try {
      resp = await postChatCompletion(
        _client,
        access: access,
        sleep: _sleep,
        body: {
          'messages': messages,
          'stream': false,
          'temperature': 0.85,
          'top_p': 1,
          'max_tokens': maxTokens,
        },
      );
    } on Exception catch (e) {
      throw LlmDiscussionException(_networkErrorText(e));
    }

    if (resp.statusCode != 200) {
      final body = utf8.decode(resp.bodyBytes);
      throw LlmDiscussionException(
        'HTTP ${resp.statusCode}: '
        '${body.substring(0, body.length > 300 ? 300 : body.length)}',
      );
    }

    // K9: HTTP 200 + non-JSON body (e.g. a gateway HTML page) must not escape as a
    // raw FormatException -> the typed exception contract is kept.
    final Object? data;
    try {
      data = jsonDecode(utf8.decode(resp.bodyBytes));
    } on FormatException catch (e) {
      throw LlmDiscussionException('invalid JSON body: ${e.message}');
    }
    if (data is! Map<String, dynamic>) {
      throw LlmDiscussionException('Unexpected response format');
    }

    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      throw LlmDiscussionException('Empty choices');
    }

    final first = choices.first;
    if (first is! Map) {
      throw LlmDiscussionException('choices[0] is not a map');
    }

    final message = first['message'];
    final content = (message is Map) ? message['content'] : null;
    if (content is! String || content.trim().isEmpty) {
      throw LlmDiscussionException('Empty response content');
    }

    final List<DiscussionTurn> turns;
    try {
      turns = parseDiscussionScript(content);
    } on DiscussionParseException {
      throw LlmDiscussionException('Response is not a valid A:/B: script');
    }

    // finish_reason == "length": the model hit the max_tokens ceiling and the LAST
    // line it wrote was cut mid-way (measurement T3: 5996/6000, a half sentence
    // with no punctuation). A half line is not played: it is dropped and the
    // previous COMPLETE lines remain. A follow-up call (extra request + delay) was
    // rejected in favour of dropping; since ceilings were raised per measurement,
    // this path is a rare safety net.
    var complete = turns;
    if (first['finish_reason'] == 'length') {
      if (turns.length < 2) {
        throw LlmDiscussionException(
          'Response was cut off in the first line; no complete line to play.',
        );
      }
      complete = turns.sublist(0, turns.length - 1);
    }
    // Self-address ("speaking as Deniz") is removed deterministically -- for the
    // author and all continuation parties (continuation parties skip the reviewer).
    return removeSelfAddress(complete);
  }
}
