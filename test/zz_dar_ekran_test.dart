// FOUNDATION LAYER -- narrow-screen OVERFLOW scan (permanent regression).
//
// Why: project report section 9 says "Rapor 360 dp overflow STILL EXISTS";
// erisilebilirlik_test.dart measures only at 360x800 and text scale 1.0, and it
// accepts the known overflow via a RATCHET. Here ALL screens are drawn on narrow
// phone surfaces (320x568 and 360x640 logical px, dpr 1.0) and at text scales
// (1.0 and 1.5 = the LARGEST text size in the app's Settings, see the
// _FontScaleControl clamp 1.5; for cells see _cells). Every RenderFlex overflow
// (FlutterError 'overflowed by') is collected and the test turns RED. There is NO
// ratchet or exception: overflow = red.
//
// Text scale: main.dart overrides MediaQuery with AppSettings.fontScale (the system
// scale is ignored), so the scale is applied through the app's real path
// (AppSettings.setFontScale). 2.0 is NOT reachable in the app (clamp 1.5).
//
// FONT: flutter_test's default Ahem font draws every glyph as a 1 em square
// (~1.7-2x wider than real Latin text). That made the Rapor "4.7 px overflow at
// 360 dp" (project report 9c) an artificial finding that does NOT exist on a
// device. Here the app's REAL fonts (assets/fonts) are loaded (_loadAppFonts);
// at 360x640 x1.0 the Rapor has NO overflow; real overflows are at 320 dp and x1.5.
//
// Helpers reused: test/helpers/test_app.dart (buildTestServices, SesliKitapApp),
// tutor_helpers.dart (tutor lesson part phase).
// The "zz_" FILE NAME PREFIX IS DELIBERATE: this test loads the REAL app fonts
// isolate-wide (FontLoader cannot be undone). CI shards and `make check-fast`
// (TEST_SINGLE_ENTRY) run the files in one isolate in C-locale SORTED order; font
// leakage would break the pixel-based textContrast measurements in
// test/temel/erisilebilirlik_test.dart (4 tests red locally). Sorting this name
// LAST ensures the leak affects no test.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/src/quiz_choice_machine.dart';
import 'package:sesli_kitap/ui/screens/cards_screen.dart';
import 'package:sesli_kitap/ui/screens/notebook_screen.dart';
import 'package:sesli_kitap/ui/screens/quiz_choice_screen.dart';
import 'package:sesli_kitap/ui/screens/reader_screen.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';

import 'helpers/pump_fast.dart';
import 'helpers/test_app.dart';
import 'helpers/tutor_helpers.dart';

const _longTitle =
    'Sigmund Freud - Rüyaların Yorumu (Tam Metin) - Genişletilmiş '
    'Türkçe Baskı, Ciltli, İkinci Cilt';

const _books = <Book>[
  Book(
    id: 'dar-1',
    title: _longTitle,
    author: 'Sigmund Freud ve Çevirmen Heyeti',
    chapterLabel: 'Bölüm 7: Rüya Çalışması ve Yer Değiştirme',
    progressPercent: 42,
    totalPages: 649,
    coverIndex: 0,
    hash: 'darhash000000001',
  ),
  Book(
    id: 'dar-2',
    title: 'Kısa Ad',
    author: 'Yazar',
    chapterLabel: 'Chapter 1',
    progressPercent: 0,
    totalPages: 100,
    coverIndex: 1,
    hash: 'darhash000000002',
  ),
  Book(
    id: 'dar-3',
    title: 'Penman Financial Statement Analysis and Security Valuation',
    author: 'Stephen H. Penman',
    chapterLabel: 'Chapter 5',
    progressPercent: 100,
    totalPages: 760,
    coverIndex: 2,
    hash: 'darhash000000003',
  ),
];

const _book0 = Book(
  id: 'dar-1',
  title: _longTitle,
  author: 'Sigmund Freud ve Çevirmen Heyeti',
  chapterLabel: 'Bölüm 7',
  progressPercent: 42,
  totalPages: 649,
  coverIndex: 0,
  hash: 'darhash000000001',
);

