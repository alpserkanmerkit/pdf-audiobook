import 'dart:async';
import 'package:flutter/material.dart';

import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/src/theme/palette.dart';
import 'package:sesli_kitap/src/turkish_case.dart';
import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({
    required this.books,
    required this.onAddBook,
    required this.onOpenBook,
    super.key,
    this.onOpenSettings,
    this.onOpenNotebook,
    this.onOpenDiscover,
    this.onOpenTutor,
    this.onDeleteBook,
  });

  final List<Book> books;
  final VoidCallback onAddBook;
  final void Function(Book) onOpenBook;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenNotebook;
  final VoidCallback? onOpenDiscover;

  /// Opens the tutor screen (TutorScreen); the school button in the title row.
  final VoidCallback? onOpenTutor;

  /// The long-pressed card carries both its [Book] and its POSITION on the shelf
  /// (index). If two records share the same id/hash (same file added twice),
  /// deleting must target only the touched card; matching by id must not delete ALL of them.
  final void Function(int index, Book book)? onDeleteBook;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final settings = AppSettingsScope.of(context);
    final firstBook = books.isNotEmpty ? books.first : null;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row: greeting + shortcuts on the same line, "Your library"
            // below at FULL width (in the field, on a device, when it shared a
            // line with the shortcuts it was split into two lines). On a narrow
            // screen / large font it shrinks instead of wrapping (FittedBox.scaleDown).
            Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'GOOD EVENING',
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 1.6,
                        color: palette.text3,
                      ),
                    ),
                  ),
                ),
                // 48dp tap target: buttons are 48 wide; with spacing 8->4 the
                // visual gap between the 44dp circles (8dp) stays the same.
                _IconButton(
                  icon: Icons.explore,
                  tooltip: 'Discover',
                  onPressed: onOpenDiscover,
                  palette: palette,
                ),
                const SizedBox(width: 4),
                _IconButton(
                  key: const Key('library-open-tutor'),
                  icon: Icons.school,
                  tooltip: 'Tutor',
                  onPressed: onOpenTutor,
                  palette: palette,
                ),
                const SizedBox(width: 4),
                _IconButton(
                  icon: Icons.bookmark_border,
                  tooltip: 'Notebook',
                  onPressed: onOpenNotebook,
                  palette: palette,
                ),
                const SizedBox(width: 4),
                _IconButton(
                  icon: Icons.tune,
                  tooltip: 'Settings',
                  onPressed: onOpenSettings,
                  palette: palette,
                ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'Your library',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 33,
                  fontFamily: serifDisplayFamily(settings),
                  color: palette.text,
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Continue card (first book)
            if (firstBook != null)
              _ContinueCard(
                book: firstBook,
                palette: palette,
                onOpenBook: onOpenBook,
              ),
            const SizedBox(height: 32),
            // Shelf heading
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Flexible: on a narrow screen with large text the "Add book"
                // button gets the space and the row does not overflow (it overflowed by 24 px at 360 dp / 1.3 scale).
                Flexible(
                  child: Text(
                    'Your shelf',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontFamily: serifTextFamily(settings),
                      fontStyle: FontStyle.italic,
                      color: palette.text,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onAddBook,
                  icon: Icon(Icons.add, color: palette.accent, size: 18),
                  label: Text(
                    'Add book',
                    style: TextStyle(color: palette.accent, fontSize: 14),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Shelf grid (shows the "no books" message when empty)
            if (books.isEmpty)
              _EmptyLibraryMessage(palette: palette)
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 18,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.62,
                ),
                itemCount: books.length,
                itemBuilder: (context, index) {
                  final book = books[index];
                  return GestureDetector(
                    onTap: () => onOpenBook(book),
                    onLongPress: onDeleteBook == null
                        ? null
                        : () => _confirmDeleteBook(
                            context,
                            index,
                            book,
                            onDeleteBook!,
                          ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cover. Flexible: with large text the lines below (progress
                        // percentage) grow; the cover keeps its 5/7 ratio and shrinks
                        // by a few px so the cell does not overflow (narrow-screen sweep).
                        Flexible(
                          child: AspectRatio(
                            aspectRatio: 5 / 7,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(9),
                                gradient: LinearGradient(
                                  colors: [
                                    kCovers[book.coverIndex].$1,
                                    kCovers[book.coverIndex].$2,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Spacer(),
                                    Text(
                                      book.title,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontFamily: serifTextFamily(settings),
                                        color: palette.text,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      maxLines: 2,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      turkishUpper(book.author),
                                      style: TextStyle(
                                        fontSize: 10,
                                        letterSpacing: 1,
                                        color: palette.text2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // progress bar
                        LinearProgressIndicator(
                          value: book.progressPercent / 100,
                          backgroundColor: palette.border,
                          valueColor: AlwaysStoppedAnimation(palette.accent),
                          minHeight: 1,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '%${book.progressPercent}',
                          style: TextStyle(fontSize: 11, color: palette.text3),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Delete confirmation opened by a long press. If accepted, [onDeleteBook] is called;
/// if cancelled, nothing changes (idempotent -- the dialog closes).
void _confirmDeleteBook(
  BuildContext context,
  int index,
  Book book,
  void Function(int index, Book book) onDeleteBook,
) {
  final pending = showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete book?'),
      content: Text(
        '«${book.title}» will be permanently deleted (including progress). '
        'This action cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('confirm-delete-book'),
          onPressed: () {
            Navigator.of(ctx).pop();
            onDeleteBook(index, book);
          },
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  unawaited(pending);
}

class _EmptyLibraryMessage extends StatelessWidget {
  const _EmptyLibraryMessage({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.menu_book, size: 40, color: palette.text3),
          const SizedBox(height: 12),
          Text(
            'No books yet',
            style: TextStyle(fontSize: 15, color: palette.text2),
          ),
          const SizedBox(height: 4),
          Text(
            'Start by adding a PDF with "Add book" above.',
            style: TextStyle(fontSize: 13, color: palette.text3),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.palette,
    super.key,
    this.tooltip,
    this.onPressed,
  });
  final IconData icon;
  final String? tooltip;
  final VoidCallback? onPressed;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    // Visual: 44dp bordered circle. Tap target: IconButton 48x48 (the circle is
    // the icon's FRAME), so the look is the same and the hit area is 48dp.
    return IconButton(
      icon: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.surface,
          border: Border.all(color: palette.border),
        ),
        child: Icon(icon, size: 24, color: palette.text),
      ),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.book,
    required this.palette,
    required this.onOpenBook,
  });
  final Book book;
  final AppPalette palette;
  final void Function(Book) onOpenBook;

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    return GestureDetector(
      onTap: () => onOpenBook(book),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: palette.glass,
          border: Border.all(color: palette.border),
          boxShadow: [
            BoxShadow(
              color: palette.text.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(2, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Cover
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 92,
                height: 128,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      kCovers[book.coverIndex].$1,
                      kCovers[book.coverIndex].$2,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Text(
                    book.title,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: serifTextFamily(settings),
                      color: palette.text,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Right side content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CONTINUE',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      color: palette.accent,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '№ ${book.id}',
                    style: TextStyle(fontSize: 12, color: palette.text2),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    book.title,
                    style: TextStyle(
                      fontSize: 21,
                      fontFamily: serifTextFamily(settings),
                      color: palette.text,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    book.author,
                    style: TextStyle(fontSize: 13, color: palette.text2),
                  ),
                  const SizedBox(height: 12),
                  // progress ring + text
                  Row(
                    children: [
                      SizedBox(
                        width: 50,
                        height: 50,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: book.progressPercent / 100,
                              valueColor: AlwaysStoppedAnimation(
                                palette.accent,
                              ),
                              backgroundColor: palette.border,
                              strokeWidth: 4,
                            ),
                            Icon(
                              Icons.play_arrow,
                              color: palette.accent,
                              size: 24,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${book.chapterLabel} · %${book.progressPercent} · pages left',
                          style: TextStyle(fontSize: 13, color: palette.text3),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
