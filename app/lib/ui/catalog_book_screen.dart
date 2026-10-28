import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/languages.dart';
import '../data/catalog.dart';
import '../data/library_store.dart';
import '../data/settings_store.dart';
import '../models/book.dart';
import 'book_actions.dart';
import 'book_details_screen.dart';
import 'widgets/book_cover.dart';

/// Details of a free book from the catalog, before it is downloaded.
class CatalogBookScreen extends StatefulWidget {
  final CatalogBook book;
  const CatalogBookScreen({super.key, required this.book});

  @override
  State<CatalogBookScreen> createState() => _CatalogBookScreenState();
}

class _CatalogBookScreenState extends State<CatalogBookScreen> {
  bool _busy = false;

  Future<Book?> _download({bool temporary = false}) async {
    final library = context.read<LibraryStore>();
    setState(() => _busy = true);
    try {
      return await library.addFromCatalog(widget.book, temporary: temporary);
    } catch (e) {
      if (mounted) await showErrorDialog(context, 'Could not get this book', e);
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final settings = context.watch<SettingsStore>();
    final owned = library.byGutenbergId(widget.book.id);
    final progress = library.pending['pg${widget.book.id}'];
    final b = widget.book;
    final theme = Theme.of(context);
    final preferred = languageByCode(settings.preferredLang);
    final bookLang = languageByIso(b.languages.isNotEmpty ? b.languages.first : null);
    final canTranslateToPreferred = preferred != null && preferred.code != bookLang?.code;

    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Center(child: BookCover(title: b.title, author: b.authorLine, urls: b.coverUrls, cacheKey: b.coverKey, width: 150)),
          const SizedBox(height: 20),
          Text(b.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(fontFamily: 'serif', fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(b.authorLine, textAlign: TextAlign.center, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '${bookLang?.name ?? b.languages.join(', ')} · Free · Public domain',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_busy || progress != null) ...[
                  LinearProgressIndicator(value: (progress ?? 0) > 0 ? progress : null),
                  const SizedBox(height: 8),
                  const Center(child: Text('Getting the book…')),
                ] else if (owned != null) ...[
                  FilledButton.icon(
                    icon: const Icon(Icons.menu_book),
                    label: const Text('Read'),
                    onPressed: () => openReader(context, owned),
                  ),
                  const SizedBox(height: 10),
                  if (owned.temporary)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.library_add),
                      label: const Text('Save to my library'),
                      onPressed: () async {
                        await library.keep(owned);
                        if (context.mounted) showMessage(context, 'Saved to your library — available offline');
                      },
                    )
                  else
                    OutlinedButton.icon(
                      icon: const Icon(Icons.info_outline),
                      label: const Text('Translations & details'),
                      onPressed: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => BookDetailsScreen(bookId: owned.id))),
                    ),
                ] else ...[
                  FilledButton.icon(
                    icon: const Icon(Icons.menu_book),
                    label: const Text('Read now'),
                    onPressed: () async {
                      final book = await _download(temporary: true);
                      if (book != null && context.mounted) await openReader(context, book, original: true);
                    },
                  ),
                  const SizedBox(height: 10),
                  if (canTranslateToPreferred) ...[
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.translate),
                      label: Text('Read in ${preferred.nativeName}'),
                      onPressed: () async {
                        final book = await _download();
                        if (book == null || !context.mounted) return;
                        final lang = await translateBook(context, book, lang: preferred);
                        if (lang != null && context.mounted) await openReader(context, book, lang: lang);
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                  OutlinedButton.icon(
                    icon: const Icon(Icons.library_add),
                    label: const Text('Save to my library'),
                    onPressed: () async {
                      final book = await _download();
                      if (book != null && context.mounted) {
                        showMessage(context, 'Saved “${book.title}” — available offline in your library');
                      }
                    },
                  ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    icon: const Icon(Icons.language),
                    label: const Text('Translate into another language…'),
                    onPressed: () async {
                      final book = await _download();
                      if (book == null || !context.mounted) return;
                      final lang = await translateBook(context, book);
                      if (lang != null && context.mounted) await openReader(context, book, lang: lang);
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '“Read now” opens the book right away. Save it to keep it in your library.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 28),
          if (b.rank > 0)
            Text('#${b.rank} most downloaded on Project Gutenberg', style: theme.textTheme.bodySmall),
          Text('Project Gutenberg book #${b.id}', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