/// Scan cells (surface, text scale). 320x568 is smaller than 360x640 in both
/// dimensions -> a layout that passes 320x568 also passes 360x640 (measured: every
/// screen that was red at 360x640 in the base code was also red at 320x568). For
/// the time budget (<10 s) ALL screens run only in these two cells; the 360x640
/// x1.5 cell additionally runs for the [_cells360] screens. 360 dp x1.0 is
/// measured separately in erisilebilirlik_test.dart (360x800).
const _cells = <({Size size, double scale})>[
  (size: Size(320, 568), scale: 1.0),
  (size: Size(320, 568), scale: 1.5),
];
const ({double scale, Size size}) _cell360 = (size: Size(360, 640), scale: 1.5);

/// Representative screens that also run in the 360x640 x1.5 cell (every overflow family).
const _cells360 = <String>{
  'kutuphane-kitapli',
  'ayarlar',
  'rapor',
  'kartlar',
  'okuyucu-icerikli',
  'tartisma-kitapli',
};

/// Summary "file:line -- N px" extracted from the FlutterError text.
String _describe(FlutterErrorDetails d) {
  final text = d.toString();
  final px = RegExp(
    r'overflowed by ([0-9.]+) pixels on the (\w+)',
  ).firstMatch(text);
  final loc = RegExp(r'/([A-Za-z0-9_]+\.dart):(\d+)').firstMatch(text);
  return '${loc?.group(1) ?? "?"}:${loc?.group(2) ?? "?"} -- '
      '${px?.group(1) ?? "?"} px ${px?.group(2) ?? "?"}';
}

Future<AppServices> _services({bool withBooks = false}) => buildTestServices(
  prefsValues: {if (withBooks) 'books_v1': encodeBooks(_books)},
);

/// Builds the app (composition root); applies the text scale through the app's
/// real path (AppSettings.setFontScale).
Future<void> _pumpApp(
  WidgetTester tester,
  double scale, {
  AppServices? services,
  bool withBooks = false,
  bool onboarded = true,
}) async {
  final s = services ?? await _services(withBooks: withBooks);
  await tester.pumpWidget(
    buildTestAppFromServices(s, initialOnboarded: onboarded),
  );
  await tester.pump();
  AppSettingsScope.of(
    tester.element(find.byType(MaterialApp)),
  ).setFontScale(scale);
  await pumpFast(tester);
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  expect(f, findsOneWidget, reason: 'the tap target must be on screen');
  await tester.tap(f);
  await pumpFast(tester);
}

Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await _tap(tester, f);
}

/// Builds a single-screen widget (not attached to the Navigator/AppShell) through
/// the app's theme + scale path.
Future<void> _pumpDirect(
  WidgetTester tester,
  double scale,
  Widget child, {
  AppServices? services,
}) async {
  final s = services ?? await _services();
  final settings = AppSettings(fontScale: scale);
  addTearDown(settings.dispose);
  await tester.pumpWidget(
    AppServicesScope(
      services: s,
      child: AppSettingsScope(
        settings: settings,
        child: MaterialApp(
          theme: buildAppTheme(settings),
          builder: (context, c) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: c!,
          ),
          home: child,
        ),
      ),
    ),
  );
  await pumpFast(tester);
}

