// FOUNDATION LAYER (A) -- Accessibility. No ICAT in this file; the standard set is used.
//
// SOURCE 1: Flutter official "Accessibility testing" > "Testing accessibility on
//   mobile" section -- Flutter Accessibility Guideline API
//   https://docs.flutter.dev/ui/accessibility/accessibility-testing
//   (old/redirected address: docs.flutter.dev/ui/accessibility-and-localization/
//   accessibility-testing). The four items in the doc, verbatim:
//     * androidTapTargetGuideline  -- tappable nodes are at least 48x48
//     * iOSTapTargetGuideline      -- 44x44; THIS APP TARGETS ANDROID/WINDOWS
//                                     (no ios/ directory) -> deliberately SKIPPED
//     * labeledTapTargetGuideline  -- nodes with tap/long-press actions are labeled
//     * textContrastGuideline      -- text contrast (WCAG 2.x: normal text
//                                     4.5:1, large text 3:1)
//   Skeleton from the doc: `final handle = tester.ensureSemantics(); pumpWidget;
//   await expectLater(tester, meetsGuideline(...)); handle.dispose();`
// SOURCE 2: flutter_test API -- AccessibilityGuideline / meetsGuideline
//   https://api.flutter.dev/flutter/flutter_test/meetsGuideline.html
//   https://api.flutter.dev/flutter/flutter_test/AccessibilityGuideline-class.html
//
// CONFLICT ANALYSIS (with existing tests):
//   * test/ui_accessibility_test.dart: S5 text scale, R6 dyslexia font, K18
//     "surface2 cannot be a text color" (palette-token claim), K17 Turkish uppercase.
//     Does NOT use meetsGuideline; checks contrast at token level (static).
//     Here: RENDERED pixel contrast + tap target + label -> NEW.
//   * test/reader_overflow_test.dart: only RenderFlex OVERFLOW (320/360/393 px,
//     scale 1.3). Does not look at the semantic tree / target size / labels -> NEW.
//   * grep: `meetsGuideline|ensureSemantics` under test/ gave 0 results (before this
//     file) -> the Guideline API is used here for the first time.
//
// RATCHET (test-writing principles §5 logic): existing accessibility debt is NOT
// hidden and the test is NOT loosened or skipped. The [knownViolations] map holds
// "screen|rule" -> (known violation COUNT, reason, date):
//   * a screen|rule NOT in the map with a violation = RED (new violation),
//   * for a map entry, if the violation count INCREASES = RED (new violation added),
//   * if the count DECREASES or becomes 0 = RED (improvement -> update/delete the
//     entry; "strict xfail", same logic as lesson 2 of test-writing principles §10).
// Violation count = number of "SemanticsNode#" in Evaluation.reason (1 node per violation).
// Limit: if one violation in the same screen|rule is fixed and a new one is added,
// the count stays the same (swap) -- node labels are listed in the reason text for review.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/ui/screens/reader_screen.dart';
import 'package:sesli_kitap/ui/screens/tutor_screen.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';

import '../helpers/test_app.dart';
import '../helpers/tutor_helpers.dart';

/// Known (existing) accessibility debt: screen|rule -> record.
class KnownViolation {
  const KnownViolation(this.count, this.reason);

  /// The violation count currently expected for this screen|rule.
  final int count;

  /// Reason + date + recommended fix.
  final String reason;
}

const Map<String, KnownViolation> knownViolations = <String, KnownViolation>{
  'okuyucu-icerikli|textContrast': KnownViolation(
    1,
    '2026-10-07: reading sentence (17px) 4.32:1 -- sentence text color is below 4.5:1; '
    'design-token decision (reading surface).',
  ),
};

/// Known OVERFLOW debt: screen -> (overflowing file names, reason). A RenderFlex
/// overflow at 360dp is not an accessibility rule, BUT because this file's screens are
/// built at 360dp it is measured as a side effect (reader_overflow_test.dart only
/// measures the reader at 320/360/393; the other screens were NOT measured before).
class KnownOverflow {
  // ignore: unreachable_from_main -- ratchet is empty; a new overflow record uses this shape
  const KnownOverflow(this.files, this.reason);
  final Set<String> files;
  final String reason;
}

