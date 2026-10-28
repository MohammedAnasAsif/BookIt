import 'dart:convert';
import 'dart:typed_data';

import '../models/book_content.dart';

/// Converts a plain-text book (e.g. a Project Gutenberg .txt) into chapters.
class TxtParser {
  static final _chapterLine = RegExp(
    r'^(chapter|book|part|volume|act|canto|letter|stave)\b[\s\w.:,\-–—]{0,60}$',
    caseSensitive: false,
  );
  static final _romanLine = RegExp(r'^[IVXLC]{1,8}\.?$');

  static String decode(Uint8List bytes) {
    try {
      var s = utf8.decode(bytes);
      if (s.startsWith('﻿')) s = s.substring(1);
      return s;
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  static BookContent parse(String text, {String title = 'Untitled', String author = ''}) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final paragraphs = normalized
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).join(' '))
        .where((p) => p.isNotEmpty)
        .toList();

    // Project Gutenberg boilerplate markers.
    final startIdx = paragraphs.indexWhere((p) => p.startsWith('*** START OF'));
    final endIdx = paragraphs.indexWhere((p) => p.startsWith('*** END OF'));
    var guessedTitle = title;
    var guessedAuthor = author;
    for (final p in paragraphs.take(40)) {
      if (p.startsWith('Title:') && guessedTitle == 'Untitled') guessedTitle = p.substring(6).trim();
      if (p.startsWith('Author:') && guessedAuthor.isEmpty) guessedAuthor = p.substring(7).trim();
    }

    final chapters = <Chapter>[];
    var current = <Block>[];
    String? currentTitle;
    void flush() {
      if (current.isNotEmpty) {
        chapters.add(Chapter(currentTitle ?? 'Section ${chapters.length + 1}', current));
      }
      current = [];
      currentTitle = null;
    }

    for (var i = 0; i < paragraphs.length; i++) {
      final p = paragraphs[i];
      final boiler = (startIdx >= 0 && i <= startIdx) || (endIdx >= 0 && i >= endIdx);
      if (boiler) {
        current.add(Block(BlockKind.paragraph, p, noTranslate: true));
        if (i == startIdx) flush();
        continue;
      }
      final isHeading = p.length <= 70 && (_chapterLine.hasMatch(p) || _romanLine.hasMatch(p));
      if (isHeading) {
        flush();
        currentTitle = p;
        current.add(Block(BlockKind.heading1, p));
        continue;
      }
      current.add(Block(BlockKind.paragraph, p, noTranslate: hasNoLetters(p)));
      if (current.length >= 400) {
        final t = currentTitle;
        flush();
        currentTitle = t == null ? null : '$t (cont.)';
      }
    }
    flush();
    return BookContent(title: guessedTitle, author: guessedAuthor, language: '', chapters: chapters);
  }
}
