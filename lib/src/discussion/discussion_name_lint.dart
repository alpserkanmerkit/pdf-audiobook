// PR-Q1 (finding #6 name fix, DESIGN §2/§3): pure, fully covered name lint.
// A strict name rule was added to the LLM prompt (_speakerRulesBlock in
// llm_discussion.dart). This function is the CODE-SIDE SAFETY NET for that rule:
// it deterministically detects the violations the prompt still misses.
// WIRED (2026-09-28 night): LlmDiscussion.generateReviewed sends the findings to
// the reviewer as "AUTOMATIC FLAGS"; [removeSelfAddress] is applied to all
// author/continuation/reviewer output (measured: 2 self-addresses in 119 lines,
// the reviewer caught 0/4).
//
// Three categories:
//  - harfToken: a single letter A/B/C/D appears INSIDE the line text (not as a
//    label) -- the model addressing someone by letter (finding #6 root cause).
//  - yanlisAd (wrong name): the line opens with a vocative "Name," but Name is
//    NOT the real name of the PREVIOUS turn's speaker (addressing the wrong person).
//  - kendiAdi (self name): the speaker uses their OWN name -- opening with
//    "Name,", "<Name> olarak" ("as <Name>"), "ben <Name>" ("I am <Name>"), or
//    referring to themselves in the third person as "<Name>'in" (measured
//    2026-09-28: "Deniz olarak soyluyorum", "Kaya olarak altini cizerim").
import 'package:sesli_kitap/src/discussion/discussion_presenter.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';
import 'package:sesli_kitap/src/turkish_case.dart';

enum DiscussionNameLintCategory { harfToken, yanlisAd, kendiAdi }

/// A single name-lint finding: in which turn ([turnIndex]) and in which category.
class DiscussionNameLintIssue {
  const DiscussionNameLintIssue({
    required this.turnIndex,
    required this.category,
    required this.detail,
  });

  final int turnIndex;
  final DiscussionNameLintCategory category;
  final String detail;
}

// Speaker -> real name table (same source as discussion_presenter.speakerName;
// kept here too so the lint stays pure/independent -- speakerName is already
// pure, so calling it directly is also fine).
const List<String> _allSpeakerNames = ['Ahmet', 'Emel', 'Deniz', 'Kaya'];

/// Looks for a single A/B/C/D letter token inside the line text (word
/// boundaries: it must be surrounded by spaces/punctuation, not part of a name).
/// The "A" inside "Ahmet" does not trigger; the leading "A" in "A haklı"
/// does.
final RegExp _letterTokenPattern = RegExp(
  r'(?:^|[\s,.;:!?"'
  "'"
  r'])([ABCD])(?=$|[\s,.;:!?"'
  "'"
  '])',
);

/// Vocative address: does the line start with "Name,"? (Name = one of the 4
/// known speakers, followed by a comma.)
final RegExp _vocativePattern = RegExp(r'^([A-ZÇŞİĞÜÖ][a-zçşığüö]+),\s*');

/// The speaker naming THEMSELVES in the text (capitalized proper name):
/// "Name olarak" ("as Name"), "ben Name" ("I am Name"), "Name'in" / "Name’in"
/// (Name = their own name). A lowercase common noun ("engin bir deniz olarak")
/// and "Deniz aşırı" (abroad) do not match.
RegExp _selfMentionPattern(String own) => RegExp(
  '(?<!\\p{L})(?:$own\\s+olarak(?!\\p{L})|[Bb]en\\s+$own(?!\\p{L})|'
  "$own['’]\\p{L})",
  unicode: true,
);

