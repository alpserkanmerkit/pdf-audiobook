// FLOW 1: add a book. First launch -> onboarding -> Library -> "Add book"
// -> "Choose file" (AppServices.pickPdf seam, REAL file path) -> real isolate import
// (copy + sha256 + syncfusion text) -> visible in the library.
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/chapter_cache.dart';
import 'package:sesli_kitap/src/library/library_store.dart';

import '../support/e2e_world.dart';

void addBookFlow() {
  testWidgets('flow 1: onboarding -> add book -> visible in library + '
      'persisted on disk/prefs', (tester) async {
    final world = await E2eWorld.create();
    addTearDown(world.dispose);
    await world.launch(tester);

    // First launch: onboarding is visible, the library is not.
    expect(find.textContaining('Welcome to the reading room'), findsWidgets);
    expect(find.text('Your library'), findsNothing);
    await finishOnboarding(tester);
    expect(find.text('Your library'), findsWidgets);
    expect(
      world.services.prefs.getString('books_v1'),
      isNull,
      reason: 'before adding, the library is empty',
    );

    await addBookViaUi(tester);

    // Visible in the library (title = file name - ".pdf").
    expect(find.text('fixture_kitap'), findsWidgets);

    // Persistence: expected values come from the FIXTURE (4 pages; content hash) --
    // not copied from the app's own output.
    final fixtureBytes = world.pdfFile.readAsBytesSync();
    final expectedHash = sha256
        .convert(fixtureBytes)
        .toString()
        .substring(0, 16);
    final books = decodeBooks(world.services.prefs.getString('books_v1')!);
    expect(books, hasLength(1));
    expect(books.single.hash, expectedHash);
    expect(books.single.title, 'fixture_kitap');
    expect(books.single.totalPages, 4);
    final stored = File('${world.dataDir.path}/books/$expectedHash.pdf');
    expect(
      stored.existsSync(),
      isTrue,
      reason: 'the PDF is copied into dataDir/books',
    );
    expect(stored.readAsBytesSync(), fixtureBytes);

    // Chapter map: the common running header of the 4 pages -> one chapter 1-4.
    final chapters = decodeChapters(
      world.services.prefs.getString('chapters_$expectedHash')!,
    );
    expect(chapters, hasLength(1));
    expect(chapters.single.title, kRunningHeader);
    expect(chapters.single.startPage, 1);
    expect(chapters.single.endPage, 4);

    // No key -> the network is NEVER contacted while adding.
    expect(world.server.requests, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
