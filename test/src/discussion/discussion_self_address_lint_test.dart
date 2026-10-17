// Oracle RED test (2026-09-28 night, measurement report §3): the speaker
// addresses themselves by their own name ("Deniz olarak soyluyorum", "Kaya
// olarak altini cizerim") -- 2 times in 119 live turns; the reviewer caught
// 0/4. The only deterministic check (lintDiscussionNames kendiAdi) only
// caught a turn that STARTS with "Ad,".
//
// Pinned contract: kendiAdi catches all measured patterns -- "<Ad> olarak",
// "Ben <Ad>", third-person self-reference like "<Ad>'in/’in", and a leading
// "<Ad>," -- and does not catch the measured false positive (W4 #27 "Deniz
// aşırı" = overseas) or ANOTHER speaker's name. The reviewer prompt has the
// rule.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/discussion/discussion_name_lint.dart';
import 'package:sesli_kitap/src/discussion/discussion_review.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';

bool _kendiAdi(DiscussionSpeaker speaker, String text) => lintDiscussionNames([
  DiscussionTurn(speaker, text),
]).any((i) => i.category == DiscussionNameLintCategory.kendiAdi);

void main() {
  group('kendiAdi -- measured patterns are caught', () {
    test('T1_orta #16 (Deniz): "Deniz olarak söylüyorum ki"', () {
      expect(
        _kendiAdi(
          DiscussionSpeaker.c,
          'Bir kazayı tekrar yaşayan insan haz aramıyor, Deniz olarak '
          'söylüyorum ki o insan parçalanmış benliğini yeniden bir araya '
          'getirme savaşı veriyor.',
        ),
        isTrue,
      );
    });

    test('T2_sonsuz #4 (Kaya): "Burada Kaya olarak altını çizerim ki"', () {
      expect(
        _kendiAdi(
          DiscussionSpeaker.d,
          'Burada Kaya olarak altını çizerim ki Ahmet haklı; rüyanın her '
          'unsuru ayrı ayrı analiz edilmeli.',
        ),
        isTrue,
      );
    });

    test(
      'R7 injected (Deniz): at the start of a turn "Deniz olarak şunu söyleyeyim:"',
      () {
        expect(
          _kendiAdi(
            DiscussionSpeaker.c,
            'Deniz olarak şunu söyleyeyim: İkiniz de meselenin özünü kaçırıyorsunuz.',
          ),
          isTrue,
        );
      },
    );

    test('R7 injected (Kaya): "Ben Kaya olarak buna katılmıyorum."', () {
      expect(
        _kendiAdi(
          DiscussionSpeaker.d,
          'Ben Kaya olarak buna katılmıyorum. Emel haklı bir noktadan girdi.',
        ),
        isTrue,
      );
    });

    test(
      'T3 reviewer output (Emel): does not refer to itself as "Emel\'in eleştirisi"',
      () {
        expect(
          _kendiAdi(
            DiscussionSpeaker.b,
            "Emel'in yanlışlanabilirlik eleştirisi Ahmet'in katı arzu "
            'formülünü tam merkezinden vuruyor.',
          ),
          isTrue,
        );
      },
    );

    test(
      'typographic apostrophe is also caught ("Kaya’nın", present in T1 output)',
      () {
        expect(
          _kendiAdi(
            DiscussionSpeaker.d,
            'Kaya’nın verdiği örnek bunu kanıtlıyor.',
          ),
          isTrue,
        );
      },
    );
  });

  group('kendiAdi -- NO false alarm', () {
    test('W4_uzun #27 (Deniz): "Deniz aşırı bir seyahat" (overseas) '
        'is NOT a self-address', () {
      expect(
        _kendiAdi(
          DiscussionSpeaker.c,
          'Deniz aşırı bir seyahati arzulayan bir çocuğun rüyasını sadece '
          'cinsel bir tabuyla mı açıklayacaksınız?',
        ),
        isFalse,
      );
    });

    test(
      "ANOTHER's name: if Kaya says \"Deniz olarak sen\" and \"Emel'in\" -> none",
      () {
        expect(
          _kendiAdi(
            DiscussionSpeaker.d,
            "Deniz olarak sen hep ahlaka dönüyorsun; Emel'in itirazı daha güçlü.",
          ),
          isFalse,
        );
      },
    );

    test('lowercase common noun ("engin bir deniz olarak") -> none', () {
      expect(
        _kendiAdi(
          DiscussionSpeaker.c,
          'Bilinçdışı engin bir deniz olarak düşünülebilir.',
        ),
        isFalse,
      );
    });
  });

  // NOTE (honesty): this group pins two TEST-UNCOVERED branches caught by the
  // scope gate (2225/2227); it was written AFTER the implementation --
  // killability was shown with a temporary mutation (agent3 report,
  // kanit/mut_3_*.txt).
  group('removeSelfAddress -- "ben Ad" and leading "Ad," address', () {
    test(
      '"Ben Kaya, buna katılmıyorum." (Kaya) -> "Ben, buna katılmıyorum."',
      () {
        final out = removeSelfAddress(const [
          DiscussionTurn(DiscussionSpeaker.d, 'Ben Kaya, buna katılmıyorum.'),
        ]);
        expect(out.single.text, 'Ben, buna katılmıyorum.');
      },
    );

    test(
      'leading self-name address is removed, next letter is capitalized',
      () {
        final out = removeSelfAddress(const [
          DiscussionTurn(DiscussionSpeaker.c, 'Deniz, bence bu yanlış.'),
        ]);
        expect(out.single.text, 'Bence bu yanlış.');
      },
    );

    test('address to ANOTHER ("Kaya, ..." -- Deniz speaking) stays as is; '
        'speaker and count do not change', () {
      const turns = [
        DiscussionTurn(DiscussionSpeaker.c, 'Kaya, sen yanılıyorsun.'),
        DiscussionTurn(DiscussionSpeaker.d, 'Ben buna katılmıyorum.'),
      ];
      expect(removeSelfAddress(turns), orderedEquals(turns));
    });
  });

  group('reviewer prompt', () {
    test('SELF-ADDRESS check EXISTS and the label->name mapping is given', () {
      expect(reviewerPrompt, contains('SELF-ADDRESS'));
      expect(reviewerPrompt, contains('A=Ahmet, B=Emel, C=Deniz, D=Kaya'));
    });
  });
}
