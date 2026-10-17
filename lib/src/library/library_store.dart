import 'dart:convert';

const int _kCoverCount = 6;

/// ROOT-CAUSE FIX (A6, device proof 08.07): `Book.progressPercent` (in the
/// books_v1 JSON blob) is NEVER updated at WRITE time -- the reader writes its
/// progress to the `progress_<hash>` prefs key (the current PAGE number) (see
/// reader_screen.dart). The library screen merges these two sources at READ
/// time (see app_shell.dart _libraryBooks); this PURE function makes the SAME
/// formula (page/totalPages -> percent, clamped 0..100) reusable (the A6 topic
/// suggestion needs this formula: since the raw progressPercent is ALWAYS 0,
/// using it meant the topic suggestion never fired on the device).
int effectiveProgressPercent({required int? page, required int totalPages}) {
  if (page == null || totalPages <= 0) return 0;
  return ((page / totalPages) * 100).round().clamp(0, 100);
}

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.chapterLabel,
    required this.progressPercent,
    required this.totalPages,
    required this.coverIndex,
    this.hash = '',
    this.filePath = '',
    this.language = 'tr',
  });

  factory Book.fromJson(Map<String, dynamic> json) => Book(
    id: json['id'] as String,
    title: json['title'] as String,
    author: json['author'] as String,
    chapterLabel: json['chapterLabel'] as String,
    progressPercent: json['progressPercent'] as int,
    totalPages: json['totalPages'] as int,
    coverIndex: (json['coverIndex'] as int).clamp(0, _kCoverCount - 1),
    hash: json.containsKey('hash') ? (json['hash'] as String) : '',
    filePath: json.containsKey('filePath') ? (json['filePath'] as String) : '',
    language: json.containsKey('language')
        ? (json['language'] as String)
        : 'tr',
  );
  final String id;
  final String title;
  final String author;
  final String chapterLabel;
  final int progressPercent;
  final int totalPages;
  final int coverIndex;
  final String hash;
  final String filePath;

  /// Phase 2 (English TTS support): chosen manually when adding a book ('tr'/'en').
  /// Default 'tr' -- existing/old records (when the field is absent) are not affected.
  final String language;

  Book withProgress(int percent) => Book(
    id: id,
    title: title,
    author: author,
    chapterLabel: chapterLabel,
    progressPercent: percent.clamp(0, 100),
    totalPages: totalPages,
    coverIndex: coverIndex,
    hash: hash,
    filePath: filePath,
    language: language,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'chapterLabel': chapterLabel,
    'progressPercent': progressPercent,
    'totalPages': totalPages,
    'coverIndex': coverIndex,
    'hash': hash,
    'filePath': filePath,
    'language': language,
  };
}

List<Book> seedBooks() => [
  const Book(
    id: 'b1',
    title: 'Sessizliğin Mimarisi',
    author: 'D. Karaca',
    chapterLabel: 'Bölüm 4',
    progressPercent: 38,
    totalPages: 318,
    coverIndex: 0,
  ),
  const Book(
    id: 'b2',
    title: 'Düşüncenin Sınırları',
    author: 'A. Vural',
    chapterLabel: 'Bölüm 2',
    progressPercent: 16,
    totalPages: 264,
    coverIndex: 1,
  ),
  const Book(
    id: 'b3',
    title: 'Zamanın Dokusu',
    author: 'M. Şahin',
    chapterLabel: 'Bölüm 7',
    progressPercent: 72,
    totalPages: 412,
    coverIndex: 2,
  ),
  const Book(
    id: 'b4',
    title: 'Anlamın İzinde',
    author: 'S. Demir',
    chapterLabel: 'Önsöz',
    progressPercent: 4,
    totalPages: 198,
    coverIndex: 3,
  ),
  const Book(
    id: 'b5',
    title: 'Bilincin Kıyısı',
    author: 'E. Aydın',
    chapterLabel: 'Bölüm 9',
    progressPercent: 91,
    totalPages: 356,
    coverIndex: 4,
  ),
  const Book(
    id: 'b6',
    title: 'Yavaşlığın Sanatı',
    author: 'L. Toprak',
    chapterLabel: 'Bölüm 1',
    progressPercent: 22,
    totalPages: 240,
    coverIndex: 5,
  ),
];

/// Removes the book at [index] from [books] ([index] outside the valid range
/// returns an unchanged copy -- as a NEW List instance). DELIBERATELY
/// index-based (NOT id-based): if two records share the same id/hash (the same
/// file was added twice), id matching would delete BOTH -- an index targets only
/// the single touched card (review finding 2).
List<Book> removeBookAt(List<Book> books, int index) {
  if (index < 0 || index >= books.length) return List<Book>.of(books);
  return List<Book>.of(books)..removeAt(index);
}

String encodeBooks(List<Book> books) =>
    jsonEncode(books.map((b) => b.toJson()).toList());

List<Book> decodeBooks(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const [];
  }
  if (decoded is! List) return const [];
  final books = <Book>[];
  for (final e in decoded) {
    try {
      books.add(Book.fromJson(e as Map<String, dynamic>));
    } on Object catch (_) {}
  }
  return books;
}
