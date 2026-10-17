// DEMO mode FAKE LLM router: recognizes a chat request (system + user message)
// by the app's known prompts and returns the pre-written answer
// (lib/demo/demo_content.dart) in the JSON/plain-text contract the app expects.
// There is NO model call.
//
// Matching: equality for the public constants (kTutorSystemPrompt,
// reviewerPrompt); for private prompts a distinctive sentence (`contains`). A
// request that does not match returns null and is recorded in [unrouted]
// (tests expect it to stay empty).
import 'dart:convert';

import 'package:sesli_kitap/demo/demo_api_server.dart';
import 'package:sesli_kitap/demo/demo_content.dart';
import 'package:sesli_kitap/src/discussion/discussion_review.dart'
    show reviewerPrompt;
import 'package:sesli_kitap/src/tutor/tutor_prompts.dart'
    show kTutorSystemPrompt;

class DemoLlmRouter {
  /// System prompt summaries of the unrouted requests.
  final List<String> unrouted = <String>[];

  int _continuationCalls = 0;
  int _quizCalls = 0;

  /// The `message.content` value for [request]; null if not recognized.
  String? respond(RecordedRequest request) {
    final String system;
    final String user;
    try {
      system = request.systemMessage;
      user = request.userMessage;
    } on Object {
      return _miss('unreadable request body');
    }
    return route(system, user) ?? _miss(system);
  }

  /// Pure matching (state: only the continuation/quiz counters). null if not recognized.
  String? route(String system, String user) {
    if (system == kTutorSystemPrompt) return _tutor(user);
    if (system == reviewerPrompt) {
      return jsonEncode({'ok': true, 'corrections': <Object>[]});
    }
    if (system.contains('is the cleaning faithful to the original')) {
      return jsonEncode({'sadik': true});
    }
    if (system.contains(
      'You will be given the raw text of a scanned Turkish book page',
    )) {
      return jsonEncode({'metin': user});
    }
    if (system.contains("extract the book's REAL chapter skeleton")) {
      return _skeleton(user);
    }
    if (system.contains('You write a voice discussion script')) {
      return _script(kDemoOpening);
    }
    if (system.contains('FROM WHERE IT LEFT OFF')) {
      final batch =
          kDemoContinuations[_continuationCalls++ % kDemoContinuations.length];
      return _script(batch);
    }
    if (system.contains('When a question arrives from the listener')) {
      return _answer(user);
    }
    if (system.contains('You are a reading assistant')) {
      return _explanation(user);
    }
    if (system.contains('You are a student assistant')) return _weekly(user);
    if (user.contains('"dogruIndex"')) return _quiz(user);
    if (user.contains('"sorular"')) return _studyQuestions();
    return null;
  }

  String? _miss(String what) {
    unrouted.add(what.length > 80 ? what.substring(0, 80) : what);
    return null;
  }

  // --- Discussion ----------------------------------------------------------

  String _script(List<DemoLine> lines) =>
      lines.map((l) => '${l.$1}: ${l.$2}').join('\n');

  String _answer(String user) {
    final m = RegExp('LISTENER QUESTION: (.*)').firstMatch(user);
    var q = (m?.group(1) ?? 'soru').trim();
    if (q.length > 120) q = '${q.substring(0, 120)}...';
    q = q.replaceAll('"', "'");
    return _script([
      for (final l in kDemoAnswer) (l.$1, l.$2.replaceAll('{SORU}', q)),
    ]);
  }

  // --- Chapter map ---------------------------------------------------------

  String _skeleton(String user) {
    final pages = RegExp(
      r'^s(\d+):',
      multiLine: true,
    ).allMatches(user).map((m) => int.parse(m.group(1)!));
    final total = pages.isEmpty ? 1 : pages.reduce((a, b) => a > b ? a : b);
    if (total >= 21) {
      return jsonEncode({
        'chapters': [
          {'title': 'Kaşağı', 'startPage': 1, 'endPage': 7},
          {'title': 'Forsa', 'startPage': 8, 'endPage': 14},
          {'title': 'Primo Türk Çocuğu', 'startPage': 15, 'endPage': 21},
        ],
      });
    }
    return jsonEncode({
      'chapters': [
        {'title': 'Chapter 1', 'startPage': 1, 'endPage': total},
      ],
    });
  }

  // --- Quiz / question bank ------------------------------------------------

