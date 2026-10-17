// Mutation test (tool/mutation.dart) finding: page_preprocess.dart last-line page number. Spec: decorated variants
// ("— 47 —") are stripped like a bare number and pageNumber is returned as a NUMBER; this path also applies to the
// LAST line only. Earlier tests used a bare digit on the last line -> the mutant that parses the whole match instead
// of the captured group survived.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/page_preprocess.dart';

void main() {
  test(
    'only the decorated page number on the last line ("— 47 —") is stripped',
    () {
      final r = stripPageArtifacts('The text ends here.\n— 47 —');
      expect(r.pageNumber, 47);
      expect(r.text, 'The text ends here.');
    },
  );
}
