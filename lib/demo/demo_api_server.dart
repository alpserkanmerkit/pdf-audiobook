// Shared FAKE server for DEMO mode and E2E tests (no live API keys, no network).
//
// The REAL URLs the app knows (https://api.deepseek.com/..., Google TTS, ...)
// are not changed: [DemoHttpOverrides] redirects the dart:io HttpClient to a
// loopback server and carries the ORIGINAL host in the `x-e2e-original-host`
// header. So the app's real `http.Client()` -> postChatCompletion / GoogleTts /
// GeminiTts path runs without adding any seam to lib/ code, and the server
// records "which host, which path, with which Authorization" for each request.
// No request leaves loopback (the client wrapper maps every connection to
// 127.0.0.1).
//
// The response content is supplied from OUTSIDE (E2E: the "E2E ..." texts in
// integration_test/support/fake_api_server.dart; DEMO: the canned content in
// lib/demo/demo_llm_router.dart and demo_content.dart; the book text stays Turkish).
//
// HONEST LIMIT: no TLS handshake and no DNS (the request goes to loopback over
// plain HTTP). Verified: the client's URL (host + path), the
// Authorization/X-Goog-Api-Key header, and the body contract. NOT verified: the
// real server's response contract.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sesli_kitap/demo/demo_wav.dart';

/// Header that carries the original (https) host; added by [DemoHttpOverrides].
const String kOriginalHostHeader = 'x-e2e-original-host';

/// Produces the `message.content` value of a chat (chat/completions) request.
/// If it returns null, the request counts as "unrouted" (logged to
/// [DemoApiServer.unrouted]) and the safe fallback `{"metin": <user>}` is returned.
typedef ChatResponder = String? Function(RecordedRequest request);

/// Audio bytes to synthesize for [text].
typedef AudioResponder = Uint8List Function(String text);

class RecordedRequest {
  RecordedRequest({
    required this.method,
    required this.path,
    required this.originalHost,
    required this.headers,
    required this.body,
  });

  final String method;
  final String path;

  /// The host the app actually targets (e.g. api.deepseek.com).
  final String? originalHost;

  /// Lowercase header names.
  final Map<String, String> headers;
  final String body;

  String? get authorization => headers['authorization'];

  Map<String, Object?> get json {
    final decoded = jsonDecode(body);
    return (decoded as Map).cast<String, Object?>();
  }

  /// Chat request: the system + last user message.
  String get systemMessage => _message('system');
  String get userMessage => _message('user');

  String _message(String role) {
    final messages = (json['messages']! as List).cast<Map<String, Object?>>();
    return messages.firstWhere((m) => m['role'] == role)['content']! as String;
  }

  /// Text to synthesize in a Google TTS request.
  String get ttsText => ((json['input']! as Map)['text']) as String;

  /// Text to synthesize in a Gemini TTS (generateContent) request.
  String get geminiTtsText {
    final contents = (json['contents']! as List).first as Map;
    final parts = contents['parts']! as List;
    return (parts.first as Map)['text']! as String;
  }

  @override
  String toString() => '$method $originalHost$path';
}

class DemoApiServer {
  DemoApiServer._(
    this._server,
    this._chat,
    this._googleAudio,
    this._geminiPcm,
  ) {
    _server.listen(_handle);
  }

  final HttpServer _server;
  final ChatResponder _chat;
  final AudioResponder _googleAudio;
  final AudioResponder _geminiPcm;

  /// All requests in arrival order (including unrecognized ones).
  final List<RecordedRequest> requests = <RecordedRequest>[];

  /// Unrecognized (404 / unrouted) requests: tests expect this list to be EMPTY.
  final List<RecordedRequest> unrouted = <RecordedRequest>[];

  /// Answer chat (chat/completions) requests with this HTTP status (null = normal 200).
  int? chatStatusOverride;

  /// Answer chat requests whose original host is in this set with 503 (to drive
  /// the provider fallback path in "all" mode).
  final Set<String> failingChatHosts = <String>{};