/// Empty: NO known overflows. The "4.7 px" entry in the report was an Ahem font artifact
/// (no overflow with the real font at 360x640 x1.0); the real overflows (320 dp, x1.5)
/// were fixed and the entry was deleted. New overflow = RED. Narrow surface + text scale
/// scan: test/zz_dar_ekran_test.dart (with real fonts).
const Map<String, KnownOverflow> knownOverflows = <String, KnownOverflow>{};

typedef _Rule = ({String ad, AccessibilityGuideline guideline});

final List<_Rule> _rules = <_Rule>[
  (ad: 'androidTapTarget48dp', guideline: androidTapTargetGuideline),
  (ad: 'labeledTapTarget', guideline: labeledTapTargetGuideline),
  (ad: 'textContrast', guideline: textContrastGuideline),
];

const _book = Book(
  id: 'a11y-1',
  title: 'Rüyaların Yorumu',
  author: 'Sigmund Freud',
  chapterLabel: 'Chapter 1',
  progressPercent: 10,
  totalPages: 100,
  coverIndex: 0,
  hash: 'a11yhash00000001',
);

/// Phone size (360x800 logical px, dpr 1.0): the default 800x600 desktop surface
/// hides narrow-screen target-size problems.
void _phoneSurface(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(360, 800);
  addTearDown(tester.view.reset);
}

Future<void> _pumpApp(WidgetTester tester) async {
  final services = await buildTestServices(
    prefsValues: {
      'books_v1': encodeBooks([_book]),
    },
  );
  await tester.pumpWidget(buildTestAppFromServices(services));
  await tester.pumpAndSettle();
}

