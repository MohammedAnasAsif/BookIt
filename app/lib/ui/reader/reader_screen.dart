import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/languages.dart';
import '../../data/library_store.dart';
import '../../data/settings_store.dart';
import '../../models/book.dart';
import '../../models/book_content.dart';
import '../../translation/translation_data.dart';
import '../../translation/translation_service.dart';
import '../book_actions.dart';
import '../widgets/format.dart';
import 'paginator.dart';
import 'reader_sheets.dart';

/// Kindle-style paginated reader with tap zones, themes and a switch between
/// the original text and its translations.
class ReaderScreen extends StatefulWidget {
  final Book book;
  const ReaderScreen({super.key, required this.book});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  BookContent? _content;
  String? _error;
  String? _lang;
  TranslationData? _translation;
  List<Bookmark> _bookmarks = [];
  List<int> _chapterStartChars = [];
  int _totalChars = 1;

  int _chapter = 0;
  List<DisplayBlock> _blocks = [];
  List<PageLayout> _pages = [];
  int _page = 0;
  // Anchor: where the current page starts (survives re-layout).
  int _anchorBlock = 0;
  double _anchorFraction = 0;

  String _layoutKey = '';
  int _translatedSignature = -1;
  DateTime _lastLayout = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _relayoutTimer;
  Timer? _saveTimer;
  bool _menu = false;
  int _direction = 1;
  final _focus = FocusNode();

  Book get book => widget.book;