final Map<String, Future<void> Function(WidgetTester, double)> _screens =
    <String, Future<void> Function(WidgetTester, double)>{
      'onboarding': (t, s) => _pumpApp(t, s, onboarded: false),
      'kutuphane-bos': _pumpApp,
      'kutuphane-kitapli': (t, s) => _pumpApp(t, s, withBooks: true),
      'kesfet': (t, s) async {
        await _pumpApp(t, s, withBooks: true);
        await _tap(t, find.byTooltip('Discover'));
      },
      'defter': (t, s) async {
        await _pumpApp(t, s);
        await _tap(t, find.byTooltip('Notebook'));
      },
      'ayarlar': (t, s) async {
        await _pumpApp(t, s);
        await _tap(t, find.byTooltip('Settings'));
      },
      'kitap-ekle': (t, s) async {
        await _pumpApp(t, s);
        await _tap(t, find.text('Add book'));
      },
      'ayarlar-api-diyalogu': (t, s) async {
        await _pumpApp(t, s);
        await _tap(t, find.byTooltip('Settings'));
        await _tapVisible(t, find.text('Gemini API key'));
      },
      'ayarlar-telaffuz-diyalogu': (t, s) async {
        await _pumpApp(t, s);
        await _tap(t, find.byTooltip('Settings'));
        await _tapVisible(t, find.text('Add new pronunciation'));
      },
      'kitap-ekle-hata': (t, s) async {
        final services = await buildTestServices(
          pickPdf: () async => PickedBook(
            name: '$_longTitle.pdf',
            bytes: Uint8List.fromList(const [1, 2, 3, 4]),
          ),
        );
        await _pumpApp(t, s, services: services);
        await _tap(t, find.text('Add book'));
        await t.tap(find.text('Choose file'));
        for (var i = 0; i < 20 && find.text('Error').evaluate().isEmpty; i++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await t.pump();
        }
        await pumpFast(t);
        expect(find.text('Error'), findsOneWidget);
      },
      'tartisma-kitapli': (t, s) async {
        await _pumpApp(t, s, withBooks: true);
        await _tap(t, find.text(_longTitle).first);
        await _tap(t, find.text('Discussion'));
      },
      'quiz-kitapli': (t, s) async {
        await _pumpApp(t, s, withBooks: true);
        await _tap(t, find.text(_longTitle).first);
        await _tap(t, find.text('Quiz'));
      },
      'okuyucu-bos': (t, s) async {
        await _pumpApp(t, s);
        await _tap(t, find.text('Reader'));
      },
      'okuyucu-icerikli': (t, s) => _pumpDirect(
        t,
        s,
        const Scaffold(
          body: ReaderScreen(
            sentences: [
              'Rüya olağanüstü bir şiir, tam yerini bulan bir alegori.',
              'Büyülenenler o saçma rüyaları gözden mi kaçırdılar?',
            ],
            book: _book0,
          ),
        ),
      ),
      'ozel-ders-kitaplar': (t, s) async {
        await _pumpApp(t, s, withBooks: true);
        await _tap(t, find.byKey(const Key('library-open-tutor')));
      },
      'ozel-ders-parca': (t, s) async {
        final services = await buildTutorServices(llm: FakeTutorLlm().call);
        await t.runAsync(() => seedTutorPages(services));
        await _pumpApp(t, s, services: services);
        await _tap(t, find.byKey(const Key('library-open-tutor')));
        await _tap(t, find.byKey(Key('tutor-book-${tutorBook.id}')));
        await pumpUntil(t, find.byKey(const Key('tutor-chapter-0')));
        await _tap(t, find.byKey(const Key('tutor-chapter-0')));
        await pumpUntil(t, find.byKey(const Key('tutor-part')));
        expect(find.byKey(const Key('tutor-part')), findsOneWidget);
      },
      'tartisma-odasi': (t, s) async {
        await _pumpApp(t, s);
        await _tap(t, find.text('Discussion'));
      },
      'quiz': (t, s) async {
        await _pumpApp(t, s);
        await _tap(t, find.text('Quiz'));
      },
      'rapor': (t, s) async {
        await _pumpApp(t, s);
        await _tap(t, find.text('Report'));
      },
      'defter-alintili': (t, s) => _pumpDirect(
        t,
        s,
        const NotebookScreen(
          quotes: [
            NotebookQuote(
              text:
                  'Rüya olağanüstü bir şiir, tam yerini bulan bir alegori, '
                  'benzersiz bir mizah ve nefis bir ironidir.',
              page: 101,
              book: _longTitle,
            ),
          ],
        ),
      ),
      'kartlar': (t, s) => _pumpDirect(
        t,
        s,
        const CardsScreen(
          cards: [
            StudyCard(
              soru:
                  'Artık kazanç (residual earnings) tam olarak nasıl '
                  'tanımlanır ve neden defter değerinin üstünde yer alır?',
              yanit:
                  'Gerekli getiriyi aşan kazanç; defter değerine eklenen '
                  'beklenen artık kazançların bugünkü değeri.',
            ),
          ],
        ),
      ),
      'kartlar-yanit': (t, s) async {
        await _pumpDirect(
          t,
          s,
          const CardsScreen(
            cards: [
              StudyCard(
                soru: 'Artık kazanç nedir?',
                yanit:
                    'Gerekli getiriyi aşan kazanç; defter değerine eklenen '
                    'beklenen artık kazançların bugünkü değeri ve sürekli '
                    'değer büyümesi için dayanak olan temel büyüklük.',
              ),
            ],
          ),
        );
        await _tap(t, find.text('QUESTION'));
      },
      'quiz-secim': (t, s) => _pumpDirect(
        t,
        s,
        QuizChoiceScreen(
          sorular: [
            MultipleChoiceQuestion(
              soru:
                  'Artık kazanç modelinde sürekli değer büyümesi hangi '
                  'varsayımla bağlantılı olarak hesaplanır?',
              secenekler: const [
                'Gerekli getiriyi aşan kazancın büyümesi sabittir',
                'Defter değeri her yıl sıfırlanır ve yeniden başlar',
                'Temettü ödeme oranı her dönem değişken kabul edilir',
                'Hiçbiri; model büyümeyi hiç hesaba katmaz sonuçta',
              ],
              dogruIndex: 0,
              kaynak: 'Penman, Bölüm 5, s. 123',
            ),
          ],
        ),
      ),
    };

