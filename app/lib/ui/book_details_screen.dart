import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/languages.dart';
import '../data/library_store.dart';
import '../translation/translation_service.dart';
import 'book_actions.dart';
import 'widgets/book_cover.dart';
import 'widgets/format.dart';
import '../l10n/strings.dart';

/// A book in the library: read, translate, manage translations, export.
class BookDetailsScreen extends StatelessWidget {
  final String bookId;
  const BookDetailsScreen({super.key, required this.bookId});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final service = context.watch<TranslationService>();
    final book = library.byId(bookId);
    final theme = Theme.of(context);
    if (book == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(tr('This book is no longer in your library.'))));
    }
    final source = languageByCode(book.sourceLang);
    final langs = library.translationLangs(book.id).toList()..sort();

    return Scaffold(
      appBar: AppBar(
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'export':
                  await exportEpub(context, book);
                case 'delete':
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text(tr('Remove this book?')),
                      content: Text(tr('The book and its translations will be deleted from this device.')),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
                        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Remove'))),
                      ],
                    ),
                  );
                  if (ok == true && context.mounted) {
                    for (final l in langs) {
                      await service.pause(book.id, l);
                    }
                    await library.delete(book);
                    if (context.mounted) Navigator.pop(context);
                  }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'export', child: Text(tr('Save original as EPUB'))),
              PopupMenuItem(value: 'delete', child: Text(tr('Remove from library'))),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            BookCover(title: book.title, author: book.author, file: library.coverFile(book), width: 110),
            const SizedBox(width: 18),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(book.title,
                    style: theme.textTheme.titleLarge?.copyWith(fontFamily: 'serif', fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                if (book.author.isNotEmpty) Text(book.author, style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Text('Original language: ${source?.name ?? book.sourceLang}', style: theme.textTheme.bodySmall),
                Text(tr('{p} read', {'p': percent(book.position.progress)}), style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.menu_book),
                  label: Text(tr('Read original')),
                  onPressed: () => openReader(context, book, original: true),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 28),
          Row(children: [
            Expanded(child: Text(tr('Translations'), style: theme.textTheme.titleMedium)),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: Text(tr('Translate')),
              onPressed: () => translateBook(context, book),
            ),
          ]),
          if (langs.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Translate this book into Tamil, Hindi, Bengali, Telugu, Marathi and 90+ other languages. '
                  'It is translated on this device and saved here, so you can read it offline.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
          for (final l in langs) _TranslationTile(bookId: book.id, lang: l),
          const SizedBox(height: 24),
          Text(
            'Translations are made by a machine translation model (NLLB-200). They are good for reading and '
            'understanding, but may contain mistakes.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _TranslationTile extends StatelessWidget {
  final String bookId;
  final String lang;
  const _TranslationTile({required this.bookId, required this.lang});

  @override
  Widget build(BuildContext context) {
    final library = context.read<LibraryStore>();
    final service = context.watch<TranslationService>();
    final book = library.byId(bookId)!;
    final job = service.job(bookId, lang);
    final language = languageByCode(lang);
    final theme = Theme.of(context);
    final done = job?.status == JobStatus.done;
    final running = job != null && job.active;
    final eta = job?.eta;

    String status;
    if (job == null) {
      status = 'Ready';
    } else {
      status = switch (job.status) {
        JobStatus.done => 'Fully translated · available offline',
        JobStatus.queued => 'Waiting to start · ${percent(job.fraction)} done',
        JobStatus.starting => job.message.isEmpty ? 'Starting…' : job.message,
        JobStatus.running =>
          'Translating · ${percent(job.fraction)}${eta != null ? ' · about ${formatDuration(eta)} left' : ''}',
        JobStatus.paused => 'Paused · ${percent(job.fraction)} done',
        JobStatus.error => 'Stopped: ${job.message}',
      };
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(language?.nativeName ?? lang, style: theme.textTheme.titleMedium),
                if (language != null && language.name != language.nativeName)
                  Text(language.name, style: theme.textTheme.bodySmall),
              ]),
            ),
            FilledButton.tonal(
              onPressed: () => openReader(context, book, lang: lang),
              child: Text(tr('Read')),
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'pause':
                    await service.pause(bookId, lang);
                  case 'resume':
                    await service.start(book, lang);
                  case 'epub':
                    await exportEpub(context, book, lang: lang);
                  case 'share':
                    await exportEdition(context, book, lang);
                  case 'delete':
                    await service.cancelAndDelete(book, lang);
                }
              },
              itemBuilder: (_) => [
                if (running) PopupMenuItem(value: 'pause', child: Text(tr('Pause translation'))),
                if (!running && !done) PopupMenuItem(value: 'resume', child: Text(tr('Continue translating'))),
                PopupMenuItem(value: 'epub', child: Text(tr('Save as EPUB'))),
                PopupMenuItem(value: 'share', child: Text(tr('Share as BookIt edition'))),
                PopupMenuItem(value: 'delete', child: Text(tr('Delete translation'))),
              ],
            ),
          ]),
          const SizedBox(height: 8),
          if (job != null && !done) ...[
            LinearProgressIndicator(value: job.fraction),
            const SizedBox(height: 6),
          ],
          Text(status, style: theme.textTheme.bodySmall),
        ]),
      ),
    );
  }
}
