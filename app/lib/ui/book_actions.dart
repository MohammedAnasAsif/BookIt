import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../books/edition.dart';
import '../books/epub_writer.dart';
import '../core/app_paths.dart';
import '../core/languages.dart';
import '../data/library_store.dart';
import '../data/settings_store.dart';
import '../models/book.dart';
import '../translation/translation_service.dart';
import 'reader/reader_screen.dart';
import 'widgets/language_picker.dart';
import 'widgets/model_download.dart';

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
}

Future<void> openReader(BuildContext context, Book book, {String? lang, bool original = false}) async {
  final library = context.read<LibraryStore>();
  if (original) {
    book.readingLang = null;
  } else if (lang != null) {
    book.readingLang = lang;
  }
  await library.touch(book);
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReaderScreen(book: book)));
}

/// Asks for a language (unless given) and starts translating [book] on this
/// device. Returns the chosen language code, or null if cancelled.
Future<String?> translateBook(BuildContext context, Book book, {Language? lang}) async {
  final settings = context.read<SettingsStore>();
  final service = context.read<TranslationService>();
  lang ??= await pickLanguage(context,
      title: 'Translate into…', exclude: book.sourceLang, selected: settings.preferredLang);
  if (lang == null || !context.mounted) return null;
  if (lang.code == book.sourceLang) {
    showMessage(context, 'This book is already in ${lang.name}.');
    return null;
  }
  settings.update((s) => s.preferredLang ??= lang!.code);
  await ensureModelPack(context);
  if (!context.mounted) return null;
  if (service.packState == PackState.notInstalled) return null;
  await service.start(book, lang.code);
  book.readingLang = lang.code;
  if (!context.mounted) return lang.code;
  await context.read<LibraryStore>().save(book);
  if (!context.mounted) return lang.code;
  showMessage(
    context,
    service.packState == PackState.installed
        ? 'Translating into ${lang.name}. Start reading now — pages switch to ${lang.nativeName} as they are ready.'
        : 'Translation into ${lang.name} will start as soon as the download finishes.',
  );
  return lang.code;
}

/// Lets the user save an EPUB of the original or a translation.
Future<void> exportEpub(BuildContext context, Book book, {String? lang}) async {
  final library = context.read<LibraryStore>();
  final service = context.read<TranslationService>();
  try {
    final content = await library.content(book.id);
    final translation = lang == null ? null : await service.translation(book.id, lang);
    final coverFile = library.coverFile(book);
    final bytes = EpubWriter.write(
      content: content,
      translation: translation,
      cover: coverFile != null && coverFile.existsSync() ? coverFile.readAsBytesSync() : null,
      coverExtension: book.coverFile?.split('.').last,
    );
    final suffix = lang == null ? '' : '-${languageByCode(lang)?.name.toLowerCase().replaceAll(RegExp('[^a-z]'), '') ?? lang}';
    final name = '${_safeName(book.title)}$suffix.epub';
    if (!context.mounted) return;
    await _saveBytes(context, name, bytes);
  } catch (e) {
    if (context.mounted) showMessage(context, 'Could not export: $e');
  }
}

/// Saves a `.bookit` edition (book + translation) to share with others or to
/// contribute to the community library.
Future<void> exportEdition(BuildContext context, Book book, String lang) async {
  final library = context.read<LibraryStore>();
  final service = context.read<TranslationService>();
  try {
    final content = await library.content(book.id);
    final translation = await service.translation(book.id, lang);
    if (translation == null) throw StateError('No translation found');
    final coverFile = library.coverFile(book);
    final bytes = Edition(
      content: content,
      translation: translation,
      sourceLang: book.sourceLang,
      gutenbergId: book.gutenbergId,
      cover: coverFile != null && coverFile.existsSync() ? coverFile.readAsBytesSync() : null,
      coverExtension: book.coverFile?.split('.').last,
    ).encode();
    final l = languageByCode(lang);
    if (!context.mounted) return;
    await _saveBytes(context, '${_safeName(book.title)}.${l?.iso1 ?? lang}.bookit', bytes);
  } catch (e) {
    if (context.mounted) showMessage(context, 'Could not export: $e');
  }
}

String _safeName(String s) {
  final n = s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  return n.isEmpty ? 'book' : (n.length > 60 ? n.substring(0, 60) : n);
}

Future<void> _saveBytes(BuildContext context, String name, Uint8List bytes) async {
  String? path;
  if (Platform.isAndroid || Platform.isIOS) {
    path = await FilePicker.saveFile(fileName: name, bytes: bytes);
  } else {
    path = await FilePicker.saveFile(fileName: name);
    if (path != null) await File(path).writeAsBytes(bytes);
  }
  if (path != null && context.mounted) showMessage(context, 'Saved $name');
}

/// Opens a file picker and imports an EPUB, TXT or .bookit file.
Future<void> importBook(BuildContext context) async {
  final library = context.read<LibraryStore>();
  final result = await FilePicker.pickFiles(
    type: FileType.any,
    allowMultiple: false,
  );
  final path = result?.files.single.path;
  if (path == null) return;
  if (!context.mounted) return;
  showMessage(context, 'Adding book…');
  try {
    final book = await library.importFile(path);
    if (context.mounted) showMessage(context, 'Added “${book.title}” to your library');
  } catch (e) {
    if (context.mounted) showMessage(context, e is FormatException ? e.message : 'Could not open this file: $e');
  }
}

/// Total size of downloaded books and models, for the settings screen.
Future<int> storageUsed() async {
  var total = 0;
  if (await AppPaths.root.exists()) {
    await for (final e in AppPaths.root.list(recursive: true, followLinks: false)) {
      if (e is File) total += await e.length();
    }
  }
  return total;
}