Future<void> _tapAndSettle(WidgetTester tester, Finder f) async {
  expect(f, findsOneWidget, reason: 'the element to tap must be on screen');
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Screen name -> the setup that reaches that screen. All enter from the composition root
/// (SesliKitapApp); navigation is done with the user's real taps.
final Map<String, Future<void> Function(WidgetTester)>
_screens = <String, Future<void> Function(WidgetTester)>{
  'kutuphane': (t) async {
    await _pumpApp(t);
    expect(find.text('Your library'), findsOneWidget);
  },
  'kitap-ekle': (t) async {
    await _pumpApp(t);
    await _tapAndSettle(t, find.text('Add book'));
    expect(find.text('Choose file'), findsOneWidget);
  },
  'okuyucu-bos': (t) async {
    await _pumpApp(t);
    await _tapAndSettle(t, find.text('Reader'));
  },
  'okuyucu-icerikli': (t) async {
    final services = await buildTestServices();
    final settings = AppSettings();
    await t.pumpWidget(
      AppServicesScope(
        services: services,
        child: AppSettingsScope(
          settings: settings,
          child: MaterialApp(
            theme: buildAppTheme(settings),
            home: const Scaffold(
              body: ReaderScreen(
                sentences: [
                  'Rüya olağanüstü bir şiir, tam yerini bulan bir alegori.',
                  'Büyülenenler o saçma rüyaları gözden mi kaçırdılar?',
                ],
                book: _book,
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump();
  },
  'ozel-ders': (t) async {
    await _pumpApp(t);
    await _tapAndSettle(t, find.byKey(const Key('library-open-tutor')));
    expect(find.byType(TutorScreen), findsOneWidget);
  },
  'ozel-ders-parca': (t) async {
    // Tutor part phase (explanation + question + answer field + submit): book ->
    // chapter -> part; a fake LLM, with the page text seeded into the cache.
    final services = await buildTutorServices(llm: FakeTutorLlm().call);
    await t.runAsync(() => seedTutorPages(services));
    await t.pumpWidget(buildTestAppFromServices(services));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('library-open-tutor')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key('tutor-book-${tutorBook.id}')));
    await pumpUntil(t, find.byKey(const Key('tutor-chapter-0')));
    await t.tap(find.byKey(const Key('tutor-chapter-0')));
    await pumpUntil(t, find.byKey(const Key('tutor-part')));
    expect(find.byKey(const Key('tutor-part')), findsOneWidget);
  },
  'tartisma-odasi': (t) async {
    await _pumpApp(t);
    await _tapAndSettle(t, find.text('Discussion'));
  },
  'ayarlar': (t) async {
    await _pumpApp(t);
    await _tapAndSettle(t, find.byIcon(Icons.tune));
  },
  'rapor': (t) async {
    await _pumpApp(t);
    await _tapAndSettle(t, find.text('Report'));
  },
  'quiz': (t) async {
    await _pumpApp(t);
    await _tapAndSettle(t, find.text('Quiz'));
  },
};

/// Runs [setup]; swallows the RenderFlex overflow errors raised during it and returns
/// the names of the overflowing source files (other errors follow the normal flow).
/// This way one screen's overflow does not turn that screen's accessibility rule tests
/// red for another reason; overflow is measured in the separate "overflow" test.
Future<Set<String>> _capturingOverflows(Future<void> Function() setup) async {
  final files = <String>{};
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.toString();
    if (text.contains('overflowed by')) {
      final m = RegExp(r'/([A-Za-z0-9_]+\.dart):\d+').firstMatch(text);
      files.add(m?.group(1) ?? '?');
      return;
    }
    previous?.call(details);
  };
  try {
    await setup();
  } finally {
    FlutterError.onError = previous;
  }
  return files;
}

/// Violation count = number of "SemanticsNode#" in Evaluation.reason (Flutter starts each
/// violation with `node: ...`; one violation can span several lines).
int _count(String? reason) => 'SemanticsNode#'.allMatches(reason ?? '').length;

/// Ratchet verdict: empty string = pass; otherwise the red reason.
String _verdict(String key, Evaluation e) {
  final known = knownViolations[key];
  final n = e.passed ? 0 : _count(e.reason);
  if (known == null) {
    return n == 0 ? '' : 'NEW violation ($n): $key\n${e.reason}';
  }
  if (n == known.count) return '';
  return 'known violation count changed ($key): expected ${known.count}, '
      'found $n -- ${n < known.count ? "IMPROVEMENT: update/delete the knownViolations entry" : "NEW violation added"}\n${e.reason ?? ""}';
}

void main() {
  test(
    'knownViolations entries are meaningful (reason+date, count>0) and tied to a known '
    'screen/rule key',
    () {
      for (final e in knownViolations.entries) {
        final parts = e.key.split('|');
        expect(parts, hasLength(2), reason: '${e.key}: "screen|rule" format');
        expect(_screens.keys, contains(parts[0]), reason: e.key);
        expect(_rules.map((r) => r.ad), contains(parts[1]), reason: e.key);
        expect(e.value.count, greaterThan(0), reason: e.key);
        expect(
          e.value.reason,
          matches(RegExp(r'\d{4}-\d{2}-\d{2}')),
          reason: '${e.key}: the reason must contain a date (YYYY-MM-DD)',
        );
      }
    },
  );

  for (final screen in _screens.entries) {
    for (final rule in _rules) {
      testWidgets('${screen.key} / ${rule.ad}', (tester) async {
        final handle = tester.ensureSemantics();
        _phoneSurface(tester);
        await _capturingOverflows(() => screen.value(tester));
        // Not an empty set green: the semantic tree has real content.
        expect(
          find.byType(Semantics),
          findsWidgets,
          reason: 'the screen must produce semantic nodes',
        );
        final result = await rule.guideline.evaluate(tester);
        expect(
          _verdict('${screen.key}|${rule.ad}', result),
          isEmpty,
          reason: '${screen.key} / ${rule.ad}',
        );
        handle.dispose();
      });
    }
  }

  for (final screen in _screens.entries) {
    testWidgets('${screen.key} / no-overflow-360dp', (tester) async {
      _phoneSurface(tester);
      final files = await _capturingOverflows(() => screen.value(tester));
      final known = knownOverflows[screen.key];
      expect(
        files,
        known?.files ?? <String>{},
        reason:
            '${screen.key}: RenderFlex overflow at 360dp '
            '${known == null ? "(NEW)" : "(known: ${known.reason})"}',
      );
    });
  }
}
