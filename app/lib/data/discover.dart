import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../core/app_paths.dart';
import '../core/downloader.dart';
import 'catalog.dart';

/// A popular book that is sold by its publisher. BookIt shows it so readers
/// can discover it, with links to buy or borrow it.
class TrendingBook {
  final String key; // Open Library work key, e.g. /works/OL18020194W
  final String title;
  final String author;
  final int? year;
  final int cover;

  const TrendingBook({required this.key, required this.title, required this.author, this.year, required this.cover});

  factory TrendingBook.fromJson(Map<String, dynamic> j) => TrendingBook(
        key: j['key'] as String,
        title: j['title'] as String,
        author: (j['author'] as String?) ?? '',
        year: (j['year'] as num?)?.toInt(),
        cover: (j['cover'] as num).toInt(),
      );

  List<String> get coverUrls => ['https://covers.openlibrary.org/b/id/$cover-M.jpg'];
  String get coverKey => 'ol$cover';
  String get openLibraryUrl => 'https://openlibrary.org$key';
}

/// The Discover shelves (built weekly by tools/build_discover.py).
class DiscoverData {
  final List<TrendingBook> trending;
  final List<TrendingBook> bestsellers;
  final List<CatalogBook> freeFiction;
  final List<CatalogBook> standardEbooks;

  const DiscoverData(this.trending, this.bestsellers, this.freeFiction, this.standardEbooks);

  static const empty = DiscoverData([], [], [], []);

  factory DiscoverData.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> list(String k) => [for (final e in (j[k] as List? ?? const [])) e as Map<String, dynamic>];
    return DiscoverData(
      [for (final e in list('trending')) TrendingBook.fromJson(e)],
      [for (final e in list('bestsellers')) TrendingBook.fromJson(e)],
      [
        for (final e in list('freeFiction'))
          CatalogBook(
            id: 0,
            key: 'ff-${e['id']}',
            source: 'free',
            title: e['title'] as String,
            authors: [e['author'] as String],
            languages: const ['en'],
            epubOverride: [e['epub'] as String],
            coverOverride: e['cover'] == null ? const [] : [e['cover'] as String],
            licence: e['licence'] as String?,
            licenceUrl: e['licenceUrl'] as String?,
            sourcePage: e['sourcePage'] as String?,
            genre: e['genre'] as String?,
            blurb: e['blurb'] as String?,
          )
      ],
      [
        for (final e in list('standardEbooks'))
          CatalogBook(
            id: 0,
            key: 'se-${e['id']}',
            source: 'standard',
            title: e['title'] as String,
            authors: [e['author'] as String],
            languages: const ['en'],
            epubOverride: [e['epub'] as String],
            coverOverride: [e['cover'] as String],
            licence: 'Public domain (CC0 edition)',
            sourcePage: e['page'] as String?,
          )
      ],
    );
  }

  static const remoteUrl = 'https://raw.githubusercontent.com/MohammedAnasAsif/BookIt/main/catalog/discover.json';
  static DiscoverData? _cache;

  static File get _cacheFile => File(p.join(AppPaths.cache.path, 'discover.json'));

  /// Bundled copy first (instant), then a copy downloaded earlier.
  static Future<DiscoverData> load() async {
    if (_cache != null) return _cache!;
    DiscoverData? data;
    try {
      if (await _cacheFile.exists()) {
        data = DiscoverData.fromJson(jsonDecode(await _cacheFile.readAsString()) as Map<String, dynamic>);
      }
    } catch (_) {}
    if (data == null || data.isEmptyData) {
      try {
        data = DiscoverData.fromJson(
            jsonDecode(await rootBundle.loadString('assets/discover.json')) as Map<String, dynamic>);
      } catch (_) {
        data = empty;
      }
    }
    _cache = data;
    return data;
  }

  /// Downloads the latest shelves (weekly updates) and keeps them for offline use.
  static Future<DiscoverData?> refresh() async {
    try {
      final body = await Downloader.getString(remoteUrl, timeout: const Duration(seconds: 20));
      final data = DiscoverData.fromJson(jsonDecode(body) as Map<String, dynamic>);
      if (data.isEmptyData) return null;
      await _cacheFile.parent.create(recursive: true);
      await _cacheFile.writeAsString(body);
      _cache = data;
      return data;
    } catch (_) {
      return null;
    }
  }

  bool get isEmptyData => trending.isEmpty && bestsellers.isEmpty && freeFiction.isEmpty && standardEbooks.isEmpty;
}

/// Live search of Open Library for books that aren't free (to show where to
/// buy or borrow them).
Future<List<TrendingBook>> searchStores(String query) async {
  final q = Uri.encodeQueryComponent(query.trim());
  if (q.isEmpty) return const [];
  final body = await Downloader.getString(
    'https://openlibrary.org/search.json?q=$q&limit=24&fields=key,title,author_name,cover_i,first_publish_year',
    timeout: const Duration(seconds: 20),
  );
  final docs = (jsonDecode(body) as Map<String, dynamic>)['docs'] as List? ?? const [];
  return [
    for (final d in docs.cast<Map<String, dynamic>>())
      if (d['cover_i'] != null)
        TrendingBook(
          key: d['key'] as String,
          title: d['title'] as String,
          author: ((d['author_name'] as List?) ?? const []).take(2).join(', '),
          year: (d['first_publish_year'] as num?)?.toInt(),
          cover: (d['cover_i'] as num).toInt(),
        )
  ];
}
