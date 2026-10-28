import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/languages.dart';
import '../data/library_store.dart';
import '../models/book.dart';
import '../translation/translation_service.dart';
import 'book_actions.dart';
import 'book_details_screen.dart';
import 'widgets/book_cover.dart';
import 'widgets/format.dart';

enum _Sort { recent, title, author }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  _Sort _sort = _Sort.recent;
  bool _translatedOnly = false;
  bool _grid = true;
  String _query = '';
  bool _searching = false;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    context.watch<TranslationService>();
    var books = library.books.toList();
    if (_translatedOnly) books = books.where((b) => library.translationLangs(b.id).isNotEmpty).toList();
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      books = books.where((b) => b.title.toLowerCase().contains(q) || b.author.toLowerCase().contains(q)).toList();
    }
    switch (_sort) {
      case _Sort.recent:
        books.sort((a, b) => (b.lastOpenedAt ?? b.addedAt).compareTo(a.lastOpenedAt ?? a.addedAt));
      case _Sort.title:
        books.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case _Sort.author:
        books.sort((a, b) => a.author.toLowerCase().compareTo(b.author.toLowerCase()));
    }
    final width = MediaQuery.sizeOf(context).width;
    final columns = (width / 150).floor().clamp(2, 8);

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Search your books', border: InputBorder.none),
                onChanged: (v) => setState(() => _query = v),
              )
            : const Text('Library'),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search your books',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _query = '';
            }),
          ),
          IconButton(
            tooltip: _grid ? 'List view' : 'Grid view',
            icon: Icon(_grid ? Icons.view_list : Icons.grid_view),
            onPressed: () => setState(() => _grid = !_grid),
          ),
          PopupMenuButton<_Sort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: (_) => const [
              PopupMenuItem(value: _Sort.recent, child: Text('Recent')),
              PopupMenuItem(value: _Sort.title, child: Text('Title')),
              PopupMenuItem(value: _Sort.author, child: Text('Author')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => importBook(context),
        icon: const Icon(Icons.add),
        label: const Text('Add a book'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: [
            FilterChip(
              label: const Text('All'),
              selected: !_translatedOnly,
              onSelected: (_) => setState(() => _translatedOnly = false),
            ),
            const SizedBox(width: 8),
            FilterChip(
              avatar: const Icon(Icons.translate, size: 16),
              label: const Text('Translated'),
              selected: _translatedOnly,
              onSelected: (_) => setState(() => _translatedOnly = true),
            ),
            const Spacer(),
            Text('${books.length} books', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        if (library.pending.isNotEmpty)
          for (final p in library.pending.entries)
            ListTile(
              leading: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
              title: const Text('Downloading book…'),
              subtitle: LinearProgressIndicator(value: p.value > 0 ? p.value : null),
            ),
        Expanded(
          child: books.isEmpty
              ? _Empty(translatedOnly: _translatedOnly)
              : _grid
                  ? GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 20,
                        crossAxisSpacing: 16,
                        childAspectRatio: 0.52,
                      ),
                      itemCount: books.length,
                      itemBuilder: (_, i) => _GridItem(book: books[i]),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 96),
                      itemCount: books.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 88),
                      itemBuilder: (_, i) => _ListItem(book: books[i]),
                    ),
        ),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  final bool translatedOnly;
  const _Empty({required this.translatedOnly});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.auto_stories_outlined, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(translatedOnly ? 'No translated books yet' : 'Your library is empty', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            translatedOnly
                ? 'Open a book and tap “Translate” to read it in your language.'
                : 'Get free classics from the “Free books” tab, or add your own EPUB or TXT file.',
            textAlign: TextAlign.center,
          ),
        ]),
      ),
    );
  }
}

void _openDetails(BuildContext context, Book book) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookDetailsScreen(bookId: book.id)));

class _LangBadges extends StatelessWidget {
  final Book book;
  const _LangBadges({required this.book});

  @override
  Widget build(BuildContext context) {
    final langs = context.read<LibraryStore>().translationLangs(book.id);
    if (langs.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Wrap(spacing: 4, runSpacing: 4, children: [
      for (final l in langs)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(languageByCode(l)?.nativeName ?? l, style: theme.textTheme.labelSmall),
        ),
    ]);
  }
}

class _GridItem extends StatelessWidget {
  final Book book;
  const _GridItem({required this.book});

  @override
  Widget build(BuildContext context) {
    final library = context.read<LibraryStore>();
    final job = context.read<TranslationService>().activeJobFor(book.id);
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, c) {
      return InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => openReader(context, book),
        onLongPress: () => _openDetails(context, book),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            BookCover(title: book.title, author: book.author, file: library.coverFile(book), width: c.maxWidth),
            if (book.position.progress > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(value: book.position.progress, minHeight: 3),
              ),
            Positioned(
              right: 2,
              top: 2,
              child: Material(
                color: Colors.black38,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _openDetails(context, book),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.more_vert, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
          if (job != null)
            Text('Translating ${percent(job.fraction)}', style: theme.textTheme.labelSmall)
          else
            _LangBadges(book: book),
        ]),
      );
    });
  }
}

class _ListItem extends StatelessWidget {
  final Book book;
  const _ListItem({required this.book});

  @override
  Widget build(BuildContext context) {
    final library = context.read<LibraryStore>();
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: BookCover(title: book.title, file: library.coverFile(book), width: 48, radius: 3),
      title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (book.author.isNotEmpty) Text(book.author, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        _LangBadges(book: book),
      ]),
      trailing: Text(percent(book.position.progress)),
      onTap: () => openReader(context, book),
      onLongPress: () => _openDetails(context, book),
    );
  }
}
