import 'package:flutter/material.dart';

import '../data/catalog.dart';
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
  Shelf _shelf = kShelves.first;
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
    _scroll.addListener(() {
      if (_more && _scroll.position.pixels > _scroll.position.maxScrollExtent - 800) _loadMore();
    });
  }

  @override
  void dispose() {
    storeSearchRequest.removeListener(_focusSearch);
    _searchFocus.dispose();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _refresh() {
    final c = _catalog;
    if (c == null) return;
    final page = c.search(query: _search.text, shelf: _shelf.code, language: _language, limit: _pageSize);
    setState(() {
      _books = page;
      _more = page.length == _pageSize;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _loadMore() {
    final c = _catalog;
    if (c == null) return;
    final page = c.search(
        query: _search.text, shelf: _shelf.code, language: _language, limit: _pageSize, offset: _books.length);
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
                  for (final s in kShelves)
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
          else if (_books.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    _language.isEmpty ? 'No books found.' : 'No books found. Try “Any language” or another search.',
                    textAlign: TextAlign.center,
                  ),
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
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Text(
                'Books come from Project Gutenberg, a volunteer library of free, public-domain e-books.',
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