  @override
  void initState() {
    super.initState();
    _lang = book.readingLang;
    _chapter = book.position.chapter;
    _anchorBlock = book.position.block;
    _anchorFraction = book.position.fraction;
    _load();
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void dispose() {
    _relayoutTimer?.cancel();
    _saveTimer?.cancel();
    _savePosition();
    _focus.dispose();
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  Future<void> _load() async {
    final library = context.read<LibraryStore>();
    try {
      final content = await library.content(book.id);
      final marks = await library.bookmarks(book.id);
      var start = 0;
      final starts = <int>[];
      for (final c in content.chapters) {
        starts.add(start);
        start += c.characterCount;
      }
      if (!mounted) return;
      setState(() {
        _content = content;
        _bookmarks = marks;
        _chapterStartChars = starts;
        _totalChars = start == 0 ? 1 : start;
        _chapter = _chapter.clamp(0, content.chapters.length - 1);
      });
      await _loadTranslation();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open this book: $e');
    }
  }

  Future<void> _loadTranslation() async {
    final lang = _lang;
    if (lang == null) {
      setState(() => _translation = null);
      return;
    }
    final service = context.read<TranslationService>();
    final t = await service.translation(book.id, lang);
    if (!mounted) return;
    setState(() {
      _translation = t;
      _layoutKey = '';
    });
    _prioritize();
  }

  void _prioritize() {
    final lang = _lang, content = _content, t = _translation;
    if (lang == null || content == null) return;
    if (t != null && t.chapterComplete(content, _chapter)) return;
    context.read<TranslationService>().prioritize(book.id, lang, _chapter);
  }

  // ------------------------------------------------------------ layout

  ReaderStyle _style(SettingsStore s) {
    final lang = languageByCode(_lang ?? book.sourceLang);
    final serif = s.font == ReaderFont.serif;
    return ReaderStyle(
      fontSize: s.fontSize,
      lineHeight: s.lineHeight,
      fontFamily: serif ? (Platform.isWindows ? 'Georgia' : 'serif') : null,
      color: s.readerTheme.text,
      mutedColor: s.readerTheme.muted,
      justify: s.justify,
      direction: (lang?.isRtl ?? false) ? TextDirection.rtl : TextDirection.ltr,
    );
  }

  List<DisplayBlock> _displayBlocks(int chapter) {
    final content = _content!;
    final blocks = content.chapters[chapter].blocks;
    final t = _translation;
    return [
      for (var b = 0; b < blocks.length; b++)
        if (_lang == null)
          DisplayBlock(blocks[b].kind, blocks[b].text)
        else if (t?.text(chapter, b) case final tr?)
          DisplayBlock(blocks[b].kind, tr)
        else
          DisplayBlock(blocks[b].kind, blocks[b].text,
              pending: !blocks[b].noTranslate && blocks[b].text.trim().isNotEmpty && !hasNoLetters(blocks[b].text)),
    ];
  }

  int _signature(int chapter) {
    final t = _translation;
    if (_lang == null || t == null || chapter >= t.chapters.length) return 0;
    return t.chapters[chapter].where((x) => x != null).length;
  }

  void _layout(Size size, ReaderStyle style, {bool force = false}) {
    final sig = _signature(_chapter);
    final key = '$_chapter|${size.width.toStringAsFixed(0)}x${size.height.toStringAsFixed(0)}|'
        '${style.fontSize}|${style.lineHeight}|${style.fontFamily}|${style.justify}|$_lang|${style.direction}';
    final translationChanged = sig != _translatedSignature;
    if (!force && key == _layoutKey && !translationChanged) return;
    if (!force && key == _layoutKey && translationChanged) {
      // Live translation updates: re-layout at most every few seconds.
      final since = DateTime.now().difference(_lastLayout);
      if (since < const Duration(seconds: 4)) {
        _relayoutTimer ??= Timer(const Duration(seconds: 4) - since, () {
          _relayoutTimer = null;
          if (mounted) setState(() {});
        });
        return;
      }
    }
    _layoutKey = key;
    _translatedSignature = sig;
    _lastLayout = DateTime.now();
    _blocks = _displayBlocks(_chapter);
    _pages = Paginator.paginate(_blocks, size, style);
    _page = _anchorFraction < 0
        ? _pages.length - 1
        : Paginator.pageFor(_pages, _blocks, _anchorBlock, _anchorFraction);
    _page = _page.clamp(0, _pages.length - 1);
    _setAnchorFromPage();
  }

  void _setAnchorFromPage() {
    if (_pages.isEmpty || _pages[_page].slices.isEmpty) {
      _anchorBlock = 0;
      _anchorFraction = 0;
      return;
    }
    final s = _pages[_page].slices.first;
    final len = displayText(_blocks[s.block]).length;
    _anchorBlock = s.block;
    _anchorFraction = len == 0 ? 0 : s.start / len;
  }

  // ------------------------------------------------------------ navigation

  void _next() {
    final content = _content;
    if (content == null) return;
    if (_page < _pages.length - 1) {
      setState(() {
        _direction = 1;
        _page++;
        _setAnchorFromPage();
      });
    } else if (_chapter < content.chapters.length - 1) {
      setState(() {
        _direction = 1;
        _chapter++;
        _anchorBlock = 0;
        _anchorFraction = 0;
        _layoutKey = '';
      });
      _prioritize();
    } else {
      showMessage(context, 'You have reached the end of the book.');
    }
    _scheduleSave();
  }

  void _previous() {
    if (_content == null) return;
    if (_page > 0) {
      setState(() {
        _direction = -1;
        _page--;
        _setAnchorFromPage();
      });
    } else if (_chapter > 0) {
      setState(() {
        _direction = -1;
        _chapter--;
        _anchorBlock = 0;
        _anchorFraction = -1; // last page
        _layoutKey = '';
      });
      _prioritize();
    }
    _scheduleSave();
  }

  void goToChapter(int c, {int block = 0, double fraction = 0}) {
    setState(() {
      _chapter = c;
      _anchorBlock = block;
      _anchorFraction = fraction;
      _layoutKey = '';
      _menu = false;
    });
    _prioritize();
    _scheduleSave();
  }

  double get _progress {
    if (_content == null || _chapterStartChars.isEmpty) return 0;
    final blocks = _content!.chapters[_chapter].blocks;
    var chars = 0;
    for (var b = 0; b < _anchorBlock && b < blocks.length; b++) {
      chars += blocks[b].text.length;
    }
    if (_anchorBlock < blocks.length) chars += (blocks[_anchorBlock].text.length * _anchorFraction.clamp(0, 1)).round();
    return ((_chapterStartChars[_chapter] + chars) / _totalChars).clamp(0, 1).toDouble();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _savePosition);
  }

  void _savePosition() {
    if (_content == null) return;
    final pos = ReadingPosition(_chapter, _anchorBlock, _anchorFraction.clamp(0, 1).toDouble(), _progress);
    book.readingLang = _lang;
    context.read<LibraryStore>().updatePosition(book, pos);
  }

  Future<void> _switchLanguage(String? lang) async {
    _savePosition();
    setState(() {
      _lang = lang;
      _translation = null;
      _layoutKey = '';
      _menu = false;
    });
    book.readingLang = lang;
    await _loadTranslation();
    _scheduleSave();
  }

  // ------------------------------------------------------------ bookmarks

  Bookmark? get _bookmarkHere {
    if (_pages.isEmpty) return null;
    final blocksOnPage = _pages[_page].slices.map((s) => s.block).toSet();
    for (final b in _bookmarks) {
      if (b.position.chapter == _chapter && blocksOnPage.contains(b.position.block)) return b;
    }
    return null;
  }

  Future<void> _toggleBookmark() async {
    final existing = _bookmarkHere;
    setState(() {
      if (existing != null) {
        _bookmarks.remove(existing);
      } else {
        final s = _pages[_page].slices.isNotEmpty ? _pages[_page].slices.first : null;
        final snippet = s == null ? '' : displayText(_blocks[s.block]).substring(s.start, s.end);
        _bookmarks.add(Bookmark(
          ReadingPosition(_chapter, _anchorBlock, _anchorFraction.clamp(0, 1).toDouble(), _progress),
          snippet.length > 120 ? '${snippet.substring(0, 120)}…' : snippet,
        ));
      }
    });
    await context.read<LibraryStore>().saveBookmarks(book.id, _bookmarks);
  }

  // ------------------------------------------------------------ build

  String _chapterTitle(int c) {
    final content = _content!;
    final t = _translation;
    if (_lang != null && t != null) {
      final blocks = content.chapters[c].blocks;
      final hi = blocks.indexWhere((b) => b.isHeading);
      final tr = hi >= 0 ? t.text(c, hi) : null;
      if (tr != null && hi >= 0 && blocks[hi].text == content.chapters[c].title) return tr;
    }
    return content.chapters[c].title;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final service = context.watch<TranslationService>();
    final rt = settings.readerTheme;
    final overlay = rt.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;

    if (_lang != null && _translation == null) {
      final cached = service.cachedTranslation(book.id, _lang!);
      if (cached != null) _translation = cached;
    }

    Widget body;
    if (_error != null) {
      body = Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)));
    } else if (_content == null) {
      body = Center(child: CircularProgressIndicator(color: rt.muted));
    } else {
      body = _buildReader(settings, service);
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: rt.background,
        body: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
            final k = event.logicalKey;
            final rtl = _style(settings).direction == TextDirection.rtl;
            if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.pageDown || k == LogicalKeyboardKey.space) {
              rtl && k == LogicalKeyboardKey.arrowRight ? _previous() : _next();
              return KeyEventResult.handled;
            }
            if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.pageUp) {
              rtl && k == LogicalKeyboardKey.arrowLeft ? _next() : _previous();
              return KeyEventResult.handled;
            }
            if (k == LogicalKeyboardKey.escape) {
              if (_menu) {
                setState(() => _menu = false);
              } else {
                Navigator.maybePop(context);
              }
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: body,
        ),
      ),
    );
  }

  Widget _buildReader(SettingsStore settings, TranslationService service) {
    final rt = settings.readerTheme;
    final style = _style(settings);
    final content = _content!;
    final job = _lang == null ? null : service.job(book.id, _lang!);
    final chapterPending = _lang != null && _blocks.any((b) => b.pending);
    final mq = MediaQuery.of(context);
    final wide = mq.size.width > 900;
    final hMargin = wide ? (mq.size.width - 760).clamp(settings.margin, double.infinity) / 2 : settings.margin;

    return Stack(children: [
      SafeArea(
        child: Column(children: [
          // Header: chapter title
          SizedBox(
            height: 34,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: hMargin),
              child: Row(children: [
                Expanded(
                  child: Text(
                    _chapterTitle(_chapter),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: rt.muted, fontSize: 12.5),
                  ),
                ),
                if (_bookmarkHere != null) Icon(Icons.bookmark, size: 18, color: Colors.red.shade400),
              ]),
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(hMargin, 6, hMargin, 6),
              child: LayoutBuilder(builder: (context, c) {
                final size = Size(c.maxWidth, c.maxHeight);
                _layout(size, style);
                if (_pages.isEmpty) return const SizedBox.shrink();
                final page = _pages[_page.clamp(0, _pages.length - 1)];
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  transitionBuilder: (child, anim) {
                    final incoming = child.key == ValueKey('$_chapter-$_page-$_lang');
                    final dx = (incoming ? 0.08 : -0.08) * _direction;
                    return FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(anim),
                        child: child,
                      ),
                    );
                  },
                  child: SizedBox(
                    key: ValueKey('$_chapter-$_page-$_lang'),
                    width: size.width,
                    height: size.height,
                    child: ClipRect(child: PageView2(page: page, blocks: _blocks, style: style)),
                  ),
                );
              }),
            ),
          ),
          // Footer: progress
          SizedBox(
            height: 30,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: hMargin),
              child: Row(children: [
                Text('Page ${_page + 1} of ${_pages.length}', style: TextStyle(color: rt.muted, fontSize: 12)),
                const Spacer(),
                if (chapterPending) ...[
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: rt.muted),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    job == null || job.status == JobStatus.paused || job.status == JobStatus.error
                        ? 'Not translated yet'
                        : 'Translating…',
                    style: TextStyle(color: rt.muted, fontSize: 12),
                  ),
                  const Spacer(),
                ],
                Text(percent(_progress), style: TextStyle(color: rt.muted, fontSize: 12)),
              ]),
            ),
          ),
        ]),
      ),
      // Tap zones and swipes
      Positioned.fill(
        child: Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              if (e.scrollDelta.dy > 0) _next();
              if (e.scrollDelta.dy < 0) _previous();
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (d) {
              final w = MediaQuery.sizeOf(context).width;
              final x = d.globalPosition.dx / w;
              final rtl = style.direction == TextDirection.rtl;
              if (_menu) {
                setState(() => _menu = false);
              } else if (x < 0.3) {
                rtl ? _next() : _previous();
              } else if (x > 0.7) {
                rtl ? _previous() : _next();
              } else {
                setState(() => _menu = true);
              }
            },
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              final rtl = style.direction == TextDirection.rtl;
              if (v < -150) rtl ? _previous() : _next();
              if (v > 150) rtl ? _next() : _previous();
            },
          ),
        ),
      ),
      if (_menu) ..._menuOverlay(settings, content, job, chapterPending),
    ]);
  }

  List<Widget> _menuOverlay(SettingsStore settings, BookContent content, JobProgress? job, bool chapterPending) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lang = languageByCode(_lang);
    final bar = scheme.surface;
    return [
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Material(
          color: bar,
          elevation: 3,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 56,
              child: Row(children: [
                IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
                Expanded(
                  child: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.translate, size: 18),
                  label: Text(lang?.nativeName ?? 'Original'),
                  onPressed: () async {
                    final choice = await showEditionPicker(context, book, _lang);
                    if (choice == null) return;
                    if (choice == kTranslateNew) {
                      if (!mounted) return;
                      final code = await translateBook(context, book);
                      if (code != null) await _switchLanguage(code);
                    } else {
                      await _switchLanguage(choice == kOriginal ? null : choice);
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Bookmark this page',
                  icon: Icon(_bookmarkHere != null ? Icons.bookmark : Icons.bookmark_border),
                  onPressed: _toggleBookmark,
                ),
                IconButton(
                  tooltip: 'Contents',
                  icon: const Icon(Icons.toc),
                  onPressed: () async {
                    final target = await showContentsSheet(
                      context,
                      chapters: [for (var c = 0; c < content.chapters.length; c++) _chapterTitle(c)],
                      current: _chapter,
                      bookmarks: _bookmarks,
                      chapterDone: (c) => _lang == null || (_translation?.chapterComplete(content, c) ?? false),
                    );
                    if (target != null) {
                      goToChapter(target.chapter, block: target.block, fraction: target.fraction);
                    }
                  },
                ),
              ]),
            ),
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Material(
          color: bar,
          elevation: 3,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_lang != null && chapterPending)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                    child: Row(children: [
                      Icon(Icons.info_outline, size: 16, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          job != null && job.active
                              ? 'Lighter text is still being translated. It updates automatically.'
                              : 'Parts of this chapter are not translated yet.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      if (job == null || !job.active)
                        TextButton(
                          onPressed: () async {
                            final ok = await translateBook(context, book, lang: lang);
                            if (ok != null) setState(() {});
                          },
                          child: const Text('Translate'),
                        ),
                    ]),
                  ),
                Row(children: [
                  IconButton(
                    tooltip: 'Previous chapter',
                    icon: const Icon(Icons.skip_previous),
                    onPressed: _chapter > 0 ? () => goToChapter(_chapter - 1) : null,
                  ),
                  Expanded(
                    child: Slider(
                      value: _chapter.toDouble(),
                      min: 0,
                      max: (content.chapters.length - 1).clamp(0, 100000).toDouble(),
                      divisions: content.chapters.length > 1 ? content.chapters.length - 1 : null,
                      label: _chapterTitle(_chapter),
                      onChanged: content.chapters.length > 1 ? (v) => goToChapter(v.round()) : null,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next chapter',
                    icon: const Icon(Icons.skip_next),
                    onPressed: _chapter < content.chapters.length - 1 ? () => goToChapter(_chapter + 1) : null,
                  ),
                  IconButton(
                    tooltip: 'Text settings',
                    icon: const Icon(Icons.text_fields),
                    onPressed: () => showReaderSettings(context),
                  ),
                ]),
                Text(
                  'Chapter ${_chapter + 1} of ${content.chapters.length} · ${percent(_progress)} of book',
                  style: theme.textTheme.bodySmall,
                ),
              ]),
            ),
          ),
        ),
      ),
    ];
  }
}
