import 'package:sesli_kitap/src/tutor/lesson_split.dart';
import 'package:sesli_kitap/src/tutor/tutor_prompts.dart';

typedef TutorLlm =
    Future<String> Function({required String system, required String user});

class TutorProviderException implements Exception {
  TutorProviderException(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

class TutorInputException implements Exception {
  TutorInputException(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

class TutorStaleStepException implements Exception {
  TutorStaleStepException(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

class TutorSession {
  TutorSession({
    required List<LessonPart> parts,
    required TutorLlm llm,
    required String bookTitle,
    required String chapterTitle,
    int startIndex = 0,
  }) : _parts = parts,
       _llm = llm,
       _bookTitle = bookTitle,
       _chapterTitle = chapterTitle,
       _currentIndex = startIndex {
    if (parts.isEmpty) {
      throw ArgumentError('parts must not be empty.');
    }
    // Resume where left off (SPEC §7.7): the starting part must be valid.
    RangeError.checkValidIndex(startIndex, parts, 'startIndex');
  }

  final List<LessonPart> _parts;
  final TutorLlm _llm;
  final String _bookTitle;
  final String _chapterTitle;

  int _currentIndex;
  LessonStep? _currentStep;
  final Map<int, GradeResult> _grades = {};
  int _pendingAnswers = 0;
  int _pendingLoads = 0;

  List<LessonPart> get parts => _parts;
  int get currentIndex => _currentIndex;
  bool get isFinished => _currentIndex >= _parts.length;

  LessonPart get currentPart {
    if (isFinished) {
      throw StateError('Session has finished.');
    }
    return _parts[_currentIndex];
  }

  LessonStep? get currentStep => _currentStep;
  Map<int, GradeResult> get grades => Map.unmodifiable(_grades);

  Future<LessonStep> loadCurrentPart() async {
    if (isFinished) {
      throw StateError('Session has finished.');
    }

    final String raw;
    _pendingLoads++;
    try {
      raw = await _llm(
        system: kTutorSystemPrompt,
        user: buildLessonPrompt(
          part: currentPart,
          totalParts: _parts.length,
          bookTitle: _bookTitle,
          chapterTitle: _chapterTitle,
        ),
      );
    } on Exception catch (e) {
      throw TutorProviderException(e.toString());
    } finally {
      _pendingLoads--;
    }

    final step = parseLessonResponse(raw);
    _currentStep = step;
    _grades.clear();
    return step;
  }

  Future<GradeResult> answer(int questionIndex, String userAnswer) async {
    final step = _currentStep;
    if (step == null) {
      throw StateError('The part must be loaded first.');
    }
    if (questionIndex < 0 || questionIndex >= step.sorular.length) {
      throw RangeError.index(questionIndex, step.sorular, 'questionIndex');
    }
    final trimmed = userAnswer.trim();
    if (trimmed.isEmpty) {
      throw TutorInputException('Answer must not be empty.');
    }

    _pendingAnswers++;
    try {
      final String raw;
      try {
        raw = await _llm(
          system: kTutorSystemPrompt,
          user: buildGradePrompt(
            part: currentPart,
            question: step.sorular[questionIndex],
            userAnswer: trimmed,
          ),
        );
      } on Exception catch (e) {
        throw TutorProviderException(e.toString());
      }

      final grade = parseGradeResponse(raw);
      if (_currentStep != step) {
        throw TutorStaleStepException(
          'The lesson step changed; this answer was not graded.',
        );
      }
      _grades[questionIndex] = grade;
      return grade;
    } finally {
      _pendingAnswers--;
    }
  }

  void nextPart() {
    final step = _currentStep;
    if (step == null) {
      throw StateError('Step not loaded.');
    }
    if (_pendingLoads > 0) {
      throw TutorInputException(
        'The lesson part is still loading; the next part cannot be opened until loading finishes.',
      );
    }
    if (_pendingAnswers > 0) {
      throw TutorInputException(
        'Your answer is still being graded; the next part cannot be opened before the result arrives.',
      );
    }
    for (var i = 0; i < step.sorular.length; i++) {
      if (!_grades.containsKey(i)) {
        throw StateError('Not all questions have been answered.');
      }
    }
    _currentIndex++;
    _currentStep = null;
    _grades.clear();
  }
}
