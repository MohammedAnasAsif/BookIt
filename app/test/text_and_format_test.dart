import 'dart:convert';
import 'dart:io';

import 'package:bookit/books/edition.dart';
import 'package:bookit/books/epub_parser.dart';
import 'package:bookit/books/epub_writer.dart';
import 'package:bookit/books/txt_parser.dart';
import 'package:bookit/core/languages.dart';
import 'package:bookit/models/book_content.dart';
import 'package:bookit/translation/engine/text_segmenter.dart';
import 'package:bookit/translation/translation_data.dart';
import 'package:flutter_test/flutter_test.dart';

BookContent sampleBook() => const BookContent(
      title: 'The Garden & the Gate',
      author: 'A. Writer',
      language: 'en',
      chapters: [
        Chapter('Chapter One', [
          Block(BlockKind.heading1, 'Chapter One'),
          Block(BlockKind.paragraph, 'The rain had stopped. Mr. Rao walked to the gate, smiling — it was open!'),
          Block(BlockKind.paragraph, '“Who left this open?” he asked.'),
          Block(BlockKind.separator, '', noTranslate: true),
          Block(BlockKind.quote, 'A short quoted line.'),
        ]),
        Chapter('Chapter Two', [
          Block(BlockKind.heading1, 'Chapter Two'),
          Block(BlockKind.paragraph, 'Nobody answered.'),
          Block(BlockKind.listItem, 'One item'),
        ]),
      ],
    );

