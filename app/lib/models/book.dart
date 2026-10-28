/// Library metadata for one book. Stored as `book.json` in the book's folder.
class Book {
  final String id;
  String title;
  String author;

  /// Where the book came from: `gutenberg`, `import` or `edition`
  /// (a ready-made translated edition from the community library).
  final String source;
  final int? gutenbergId;

  /// FLORES-200 code of the book's original language, e.g. `eng_Latn`.
  String sourceLang;

  /// File name of the cover image inside the book folder, if any.
  String? coverFile;

  final DateTime addedAt;
  DateTime? lastOpenedAt;

  /// Language code of the edition shown in the reader, or null for the original.
  String? readingLang;

  /// Saved reading position.
  ReadingPosition position;

  /// Opened with "Read now" and not saved to the library yet. Temporary books
  /// show under "Continue reading" but not in the library, and are cleaned up
  /// after 30 days without reading.
  bool temporary;

  Book({
    required this.id,
    required this.title,
    required this.author,
    required this.source,
    required this.sourceLang,
    this.gutenbergId,
    this.coverFile,
    DateTime? addedAt,
    this.lastOpenedAt,
    this.readingLang,
    ReadingPosition? position,
    this.temporary = false,
  })  : addedAt = addedAt ?? DateTime.now(),
        position = position ?? const ReadingPosition(0, 0, 0);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'source': source,
        'sourceLang': sourceLang,
        if (gutenbergId != null) 'gutenbergId': gutenbergId,
        if (coverFile != null) 'coverFile': coverFile,
        'addedAt': addedAt.toIso8601String(),
        if (lastOpenedAt != null) 'lastOpenedAt': lastOpenedAt!.toIso8601String(),
        if (readingLang != null) 'readingLang': readingLang,
        'position': position.toJson(),
        if (temporary) 'temporary': true,
      };

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? 'Untitled',
        author: (j['author'] as String?) ?? '',
        source: (j['source'] as String?) ?? 'import',
        sourceLang: (j['sourceLang'] as String?) ?? 'eng_Latn',
        gutenbergId: j['gutenbergId'] as int?,
        coverFile: j['coverFile'] as String?,
        addedAt: DateTime.tryParse(j['addedAt'] as String? ?? ''),
        lastOpenedAt: DateTime.tryParse(j['lastOpenedAt'] as String? ?? ''),
        readingLang: j['readingLang'] as String?,
        position: j['position'] is Map
            ? ReadingPosition.fromJson((j['position'] as Map).cast<String, dynamic>())
            : null,
        temporary: j['temporary'] == true,
      );
}

/// A place in a book: chapter, block inside the chapter and how far into the
/// block (0..1). Using a fraction keeps the position meaningful when switching
/// between the original and a translation of different length.
class ReadingPosition {
  final int chapter;
  final int block;
  final double fraction;

  /// Overall progress through the book, 0..1 (for display only).
  final double progress;

  const ReadingPosition(this.chapter, this.block, this.fraction, [this.progress = 0]);

  Map<String, dynamic> toJson() => {'c': chapter, 'b': block, 'f': fraction, 'p': progress};

  factory ReadingPosition.fromJson(Map<String, dynamic> j) => ReadingPosition(
        (j['c'] as num?)?.toInt() ?? 0,
        (j['b'] as num?)?.toInt() ?? 0,
        (j['f'] as num?)?.toDouble() ?? 0,
        (j['p'] as num?)?.toDouble() ?? 0,
      );
}

class Bookmark {
  final ReadingPosition position;
  final String snippet;
  final DateTime createdAt;

  Bookmark(this.position, this.snippet, [DateTime? createdAt]) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() =>
      {'pos': position.toJson(), 'snippet': snippet, 'at': createdAt.toIso8601String()};

  factory Bookmark.fromJson(Map<String, dynamic> j) => Bookmark(
        ReadingPosition.fromJson((j['pos'] as Map).cast<String, dynamic>()),
        (j['snippet'] as String?) ?? '',
        DateTime.tryParse(j['at'] as String? ?? ''),
      );
}
