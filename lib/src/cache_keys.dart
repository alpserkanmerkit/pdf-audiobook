import 'package:meta/meta.dart';

@immutable
class CacheStamp {
  const CacheStamp({
    required this.cleanPromptVersion,
    required this.ttsVoice,
    required this.ttsRate,
    this.pronTag = '',
  });
  final String cleanPromptVersion;
  final String ttsVoice;
  final String ttsRate;
  final String pronTag;

  @override
  bool operator ==(Object other) =>
      other is CacheStamp &&
      cleanPromptVersion == other.cleanPromptVersion &&
      ttsVoice == other.ttsVoice &&
      ttsRate == other.ttsRate &&
      pronTag == other.pronTag;

  @override
  int get hashCode =>
      Object.hash(cleanPromptVersion, ttsVoice, ttsRate, pronTag);
}

String _sanitize(String input) {
  final buffer = StringBuffer();
  for (final char in input.runes) {
    final c = String.fromCharCode(char);
    if (RegExp(r'^[a-zA-Z0-9._-]$').hasMatch(c)) {
      buffer.write(c);
    } else {
      buffer.write('x${char.toRadixString(16).padLeft(2, '0')}');
    }
  }
  return buffer.toString();
}

String textCacheKey({
  required String bookHash,
  required int pageNo,
  required String cleanPromptVersion,
}) {
  return 't_${_sanitize(bookHash)}_p${pageNo}_${_sanitize(cleanPromptVersion)}';
}

String audioCacheKey({
  required String bookHash,
  required int pageNo,
  required CacheStamp stamp,
}) {
  var key =
      'a_${_sanitize(bookHash)}_p${pageNo}_${_sanitize(stamp.cleanPromptVersion)}_${_sanitize(stamp.ttsVoice)}_${_sanitize(stamp.ttsRate)}';
  if (stamp.pronTag.isNotEmpty) {
    key += '_${_sanitize(stamp.pronTag)}';
  }
  return key;
}

bool isTextStale({
  required String storedPromptVersion,
  required String currentPromptVersion,
}) {
  return storedPromptVersion != currentPromptVersion;
}

bool isAudioStale({required CacheStamp stored, required CacheStamp current}) {
  final _ = stored.hashCode;
  return stored != current;
}
