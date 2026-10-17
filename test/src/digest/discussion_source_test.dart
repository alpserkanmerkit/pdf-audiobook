// RED-once oracle test (Wave-A / PR-A): discussion SOURCE SELECTOR layer.
// Spec: internal design note §3-C/§5/§6 --
// the block sent to the discussion = book summary + the 2-3 chapter summaries closest to the
// topic + (passages supplied by the caller). The relevance score is PURE and DETERMINISTIC
// (Turkish lowercase term matching in title+summary texts; the mini-LLM selection option goes
// to Wave-B). The output budget is a hard cap (maxChars).
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/digest/digest_model.dart';
import 'package:sesli_kitap/src/digest/discussion_source.dart';

const String _header =
    'SOURCE MATERIAL (book digest):\n\n=== BOOK SUMMARY ===\n';

BookDigest _digest({
  String bookSummary = 'Book summary.',
  List<ChapterDigest> chapters = const [],
}) => BookDigest(
  bookHash: 'h',
  createdAtMs: 0,
  chapters: chapters,
  bookSummary: bookSummary,
);

ChapterDigest _ch(
  int index, {
  String? title,
  String summary = '',
  int start = 1,
  int end = 10,
}) => ChapterDigest(
  chapterIndex: index,
  title: title,
  startPage: start,
  endPage: end,
  pagesProcessed: end - start + 1,
  summary: summary,
);

