import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;

/// A free book from Project Gutenberg. Every Gutenberg book is in the public
/// domain in the USA.
class CatalogBook {
  final int id;
  final String title;
  final List<String> authors;
  final List<String> languages;

  /// Shelf codes (see [kShelves]).
  final String shelves;

  /// Popularity rank on Project Gutenberg (1 = most downloaded), 0 if unknown.
  final int rank;

  const CatalogBook({
    required this.id,
    required this.title,
    required this.authors,
    required this.languages,
    this.shelves = '',
    this.rank = 0,
  });

  String get authorLine => authors.join(', ');
  String get coverUrl => 'https://www.gutenberg.org/cache/epub/$id/pg$id.cover.medium.jpg';
  String get epubUrl => 'https://www.gutenberg.org/ebooks/$id.epub3.images';
  String get textUrl => 'https://www.gutenberg.org/cache/epub/$id/pg$id.txt';
}

/// Topic shelves shown in the store, mapped to catalog shelf codes.
class Shelf {
  final String label;
  final String code; // '' = all books
  const Shelf(this.label, this.code);
}

const kShelves = [
  Shelf('Popular', ''),
  Shelf('Indian', 'I'),
  Shelf('Novels', 'N'),
  Shelf('Adventure', 'A'),
  Shelf('Romance', 'R'),
  Shelf('Mystery', 'M'),
  Shelf('Science fiction', 'S'),
  Shelf('Children', 'C'),
  Shelf('Fairy tales', 'Y'),
  Shelf('Poetry', 'P'),
  Shelf('Short stories', 'T'),
  Shelf('Plays', 'D'),
  Shelf('History', 'H'),
  Shelf('Philosophy', 'F'),
  Shelf('Humour', 'U'),
];

/// The whole Project Gutenberg catalog, bundled with the app
/// (`assets/catalog.json.gz`, built by tools/build_catalog.py), so browsing
/// and search are instant and work offline.
class LocalCatalog {
  static LocalCatalog? _instance;
  static Future<LocalCatalog>? _loading;

  final List<CatalogBook> books;
  final List<String> _keys; // lowercase "title | author" for search
  final String built;

  LocalCatalog._(this.books, this._keys, this.built);

  static Future<LocalCatalog> load() {
    if (_instance != null) return Future.value(_instance);
    return _loading ??= () async {
      final data = await rootBundle.load('assets/catalog.json.gz');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final parsed = await Isolate.run(_CatalogDecoder(bytes).call);
      _instance = LocalCatalog._(parsed.$1, parsed.$2, parsed.$3);
      return _instance!;
    }();
  }

  /// Search by words in the title or author, filtered by shelf and language.
  /// Results are ordered by popularity.
  List<CatalogBook> search({String query = '', String shelf = '', String language = '', int limit = 60, int offset = 0}) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final out = <CatalogBook>[];
    final titleHits = <CatalogBook>[];
    for (var i = 0; i < books.length; i++) {
      final b = books[i];
      if (shelf.isNotEmpty && !b.shelves.contains(shelf)) continue;
      if (language.isNotEmpty && !b.languages.contains(language)) continue;
      if (words.isNotEmpty) {
        final key = _keys[i];
        if (!words.every(key.contains)) continue;
        // Books whose title starts with the query come first.
        if (key.startsWith(words.first) && titleHits.length < limit + offset) {
          titleHits.add(b);
          continue;
        }
      }
      out.add(b);
    }
    final all = [...titleHits, ...out];
    final end = (offset + limit).clamp(0, all.length);
    return offset >= all.length ? const [] : all.sublist(offset, end);
  }

  CatalogBook? byId(int id) {
    for (final b in books) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// Languages present in the catalog with their book counts.
  Map<String, int> languageCounts() {
    final m = <String, int>{};
    for (final b in books) {
      for (final l in b.languages) {
        m[l] = (m[l] ?? 0) + 1;
      }
    }
    return m;
  }
}

class _CatalogDecoder {
  final Uint8List bytes;
  _CatalogDecoder(this.bytes);

  (List<CatalogBook>, List<String>, String) call() {
    final raw = GZipDecoder().decodeBytes(bytes);
    final j = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
    final books = <CatalogBook>[];
    final keys = <String>[];
    for (final e in (j['books'] as List)) {
      final r = e as List;
      final author = r[2] as String;
      books.add(CatalogBook(
        id: (r[0] as num).toInt(),
        title: r[1] as String,
        authors: author.isEmpty ? const [] : [author],
        languages: (r[3] as String).split(','),
        shelves: r[4] as String,
        rank: (r[5] as num).toInt(),
      ));
      keys.add('${(r[1] as String).toLowerCase()} | ${author.toLowerCase()}');
    }
    return (books, keys, (j['built'] as String?) ?? '');
  }
}

/// Curated shelves of well-known classics (assets/featured.json).
class FeaturedBook {
  final String shelf;
  final CatalogBook book;
  FeaturedBook(this.shelf, this.book);

  factory FeaturedBook.fromJson(Map<String, dynamic> j) => FeaturedBook(
        (j['shelf'] as String?) ?? 'classics',
        CatalogBook(
          id: (j['id'] as num).toInt(),
          title: (j['title'] as String?) ?? 'Untitled',
          authors: [for (final a in (j['authors'] as List? ?? const [])) a as String],
          languages: [for (final l in (j['languages'] as List? ?? const ['en'])) l as String],
          rank: (j['rank'] as num?)?.toInt() ?? 0,
        ),
      );
}

class FeaturedBooks {
  static List<FeaturedBook>? _cache;

  static Future<List<FeaturedBook>> load() async {
    if (_cache != null) return _cache!;
    try {
      final j = jsonDecode(await rootBundle.loadString('assets/featured.json')) as Map<String, dynamic>;
      _cache = [for (final b in (j['books'] as List)) FeaturedBook.fromJson(b as Map<String, dynamic>)];
    } catch (_) {
      _cache = const [];
    }
    return _cache!;
  }
}
