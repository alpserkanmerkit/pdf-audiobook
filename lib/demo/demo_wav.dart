// DEMO mode: fake TTS audio. There is NO real speech; a silent but REAL-DURATION
// WAV is produced so that the player (DemoAudioOps) and the reader's karaoke
// highlight progress in real time.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sesli_kitap/src/wav.dart';

/// Demo speech rate: characters per second (about 3x faster than real speech;
/// a 1500-character page takes ~33 s).
const double kDemoCharsPerSecond = 45;

/// Minimum duration of the silent fake speech.
const Duration kDemoMinSpeech = Duration(milliseconds: 1500);

/// Low sample rate: keeps the file small (4000 Hz x 16 bit = 8 KB/s).
const int kDemoSampleRate = 4000;

/// Silent mono 16-bit WAV lasting [duration].
Uint8List silentWav({
  required Duration duration,
  int sampleRate = kDemoSampleRate,
}) {
  final samples = (duration.inMicroseconds * sampleRate / 1000000).round();
  return pcmToWav(Uint8List(samples * 2), sampleRate: sampleRate);
}

/// Fake speech duration for [text]: character count / [charsPerSecond]
/// (at least [kDemoMinSpeech]).
Duration demoSpeechDuration(
  String text, {
  double charsPerSecond = kDemoCharsPerSecond,
}) {
  final micros = (text.length / charsPerSecond * 1000000).round();
  return Duration(
    microseconds: math.max(micros, kDemoMinSpeech.inMicroseconds),
  );
}

/// Duration of a WAV (RIFF/WAVE) byte array; null if it is not a WAV. Computed
/// from the byteRate in the fmt chunk and the length of the data chunk (extra
/// chunks are skipped).
Duration? wavDuration(Uint8List b) {
  if (b.length < 44 ||
      String.fromCharCodes(b.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(b.sublist(8, 12)) != 'WAVE') {
    return null;
  }
  final view = ByteData.sublistView(b);
  var byteRate = 0;
  var offset = 12;
  while (offset + 8 <= b.length) {
    final id = String.fromCharCodes(b.sublist(offset, offset + 4));
    final size = view.getUint32(offset + 4, Endian.little);
    if (id == 'fmt ' && offset + 20 <= b.length) {
      byteRate = view.getUint32(offset + 16, Endian.little);
    } else if (id == 'data') {
      if (byteRate <= 0) return null;
      final available = b.length - (offset + 8);
      final dataLen = math.min(size, available);
      return Duration(microseconds: (dataLen * 1000000 / byteRate).round());
    }
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  return null;
}
