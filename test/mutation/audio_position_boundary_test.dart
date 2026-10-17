// Mutation test (tool/mutation.dart) finding: audio_position.dart page lower bound. Spec (audio_position.dart header):
// page numbers start at 1; "page < 1" is invalid, page 1 (the book's first page) is VALID. Earlier tests only tried
// 0 and -1 -> the `page <= 1` / `page < 2` mutants survived.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/audio_position.dart';

void main() {
  test("page 1 (the book's first page) is a valid position", () {
    expect(parseAudioPos('1:5000'), (
      page: 1,
      pos: const Duration(milliseconds: 5000),
    ));
  });

  test('save/load round-trip for page 1 stays intact', () {
    final raw = formatAudioPos(page: 1, pos: const Duration(seconds: 42));
    expect(raw, '1:42000');
    expect(parseAudioPos(raw), (page: 1, pos: const Duration(seconds: 42)));
  });
}
