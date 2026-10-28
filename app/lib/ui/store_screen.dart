import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../data/gutendex.dart';
import 'home_screen.dart';

/// Browse and search the free Project Gutenberg catalog.
class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Shelf _shelf = kShelves.first;
  String _language = 'en';
  final List<CatalogBook> _books = [];
  String? _next;
  bool _loading = false;
  String? _error;
  int _generation = 0;
  Timer? _debounce;
  bool _offlinePicks = false;

  static const _bookLanguages = {
    'en': 'English',
    'hi': 'Hindi',
    'bn': 'Bengali',
    'ta': 'Tamil',
    'te': 'Telugu',
    'sa': 'Sanskrit',
    'fr': 'French',
    'de': 'German',
    'es': 'Spanish',
    'it': 'Italian',
    'pt': 'Portuguese',
    'nl': 'Dutch',
    'fi': 'Finnish',
    'zh': 'Chinese',
    '': 'Any language',
  };

  @override
  void initState() {
    super.initState();
    _reload();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _loadMore();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  /// Bundled picks matching the current shelf/search, shown instantly.
  Future<List<CatalogBook>> _picks() async {
    final featured = await FeaturedBooks.load(rootBundle.loadString);
    final q = _search.text.trim().toLowerCase();
    return [
      for (final f in featured)
        if ((q.isEmpty || f.book.title.toLowerCase().contains(q) || f.book.authorLine.toLowerCase().contains(q)) &&
            (_shelf.topic.isEmpty ||
                (_shelf.topic == 'india' && f.shelf == 'india') ||
                ((_shelf.topic == 'children' || _shelf.topic == 'fairy tales') && f.shelf == 'children')) &&
            (_language.isEmpty || f.book.languages.contains(_language)))
          f.book
    ];
  }

  Future<void> _reload() async {
    final gen = ++_generation;
    final picks = await _picks();
    if (gen != _generation) return;
    setState(() {
      _books
        ..clear()
        ..addAll(picks);
      _next = null;
      _error = null;
      _offlinePicks = false;
      _loading = true;
    });
    try {
      final page = await Gutendex.fetch(search: _search.text, topic: _shelf.topic, languages: _language);
      if (gen != _generation) return;
      setState(() {
        final seen = _books.map((b) => b.id).toSet();
        _books.addAll(page.books.where((b) => seen.add(b.id)));
        _next = page.next;
      });
    } catch (e) {
      if (gen == _generation) {
        setState(() {
          if (_books.isEmpty) {
            _error = 'Could not reach the free book catalog. Check your internet connection.';
          } else {
            _offlinePicks = true;
          }
        });
      }
    } finally {
      if (gen == _generation) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _next == null) return;
    final gen = _generation;
    setState(() => _loading = true);
    try {
      final page = await Gutendex.fetch(pageUrl: _next);
      if (gen != _generation) return;
      setState(() {
        _books.addAll(page.books);
        _next = page.next;
      });
    } catch (_) {
    } finally {
      if (gen == _generation) setState(() => _loading = false);
    }
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
            icon: const Icon(Icons.language),
            initialValue: _language,
            onSelected: (v) {
              _language = v;
              _reload();
            },
            itemBuilder: (_) => [
              for (final e in _bookLanguages.entries) PopupMenuItem(value: e.key, child: Text(e.value)),
            ],
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
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search 70,000+ free books by title or author',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _search.clear();
                            _reload();
                          },
                        ),
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                ),
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 600), _reload);
                },
                onSubmitted: (_) => _reload(),
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
                          _reload();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_offlinePicks)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Text(
                  'Showing our picks. The full catalog is not reachable right now — pull down or try again later.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          if (_error != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.wifi_off, size: 48, color: theme.colorScheme.outline),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(onPressed: _reload, child: const Text('Try again')),
                ]),
              ),
            )
          else if (_books.isEmpty && !_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('No books found. Try another search.')),
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
          if (_loading)
            const SliverToBoxAdapter(
              child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
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
