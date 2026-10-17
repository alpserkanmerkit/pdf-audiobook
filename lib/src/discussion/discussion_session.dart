// DQ-3: Discussion "resume where you left off" core.
// Pure persistence model: stores only text (topic + turns + played index).
// Audio is NOT persisted in the cache (the played turn file is deleted right
// away, and the sweepAudio run at startup cleans up leftovers) -> resume is
// re-synthesized from the text, so this model holds NO mp3 path. Real
// prefs/file io + UI wiring is the NEXT wave; this file consists only of a pure
// model and pure functions (NO io).
import 'dart:convert';

import 'package:sesli_kitap/src/discussion/discussion_turn.dart';

/// Persistence schema version. Bumped only on breaking shape changes; any
/// other value (including missing) is treated as incompatible and yields null
/// on decode, matching the K11 "unknown version -> ignore" precedent.
const int kDiscussionSessionVersion = 1;

/// A snapshot of a discussion in progress: the topic, the turns generated so
/// far, and how far the user has listened. Pure data holder — no io.
class DiscussionSession {
  const DiscussionSession({
    required this.topic,
    required this.turns,
    required this.playedIndex,
    required this.openEnded,
    required this.createdAtMs,
    this.bookHash,
  });

  /// The discussion topic as given by the user.
  final String topic;

  /// All turns generated so far (opening batch + any continuations).
  final List<DiscussionTurn> turns;

  /// Index (into [turns]) of the last turn the user has actually heard.
  /// -1 means no turn has been played yet.
  final int playedIndex;

  /// Whether the discussion was started in "infinite" (open-ended) mode.
  final bool openEnded;

  /// Creation timestamp in epoch milliseconds.
  final int createdAtMs;

  /// Source book hash, or null if the session has no associated book.
  final String? bookHash;
}

const Map<DiscussionSpeaker, String> _speakerLetters = {
  DiscussionSpeaker.a: 'a',
  DiscussionSpeaker.b: 'b',
  DiscussionSpeaker.c: 'c',
  DiscussionSpeaker.d: 'd',
};

const Map<String, DiscussionSpeaker> _lettersToSpeaker = {
  'a': DiscussionSpeaker.a,
  'b': DiscussionSpeaker.b,
  'c': DiscussionSpeaker.c,
  'd': DiscussionSpeaker.d,
};

/// Whether a discussion has unplayed turns worth resuming.
///
/// false when: [session] is null, has no turns, or [DiscussionSession.playedIndex]
/// points at/past the last turn AND the discussion is finite (finished --
/// nothing more will ever be generated). [DiscussionSession.playedIndex]
/// pointing past turns.length-1 (corrupt data) is also false, defensively --
/// [sessionFromJsonString] already rejects this at decode time, but this
/// function stays defensive for directly-constructed sessions too.
///
/// ROOT-CAUSE COMPLETION (Round-2 adversarial review): in open-ended (infinite)
/// mode, "no known tail" (playedIndex==turns.length-1) does NOT mean "finished"
/// -- a continuation batch can always be pulled (DiscussionController.resume
/// handles exactly this case). Only in FINITE mode does having no tail mean the
/// discussion is really over.
bool isResumable(DiscussionSession? session) {
  if (session == null) return false;
  final turns = session.turns;
  if (turns.isEmpty) return false;
  if (session.playedIndex >= turns.length) return false;
  if (session.openEnded) return true;
  return session.playedIndex < turns.length - 1;
}

/// Serializes [session] to a compact JSON string suitable for writing to
/// a single cache file (atomic .tmp+rename is the caller's responsibility).
String sessionToJsonString(DiscussionSession session) {
  final map = <String, Object?>{
    'version': kDiscussionSessionVersion,
    'topic': session.topic,
    'turns': [
      for (final turn in session.turns)
        {'s': _speakerLetters[turn.speaker], 't': turn.text},
    ],
    'playedIndex': session.playedIndex,
    'openEnded': session.openEnded,
    'createdAtMs': session.createdAtMs,
    if (session.bookHash != null) 'bookHash': session.bookHash,
  };
  return jsonEncode(map);
}

/// Parses a JSON string (as produced by [sessionToJsonString]) back into a
/// [DiscussionSession]. Returns null for any malformed, incomplete,
/// wrongly-typed, or version-incompatible input — this is the tolerant entry
/// point the io layer is expected to call with raw (possibly absent or
/// corrupt) file contents.
DiscussionSession? sessionFromJsonString(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on Object catch (_) {
    return null;
  }

  if (decoded is! Map) return null;
  final map = decoded;

  final version = map['version'];
  if (version is! int || version != kDiscussionSessionVersion) return null;

  final topic = map['topic'];
  if (topic is! String) return null;

  final rawTurns = map['turns'];
  if (rawTurns is! List) return null;

  final turns = <DiscussionTurn>[];
  for (final entry in rawTurns) {
    if (entry is! Map) return null;
    final speakerLetter = entry['s'];
    final text = entry['t'];
    if (speakerLetter is! String || text is! String) return null;
    final speaker = _lettersToSpeaker[speakerLetter];
    if (speaker == null) return null;
    turns.add(DiscussionTurn(speaker, text));
  }

  final playedIndex = map['playedIndex'];
  if (playedIndex is! int) return null;
  // ROOT-CAUSE FIX (Bug#2, adversarial review): previously only the type was
  // checked, with NO RANGE check. -1 (no turn played yet) is the valid lower
  // bound; turns.length (or beyond) is invalid -- such a value would cause an
  // uncaught ArgumentError in callers using e.g. turns.take(playedIndex+1)
  // (take(negative)), or silently accept a meaningless index.
  if (playedIndex < -1 || playedIndex >= turns.length) return null;

  final openEnded = map['openEnded'];
  if (openEnded is! bool) return null;

  final createdAtMs = map['createdAtMs'];
  if (createdAtMs is! int) return null;

  final rawBookHash = map['bookHash'];
  if (rawBookHash != null && rawBookHash is! String) return null;
  final bookHash = rawBookHash as String?;

  return DiscussionSession(
    topic: topic,
    turns: turns,
    playedIndex: playedIndex,
    openEnded: openEnded,
    createdAtMs: createdAtMs,
    bookHash: bookHash,
  );
}
