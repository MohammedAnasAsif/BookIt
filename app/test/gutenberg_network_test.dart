import 'dart:io';

import 'package:bookit/books/epub_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Downloads real Project Gutenberg books and checks they parse into
/// readable chapters. Needs internet; runs in CI with RUN_NETWORK_TESTS=1.
void main() {
  final enabled = Platform.environment['RUN_NETWORK_TESTS'] == '1';

  const books = {
    1342: 'Pride and Prejudice',
    37106: 'Little Women',
    11: "Alice's Adventures in Wonderland",
    7164: 'Gitanjali',
    236: 'The Jungle Book',
    2600: 'War and Peace',
  };

  for (final entry in books.entries) {
    test('downloads and parses #${entry.key} ${entry.value}', () async {
      final url = 'https://www.gutenberg.org/cache/epub/${entry.key}/pg${entry.key}.epub';
      final r = await http.get(Uri.parse(url), headers: {'User-Agent': 'BookIt test'});
      expect(r.statusCode, 200);
      final sw = Stopwatch()..start();
      final parsed = EpubParser.parse(r.bodyBytes);
      sw.stop();
      final c = parsed.content;
      final blocks = c.chapters.fold<int>(0, (n, ch) => n + ch.blocks.length);
      // ignore: avoid_print
      print('#${entry.key}: ${r.bodyBytes.length ~/ 1024} KB, ${c.chapters.length} chapters, $blocks blocks, '
          'parsed in ${sw.elapsedMilliseconds} ms, title "${c.title}", cover ${parsed.coverBytes?.length ?? 0} bytes, '
          'first chapters: ${c.chapters.take(4).map((x) => x.title).join(" | ")}');
      expect(c.title.toLowerCase(), contains(entry.value.toLowerCase().split(' ').first.replaceAll("'s", '')));
      expect(c.chapters.length, greaterThan(1));
      expect(blocks, greaterThan(50));
    }, skip: !enabled, timeout: const Timeout(Duration(minutes: 3)));
  }

  test('parses the large illustrated EPUB too', () async {
    final r = await http.get(Uri.parse('https://www.gutenberg.org/ebooks/1342.epub3.images'));
    expect(r.statusCode, 200);
    final c = EpubParser.parse(r.bodyBytes).content;
    expect(c.chapters.length, greaterThan(10));
  }, skip: !enabled, timeout: const Timeout(Duration(minutes: 3)));
}
