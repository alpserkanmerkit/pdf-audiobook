// PURE layer (gate-tested): prompt building + JSON contract parsing for LLM
// 4-option quiz generation. HTTP transport lives in lib/io/llm_quiz.dart (same
// split as question_bank / llm_skeleton). The MultipleChoiceQuestion contract
// (exactly 4 options + dogruIndex 0..3) is validated in quiz_choice_machine.dart.
import 'dart:convert';

import 'package:sesli_kitap/src/quiz_choice_machine.dart';

class QuizParseException implements Exception {
  QuizParseException(this.reason);
  final String reason;

  @override
  String toString() => 'QuizParseException: $reason';
}

/// LLM user prompt asking for [count] four-option questions from the book text.
/// Very long text is cut to 8000 characters (a token/cost cap).
String buildQuizPrompt({required String bookText, required int count}) {
  final capped = bookText.length > 8000
      ? bookText.substring(0, 8000)
      : bookText;
  return 'Generate exactly $count four-option multiple-choice questions from '
      'the text below. Each question MUST rely ONLY on information in the text; '
      'do not ask about anything not in the text. Return ONLY this JSON schema, '
      'write nothing else:\n'
      '{"questions":[{"soru":"question text","secenekler":["A","B","C","D"],"dogruIndex":0}]}\n'
      'Rules: each question must have EXACTLY 4 options; "dogruIndex" is the '
      'index of the correct option (0..3); questions and options must be in Turkish.\n\n'
      'TEXT:\n$capped';
}

/// Converts the LLM response body (JSON) into a [MultipleChoiceQuestion] list.
/// [kaynak] is the source label assigned to each question (e.g. the book
/// title). On a contract violation (invalid JSON, a missing field, a wrong
/// number of options, or a dogruIndex outside the range) it throws
/// [QuizParseException].
List<MultipleChoiceQuestion> parseQuizResponse(
  String content, {
  required String kaynak,
}) {
  final Object? data;
  try {
    data = jsonDecode(content);
  } on FormatException catch (e) {
    throw QuizParseException('invalid JSON body: $e');
  }
  if (data is! Map) {
    throw QuizParseException('root value is not an object');
  }
  final rawList = data['questions'];
  if (rawList is! List || rawList.isEmpty) {
    throw QuizParseException('questions field is empty or not a list');
  }
  final out = <MultipleChoiceQuestion>[];
  for (final item in rawList) {
    if (item is! Map) {
      throw QuizParseException('question item is not an object');
    }
    final soru = item['soru'];
    if (soru is! String || soru.trim().isEmpty) {
      throw QuizParseException('question text is invalid');
    }
    final secenekler = item['secenekler'];
    if (secenekler is! List || secenekler.length != 4) {
      throw QuizParseException('secenekler must have exactly 4 items');
    }
    final opts = [for (final s in secenekler) s.toString()];
    final dogruIndex = item['dogruIndex'];
    if (dogruIndex is! int || dogruIndex < 0 || dogruIndex > 3) {
      throw QuizParseException('dogruIndex must be in range 0..3');
    }
    out.add(
      MultipleChoiceQuestion(
        soru: soru.trim(),
        secenekler: opts,
        dogruIndex: dogruIndex,
        kaynak: kaynak,
      ),
    );
  }
  return out;
}
