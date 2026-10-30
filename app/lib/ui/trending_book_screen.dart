import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/discover.dart';
import 'book_actions.dart';
import 'widgets/book_cover.dart';
import '../l10n/strings.dart';

/// A popular book sold by its publisher: shows where to buy or borrow it, and
/// how to add your own copy to BookIt.
class TrendingBookScreen extends StatelessWidget {
  final TrendingBook book;
  const TrendingBookScreen({super.key, required this.book});

  bool get _india => Platform.localeName.toUpperCase().endsWith('_IN');

  Uri _search(String base) => Uri.parse('$base${Uri.encodeQueryComponent('${book.title} ${book.author}')}');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stores = <(IconData, String, Uri)>[
      (Icons.shop_outlined, 'Google Play Books', _search('https://play.google.com/store/search?c=books&q=')),
      (
        Icons.shopping_bag_outlined,
        'Amazon Kindle',
        _search(_india ? 'https://www.amazon.in/s?i=digital-text&k=' : 'https://www.amazon.com/s?i=digital-text&k=')
      ),
      (Icons.local_library_outlined, 'Borrow from Open Library', Uri.parse(book.openLibraryUrl)),
      (Icons.account_balance_outlined, 'Find in a library near you', _search('https://search.worldcat.org/search?q=')),
    ];

    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Center(child: BookCover(title: book.title, author: book.author, urls: book.coverUrls, cacheKey: book.coverKey, width: 150)),
          const SizedBox(height: 20),
          Text(book.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(fontFamily: 'serif', fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(book.author, textAlign: TextAlign.center, style: theme.textTheme.titleSmall),
          if (book.year != null)
            Text('First published ${book.year}', textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          const SizedBox(height: 20),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Card(
                  color: theme.colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      'This book is sold by its publisher, so it isn\'t free in BookIt. '
                      'Get it from a store or a library below. If your copy is DRM-free, add it to BookIt to read '
                      'and translate it privately in your language.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                for (final s in stores)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton.icon(
                      icon: Icon(s.$1),
                      label: Text(s.$2),
                      style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.all(14)),
                      onPressed: () => launchUrl(s.$3, mode: LaunchMode.externalApplication),
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.add),
                  label: Text(tr('I have this book — add it to BookIt')),
                  onPressed: () => importBook(context),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          Text(tr('Book details and cover from Open Library.'), textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// A cover tile for a trending book.
class TrendingTile extends StatelessWidget {
  final TrendingBook book;
  final double width;
  const TrendingTile({super.key, required this.book, required this.width});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TrendingBookScreen(book: book))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          BookCover(title: book.title, author: book.author, urls: book.coverUrls, cacheKey: book.coverKey, width: width),
          const SizedBox(height: 6),
          Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
        ]),
      ),
    );
  }
}
