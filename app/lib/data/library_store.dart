import 'dart:convert';
import 'dart:io';
import 'dart:isolate';


import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../books/edition.dart';
import '../books/epub_parser.dart';
import '../books/txt_parser.dart';
import '../core/app_paths.dart';
import '../core/downloader.dart';
import '../core/languages.dart';
import '../models/book.dart';
import '../models/book_content.dart';
import '../translation/translation_data.dart';
import 'gutendex.dart';

/// The user's books on this device.
class LibraryStore extends ChangeNotifier {
  final List<Book> _books = [];
  final Map<String, BookContent> _contentCache = {};
  final Map<String, Set<String>> _translationLangs = {};
  bool loaded = false;

  /// Book ids currently being downloaded or imported, with progress 0..1.
  final Map<String, double> pending = {};

  List<Book> get books => List.unmodifiable(_books);

  List<Book> get recent {
    final l = _books.where((b) => b.lastOpenedAt != null).toList()
      ..sort((a, b) => b.lastOpenedAt!.compareTo(a.lastOpenedAt!));
    return l;
  }

  Book? byId(String id) {
    for (final b in _books) {
      if (b.id == id) return b;
    }
    return null;
  }

  Book? byGutenbergId(int id) {
    for (final b in _books) {
      if (b.gutenbergId == id) return b;
    }
    return null;
  }

  Set<String> translationLangs(String bookId) => _translationLangs[bookId] ?? const {};

  Future<void> load() async {
    _books.clear();
    final dir = AppPaths.books;
    if (await dir.exists()) {
      await for (final e in dir.list()) {
        if (e is! Directory) continue;
        final meta = File(p.join(e.path, 'book.json'));
        if (!await meta.exists()) continue;
        try {
          final b = Book.fromJson(jsonDecode(await meta.readAsString()) as Map<String, dynamic>);
          _books.add(b);
          await _scanTranslations(b.id);
        } catch (_) {}
      }
    }
    _books.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    loaded = true;
    notifyListeners();
  }

  Future<void> _scanTranslations(String id) async {
    final dir = AppPaths.translations(id);
    final langs = <String>{};
    if (await dir.exists()) {
      await for (final f in dir.list()) {
        if (f is File && f.path.endsWith('.json')) langs.add(p.basenameWithoutExtension(f.path));
      }
    }
    _translationLangs[id] = langs;
  }

  void registerTranslation(String bookId, String lang) {
    final s = _translationLangs.putIfAbsent(bookId, () => <String>{});
    if (s.add(lang)) notifyListeners();
  }

