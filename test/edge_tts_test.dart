// Oracle test (FAZ3a K15): a double turn.end frame -> the second done.complete()
// must not throw StateError (single-completion contract).
// No real endpoint is reached: a fake channel is injected through the connection
// factory of EdgeTts (connect parameter, impl scope).
// The fake channel uses a sync controller: frames are published in the SAME call
// chain as soon as the SSML message is written to the sink -> no microtask race,
// so RED/GREEN is deterministic. (Today: no guard -> StateError -> RED.)
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/io/edge_tts.dart';
import 'package:sesli_kitap/io/tts_provider.dart';
import 'package:sesli_kitap/src/voices.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// edge-tts binary frame: 2-byte big-endian header length + header
/// (contains Path:audio) + mp3 payload (lib/src/tts_messages.dart contract).
Uint8List _audioFrame(List<int> payload) {
  final header = utf8.encode(
    'X-RequestId:x\r\nContent-Type:audio/mpeg\r\nPath:audio\r\n\r\n',
  );
  final b = BytesBuilder()
    ..add([header.length >> 8, header.length & 0xff])
    ..add(header)
    ..add(payload);
  return b.toBytes();
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this._onAdd);
  final void Function(dynamic data) _onAdd;

  @override
  void add(dynamic data) => _onAdd(data);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Fake channel that, once an SSML message is written to the sink, publishes one
/// audio frame + TWO turn.end frames (a double turn.end was observed in the field on Windows).
class _DoubleTurnEndChannel implements WebSocketChannel {
  final StreamController<dynamic> _controller = StreamController<dynamic>(
    sync: true,
  );

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  WebSocketSink get sink => _FakeSink((data) {
    if (data is String && data.contains('Path:ssml')) {
      _controller
        ..add(_audioFrame([1, 2, 3]))
        ..add('Path:turn.end\r\n\r\n{}')
        ..add('Path:turn.end\r\n\r\n{}');
    }
  });

  @override
  Future<void> get ready => Future<void>.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Builds an audio.metadata text frame (WordBoundary events).
String _metadataFrame() {
  const body =
      '{"Metadata":[{"Type":"WordBoundary","Data":{"Offset":1000000,'
      '"Duration":2000000,"text":{"Text":"merhaba"}}}]}';
  return 'X-RequestId:x\r\nContent-Type:application/json; charset=utf-8\r\n'
      'Path:audio.metadata\r\n\r\n$body';
}

/// Fake channel that, once an SSML message is written, publishes: one audio frame +
/// ONE metadata text frame + turn.end; it captures the messages written to the sink
/// (including speech.config).
class _TimedChannel implements WebSocketChannel {
  final StreamController<dynamic> _controller = StreamController<dynamic>(
    sync: true,
  );
  final List<String> writes = [];

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  WebSocketSink get sink => _FakeSink((data) {
    if (data is String) {
      writes.add(data);
      if (data.contains('Path:ssml')) {
        _controller
          ..add(_audioFrame([1, 2, 3]))
          ..add(_metadataFrame())
          ..add('Path:turn.end\r\n\r\n{}');
      }
    }
  });

  @override
  Future<void> get ready => Future<void>.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'double turn.end -> single completion, no StateError; audio is returned',
    () async {
      final tts = EdgeTts(connect: (_) async => _DoubleTurnEndChannel());
      final bytes = await tts.synthesize(
        text: 'merhaba',
        voice: SesliVoice.emel,
      );
      expect(bytes, [1, 2, 3]);
    },
  );

  test('synthesizeWithTimings -> audio + parsed words; speech.config '
      'wordBoundary ON', () async {
    late _TimedChannel ch;
    final tts = EdgeTts(
      connect: (_) async {
        return ch = _TimedChannel();
      },
    );
    final result = await tts.synthesizeWithTimings(
      text: 'merhaba',
      voice: SesliVoice.emel,
    );
    expect(result, isA<TimedSynthesis>());
    expect(result.audio, [1, 2, 3]);
    expect(result.words, isNotNull);
    expect(result.words!.length, 1);
    expect(result.words![0].text, 'merhaba');
    expect(result.words![0].offsetMs, 100); // 1000000 ~/ 10000
    // The captured speech.config must have wordBoundary ON.
    final config = ch.writes.firstWhere((w) => w.contains('speech.config'));
    expect(config, contains('"wordBoundaryEnabled":"true"'));
  });

  test(
    'plain synthesize -> speech.config wordBoundary OFF (behavior byte-identical)',
    () async {
      late _TimedChannel ch;
      final tts = EdgeTts(
        connect: (_) async {
          return ch = _TimedChannel();
        },
      );
      final bytes = await tts.synthesize(
        text: 'merhaba',
        voice: SesliVoice.emel,
      );
      expect(bytes, [1, 2, 3]);
      final config = ch.writes.firstWhere((w) => w.contains('speech.config'));
      expect(config, contains('"wordBoundaryEnabled":"false"'));
    },
  );
}
