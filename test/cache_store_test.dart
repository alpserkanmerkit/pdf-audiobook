// Oracle test (FAZ 2b — cache integrity K11+K23):
// K11: corrupt-record contract — "corrupt record = treat as missing, regenerate"
//   must cover ALL corruption, including valid JSON with a wrong field type
//   (TypeError, an Error); readText must return null and must not crash the caller.
// K23: atomic audio writes — writeAudio must write via a temp file + rename
//   (a half-written file must never appear under the final name); hasAudio does NOT
//   count a 0-byte mp3 as cached (content-stamped keys never change, so a truncated
//   file would be served forever).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/io/cache_store.dart';
import 'package:sesli_kitap/src/sentence_timing.dart';

void main() {
  late Directory tmp;
  late CacheStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cache_store_test');
    store = CacheStore(tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  group('readText — corrupt record contract (K11)', () {
    test(
      'valid JSON but wrong field type -> null (TypeError is swallowed)',
      () async {
        // raw int (not String): jsonDecode succeeds, the fromJson cast throws a
        // TypeError (an Error) -- by the contract this too is "corrupt record = null".
        final f = File('${tmp.path}/k11.json');
        await f.writeAsString(
          jsonEncode({
            'raw': 5,
            'clean': 'clean text',
            'promptVersion': 'v1',
            'suspicious': false,
          }),
        );
        expect(await store.readText('k11'), isNull);
      },
    );

    test('JSON body is not a Map (list) -> null', () async {
      final f = File('${tmp.path}/liste.json');
      await f.writeAsString('[1, 2, 3]');
      expect(await store.readText('liste'), isNull);
    });

    test('invalid JSON -> null (existing behavior is kept)', () async {
      final f = File('${tmp.path}/cop.json');
      await f.writeAsString('{bozuk json%%');
      expect(await store.readText('cop'), isNull);
    });

    test('valid record round-trips and reads back (regression)', () async {
      const entry = TextEntry(
        raw: 'ham',
        clean: 'temiz',
        promptVersion: 'v1',
        suspicious: true,
        suspicionReasons: ['kisa'],
        auditFaithful: true,
      );
      await store.writeText('ok', entry);
      final okunan = await store.readText('ok');
      expect(okunan, isNotNull);
      expect(okunan!.raw, 'ham');
      expect(okunan.clean, 'temiz');
      expect(okunan.promptVersion, 'v1');
      expect(okunan.suspicious, isTrue);
      expect(okunan.suspicionReasons, ['kisa']);
      expect(okunan.auditFaithful, isTrue);
    });
  });

  group('writeAudio — atomic write (K23)', () {
    test(
      'no .tmp leftover after writing; the mp3 exists with the content',
      () async {
        final bytes = Uint8List.fromList([0x49, 0x44, 0x33, 1, 2, 3]);
        final f = await store.writeAudio('ses1', bytes);
        expect(await f.exists(), isTrue);
        expect(await f.readAsBytes(), bytes);
        final tmpArtiklari = tmp
            .listSync()
            .where((e) => e.path.endsWith('.tmp'))
            .toList();
        expect(tmpArtiklari, isEmpty);
        expect(await store.hasAudio('ses1'), isTrue);
      },
    );
  });

  group('hasAudio — empty file protection (K23)', () {
    test('0-byte mp3 (half-written leftover) -> false', () async {
      final f = File('${tmp.path}/bos.mp3');
      await f.writeAsBytes(<int>[], flush: true);
      expect(await f.exists(), isTrue); // the file really exists...
      expect(
        await store.hasAudio('bos'),
        isFalse,
      ); // ...but is not counted as cache
    });

    test('file does not exist at all -> false', () async {
      expect(await store.hasAudio('yok'), isFalse);
    });
  });

  group('timing sidecar (karaoke PR-K1)', () {
    test(
      'round-trip: readTimings returns the same value that writeTimings wrote',
      () async {
        const t = SentenceTimings(startsMs: [0, 1200, 4500], totalMs: 9000);
        await store.writeTimings('t1', t);
        final okunan = await store.readTimings('t1');
        expect(okunan, isNotNull);
        expect(okunan!.startsMs, [0, 1200, 4500]);
        expect(okunan.totalMs, 9000);
        // no .tmp leftover after the atomic write.
        final artik = tmp
            .listSync()
            .where((e) => e.path.endsWith('.tmp'))
            .toList();
        expect(artik, isEmpty);
      },
    );

    test('file missing -> null', () async {
      expect(await store.readTimings('yok'), isNull);
    });

    test('corrupt sidecar -> null (K11 catch-all pattern)', () async {
      final f = store.timingFile('cop');
      await f.writeAsString('{bozuk json%%');
      expect(await store.readTimings('cop'), isNull);
    });

    test('valid JSON but wrong version -> null', () async {
      final f = store.timingFile('vy');
      await f.writeAsString('{"v":2,"startsMs":[0],"totalMs":1}');
      expect(await store.readTimings('vy'), isNull);
    });
  });

  // S2: an infinite discussion writes a temporary mp3 for every turn; the sweep at
  // the start of a run removes the leftovers of the previous run (.mp3 + truncated .mp3.tmp).
  group('sweepAudio — deletes audio leftovers that match the prefix', () {
    test(
      'matching mp3 + .mp3.tmp are deleted, the others stay, the count is returned',
      () async {
        // Matches: mp3 + tmp starting with the prefix "discussion_turn_".
        await File('${tmp.path}/discussion_turn_1.mp3').writeAsBytes([1, 2, 3]);
        await File('${tmp.path}/discussion_turn_2.mp3').writeAsBytes([4, 5]);
        await File('${tmp.path}/discussion_turn_3.mp3.tmp').writeAsBytes([6]);
        // Non-matches: an mp3 with a different prefix, a text JSON, a prefixed file without the extension.
        await File('${tmp.path}/reader_page_1.mp3').writeAsBytes([7]);
        await File('${tmp.path}/discussion_turn_1.json').writeAsString('{}');

        final silinen = await store.sweepAudio('discussion_turn_');
        expect(silinen, 3, reason: '2 mp3 + 1 tmp = 3 files must be deleted');

        final kalan = tmp.listSync().map((e) => e.path.split('/').last).toSet();
        // the path separator may differ by platform -> normalize the last segment.
        final adlar = tmp
            .listSync()
            .map((e) => e.uri.pathSegments.last)
            .toSet();
        expect(adlar, contains('reader_page_1.mp3'));
        expect(adlar, contains('discussion_turn_1.json'));
        expect(
          adlar.where(
            (n) => n.startsWith('discussion_turn_') && n.endsWith('.mp3'),
          ),
          isEmpty,
          reason: 'none of the prefixed mp3s may remain',
        );
        expect(
          adlar.any((n) => n.endsWith('.mp3.tmp')),
          isFalse,
          reason: 'the prefixed .mp3.tmp leftover must be deleted too',
        );
        // ('kalan' is only a cross-check; 'adlar' is the actual assertion.)
        expect(kalan, isNotEmpty);
      },
    );

    test('no match -> returns 0, the directory is unchanged', () async {
      await File('${tmp.path}/other.mp3').writeAsBytes([1]);
      final silinen = await store.sweepAudio('discussion_turn_');
      expect(silinen, 0);
      expect(await File('${tmp.path}/other.mp3').exists(), isTrue);
    });
  });
}