  String _quiz(String user) {
    final count =
        int.tryParse(
          RegExp(r'exactly (\d+) ').firstMatch(user)?.group(1) ?? '',
        ) ??
        5;
    final start = (_quizCalls++ * count) % kDemoQuiz.length;
    return jsonEncode({
      'questions': [
        for (var i = 0; i < count; i++)
          {
            'soru': kDemoQuiz[(start + i) % kDemoQuiz.length].$1,
            'secenekler': kDemoQuiz[(start + i) % kDemoQuiz.length].$2,
            'dogruIndex': kDemoQuiz[(start + i) % kDemoQuiz.length].$3,
          },
      ],
    });
  }

  String _studyQuestions() => jsonEncode({
    'sorular': [
      for (final q in kDemoStudyQuestions)
        {'soru': q.$1, 'cevap': q.$2, 'tip': q.$3},
    ],
  });

  // --- Ask (explanation) ---------------------------------------------------

  String _explanation(String user) {
    final word = RegExp('the word "([^"]+)"').firstMatch(user);
    const note =
        ' (Demo: this explanation was written in advance; no AI model was called.)';
    if (word == null) {
      return jsonEncode({
        'aciklama':
            'This sentence briefly describes an event in the story: you can work out '
            'what happened and who did what from the context.$note',
      });
    }
    final target = word.group(1)!;
    final known = kDemoWords[_lower(target)];
    return jsonEncode(
      {
        'aciklama':
            known ??
            '"$target" is part of the event described in this sentence; you can '
                'work out its meaning from the surrounding sentences.',
      }..update('aciklama', (v) => '$v$note'),
    );
  }

  // --- Private tutoring ----------------------------------------------------

  String _tutor(String user) {
    if (user.contains('STUDENT ANSWER:')) return _grade(user);
    final chapter = RegExp('Chapter: (.*)').firstMatch(user)?.group(1)?.trim();
    final lessons = kDemoLessons[chapter] ?? kDemoLessons.values.first;
    final no =
        int.tryParse(RegExp(r'Part (\d+)/').firstMatch(user)?.group(1) ?? '') ??
        1;
    final l = lessons[(no - 1) % lessons.length];
    return jsonEncode({
      'anlatim': l.$1,
      'sorular': [
        {'soru': l.$2, 'beklenen': l.$3},
      ],
    });
  }

  String _grade(String user) {
    final m = RegExp(
      r'EXPECTED ANSWER:\n(.*?)\n\nSTUDENT ANSWER:\n(.*)$',
      dotAll: true,
    ).firstMatch(user);
    final expected = _stems(m?.group(1) ?? '');
    final answer = _stems(m?.group(2) ?? '');
    final hit = expected.where(answer.contains).length;
    final ratio = expected.isEmpty ? 0.0 : hit / expected.length;
    final String verdict;
    final String note;
    if (ratio >= 0.5) {
      verdict = 'dogru';
      note = 'Well done, you captured the essence of the expected answer.';
    } else if (ratio > 0) {
      verdict = 'yarim';
      note =
          'You are on the right track, but an important part is missing; read the passage once more.';
    } else {
      verdict = 'yanlis';
      note =
          'This answer does not match the passage; review the explanation again.';
    }
    return jsonEncode({
      'sonuc': verdict,
      'aciklama': '$note (Demo evaluation: based on keyword matching.)',
    });
  }

  /// First 4 letters of words with 4+ letters (tolerant of Turkish suffix changes).
  Set<String> _stems(String text) => RegExp(
    '[a-zçğıöşüâîû]{4,}',
  ).allMatches(_lower(text)).map((m) => m.group(0)!.substring(0, 4)).toSet();

  String _lower(String s) =>
      s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

  // --- Weekly report -------------------------------------------------------

  String _weekly(String user) {
    int n(String label) =>
        int.tryParse(
          RegExp('$label (\\d+)').firstMatch(user)?.group(1) ?? '',
        ) ??
        0;
    final toplam = n('Total');
    final hakim = n('Mastered');
    final devam = n('In progress');
    final geciken = n('Overdue');
    return jsonEncode({
      'mektup':
          'Dear reader, you have $toplam cards in your review bank this week: you have mastered $hakim of them, '
          '$devam are in progress, and $geciken are overdue. '
          'Small but steady steps make the most solid learning; set aside '
          'ten minutes this week for the overdue cards. (Demo: this letter was written in advance.)',
    });
  }
}
