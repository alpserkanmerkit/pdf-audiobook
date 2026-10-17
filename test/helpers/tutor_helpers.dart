// Oracle test helper (2026-10-06, private tutor Slice-2, G7a).
// Spec: internal design note §7.
//
// - FakeTutorLlm: recording fake LLM (matches the TutorLlm signature: `fake.call`).
//   It inspects the prompt text: if it contains 'STUDENT ANSWER:' it is a
//   grading call, otherwise it is a lesson request. The part number is read
//   from the prompt ('Part i/N').
// - buildTutorServices: like test_app.dart's buildTestServices (mock prefs +
//   temp dir + fake audio ops), but wired through the
//   AppServices.tutorLlmFactory seam.
// - pumpUntil: real file read/write (CacheStore) does not advance on
//   testWidgets' fake clock -> runAsync with zero-delay real turns + pump,
//   until the finder is found (bounded by a wall-clock timeout).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/io/cache_store.dart';
import 'package:sesli_kitap/io/llm_cleaner.dart';
import 'package:sesli_kitap/src/cache_keys.dart';
import 'package:sesli_kitap/src/chapter_cache.dart';
import 'package:sesli_kitap/src/chapter_map.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/src/tutor/tutor_session.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

class TutorCall {
  TutorCall(this.system, this.user);
  final String system;
  final String user;
  bool get isGrade => user.contains('STUDENT ANSWER:');
}

class TutorProviderDown implements Exception {
  TutorProviderDown(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Recording fake LLM.
/// - [holdNext]: if set, the next call waits until this Completer resolves.
/// - [failLessonWith] / [failGradeWith]: if set, the matching call throws it.
/// - [gradeJson]: grading response (default: correct).
/// - [questionsPerPart]: number of questions in a lesson response (1 or 2).
class FakeTutorLlm {
  final List<TutorCall> calls = [];
  Completer<void>? holdNext;
  Exception? failLessonWith;
  Exception? failGradeWith;
  String gradeJson =
      '{"sonuc":"dogru","aciklama":"Well done, you got the gist."}';
  int questionsPerPart = 1;

  List<TutorCall> get lessonCalls => calls.where((c) => !c.isGrade).toList();
  List<TutorCall> get gradeCalls => calls.where((c) => c.isGrade).toList();

  Future<String> call({required String system, required String user}) async {
    final c = TutorCall(system, user);
    calls.add(c);
    final hold = holdNext;
    if (hold != null) {
      holdNext = null;
      await hold.future;
    }
    if (c.isGrade) {
      final f = failGradeWith;
      if (f != null) throw f;
      return gradeJson;
    }
    final f = failLessonWith;
    if (f != null) throw f;
    final m = RegExp(r'Part (\d+)/(\d+)').firstMatch(user);
    final no = m?.group(1) ?? '?';
    final sorular = [
      for (var q = 1; q <= questionsPerPart; q++)
        {'soru': 'Question $q part $no?', 'beklenen': 'Expected $q'},
    ];
    return jsonEncode({'anlatim': 'Explanation part $no.', 'sorular': sorular});
  }
}

const Book tutorBook = Book(
  id: 'tb1',
  title: 'Penman FSA',
  author: 'S. Penman',
  chapterLabel: 'Chapter 5',
  progressPercent: 0,
  totalPages: 760,
  coverIndex: 0,
  hash: 'th1',
);

/// Small 3-page chapter -> splitChapterIntoLessons produces 3 parts (one page
/// each: 10, 11, 12).
const Chapter tutorChapter = Chapter(
  title: 'Pricing Book Values',
  startPage: 10,
  endPage: 12,
);

const Map<int, String> tutorPageTexts = {
  10: 'Residual earnings are earnings in excess of a required return.',
  11: 'Book value plus the present value of expected residual earnings.',
  12: 'Growth in residual earnings drives the continuing value.',
};

/// AppServices + tutorLlmFactory seam. If [withBook] is true, writes
/// [tutorBook] to books_v1; if [chapters] is given, writes them under the
/// `chapters_<hash>` key.
Future<AppServices> buildTutorServices({
  TutorLlm? llm,
  bool withBook = true,
  List<Chapter>? chapters = const [tutorChapter],
  String? geminiKey,
}) async {
  final values = <String, Object>{
    if (withBook) 'books_v1': encodeBooks(const [tutorBook]),
    if (withBook && chapters != null)
      'chapters_${tutorBook.hash}': encodeChapters(chapters),
    'geminiKey': ?geminiKey,
  };
  SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  final dir = Directory.systemTemp.createTempSync('sesli_kitap_tutor_');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // temp dir cleanup is best-effort; it must not fail the test
    }
  });
  final services = AppServices(
    prefs: prefs,
    dataDir: dir,
    playerOpsFactory: RecordingAudioOps.new,
    tutorLlmFactory: llm == null ? null : () => llm,
  );
  services.reading.load();
  return services;
}

/// Writes [tutorPageTexts] (or [texts]) to the cache as clean text.
/// Real file read/write -> the caller must call it inside tester.runAsync.
Future<void> seedTutorPages(
  AppServices services, [
  Map<int, String> texts = tutorPageTexts,
]) async {
  for (final e in texts.entries) {
    await services.cache.writeText(
      textCacheKey(
        bookHash: tutorBook.hash,
        pageNo: e.key,
        cleanPromptVersion: cleanPromptVersion,
      ),
      TextEntry(
        raw: e.value,
        clean: e.value,
        promptVersion: cleanPromptVersion,
        suspicious: false,
      ),
    );
  }
}

/// Lets real time pass until [finder] is found (at most [timeout] of REAL time
/// or [maxRounds] rounds). If it is never found, it returns silently; the real
/// assertion is the caller's expect.
///
/// Each round gives the event loop one zero-delay real turn. The number of
/// read/write completions depends on the number of turns, not on time (measured:
/// the same 15 turns; a 5 ms sleep was pure idle waste). The timeout is bounded
/// by wall-clock time rather than turn count, so that a slow machine keeps the
/// old ~2 s+ budget.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maxRounds = 100000,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final clock = Stopwatch()..start();
  for (var i = 0; i < maxRounds && finder.evaluate().isEmpty; i++) {
    if (clock.elapsed > timeout) break;
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

/// Whether the button is enabled (ButtonStyleButton or IconButton).
bool isEnabled(WidgetTester tester, Finder button) {
  final w = tester.widget(
    find
        .descendant(
          of: button,
          matching: find.byWidgetPredicate(
            (w) => w is ButtonStyleButton || w is IconButton,
          ),
          matchRoot: true,
        )
        .first,
  );
  if (w is ButtonStyleButton) return w.onPressed != null;
  return (w as IconButton).onPressed != null;
}
