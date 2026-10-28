import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../models/book_content.dart';

/// Result of parsing an EPUB file.
class ParsedEpub {
  final BookContent content;
  final Uint8List? coverBytes;
  final String? coverExtension;

  ParsedEpub(this.content, this.coverBytes, this.coverExtension);
}

/// Converts an EPUB (2 or 3) into BookIt's [BookContent]: chapters made of
/// headings and paragraphs. Images, styles and scripts are dropped.
class EpubParser {
  static ParsedEpub parse(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, ArchiveFile>{};
    for (final f in archive.files) {
      if (f.isFile) files[_norm(f.name)] = f;
    }
    String read(String path) {
      final f = files[_norm(path)];
      if (f == null) throw FormatException('Missing $path in EPUB');
      return utf8.decode(f.content as List<int>, allowMalformed: true);
    }

    Uint8List? readBytes(String path) {
      final f = files[_norm(path)];
      return f == null ? null : Uint8List.fromList(f.content as List<int>);
    }

    // container.xml -> OPF path
    final container = _parseXml(read('META-INF/container.xml'));
    final rootfile = container.descendants
        .whereType<XmlElement>()
        .firstWhere((e) => e.name.local == 'rootfile')
        .getAttribute('full-path')!;
    final opfDir = p.posix.dirname(rootfile) == '.' ? '' : p.posix.dirname(rootfile);
    String resolve(String base, String href) {
      final clean = Uri.decodeFull(href.split('#').first);
      return p.posix.normalize(p.posix.join(base, clean));
    }

    final opf = _parseXml(read(rootfile));
    final elements = opf.descendants.whereType<XmlElement>().toList();
    String meta(String name) {
      for (final e in elements) {
        if (e.name.local == name) {
          final t = e.innerText.trim();
          if (t.isNotEmpty) return t;
        }
      }
      return '';
    }

    final title = meta('title');
    final creators = [
      for (final e in elements)
        if (e.name.local == 'creator' && e.innerText.trim().isNotEmpty) e.innerText.trim()
    ];
    final language = meta('language');

    // Manifest
    final manifest = <String, _Item>{};
    String? coverId;
    for (final e in elements) {
      if (e.name.local == 'item') {
        final id = e.getAttribute('id');
        final href = e.getAttribute('href');
        if (id == null || href == null) continue;
        manifest[id] = _Item(id, resolve(opfDir, href), e.getAttribute('media-type') ?? '',
            e.getAttribute('properties') ?? '');
      } else if (e.name.local == 'meta' && e.getAttribute('name') == 'cover') {
        coverId = e.getAttribute('content');
      }
    }

    // Spine
    final spine = <_Item>[];
    String? ncxId;
    for (final e in elements) {
      if (e.name.local == 'spine') ncxId = e.getAttribute('toc');
      if (e.name.local == 'itemref') {
        final item = manifest[e.getAttribute('idref')];
        if (item != null && e.getAttribute('linear') != 'no') spine.add(item);
      }
    }

    // Table of contents: file -> {fragment or '' -> title}
    final toc = <String, Map<String, String>>{};
    void addToc(String target, String label) {
      label = label.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (label.isEmpty) return;
      final parts = target.split('#');
      final file = resolve('', parts.first);
      final frag = parts.length > 1 ? parts[1] : '';
      toc.putIfAbsent(file, () => {}).putIfAbsent(frag, () => label);
    }

    final navItem = manifest.values.where((i) => i.properties.split(' ').contains('nav')).firstOrNull;
    if (navItem != null) {
      try {
        final nav = _parseXml(read(navItem.path));
        final navDir = p.posix.dirname(navItem.path);
        XmlElement? tocNav;
        for (final e in nav.descendants.whereType<XmlElement>()) {
          if (e.name.local == 'nav') {
            final type = e.attributes
                .where((a) => a.name.local == 'type')
                .map((a) => a.value)
                .firstOrNull;
            if (type == 'toc' || tocNav == null) tocNav = e;
            if (type == 'toc') break;
          }
        }
        for (final a in (tocNav?.descendants.whereType<XmlElement>() ?? const <XmlElement>[])) {
          if (a.name.local == 'a' && a.getAttribute('href') != null) {
            addToc(_joinTarget(navDir, a.getAttribute('href')!), a.innerText);
          }
        }
      } catch (_) {}
    }
    if (toc.isEmpty) {
      final ncx = manifest[ncxId] ??
          manifest.values.where((i) => i.mediaType == 'application/x-dtbncx+xml').firstOrNull;
      if (ncx != null) {
        try {
          final doc = _parseXml(read(ncx.path));
          final ncxDir = p.posix.dirname(ncx.path);
          for (final np in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'navPoint')) {
            final label = np.childElements
                .where((e) => e.name.local == 'navLabel')
                .map((e) => e.innerText)
                .firstOrNull;
            final src = np.childElements
                .where((e) => e.name.local == 'content')
                .map((e) => e.getAttribute('src'))
                .firstOrNull;
            if (label != null && src != null) addToc(_joinTarget(ncxDir, src), label);
          }
        } catch (_) {}
      }
    }

