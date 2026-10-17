// Oracle test (Slice-1): parsing an LLM "A:/B:" line-labelled dialogue into
// List<DiscussionTurn> + speaker->voice mapping (pure layer).
// Kickoff §4: "Dialogue parse ... empty/broken -> error; voice A->Ahmet, B->Emel".
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';
import 'package:sesli_kitap/src/voices.dart';

void main() {
  group('parseDiscussionScript', () {
    test('plain A/B/A dialogue -> 3 turns, correct order and text', () {
      final turns = parseDiscussionScript(
        'A: Yapay zeka her seyi cozer mi?\n'
        'B: Hayir, bunu farkli okuyorum.\n'
        'A: Neden boyle dusunuyorsun?',
      );
      expect(turns, hasLength(3));
      expect(turns[0].speaker, DiscussionSpeaker.a);
      expect(turns[0].text, 'Yapay zeka her seyi cozer mi?');
      expect(turns[1].speaker, DiscussionSpeaker.b);
      expect(turns[1].text, 'Hayir, bunu farkli okuyorum.');
      expect(turns[2].speaker, DiscussionSpeaker.a);
    });

    test('single turn (B: ...) is valid', () {
      final turns = parseDiscussionScript('B: Tek replik.');
      expect(turns, hasLength(1));
      expect(turns.single.speaker, DiscussionSpeaker.b);
      expect(turns.single.text, 'Tek replik.');
    });

    test('case-insensitive labels (a:/b:) are accepted', () {
      final turns = parseDiscussionScript('a: birinci\nB: ikinci');
      expect(turns, hasLength(2));
      expect(turns[0].speaker, DiscussionSpeaker.a);
      expect(turns[1].speaker, DiscussionSpeaker.b);
    });

    test('blank lines and leading/trailing whitespace are skipped', () {
      final turns = parseDiscussionScript('\n\n  A: ilk  \n\n   \nB: son\n\n');
      expect(turns, hasLength(2));
      expect(turns[0].text, 'ilk');
      expect(turns[1].text, 'son');
    });

    test('unlabeled continuation line is appended to the previous turn', () {
      final turns = parseDiscussionScript('A: bir\ndevam metni\nB: iki');
      expect(turns, hasLength(2));
      expect(turns[0].speaker, DiscussionSpeaker.a);
      expect(turns[0].text, contains('bir'));
      expect(turns[0].text, contains('devam metni'));
      expect(turns[1].text, 'iki');
    });

    test(
      'empty-text label (A:) is skipped, only the non-empty turn remains',
      () {
        final turns = parseDiscussionScript('A:\nB: dolu');
        expect(turns, hasLength(1));
        expect(turns.single.speaker, DiscussionSpeaker.b);
        expect(turns.single.text, 'dolu');
      },
    );

    test('empty input -> DiscussionParseException', () {
      expect(
        () => parseDiscussionScript(''),
        throwsA(isA<DiscussionParseException>()),
      );
    });

    test('whitespace only -> DiscussionParseException', () {
      expect(
        () => parseDiscussionScript('   \n\t\n  '),
        throwsA(isA<DiscussionParseException>()),
      );
    });

    test('no labels (plain text) -> DiscussionParseException', () {
      expect(
        () => parseDiscussionScript('merhaba dunya\nbaska bir satir'),
        throwsA(isA<DiscussionParseException>()),
      );
    });

    // Slice-1.1: resilience to common LLM format deviations (like sibling parsers,
    // strip line-start markdown/list/fence markers; a deviation must NOT cause a full failure).
    test('markdown-bold labels (**A:** / **B:**) are stripped', () {
      final turns = parseDiscussionScript('**A:** ilk\n**B:** ikinci');
      expect(turns, hasLength(2));
      expect(turns[0].speaker, DiscussionSpeaker.a);
      expect(turns[0].text, 'ilk');
      expect(turns[1].speaker, DiscussionSpeaker.b);
      expect(turns[1].text, 'ikinci');
    });

    test('numbered/list labels (1. A: / - B:) are stripped', () {
      final turns = parseDiscussionScript('1. A: ilk\n- B: ikinci');
      expect(turns, hasLength(2));
      expect(turns[0].speaker, DiscussionSpeaker.a);
      expect(turns[1].speaker, DiscussionSpeaker.b);
    });

    test('code-fence (```) lines do not pollute the text', () {
      final turns = parseDiscussionScript('```\nA: ilk\nB: ikinci\n```');
      expect(turns, hasLength(2));
      expect(turns[0].text, 'ilk');
      expect(
        turns[1].text,
        'ikinci',
      ); // closing fence does not stick to the last turn
    });

    test('colon with spaces (A : / B :) is recognized', () {
      final turns = parseDiscussionScript('A : ilk\nB : ikinci');
      expect(turns, hasLength(2));
      expect(turns[0].speaker, DiscussionSpeaker.a);
      expect(turns[1].speaker, DiscussionSpeaker.b);
    });

    // Slice-2: 4 speakers (A/B/C/D) + stripping of parenthesized stage directions.
    // De-risk lesson: TTS read round-bracket text aloud ("(turning to A)") -> stripped in parse.
    test('A/B/C/D four speakers are parsed correctly', () {
      final turns = parseDiscussionScript('A: bir\nB: iki\nC: uc\nD: dort');
      expect(turns, hasLength(4));
      expect(turns[0].speaker, DiscussionSpeaker.a);
      expect(turns[1].speaker, DiscussionSpeaker.b);
      expect(turns[2].speaker, DiscussionSpeaker.c);
      expect(turns[3].speaker, DiscussionSpeaker.d);
      expect(turns[3].text, 'dort');
    });

    test('case-insensitive c:/d: are accepted', () {
      final turns = parseDiscussionScript('c: ucuncu\nd: dorduncu');
      expect(turns, hasLength(2));
      expect(turns[0].speaker, DiscussionSpeaker.c);
      expect(turns[1].speaker, DiscussionSpeaker.d);
    });

    test('round-bracket stage direction is removed from the text', () {
      final turns = parseDiscussionScript('A: (gulerek) Merhaba dunya');
      expect(turns, hasLength(1));
      expect(turns.single.text, 'Merhaba dunya');
    });

    test('parentheses inside a line are removed, one space remains', () {
      final turns = parseDiscussionScript(
        'B: Dur bir saniye (keserek) devam ediyorum',
      );
      expect(turns.single.text, 'Dur bir saniye devam ediyorum');
    });

    test('square-bracket direction is also removed', () {
      final turns = parseDiscussionScript('C: [dusunur] Belki de haklisin');
      expect(turns.single.text, 'Belki de haklisin');
    });

    test('a line made up entirely of a direction is skipped', () {
      final turns = parseDiscussionScript(
        'A: (sadece yonerge)\nB: gercek replik',
      );
      expect(turns, hasLength(1));
      expect(turns.single.speaker, DiscussionSpeaker.b);
      expect(turns.single.text, 'gercek replik');
    });
  });

  group('voiceForSpeaker (Slice-2: 4-voice Google)', () {
    test('A -> Wavenet-B (male)', () {
      expect(voiceForSpeaker(DiscussionSpeaker.a), SesliVoice.wavenetB);
    });
    test('B -> Aoede (female)', () {
      expect(voiceForSpeaker(DiscussionSpeaker.b), SesliVoice.aoede);
    });
    test('C -> Wavenet-E (male)', () {
      expect(voiceForSpeaker(DiscussionSpeaker.c), SesliVoice.wavenetE);
    });
    test('D -> Wavenet-C (female)', () {
      expect(voiceForSpeaker(DiscussionSpeaker.d), SesliVoice.wavenetC);
    });
    test('four speakers get FOUR DISTINCT voices', () {
      final voices = {
        DiscussionSpeaker.a,
        DiscussionSpeaker.b,
        DiscussionSpeaker.c,
        DiscussionSpeaker.d,
      }.map(voiceForSpeaker).toSet();
      expect(voices, hasLength(4));
    });
  });

  group('DiscussionTurn value equality', () {
    test('same speaker+text are equal; different text is not equal', () {
      expect(
        const DiscussionTurn(DiscussionSpeaker.a, 'x'),
        const DiscussionTurn(DiscussionSpeaker.a, 'x'),
      );
      expect(
        const DiscussionTurn(DiscussionSpeaker.a, 'x'),
        isNot(const DiscussionTurn(DiscussionSpeaker.a, 'y')),
      );
      expect(
        const DiscussionTurn(DiscussionSpeaker.a, 'x'),
        isNot(const DiscussionTurn(DiscussionSpeaker.b, 'x')),
      );
    });

    test(
      'value-equal turns have the same hashCode (Set/Map contract: == implies equal hash)',
      () {
        const t1 = DiscussionTurn(DiscussionSpeaker.a, 'x');
        const t2 = DiscussionTurn(DiscussionSpeaker.a, 'x');
        expect(t1.hashCode, t2.hashCode);
      },
    );
  });

  group('DiscussionParseException', () {
    test('toString contains the reason text (error is diagnosable)', () {
      expect(
        DiscussionParseException('empty input').toString(),
        contains('empty input'),
      );
    });
  });
}