/// flutter_test's default is the Ahem font (each glyph a 1 em SQUARE: ~1.7-2x wider
/// than real Latin text), so overflow results are overly pessimistic. The app's
/// REAL fonts (pubspec.yaml `fonts:`, assets/fonts/*.ttf) are loaded, so the
/// measured widths are close to those on a device. (No Roboto/system font: the app
/// already supplies its theme font, 'Public Sans'.)
Future<void> _loadAppFonts() async {
  const families = <String, List<String>>{
    'Public Sans': [
      'PublicSans-Light',
      'PublicSans-Regular',
      'PublicSans-Medium',
      'PublicSans-SemiBold',
      'PublicSans-Bold',
    ],
    'Libre Caslon Display': ['LibreCaslonDisplay-Regular'],
    'Libre Caslon Text': ['LibreCaslonText-Regular', 'LibreCaslonText-Italic'],
    'Lexend': ['Lexend-Regular', 'Lexend-Medium'],
  };
  for (final e in families.entries) {
    final loader = FontLoader(e.key);
    for (final f in e.value) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_loadAppFonts);

  test('scan coverage: cell and screen counts', () {
    expect(_cells.map((c) => c.scale), contains(1.5));
    expect(_cells.map((c) => c.size.width), contains(320));
    expect(_cell360.size.width, 360);
    expect(_screens.length, greaterThanOrEqualTo(20));
    expect(_screens.keys, containsAll(_cells360));
  });

  for (final screen in _screens.entries) {
    for (final cell in [
      ..._cells,
      if (_cells360.contains(screen.key)) _cell360,
    ]) {
      final size = cell.size;
      final scale = cell.scale;
      testWidgets(
        '${screen.key} / ${size.width.toInt()}x${size.height.toInt()} / '
        'x$scale: no overflow',
        (tester) async {
          tester.view.devicePixelRatio = 1.0;
          tester.view.physicalSize = size;
          addTearDown(tester.view.reset);
          final overflows = <String>[];
          final previous = FlutterError.onError;
          FlutterError.onError = (details) {
            if (details.toString().contains('overflowed by')) {
              overflows.add(_describe(details));
              return;
            }
            previous?.call(details);
          };
          addTearDown(() => FlutterError.onError = previous);
          await screen.value(tester, scale);
          // Do not let an empty set pass: the screen was really drawn.
          expect(find.byType(Scaffold), findsWidgets);
          expect(
            overflows.toSet().toList()..sort(),
            isEmpty,
            reason:
                '${screen.key} ${size.width.toInt()}x${size.height.toInt()}'
                ' scale $scale: RenderFlex overflow',
          );
        },
      );
    }
  }
}
