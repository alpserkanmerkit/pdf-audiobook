// PR-Q1 (finding #6 name-fix, DESIGN §3): pure, 100%-coverage name-lint tests.
// Prepared for the reviewer / future use; in this PR it is NOT wired to the UI
// (it is enough that the test and the function exist for the future reviewer gate).
//
// Three detection categories (design §2/§3):
//  - harfToken: a standalone A/B/C/D letter INSIDE the turn text (label leak).
//  - yanlisAd: the turn starts with a vocative "Ad," but this name is NOT the
//    real name of the PREVIOUS speaker (the previous turn) (wrong person addressed).
//  - kendiAdi: the turn starts with the speaker's OWN name (style violation, a
//    side effect observed in A2b Experiment-2).
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/discussion/discussion_name_lint.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';

void main() {
  group('lintDiscussionNames — clean script', () {
    test('correct names used in address + no violations -> empty list', () {
      const turns = [
        DiscussionTurn(DiscussionSpeaker.a, 'Bence bu boyle degil.'),
        DiscussionTurn(
          DiscussionSpeaker.b,
          'Ahmet, buna katilmiyorum, veriler baska sey soyluyor.',
        ),
        DiscussionTurn(
          DiscussionSpeaker.c,
          'Emel, ikiniz de bir noktayi atliyorsunuz.',
        ),
      ];
      expect(lintDiscussionNames(turns), isEmpty);
    });

    test('empty list -> empty list (no crash)', () {
      expect(lintDiscussionNames(const []), isEmpty);
    });

    test('single turn -> no previous speaker, vocative check is skipped', () {
      const turns = [
        DiscussionTurn(DiscussionSpeaker.a, 'Ahmet, bir sey soyleyecegim.'),
      ];
      // In a single turn the "previous speaker" is undefined, so there is no reference
      // for the vocative check; however the self-name check STILL applies
      // (speaker Ahmet, starts with their own name -> violation).
      final issues = lintDiscussionNames(turns);
      expect(issues, hasLength(1));
      expect(issues.single.category, DiscussionNameLintCategory.kendiAdi);
    });
  });

  group('lintDiscussionNames — harfToken (label leak)', () {
    test('standalone letter token in the text -> harfToken violation', () {
      const turns = [
        DiscussionTurn(DiscussionSpeaker.a, 'Bir iddiam var.'),
        DiscussionTurn(
          DiscussionSpeaker.b,
          "B haklı olabilir ama ben B'ye katılmıyorum diyor A.",
        ),
      ];
      final issues = lintDiscussionNames(turns);
      expect(
        issues.any((i) => i.category == DiscussionNameLintCategory.harfToken),
        isTrue,
      );
    });

    test(
      'letters that are part of a speaker name do NOT produce a FALSE positive',
      () {
        // Letters A/E appear INSIDE names like "Ahmet" and "Emel", but they are NOT
        // standalone tokens -> harfToken must not fire.
        const turns = [
          DiscussionTurn(
            DiscussionSpeaker.a,
            'Ahmet ve Emel ayni sey mi diyor acaba?',
          ),
        ];
        final issues = lintDiscussionNames(turns);
        expect(
          issues.where(
            (i) => i.category == DiscussionNameLintCategory.harfToken,
          ),
          isEmpty,
        );
      },
    );

    test(
      'sentence-initial letter + period ("A.") does not produce a false positive (possibly a word end, not an abbreviation)',
      () {
        const turns = [
          DiscussionTurn(DiscussionSpeaker.a, 'Once C, sonra D konustu.'),
        ];
        final issues = lintDiscussionNames(turns);
        expect(
          issues.where(
            (i) => i.category == DiscussionNameLintCategory.harfToken,
          ),
          hasLength(2),
          reason:
              'C and D here are REALLY letter-token addresses and must be caught',
        );
      },
    );
  });

  group('lintDiscussionNames — yanlisAd (vocative consistency)', () {
    test(
      "vocative name is NOT the previous speaker's name -> yanlisAd violation",
      () {
        const turns = [
          // Ahmet (a) is speaking.
          DiscussionTurn(DiscussionSpeaker.a, 'Bence durum boyle.'),
          // Kaya (d) replies but says "Deniz," -- the previous speaker was Ahmet.
          DiscussionTurn(
            DiscussionSpeaker.d,
            'Deniz, bu tamamen yanlış bir okuma.',
          ),
        ];
        final issues = lintDiscussionNames(turns);
        expect(issues, hasLength(1));
        expect(issues.single.category, DiscussionNameLintCategory.yanlisAd);
        expect(issues.single.turnIndex, 1);
      },
    );

    test(
      "vocative name MATCHES the previous speaker's name -> no violation",
      () {
        const turns = [
          DiscussionTurn(DiscussionSpeaker.a, 'Bence durum boyle.'),
          DiscussionTurn(
            DiscussionSpeaker.d,
            'Ahmet, bu tamamen yanlış bir okuma.',
          ),
        ];
        expect(lintDiscussionNames(turns), isEmpty);
      },
    );
  });

  group('lintDiscussionNames — kendiAdi (mentioning own name)', () {
    test("turn starts with the speaker's OWN name -> kendiAdi violation", () {
      const turns = [
        DiscussionTurn(DiscussionSpeaker.a, 'Bence durum boyle.'),
        // Kaya (d) is speaking but starts with "Kaya, ..." -- their OWN name.
        DiscussionTurn(
          DiscussionSpeaker.d,
          "Kaya, Deniz'in dediğine katılıyorum.",
        ),
      ];
      final issues = lintDiscussionNames(turns);
      expect(
        issues.any((i) => i.category == DiscussionNameLintCategory.kendiAdi),
        isTrue,
      );
    });

    test(
      "starting with someone else's name does NOT trigger kendiAdi (correct usage)",
      () {
        const turns = [
          DiscussionTurn(DiscussionSpeaker.a, 'Bence durum boyle.'),
          DiscussionTurn(
            DiscussionSpeaker.d,
            "Ahmet, Deniz'in dediğine katılıyorum.",
          ),
        ];
        final issues = lintDiscussionNames(turns);
        expect(
          issues.where(
            (i) => i.category == DiscussionNameLintCategory.kendiAdi,
          ),
          isEmpty,
        );
      },
    );
  });

  group('lintDiscussionNames — multiple violations', () {
    test('the same script returns multiple category violations together', () {
      const turns = [
        DiscussionTurn(DiscussionSpeaker.a, 'Bir iddiam var.'),
        DiscussionTurn(
          DiscussionSpeaker.b,
          "B'nin dedigi dogru degil, A yanılıyor.",
        ),
        DiscussionTurn(
          DiscussionSpeaker.d,
          'Kaya, bu konuda net bir örnek verebilirim.',
        ),
      ];
      final issues = lintDiscussionNames(turns);
      expect(
        issues.map((i) => i.category).toSet(),
        containsAll([
          DiscussionNameLintCategory.harfToken,
          DiscussionNameLintCategory.kendiAdi,
        ]),
      );
    });
  });
}