    // Walk the spine
    final builder = _ChapterBuilder();
    for (final item in spine) {
      if (!item.mediaType.contains('html') && !item.path.endsWith('html') && !item.path.endsWith('.htm')) {
        continue;
      }
      String html;
      try {
        html = read(item.path);
      } catch (_) {
        continue;
      }
      final anchors = toc[item.path] ?? const <String, String>{};
      if (anchors.containsKey('')) builder.startChapter(anchors['']!);
      _HtmlBlockExtractor(builder, anchors).extract(html);
    }
    final chapters = builder.finish();

    // Cover
    Uint8List? cover;
    String? coverExt;
    final coverItem = manifest.values.where((i) => i.properties.split(' ').contains('cover-image')).firstOrNull ??
        manifest[coverId];
    if (coverItem != null && coverItem.mediaType.startsWith('image/')) {
      cover = readBytes(coverItem.path);
      coverExt = p.extension(coverItem.path).replaceFirst('.', '');
    }

    return ParsedEpub(
      BookContent(
        title: title.isEmpty ? 'Untitled' : title,
        author: creators.join(', '),
        language: language,
        chapters: chapters,
      ),
      cover,
      coverExt,
    );
  }

  static String _norm(String path) => p.posix.normalize(path.replaceAll('\\', '/')).replaceFirst(RegExp('^/'), '');

  static String _joinTarget(String dir, String href) {
    final parts = href.split('#');
    final file = p.posix.normalize(p.posix.join(dir, Uri.decodeFull(parts.first)));
    return parts.length > 1 ? '$file#${parts[1]}' : file;
  }

  static XmlDocument _parseXml(String text) {
    try {
      return XmlDocument.parse(text, entityMapping: const XmlDefaultEntityMapping.html5());
    } catch (_) {
      // Strip a DOCTYPE with an internal subset and retry.
      final cleaned = text.replaceFirst(RegExp(r'<!DOCTYPE[^>\[]*(\[[^\]]*\])?\s*>', caseSensitive: false), '');
      return XmlDocument.parse(cleaned, entityMapping: const XmlDefaultEntityMapping.html5());
    }
  }

  /// Exposed for the TXT/HTML importers and tests.
  static List<Chapter> htmlToChapters(String html, {String title = ''}) {
    final b = _ChapterBuilder();
    if (title.isNotEmpty) b.startChapter(title);
    _HtmlBlockExtractor(b, const {}).extract(html);
    return b.finish();
  }
}

class _Item {
  final String id;
  final String path;
  final String mediaType;
  final String properties;
  _Item(this.id, this.path, this.mediaType, this.properties);
}

class _ChapterBuilder {
  final chapters = <Chapter>[];
  String? _title;
  List<Block> _blocks = [];

  void startChapter(String title) {
    _flush();
    _title = title;
  }

  void add(Block b) => _blocks.add(b);

  void _flush() {
    if (_blocks.isNotEmpty) {
      var title = _title;
      if (title == null || title.isEmpty) {
        final h = _blocks.where((b) => b.isHeading).map((b) => b.text).firstOrNull;
        title = h ?? 'Section ${chapters.length + 1}';
      }
      chapters.add(Chapter(title.length > 80 ? '${title.substring(0, 77)}…' : title, _blocks));
    }
    _blocks = [];
    _title = null;
  }

  /// Splits very long untitled runs so chapters stay a comfortable size.
  void maybeSplit() {
    if (_blocks.length >= 600) {
      final t = _title;
      _flush();
      _title = t == null ? null : '$t (cont.)';
    }
  }

  List<Chapter> finish() {
    _flush();
    return chapters;
  }
}

class _HtmlBlockExtractor {
  final _ChapterBuilder out;
  final Map<String, String> anchors;
  bool _inBoilerplate = false;

  _HtmlBlockExtractor(this.out, this.anchors);

  static const _blockTags = {
    'p', 'div', 'section', 'article', 'header', 'footer', 'aside', 'main', 'nav', 'blockquote', 'pre',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'li', 'dl', 'dt', 'dd', 'table', 'thead', 'tbody',
    'tfoot', 'tr', 'td', 'th', 'figure', 'figcaption', 'hr', 'body', 'center', 'address', 'hgroup',
  };
  static const _skipTags = {'head', 'script', 'style', 'svg', 'math', 'img', 'image', 'audio', 'video', 'object'};