  Future<void> save(Book b) async {
    final f = AppPaths.bookMeta(b.id);
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(b.toJson()));
  }

  File? coverFile(Book b) => b.coverFile == null ? null : File(p.join(AppPaths.bookDir(b.id).path, b.coverFile!));

  Future<BookContent> content(String id) async {
    final cached = _contentCache[id];
    if (cached != null) return cached;
    final c = await Isolate.run(_ContentLoader(AppPaths.bookContent(id).path).call);
    if (_contentCache.length > 3) _contentCache.remove(_contentCache.keys.first);
    _contentCache[id] = c;
    return c;
  }

  Future<void> touch(Book b) async {
    b.lastOpenedAt = DateTime.now();
    await save(b);
    notifyListeners();
  }

  Future<void> updatePosition(Book b, ReadingPosition pos, {String? readingLang, bool keepLang = true}) async {
    b.position = pos;
    if (!keepLang) b.readingLang = readingLang;
    await save(b);
  }

  Future<void> delete(Book b) async {
    _books.remove(b);
    _contentCache.remove(b.id);
    _translationLangs.remove(b.id);
    final dir = AppPaths.bookDir(b.id);
    if (await dir.exists()) await dir.delete(recursive: true);
    notifyListeners();
  }

  Future<void> deleteTranslation(Book b, String lang) async {
    final f = AppPaths.translation(b.id, lang);
    if (await f.exists()) await f.delete();
    _translationLangs[b.id]?.remove(lang);
    if (b.readingLang == lang) {
      b.readingLang = null;
      await save(b);
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- adding

  /// Downloads a Project Gutenberg book and adds it to the library.
  Future<Book> addFromCatalog(CatalogBook cb) async {
    final existing = byGutenbergId(cb.id);
    if (existing != null) return existing;
    final id = 'pg${cb.id}';
    pending[id] = 0;
    notifyListeners();
    try {
      final tmp = File(p.join(AppPaths.cache.path, 'download-$id'));
      final url = cb.epubUrl ?? cb.textUrl!;
      await Downloader.toFile(url, tmp, onProgress: (r, t) {
        if (t > 0) {
          pending[id] = (r / t).clamp(0, 1).toDouble();
          notifyListeners();
        }
      });
      final bytes = await tmp.readAsBytes();
      await tmp.delete();
      Uint8List? cover;
      if (cb.coverUrl != null) {
        try {
          cover = await Downloader.getBytes(cb.coverUrl!);
        } catch (_) {}
      }
      final isEpub = cb.epubUrl != null;
      final book = await _addParsed(
        id: id,
        source: 'gutenberg',
        gutenbergId: cb.id,
        bytes: bytes,
        isEpub: isEpub,
        titleOverride: cb.title,
        authorOverride: cb.authorLine,
        languageHint: cb.languages.isNotEmpty ? cb.languages.first : null,
        coverOverride: cover,
      );
      return book;
    } finally {
      pending.remove(id);
      notifyListeners();
    }
  }

  /// Imports a local EPUB, TXT or `.bookit` edition file.
  Future<Book> importFile(String path) async => importBytes(p.basename(path), await File(path).readAsBytes());

  /// Imports an EPUB, TXT or `.bookit` file given its name and contents.
  Future<Book> importBytes(String fileName, Uint8List bytes) async {
    final path = fileName;
    final ext = p.extension(fileName).toLowerCase();
    if (ext == '.bookit') return addEdition(bytes);
    final id = 'imp${DateTime.now().millisecondsSinceEpoch}';
    if (ext != '.epub' && ext != '.txt') {
      throw const FormatException('BookIt can open EPUB, TXT and .bookit files.');
    }
    return _addParsed(
      id: id,
      source: 'import',
      bytes: bytes,
      isEpub: ext == '.epub',
      titleOverride: ext == '.txt' ? p.basenameWithoutExtension(path) : null,
    );
  }

  Future<Book> _addParsed({
    required String id,
    required String source,
    required Uint8List bytes,
    required bool isEpub,
    int? gutenbergId,
    String? titleOverride,
    String? authorOverride,
    String? languageHint,
    Uint8List? coverOverride,
  }) async {
    final parsed = await Isolate.run(_BookParser(bytes, isEpub, titleOverride ?? 'Untitled').call);
    var content = BookContent.fromJson(parsed[0] as Map<String, dynamic>);
    if (content.chapters.isEmpty) throw const FormatException('No readable text found in this book.');
    final title = (content.title == 'Untitled' || content.title.isEmpty) ? (titleOverride ?? content.title) : content.title;
    final author = content.author.isEmpty ? (authorOverride ?? '') : content.author;
    content = BookContent(title: title, author: author, language: content.language, chapters: content.chapters);

    final dir = AppPaths.bookDir(id);
    await dir.create(recursive: true);
    await AppPaths.bookContent(id).writeAsString(jsonEncode(content.toJson()));
    if (isEpub) await File(p.join(dir.path, 'original.epub')).writeAsBytes(bytes);

    String? coverName;
    final coverBytes = coverOverride ?? parsed[1] as Uint8List?;
    if (coverBytes != null) {
      final ext = coverOverride != null ? 'jpg' : ((parsed[2] as String?) ?? 'jpg');
      coverName = 'cover.$ext';
      await File(p.join(dir.path, coverName)).writeAsBytes(coverBytes);
    }
    final lang = languageByIso(content.language) ?? languageByIso(languageHint) ?? englishLanguage;
    final book = Book(
      id: id,
      title: title,
      author: author,
      source: source,
      sourceLang: lang.code,
      gutenbergId: gutenbergId,
      coverFile: coverName,
    );
    await save(book);
    _books.insert(0, book);
    _contentCache[id] = content;
    _translationLangs[id] = {};
    notifyListeners();
    return book;
  }

  /// Adds a `.bookit` edition (book + translation).
  Future<Book> addEdition(Uint8List bytes) async {
    final ed = await Isolate.run(_EditionDecoder(bytes).call);
    final id = ed.gutenbergId != null ? 'pg${ed.gutenbergId}' : 'ed${DateTime.now().millisecondsSinceEpoch}';
    var book = byId(id);
    if (book == null) {
      final dir = AppPaths.bookDir(id);
      await dir.create(recursive: true);
      await AppPaths.bookContent(id).writeAsString(jsonEncode(ed.content.toJson()));
      String? coverName;
      if (ed.cover != null) {
        coverName = 'cover.${ed.coverExtension ?? 'jpg'}';
        await File(p.join(dir.path, coverName)).writeAsBytes(ed.cover!);
      }
      book = Book(
        id: id,
        title: ed.content.title,
        author: ed.content.author,
        source: 'edition',
        sourceLang: ed.sourceLang,
        gutenbergId: ed.gutenbergId,
        coverFile: coverName,
      );
      _books.insert(0, book);
      _contentCache[id] = ed.content;
    } else {
      // Same book already here: align the translation with our content.
      final mine = await content(id);
      if (mine.blockCount != ed.content.blockCount) {
        // Different parse of the book; keep the edition's text as the content.
        await AppPaths.bookContent(id).writeAsString(jsonEncode(ed.content.toJson()));
        _contentCache[id] = ed.content;
        for (final l in translationLangs(id).toList()) {
          if (l != ed.translation.lang) await deleteTranslation(book, l);
        }
      }
    }
    await ed.translation.write(AppPaths.translation(id, ed.translation.lang));
    book.readingLang = ed.translation.lang;
    await save(book);
    registerTranslation(id, ed.translation.lang);
    notifyListeners();
    return book;
  }

  Future<TranslationData?> readTranslation(String bookId, String lang) =>
      TranslationData.read(AppPaths.translation(bookId, lang));

  // ---------------------------------------------------------------- bookmarks

  Future<List<Bookmark>> bookmarks(String id) async {
    final f = AppPaths.bookmarks(id);
    if (!await f.exists()) return [];
    try {
      return [
        for (final b in (jsonDecode(await f.readAsString()) as List))
          Bookmark.fromJson((b as Map).cast<String, dynamic>())
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveBookmarks(String id, List<Bookmark> list) async {
    await AppPaths.bookmarks(id).writeAsString(jsonEncode([for (final b in list) b.toJson()]));
  }
}

// Work done on background isolates. These small classes hold only plain data,
// so nothing else from the app gets copied into the isolate.

class _ContentLoader {
  final String path;
  _ContentLoader(this.path);
  BookContent call() => BookContent.fromJson(jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>);
}

class _BookParser {
  final Uint8List bytes;
  final bool isEpub;
  final String title;
  _BookParser(this.bytes, this.isEpub, this.title);

  List<Object?> call() {
    if (isEpub) {
      final r = EpubParser.parse(bytes);
      return [r.content.toJson(), r.coverBytes, r.coverExtension];
    }
    final c = TxtParser.parse(TxtParser.decode(bytes), title: title);
    return [c.toJson(), null, null];
  }
}

class _EditionDecoder {
  final Uint8List bytes;
  _EditionDecoder(this.bytes);
  Edition call() => Edition.decode(bytes);
}
