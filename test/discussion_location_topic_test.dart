// PR (A6) wiring test (oracle). discussion_room_screen.dart _showStartDialog
// correctly wires the worker's location-aware topic-suggestion chip list.
// Harness pattern: test/discussion_wiring_test.dart (UNCHANGED; only its setup
// style -- _wrapScreen/AppServicesScope -- is repeated here, since private
// helpers cannot be shared across files).
//
//  t1: seeded books_v1 (progress>0) -> a book chip appears in the start dialog;
//      tapping the chip fills the topic field with discussionTopicForBook(book).
//  t2: if no book has progress >0, the chip list NEVER appears (BYTE-IDENTITY:
//      the old dialog body stays unchanged).
//  t3: when there is NO AppServicesScope (the setup of many existing wiring
//      tests) the dialog opens as before; no crash, no chip list.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/discussion/discussion_topic_suggest.dart';
import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/ui/screens/discussion_room_screen.dart';
import 'package:sesli_kitap/ui/state/app_services.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';
import 'helpers/test_app.dart';

/// Wraps [DiscussionRoomScreen] alone -- the SAME pattern as `_wrapScreen` in
/// test/discussion_wiring_test.dart (private helpers are repeated here, since
/// they cannot be shared across files).
Widget _wrapScreen(Widget child) {
  final settings = AppSettings();
  return AppSettingsScope(
    settings: settings,
    child: MaterialApp(theme: buildAppTheme(settings), home: child),
  );
}

Future<void> _openStartDialog(WidgetTester tester) async {
  await tester.tap(find.widgetWithIcon(IconButton, Icons.play_arrow));
  await tester.pumpAndSettle();
}

