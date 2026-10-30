import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/languages.dart';
import '../data/community_catalog.dart';
import '../data/catalog.dart';
import '../data/discover.dart';
import 'trending_book_screen.dart';
import '../data/library_store.dart';
import '../data/settings_store.dart';
import '../models/book.dart';
import '../translation/translation_service.dart';
import 'book_actions.dart';
import 'book_details_screen.dart';
import 'catalog_book_screen.dart';
import 'engagement_ui.dart';
import 'widgets/book_cover.dart';
import 'widgets/format.dart';
import 'widgets/language_picker.dart';
import '../l10n/strings.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onOpenStore;
  final VoidCallback onOpenLibrary;
  final VoidCallback onSearch;
  const HomeScreen({super.key, required this.onOpenStore, required this.onOpenLibrary, required this.onSearch});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<FeaturedBook>> _featured;
  late Future<List<CommunityEdition>> _editions;
  DiscoverData _discover = DiscoverData.empty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _featured = FeaturedBooks.load();
    DiscoverData.load().then((d) {
      if (mounted) setState(() => _discover = d);
      DiscoverData.refresh().then((fresh) {
        if (fresh != null && mounted) setState(() => _discover = fresh);
      });
    });
    _editions = CommunityCatalog.fetch().catchError((_) => <CommunityEdition>[]);
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final settings = context.watch<SettingsStore>();
    final service = context.watch<TranslationService>();
    final theme = Theme.of(context);
    final recent = library.recent;
    final preferred = languageByCode(settings.preferredLang);

    return Scaffold(
      appBar: AppBar(
        title: const Text('BookIt'),
        actions: [
          IconButton(
            tooltip: tr('Search free books'),
            icon: const Icon(Icons.search),
            onPressed: widget.onSearch,
          ),
          TextButton.icon(
            icon: const Icon(Icons.translate, size: 18),
            label: Text(preferred?.nativeName ?? tr('Language')),
            onPressed: () async {
              final l = await pickLanguage(context, title: tr('Your reading language'), selected: settings.preferredLang);
              if (l != null) settings.update((s) => s.preferredLang = l.code);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(_load);
          await _editions;
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const UpdateBanner(),
            if (preferred == null) _WelcomeCard(onPick: (l) => settings.update((s) => s.preferredLang = l.code)),
            if (recent.isNotEmpty) ...[
              _SectionTitle(tr('Continue reading')),
              _ContinueCard(book: recent.first),
              if (recent.length > 1)
                SizedBox(
                  height: 190,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    children: [
                      for (final b in recent.skip(1).take(10))
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: _LibraryBookTile(book: b, width: 96),
                        ),
                    ],
                  ),
                ),
            ],
            const StreakCard(),
            for (final job in service.jobs.where((j) => j.active))
              _TranslationCard(job: job, book: library.byId(job.bookId)),
            if (_discover.trending.isNotEmpty)
              _TrendingShelf(
                title: tr('Trending now'),
                subtitle: tr('What readers around the world are picking up this week'),
                books: _discover.trending,
              ),
            if (_discover.freeFiction.isNotEmpty)
              _CatalogShelf(
                title: tr('Free modern fiction'),
                subtitle: tr('Novels their authors chose to share for free — read and translate them'),
                books: _discover.freeFiction,
              ),
            if (_discover.bestsellers.isNotEmpty)
              _TrendingShelf(
                title: tr('Bestsellers everyone is talking about'),
                subtitle: tr('See where to buy or borrow them'),
                books: _discover.bestsellers,
              ),
            if (_discover.standardEbooks.isNotEmpty)
              _CatalogShelf(
                title: tr('Beautiful classics'),
                subtitle: tr('Carefully edited editions from Standard Ebooks — free'),
                books: _discover.standardEbooks.take(30).toList(),
              ),
            FutureBuilder<List<CommunityEdition>>(
              future: _editions,
              builder: (context, snap) {
                var eds = snap.data ?? const <CommunityEdition>[];
                if (preferred != null) {
                  final mine = eds.where((e) => e.lang == preferred.code).toList();
                  if (mine.isNotEmpty) eds = mine;
                }
                if (eds.isEmpty) return const SizedBox.shrink();
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _SectionTitle(tr('Ready to read in your language'),
                      subtitle: tr('Already translated by the BookIt community — download and read offline')),
                  SizedBox(
                    height: 236,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      children: [for (final e in eds) _EditionTile(edition: e)],
                    ),
                  ),
                ]);
              },
            ),
            FutureBuilder<List<FeaturedBook>>(
              future: _featured,
              builder: (context, snap) {
                final featured = snap.data ?? const <FeaturedBook>[];
                Widget shelf(String title, String subtitle, Iterable<FeaturedBook> books, {Widget? action}) {
                  final list = books.toList();
                  if (list.isEmpty) return const SizedBox.shrink();
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _SectionTitle(title, subtitle: subtitle, action: action),
                    SizedBox(
                      height: 236,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        children: [
                          for (final f in list)
                            Padding(
                              padding: const EdgeInsets.only(right: 14),
                              child: CatalogTile(book: f.book, width: 110),
                            ),
                        ],
                      ),
                    ),
                  ]);
                }

                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  shelf(tr('Indian classics'), tr('Tagore, Kipling, folk tales and more — free and public domain'),
                      featured.where((f) => f.shelf == 'india')),
                  shelf(tr('Popular free classics'), tr('From Project Gutenberg — free and public domain'),
                      featured.where((f) => f.shelf == 'classics'),
                      action: TextButton(onPressed: widget.onOpenStore, child: Text(tr('See all')))),
                  shelf(tr('For children'), tr('Fairy tales, fables and adventures'), featured.where((f) => f.shelf == 'children')),
                ]);
              },
            ),
            if (library.books.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('How BookIt works'), style: theme.textTheme.titleMedium),
                      const SizedBox(height: 12),
                      _Step(n: 1, text: tr('Pick any free book from the store (or open your own EPUB).')),
                      _Step(n: 2, text: tr('Tap “Translate” and choose your language — Tamil, Hindi, Bengali and 90+ more.')),
                      const _Step(
                          n: 3,
                          text: 'The book is translated on your phone or PC and saved. Read it anytime, even offline.'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: widget.onOpenStore,
                        icon: const Icon(Icons.storefront),
                        label: Text(tr('Browse free books')),
                      ),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String text;
  const _Step({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: theme.colorScheme.secondaryContainer,
          child: Text('$n', style: theme.textTheme.labelMedium),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;
  const _SectionTitle(this.title, {this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 12, 4),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: theme.textTheme.titleLarge?.copyWith(fontFamily: 'serif', fontWeight: FontWeight.w600)),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(subtitle!, style: theme.textTheme.bodySmall),
              ),
          ]),
        ),
        if (action != null) action!,
      ]),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  final ValueChanged<Language> onPick;
  const _WelcomeCard({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quick = kLanguages.where((l) => l.group == LanguageGroup.indian).take(10).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        color: theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Welcome! Which language do you like to read in?'),
                style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final l in quick) ActionChip(label: Text(l.nativeName), onPressed: () => onPick(l)),
              ActionChip(
                avatar: const Icon(Icons.more_horiz, size: 18),
                label: Text(tr('More')),
                onPressed: () async {
                  final l = await pickLanguage(context, title: tr('Your reading language'));
                  if (l != null) onPick(l);
                },
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  final Book book;
  const _ContinueCard({required this.book});

  @override
  Widget build(BuildContext context) {
    final library = context.read<LibraryStore>();
    final theme = Theme.of(context);
    final lang = languageByCode(book.readingLang);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openReader(context, book),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              BookCover(title: book.title, author: book.author, file: library.coverFile(book), width: 84),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontFamily: 'serif')),
                  if (book.author.isNotEmpty)
                    Text(book.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 10),
                  if (lang != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.translate, size: 16),
                        label: Text(tr('Reading in {lang}', {'lang': lang.nativeName})),
                      ),
                    ),
                  LinearProgressIndicator(value: book.position.progress, minHeight: 4, borderRadius: BorderRadius.circular(2)),
                  const SizedBox(height: 6),
                  Text(tr('{p} read', {'p': percent(book.position.progress)}), style: theme.textTheme.bodySmall),
                ]),
              ),
              const Icon(Icons.chevron_right),
            ]),
          ),
        ),
      ),
    );
  }
}

