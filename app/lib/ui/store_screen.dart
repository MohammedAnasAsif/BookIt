import 'dart:async';

import 'package:flutter/material.dart';

import '../data/catalog.dart';
import '../data/discover.dart';
import 'trending_book_screen.dart';
import 'home_screen.dart';

/// Bump to move to the store and put the cursor in its search box.
final storeSearchRequest = ValueNotifier<int>(0);

/// Browse and search every free Project Gutenberg book. The catalog is bundled
/// with the app, so this is instant and works offline; only downloading a
/// book needs the internet.
class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  static const _pageSize = 60;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _scroll = ScrollController();
  LocalCatalog? _catalog;
  static const _freeFiction = Shelf('Free modern fiction', '#ff');
  static const _standard = Shelf('Standard Ebooks', '#se');
  static final _shelves = [kShelves.first, _freeFiction, _standard, ...kShelves.skip(1)];
  Shelf _shelf = kShelves.first;
  DiscoverData _discover = DiscoverData.empty;
  List<TrendingBook> _storeHits = const [];
  bool _storeLoading = false;
  Timer? _storeTimer;
  int _storeGeneration = 0;
  int _extraCount = 0;
  String _language = 'en';
  List<CatalogBook> _books = const [];
  bool _more = false;

  static const _bookLanguages = {
    'en': 'English',
    'hi': 'Hindi',
    'bn': 'Bengali',
    'ta': 'Tamil',
    'te': 'Telugu',
    'mr': 'Marathi',
    'sa': 'Sanskrit',
    'fr': 'French',
    'de': 'German',
    'es': 'Spanish',
    'it': 'Italian',
    'pt': 'Portuguese',
    'nl': 'Dutch',
    'fi': 'Finnish',
    'zh': 'Chinese',
    'la': 'Latin',
    '': 'Any language',
  };

  void _focusSearch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void initState() {
    super.initState();
    storeSearchRequest.addListener(_focusSearch);
    LocalCatalog.load().then((c) {
      if (!mounted) return;
      _catalog = c;
      _refresh();
    });
    DiscoverData.load().then((d) {
      if (!mounted) return;
      _discover = d;
      if (_shelf.code.startsWith('#')) _refresh();
    });
    _scroll.addListener(() {
      if (_more && _scroll.position.pixels > _scroll.position.maxScrollExtent - 800) _loadMore();
    });
  }

  @override
  void dispose() {
    storeSearchRequest.removeListener(_focusSearch);
    _storeTimer?.cancel();
    _searchFocus.dispose();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _refresh() {
    final c = _catalog;
    if (c == null) return;
    List<CatalogBook> page;
    if (_shelf.code.startsWith('#')) {
      final list = _shelf == _freeFiction ? _discover.freeFiction : _discover.standardEbooks;
      final words = _search.text.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
      page = [
        for (final b in list)
          if (words.every((w) => '${b.title} ${b.authorLine}'.toLowerCase().contains(w))) b
      ];
      _more = false;
    } else {
      page = c.search(query: _search.text, shelf: _shelf.code, language: _language, limit: _pageSize);
      _more = page.length == _pageSize;
    }
    // Free books from the other shelves that match the search too.
    if (_search.text.trim().length >= 2 && !_shelf.code.startsWith('#')) {
      final words = _search.text.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
      final extra = [
        for (final b in [..._discover.freeFiction, ..._discover.standardEbooks])
          if (words.every((w) => '${b.title} ${b.authorLine}'.toLowerCase().contains(w))) b
      ];
      _extraCount = extra.take(12).length;
      page = [...extra.take(12), ...page];
    } else {
      _extraCount = 0;
    }
    setState(() => _books = page);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _scheduleStoreSearch();
  }

  /// Looks the search up in Open Library too, to show where to buy or borrow
  /// books that aren't free.
  void _scheduleStoreSearch() {
    _storeTimer?.cancel();
    final q = _search.text.trim();
    final gen = ++_storeGeneration;
    if (q.length < 3) {
      if (_storeHits.isNotEmpty || _storeLoading) {
        setState(() {
          _storeHits = const [];
          _storeLoading = false;
        });
      }
      return;
    }
    setState(() => _storeLoading = true);
    _storeTimer = Timer(const Duration(milliseconds: 700), () async {
      List<TrendingBook> hits = const [];
      try {
        hits = await searchStores(q);
      } catch (_) {}
      if (!mounted || gen != _storeGeneration) return;
      final free = _books.map((b) => b.title.toLowerCase()).toSet();
      setState(() {
        _storeHits = hits.where((h) => !free.contains(h.title.toLowerCase())).toList();
        _storeLoading = false;
      });
    });
  }

  void _loadMore() {
    final c = _catalog;
    if (c == null) return;
    final page = c.search(
        query: _search.text, shelf: _shelf.code, language: _language, limit: _pageSize, offset: _books.length - _extraCount);
    setState(() {
      _books = [..._books, ...page];
      _more = page.length == _pageSize;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = (width / 150).floor().clamp(2, 8);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Free books'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Book language',
            initialValue: _language,
            onSelected: (v) {
              _language = v;
              _refresh();
            },
            itemBuilder: (_) => [
              for (final e in _bookLanguages.entries) PopupMenuItem(value: e.key, child: Text(e.value)),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                const Icon(Icons.language, size: 20),
                const SizedBox(width: 6),
                Text(_bookLanguages[_language] ?? _language),
              ]),
            ),
          ),
        ],
      ),
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _search,
                focusNode: _searchFocus,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search ${_catalog == null ? '' : '${(_catalog!.books.length ~/ 1000)},000+ '}free books',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _search.clear();
                            _refresh();
                          },
                        ),
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                ),
                onChanged: (_) => _refresh(),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final s in _shelves)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(s.label),
                        selected: s == _shelf,
                        onSelected: (_) {
                          _shelf = s;
                          _refresh();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_catalog == null)
            const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
          else ...[
            if (_books.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
                  child: Text(
                    _search.text.trim().isEmpty
                        ? 'No books here yet.'
                        : 'No free books match “${_search.text.trim()}”.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 18,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.55,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => LayoutBuilder(builder: (_, c) => CatalogTile(book: _books[i], width: c.maxWidth)),
                    childCount: _books.length,
                  ),
                ),
              ),
            if (_storeLoading || _storeHits.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Books you can buy or borrow',
                        style: theme.textTheme.titleLarge?.copyWith(fontFamily: 'serif', fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      'Newer books are sold by their publishers. Tap one to see where to get it — then add your '
                      'DRM-free copy to BookIt to read and translate it.',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (_storeLoading)
                      const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
                  ]),
                ),
              ),
            if (_storeHits.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 18,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.55,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) =>
                        LayoutBuilder(builder: (_, c) => TrendingTile(book: _storeHits[i], width: c.maxWidth)),
                    childCount: _storeHits.length,
                  ),
                ),
              ),
          ],
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Text(
                'Free books come from Project Gutenberg, Standard Ebooks and authors who share their work. '
                'Details of other books come from Open Library.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
