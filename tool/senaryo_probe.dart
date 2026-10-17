// SCENARIO PROBE (development tool; NOT a gate test, evidence layer):
// Runs the pure core with REALISTIC usage scenarios and prints whether the
// promised behavior happens. Sits above the unit tests (scenario integrity)
// and below device acceptance (no UI/audio).
// Run: dart run tool/senaryo_probe.dart (make probe)
import 'dart:io';

import 'package:sesli_kitap/src/chapter_map.dart';
import 'package:sesli_kitap/src/pronunciation_rules.dart';
import 'package:sesli_kitap/src/review_scheduler.dart';
import 'package:sesli_kitap/src/study_questions.dart';

int passCount = 0;
int failCount = 0;

// The probe makes many positional calls; naming them would be behaviorless noise.
// ignore: avoid_positional_boolean_parameters
void check(String vaat, bool gercek, [String? detay]) {
  if (gercek) {
    passCount++;
    stdout.writeln('  OK   $vaat${detay == null ? '' : '  [$detay]'}');
  } else {
    failCount++;
    stdout.writeln('  FAIL $vaat${detay == null ? '' : '  [$detay]'}');
  }
}

void main() {
  stdout.writeln('=== SCENARIO 1: 30-page book -> chapter map ===');
  // Real book pattern: 4 untitled front-matter pages; the first page of a chapter has NO
  // running header (typical), later pages DO; the tail of the last chapter is untitled.
  final entries = <PageHeaderEntry>[
    for (var p = 1; p <= 4; p++) PageHeaderEntry(page: p),
    const PageHeaderEntry(page: 5), // first untitled page of chapter 1
    for (var p = 6; p <= 12; p++)
      PageHeaderEntry(page: p, header: 'Birinci Söz'),
    const PageHeaderEntry(page: 13), // start of chapter 2
    for (var p = 14; p <= 22; p++)
      PageHeaderEntry(page: p, header: 'İkinci Söz'),
    for (var p = 23; p <= 30; p++) PageHeaderEntry(page: p), // tail
  ];
  final map = buildChapterMap(entries);
  stdout.writeln(
    '  map: ${map.map((c) => '"${c.title}" ${c.startPage}-${c.endPage}').join(' | ')}',
  );
  check('3 units extracted (front matter + 2 chapters)', map.length == 3);
  // S1/K24: endPage is ASSERTED too (the old version only checked startPage and
  // let the drift through = vacuous check). Corrected contract: chapter 1's
  // untitled opening page (5) belongs to the chapter; front matter = 1-4.
  check(
    'front matter covers exactly 1-4 (chapter 1 starts at page 5)',
    map[0].title == null && map[0].startPage == 1 && map[0].endPage == 4,
    'actual: ${map[0].startPage}-${map[0].endPage}',
  );
  check(
    'chapter 1 takes the untitled opening page (5-12)',
    map[1].startPage == 5 && map[1].endPage == 12,
    'actual: ${map[1].startPage}-${map[1].endPage}',
  );
  check(
    'last chapter absorbs the untitled tail pages (22->30)',
    map[2].endPage == 30,
  );

  stdout.writeln('=== SCENARIO 3: pronunciation dictionary — real Turkish sentence ===');
  final kurallar = parsePronRules(
    '# kisisel sozluk\nİbn-i Sina=İbni Sina\nHû=Huu\nvesaire=\n',
  );
  const cumle =
      'İbn-i Sina, Hû diyerek vesaire anlattı; Hûr kelimesine dokunma.';
  final okunacak = applyPronRules(cumle, kurallar);
  stdout
    ..writeln('  input  : $cumle')
    ..writeln('  output : $okunacak');
  check('multi-word rule applied', okunacak.contains('İbni Sina'));
  check(
    'Hû -> Huu, Hûr kept (word boundary)',
    okunacak.contains('Huu diyerek') && okunacak.contains('Hûr'),
  );
  check('empty-replacement rule dropped the word', !okunacak.contains('vesaire'));
  final tag1 = pronRulesTag(kurallar);
  final tag2 = pronRulesTag(parsePronRules('İbn-i Sina=İbni Sina\n'));
  check(
    'changing a rule changes the audio-cache tag (stale mp3s)',
    tag1 != tag2 && tag1.isNotEmpty,
    'tag=$tag1/$tag2',
  );

  stdout.writeln('=== SCENARIO 5: question bank — 10 questions accepted / 7 rejected ===');
  String soru(int i, String tip) =>
      '{"soru": "Soru $i?", "cevap": "Cevap $i.", "tip": "$tip"}';
  final bank =
      '{"sorular": ['
      '${List.generate(8, (i) => soru(i, 'olgusal')).join(',')},'
      '${soru(8, 'kavramsal')},${soru(9, 'uygulamali')}]}';
  final sorular = parseQuestionsResponse(bank);
  check(
    '10 questions, three types',
    sorular.length == 10 && sorular.last.tip == QuestionKind.uygulamali,
  );
  var az = false;
  try {
    parseQuestionsResponse(
      '{"sorular": [${List.generate(7, (i) => soru(i, 'olgusal')).join(',')}]}',
    );
  } on QuestionsParseException {
    az = true;
  }
  check('7 questions REJECTED (8-12 limit)', az);

  stdout.writeln(
    '=== SCENARIO 6: 1-3-7 interval review — 30-day simulation ===',
  );
  // 5 questions are added on day 0; s1-s3 are always known, s4 is unknown on day 2, s5 is always unknown.
  var items = [for (var i = 1; i <= 5; i++) planNewItem('s$i', 0)];
  final gunlukDue = <int, List<String>>{};
  for (var gun = 1; gun <= 30; gun++) {
    final due = dueItems(items, gun);
    if (due.isNotEmpty) gunlukDue[gun] = due.map((e) => e.id).toList();
    for (final d in due) {
      final bilir = d.id != 's5' && !(d.id == 's4' && gun == 2);
      items = [
        for (final it in items)
          if (it.id == d.id) applyAnswer(it, knewIt: bilir, today: gun) else it,
      ];
    }
  }
  stdout.writeln('  due days: ${gunlukDue.keys.toList()}');
  check('first review on day 1 (5 questions)', gunlukDue[1]?.length == 5);
  check(
    'known items return on day 4 and day 11 (1->3->7)',
    (gunlukDue[4] ?? []).contains('s1') && (gunlukDue[11] ?? []).contains('s1'),
  );
  check(
    's1 RETIRED after day 11 (never returns)',
    !gunlukDue.entries.any((e) => e.key > 11 && e.value.contains('s1')),
  );
  check(
    'always-unknown s5 is re-queued every day (never retired)',
    (gunlukDue[20] ?? []).contains('s5') &&
        (gunlukDue[30] ?? []).contains('s5'),
  );

  // Session flow: full quiz chain with the day-1 due list.
  var s = ReviewSessionState.initial();
  var r = reviewTransition(s, const SessionStarted(['s1', 's2', 's3']));
  var komutSayisi = r.commands.length;
  s = r.state;
  for (var i = 0; i < 3; i++) {
    r = reviewTransition(s, const RevealRequested());
    komutSayisi += r.commands.length;
    s = r.state;
    r = reviewTransition(s, Marked(knewIt: i != 1));
    komutSayisi += r.commands.length;
    s = r.state;
  }
  check(
    '3-question session ends in done; counter 2 knew / 1 did not know',
    s.phase == ReviewPhase.done && s.knownCount == 2 && s.unknownCount == 1,
  );
  check(
    'command flow correct (3 SpeakQuestion + 3 SpeakAnswer = 6)',
    komutSayisi == 6,
    'commands=$komutSayisi',
  );

  stdout
    ..writeln()
    ..writeln('RESULT: $passCount OK / $failCount FAIL');
  if (failCount > 0) {
    throw StateError('scenario-probe has FAIL results');
  }
}