  /// [chatResponder] is required. If no audio responders are given, a silent WAV
  /// (duration proportional to the text length) is returned.
  static Future<DemoApiServer> start({
    required ChatResponder chatResponder,
    AudioResponder? googleAudio,
    AudioResponder? geminiPcm,
    double charsPerSecond = kDemoCharsPerSecond,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Duration dur(String t) =>
        demoSpeechDuration(t, charsPerSecond: charsPerSecond);
    return DemoApiServer._(
      server,
      chatResponder,
      googleAudio ?? (t) => silentWav(duration: dur(t)),
      geminiPcm ??
          (t) => Uint8List(
            (dur(t).inMicroseconds * kDemoSampleRate / 1000000).round() * 2,
          ),
    );
  }

  int get port => _server.port;

  Iterable<RecordedRequest> get chatRequests =>
      requests.where((r) => r.path.endsWith('/chat/completions'));

  Iterable<RecordedRequest> get ttsRequests =>
      requests.where((r) => r.path == '/v1/text:synthesize');

  Iterable<RecordedRequest> get geminiTtsRequests =>
      requests.where((r) => r.path.endsWith(':generateContent'));

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final body = await utf8.decoder.bind(req).join();
    final headers = <String, String>{};
    req.headers.forEach((name, values) {
      headers[name.toLowerCase()] = values.join(',');
    });
    final rec = RecordedRequest(
      method: req.method,
      path: req.uri.path,
      originalHost: headers[kOriginalHostHeader],
      headers: headers,
      body: body,
    );
    requests.add(rec);

    final res = req.response;
    try {
      if (req.method == 'POST' && rec.path.endsWith('/chat/completions')) {
        _replyChat(rec, res);
      } else if (req.method == 'POST' && rec.path == '/v1/text:synthesize') {
        res
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'audioContent': base64Encode(_googleAudio(rec.ttsText)),
            }),
          );
      } else if (req.method == 'POST' &&
          rec.path.endsWith(':generateContent')) {
        res
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {
                        'inlineData': {
                          'mimeType': 'audio/L16;rate=$kDemoSampleRate',
                          'data': base64Encode(_geminiPcm(rec.geminiTtsText)),
                        },
                      },
                    ],
                  },
                },
              ],
            }),
          );
      } else {
        unrouted.add(rec);
        res
          ..statusCode = 404
          ..write('{"error":"demo-unrouted"}');
      }
    } on Object catch (e) {
      // The fake server reports its own error as a 500 (no silent pass-through).
      unrouted.add(rec);
      res
        ..statusCode = 500
        ..write(jsonEncode({'error': 'demo-server: $e'}));
    }
    await res.close();
  }

  void _replyChat(RecordedRequest rec, HttpResponse res) {
    final status =
        chatStatusOverride ??
        (failingChatHosts.contains(rec.originalHost) ? 503 : null);
    if (status != null) {
      res
        ..statusCode = status
        ..write('{"error":"e2e-injected-status"}');
      return;
    }
    var content = _chat(rec);
    if (content == null) {
      unrouted.add(rec);
      content = jsonEncode({'metin': rec.userMessage});
    }
    res
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': content},
            },
          ],
        }),
      );
  }
}

/// Redirects the dart:io HttpClient to [DemoApiServer] (without changing lib/).
/// package:http's IOClient only uses `openUrl` + `userAgent` + `close`; the
/// others are unsupported (UnsupportedError -> no silent pass-through).
class DemoHttpOverrides extends HttpOverrides {
  DemoHttpOverrides(this.port);

  final int port;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _RedirectingHttpClient(super.createHttpClient(context), port);
}

class _RedirectingHttpClient implements HttpClient {
  _RedirectingHttpClient(this._inner, this._port);

  final HttpClient _inner;
  final int _port;

  @override
  String? get userAgent => _inner.userAgent;
  @override
  set userAgent(String? value) => _inner.userAgent = value;

  @override
  bool get autoUncompress => _inner.autoUncompress;
  @override
  set autoUncompress(bool value) => _inner.autoUncompress = value;

  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;

  @override
  Duration get idleTimeout => _inner.idleTimeout;
  @override
  set idleTimeout(Duration value) => _inner.idleTimeout = value;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final target = Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: _port,
      path: url.path,
      query: url.hasQuery ? url.query : null,
    );
    final req = await _inner.openUrl(method, target);
    req.headers.set(kOriginalHostHeader, url.host);
    return req;
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  void close({bool force = false}) => _inner.close(force: force);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'DemoHttpOverrides: ${invocation.memberName} is not supported',
  );
}
