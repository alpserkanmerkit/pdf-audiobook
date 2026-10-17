import 'dart:convert';
import 'dart:typed_data';

import 'package:sesli_kitap/src/sentence_timing.dart' show WordBoundary;

String escapeXml(String s) {
  return s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

/// Phase 2 (English TTS support): xml:lang now comes from [languageCode] --
/// it used to be the constant 'tr-TR'. The caller (lib/src/voices.dart localeCodeOf)
/// derives the voice's OWN locale and passes it in, so the SSML always matches the real voice.
String buildSsml({
  required String text,
  required String voiceId,
  required String rate,
  required String languageCode,
}) {
  final escaped = escapeXml(text);
  return "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='$languageCode'><voice name='$voiceId'><prosody pitch='+0Hz' rate='$rate' volume='+0%'>$escaped</prosody></voice></speak>";
}

String buildSpeechConfigMessage({
  required String timestamp,
  bool wordBoundary = false,
}) {
  // The default (wordBoundary=false) output stays BYTE-IDENTICAL to today's string
  // (the discussion path uses it; pinned by a test). When true, wordBoundaryEnabled
  // is turned on for karaoke timing.
  final wb = wordBoundary ? 'true' : 'false';
  final body =
      '{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"$wb"},"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}';
  return 'X-Timestamp:$timestamp\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n$body';
}

String buildSsmlMessage({
  required String requestId,
  required String timestamp,
  required String ssml,
}) {
  return 'X-RequestId:$requestId\r\nX-Timestamp:$timestamp\r\nContent-Type:application/ssml+xml\r\nPath:ssml\r\n\r\n$ssml';
}

bool isTurnEnd(String textFrame) {
  return textFrame.contains('Path:turn.end');
}

/// Is this an audio.metadata text frame? (WordBoundary events arrive here.)
bool isAudioMetadata(String textFrame) {
  return textFrame.contains('Path:audio.metadata');
}

/// Extracts WordBoundary events from the body of an audio.metadata text frame.
/// The body is the JSON after `\r\n\r\n`. ANY corruption -> that input is skipped / [] is returned;
/// it NEVER throws (the audio stream is not affected by a timing error).
List<WordBoundary> parseMetadataWords(String textFrame) {
  final sep = textFrame.indexOf('\r\n\r\n');
  if (sep < 0) return const [];
  final bodyStr = textFrame.substring(sep + 4);
  final out = <WordBoundary>[];
  try {
    final decoded = jsonDecode(bodyStr);
    if (decoded is! Map) return const [];
    final meta = decoded['Metadata'];
    if (meta is! List) return const [];
    for (final e in meta) {
      if (e is! Map) continue;
      if (e['Type'] != 'WordBoundary') continue;
      final data = e['Data'];
      if (data is! Map) continue;
      final offset = data['Offset'];
      final duration = data['Duration'];
      final textObj = data['text'];
      if (offset is! int || duration is! int) continue;
      if (textObj is! Map) continue;
      final text = textObj['Text'];
      if (text is! String) continue;
      // 100-ns tick -> ms (~/ 10000).
      out.add(
        WordBoundary(
          offsetMs: offset ~/ 10000,
          durationMs: duration ~/ 10000,
          text: text,
        ),
      );
    }
  } on Object catch (_) {
    return const []; // broken JSON = no events
  }
  return out;
}

Uint8List? extractAudioPayload(Uint8List frame) {
  if (frame.length < 2) return null;
  final headerLen = (frame[0] << 8) | frame[1];
  if (headerLen > frame.length - 2) return null;
  final header = utf8.decode(frame.sublist(2, 2 + headerLen));
  // HARDENING: 'Path:audio' also matches 'Path:audio.metadata'; if the metadata
  // body mixes into the binary audio stream the MP3 gets corrupted. Exclude the metadata header.
  if (isAudioMetadata(header)) return null;
  if (!header.contains('Path:audio')) return null;
  return frame.sublist(2 + headerLen);
}
