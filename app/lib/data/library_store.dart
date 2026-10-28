import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';


import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../books/edition.dart';
import '../books/epub_parser.dart';
import '../books/txt_parser.dart';
import '../core/app_paths.dart';
import '../core/cover_cache.dart';
import '../core/downloader.dart';
import '../core/languages.dart';
import '../models/book.dart';
import '../models/book_content.dart';
import '../translation/translation_data.dart';
import 'catalog.dart';

/// The user's books on this device.
class LibraryStore extends ChangeNotifier {
  final List<Book> _books = [];
  final Map<String, BookContent> _contentCache = {};
  final Map<String, Set<String>> _translationLangs = {};
  bool loaded = false;

  /// Book ids currently being downloaded or imported, with progress 0..1.
  final Map<String, double> pending = {};

  /// Books saved to the library (excludes books only opened with "Read now").
  List<Book> get books => List.unmodifiable(_books.where((b) => !b.temporary));

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
    // Forget books read online that haven't been opened for 30 days.
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    for (final b in _books.where((b) => b.temporary && (b.lastOpenedAt ?? b.addedAt).isBefore(cutoff)).toList()) {
      if (translationLangs(b.id).isEmpty) await delete(b);
    }
    loaded = true;
    notifyListeners();
  }

  /// Saves a book opened with "Read now" to the library.
  Future<void> keep(Book b) async {
    if (!b.temporary) return;
    b.temporary = false;
    await save(b);
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

  /// Downloads a Project Gutenberg book. With [temporary] the book is only
  /// opened ("Read now") and not shown in the library until it is saved.
  Future<Book> addFromCatalog(CatalogBook cb, {bool temporary = false}) async {
    final existing = byGutenbergId(cb.id);
    if (existing != null) {
      if (!temporary) await keep(existing);
      return existing;
    }
    final id = 'pg${cb.id}';
    pending[id] = 0;
    notifyListeners();
    try {
      final tmp = File(p.join(AppPaths.cache.path, 'download-$id.epub'));
      Object? lastError;
      Uint8List? bytes;
      for (final url in cb.epubUrls) {
        try {
          await Downloader.toFile(url, tmp, onProgress: (r, t) {
            if (t > 0) {
              pending[id] = (r / t).clamp(0, 1).toDouble();
              notifyListeners();
            }
          });
          bytes = await tmp.readAsBytes();
          await tmp.delete();
          break;
        } catch (e) {
          lastError = e;
          try {
            if (await tmp.exists()) await tmp.delete();
          } catch (_) {}
        }
      }
      if (bytes == null) throw BookDownloadException(cb.title, lastError);
      final coverFile = await CoverCache.get(cb.coverKey, cb.coverUrls);
      final book = await _addParsed(
        id: id,
        source: 'gutenberg',
        gutenbergId: cb.id,
        bytes: bytes,
        isEpub: true,
        titleOverride: cb.title,
        authorOverride: cb.authorLine,
        languageHint: cb.languages.isNotEmpty ? cb.languages.first : null,
        coverOverride: coverFile == null ? null : await coverFile.readAsBytes(),
        temporary: temporary,
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
    bool temporary = false,
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
    // Open at the start of the book itself, after licence/boilerplate pages.
    var startChapter = content.chapters.indexWhere(
        (c) => c.blocks.any((b) => !b.noTranslate && b.text.trim().isNotEmpty && !b.isHeading));
    if (startChapter < 0) startChapter = 0;
    final book = Book(
      id: id,
      title: title,
      author: author,
      source: source,
      sourceLang: lang.code,
      gutenbergId: gutenbergId,
      coverFile: coverName,
      temporary: temporary,
      position: ReadingPosition(startChapter, 0, 0),
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

/// A book could not be downloaded; explains why in plain words.
class BookDownloadException implements Exception {
  final String title;
  final Object? cause;
  BookDownloadException(this.title, this.cause);

  String get reason {
    final c = cause;
    if (c is SocketException || c is TimeoutException || c is HandshakeException) {
      return 'BookIt could not connect to Project Gutenberg (www.gutenberg.org). '
          'Check your internet connection, or whether a firewall, VPN or antivirus is blocking BookIt.';
    }
    if (c is HttpException) return 'Project Gutenberg answered with an error (${c.message}).';
    return 'The download failed.';
  }

  @override
  String toString() => '$reason\n\nDetails: $cause';
}
