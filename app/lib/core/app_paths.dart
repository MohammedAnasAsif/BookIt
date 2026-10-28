import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where BookIt keeps its files. Everything lives in the app's private
/// support folder, so books and translations work fully offline.
class AppPaths {
  static late Directory root;

  static Future<void> init() async {
    final base = await getApplicationSupportDirectory();
    root = Directory(p.join(base.path, 'BookIt'));
    await root.create(recursive: true);
    await books.create(recursive: true);
    await models.create(recursive: true);
    await cache.create(recursive: true);
  }

  static Directory get books => Directory(p.join(root.path, 'books'));
  static Directory get models => Directory(p.join(root.path, 'models'));
  static Directory get cache => Directory(p.join(root.path, 'cache'));

  static Directory bookDir(String id) => Directory(p.join(books.path, id));
  static File bookMeta(String id) => File(p.join(bookDir(id).path, 'book.json'));
  static File bookContent(String id) => File(p.join(bookDir(id).path, 'content.json'));
  static File bookmarks(String id) => File(p.join(bookDir(id).path, 'bookmarks.json'));
  static File translation(String id, String lang) =>
      File(p.join(bookDir(id).path, 'translations', '$lang.json'));
  static Directory translations(String id) => Directory(p.join(bookDir(id).path, 'translations'));
  static File settings() => File(p.join(root.path, 'settings.json'));
  static File jobs() => File(p.join(root.path, 'translation_jobs.json'));
}
