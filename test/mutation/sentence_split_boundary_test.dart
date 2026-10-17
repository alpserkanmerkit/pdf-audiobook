// Mutation test (tool/mutation.dart) finding: sentence_split.dart boundary decisions. Spec (file header): a period is
// NOT a sentence end when (a) it continues with no space and the continuing letter is NOT uppercase, (b) it is
// followed by a space and a lowercase letter, (c) it is a single letter / known abbreviation. All others are sentence
// ends: no space followed by an UPPERCASE letter ("Bitti.Yeni"), followed by a digit ("bitti. 2 yil") and an
// abbreviation at the very start of the text ("Dr. Ahmet") included.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/sentence_split.dart';

void main() {
  test(
    'a digit after a period starts a new sentence (a digit is not lowercase)',
    () {
      expect(splitIntoSentences('Bölüm bitti. 2 yıl sonra döndü.'), [
        'Bölüm bitti.',
        '2 yıl sonra döndü.',
      ]);
    },
  );

  test(
    'a period with no space followed by an UPPERCASE letter is a sentence end',
    () {
      expect(splitIntoSentences('Bitti.Yeni başladı.'), [
        'Bitti.',
        'Yeni başladı.',
      ]);
    },
  );

  test(
    'an abbreviation at the very start of the text ("Dr.") does not split the sentence',
    () {
      expect(splitIntoSentences('Dr. Ahmet geldi.'), ['Dr. Ahmet geldi.']);
    },
  );
}