class _TranslationCard extends StatelessWidget {
  final JobProgress job;
  final Book? book;
  const _TranslationCard({required this.job, required this.book});

  @override
  Widget build(BuildContext context) {
    if (book == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final lang = languageByCode(job.lang);
    final eta = job.eta;
    final status = switch (job.status) {
      JobStatus.queued => 'Waiting…',
      JobStatus.starting => job.message.isEmpty ? 'Starting…' : job.message,
      _ => '${percent(job.fraction)}${eta != null ? ' · about ${formatDuration(eta)} left' : ''}',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.translate),
          title: Text(tr('Translating “{title}” into {lang}', {'title': book!.title, 'lang': lang?.nativeName ?? job.lang}),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 6),
            LinearProgressIndicator(value: job.status == JobStatus.running ? job.fraction : null),
            const SizedBox(height: 4),
            Text(status, style: theme.textTheme.bodySmall),
          ]),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => BookDetailsScreen(bookId: book!.id))),
        ),
      ),
    );
  }
}

class _LibraryBookTile extends StatelessWidget {
  final Book book;
  final double width;
  const _LibraryBookTile({required this.book, required this.width});

  @override
  Widget build(BuildContext context) {
    final library = context.read<LibraryStore>();
    return GestureDetector(
      onTap: () => openReader(context, book),
      child: SizedBox(
        width: width,
        child: BookCover(title: book.title, author: book.author, file: library.coverFile(book), width: width),
      ),
    );
  }
}