/// Checks [turns] for name consistency; returns the violations found, in order
/// (an empty list means a clean script).
List<DiscussionNameLintIssue> lintDiscussionNames(List<DiscussionTurn> turns) {
  final issues = <DiscussionNameLintIssue>[];

  for (var i = 0; i < turns.length; i++) {
    final turn = turns[i];
    final ownName = speakerName(turn.speaker);

    // 1) harfToken: a standalone A/B/C/D inside the text.
    for (final m in _letterTokenPattern.allMatches(turn.text)) {
      issues.add(
        DiscussionNameLintIssue(
          turnIndex: i,
          category: DiscussionNameLintCategory.harfToken,
          detail:
              'single-letter token "${m.group(1)}" appeared in the line text',
        ),
      );
    }

    // 2) vocative check: does the line start with "Name,"?
    var selfFlagged = false;
    final vocativeMatch = _vocativePattern.firstMatch(turn.text);
    if (vocativeMatch != null) {
      final vocativeName = vocativeMatch.group(1)!;
      if (_allSpeakerNames.contains(vocativeName)) {
        if (vocativeName == ownName) {
          // kendiAdi: the speaker opens with their own name.
          selfFlagged = true;
          issues.add(
            DiscussionNameLintIssue(
              turnIndex: i,
              category: DiscussionNameLintCategory.kendiAdi,
              detail: '$ownName opens with their own name',
            ),
          );
        } else if (i > 0) {
          // yanlisAd: the vocative name is NOT the previous turn's speaker.
          final prevName = speakerName(turns[i - 1].speaker);
          if (vocativeName != prevName) {
            issues.add(
              DiscussionNameLintIssue(
                turnIndex: i,
                category: DiscussionNameLintCategory.yanlisAd,
                detail:
                    '"$vocativeName," as a form of address does not match '
                    'the previous speaker "$prevName"',
              ),
            );
          }
        }
      }
    }

    // 3) kendiAdi: the speaker mentions their own name in the text (one finding per line).
    if (!selfFlagged && _selfMentionPattern(ownName).hasMatch(turn.text)) {
      issues.add(
        DiscussionNameLintIssue(
          turnIndex: i,
          category: DiscussionNameLintCategory.kendiAdi,
          detail: '$ownName mentions their own name',
        ),
      );
    }
  }

  return issues;
}

/// Deterministically extracts the forms of self-address that can be REMOVED
/// without breaking the grammar: "Name olarak " ("as Name", e.g. "Deniz olarak
/// söylüyorum" -> "söylüyorum"), "ben Name" -> "ben", and a leading "Name, ".
/// If the removed pattern was at the start of a sentence, the next letter is
/// capitalized. Third-person self-reference ("Emel'in elestirisi") CANNOT be
/// removed (the sentence would break) -- [lintDiscussionNames] flags it and
/// leaves it to the reviewer. Speaker, order and turn count do not change.
List<DiscussionTurn> removeSelfAddress(List<DiscussionTurn> turns) => [
  for (final t in turns)
    DiscussionTurn(
      t.speaker,
      _stripSelfAddress(t.text, speakerName(t.speaker)),
    ),
];

String _stripSelfAddress(String text, String own) {
  var out = text.replaceAllMapped(
    RegExp('(?<!\\p{L})$own\\s+olarak\\s+(\\p{L})', unicode: true),
    (m) => _nextLetter(m.input, m.start, m.group(1)!),
  );
  out = out.replaceAllMapped(
    RegExp('(?<!\\p{L})([Bb]en)\\s+$own(?!\\p{L})', unicode: true),
    (m) => m.group(1)!,
  );
  return out.replaceFirstMapped(
    RegExp('^$own,\\s*(\\p{L})', unicode: true),
    (m) => turkishUpper(m.group(1)!),
  );
}

/// If the removed pattern was at the start of a sentence (start of text, or
/// after . ! ?), capitalizes the next letter; otherwise leaves it as it is.
String _nextLetter(String input, int start, String letter) {
  final before = input.substring(0, start).trimRight();
  final sentenceStart = before.isEmpty || RegExp(r'[.!?]$').hasMatch(before);
  return sentenceStart ? turkishUpper(letter) : letter;
}
