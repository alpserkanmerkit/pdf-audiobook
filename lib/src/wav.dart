// Pure WAV helper (Gemini TTS slice, 2026-09-28) -- NO I/O.
// Gemini TTS audio is usually returned as a HEADERED WAV (RIFF); sometimes as raw
// 16-bit PCM (mimeType 'audio/L16;...;rate=24000'). The player detects the file from
// its content; so the single rule is: if it is RIFF, DO NOT TOUCH it (a double header
// causes a "crackle" -- a field lesson); if it is raw PCM, wrap it with a 44-byte
// mono 16-bit header.
import 'dart:typed_data';

/// Default sample rate documented for Gemini TTS.
const int kDefaultTtsSampleRate = 24000;

/// Reads the `rate=` value from the mimeType; if absent, [kDefaultTtsSampleRate].
int sampleRateFromMime(String? mime) {
  final match = RegExp(r'rate=(\d+)').firstMatch(mime ?? '');
  return match == null ? kDefaultTtsSampleRate : int.parse(match.group(1)!);
}

/// Returns [bytes] unchanged if they are already WAV; if raw PCM, returns them wrapped with a WAV header.
Uint8List ensureWav(Uint8List bytes, {required int sampleRate}) =>
    _isRiff(bytes) ? bytes : pcmToWav(bytes, sampleRate: sampleRate);

/// Wraps mono 16-bit raw PCM into a WAV with a standard 44-byte header.
Uint8List pcmToWav(Uint8List pcm, {required int sampleRate}) {
  final header = ByteData(44);
  void tag(int offset, String fourChars) {
    for (var i = 0; i < 4; i++) {
      header.setUint8(offset + i, fourChars.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  header
    ..setUint32(16, 16, Endian.little) // fmt chunk length
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, 1, Endian.little) // mono
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * 2, Endian.little) // bytes/sec
    ..setUint16(32, 2, Endian.little) // block align
    ..setUint16(34, 16, Endian.little); // bits
  tag(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);
  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(pcm))
      .toBytes();
}

bool _isRiff(Uint8List b) =>
    b.length >= 4 &&
    b[0] == 0x52 &&
    b[1] == 0x49 &&
    b[2] == 0x46 &&
    b[3] == 0x46;
