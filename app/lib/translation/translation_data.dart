import 'dart:convert';
import 'dart:io';

import '../models/book_content.dart';

/// A translation of a book into one language, aligned block-by-block with the
/// book's [BookContent]. `chapters[c][b]` is the translated text of block `b`
/// of chapter `c`, or null when it has not been translated yet.
class TranslationData {
  final String lang;
  final String sourceLang;
  String engine;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<List<String?>> chapters;

  TranslationData({
    required this.lang,
    required this.sourceLang,
    required this.engine,
    required this.chapters,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory TranslationData.emptyFor(BookContent content, String lang, String sourceLang, String engine) =>
      TranslationData(
        lang: lang,
        sourceLang: sourceLang,
        engine: engine,
        chapters: [for (final c in content.chapters) List<String?>.filled(c.blocks.length, null)],
      );

  /// Makes sure the shape matches [content] (e.g. after a re-import).
  void conformTo(BookContent content) {
    while (chapters.length < content.chapters.length) {
      chapters.add([]);
    }
    if (chapters.length > content.chapters.length) {
      chapters.removeRange(content.chapters.length, chapters.length);
    }
    for (var c = 0; c < content.chapters.length; c++) {
      final n = content.chapters[c].blocks.length;
      final row = chapters[c];
      if (row.length < n) row.addAll(List<String?>.filled(n - row.length, null));
      if (row.length > n) row.removeRange(n, row.length);
    }
  }

  String? text(int chapter, int block) {
    if (chapter < 0 || chapter >= chapters.length) return null;
    final row = chapters[chapter];
    if (block < 0 || block >= row.length) return null;
    return row[block];
  }

  int translatedCount(BookContent content) {
    var n = 0;
    for (var c = 0; c < content.chapters.length && c < chapters.length; c++) {
      final blocks = content.chapters[c].blocks;
      for (var b = 0; b < blocks.length && b < chapters[c].length; b++) {
        if (_counts(blocks[b]) && chapters[c][b] != null) n++;
      }
    }
    return n;
  }

  static bool _counts(Block b) => !b.noTranslate && b.text.trim().isNotEmpty;

  bool isComplete(BookContent content) => translatedCount(content) >= content.translatableBlockCount;

  bool chapterComplete(BookContent content, int c) {
    if (c >= chapters.length) return false;
    final blocks = content.chapters[c].blocks;
    for (var b = 0; b < blocks.length; b++) {
      if (_counts(blocks[b]) && (b >= chapters[c].length || chapters[c][b] == null)) return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
        'format': 'bookit-translation',
        'version': 1,
        'lang': lang,
        'sourceLang': sourceLang,
        'engine': engine,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'chapters': chapters,
      };

  factory TranslationData.fromJson(Map<String, dynamic> j) => TranslationData(
        lang: j['lang'] as String,
        sourceLang: (j['sourceLang'] as String?) ?? 'eng_Latn',
        engine: (j['engine'] as String?) ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? ''),
        chapters: [
          for (final c in (j['chapters'] as List? ?? const []))
            [for (final b in (c as List)) b as String?]
        ],
      );

  static Future<TranslationData?> read(File f) async {
    if (!await f.exists()) return null;
    try {
      return TranslationData.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(File f) async {
    updatedAt = DateTime.now();
    final tmp = File('${f.path}.tmp');
    await tmp.parent.create(recursive: true);
    await tmp.writeAsString(jsonEncode(toJson()), flush: true);
    if (await f.exists()) await f.delete();
    await tmp.rename(f.path);
  }
}
