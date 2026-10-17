// Oracle RED test (2026-09-28 night, measurement report item 2): in long mode the
// author's reply hits the max_tokens cap and is cut off MID-SENTENCE (T3:
// 5996/6000, finish_reason=length, last line "...but the conclusion is still
// incomplete" -- a sentence cut without punctuation). The app PLAYED that partial
// line, because the code never read finish_reason.
//
// Pinned contract:
//  1) finish_reason == "length" -> the last (cut) line does NOT enter the playback
//     queue; the earlier complete lines stay as they are.
//  2) finish_reason == "stop" -> no line is dropped (no over-trimming).
//  3) If NO complete line remains in a cut reply (cut in the first line) -> a typed
//     LlmDiscussionException (there is no valid script to play).
//  4) The continuation batch (generateContinuation) follows the same rule (shared
//     chain).
//  5) Mode caps meet the MEASURED need: cap >= target words x 1.29 (measured worst
//     word overshoot, Long 2779/2150) x 2.23 (measured worst tokens/word, Endless
//     1515/679). The old 1500/3000/6000 are below this bound.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sesli_kitap/io/llm_discussion.dart';
import 'package:sesli_kitap/src/discussion/discussion_budget.dart';
import 'package:sesli_kitap/src/discussion/discussion_controller.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';

http.Response _resp(String content, {String? finishReason}) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': content},
        'finish_reason': ?finishReason,
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

bool _isReviewer(http.Request req) {
  final body = jsonDecode(req.body) as Map<String, dynamic>;
  final sys = ((body['messages'] as List)[0] as Map)['content'] as String;
  return sys.contains('"corrections"');
}

// Shortened form of the T3 case: two complete lines + a third cut mid-sentence.
const String _tamA =
    'Ruyalar rastgele gurultu degildir. Her parca bir dusunce zincirine '
    'baglanir. Zinciri izlersen arzuya varirsin.';
const String _tamB =
    'Ahmet, bu yontem yanlislanamaz. Her celiskiyi direnc diye aciklarsan '
    'hicbir kanit seni curutemez. Bilim boyle isleyemez.';
const String _yarimC =
    "Emel'in yanlislanabilirlik elestirisi Ahmet'in kati arzu formulunu tam "
    'merkezinden vuruyor ama vardigi sonuc yine eksik';
const String _kesikScript = 'A: $_tamA\nB: $_tamB\nC: $_yarimC';

void main() {
  group(
    'finish_reason=length -> the partial last line does NOT enter the playback queue',
    () {
      test(
        'generateReviewed: the cut last line is dropped, complete lines remain',
        () async {
          final mock = MockClient((req) async {
            if (_isReviewer(req)) {
              return _resp(
                '{"ok": true, "corrections": []}',
                finishReason: 'stop',
              );
            }
            return _resp(_kesikScript, finishReason: 'length');
          });

          final turns = await LlmDiscussion(
            apiKey: 'k',
            client: mock,
          ).generateReviewed('topic', mode: DiscussionLengthMode.uzun);

          expect(turns.map((t) => t.text), isNot(contains(_yarimC)));
          expect(turns, hasLength(2));
          expect(turns[0], const DiscussionTurn(DiscussionSpeaker.a, _tamA));
          expect(turns[1], const DiscussionTurn(DiscussionSpeaker.b, _tamB));
        },
      );

      test(
        'via DiscussionController: the partial line is neither synthesized nor played',
        () async {
          final mock = MockClient((req) async {
            if (_isReviewer(req)) {
              return _resp(
                '{"ok": true, "corrections": []}',
                finishReason: 'stop',
              );
            }
            return _resp(_kesikScript, finishReason: 'length');
          });
          final llm = LlmDiscussion(apiKey: 'k', client: mock);
          final synthesized = <String>[];
          final played = <String>[];

          await DiscussionController(
            generate: (topic) =>
                llm.generateReviewed(topic, mode: DiscussionLengthMode.uzun),
            synthesize: (turn) async {
              synthesized.add(turn.text);
              return Uint8List.fromList(utf8.encode(turn.text));
            },
            play: (bytes) async => played.add(utf8.decode(bytes)),
          ).run('topic');

          expect(synthesized, [_tamA, _tamB]);
          expect(played, [_tamA, _tamB]);
        },
      );

      test(
        'finish_reason=stop -> no line is dropped (no over-trimming)',
        () async {
          final mock = MockClient((req) async {
            if (_isReviewer(req)) {
              return _resp(
                '{"ok": true, "corrections": []}',
                finishReason: 'stop',
              );
            }
            return _resp(_kesikScript, finishReason: 'stop');
          });

          final turns = await LlmDiscussion(
            apiKey: 'k',
            client: mock,
          ).generateReviewed('topic');

          expect(turns, hasLength(3));
          expect(turns.last.text, _yarimC);
        },
      );

      test(
        'reply cut in the first line (no complete line) -> LlmDiscussionException',
        () async {
          final mock = MockClient(
            (req) async => _resp('A: $_yarimC', finishReason: 'length'),
          );

          await expectLater(
            LlmDiscussion(apiKey: 'k', client: mock).generate('topic'),
            throwsA(isA<LlmDiscussionException>()),
          );
        },
      );

      test(
        'generateContinuation also drops the cut last line (shared chain)',
        () async {
          final mock = MockClient(
            (req) async => _resp(_kesikScript, finishReason: 'length'),
          );

          final turns = await LlmDiscussion(
            apiKey: 'k',
            client: mock,
          ).generateContinuation('topic', const []);

          expect(turns.map((t) => t.text), [_tamA, _tamB]);
        },
      );
    },
  );

  group(
    'mode cap meets the measured need (T3/W4: 2/2 Long runs hit the cap)',
    () {
      Future<int> maxTokensFor(DiscussionLengthMode mode) async {
        Map<String, dynamic>? body;
        final mock = MockClient((req) async {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return _resp('A: one\nB: two', finishReason: 'stop');
        });
        await LlmDiscussion(
          apiKey: 'k',
          client: mock,
        ).generate('topic', mode: mode);
        return body!['max_tokens'] as int;
      }

      // Measured worst values (internal measurement note §2): word overshoot
      // 2779/2150 = 1.29; tokens per word 1515/679 = 2.23.
      const worstOvershoot = 1.29;
      const worstTokensPerWord = 2.23;

      for (final mode in [
        DiscussionLengthMode.kisa,
        DiscussionLengthMode.orta,
        DiscussionLengthMode.uzun,
      ]) {
        test(
          '${mode.name}: cap >= target x $worstOvershoot x $worstTokensPerWord',
          () async {
            final need =
                (targetWordsFor(mode)! * worstOvershoot * worstTokensPerWord)
                    .ceil();
            expect(await maxTokensFor(mode), greaterThanOrEqualTo(need));
          },
        );
      }
    },
  );
}
