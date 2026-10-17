// DQ-3 RED test (oracle). lib/src/discussion/discussion_session.dart is written by a worker.
// Core of "continue from where you left off" for the discussion: PURE persistence model (model + json + resume eligibility).
// No audio/file io; audio is not kept in cache (sweep deletes it) -> resuming re-synthesizes from the text,
// so the model stores ONLY text (no mp3 path). Real prefs/file io + UI wiring is the NEXT wave (this file is pure model + pure functions).
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/discussion/discussion_session.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';

void main() {
  group('DiscussionSession round-trip', () {
    test('full session: toJson -> fromJson is lossless', () {
      const session = DiscussionSession(
        topic: 'How does AI change working life?',
        turns: [
          DiscussionTurn(
            DiscussionSpeaker.a,
            'Hello, let us discuss this today.',
          ),
          DiscussionTurn(
            DiscussionSpeaker.b,
            'I disagree, the data says something else.',
          ),
          DiscussionTurn(
            DiscussionSpeaker.c,
            'There is a point you both missed.',
          ),
          DiscussionTurn(
            DiscussionSpeaker.d,
            'Let me give a concrete example.',
          ),
        ],
        playedIndex: 1,
        openEnded: true,
        createdAtMs: 1751600000000,
      );

      final decoded = sessionFromJsonString(sessionToJsonString(session));

      expect(decoded, isNotNull);
      expect(decoded!.topic, session.topic);
      expect(decoded.turns, session.turns);
      expect(decoded.playedIndex, session.playedIndex);
      expect(decoded.openEnded, session.openEnded);
      expect(decoded.createdAtMs, session.createdAtMs);
    });

    test('single-turn session round-trips losslessly', () {
      const session = DiscussionSession(
        topic: 'Single-line topic',
        turns: [DiscussionTurn(DiscussionSpeaker.a, 'Single line.')],
        playedIndex: 0,
        openEnded: false,
        createdAtMs: 42,
      );

      final decoded = sessionFromJsonString(sessionToJsonString(session));

      expect(decoded, isNotNull);
      expect(decoded!.turns, hasLength(1));
      expect(
        decoded.turns.single,
        const DiscussionTurn(DiscussionSpeaker.a, 'Single line.'),
      );
      expect(decoded.playedIndex, 0);
      expect(decoded.openEnded, isFalse);
    });

    test('empty-turns session round-trip (turns stay an empty list)', () {
      const session = DiscussionSession(
        topic: 'No lines generated yet',
        turns: [],
        playedIndex: -1,
        openEnded: true,
        createdAtMs: 7,
      );

      final decoded = sessionFromJsonString(sessionToJsonString(session));

      expect(decoded, isNotNull);
      expect(decoded!.turns, isEmpty);
      expect(decoded.playedIndex, -1);
    });

    test(
      '4 different speakers (a/b/c/d) nested turn serialization is lossless',
      () {
        const session = DiscussionSession(
          topic: 'Speaker coverage test',
          turns: [
            DiscussionTurn(DiscussionSpeaker.a, 'A line'),
            DiscussionTurn(DiscussionSpeaker.b, 'B line'),
            DiscussionTurn(DiscussionSpeaker.c, 'C line'),
            DiscussionTurn(DiscussionSpeaker.d, 'D line'),
          ],
          playedIndex: 3,
          openEnded: false,
          createdAtMs: 100,
        );

        final decoded = sessionFromJsonString(sessionToJsonString(session));

        expect(decoded, isNotNull);
        expect(decoded!.turns.map((t) => t.speaker).toList(), [
          DiscussionSpeaker.a,
          DiscussionSpeaker.b,
          DiscussionSpeaker.c,
          DiscussionSpeaker.d,
        ]);
        expect(decoded.turns.map((t) => t.text).toList(), [
          'A line',
          'B line',
          'C line',
          'D line',
        ]);
      },
    );

    test(
      'text with special characters (quotes, newline, unicode) is preserved losslessly',
      () {
        const session = DiscussionSession(
          topic: 'Special character test "quoted" title',
          turns: [
            DiscussionTurn(
              DiscussionSpeaker.a,
              'Contains a "quote" and\nnew line: ünlü çağrı ığdır.',
            ),
          ],
          playedIndex: 0,
          openEnded: true,
          createdAtMs: 5,
        );

        final decoded = sessionFromJsonString(sessionToJsonString(session));

        expect(decoded, isNotNull);
        expect(decoded!.topic, session.topic);
        expect(decoded.turns.single.text, session.turns.single.text);
      },
    );
  });

  group('DiscussionSession.fromJson broken/missing/wrong-type -> null', () {
    test('invalid JSON text -> null', () {
      expect(sessionFromJsonString('{this is not valid json'), isNull);
    });

    test('JSON but not the expected map (list) -> null', () {
      expect(sessionFromJsonString('[1,2,3]'), isNull);
    });

    test('missing field: no topic -> null', () {
      const raw =
          '{"version":1,"turns":[],"playedIndex":-1,"openEnded":true,"createdAtMs":1}';
      expect(sessionFromJsonString(raw), isNull);
    });

    test('missing field: no turns -> null', () {
      const raw =
          '{"version":1,"topic":"x","playedIndex":-1,"openEnded":true,"createdAtMs":1}';
      expect(sessionFromJsonString(raw), isNull);
    });

    test('missing field: no playedIndex -> null', () {
      const raw =
          '{"version":1,"topic":"x","turns":[],"openEnded":true,"createdAtMs":1}';
      expect(sessionFromJsonString(raw), isNull);
    });

    test('wrong type: turns is not a list (string) -> null', () {
      const raw =
          '{"version":1,"topic":"x","turns":"broken","playedIndex":0,"openEnded":true,"createdAtMs":1}';
      expect(sessionFromJsonString(raw), isNull);
    });

    test('wrong type: playedIndex is not a number (string) -> null', () {
      const raw =
          '{"version":1,"topic":"x","turns":[],"playedIndex":"0","openEnded":true,"createdAtMs":1}';
      expect(sessionFromJsonString(raw), isNull);
    });

    test('wrong type: openEnded is not a bool (string) -> null', () {
      const raw =
          '{"version":1,"topic":"x","turns":[],"playedIndex":0,"openEnded":"yes","createdAtMs":1}';
      expect(sessionFromJsonString(raw), isNull);
    });

    test('wrong type: invalid speaker letter inside a turn -> null', () {
      const raw =
          '{"version":1,"topic":"x",'
          '"turns":[{"s":"z","t":"text"}],'
          '"playedIndex":0,"openEnded":true,"createdAtMs":1}';
      expect(sessionFromJsonString(raw), isNull);
    });

    test('wrong type: turn is not a map -> null', () {
      const raw =
          '{"version":1,"topic":"x",'
          '"turns":["plain-string"],'
          '"playedIndex":0,"openEnded":true,"createdAtMs":1}';
      expect(sessionFromJsonString(raw), isNull);
    });

    test('version mismatch: version 2 -> null', () {
      const raw =
          '{"version":2,"topic":"x","turns":[],"playedIndex":0,"openEnded":true,"createdAtMs":1}';
      expect(sessionFromJsonString(raw), isNull);
    });

    test('missing version: no version field -> null', () {
      const raw =
          '{"topic":"x","turns":[],"playedIndex":0,"openEnded":true,"createdAtMs":1}';
      expect(sessionFromJsonString(raw), isNull);
    });

    // ROOT-CAUSE FIX (Bug#2, adversarial-review): previously playedIndex was only
    // checked for "is it an int"; there was NO RANGE check. A broken/negative
    // playedIndex led to an uncaught ArgumentError in the
    // turns.take(playedIndex+1) call in _resumeDiscussion (take(negative)).
    test('playedIndex negative and not -1 (broken data) -> null', () {
      const raw =
          '{"version":1,"topic":"x","turns":[{"s":"a","t":"m"}],'
          '"playedIndex":-5,"openEnded":true,"createdAtMs":1}';
      expect(sessionFromJsonString(raw), isNull);
    });

    test(
      'playedIndex equal to or greater than the turns length (broken data) -> null',
      () {
        const raw =
            '{"version":1,"topic":"x","turns":[{"s":"a","t":"m"}],'
            '"playedIndex":1,"openEnded":true,"createdAtMs":1}';
        expect(sessionFromJsonString(raw), isNull);
      },
    );

    test(
      'playedIndex at the exact boundary (-1, no turn played) -> ACCEPTED',
      () {
        const raw =
            '{"version":1,"topic":"x","turns":[{"s":"a","t":"m"}],'
            '"playedIndex":-1,"openEnded":true,"createdAtMs":1}';
        expect(sessionFromJsonString(raw), isNotNull);
      },
    );

    test(
      'playedIndex at the exact boundary (turns.length-1, last turn) -> ACCEPTED',
      () {
        const raw =
            '{"version":1,"topic":"x","turns":[{"s":"a","t":"m"}],'
            '"playedIndex":0,"openEnded":true,"createdAtMs":1}';
        expect(sessionFromJsonString(raw), isNotNull);
      },
    );
  });

  group('isResumable', () {
    test('null session -> false', () {
      expect(isResumable(null), isFalse);
    });

    test('empty turns -> false', () {
      const session = DiscussionSession(
        topic: 'x',
        turns: [],
        playedIndex: -1,
        openEnded: true,
        createdAtMs: 1,
      );
      expect(isResumable(session), isFalse);
    });

    test('middle index (a turn to play remains) -> true', () {
      const session = DiscussionSession(
        topic: 'x',
        turns: [
          DiscussionTurn(DiscussionSpeaker.a, '1'),
          DiscussionTurn(DiscussionSpeaker.b, '2'),
          DiscussionTurn(DiscussionSpeaker.c, '3'),
        ],
        playedIndex: 1,
        openEnded: true,
        createdAtMs: 1,
      );
      expect(isResumable(session), isTrue);
    });

    test('last index (playedIndex == turns.length-1, finished) -> false', () {
      const session = DiscussionSession(
        topic: 'x',
        turns: [
          DiscussionTurn(DiscussionSpeaker.a, '1'),
          DiscussionTurn(DiscussionSpeaker.b, '2'),
        ],
        playedIndex: 1,
        openEnded: false,
        createdAtMs: 1,
      );
      expect(isResumable(session), isFalse);
    });

    test(
      'playedIndex beyond the turns.length boundary (broken data) -> false',
      () {
        const session = DiscussionSession(
          topic: 'x',
          turns: [DiscussionTurn(DiscussionSpeaker.a, '1')],
          playedIndex: 5,
          openEnded: true,
          createdAtMs: 1,
        );
        expect(isResumable(session), isFalse);
      },
    );

    test(
      'negative playedIndex and turns filled (no turn played yet) -> true',
      () {
        const session = DiscussionSession(
          topic: 'x',
          turns: [
            DiscussionTurn(DiscussionSpeaker.a, '1'),
            DiscussionTurn(DiscussionSpeaker.b, '2'),
          ],
          playedIndex: -1,
          openEnded: true,
          createdAtMs: 1,
        );
        expect(isResumable(session), isTrue);
      },
    );

    test(
      'single-turn session, nothing played (playedIndex -1) -> true (rule: a turn to play exists, turn=last)',
      () {
        const session = DiscussionSession(
          topic: 'x',
          turns: [DiscussionTurn(DiscussionSpeaker.a, 'single')],
          playedIndex: -1,
          openEnded: false,
          createdAtMs: 1,
        );
        // In a single-turn session -1 < (turns.length-1)=0, so it still counts as "a turn to play exists".
        expect(isResumable(session), isTrue);
      },
    );

    // ROOT-CAUSE COMPLETION (Round-2 adversarial-review): the endless-mode
    // continuation-batch fetch path of resume() (the degenerate-expansion branch
    // of DiscussionController.resume) was previously found to be "dead code",
    // because isResumable ALWAYS returned false when there was NO known tail
    // (playedIndex==turns.length-1), even in open-ended mode. But in endless mode
    // "no tail" does NOT mean "finished" -- the continuation batch can ALWAYS be fetched.
    // This test covers that missing branch.
    test(
      'endless mode with no tail left (playedIndex==turns.length-1) -> '
      'true (continuation batch can always be fetched, NOT considered finished)',
      () {
        const session = DiscussionSession(
          topic: 'x',
          turns: [
            DiscussionTurn(DiscussionSpeaker.a, '1'),
            DiscussionTurn(DiscussionSpeaker.b, '2'),
          ],
          playedIndex: 1, // == turns.length-1, everything played
          openEnded: true,
          createdAtMs: 1,
        );
        expect(isResumable(session), isTrue);
      },
    );

    test('finite mode with no tail left (playedIndex==turns.length-1) -> false '
        '(truly finished, no continuation batch possible -- regression: this line '
        'must not be broken by the endless-mode fix)', () {
      const session = DiscussionSession(
        topic: 'x',
        turns: [
          DiscussionTurn(DiscussionSpeaker.a, '1'),
          DiscussionTurn(DiscussionSpeaker.b, '2'),
        ],
        playedIndex: 1,
        openEnded: false,
        createdAtMs: 1,
      );
      expect(isResumable(session), isFalse);
    });
  });

  group(
    'sessionFromJsonString input tolerance (raw input the io layer will read)',
    () {
      test('null input -> null', () {
        expect(sessionFromJsonString(null), isNull);
      });

      test('empty string input -> null', () {
        expect(sessionFromJsonString(''), isNull);
      });

      test('whitespace-only input -> null', () {
        expect(sessionFromJsonString('   '), isNull);
      });

      test('garbage data (random text) -> null', () {
        expect(sessionFromJsonString('this is not json, plain text'), isNull);
      });

      test('valid json string -> returns the model', () {
        const session = DiscussionSession(
          topic: 'valid',
          turns: [DiscussionTurn(DiscussionSpeaker.a, 'hello')],
          playedIndex: 0,
          openEnded: true,
          createdAtMs: 9,
        );
        final jsonStr = sessionToJsonString(session);
        final decoded = sessionFromJsonString(jsonStr);
        expect(decoded, isNotNull);
        expect(decoded!.topic, 'valid');
      });
    },
  );
}
