// Slice-5a RED test (oracle). Pure reader units (reader analysis). 100% branch target.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/reader_highlight_view.dart';
import 'package:sesli_kitap/src/sentence_split.dart';

void main() {
  group('splitIntoSentences', () {
    test('splits on sentence-ending punctuation, trims', () {
      final s = splitIntoSentences('Bir cümle. İkinci cümle! Üçüncü?');
      expect(s, hasLength(3));
      expect(s[0], 'Bir cümle.');
      expect(s[1], 'İkinci cümle!');
      expect(s[2], 'Üçüncü?');
    });
    test('empty/whitespace input -> empty list', () {
      expect(splitIntoSentences(''), isEmpty);
      expect(splitIntoSentences('   '), isEmpty);
    });
    test('no punctuation single piece -> single sentence', () {
      expect(splitIntoSentences('noktalama yok'), hasLength(1));
    });
  });

  group('visualStateFor', () {
    test('highlighted has priority', () {
      expect(
        visualStateFor(index: 1, narratingIndex: 0, highlightedIndexes: {1}),
        SentenceVisualState.highlighted,
      );
    });
    test('the sentence being read is narrating', () {
      expect(
        visualStateFor(index: 2, narratingIndex: 2, highlightedIndexes: {}),
        SentenceVisualState.narrating,
      );
    });
    test('others are plain', () {
      expect(
        visualStateFor(index: 3, narratingIndex: 0, highlightedIndexes: {1}),
        SentenceVisualState.plain,
      );
    });
  });
}
