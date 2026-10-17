import 'package:meta/meta.dart';
import 'package:sesli_kitap/src/voices.dart';

enum DiscussionSpeaker { a, b, c, d }

/// A single turn in a two-voice discussion.
@immutable
class DiscussionTurn {
  const DiscussionTurn(this.speaker, this.text);

  final DiscussionSpeaker speaker;
  final String text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscussionTurn &&
          runtimeType == other.runtimeType &&
          speaker == other.speaker &&
          text == other.text;

  @override
  int get hashCode => Object.hash(speaker, text);
}

/// Exception thrown when script parsing fails.
class DiscussionParseException implements Exception {
  DiscussionParseException(this.reason);
  final String reason;

  @override
  String toString() => 'DiscussionParseException: $reason';
}

// Helper to strip common markdown / list prefixes from a line.
// Returns the line without the decoration, or null if the line should be
// skipped entirely (code fence).
String? _stripMarkdown(String line) {
  // Skip code fences entirely.
  if (line.startsWith('```')) return null;

  // Remove leading list numbers (1. ), dashes (-), blockquotes (>), headings (#),
  // and any surrounding bold/italic markers later handled by label regex.
  // We apply it only once; the label regex will clean remaining markers.
  final listOrQuote = RegExp(r'^\s*(?:\d+\.\s*|[-#>]\s+)');
  return line.replaceFirst(listOrQuote, '').trim();
}

/// Parses a raw script of "A:"/"B:" lines into [DiscussionTurn]s.
List<DiscussionTurn> parseDiscussionScript(String raw) {
  final lines = raw.split('\n');
  final result = <DiscussionTurn>[];

  // Label regex: optional bold opening, speaker letter, optional spaces, colon,
  // optional bold closing, then optional spaces and the rest of the text.
  // Now supports letters A-D (case insensitive).
  final labelRegex = RegExp(r'^(?:\*\*)?([A-Da-d])\s*:(?:\*\*)?\s*(.*)');

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    // Skip code fences.
    if (trimmed.startsWith('```')) continue;

    // Strip list / quote prefixes.
    final stripped = _stripMarkdown(trimmed);
    if (stripped == null || stripped.isEmpty) continue;

    // Try to match a speaker label.
    final match = labelRegex.firstMatch(stripped);
    if (match != null) {
      final speakerLetter = match.group(1)!.toLowerCase();
      final speaker = const {
        'a': DiscussionSpeaker.a,
        'b': DiscussionSpeaker.b,
        'c': DiscussionSpeaker.c,
        'd': DiscussionSpeaker.d,
      }[speakerLetter]!;
      var text = match.group(2)!.trim();
      // Strip parenthetical and bracketed stage directions.
      text = text.replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), '');
      text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isNotEmpty) {
        result.add(DiscussionTurn(speaker, text));
      }
    } else {
      // Continuation line.
      if (result.isNotEmpty) {
        final last = result.removeLast();
        result.add(DiscussionTurn(last.speaker, '${last.text} $stripped'));
      }
    }
  }

  if (result.isEmpty) {
    throw DiscussionParseException('No valid turns found');
  }
  return result;
}

/// Maps a speaker to the corresponding Sesli voice.
SesliVoice voiceForSpeaker(DiscussionSpeaker speaker) {
  switch (speaker) {
    case DiscussionSpeaker.a:
      return SesliVoice.wavenetB;
    case DiscussionSpeaker.b:
      return SesliVoice.aoede;
    case DiscussionSpeaker.c:
      return SesliVoice.wavenetE;
    case DiscussionSpeaker.d:
      return SesliVoice.wavenetC;
  }
}
