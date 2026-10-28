import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../core/languages.dart';
import '../models/book_content.dart';
import '../translation/translation_data.dart';

/// Writes a simple, valid EPUB 3 of a book — the original or a translation —
/// so it can be read in any e-reader app.
class EpubWriter {
  static Uint8List write({
    required BookContent content,
    TranslationData? translation,
    Uint8List? cover,
    String? coverExtension,
    String? identifier,
  }) {
    final langCode = translation?.lang;
    final lang = languageByCode(langCode);
    final iso = lang?.iso1 ?? (content.language.isEmpty ? 'en' : content.language);
    final rtl = lang?.isRtl ?? false;
    final title = translation == null ? content.title : '${content.title} (${lang?.nativeName ?? langCode})';
    final id = identifier ?? 'bookit-${content.title.hashCode.toUnsigned(32)}-${langCode ?? 'orig'}';

    final archive = Archive();
    void add(String name, List<int> data, {bool compress = true}) {
      final f = ArchiveFile(name, data.length, data);
      f.compress = compress;
      archive.addFile(f);
    }

    add('mimetype', ascii.encode('application/epub+zip'), compress: false);
    add('META-INF/container.xml', utf8.encode('''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>'''));

    final manifest = StringBuffer();
    final spine = StringBuffer();
    final navItems = StringBuffer();
    final dir = rtl ? ' dir="rtl"' : '';
    for (var c = 0; c < content.chapters.length; c++) {
      final ch = content.chapters[c];
      final body = StringBuffer();
      for (var b = 0; b < ch.blocks.length; b++) {
        final block = ch.blocks[b];
        final text = translation?.text(c, b) ?? block.text;
        final esc = _esc(text).replaceAll('\n', '<br/>');
        switch (block.kind) {
          case BlockKind.heading1:
            body.writeln('<h2>$esc</h2>');
          case BlockKind.heading2:
            body.writeln('<h3>$esc</h3>');
          case BlockKind.heading3:
            body.writeln('<h4>$esc</h4>');
          case BlockKind.quote:
            body.writeln('<blockquote><p>$esc</p></blockquote>');
          case BlockKind.preformatted:
            body.writeln('<pre>${_esc(text)}</pre>');
          case BlockKind.listItem:
            body.writeln('<p class="li">• $esc</p>');
          case BlockKind.separator:
            body.writeln('<hr/>');
          case BlockKind.paragraph:
            body.writeln('<p>$esc</p>');
        }
      }
      final name = 'chapter${(c + 1).toString().padLeft(4, '0')}.xhtml';
      final chTitle = translation?.text(c, ch.blocks.indexWhere((b) => b.isHeading)) ?? ch.title;
      add('OEBPS/$name', utf8.encode('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="$iso" lang="$iso"$dir>
<head><title>${_esc(chTitle)}</title><link rel="stylesheet" type="text/css" href="style.css"/></head>
<body>
$body</body>
</html>'''));
      manifest.writeln('<item id="c$c" href="$name" media-type="application/xhtml+xml"/>');
      spine.writeln('<itemref idref="c$c"/>');
      navItems.writeln('<li><a href="$name">${_esc(chTitle)}</a></li>');
    }

    add('OEBPS/style.css', utf8.encode(
        'body{line-height:1.5;margin:0 5%}p{text-indent:1.2em;margin:0 0 .4em}h2,h3,h4{text-align:center}'
        'blockquote{margin:0 1.5em;font-style:italic}p.li{text-indent:0}'));
    add('OEBPS/nav.xhtml', utf8.encode('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="$iso" lang="$iso"$dir>
<head><title>${_esc(title)}</title></head>
<body><nav epub:type="toc" id="toc"><h1>${_esc(title)}</h1><ol>
$navItems</ol></nav></body>
</html>'''));

    var coverManifest = '';
    var coverMeta = '';
    if (cover != null) {
      final ext = (coverExtension ?? 'jpg').toLowerCase();
      final mt = ext == 'png' ? 'image/png' : (ext == 'gif' ? 'image/gif' : 'image/jpeg');
      add('OEBPS/cover.$ext', cover);
      coverManifest = '<item id="cover-image" href="cover.$ext" media-type="$mt" properties="cover-image"/>';
      coverMeta = '<meta name="cover" content="cover-image"/>';
    }

    final modified = DateTime.now().toUtc().toIso8601String().split('.').first;
    final note = translation == null
        ? ''
        : '<dc:description>Machine translation made with BookIt (${_esc(translation.engine)}).</dc:description>';
    add('OEBPS/content.opf', utf8.encode('''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid" xml:lang="$iso">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="bookid">${_esc(id)}</dc:identifier>
<dc:title>${_esc(title)}</dc:title>
<dc:creator>${_esc(content.author)}</dc:creator>
<dc:language>$iso</dc:language>
$note
<meta property="dcterms:modified">${modified}Z</meta>
$coverMeta
</metadata>
<manifest>
<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
<item id="css" href="style.css" media-type="text/css"/>
$coverManifest
$manifest</manifest>
<spine${rtl ? ' page-progression-direction="rtl"' : ''}>
$spine</spine>
</package>'''));

    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  static String _esc(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
}
