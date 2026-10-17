// Oracle test (PHASE 2): prefetch limit (spec §3): "Only the next 3-page
// block is prefetched in the background. Never more." These tests lock that
// "never" structurally: a page beyond the block = a contract violation.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/prefetch_policy.dart';

void main() {
  group('nextPrefetchBlock', () {
    test('next 3 consecutive pages (none ready)', () {
      expect(nextPrefetchBlock(currentPage: 10, totalPages: 706, ready: {}), [
        11,
        12,
        13,
      ]);
    });
    test('ready pages are skipped, only missing ones are returned', () {
      expect(
        nextPrefetchBlock(currentPage: 10, totalPages: 706, ready: {11, 13}),
        [12],
      );
    });
    test(
      'block fully ready returns empty -- does NOT reach page 4 (spec: never)',
      () {
        expect(
          nextPrefetchBlock(
            currentPage: 10,
            totalPages: 706,
            ready: {11, 12, 13},
          ),
          isEmpty,
        );
      },
    );
    test('book end is clipped: 705/706 -> only [706]', () {
      expect(nextPrefetchBlock(currentPage: 705, totalPages: 706, ready: {}), [
        706,
      ]);
    });
    test('empty on the last page', () {
      expect(
        nextPrefetchBlock(currentPage: 706, totalPages: 706, ready: {}),
        isEmpty,
      );
    });
    test('no returned page goes outside the block (structural contract)', () {
      for (final ready in <Set<int>>[
        {},
        {11},
        {11, 12},
        {11, 12, 13},
      ]) {
        final block = nextPrefetchBlock(
          currentPage: 10,
          totalPages: 706,
          ready: ready,
        );
        for (final p in block) {
          expect(p, inInclusiveRange(11, 13));
        }
      }
    });
  });
}