  void extract(String html) {
    XmlDocument doc;
    try {
      doc = EpubParser._parseXml(html);
    } catch (_) {
      _fallback(html);
      return;
    }
    final body = doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'body').firstOrNull ??
        doc.rootElement;
    _walk(body, BlockKind.paragraph);
  }

  void _fallback(String html) {
    final text = html
        .replaceAll(RegExp(r'<(script|style)[^>]*>.*?</\1>', dotAll: true, caseSensitive: false), ' ')
        .replaceAll(RegExp(r'</(p|div|h\d|li|tr)>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
    for (final para in text.split(RegExp(r'\n\s*\n'))) {
      final t = _clean(_decodeEntities(para));
      if (t.isNotEmpty) out.add(Block(BlockKind.paragraph, t, noTranslate: hasNoLetters(t)));
    }
  }

  static String _decodeEntities(String s) => s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");

  bool _isBoilerplate(XmlElement e) {
    final id = e.getAttribute('id') ?? '';
    final cls = e.getAttribute('class') ?? '';
    return id == 'pg-header' || id == 'pg-footer' || cls.contains('pg-boilerplate');
  }

  bool _isPageNumber(XmlElement e) {
    final cls = e.getAttribute('class') ?? '';
    return cls.contains('pagenum') || cls.contains('pageno') || cls.contains('page-number');
  }

  /// Checks whether [e] (or, for leaf blocks, any element inside it) carries
  /// an id that the table of contents points at, and starts a chapter.
  void _checkAnchors(XmlElement e, {required bool deep}) {
    if (anchors.isEmpty) return;
    final id = e.getAttribute('id');
    if (id != null && anchors.containsKey(id)) {
      out.startChapter(anchors[id]!);
      return;
    }
    if (deep) {
      for (final d in e.descendants.whereType<XmlElement>()) {
        final did = d.getAttribute('id');
        if (did != null && anchors.containsKey(did)) {
          out.startChapter(anchors[did]!);
          return;
        }
      }
    }
  }

  bool _hasBlockChildren(XmlElement e) =>
      e.childElements.any((c) => _blockTags.contains(c.name.local.toLowerCase()));

  void _walk(XmlElement e, BlockKind context) {
    final tag = e.name.local.toLowerCase();
    if (_skipTags.contains(tag)) return;
    final wasBoiler = _inBoilerplate;
    if (_isBoilerplate(e)) _inBoilerplate = true;

    if (tag == 'hr') {
      out.add(const Block(BlockKind.separator, '', noTranslate: true));
    } else if (_hasBlockChildren(e) || tag == 'body') {
      _checkAnchors(e, deep: false);
      final childContext = tag == 'blockquote' ? BlockKind.quote : context;
      // Inline text directly inside a container is collected as paragraphs.
      final inline = StringBuffer();
      void flushInline() {
        final t = _clean(inline.toString());
        inline.clear();
        if (t.isNotEmpty) _emit(childContext, t);
      }

      for (final node in e.children) {
        if (node is XmlElement && _blockTags.contains(node.name.local.toLowerCase())) {
          flushInline();
          _walk(node, childContext);
        } else if (node is XmlElement) {
          if (!_skipTags.contains(node.name.local.toLowerCase())) {
            _checkAnchors(node, deep: true);
            _inlineText(node, inline);
          }
        } else if (node is XmlText || node is XmlCDATA) {
          inline.write(node.value ?? '');
        }
      }
      flushInline();
      if (tag == 'tr') {
        // handled through children
      }
    } else {
      _checkAnchors(e, deep: true);
      final sb = StringBuffer();
      if (tag == 'pre') {
        for (final n in e.descendants.whereType<XmlText>()) {
          sb.write(n.value);
        }
        final t = sb.toString().trimRight();
        if (t.trim().isNotEmpty) {
          out.add(Block(BlockKind.preformatted, t, noTranslate: _inBoilerplate || hasNoLetters(t)));
        }
      } else {
        _inlineText(e, sb);
        final t = _clean(sb.toString());
        if (t.isNotEmpty) {
          final kind = switch (tag) {
            'h1' || 'h2' => BlockKind.heading1,
            'h3' => BlockKind.heading2,
            'h4' || 'h5' || 'h6' => BlockKind.heading3,
            'li' || 'dd' || 'dt' => BlockKind.listItem,
            _ => context,
          };
          _emit(kind, t);
        }
      }
    }
    _inBoilerplate = wasBoiler;
    out.maybeSplit();
  }

  void _emit(BlockKind kind, String text) {
    out.add(Block(kind, text, noTranslate: _inBoilerplate || hasNoLetters(text)));
  }

  void _inlineText(XmlElement e, StringBuffer sb) {
    for (final node in e.children) {
      if (node is XmlText || node is XmlCDATA) {
        sb.write(node.value ?? '');
      } else if (node is XmlElement) {
        final tag = node.name.local.toLowerCase();
        if (_skipTags.contains(tag) || _isPageNumber(node)) continue;
        if (tag == 'br') {
          sb.write('\n');
        } else {
          _inlineText(node, sb);
        }
      }
    }
  }

  /// Collapses whitespace but keeps explicit line breaks (from <br>).
  static String _clean(String s) {
    final lines = s.split('\n').map((l) => l.replaceAll(RegExp(r'[ \t\r\f ]+'), ' ').trim());
    return lines.where((l) => l.isNotEmpty).join('\n').trim();
  }
}
