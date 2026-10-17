import 'dart:convert';

import 'package:sesli_kitap/src/chapter_map.dart';
import 'package:sesli_kitap/src/llm_fence.dart';

/// Exception thrown when skeleton JSON fails to parse or validate.
class SkeletonParseException implements Exception {
  const SkeletonParseException();
}

/// Strips leading or trailing page numbers separated by • or ».
String stripHeaderPageNumber(String header) {
  final trimmed = header.trim();
  if (trimmed.isEmpty) return '';
  const leading = r'^\d+\s*[•»]\s*';
  const trailing = r'\s*[•»]\s*\d+$';
  var result = trimmed.replaceFirst(RegExp(leading), '');
  result = result.replaceFirst(RegExp(trailing), '');
  return result.trim();
}

/// Builds the prompt input string from a list of page header entries.
String buildSkeletonInput(List<PageHeaderEntry> headers) {
  final lines = <String>[];
  for (final entry in headers) {
    final stripped = stripHeaderPageNumber(entry.header ?? '');
    lines.add('s${entry.page}: $stripped');
  }
  return lines.join('\n');
}

/// Parses the LLM response into an unmodifiable list of [Chapter]s.
List<Chapter> parseSkeletonResponse(String raw, {required int totalPages}) {
  // K1: fence stripping lives in the shared helper — a single-line fence can no
  // longer raise RangeError; leftover corrupt content is caught below as a
  // FormatException -> SkeletonParseException.
  final content = stripCodeFence(raw);

  // Parse JSON
  final dynamic parsed;
  try {
    parsed = jsonDecode(content);
  } on FormatException {
    throw const SkeletonParseException();
  }

  if (parsed is! Map<String, dynamic> || !parsed.containsKey('chapters')) {
    throw const SkeletonParseException();
  }

  final chaptersRaw = parsed['chapters'];
  if (chaptersRaw is! List || chaptersRaw.isEmpty) {
    throw const SkeletonParseException();
  }

  final chapters = <Chapter>[];
  for (final entry in chaptersRaw) {
    if (entry is! Map<String, dynamic>) {
      throw const SkeletonParseException();
    }

    final title = entry['title'];
    if (title is! String || title.trim().isEmpty) {
      throw const SkeletonParseException();
    }

    final startPage = entry['startPage'];
    final endPage = entry['endPage'];
    if (startPage is! int || endPage is! int) {
      throw const SkeletonParseException();
    }

    if (startPage < 1 || endPage > totalPages || startPage > endPage) {
      throw const SkeletonParseException();
    }

    if (chapters.isNotEmpty && startPage <= chapters.last.endPage) {
      throw const SkeletonParseException();
    }

    chapters.add(
      Chapter(title: title.trim(), startPage: startPage, endPage: endPage),
    );
  }

  return List<Chapter>.unmodifiable(chapters);
}
