// Oracle pinning test (2026-09-28, field report: a user saw the text break into
// fragments like "bolük porcuk" in the reader). Desktop reproduction using the app's
// own chain (extractPageText -> stripPageArtifacts -> splitIntoSentences) on page 649
// of the Freud "Rüyaların Yorumu" PDF (LLM-free path): of 12951 screen blocks, 893
// start with a lowercase letter inside a sentence (split mid-sentence), 1109 are
// <= 6 characters, and 336 start with a closing quote. Examples (real output):
// "(s." | "553): ..." ; "vb." | "'nin ruyayi..." ; "52." | "sayfa ve..." ; "F." |
// "RÜYADA AHLAK..." ; "www." | "sayyayincilik." The reader draws each block as a
// separate box, so the text looks disconnected. The splitter also runs after LLM
// cleanup in the same way (reader_screen: splitIntoSentences(cleanText)).
// Inputs are real sentences from the PDF (shortened).
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/sentence_split.dart';

void main() {
  test(
    'page reference "(s. 553)" and closing quote do not split the sentence',
    () {
      final s = splitIntoSentences(
        'Jessen şöyle diyor (s. 553): "Rüyada daha iyi ya da daha erdemli '
        'olmayız. Başkalarına acımak nedir bilmeyen vicdanımız adeta bir '
        'suskunluğa bürünüyor." Radestock (s. 146): "Dikkate alınması '
        'gereken bir nokta."',
      );
      expect(s, [
        'Jessen şöyle diyor (s. 553): "Rüyada daha iyi ya da daha erdemli '
            'olmayız.',
        'Başkalarına acımak nedir bilmeyen vicdanımız adeta bir suskunluğa '
            'bürünüyor."',
        'Radestock (s. 146): "Dikkate alınması gereken bir nokta."',
      ]);
    },
  );

  test('ordinal number "52." (followed by lowercase) does not split', () {
    final s = splitIntoSentences(
      'İdam edildiğini gördüğü 52. sayfa ve devamında ele aldığımız rüya, '
      'bunu gösteriyor. Ama bu çıkarsamaya karşı çıkıldı.',
    );
    expect(s, [
      'İdam edildiğini gördüğü 52. sayfa ve devamında ele aldığımız rüya, '
          'bunu gösteriyor.',
      'Ama bu çıkarsamaya karşı çıkıldı.',
    ]);
  });

  test(
    '"vb." abbreviation and a suffix with no space ("vb.\'nin") do not split',
    () {
      final s = splitIntoSentences(
        "Genç Fichte vb.'nin rüyayı üst bir basamağa taşıdığına dair "
        'ifadelerini anlamakta zorlanıyoruz. Bu tür sözler bugün tekrarlanıyor.',
      );
      expect(s, [
        "Genç Fichte vb.'nin rüyayı üst bir basamağa taşıdığına dair "
            'ifadelerini anlamakta zorlanıyoruz.',
        'Bu tür sözler bugün tekrarlanıyor.',
      ]);
    },
  );

  test(
    'single letter + period (section letter "F.", initial "K.") does not split',
    () {
      final s = splitIntoSentences(
        'Ufukta belirmiş durumda. F. RÜYADA AHLAK DUYGUSU Benim '
        'araştırmalarımı bilenler anlar. K. Fischer bunu iddia eder.',
      );
      expect(s, [
        'Ufukta belirmiş durumda.',
        'F. RÜYADA AHLAK DUYGUSU Benim araştırmalarımı bilenler anlar.',
        'K. Fischer bunu iddia eder.',
      ]);
    },
  );

  test('address parts ("www. saykitap. com") stay as one block', () {
    expect(splitIntoSentences('İnternet satış: www. saykitap. com adresi.'), [
      'İnternet satış: www. saykitap. com adresi.',
    ]);
  });

  test(
    'decimal number is not split; a capital letter after ?! and ... starts a new sentence',
    () {
      expect(
        splitIntoSentences(
          'Tam 3.5 kilo aldı. Gerçekten mi?! Evet... Sonra '
          'durdu.',
        ),
        ['Tam 3.5 kilo aldı.', 'Gerçekten mi?!', 'Evet...', 'Sonra durdu.'],
      );
    },
  );

  // The old splitter returned [] for '...' but ['?!'] for ' ?! ' (an empty box
  // with nothing to read); a punctuation-only fragment is not a block.
  test('punctuation only -> empty list', () {
    expect(splitIntoSentences('...'), isEmpty);
    expect(splitIntoSentences(' ?! '), isEmpty);
  });
}