void main() {
  group('A6 — location-aware discussion topic suggestion', () {
    testWidgets(
      'a chip appears for a book with progress >0; tapping it fills the topic '
      'field with discussionTopicForBook (ROOT-CAUSE FIX, device evidence 08.07: '
      'the real progress is NOT books_v1 progressPercent but the page-based '
      'progress_<hash> persistence written by the reader -- see app_shell.dart '
      '_libraryBooks; this fixture leaves the SEED books_v1 progressPercent=0 '
      'and feeds the real source via progress_<hash>)',
      (tester) async {
        const book = Book(
          id: 'b1',
          title: 'Sessizliğin Mimarisi',
          author: 'D. Karaca',
          chapterLabel: 'Chapter 4',
          progressPercent: 0,
          totalPages: 318,
          coverIndex: 0,
          hash: 'h1',
        );
        final services = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks(const [book]),
            'progress_h1': 121, // 121/318 -> 38% (effectiveProgressPercent)
          },
        );

        await tester.pumpWidget(
          AppServicesScope(
            services: services,
            child: _wrapScreen(const DiscussionRoomScreen()),
          ),
        );
        await tester.pumpAndSettle();

        await _openStartDialog(tester);

        expect(
          find.text(book.title),
          findsOneWidget,
          reason: 'a suggestion chip must appear for a book with progress >0',
        );

        await tester.tap(find.text(book.title));
        await tester.pumpAndSettle();

        final field = tester.widget<TextField>(find.byType(TextField).first);
        expect(
          field.controller!.text,
          discussionTopicForBook(book.withProgress(38)),
          reason:
              'tapping the chip must fill the topic field with discussionTopicForBook '
              'using the REAL percentage (computed from progress_<hash>)',
        );
      },
    );

    testWidgets(
      'if no book has progress >0, the suggestion chip list is NEVER shown '
      '(BYTE-IDENTITY: the old dialog does not change)',
      (tester) async {
        const book = Book(
          id: 'b1',
          title: 'Not Started Yet',
          author: 'Y',
          chapterLabel: 'Chapter 1',
          progressPercent: 0,
          totalPages: 100,
          coverIndex: 0,
        );
        final services = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks(const [book]),
          },
        );

        await tester.pumpWidget(
          AppServicesScope(
            services: services,
            child: _wrapScreen(const DiscussionRoomScreen()),
          ),
        );
        await tester.pumpAndSettle();

        await _openStartDialog(tester);

        expect(find.text(book.title), findsNothing);
        // The old dialog body (length selector) must remain intact.
        expect(find.text('New Discussion'), findsOneWidget);
        expect(find.text('Short'), findsOneWidget);
        expect(find.text('Endless'), findsOneWidget);
      },
    );

    testWidgets(
      'if there is NO AppServicesScope (setup of the existing wiring tests) the '
      'dialog opens as before; no crash',
      (tester) async {
        await tester.pumpWidget(_wrapScreen(const DiscussionRoomScreen()));
        await tester.pumpAndSettle();

        await _openStartDialog(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('New Discussion'), findsOneWidget);
        expect(find.text('Short'), findsOneWidget);
      },
    );

    testWidgets(
      'a manually typed topic stays BYTE-IDENTICAL without touching any '
      'chip (the suggestion chip mechanism does not affect manual input)',
      (tester) async {
        const book = Book(
          id: 'b1',
          title: 'Sessizliğin Mimarisi',
          author: 'D. Karaca',
          chapterLabel: 'Chapter 4',
          progressPercent: 0,
          totalPages: 318,
          coverIndex: 0,
          hash: 'h1',
        );
        final services = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks(const [book]),
            'progress_h1':
                121, // make the chip REALLY visible -- to check whether
            // manual input changes DESPITE the mechanism's presence.
          },
        );

        await tester.pumpWidget(
          AppServicesScope(
            services: services,
            child: _wrapScreen(const DiscussionRoomScreen()),
          ),
        );
        await tester.pumpAndSettle();

        await _openStartDialog(tester);

        const elleYazilan = 'a topic written entirely by hand';
        await tester.enterText(find.byType(TextField).first, elleYazilan);
        await tester.pumpAndSettle();

        final field = tester.widget<TextField>(find.byType(TextField).first);
        expect(field.controller!.text, elleYazilan);
      },
    );

    testWidgets(
      'ROOT-CAUSE FIX (device evidence 08.07): several (long-title) book '
      'suggestions -- the dialog does NOT cause a RenderFlex overflow (BOTTOM OVERFLOWED)',
      (tester) async {
        // 3 books actually observed on the device, with long titles (Mir.az-insan,
        // Ani Depar Hizini Artirma Programi, Sigmund Freud - Rüyaların Yorumu).
        // The earlier single-book tests (t1/t4) did NOT catch the overflow,
        // because one short chip did not exceed the available height. The real
        // bug appears ONLY with several/long chips + the length selector + the
        // TextField keyboard TOGETHER (narrow vertical space); it was observed on
        // the device exactly like this.
        const books = [
          Book(
            id: 'b1',
            title: 'Mir.az-insan',
            author: '',
            chapterLabel: '',
            progressPercent: 0,
            totalPages: 706,
            coverIndex: 0,
            hash: 'h1',
          ),
          Book(
            id: 'b2',
            title: 'Ani Depar Hızını Artırma Programı',
            author: '',
            chapterLabel: '',
            progressPercent: 0,
            totalPages: 200,
            coverIndex: 1,
            hash: 'h2',
          ),
          Book(
            id: 'b3',
            title: 'Sigmund Freud - Rüyaların Yorumu (Tam Metin)',
            author: '',
            chapterLabel: '',
            progressPercent: 0,
            totalPages: 500,
            coverIndex: 2,
            hash: 'h3',
          ),
        ];
        final services = await buildTestServices(
          prefsValues: {
            'books_v1': encodeBooks(books),
            'progress_h1': 50,
            'progress_h2': 20,
            'progress_h3': 100,
          },
        );

        // The REAL condition on the device: TextField(autofocus:true) OPENS the
        // keyboard, and MediaQuery.viewInsets.bottom takes about half the screen.
        // By default the widget-test environment does NOT simulate the keyboard
        // (viewInsets stays zero), which is why the overflow was never caught in
        // tests. tester.view is used to EXPLICITLY simulate both a narrow physical
        // screen AND a realistic keyboard inset, reproducing the narrow-vertical-
        // space condition observed on the device exactly.
        tester.view.physicalSize = const Size(1080, 1200);
        tester.view.devicePixelRatio = 1.0;
        tester.view.viewInsets = const FakeViewPadding(bottom: 700);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);

        await tester.pumpWidget(
          AppServicesScope(
            services: services,
            child: _wrapScreen(const DiscussionRoomScreen()),
          ),
        );
        await tester.pumpAndSettle();

        await _openStartDialog(tester);

        expect(
          tester.takeException(),
          isNull,
          reason:
              'the dialog opened with several book suggestions + the keyboard open '
              'must NOT produce a RenderFlex overflow (observed on the device: '
              '"BOTTOM OVERFLOWED BY 145 PIXELS")',
        );
        expect(find.text('Endless'), findsOneWidget);
      },
    );
  });
}
