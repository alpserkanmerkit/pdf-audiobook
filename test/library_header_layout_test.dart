// Oracle test (2026-10-06, field: device, Library screen). Observation: the
// title "Your library" stayed on the same row as the 4 shortcut buttons on the
// right, so the title broke into TWO lines (device screenshot,
// 1224 px wide; assuming dpr 3, ~408 dp).
// Expected: on narrow phone widths (360/393/408 dp) and text scale 1.0 / 1.3 the
// title is ONE line, the 4 shortcuts are on screen and do not overlap the title,
// and there is no RenderFlex overflow.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/ui/screens/library_screen.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';

const _title = 'Your library';

const List<IconData> _shortcutIcons = [
  Icons.explore,
  Icons.school,
  Icons.bookmark_border,
  Icons.tune,
];

Future<void> _pumpLibrary(
  WidgetTester tester, {
  required double width,
  required double textScale,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);
  final settings = AppSettings();
  await tester.pumpWidget(
    AppSettingsScope(
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
          body: LibraryScreen(
            books: const [],
            onAddBook: () {},
            onOpenBook: (_) {},
            onOpenSettings: () {},
            onOpenNotebook: () {},
            onOpenDiscover: () {},
            onOpenTutor: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Number of lines the paragraph actually wraps to: each line produces a box at
/// a different vertical position, so count the distinct 'top' values.
int _lineCount(RenderParagraph p) {
  final boxes = p.getBoxesForSelection(
    const TextSelection(baseOffset: 0, extentOffset: _title.length),
  );
  return boxes.map((b) => b.top.round()).toSet().length;
}

void main() {
  for (final width in const [360.0, 393.0, 408.0]) {
    for (final scale in const [1.0, 1.3]) {
      testWidgets(
        'width=$width dp, scale=$scale: title is one line, shortcuts are on '
        'screen and do not overlap the title, no overflow',
        (tester) async {
          await _pumpLibrary(tester, width: width, textScale: scale);

          expect(
            tester.takeException(),
            isNull,
            reason: 'there must be no RenderFlex overflow or paint error',
          );

          final titleFinder = find.text(_title);
          expect(titleFinder, findsOneWidget);
          final paragraph = tester.renderObject<RenderParagraph>(titleFinder);
          expect(
            _lineCount(paragraph),
            1,
            reason:
                '"$_title" must not wrap onto two lines (field bug: the title broke)',
          );

          final titleRect = tester.getRect(titleFinder);
          expect(
            titleRect.right,
            lessThanOrEqualTo(width),
            reason: 'title must not overflow the screen',
          );

          for (final icon in _shortcutIcons) {
            final f = find.byIcon(icon);
            expect(f, findsOneWidget, reason: 'shortcut $icon must be visible');
            final r = tester.getRect(f);
            expect(r.left, greaterThanOrEqualTo(0));
            expect(
              r.right,
              lessThanOrEqualTo(width),
              reason: 'shortcut $icon must be on screen',
            );
            expect(
              r.overlaps(titleRect),
              isFalse,
              reason: 'shortcut $icon must not overlap the title',
            );
            // Accessibility: the button is actually tappable (the hit test reaches it).
            final center = r.center;
            final hit = tester.hitTestOnBinding(center);
            final hitsButton = hit.path.any(
              (e) =>
                  e.target is RenderObject &&
                  find
                      .ancestor(of: f, matching: find.byType(IconButton))
                      .evaluate()
                      .any((el) => el.renderObject == e.target),
            );
            expect(
              hitsButton,
              isTrue,
              reason: 'shortcut $icon must be tappable',
            );
          }
        },
      );
    }
  }
}
