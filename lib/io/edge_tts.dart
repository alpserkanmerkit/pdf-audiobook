// PHASE 1 wiring: edge-tts websocket client (spec §2; reference: rany2/edge-tts).
// Message BUILDING lives in the pure layer (lib/src/tts_messages.dart, gate-tested);
// only connection/streaming is here. The LIVE endpoint is NOT gate-tested -> manual
// acceptance; if it breaks, use the Azure F0 fallback (spec §9) -- the TtsProvider
// interface is split in Phase 2.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sesli_kitap/io/tts_provider.dart';
import 'package:sesli_kitap/src/sentence_timing.dart';
import 'package:sesli_kitap/src/tts_messages.dart';
import 'package:sesli_kitap/src/voices.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class EdgeTtsException implements Exception {
  EdgeTtsException(this.reason);
  final String reason;

  @override
  String toString() => 'EdgeTtsException: $reason';
}

const String _trustedClientToken =
    '6A5AA1D4EAFF4E9FB37E23D68491D6F4'; // gitleaks:allow (public Edge client constant)
// FIELD PROOF (2026-06-11, 2nd device test): with the 130.x release it returned
// 403; the reference python edge-tts (v7+, CHROMIUM_FULL_VERSION=143.0.3650.75)
// WORKED from the same network -> the version is validated server-side. This
// constant is kept in sync with the reference package.
const String _chromiumFullVersion = '143.0.3650.75';
const String _chromiumMajor = '143';
const String _gecVersion = '1-$_chromiumFullVersion';

/// Sec-MS-GEC DRM value: Windows file-time ticks are rounded to a 5-minute
/// window, concatenated with the token, and SHA-256 hashed as uppercase hex.
String secMsGec(DateTime nowUtc) {
  var ticks = (nowUtc.millisecondsSinceEpoch ~/ 1000 + 11644473600) * 10000000;
  ticks -= ticks % 3000000000;
  return sha256
      .convert(utf8.encode('$ticks$_trustedClientToken'))
      .toString()
      .toUpperCase();
}

String _newRequestId() {
  final r = Random.secure();
  final sb = StringBuffer();
  for (var i = 0; i < 32; i++) {
    sb.write(r.nextInt(16).toRadixString(16));
  }
  return sb.toString();
}

class EdgeTts implements TimedTtsProvider {
  /// [connect] is a test seam (FAZ3a K15): a fake channel can be injected; if
  /// null, a real WebSocket connection is made.
  EdgeTts({Future<WebSocketChannel> Function(Uri uri)? connect})
    : _connect = connect;

  final Future<WebSocketChannel> Function(Uri uri)? _connect;