void main() {
  group('TextSegmenter', () {
    test('splits sentences and keeps abbreviations together', () {
      final s = TextSegmenter.split('The rain had stopped. Mr. Rao walked to the gate. It was open!');
      expect(s, ['The rain had stopped.', 'Mr. Rao walked to the gate.', 'It was open!']);
    });

    test('handles closing quotes and Indic danda', () {
      expect(TextSegmenter.split('“Is it?” she asked. Yes.'), ['“Is it?” she asked. Yes.']);
      expect(TextSegmenter.split('मैं घर जा रहा हूँ। तुम कहाँ हो?'), ['मैं घर जा रहा हूँ।', 'तुम कहाँ हो?']);
    });

    test('splits very long sentences', () {
      final long = List.filled(80, 'word, another').join(' ');
      final parts = TextSegmenter.split(long, maxChars: 200);
      expect(parts.every((p) => p.length <= 200), isTrue);
      expect(parts.join(' ').replaceAll(' ', ''), long.replaceAll(' ', ''));
    });

    test('replaces characters unknown to the model', () {
      expect(TextSegmenter.prepareForModel('“Well,” he said — ‘fine’'), '"Well," he said - \'fine\'');
    });

    test('joins without spaces for Chinese/Japanese/Thai', () {
      expect(TextSegmenter.join(['你好。', '再见。'], 'zho_Hans'), '你好。再见。');
      expect(TextSegmenter.join(['Hello.', 'Bye.'], 'fra_Latn'), 'Hello. Bye.');
    });
  });

  group('Languages', () {
    test('every language code exists in the NLLB vocabulary', () {
      final codes = (jsonDecode(File('test/fixtures/nllb_lang_codes.json').readAsStringSync()) as List).toSet();
      for (final l in kLanguages) {
        expect(codes.contains(l.code), isTrue, reason: '${l.code} (${l.name}) is not an NLLB language');
      }
      expect(kLanguages.map((l) => l.code).toSet().length, kLanguages.length, reason: 'duplicate codes');
      expect(kLanguages.where((l) => l.group == LanguageGroup.indian).length, greaterThanOrEqualTo(20));
    });

    test('maps Gutenberg language codes', () {
      expect(languageByIso('en')?.code, 'eng_Latn');
      expect(languageByIso('en-GB')?.code, 'eng_Latn');
      expect(languageByIso('ta')?.code, 'tam_Taml');
      expect(languageByCode('urd_Arab')?.isRtl, isTrue);
    });
  });

  group('EPUB', () {
    test('writing then parsing an EPUB keeps chapters and blocks', () {
      final content = sampleBook();
      final bytes = EpubWriter.write(content: content);
      final parsed = EpubParser.parse(bytes);
      expect(parsed.content.title, content.title);
      expect(parsed.content.author, content.author);
      expect(parsed.content.chapters.length, 2);
      expect(parsed.content.chapters[0].title, 'Chapter One');
      final texts = parsed.content.chapters[0].blocks.map((b) => b.text).toList();
      expect(texts, contains('“Who left this open?” he asked.'));
      expect(parsed.content.chapters[0].blocks.first.kind, BlockKind.heading1);
      expect(parsed.content.chapters[1].blocks.map((b) => b.text), contains('Nobody answered.'));
    });

    test('translated EPUB uses the translation text and language', () {
      final content = sampleBook();
      final t = TranslationData.emptyFor(content, 'hin_Deva', 'eng_Latn', 'test');
      t.chapters[0][1] = 'बारिश रुक गई थी।';
      final bytes = EpubWriter.write(content: content, translation: t);
      final parsed = EpubParser.parse(bytes);
      expect(parsed.content.language, 'hi');
      expect(parsed.content.chapters[0].blocks.map((b) => b.text), contains('बारिश रुक गई थी।'));
    });

    test('splits chapters at table-of-contents anchors inside one file', () {
      const html = '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>x</title></head><body>
<section id="pg-header" class="pg-boilerplate"><p>The Project Gutenberg eBook of Something</p></section>
<div class="chapter"><h2><a id="c1"></a>CHAPTER I.</h2><p>First&nbsp;paragraph<span class="pagenum"><a id="Page_1">[1]</a></span> here.</p></div>
<div class="chapter"><h2 id="c2">CHAPTER II.</h2><p>Second.</p><hr/><blockquote><p>Quote</p></blockquote></div>
</body></html>''';
      final chapters = EpubParser.htmlToChapters(html);
      expect(chapters.length, 1); // no anchors given -> one chapter
      final all = chapters.expand((c) => c.blocks).toList();
      expect(all.first.noTranslate, isTrue); // boilerplate
      expect(all.map((b) => b.text), contains('First paragraph here.'));
      expect(all.any((b) => b.kind == BlockKind.quote && b.text == 'Quote'), isTrue);
      expect(all.any((b) => b.kind == BlockKind.separator), isTrue);
    });
  });

  group('TXT', () {
    test('detects chapters and unwraps lines', () {
      const text = 'Title: My Book\nAuthor: Someone\n\n*** START OF THE PROJECT GUTENBERG EBOOK ***\n\n'
          'CHAPTER I\n\nIt was a dark\nand stormy night.\n\nCHAPTER II\n\nThe end.\n\n*** END OF THE PROJECT GUTENBERG EBOOK ***\n\nLicence text.';
      final c = TxtParser.parse(text);
      expect(c.title, 'My Book');
      expect(c.author, 'Someone');
      final titles = c.chapters.map((x) => x.title).toList();
      expect(titles, containsAll(['CHAPTER I', 'CHAPTER II']));
      final ch1 = c.chapters.firstWhere((x) => x.title == 'CHAPTER I');
      expect(ch1.blocks.map((b) => b.text), contains('It was a dark and stormy night.'));
      expect(c.chapters.expand((x) => x.blocks).where((b) => b.text.startsWith('Licence')).first.noTranslate, isTrue);
    });
  });

  group('Edition', () {
    test('round trip keeps content and translation', () {
      final content = sampleBook();
      final t = TranslationData.emptyFor(content, 'tam_Taml', 'eng_Latn', 'test');
      t.chapters[1][1] = 'யாரும் பதில் சொல்லவில்லை.';
      final ed = Edition(content: content, translation: t, sourceLang: 'eng_Latn', gutenbergId: 42);
      final back = Edition.decode(ed.encode());
      expect(back.gutenbergId, 42);
      expect(back.content.chapters.length, 2);
      expect(back.translation.lang, 'tam_Taml');
      expect(back.translation.text(1, 1), 'யாரும் பதில் சொல்லவில்லை.');
      expect(back.translation.translatedCount(back.content), 1);
    });
  });
}
