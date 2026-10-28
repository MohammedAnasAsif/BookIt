import 'dart:convert';
import 'dart:typed_data';

import '../core/downloader.dart';

/// A ready-made translated edition from the BookIt community library.
class CommunityEdition {
  final String id;
  final String title;
  final String author;
  final String lang;
  final String sourceLang;
  final int? gutenbergId;
  final String url;
  final int size;
  final String engine;
  final String? coverUrl;

  CommunityEdition({
    required this.id,
    required this.title,
    required this.author,
    required this.lang,
    required this.sourceLang,
    required this.gutenbergId,
    required this.url,
    required this.size,
    required this.engine,
    required this.coverUrl,
  });

  factory CommunityEdition.fromJson(Map<String, dynamic> j) => CommunityEdition(
        id: j['id'] as String,
        title: j['title'] as String,
        author: (j['author'] as String?) ?? '',
        lang: j['lang'] as String,
        sourceLang: (j['sourceLang'] as String?) ?? 'eng_Latn',
        gutenbergId: (j['gutenbergId'] as num?)?.toInt(),
        url: j['url'] as String,
        size: (j['size'] as num?)?.toInt() ?? 0,
        engine: (j['engine'] as String?) ?? '',
        coverUrl: j['cover'] as String?,
      );
}

/// The list of community editions lives in the project repository
/// (`catalog/editions.json`) and the files are attached to GitHub releases,
/// so hosting is free and anyone can contribute through a pull request.
class CommunityCatalog {
  static const url = 'https://raw.githubusercontent.com/MohammedAnasAsif/BookIt/main/catalog/editions.json';

  static Future<List<CommunityEdition>> fetch() async {
    final body = await Downloader.getString(url);
    final j = jsonDecode(body) as Map<String, dynamic>;
    return [
      for (final e in (j['editions'] as List? ?? const []))
        CommunityEdition.fromJson(e as Map<String, dynamic>)
    ];
  }
}

/// Downloads a community edition file.
Future<Uint8List> downloadEditionBytes(String url) =>
    Downloader.getBytes(url, timeout: const Duration(minutes: 10));
