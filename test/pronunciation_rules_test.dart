// Oracle test (feature: pronunciation dictionary): pre-TTS rule engine — PURE.
// Precedent: Voice Dream pronunciation dictionary + skip rule. A user rule
// corrects a word TTS reads wrongly ("İbn-i Sina=İbni Sina") or drops it
// entirely (empty to = skip). The audio cache must be SENSITIVE to the rules:
// when a rule changes, the old mp3 goes stale (pronTag, added backward-
// compatibly to cache_keys).
//
// Contract decisions (oracle, 2026-06-12):
// - PronRule{from,to}; to == '' → SKIP rule. parsePronRules line format is
//   "from=to"; '#' is a comment, empty lines are skipped; a line without '='
//   or with an empty from → PronRuleParseException (the message carries the
//   line number; silent swallowing is forbidden).
// - applyPronRules: word-character set [A-Za-z0-9çğıöşüÇĞİÖŞÜ]; matching is
//   CASE-SENSITIVE exact; if the start/end of from is a word character, a
//   word boundary is required at that edge (no substring leakage). SINGLE
//   PASS left to right: at each position the rules are tried in the given
//   order, the FIRST match is applied, and the cursor jumps to AFTER the
//   replacement (the output is not rescanned -- no chaining). Double spaces
//   created by a skip collapse to one.
// - cache_keys: CacheStamp gets pronTag (default ''); when pronTag is EMPTY,
//   audioCacheKey is BYTE-FOR-BYTE the OLD format (backward compatibility --
//   the existing cache is not invalidated); when it is filled, the key
//   changes. isAudioStale treats a pronTag difference as stale.
//   pronRulesTag(rules): deterministic, filename-safe; empty list → ''.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/cache_keys.dart';
import 'package:sesli_kitap/src/pronunciation_rules.dart';

