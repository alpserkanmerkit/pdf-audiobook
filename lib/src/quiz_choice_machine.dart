// lib/src/quiz_choice_machine.dart

class MultipleChoiceQuestion {
  // K25: 'exactly 4 options' used to be only an assert (stripped in release;
  // the UI assumes a fixed 4 via List.generate(4)). Runtime check: in release
  // mode too it is an ArgumentError -- a contract violation cannot pass silently.
  MultipleChoiceQuestion({
    required this.soru,
    required this.secenekler,
    required this.dogruIndex,
    required this.kaynak,
  }) {
    if (secenekler.length != 4) {
      throw ArgumentError.value(
        secenekler.length,
        'secenekler',
        'exactly 4 options required',
      );
    }
    if (dogruIndex < 0 || dogruIndex > 3) {
      throw ArgumentError.value(
        dogruIndex,
        'dogruIndex',
        'must be in range 0..3',
      );
    }
  }
  final String soru;
  final List<String> secenekler;
  final int dogruIndex;
  final String kaynak;
}

class QuizChoiceState {
  const QuizChoiceState({
    required this.sorular,
    required this.qIndex,
    required this.dogrular,
    this.secilen,
    this.tamamlandi = false,
  });

  factory QuizChoiceState.initial(List<MultipleChoiceQuestion> s) =>
      QuizChoiceState(
        sorular: s,
        qIndex: 0,
        dogrular: List<bool?>.filled(s.length, null),
      );
  final List<MultipleChoiceQuestion> sorular;
  final int qIndex;
  final int? secilen;

  /// Correctness per question (in question order; null = not answered yet).
  /// The review bank wiring (quiz_review_bridge) converts this into applyAnswer calls.
  final List<bool?> dogrular;

  /// Becomes true when the last question is answered and Next is pressed -- the
  /// flow is NOT circular; the UI shows the completion panel, and the results are
  /// written to the review bank.
  final bool tamamlandi;

  bool get yanitlandi => secilen != null;

  MultipleChoiceQuestion? get gecerliSoru =>
      sorular.isEmpty ? null : sorular[qIndex];

  String get ilerlemeEtiketi =>
      sorular.isEmpty ? '0 / 0' : '${qIndex + 1} / ${sorular.length}';

  int get dogruSayisi => dogrular.where((d) => d ?? false).length;
}

sealed class QuizChoiceEvent {
  const QuizChoiceEvent();
}

class ChoiceSelected extends QuizChoiceEvent {
  const ChoiceSelected(this.index);
  final int index;
}

class NextRequested extends QuizChoiceEvent {
  const NextRequested();
}

QuizChoiceState quizChoiceTransition(QuizChoiceState s, QuizChoiceEvent e) {
  if (s.sorular.isEmpty) return s;
  if (s.tamamlandi) return s; // finished: the event is swallowed (no-op)
  switch (e) {
    case ChoiceSelected():
      if (s.yanitlandi) return s;
      if (e.index < 0 || e.index > 3) return s;
      final yeniDogrular = List<bool?>.of(s.dogrular);
      yeniDogrular[s.qIndex] = e.index == s.sorular[s.qIndex].dogruIndex;
      return QuizChoiceState(
        sorular: s.sorular,
        qIndex: s.qIndex,
        secilen: e.index,
        dogrular: yeniDogrular,
      );
    case NextRequested():
      if (!s.yanitlandi) return s;
      // If the last question was answered, it is NOT circular -> finished.
      if (s.qIndex >= s.sorular.length - 1) {
        return QuizChoiceState(
          sorular: s.sorular,
          qIndex: s.qIndex,
          secilen: s.secilen,
          dogrular: s.dogrular,
          tamamlandi: true,
        );
      }
      return QuizChoiceState(
        sorular: s.sorular,
        qIndex: s.qIndex + 1,
        dogrular: s.dogrular,
      );
  }
}

List<MultipleChoiceQuestion> seedQuizQuestions() => [
  MultipleChoiceQuestion(
    soru: 'Yazara göre boşluk (negatif mekân) neyi temsil eder?',
    secenekler: [
      'Bir eksikliği',
      'Başlı başına bir tasarım malzemesini',
      'Yapısal bir zaafı',
      'Geçici bir çözümü',
    ],
    dogruIndex: 1,
    kaynak: 's. 42',
  ),
  MultipleChoiceQuestion(
    soru: '"Ma" kavramı hangi geleneğin estetiğinden gelir?',
    secenekler: [
      'İskandinav tasarımı',
      'Japon estetiği',
      'Akdeniz mimarisi',
      'Antik Yunan',
    ],
    dogruIndex: 1,
    kaynak: 's. 71',
  ),
  MultipleChoiceQuestion(
    soru: 'Dördüncü bölümün ana savı aşağıdakilerden hangisidir?',
    secenekler: [
      'Form, işlevi izler',
      'Boşluk da bir malzemedir',
      'Işık her şeyi belirler',
      'Ölçek her zaman görecelidir',
    ],
    dogruIndex: 1,
    kaynak: 's. 78',
  ),
];
