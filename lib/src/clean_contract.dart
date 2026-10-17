import 'dart:convert';

import 'package:sesli_kitap/src/llm_fence.dart';

class CleanResult {
  CleanResult(this.metin);
  final String metin;
}

class CleanParseException implements Exception {
  CleanParseException(this.reason);
  final String reason;
  @override
  String toString() => 'CleanParseException: $reason';
}

CleanResult parseCleanResponse(String raw) {
  // K1: fence stripping lives in the shared helper (tolerates single-line fences too).
  final trimmed = stripCodeFence(raw);

  dynamic parsed;
  try {
    parsed = jsonDecode(trimmed);
  } on Object catch (_) {
    throw CleanParseException('metin');
  }

  if (parsed is! Map<String, dynamic> || !parsed.containsKey('metin')) {
    throw CleanParseException('metin');
  }

  final value = parsed['metin'];
  if (value is! String || value.trim().isEmpty) {
    throw CleanParseException('metin');
  }

  return CleanResult(value);
}