void main() {
  group('scoreChaptersForTopic — deterministic relevance score', () {
    test('title match (x3) outweighs summary match', () {
      final d = _digest(
        chapters: [
          _ch(0, title: 'Kıskançlık', summary: 'bambaska bir konu'),
          _ch(1, title: 'Uyum', summary: 'kıskançlık burada gecer'),
        ],
      );
      final scored = scoreChaptersForTopic(digest: d, topic: 'kıskançlık');
      expect(scored, hasLength(2));
      expect(scored.first.chapter.chapterIndex, 0);
      expect(scored.first.score, 3);
      expect(scored[1].score, 1);
    });

    test('a term that appears more often gives a higher score', () {
      final d = _digest(
        chapters: [
          _ch(0, title: 'A', summary: 'korku bir kez'),
          _ch(1, title: 'B', summary: 'korku korku iki kez'),
        ],
      );
      final scored = scoreChaptersForTopic(digest: d, topic: 'korku');
      expect(scored.first.chapter.chapterIndex, 1);
      expect(scored.first.score, 2);
      expect(scored[1].score, 1);
    });

    test(
      'on equal score, lower chapterIndex comes first (deterministic order)',
      () {
        final d = _digest(
          chapters: [
            _ch(0, title: 'A', summary: 'korku'),
            _ch(1, title: 'B', summary: 'korku'),
          ],
        );
        final scored = scoreChaptersForTopic(digest: d, topic: 'korku');
        expect(scored.map((s) => s.chapter.chapterIndex).toList(), [0, 1]);
      },
    );

    test('Turkish uppercase is case-folded correctly (İ->i, I->ı)', () {
      final d = _digest(
        chapters: [_ch(0, title: 'Narsisizm', summary: 'kıskançlık kokleri')],
      );
      final scored = scoreChaptersForTopic(
        digest: d,
        topic: 'KISKANÇLIK VE NARSİSİZM',
      );
      // 'NARSİSİZM' -> 'narsisizm' in the title (3), 'KISKANÇLIK' -> 'kıskançlık' in the summary (1).
      expect(scored.single.score, 4);
    });

    test('suffixed body text is matched by substring', () {
      final d = _digest(
        chapters: [_ch(0, summary: 'narsisizmin kokleri derindir')],
      );
      final scored = scoreChaptersForTopic(digest: d, topic: 'narsisizm');
      expect(scored.single.score, 1);
    });

    test('stopwords and words shorter than 3 letters are not terms', () {
      final d = _digest(
        chapters: [_ch(0, summary: 'hakkında ve bu da soz gecmez')],
      );
      final scored = scoreChaptersForTopic(
        digest: d,
        topic: 'aşk hakkında ve bu',
      );
      // 'hakkında' is a stopword, 've'/'bu' are short: only 'aşk' is a term; it is absent too.
      expect(scored.single.score, 0);
    });

    test('a repeated term counts once (no double counting)', () {
      final d = _digest(chapters: [_ch(0, summary: 'aşk')]);
      final scored = scoreChaptersForTopic(digest: d, topic: 'aşk aşk aşk');
      expect(scored.single.score, 1);
    });

    test('all chapters are returned with a score (including 0)', () {
      final d = _digest(
        chapters: [
          _ch(0, title: 'A'),
          _ch(1, title: 'B'),
          _ch(2, title: 'C'),
        ],
      );
      final scored = scoreChaptersForTopic(digest: d, topic: 'eslesmeyen');
      expect(scored, hasLength(3));
      expect(scored.map((s) => s.score).toSet(), {0});
    });
  });

  group('selectRelevantChapters', () {
    BookDigest fourChapters() => _digest(
      chapters: [
        _ch(0, title: 'Ofke', summary: 'ofke ofke ofke'),
        _ch(1, title: 'Korku', summary: 'korku konusu'),
        _ch(2, title: 'Korku Kokleri', summary: 'korku korku'),
        _ch(3, title: 'Uyum', summary: 'korku hic yok aslinda var: korku'),
      ],
    );

    test('at most maxChapters chapters with score > 0, in score order', () {
      final picked = selectRelevantChapters(
        digest: fourChapters(),
        topic: 'korku',
        maxChapters: 2,
      );
      // Scores: ch1=3+1=4, ch2=3+2=5, ch3=2 -> first two: [ch2, ch1].
      expect(picked.map((c) => c.chapterIndex).toList(), [2, 1]);
    });

    test('default maxChapters = 3 (report: 2-3 chapter summaries)', () {
      final picked = selectRelevantChapters(
        digest: fourChapters(),
        topic: 'korku',
      );
      expect(picked.map((c) => c.chapterIndex).toList(), [2, 1, 3]);
    });

    test('maxChapters <= 0 -> empty', () {
      expect(
        selectRelevantChapters(
          digest: fourChapters(),
          topic: 'korku',
          maxChapters: 0,
        ),
        isEmpty,
      );
    });

    test('no match -> empty (a chapter with score 0 is NOT selected)', () {
      expect(
        selectRelevantChapters(digest: fourChapters(), topic: 'kuantum'),
        isEmpty,
      );
    });
  });

  group('selectDigestContext — source material block', () {
    BookDigest smallBook() => _digest(
      bookSummary: 'SUMMARY',
      chapters: [
        _ch(0, title: 'Aşk', summary: 'aşk özeti', end: 4),
        _ch(1, title: 'Korku', summary: 'aşk korku', start: 5),
      ],
    );
    const sec0 = '\n\n=== CHAPTER: Aşk (s.1-4) ===\naşk özeti';
    const sec1 = '\n\n=== CHAPTER: Korku (s.5-10) ===\naşk korku';
    const pas1 = '\n\n=== SELECTED PASSAGES ===\nP1';
    const pas2 = '\n\nP2';

    test('format: summary + relevant chapters + passages', () {
      final out = selectDigestContext(
        digest: smallBook(),
        topic: 'aşk',
        maxChars: 10000,
        passages: const ['P1', 'P2'],
      );
      expect(out, '${_header}SUMMARY$sec0$sec1$pas1$pas2');
    });

    test('book with no topic match: only the book summary', () {
      final out = selectDigestContext(
        digest: smallBook(),
        topic: 'kuantum fiziği',
        maxChars: 10000,
      );
      expect(out, '${_header}SUMMARY');
      expect(out.contains('=== CHAPTER'), isFalse);
    });

    test('budget trap: output never exceeds maxChars at any budget', () {
      const full = '${_header}SUMMARY$sec0$sec1$pas1$pas2';
      for (final budget in [1, 5, 20, _header.length, 100, full.length]) {
        final out = selectDigestContext(
          digest: smallBook(),
          topic: 'aşk',
          maxChars: budget,
          passages: const ['P1', 'P2'],
        );
        expect(out.length, lessThanOrEqualTo(budget), reason: 'budget $budget');
      }
    });

    test(
      'with a small budget the block is trimmed from the start (hard cap)',
      () {
        final out = selectDigestContext(
          digest: smallBook(),
          topic: 'aşk',
          maxChars: 10,
        );
        expect(out, _header.substring(0, 10));
      },
    );

    test('maxChars <= 0 -> empty block', () {
      expect(
        selectDigestContext(digest: smallBook(), topic: 'aşk', maxChars: 0),
        '',
      );
      expect(
        selectDigestContext(digest: smallBook(), topic: 'aşk', maxChars: -5),
        '',
      );
    });

    test('if the budget only fits the first chapter, the rest is dropped', () {
      const budget = '${_header}SUMMARY$sec0'.length;
      final out = selectDigestContext(
        digest: smallBook(),
        topic: 'aşk',
        maxChars: budget,
        passages: const ['P1'],
      );
      expect(out, '${_header}SUMMARY$sec0');
    });

    test(
      'passages are dropped if they do not fit the budget (chapters are kept)',
      () {
        const budget = '${_header}SUMMARY$sec0$sec1'.length;
        final out = selectDigestContext(
          digest: smallBook(),
          topic: 'aşk',
          maxChars: budget,
          passages: const ['P1'],
        );
        expect(out, '${_header}SUMMARY$sec0$sec1');
        expect(out.contains('SELECTED PASSAGES'), isFalse);
      },
    );

    test('if the second passage does not fit, only the first is included', () {
      const budget = '${_header}SUMMARY$sec0$sec1$pas1'.length;
      final out = selectDigestContext(
        digest: smallBook(),
        topic: 'aşk',
        maxChars: budget,
        passages: const ['P1', 'P2'],
      );
      expect(out, '${_header}SUMMARY$sec0$sec1$pas1');
      expect(out.contains('P2'), isFalse);
    });

    test(
      'chapter label without a title: "Chapter N" (1-based, human-readable)',
      () {
        final d = _digest(
          bookSummary: 'K',
          chapters: [
            _ch(4, summary: 'aşk', start: 30, end: 40),
            _ch(5, title: '   ', summary: 'aşk aşk', start: 41, end: 50),
          ],
        );
        final out = selectDigestContext(
          digest: d,
          topic: 'aşk',
          maxChars: 10000,
        );
        expect(out.contains('=== CHAPTER: Chapter 5 (s.30-40) ==='), isTrue);
        expect(out.contains('=== CHAPTER: Chapter 6 (s.41-50) ==='), isTrue);
      },
    );

    test(
      'without passages the block ends without passages (default empty)',
      () {
        final out = selectDigestContext(
          digest: smallBook(),
          topic: 'aşk',
          maxChars: 10000,
        );
        expect(out, '${_header}SUMMARY$sec0$sec1');
        expect(out.contains('SELECTED PASSAGES'), isFalse);
      },
    );
  });
}
