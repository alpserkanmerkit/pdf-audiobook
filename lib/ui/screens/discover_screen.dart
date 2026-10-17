import 'package:flutter/material.dart';

import 'package:sesli_kitap/src/library/library_store.dart';
import 'package:sesli_kitap/src/theme/palette.dart';
import 'package:sesli_kitap/src/turkish_case.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';

class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key, this.books, this.onOpenBook});

  final List<Book>? books;

  /// Callback that opens the book when its cover is tapped (same as in the
  /// library). If not provided, the covers stay non-tappable (the old dead-affordance behavior).
  final void Function(Book book)? onOpenBook;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final list = books ?? const <Book>[];
    final chips = [
      'Architecture',
      'Philosophy',
      'Design',
      'Silence',
      'Aesthetics',
    ];

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('DISCOVER / For you'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -- Topic chips --
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: chips.map((chip) {
                return Chip(
                  label: Text(chip),
                  backgroundColor: palette.surface,
                  side: BorderSide(color: palette.border),
                  labelStyle: TextStyle(color: palette.text2, fontSize: 12),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // -- Recommended heading --
            Text(
              'Recommended',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.3,
                color: palette.text3,
              ),
            ),
            const SizedBox(height: 12),

            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'There are no books in your library yet.',
                  style: TextStyle(fontSize: 13, color: palette.text3),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 5 / 7,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final kitap = list[index];
                  final (c1, c2) = kCovers[kitap.coverIndex];
                  return GestureDetector(
                    key: ValueKey('discover-${kitap.hash}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onOpenBook == null ? null : () => onOpenBook!(kitap),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: LinearGradient(
                                colors: [c1, c2],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          kitap.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontFamily: 'Serif',
                            fontWeight: FontWeight.w600,
                            color: palette.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          turkishUpper(kitap.author),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