class _EditionTile extends StatelessWidget {
  final CommunityEdition edition;
  const _EditionTile({required this.edition});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = languageByCode(edition.lang);
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: SizedBox(
        width: 110,
        child: InkWell(
          onTap: () => openCommunityEdition(context, edition),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(children: [
              BookCover(title: edition.title, author: edition.author, url: edition.coverUrl, width: 110),
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4)),
                  child: Text(lang?.nativeName ?? edition.lang,
                      style: const TextStyle(color: Colors.white, fontSize: 11)),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text(edition.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }
}

Future<void> openCommunityEdition(BuildContext context, CommunityEdition e) async {
  final library = context.read<LibraryStore>();
  showMessage(context, tr('Downloading “{title}”…', {'title': e.title}));
  try {
    final bytes = await downloadEditionBytes(e.url);
    final book = await library.addEdition(bytes);
    if (context.mounted) await openReader(context, book, lang: e.lang);
  } catch (err) {
    if (context.mounted) showMessage(context, 'Could not download this edition: $err');
  }
}

class CatalogTile extends StatelessWidget {
  final CatalogBook book;
  final double width;
  const CatalogTile({super.key, required this.book, required this.width});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CatalogBookScreen(book: book))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          BookCover(
              title: book.title, author: book.authorLine, urls: book.coverUrls, cacheKey: book.coverKey, width: width),
          const SizedBox(height: 6),
          Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
        ]),
      ),
    );
  }
}

class _TrendingShelf extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<TrendingBook> books;
  const _TrendingShelf({required this.title, required this.subtitle, required this.books});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SectionTitle(title, subtitle: subtitle),
        SizedBox(
          height: 236,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              for (final b in books)
                Padding(padding: const EdgeInsets.only(right: 14), child: TrendingTile(book: b, width: 110)),
            ],
          ),
        ),
      ]);
}

class _CatalogShelf extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<CatalogBook> books;
  const _CatalogShelf({required this.title, required this.subtitle, required this.books});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SectionTitle(title, subtitle: subtitle),
        SizedBox(
          height: 236,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              for (final b in books)
                Padding(padding: const EdgeInsets.only(right: 14), child: CatalogTile(book: b, width: 110)),
            ],
          ),
        ),
      ]);
}
