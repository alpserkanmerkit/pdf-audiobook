import 'dart:convert';

import 'package:sesli_kitap/src/llm_fence.dart';

enum QuestionKind { olgusal, kavramsal, uygulamali }

class StudyQuestion {
  StudyQuestion({required this.soru, required this.cevap, required this.tip});
  final String soru;
  final String cevap;
  final QuestionKind tip;
}

class QuestionsParseException implements Exception {
  QuestionsParseException(this.message);
  final String message;

  @override
  String toString() => message;
}

List<StudyQuestion> parseQuestionsResponse(String raw) {
  // K1: shared helper instead of the local _unwrapFence (same tolerance semantics).
  final jsonStr = stripCodeFence(raw);

  Object decoded;
  try {
    decoded = jsonDecode(jsonStr) as Object;
  } on FormatException {
    throw QuestionsParseException('Invalid JSON format.');
  }

  if (decoded is! Map || !decoded.containsKey('sorular')) {
    throw QuestionsParseException('Missing required key "sorular".');
  }

  final list = decoded['sorular'] as Object?;
  if (list is! List) {
    throw QuestionsParseException('"sorular" must be a list.');
  }

  if (list.length < 8 || list.length > 12) {
    throw QuestionsParseException(
      'Expected 8-12 questions, got ${list.length}.',
    );
  }

  final questions = <StudyQuestion>[];
  for (final item in list) {
    if (item is! Map) {
      throw QuestionsParseException('Each question must be an object.');
    }
    final soru = item['soru'];
    final cevap = item['cevap'];
    final tipStr = item['tip'];
    if (soru is! String || cevap is! String || tipStr is! String) {
      throw QuestionsParseException(
        'Each question must have "soru", "cevap", and "tip" as strings.',
      );
    }
    if (soru.trim().isEmpty || cevap.trim().isEmpty) {
      throw QuestionsParseException('Question and answer must not be empty.');
    }
    final kind = QuestionKind.values.cast<QuestionKind?>().firstWhere(
      (k) => k!.name == tipStr,
      orElse: () => null,
    );
    if (kind == null) {
      throw QuestionsParseException('Invalid question type: "$tipStr".');
    }
    questions.add(StudyQuestion(soru: soru, cevap: cevap, tip: kind));
  }

  return List.unmodifiable(questions);
}

String buildQuestionsPrompt({
  required String chapterText,
  String? chapterTitle,
}) {
  final buffer = StringBuffer()..writeln('Chapter text: $chapterText');
  if (chapterTitle != null) {
    buffer.writeln('Chapter title: $chapterTitle');
  }
  buffer
    ..writeln('Create 8-12 questions.')
    ..writeln('Question types: olgusal, kavramsal, uygulamali.')
    ..writeln(
      'JSON format for each question: {"sorular": [{"soru": "...", "cevap": "...", "tip": "..."}]}',
    );
  return buffer.toString();
}