  static Future<WebSocketChannel> _defaultConnect(Uri uri) async {
    // FIELD PROOF (3rd device test + PC dart-repro, 2026-06-11): dart:io's
    // DEFAULT HttpClient adds its own 'User-Agent: Dart/...' value -> our UA
    // becomes a second copy -> Microsoft answers 403 ("was not upgraded").
    // Repro: WS-DEFAULT-CLIENT=403, WS-UA-NULL-CLIENT=CONNECTED (readyState=1,
    // internal repro note). Fix: customClient.userAgent=null -> only the single
    // UA from the headers is sent.
    final httpClient = HttpClient()..userAgent = null;
    final ws = await WebSocket.connect(
      uri.toString(),
      customClient: httpClient,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/$_chromiumMajor.0.0.0 Safari/537.36 '
            'Edg/$_chromiumMajor.0.0.0',
        'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
        'Pragma': 'no-cache',
        'Cache-Control': 'no-cache',
        'Accept-Encoding': 'gzip, deflate, br, zstd',
        'Accept-Language': 'en-US,en;q=0.9',
      },
    );
    return IOWebSocketChannel(ws);
  }

  /// [text] is the clean page text; returns mp3 bytes. Behavior is byte-identical
  /// (collectWords:false -> speech.config wordBoundary is OFF).
  @override
  Future<Uint8List> synthesize({
    required String text,
    required SesliVoice voice,
    double rate = 1.0,
  }) async {
    final r = await _run(
      text: text,
      voice: voice,
      rate: rate,
      collectWords: false,
    );
    return r.audio;
  }

  /// Karaoke foundation (PR-K1): audio + word-boundary events. If no words were
  /// collected, words is null (alignment is done in the pipeline after synthesis
  /// ends).
  @override
  Future<TimedSynthesis> synthesizeWithTimings({
    required String text,
    required SesliVoice voice,
    double rate = 1.0,
  }) => _run(text: text, voice: voice, rate: rate, collectWords: true);

  Future<TimedSynthesis> _run({
    required String text,
    required SesliVoice voice,
    required double rate,
    required bool collectWords,
  }) async {
    final requestId = _newRequestId();
    final now = DateTime.now().toUtc();
    final uri = Uri.parse(
      'wss://speech.platform.bing.com/consumer/speech/synthesize/'
      'readaloud/edge/v1'
      '?TrustedClientToken=$_trustedClientToken'
      '&Sec-MS-GEC=${secMsGec(now)}'
      '&Sec-MS-GEC-Version=$_gecVersion'
      '&ConnectionId=$requestId',
    );
    final channel = await (_connect ?? _defaultConnect)(uri);
    final audio = BytesBuilder(copy: false);
    final words = <WordBoundary>[];
    final done = Completer<void>();
    final ts = now.toIso8601String();

    var binaryFrameCount = 0;
    var textFrameCount = 0;
    final sub = channel.stream.listen(
      (frame) {
        if (frame is String) {
          textFrameCount++;
          // Metadata text frames arrive mixed with binary audio frames, and all
          // of them come BEFORE turn.end -> just ACCUMULATE them.
          if (collectWords && isAudioMetadata(frame)) {
            words.addAll(parseMetadataWords(frame));
          }
          if (isTurnEnd(frame)) {
            // K15: a duplicate turn.end frame may arrive; an unguarded second
            // complete() throws StateError (inside the listener -> crash).
            if (!done.isCompleted) {
              done.complete();
            }
          }
        } else if (frame is List<int>) {
          binaryFrameCount++;
          final payload = extractAudioPayload(
            frame is Uint8List ? frame : Uint8List.fromList(frame),
          );
          if (payload != null) {
            audio.add(payload);
          }
        }
      },
      onError: (Object e) {
        if (!done.isCompleted) {
          done.completeError(EdgeTtsException('websocket error: $e'));
        }
      },
      onDone: () {
        if (!done.isCompleted) {
          // Closed before turn.end: use the audio if any was accumulated (on
          // Windows, turn.end is sometimes lost); if there is no audio at all,
          // fail with the diagnostic counters.
          if (audio.length > 0) {
            done.complete();
          } else {
            done.completeError(
              EdgeTtsException(
                'no-audio (closed before turn.end; '
                'binary=$binaryFrameCount text=$textFrameCount)',
              ),
            );
          }
        }
      },
    );

    try {
      await channel.ready;
      channel.sink.add(
        buildSpeechConfigMessage(timestamp: ts, wordBoundary: collectWords),
      );
      channel.sink.add(
        buildSsmlMessage(
          requestId: requestId,
          timestamp: ts,
          ssml: buildSsml(
            text: text,
            voiceId: voiceId(voice),
            rate: formatRate(rate),
            languageCode: localeCodeOf(voice),
          ),
        ),
      );
      await done.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw EdgeTtsException('no audio within 60s'),
      );
    } finally {
      await sub.cancel();
      await channel.sink.close();
    }
    final bytes = audio.takeBytes();
    if (bytes.isEmpty) {
      throw EdgeTtsException('empty audio returned (protocol/access problem?)');
    }
    return TimedSynthesis(audio: bytes, words: words.isEmpty ? null : words);
  }
}
