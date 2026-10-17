// T9 RED test (oracle, 2026-10-04 night). lib/src/discussion/discussion_session.dart is written by a worker.
// Workbench plan "Out of scope": the "continue from where you left off" path has no book text -- the saved session carries no book identity. T9: the session carries the source book's hash of the discussion (optional).
//  - bookHash is optional (default null); when null, NO 'bookHash' key is written to JSON
//    (old session files and the old output format are not broken; version stays 1).
//  - Old (keyless) JSON -> decoded with bookHash null (backward compatibility).
//  - 'bookHash' present but not String/null -> tolerant entry-point rule: null (no session).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/discussion/discussion_session.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';

const _turns = [
  DiscussionTurn(DiscussionSpeaker.a, 'one'),
  DiscussionTurn(DiscussionSpeaker.b, 'two'),
];

Map<String, Object?> _baseMap() => {
  'version': kDiscussionSessionVersion,
  'topic': 'topic',
  'turns': [
    {'s': 'a', 't': 'one'},
    {'s': 'b', 't': 'two'},
  ],
  'playedIndex': 0,
  'openEnded': false,
  'createdAtMs': 1,
};

void main() {
  group('T9 DiscussionSession.bookHash', () {
    test('if bookHash is given, round-trip is lossless', () {
      const session = DiscussionSession(
        topic: 'topic',
        turns: _turns,
        playedIndex: 0,
        openEnded: true,
        createdAtMs: 7,
        bookHash: 'hq',
      );

      final decoded = sessionFromJsonString(sessionToJsonString(session));

      expect(decoded, isNotNull);
      expect(decoded!.bookHash, 'hq');
      expect(decoded.topic, 'topic');
      expect(decoded.turns, _turns);
      expect(decoded.openEnded, isTrue);
    });

    test(
      'if bookHash is not given, default is null and no key is written to JSON',
      () {
        const session = DiscussionSession(
          topic: 'topic',
          turns: _turns,
          playedIndex: 0,
          openEnded: false,
          createdAtMs: 1,
        );

        expect(session.bookHash, isNull);
        final map = jsonDecode(sessionToJsonString(session)) as Map;
        expect(map.containsKey('bookHash'), isFalse);
        expect(
          sessionFromJsonString(sessionToJsonString(session))!.bookHash,
          isNull,
        );
      },
    );

    test('old (no bookHash key) JSON is decoded backward-compatibly', () {
      final decoded = sessionFromJsonString(jsonEncode(_baseMap()));

      expect(decoded, isNotNull);
      expect(decoded!.bookHash, isNull);
      expect(decoded.playedIndex, 0);
    });

    test('explicit null bookHash is accepted (null)', () {
      final decoded = sessionFromJsonString(
        jsonEncode({..._baseMap(), 'bookHash': null}),
      );

      expect(decoded, isNotNull);
      expect(decoded!.bookHash, isNull);
    });

    test('wrong-type bookHash -> null (tolerant entry-point rule)', () {
      expect(
        sessionFromJsonString(jsonEncode({..._baseMap(), 'bookHash': 42})),
        isNull,
      );
      expect(
        sessionFromJsonString(
          jsonEncode({
            ..._baseMap(),
            'bookHash': ['hq'],
          }),
        ),
        isNull,
      );
    });
  });
}
