// Oracle test (Gemini TTS slice, 2026-09-28): pure WAV helper.
// FIELD LESSON: Gemini TTS returns the audio as a headered WAV (RIFF). The first
// measurement script wrote that header out as raw audio -> a "crackle" at every line
// change (the user caught it by ear). ensureWav passes RIFF input through AS IS (no
// double header); raw PCM is wrapped with a correct 44-byte header.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/wav.dart';

int _u32(Uint8List b, int o) =>
    ByteData.sublistView(b).getUint32(o, Endian.little);
int _u16(Uint8List b, int o) =>
    ByteData.sublistView(b).getUint16(o, Endian.little);
String _ascii(Uint8List b, int o) => String.fromCharCodes(b.sublist(o, o + 4));

void main() {
  group('ensureWav', () {
    test(
      'byte array starting with RIFF is returned UNCHANGED (no double header)',
      () {
        final pcm = Uint8List.fromList(List<int>.generate(10, (i) => i));
        final wav = pcmToWav(pcm, sampleRate: 24000);
        final out = ensureWav(wav, sampleRate: 16000);
        expect(out, wav);
        expect(String.fromCharCodes(out).split('RIFF').length - 1, 1);
      },
    );

    test('raw PCM is wrapped with a 44-byte mono 16-bit header', () {
      final pcm = Uint8List.fromList([1, 0, 2, 0, 3, 0, 4, 0]);
      final out = ensureWav(pcm, sampleRate: 24000);
      expect(out.length, 44 + pcm.length);
      expect(_ascii(out, 0), 'RIFF');
      expect(_u32(out, 4), 36 + pcm.length);
      expect(_ascii(out, 8), 'WAVE');
      expect(_ascii(out, 12), 'fmt ');
      expect(_u32(out, 16), 16);
      expect(_u16(out, 20), 1); // PCM
      expect(_u16(out, 22), 1); // mono
      expect(_u32(out, 24), 24000);
      expect(_u32(out, 28), 48000); // byteRate = rate * 2
      expect(_u16(out, 32), 2); // blockAlign
      expect(_u16(out, 34), 16); // bit
      expect(_ascii(out, 36), 'data');
      expect(_u32(out, 40), pcm.length);
      expect(out.sublist(44), pcm);
    });

    test('empty input -> header only (0 data bytes)', () {
      final out = ensureWav(Uint8List(0), sampleRate: 24000);
      expect(out.length, 44);
      expect(_u32(out, 40), 0);
    });

    test('input shorter than 4 bytes and not RIFF is treated as PCM', () {
      final out = ensureWav(Uint8List.fromList([82, 73]), sampleRate: 8000);
      expect(out.length, 46);
      expect(_u32(out, 24), 8000);
    });
  });

  group('sampleRateFromMime', () {
    test('rate parameter is read', () {
      expect(sampleRateFromMime('audio/L16;codec=pcm;rate=24000'), 24000);
      expect(sampleRateFromMime('audio/L16; rate=16000'), 16000);
    });
    test('when rate is missing or mime is null, the default is 24000', () {
      expect(sampleRateFromMime('audio/wav'), 24000);
      expect(sampleRateFromMime(null), 24000);
    });
  });
}
