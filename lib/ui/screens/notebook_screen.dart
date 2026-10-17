import 'package:flutter/material.dart';

import 'package:sesli_kitap/ui/state/app_settings.dart';
import 'package:sesli_kitap/ui/theme/app_theme.dart';
import 'package:sesli_kitap/ui/widgets/share_quote_sheet.dart';

class NotebookQuote {
  const NotebookQuote({
    required this.text,
    required this.page,
    required this.book,
  });
  final String text;
  final int page;
  final String book;
}

class NotebookScreen extends StatelessWidget {
  const NotebookScreen({super.key, this.quotes = const [], this.onShare});

  final List<NotebookQuote> quotes;
  final void Function(NotebookQuote)? onShare;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final firstBook = quotes.isNotEmpty ? quotes.first.book : null;
    final count = quotes.length;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'NOTEBOOK / Quote Notebook',
          style: TextStyle(color: palette.text, fontWeight: FontWeight.w600),
        ),
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              firstBook != null
                  ? '«$firstBook» · $count quotes'
                  : '$count quotes',
              style: TextStyle(color: palette.text2, fontSize: 14),
            ),
          ),
          const SizedBox(height: 12),
          // Quote list or empty-state text
          Expanded(
            child: quotes.isEmpty
                ? Center(
                    child: Text(
                      'You have not saved any quotes yet.',
                      style: TextStyle(color: palette.text3),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: quotes.length,
                    itemBuilder: (context, index) {
                      final q = quotes[index];
                      return _QuoteCard(
                        quote: q,
                        palette: palette,
                        onShare: onShare,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({
    required this.quote,
    required this.palette,
    required this.onShare,
  });

  final NotebookQuote quote;
  final AppPalette palette;
  final void Function(NotebookQuote)? onShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Decorative quote mark
          Text(
            '"',
            style: TextStyle(
              fontSize: 48,
              height: 0.5,
              color: palette.accent.withValues(alpha: 0.2),
            ),
          ),
          const SizedBox(height: 4),
          // Quote text
          Text(
            quote.text,
            style: TextStyle(
              fontSize: 16,
              fontStyle: FontStyle.italic,
              color: palette.text,
              fontFamily: serifTextFamily(AppSettingsScope.of(context)),
            ),
          ),
          const SizedBox(height: 12),
          // Book and page
          Text(
            '${quote.book} · p.${quote.page}',
            style: TextStyle(color: palette.text3, fontSize: 13),
          ),
          // Share button
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onShare != null
                  ? () => onShare!(quote)
                  : () => showShareQuoteSheet(
                      context,
                      text: quote.text,
                      page: quote.page,
                      book: quote.book,
                    ),
              child: Text('Share', style: TextStyle(color: palette.accent)),
            ),
          ),
        ],
      ),
    );
  }
}
