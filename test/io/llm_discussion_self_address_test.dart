// Oracle RED test (2026-09-28 night, measurement report §3): NO mechanism that
// corrects self-address (a speaker naming themselves) was working in the app.
// The reviewer prompt had no rule (R7: "Ben Kaya olarak" stayed 3/3 times), and
// the lint was not wired into the app (only the unconnected shouldSkipReview was
// called).
//
// Pinned contract (app path, LlmDiscussion):
//  1) Deterministic fix: "<own name> olarak " and "ben <own name>" are removed
//     from the line (if at the start of a sentence, the next letter is
//     capitalized). Even if the reviewer returns ok:true (or misses it), it does
//     not remain in the text that will be played.
//  2) If the reviewer ITSELF produces it (measurement T3), it is cleaned in a
//     final pass.
//  3) A form that cannot be fixed deterministically ("Emel'in elestirisi" --
//     Emel speaking) is AUTOMATICALLY flagged to the reviewer with its number.
//  4) The continuation batch (endless mode, no reviewer) goes through the same
//     fix.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sesli_kitap/io/llm_discussion.dart';

http.Response _ok(String content) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': content},
        'finish_reason': 'stop',
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

String _userOf(http.Request req) {
  final body = jsonDecode(req.body) as Map<String, dynamic>;
  return ((body['messages'] as List)[1] as Map)['content'] as String;
}

// Self-address lines copied verbatim from live outputs (olcum_out).
const String _t1Deniz =
    'Bir kazayı tekrar yaşayan insan haz aramıyor, Deniz olarak söylüyorum '
    'ki o insan parçalanmış benliğini yeniden bir araya getirme savaşı veriyor.';
const String _t2Kaya =
    'Burada Kaya olarak altını çizerim ki Ahmet haklı; rüyanın her unsuru '
    'ayrı ayrı analiz edildiğinde hekimin dileği açığa çıkıyor.';
const String _r7Deniz =
    'Deniz olarak şunu söyleyeyim: İkiniz de meselenin özünü kaçırıyorsunuz.';

void main() {
  test(
    'even if the reviewer returns ok:true, self-address is removed from the text to be played',
    () async {
      final mock = MockClient((req) async {
        if (_isReviewer(req)) return _ok('{"ok": true, "corrections": []}');
        return _ok(
          'A: Bence mesele açık.\nC: $_t1Deniz\nD: $_t2Kaya\nC: $_r7Deniz',
        );
      });

      final turns = await LlmDiscussion(
        apiKey: 'k',
        client: mock,
      ).generateReviewed('topic');

      expect(
        turns[1].text,
        'Bir kazayı tekrar yaşayan insan haz aramıyor, söylüyorum ki o insan '
        'parçalanmış benliğini yeniden bir araya getirme savaşı veriyor.',
      );
      expect(
        turns[2].text,
        'Burada altını çizerim ki Ahmet haklı; rüyanın her unsuru ayrı ayrı '
        'analiz edildiğinde hekimin dileği açığa çıkıyor.',
      );
      expect(
        turns[3].text,
        'Şunu söyleyeyim: İkiniz de meselenin özünü kaçırıyorsunuz.',
      );
    },
  );

  test(
    'if the reviewer correction INTRODUCES self-address, it is cleaned in the '
    'final pass (R7: "Ben Kaya olarak" survived the reviewer rewrite)',
    () async {
      const orijinal =
          'Buna katılmıyorum. Emel haklı bir noktadan girdi ama eksik bıraktı; '
          'bedensel uyaranlar bile psişik sansürün süzgecinden geçer.';
      const reviewerMetni =
          'Ben Kaya olarak buna katılmıyorum. Emel haklı bir noktadan girdi ama '
          'eksik bıraktı; bedensel uyaranlar bile psişik sansürün süzgecinden '
          'geçer. Irma rüyasındaki lekeler bunu gösteriyor.';
      final mock = MockClient((req) async {
        if (_isReviewer(req)) {
          return _ok(
            jsonEncode({
              'ok': false,
              'corrections': [
                {'index': 1, 'text': reviewerMetni},
              ],
            }),
          );
        }
        return _ok('A: Bence mesele açık.\nD: $orijinal');
      });

      final turns = await LlmDiscussion(
        apiKey: 'k',
        client: mock,
      ).generateReviewed('topic');

      expect(
        turns[1].text,
        'Ben buna katılmıyorum. Emel haklı bir noktadan girdi ama eksik bıraktı; '
        'bedensel uyaranlar bile psişik sansürün süzgecinden geçer. Irma '
        'rüyasındaki lekeler bunu gösteriyor.',
      );
    },
  );

  test(
    'self-address that cannot be fixed deterministically is sent to the reviewer '
    'with its number as an AUTOMATIC FLAG',
    () async {
      String? reviewerUser;
      final mock = MockClient((req) async {
        if (_isReviewer(req)) {
          reviewerUser = _userOf(req);
          return _ok('{"ok": true, "corrections": []}');
        }
        return _ok(
          "A: Bence mesele açık.\nB: Emel'in yanlışlanabilirlik eleştirisi "
          'yöntemi tam merkezinden vuruyor.',
        );
      });

      await LlmDiscussion(apiKey: 'k', client: mock).generateReviewed('topic');

      expect(reviewerUser, contains('AUTOMATIC FLAGS'));
      expect(reviewerUser, contains('#1 kendiAdi'));
    },
  );

  test('a clean batch does NOT send the AUTOMATIC FLAG block', () async {
    String? reviewerUser;
    final mock = MockClient((req) async {
      if (_isReviewer(req)) {
        reviewerUser = _userOf(req);
        return _ok('{"ok": true, "corrections": []}');
      }
      return _ok('A: Bence mesele açık.\nB: Ahmet, buna katılmıyorum.');
    });

    await LlmDiscussion(apiKey: 'k', client: mock).generateReviewed('topic');

    expect(reviewerUser, isNot(contains('AUTOMATIC FLAGS')));
  });

  test('the continuation batch (endless, no reviewer) is also fixed', () async {
    final mock = MockClient((req) async => _ok('C: $_r7Deniz\nD: $_t2Kaya'));

    final turns = await LlmDiscussion(
      apiKey: 'k',
      client: mock,
    ).generateContinuation('topic', const []);

    expect(turns[0].text, startsWith('Şunu söyleyeyim:'));
    expect(turns[1].text, startsWith('Burada altını çizerim ki'));
  });
}
