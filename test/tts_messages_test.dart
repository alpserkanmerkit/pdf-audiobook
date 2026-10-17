// Oracle test (PHASE 1): building edge-tts websocket messages -- PURE string/byte logic.
// Reference protocol: rany2/edge-tts (spec §2). The live endpoints are not a gate test
// (manual acceptance); here only the deterministic message format is verified
// (timestamp/requestId are injected from OUTSIDE = hermetic).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/tts_messages.dart';

void main() {
  group('escapeXml', () {
    test('escapes XML special characters', () {
      expect(
        escapeXml('a & b < c > "d" \'e\''),
        'a &amp; b &lt; c &gt; &quot;d&quot; &apos;e&apos;',
      );
    });
    test('leaves plain Turkish text unchanged', () {
      expect(escapeXml('farkındalık ve şükür'), 'farkındalık ve şükür');
    });
  });

  group('buildSsml', () {
    test('contains voice + rate + escaped text', () {
      final ssml = buildSsml(
        text: 'Gel & gör',
        voiceId: 'tr-TR-AhmetNeural',
        rate: '+0%',
        languageCode: 'tr-TR',
      );
      expect(ssml, contains('<speak'));
      expect(ssml, contains("xml:lang='tr-TR'"));
      expect(ssml, contains("<voice name='tr-TR-AhmetNeural'>"));
      expect(ssml, contains("rate='+0%'"));
      expect(ssml, contains('Gel &amp; gör'));
      expect(ssml, contains('</speak>'));
    });
    test('raw < > text cannot break SSML structure', () {
      final ssml = buildSsml(
        text: '<speak>sahte</speak>',
        voiceId: 'tr-TR-EmelNeural',
        rate: '-20%',
        languageCode: 'tr-TR',
      );
      expect(ssml, contains('&lt;speak&gt;sahte&lt;/speak&gt;'));
    });
    // Phase 2 (English TTS support): the tr-TR hardcode was removed --
    // xml:lang now passes the caller's languageCode through as-is.
    test('English languageCode -> xml:lang en-US (hardcode removed)', () {
      final ssml = buildSsml(
        text: 'Hello',
        voiceId: 'en-US-Wavenet-D',
        rate: '+0%',
        languageCode: 'en-US',
      );
      expect(ssml, contains("xml:lang='en-US'"));
      expect(ssml, contains("<voice name='en-US-Wavenet-D'>"));
    });
  });

  group('buildSpeechConfigMessage', () {
    test('header + empty line + JSON body; mp3 output format pinned', () {
      final msg = buildSpeechConfigMessage(timestamp: 'TS-FIXED');
      expect(msg, contains('X-Timestamp:TS-FIXED'));
      expect(msg, contains('Content-Type:application/json'));
      expect(msg, contains('Path:speech.config'));
      expect(msg, contains('\r\n\r\n'));
      expect(msg, contains('audio-24khz-48kbitrate-mono-mp3'));
      final body = msg.split('\r\n\r\n')[1];
      expect(() => jsonDecode(body), returnsNormally);
    });

    test(
      'no parameter (default) output has wordBoundary OFF -- discussion-path pin '
      '(byte-identical behavior)',
      () {
        final msg = buildSpeechConfigMessage(timestamp: 'TS-FIXED');
        expect(msg, contains('"wordBoundaryEnabled":"false"'));
      },
    );

    test('wordBoundary:false explicitly -> still OFF', () {
      final msg = buildSpeechConfigMessage(timestamp: 'TS-FIXED');
      expect(msg, contains('"wordBoundaryEnabled":"false"'));
    });

    test('wordBoundary:true -> ON (karaoke timing path)', () {
      final msg = buildSpeechConfigMessage(
        timestamp: 'TS-FIXED',
        wordBoundary: true,
      );
      expect(msg, contains('"wordBoundaryEnabled":"true"'));
      // JSON body is still valid.
      final body = msg.split('\r\n\r\n')[1];
      expect(() => jsonDecode(body), returnsNormally);
    });
  });

  group('isAudioMetadata', () {
    test('Path:audio.metadata frame -> true', () {
      expect(
        isAudioMetadata('X-RequestId:1\r\nPath:audio.metadata\r\n\r\n{}'),
        isTrue,
      );
    });
    test('audio (not metadata) / turn.end -> false', () {
      expect(isAudioMetadata('Path:audio\r\n\r\n'), isFalse);
      expect(isAudioMetadata('Path:turn.end\r\n\r\n{}'), isFalse);
    });
  });

  group('parseMetadataWords', () {
    String frame(String body) =>
        'X-RequestId:1\r\nContent-Type:application/json; charset=utf-8\r\n'
        'Path:audio.metadata\r\n\r\n$body';

    test(
      'extracts WordBoundary events (Offset/Duration 100ns ticks -> ms)',
      () {
        const body =
            '{"Metadata":[{"Type":"WordBoundary","Data":{"Offset":8750000,'
            '"Duration":5000000,"text":{"Text":"merhaba"}}}]}';
        final words = parseMetadataWords(frame(body));
        expect(words.length, 1);
        expect(words[0].offsetMs, 875); // 8750000 ~/ 10000
        expect(words[0].durationMs, 500); // 5000000 ~/ 10000
        expect(words[0].text, 'merhaba');
      },
    );

    test('skips Types that are not WordBoundary', () {
      const body =
          '{"Metadata":[{"Type":"SentenceBoundary","Data":{"Offset":0,'
          '"Duration":0,"text":{"Text":"x"}}},{"Type":"WordBoundary","Data":'
          '{"Offset":10000,"Duration":10000,"text":{"Text":"iyi"}}}]}';
      final words = parseMetadataWords(frame(body));
      expect(words.length, 1);
      expect(words[0].text, 'iyi');
      expect(words[0].offsetMs, 1);
    });

    test('broken JSON -> [] (never throws)', () {
      expect(parseMetadataWords(frame('{bozuk%%')), isEmpty);
    });

    test('Metadata field missing / empty -> []', () {
      expect(parseMetadataWords(frame('{}')), isEmpty);
      expect(parseMetadataWords(frame('{"Metadata":[]}')), isEmpty);
    });

    test('entries with missing fields are skipped; valid ones pass', () {
      const body =
          '{"Metadata":[{"Type":"WordBoundary","Data":{"Offset":10000}},'
          '{"Type":"WordBoundary","Data":{"Offset":20000,"Duration":10000,'
          '"text":{"Text":"tam"}}}]}';
      final words = parseMetadataWords(frame(body));
      expect(words.length, 1);
      expect(words[0].text, 'tam');
    });
  });

  group('buildSsmlMessage', () {
    test('carries requestId + ssml body', () {
      final msg = buildSsmlMessage(
        requestId: 'abc123',
        timestamp: 'TS-FIXED',
        ssml: '<speak>x</speak>',
      );
      expect(msg, contains('X-RequestId:abc123'));
      expect(msg, contains('X-Timestamp:TS-FIXED'));
      expect(msg, contains('Content-Type:application/ssml+xml'));
      expect(msg, contains('Path:ssml'));
      expect(msg.split('\r\n\r\n')[1], '<speak>x</speak>');
    });
  });

  group('isTurnEnd', () {
    test('recognizes the turn.end message', () {
      expect(isTurnEnd('X-RequestId:1\r\nPath:turn.end\r\n\r\n{}'), isTrue);
    });
    test('false for other path messages', () {
      expect(isTurnEnd('X-RequestId:1\r\nPath:turn.start\r\n\r\n{}'), isFalse);
    });
  });

  group('extractAudioPayload', () {
    Uint8List frame(String header, List<int> payload) {
      final h = utf8.encode(header);
      return Uint8List.fromList([
        h.length >> 8,
        h.length & 0xff,
        ...h,
        ...payload,
      ]);
    }

    test('extracts audio bytes from a frame with a Path:audio header', () {
      final f = frame(
        'X-RequestId:1\r\nContent-Type:audio/mpeg\r\nPath:audio\r\n',
        [9, 8, 7],
      );
      expect(extractAudioPayload(f), Uint8List.fromList([9, 8, 7]));
    });
    test('non-audio header -> null', () {
      final f = frame('Path:metadata\r\n', [1, 2]);
      expect(extractAudioPayload(f), isNull);
    });
    test(
      'frame shorter than 2 bytes -> null (broken input never silently produces audio)',
      () {
        expect(extractAudioPayload(Uint8List.fromList([0])), isNull);
        expect(extractAudioPayload(Uint8List(0)), isNull);
      },
    );
    test(
      'empty payload -> empty list (not null; the turn may still be in progress)',
      () {
        final f = frame('Path:audio\r\n', []);
        expect(extractAudioPayload(f), Uint8List(0));
      },
    );

    test(
      'Path:audio.metadata header -> null (if metadata gets mixed into the binary, the MP3 must not be corrupted; hardening)',
      () {
        final f = frame(
          'X-RequestId:1\r\nContent-Type:application/json\r\n'
          'Path:audio.metadata\r\n',
          [1, 2, 3],
        );
        expect(extractAudioPayload(f), isNull);
      },
    );
  });
}
