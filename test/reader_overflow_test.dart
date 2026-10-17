// Oracle test (2026-09-28, field: the user saw the Flutter "RIGHT OVERFLOWED
// BY 251 PIXELS" message on the reader screen on their phone; the discussion
// screen was fine). The user will not retry on the phone, so the field issue
// is reproduced on desktop: the reader screen is drawn at phone widths
// (320/360/393 logical px) and at a large text scale (1.3). When a RenderFlex
// overflows in a Flutter test it throws a FlutterError -> caught by
// tester.takeException().
// The book title comes from the file name of the PDF the user opened
// (add_book_screen: title = file name minus '.pdf') -- the real desktop file
// name is used.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/ui/screens/reader_screen.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';

import 'helpers/test_app.dart';

const _freudTitle = 'Sigmund Freud - Rüyaların Yorumu (Tam Metin)';

// Two real sentences from the Freud PDF p.101 (the app's own extraction).
const _sentences = [
  'Rüya olağanüstü bir şiir, tam yerini bulan bir alegori, benzersiz bir '
      'mizah ve nefis bir ironidir.',
  'Büyülenenler o saçma rüyaları, aşağılayanlar ise, o derinlikli ve '
      'duyarlı rüyaları gözden mi kaçırdılar acaba?',
];

Book _book({String filePath = ''}) => Book(
  id: 'freud',
  title: _freudTitle,
  author: '',
  chapterLabel: '',
  progressPercent: 0,
  totalPages: 649,
  coverIndex: 0,
  hash: 'freudhash0000001',
  filePath: filePath,
);

Future<void> _pumpReader(
  WidgetTester tester, {
  required double width,
  required double textScale,
  required Book book,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.reset);
  final services = await buildTestServices();
  final settings = AppSettings();
  await tester.pumpWidget(
    AppServicesScope(
      services: services,
      child: AppSettingsScope(
        settings: settings,
        child: MaterialApp(
          theme: buildAppTheme(settings),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: ReaderScreen(sentences: _sentences, book: book),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  for (final width in const [320.0, 360.0, 393.0]) {
    for (final scale in const [1.0, 1.3]) {
      testWidgets('reader ${width.toInt()} px, text scale $scale: '
          'no OVERFLOW with a long book title', (tester) async {
        await _pumpReader(
          tester,
          width: width,
          textScale: scale,
          book: _book(),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'RenderFlex overflow (field: RIGHT OVERFLOWED BY 251 PIXELS)',
        );
        // The book title stays on screen (it may be shortened).
        expect(find.textContaining('Sigmund Freud'), findsOneWidget);
      });
    }
  }

  testWidgets('file-not-found warning at 320 px + scale 1.3: no OVERFLOW', (
    tester,
  ) async {
    await _pumpReader(
      tester,
      width: 320,
      textScale: 1.3,
      book: _book(filePath: '/missing/no-such-file.pdf'),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('File not found'), findsOneWidget);
  });
}
