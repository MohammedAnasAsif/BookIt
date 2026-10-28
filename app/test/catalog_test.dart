import 'package:bookit/data/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled catalog loads and searches', () async {
    final c = await LocalCatalog.load();
    expect(c.books.length, greaterThan(50000));
    final pride = c.search(query: 'pride and prejudice austen');
    expect(pride.first.id, 1342);
    final tagore = c.search(query: 'gitanjali', shelf: 'I');
    expect(tagore.map((b) => b.id), contains(7164));
    final popular = c.search(limit: 10);
    expect(popular.first.rank, 1);
    final page2 = c.search(limit: 10, offset: 10);
    expect(page2.first.rank, greaterThan(popular.last.rank));
    expect(c.search(language: 'en', limit: 5).every((b) => b.languages.contains('en')), isTrue);
  });

  test('featured shelves resolve to catalog books', () async {
    final featured = await FeaturedBooks.load();
    expect(featured.where((f) => f.shelf == 'india').length, greaterThanOrEqualTo(8));
    expect(featured.map((f) => f.book.id), containsAll([1342, 11, 236, 7164]));
  });
}