void main() {
  group('parsePronRules', () {
    test(
      'multiple lines + comment + empty line: rules are returned in order',
      () {
        final rules = parsePronRules(
          '# telaffuz kuralları\nHû=Hu\n\nİbn-i Sina=İbni Sina\nfalan=\n',
        );
        expect(rules, hasLength(3));
        expect(rules[0].from, 'Hû');
        expect(rules[0].to, 'Hu');
        expect(rules[1].from, 'İbn-i Sina');
        expect(rules[2].from, 'falan');
        expect(rules[2].to, ''); // skip rule
      },
    );

    test("a line without '=' → exception, message carries the line number", () {
      expect(
        () => parsePronRules('Hû=Hu\nmalformed line\n'),
        throwsA(
          isA<PronRuleParseException>().having(
            (e) => e.toString(),
            'message',
            contains('2'),
          ),
        ),
      );
    });

    test('empty from → exception', () {
      expect(
        () => parsePronRules('=Hu'),
        throwsA(isA<PronRuleParseException>()),
      );
    });

    test('empty input → empty list', () {
      expect(parsePronRules(''), isEmpty);
      expect(parsePronRules('# only a comment\n'), isEmpty);
    });
  });

  group('applyPronRules — matching', () {
    test('simple replacement, also when attached to punctuation', () {
      const rules = [PronRule(from: 'Hû', to: 'Hu')];
      expect(applyPronRules('Hû, dedi.', rules), 'Hu, dedi.');
    });

    test('word boundary: substring leakage forbidden', () {
      const rules = [PronRule(from: 'kar', to: 'kış')];
      expect(
        applyPronRules('kar yağdı, karga uçtu', rules),
        'kış yağdı, karga uçtu',
      );
    });

    test('Turkish letters are word characters (inner matches do not leak)', () {
      const rules = [PronRule(from: 'aş', to: 'as')];
      expect(applyPronRules('aşı oldu, aş pişti', rules), 'aşı oldu, as pişti');
    });

    test(
      'circumflexed letters are word characters too (Hûr is preserved; probe FAIL-2)',
      () {
        const rules = [PronRule(from: 'Hû', to: 'Huu')];
        expect(
          applyPronRules('Hû dedi; Hûr ve kâr kaldı', rules),
          'Huu dedi; Hûr ve kâr kaldı',
        );
        const rules2 = [PronRule(from: 'kâr', to: 'kaar')];
        expect(
          applyPronRules('kâr etti, kârlı çıktı', rules2),
          'kaar etti, kârlı çıktı',
        );
      },
    );

    test('multi-word and hyphenated from matches exactly', () {
      const rules = [PronRule(from: 'İbn-i Sina', to: 'İbni Sina')];
      expect(
        applyPronRules('Filozof İbn-i Sina yazdı.', rules),
        'Filozof İbni Sina yazdı.',
      );
    });

    test(
      'case-sensitive: a lowercase rule does not change the uppercase form',
      () {
        const rules = [PronRule(from: 'hû', to: 'hu')];
        expect(applyPronRules('Hû dedi', rules), 'Hû dedi');
      },
    );

    test('rule order: the first match wins', () {
      const rules = [
        PronRule(from: 'aşk', to: 'ask'),
        PronRule(from: 'aşk', to: 'IKINCI'),
      ];
      expect(applyPronRules('aşk', rules), 'ask');
    });

    test("no chaining: a rule's output is not rescanned", () {
      const rules = [
        PronRule(from: 'a', to: 'b'),
        PronRule(from: 'b', to: 'c'),
      ];
      expect(applyPronRules('a b', rules), 'b c');
    });

    test('skip rule: the word is dropped, double space collapses to one', () {
      const rules = [PronRule(from: 'falan', to: '')];
      expect(applyPronRules('bu falan kitap', rules), 'bu kitap');
    });

    test('empty rule list: text unchanged', () {
      expect(applyPronRules('değişmez metin', const []), 'değişmez metin');
    });
  });

  group('cache_keys pronTag integration (backward compatible)', () {
    const eski = CacheStamp(
      cleanPromptVersion: 'v1',
      ttsVoice: 'tr-TR-AhmetNeural',
      ttsRate: '+0%',
    );

    test('empty pronTag: audioCacheKey is IDENTICAL to the old format', () {
      final key = audioCacheKey(bookHash: 'abc', pageNo: 5, stamp: eski);
      expect(
        key,
        'a_abc_p5_v1_tr-TR-AhmetNeural_x2b0x25', // gitleaks:allow (cache key)
      );
    });

    test('filled pronTag changes the key and it stays filename-safe', () {
      const tagli = CacheStamp(
        cleanPromptVersion: 'v1',
        ttsVoice: 'tr-TR-AhmetNeural',
        ttsRate: '+0%',
        pronTag: 'pr1a2b',
      );
      final k1 = audioCacheKey(bookHash: 'abc', pageNo: 5, stamp: eski);
      final k2 = audioCacheKey(bookHash: 'abc', pageNo: 5, stamp: tagli);
      expect(k1, isNot(k2));
      expect(RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(k2), isTrue);
    });

    test(
      'isAudioStale: a pronTag difference makes it stale; equality is fresh',
      () {
        const t1 = CacheStamp(
          cleanPromptVersion: 'v1',
          ttsVoice: 'v',
          ttsRate: 'r',
          pronTag: 'a',
        );
        const t2 = CacheStamp(
          cleanPromptVersion: 'v1',
          ttsVoice: 'v',
          ttsRate: 'r',
          pronTag: 'b',
        );
        const t3 = CacheStamp(
          cleanPromptVersion: 'v1',
          ttsVoice: 'v',
          ttsRate: 'r',
          pronTag: 'a',
        );
        expect(isAudioStale(stored: t1, current: t2), isTrue);
        expect(isAudioStale(stored: t1, current: t3), isFalse);
      },
    );

    test(
      'pronRulesTag: deterministic; empty list → empty tag; different rules → different tag',
      () {
        const r1 = [PronRule(from: 'Hû', to: 'Hu')];
        const r2 = [PronRule(from: 'Hû', to: 'Huu')];
        expect(pronRulesTag(const []), '');
        expect(pronRulesTag(r1), pronRulesTag(r1));
        expect(pronRulesTag(r1), isNot(pronRulesTag(r2)));
        expect(RegExp(r'^[a-zA-Z0-9._-]*$').hasMatch(pronRulesTag(r1)), isTrue);
      },
    );
  });
}
