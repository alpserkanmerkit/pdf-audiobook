import 'dart:convert';

import 'package:sesli_kitap/src/sentence_split.dart';

/// Splits [text] into pieces that do not exceed the [maxBytes] UTF-8 byte limit
/// (the Google Cloud TTS text:synthesize input is limited to 5000 bytes -- Phase Bug-G).
/// Packs at sentence boundaries (same delimiter logic as [splitIntoSentences]); when
/// the next sentence would push a full piece over the limit, a new piece is started.
/// If a SINGLE sentence by itself exceeds the limit, it is split at word boundaries
/// (spaces -- a UTF-8 multi-byte character is never cut in the MIDDLE, because cut
/// points are always single-byte delimiters such as ASCII spaces and periods).
///
/// Empty input -> []. maxBytes <= 0 -> ArgumentError (meaningless limit).
List<String> chunkTextForTts(String text, {required int maxBytes}) {
  if (maxBytes <= 0) {
    throw ArgumentError.value(maxBytes, 'maxBytes', 'must be positive');
  }
  if (text.isEmpty) return [];

  final sentences = splitIntoSentences(text);
  if (sentences.isEmpty) return [];

  final chunks = <String>[];
  final current = StringBuffer();
  var currentBytes = 0;

  void flush() {
    if (current.isNotEmpty) {
      chunks.add(current.toString());
      current.clear();
      currentBytes = 0;
    }
  }

  for (final sentence in sentences) {
    final sentenceBytes = utf8.encode(sentence).length;

    if (sentenceBytes > maxBytes) {
      // A single sentence exceeds the limit on its own -- close the current piece first,
      // then split this sentence into its own sub-pieces at word boundaries.
      flush();
      chunks.addAll(_splitByWords(sentence, maxBytes: maxBytes));
      continue;
    }

    final separator = current.isEmpty ? '' : ' ';
    final addedBytes = utf8.encode(separator).length + sentenceBytes;
    if (current.isNotEmpty && currentBytes + addedBytes > maxBytes) {
      flush();
      current.write(sentence);
      currentBytes = sentenceBytes;
    } else {
      current
        ..write(separator)
        ..write(sentence);
      currentBytes += addedBytes;
    }
  }
  flush();

  return chunks;
}

/// Splits a single sentence that exceeds [maxBytes] at spaces (word boundaries)
/// into pieces under [maxBytes]. If even one multi-byte "word" (a run without
/// spaces) exceeds the limit -- last resort -- it is cut at a code point boundary
/// (never in the MIDDLE of a UTF-8 multi-byte character).
List<String> _splitByWords(String sentence, {required int maxBytes}) {
  final words = sentence.split(' ').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return [];

  final result = <String>[];
  final current = StringBuffer();
  var currentBytes = 0;

  void flush() {
    if (current.isNotEmpty) {
      result.add(current.toString());
      current.clear();
      currentBytes = 0;
    }
  }

  for (final word in words) {
    final wordBytes = utf8.encode(word).length;

    if (wordBytes > maxBytes) {
      flush();
      result.addAll(_splitByCodePoints(word, maxBytes: maxBytes));
      continue;
    }

    final separator = current.isEmpty ? '' : ' ';
    final addedBytes = utf8.encode(separator).length + wordBytes;
    if (current.isNotEmpty && currentBytes + addedBytes > maxBytes) {
      flush();
      current.write(word);
      currentBytes = wordBytes;
    } else {
      current
        ..write(separator)
        ..write(word);
      currentBytes += addedBytes;
    }
  }
  flush();

  return result;
}

/// Last-resort split: if even a single space-free "word" exceeds [maxBytes],
/// walks the Dart String's code points (runes) and adds each rune COMPLETELY or
/// not at all -- so the bytes of a multi-byte UTF-8 character are never split
/// across two pieces.
List<String> _splitByCodePoints(String word, {required int maxBytes}) {
  final result = <String>[];
  final current = StringBuffer();
  var currentBytes = 0;

  for (final rune in word.runes) {
    final ch = String.fromCharCode(rune);
    final chBytes = utf8.encode(ch).length;
    if (currentBytes + chBytes > maxBytes && current.isNotEmpty) {
      result.add(current.toString());
      current.clear();
      currentBytes = 0;
    }
    current.write(ch);
    currentBytes += chBytes;
  }
  if (current.isNotEmpty) {
    result.add(current.toString());
  }

  return result;
}
