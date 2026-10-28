/// The reading model of a book: chapters made of simple text blocks.
///
/// Every book (EPUB, TXT or community edition) is converted into this model
/// once and stored as `content.json`. Translations are stored separately and
/// are aligned block-by-block with this content, which is what lets the reader
/// switch between the original and the translation on the same page.
library;

enum BlockKind {
  heading1,
  heading2,
  heading3,
  paragraph,
  quote,
  preformatted,
  listItem,
  separator,
}

const _kindCodes = {
  BlockKind.heading1: 'h1',
  BlockKind.heading2: 'h2',
  BlockKind.heading3: 'h3',
  BlockKind.paragraph: 'p',
  BlockKind.quote: 'q',
  BlockKind.preformatted: 'pre',
  BlockKind.listItem: 'li',
  BlockKind.separator: 'hr',
};
final _codeKinds = {for (final e in _kindCodes.entries) e.value: e.key};

class Block {
  final BlockKind kind;
  final String text;

  /// Blocks that should be shown as-is in translations (licence boilerplate,
  /// separators, numbers only).
  final bool noTranslate;

  const Block(this.kind, this.text, {this.noTranslate = false});

  bool get isHeading =>
      kind == BlockKind.heading1 || kind == BlockKind.heading2 || kind == BlockKind.heading3;

  Map<String, dynamic> toJson() => {
        'k': _kindCodes[kind],
        't': text,
        if (noTranslate) 'n': 1,
      };

  factory Block.fromJson(Map<String, dynamic> j) => Block(
        _codeKinds[j['k']] ?? BlockKind.paragraph,
        (j['t'] as String?) ?? '',
        noTranslate: j['n'] == 1 || j['n'] == true,
      );
}

class Chapter {
  final String title;
  final List<Block> blocks;

  const Chapter(this.title, this.blocks);

  Map<String, dynamic> toJson() => {
        'title': title,
        'blocks': [for (final b in blocks) b.toJson()],
      };

  factory Chapter.fromJson(Map<String, dynamic> j) => Chapter(
        (j['title'] as String?) ?? '',
        [for (final b in (j['blocks'] as List? ?? const [])) Block.fromJson(b as Map<String, dynamic>)],
      );

  int get characterCount => blocks.fold(0, (n, b) => n + b.text.length);
}

class BookContent {
  final String title;
  final String author;

  /// ISO 639-1 language code from the book's metadata (may be empty).
  final String language;
  final List<Chapter> chapters;

  const BookContent({
    required this.title,
    required this.author,
    required this.language,
    required this.chapters,
  });

  int get blockCount => chapters.fold(0, (n, c) => n + c.blocks.length);

  int get translatableBlockCount => chapters.fold(
      0, (n, c) => n + c.blocks.where((b) => !b.noTranslate && b.text.trim().isNotEmpty).length);

  int get characterCount => chapters.fold(0, (n, c) => n + c.characterCount);

  Map<String, dynamic> toJson() => {
        'format': 'bookit-content',
        'version': 1,
        'title': title,
        'author': author,
        'language': language,
        'chapters': [for (final c in chapters) c.toJson()],
      };

  factory BookContent.fromJson(Map<String, dynamic> j) => BookContent(
        title: (j['title'] as String?) ?? 'Untitled',
        author: (j['author'] as String?) ?? '',
        language: (j['language'] as String?) ?? '',
        chapters: [
          for (final c in (j['chapters'] as List? ?? const [])) Chapter.fromJson(c as Map<String, dynamic>)
        ],
      );
}

/// Returns true when a text has no letters at all (numbers, "* * *", ...).
bool hasNoLetters(String text) => !RegExp(r'\p{L}', unicode: true).hasMatch(text);
