// RED-once oracle test (Wave-A / PR-A): book-digest PLAN layer.
// Spec: internal design note §3/§6 —
// one summarization job per chapter from the chapter map; a chapter over the token budget
// gets page-range sub-splitting (defensive: not needed for Mir; kept in the contract
// anyway); an empty or degenerate map yields one 1..N fallback chapter.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/digest/digest_constants.dart';
import 'package:sesli_kitap/src/digest/digest_plan.dart';

/// Synthetic map resembling the 20-chapter structure of Mir «Insan Dogasinin Yasalari»:
/// content s13-704 (692 pages, contiguous); front matter s1-12 is NOT in the map
/// (report FACT pattern). The largest chapter, «Uyum», has 53 pages.
const List<({String? title, int startPage, int endPage})> mirLikeChapters = [
  (title: 'Giris', startPage: 13, endPage: 26),
  (title: 'Yasa 1', startPage: 27, endPage: 62),
  (title: 'Yasa 2', startPage: 63, endPage: 98),
  (title: 'Yasa 3', startPage: 99, endPage: 134),
  (title: 'Yasa 4', startPage: 135, endPage: 170),
  (title: 'Yasa 5', startPage: 171, endPage: 206),
  (title: 'Savunuculuk Yasasi', startPage: 207, endPage: 251),
  (title: 'Yasa 7', startPage: 252, endPage: 287),
  (title: 'Yasa 8', startPage: 288, endPage: 323),
  (title: 'Uyum', startPage: 324, endPage: 376),
  (title: 'Yasa 10', startPage: 377, endPage: 412),
  (title: 'Yasa 11', startPage: 413, endPage: 448),
  (title: 'Yasa 12', startPage: 449, endPage: 484),
  (title: 'Yasa 13', startPage: 485, endPage: 520),
  (title: 'Yasa 14', startPage: 521, endPage: 556),
  (title: 'Yasa 15', startPage: 557, endPage: 592),
  (title: 'Yasa 16', startPage: 593, endPage: 628),
  (title: 'Yasa 17', startPage: 629, endPage: 671),
  (title: 'Olumu Inkar', startPage: 672, endPage: 700),
  (title: 'Kaynakca', startPage: 701, endPage: 704),
];

