import 'dart:convert';

import '../core/downloader.dart';

/// A book from the Project Gutenberg catalog (via the free Gutendex API).
/// Every book listed here is in the public domain in the USA.
class CatalogBook {
  final int id;
  final String title;
  final List<String> authors;
  final List<String> languages;
  final List<String> subjects;
  final String? coverUrl;
  final String? epubUrl;
  final String? textUrl;
  final int downloadCount;

  CatalogBook({
    required this.id,
    required this.title,
    required this.authors,
    required this.languages,
    required this.subjects,
    required this.coverUrl,
    required this.epubUrl,
    required this.textUrl,
    required this.downloadCount,
  });

  String get authorLine => authors.map(_flipName).join(', ');

  /// "Austen, Jane" -> "Jane Austen"
  static String _flipName(String n) {
    final parts = n.split(', ');
    if (parts.length == 2) return '${parts[1]} ${parts[0]}';
    return n;
  }

  bool get readable => epubUrl != null || textUrl != null;

  factory CatalogBook.fromGutendex(Map<String, dynamic> j) {
    final formats = (j['formats'] as Map?)?.cast<String, dynamic>() ?? {};
    String? fmt(bool Function(String k) test) {
      for (final e in formats.entries) {
        if (test(e.key) && !(e.value as String).endsWith('.zip')) return e.value as String;
      }
      return null;
    }

    return CatalogBook(
      id: (j['id'] as num).toInt(),
      title: ((j['title'] as String?) ?? 'Untitled').replaceAll(RegExp(r'\s+'), ' ').trim(),
      authors: [for (final a in (j['authors'] as List? ?? const [])) ((a as Map)['name'] as String?) ?? ''],
      languages: [for (final l in (j['languages'] as List? ?? const [])) l as String],
      subjects: [for (final s in (j['subjects'] as List? ?? const [])) s as String],
      coverUrl: fmt((k) => k.startsWith('image/')),
      epubUrl: fmt((k) => k.startsWith('application/epub')),
      textUrl: fmt((k) => k.startsWith('text/plain')),
      downloadCount: (j['download_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'authors': [for (final a in authors) {'name': a}],
        'languages': languages,
        'subjects': subjects,
        'download_count': downloadCount,
        'formats': {
          if (coverUrl != null) 'image/jpeg': coverUrl,
          if (epubUrl != null) 'application/epub+zip': epubUrl,
          if (textUrl != null) 'text/plain; charset=utf-8': textUrl,
        },
      };
}

class CatalogPage {
  final List<CatalogBook> books;
  final String? next;
  final int count;
  CatalogPage(this.books, this.next, this.count);
}

/// Topic shelves shown in the store.
class Shelf {
  final String label;
  final String topic;
  const Shelf(this.label, this.topic);
}

const kShelves = [
  Shelf('Popular', ''),
  Shelf('Fiction', 'fiction'),
  Shelf('Adventure', 'adventure'),
  Shelf('Romance', 'love stories'),
  Shelf('Mystery', 'detective'),
  Shelf('Science fiction', 'science fiction'),
  Shelf('Children', 'children'),
  Shelf('Fairy tales', 'fairy tales'),
  Shelf('Poetry', 'poetry'),
  Shelf('Short stories', 'short stories'),
  Shelf('History', 'history'),
  Shelf('Philosophy', 'philosophy'),
  Shelf('India', 'india'),
  Shelf('Plays', 'drama'),
];

class Gutendex {
  static const base = 'https://gutendex.com/books';

  static Future<CatalogPage> fetch({
    String search = '',
    String topic = '',
    String languages = '',
    String? pageUrl,
  }) async {
    final url = pageUrl ??
        Uri.parse(base).replace(queryParameters: {
          if (search.trim().isNotEmpty) 'search': search.trim(),
          if (topic.isNotEmpty) 'topic': topic,
          if (languages.isNotEmpty) 'languages': languages,
          'mime_type': 'application/epub',
        }).toString();
    final body = await Downloader.getString(url, timeout: const Duration(seconds: 40));
    final j = jsonDecode(body) as Map<String, dynamic>;
    final books = [
      for (final b in (j['results'] as List? ?? const [])) CatalogBook.fromGutendex(b as Map<String, dynamic>)
    ].where((b) => b.readable).toList();
    return CatalogPage(books, j['next'] as String?, (j['count'] as num?)?.toInt() ?? books.length);
  }
}

/// Curated, bundled list of popular classics (app/assets/featured.json).
/// Shown instantly and offline; built by tools/make_featured.py.
class FeaturedBooks {
  static List<FeaturedBook>? _cache;

  static Future<List<FeaturedBook>> load(Future<String> Function(String) loadAsset) async {
    if (_cache != null) return _cache!;
    try {
      final j = jsonDecode(await loadAsset('assets/featured.json')) as Map<String, dynamic>;
      _cache = [for (final b in (j['books'] as List)) FeaturedBook.fromJson(b as Map<String, dynamic>)];
    } catch (_) {
      _cache = const [];
    }
    return _cache!;
  }
}

class FeaturedBook {
  final String shelf;
  final CatalogBook book;
  FeaturedBook(this.shelf, this.book);

  factory FeaturedBook.fromJson(Map<String, dynamic> j) {
    final id = (j['id'] as num).toInt();
    return FeaturedBook(
      (j['shelf'] as String?) ?? 'classics',
      CatalogBook(
        id: id,
        title: (j['title'] as String?) ?? 'Untitled',
        authors: [for (final a in (j['authors'] as List? ?? const [])) a as String],
        languages: [for (final l in (j['languages'] as List? ?? const ['en'])) l as String],
        subjects: const [],
        coverUrl: 'https://www.gutenberg.org/cache/epub/$id/pg$id.cover.medium.jpg',
        epubUrl: 'https://www.gutenberg.org/ebooks/$id.epub3.images',
        textUrl: 'https://www.gutenberg.org/cache/epub/$id/pg$id.txt',
        downloadCount: (j['downloads'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}
