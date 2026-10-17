// Fake server for the E2E smoke tests: the shared mechanism lives in lib/demo/
// (DemoApiServer + DemoHttpOverrides -- the SAME code demo mode uses); here only
// the E2E-specific response content exists ("E2E ..." texts, "ID3" fake mp3
// bytes). This way the e2e tests also verify the demo server's HTTP layer on
// every run.
import 'dart:convert';
import 'dart:typed_data';

import 'package:sesli_kitap/demo/demo_api_server.dart';
import 'package:sesli_kitap/src/tutor/tutor_prompts.dart'
    show kTutorSystemPrompt;

export 'package:sesli_kitap/demo/demo_api_server.dart'
    show DemoApiServer, DemoHttpOverrides, RecordedRequest;

/// Recognizable fake audio bytes returned in the TTS response ("ID3" + marker).
final Uint8List kFakeAudioBytes = Uint8List.fromList(<int>[
  0x49, 0x44, 0x33, 0x03, 0x00, 0x00, // ID3v2.3 header start
  ...utf8.encode('E2E-FAKE-MP3-PAYLOAD'),
]);

/// Starts the E2E server (chat replies are E2E-specific, audio = [kFakeAudioBytes]).
Future<DemoApiServer> startE2eServer() => DemoApiServer.start(
  chatResponder: _e2eChatContent,
  googleAudio: (_) => kFakeAudioBytes,
);

/// The `content` value of the OpenAI-compatible chat reply (fake "model"):
/// - tutor system prompt + 'STUDENT ANSWER:' -> grade JSON
/// - tutor system prompt -> {"anlatim","sorular"} (part no. taken from the prompt)
/// - anything else (text cleaner etc.) -> {"metin": user text} (verbatim)
String _e2eChatContent(RecordedRequest rec) {
  if (rec.systemMessage == kTutorSystemPrompt) {
    final user = rec.userMessage;
    if (user.contains('STUDENT ANSWER:')) {
      return jsonEncode({
        'sonuc': 'dogru',
        'aciklama': 'E2E: Well done, you got the gist.',
      });
    }
    final m = RegExp(r'Part (\d+)/(\d+)').firstMatch(user);
    final no = m?.group(1) ?? '?';
    return jsonEncode({
      'anlatim': 'E2E explanation part $no.',
      'sorular': [
        {'soru': 'E2E question part $no?', 'beklenen': 'E2E expected $no'},
      ],
    });
  }
  return jsonEncode({'metin': rec.userMessage});
}