void main() {
  group('planDigest — normal 20-chapter map (Mir-like)', () {
    test(
      'one job per chapter, NO sub-splitting (report: 128K not exceeded)',
      () {
        final plan = planDigest(chapters: mirLikeChapters, totalPages: 706);
        expect(plan.usedFallback, isFalse);
        expect(plan.totalPages, 706);
        expect(plan.jobs, hasLength(20));
        expect(plan.chapterCount, 20);
        for (var i = 0; i < plan.jobs.length; i++) {
          final job = plan.jobs[i];
          expect(job.chapterIndex, i);
          expect(job.partIndex, 0);
          expect(job.partCount, 1);
          expect(job.title, mirLikeChapters[i].title);
          expect(job.startPage, mirLikeChapters[i].startPage);
          expect(job.endPage, mirLikeChapters[i].endPage);
          expect(
            job.estimatedTokens,
            lessThanOrEqualTo(defaultMaxTokensPerCall),
          );
        }
      },
    );

    test(
      'token estimate: Uyum (53 p.) ~45K tokens (pages x chars / chars-per-token)',
      () {
        final plan = planDigest(chapters: mirLikeChapters, totalPages: 706);
        final uyum = plan.jobs[9];
        expect(uyum.title, 'Uyum');
        expect(uyum.pageCount, 53);
        expect(uyum.estimatedChars, 53 * 2133);
        // ceil(113049 / 2.5) = 45220 -> within the report's 38-45K range.
        expect(uyum.estimatedTokens, 45220);
      },
    );

    test('job list is unmodifiable', () {
      final plan = planDigest(chapters: mirLikeChapters, totalPages: 706);
      expect(plan.jobs.removeLast, throwsUnsupportedError);
    });
  });

  group('planDigest — dev chapter sub-splitting', () {
    test('one 300-page chapter, 100 pages/call budget -> 3 equal parts', () {
      // maxTokensPerCall=85320 -> floor(85320 * 2.5 / 2133) = 100 pages/call.
      final plan = planDigest(
        chapters: const [(title: 'Dev', startPage: 1, endPage: 300)],
        totalPages: 300,
        maxTokensPerCall: 85320,
      );
      expect(plan.jobs, hasLength(3));
      expect(plan.jobs.map((j) => (j.startPage, j.endPage)).toList(), [
        (1, 100),
        (101, 200),
        (201, 300),
      ]);
      expect(plan.jobs.map((j) => j.partIndex).toList(), [0, 1, 2]);
      for (final j in plan.jobs) {
        expect(j.chapterIndex, 0);
        expect(j.partCount, 3);
        expect(j.title, 'Dev');
        expect(j.pageCount, 100);
        // Part estimates stay within the budget (page-quantized split guarantee).
        expect(j.estimatedTokens, lessThanOrEqualTo(85320));
      }
    });

    test('uneven split: 10 pages / 3-page limit -> 3+3+2+2', () {
      // maxTokensPerCall=2560 -> floor(2560 * 2.5 / 2133) = 3 pages/call.
      final plan = planDigest(
        chapters: const [(title: null, startPage: 11, endPage: 20)],
        totalPages: 20,
        maxTokensPerCall: 2560,
      );
      expect(plan.jobs.map((j) => (j.startPage, j.endPage)).toList(), [
        (11, 13),
        (14, 16),
        (17, 18),
        (19, 20),
      ]);
      expect(plan.jobs.map((j) => j.partCount).toSet(), {4});
      expect(plan.jobs.map((j) => j.partIndex).toList(), [0, 1, 2, 3]);
    });

    test(
      'even a single page fitting the budget -> part = 1 page (minimum grain)',
      () {
        final plan = planDigest(
          chapters: const [(title: 'K', startPage: 1, endPage: 3)],
          totalPages: 3,
          maxTokensPerCall: 100,
        );
        expect(plan.jobs, hasLength(3));
        for (final j in plan.jobs) {
          expect(j.pageCount, 1);
          // The estimate stays HONEST: it exceeds the budget and the overrun is reported (silent
          // downsizing is not done) -- so the io layer can pass the decision to the user.
          expect(j.estimatedTokens, greaterThan(100));
        }
      },
    );
  });

  group(
    'planDigest — empty/degenerate map -> single 1..N fallback chapter',
    () {
      test('empty map', () {
        final plan = planDigest(chapters: const [], totalPages: 50);
        expect(plan.usedFallback, isTrue);
        expect(plan.jobs, hasLength(1));
        expect(plan.jobs.single.title, isNull);
        expect(plan.jobs.single.startPage, 1);
        expect(plan.jobs.single.endPage, 50);
        expect(plan.chapterCount, 1);
      });

      test('startPage < 1 -> degenerate', () {
        final plan = planDigest(
          chapters: const [(title: 'X', startPage: 0, endPage: 10)],
          totalPages: 10,
        );
        expect(plan.usedFallback, isTrue);
        expect(plan.jobs.single.startPage, 1);
        expect(plan.jobs.single.endPage, 10);
      });

      test('endPage > totalPages -> degenerate', () {
        final plan = planDigest(
          chapters: const [(title: 'X', startPage: 1, endPage: 60)],
          totalPages: 50,
        );
        expect(plan.usedFallback, isTrue);
        expect(plan.jobs.single.endPage, 50);
      });

      test('reversed range (start > end) -> degenerate', () {
        final plan = planDigest(
          chapters: const [(title: 'X', startPage: 20, endPage: 10)],
          totalPages: 30,
        );
        expect(plan.usedFallback, isTrue);
      });

      test('overlapping chapters -> degenerate', () {
        final plan = planDigest(
          chapters: const [
            (title: 'A', startPage: 1, endPage: 10),
            (title: 'B', startPage: 5, endPage: 20),
          ],
          totalPages: 20,
        );
        expect(plan.usedFallback, isTrue);
      });

      test('fallback is also sub-split for a dev-sized book', () {
        final plan = planDigest(
          chapters: const [],
          totalPages: 300,
          maxTokensPerCall: 85320,
        );
        expect(plan.usedFallback, isTrue);
        expect(plan.jobs, hasLength(3));
        expect(plan.jobs.first.title, isNull);
      });
    },
  );

  group('planDigest — edge cases / parameter validation', () {
    test('totalPages < 1 -> empty plan (no jobs)', () {
      final zero = planDigest(chapters: const [], totalPages: 0);
      expect(zero.jobs, isEmpty);
      expect(zero.usedFallback, isFalse);
      expect(zero.chapterCount, 0);
      expect(planDigest(chapters: const [], totalPages: -5).jobs, isEmpty);
    });

    test('invalid parameters -> ArgumentError', () {
      expect(
        () =>
            planDigest(chapters: const [], totalPages: 10, maxTokensPerCall: 0),
        throwsArgumentError,
      );
      expect(
        () => planDigest(chapters: const [], totalPages: 10, charsPerPage: 0),
        throwsArgumentError,
      );
      expect(
        () => planDigest(chapters: const [], totalPages: 10, charsPerToken: 0),
        throwsArgumentError,
      );
    });

    test(
      'a gap between chapters does NOT make the plan degenerate (front matter s1-12)',
      () {
        // In the Mir pattern s1-12 belongs to no chapter; the plan is still valid --
        // the gap is a fact the coverage layer (coverage_manifest) will report.
        final plan = planDigest(
          chapters: const [(title: 'A', startPage: 13, endPage: 20)],
          totalPages: 20,
        );
        expect(plan.usedFallback, isFalse);
        expect(plan.jobs, hasLength(1));
      },
    );
  });
}
