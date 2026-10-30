import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/languages.dart';
import '../../data/engagement.dart';
import '../../data/library_store.dart';
import '../../data/reading_stats.dart';
import '../../data/settings_store.dart';
import '../../models/book.dart';
import '../../models/book_content.dart';
import '../../translation/translation_data.dart';
import '../../translation/translation_service.dart';
import '../../l10n/strings.dart';
import '../book_actions.dart';
import '../engagement_ui.dart';
import '../share_cards.dart';
import '../widgets/format.dart';
import 'paginator.dart';
import 'read_aloud.dart';
import 'reader_sheets.dart';

/// Kindle-style paginated reader with tap zones, themes and a switch between
/// the original text and its translations.
class ReaderScreen extends StatefulWidget {
  final Book book;
  final bool startWithMenu;
  const ReaderScreen({super.key, required this.book, this.startWithMenu = false});

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
  int _footerPageCount = -1;
  int _translatedSignature = -1;
  DateTime _lastLayout = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _relayoutTimer;
  Timer? _saveTimer;
  bool _menu = false;
  int _direction = 1;
  final _focus = FocusNode();
  late final ReadingStats _stats;
  final _aloud = ReadAloud();
  bool _readingAloud = false;

  Book get book => widget.book;

  @override
  void initState() {
    super.initState();
    _lang = book.readingLang;
    _menu = widget.startWithMenu;
    _chapter = book.position.chapter;
    _anchorBlock = book.position.block;
    _anchorFraction = book.position.fraction;
    _stats = context.read<ReadingStats>()..startSession();
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
    _aloud.stop();
    _stats.endSession();
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

  bool get _bilingual => _lang != null && context.read<SettingsStore>().bilingual;

  List<DisplayBlock> _displayBlocks(int chapter) {
    final content = _content!;
    final blocks = content.chapters[chapter].blocks;
    final t = _translation;
    final both = _bilingual;
    return [
      for (var b = 0; b < blocks.length; b++)
        if (_lang == null)
          DisplayBlock(blocks[b].kind, blocks[b].text, source: b)
        else if (t?.text(chapter, b) case final tr?) ...[
          DisplayBlock(blocks[b].kind, tr, source: b),
          if (both && tr.trim() != blocks[b].text.trim() && blocks[b].kind != BlockKind.separator)
            DisplayBlock(blocks[b].kind, blocks[b].text, source: b, secondary: true),
        ] else
          DisplayBlock(blocks[b].kind, blocks[b].text,
              source: b,
              pending: !blocks[b].noTranslate && blocks[b].text.trim().isNotEmpty && !hasNoLetters(blocks[b].text)),
    ];
  }

  /// Index in [_blocks] of the main text of book block [source].
  int _displayIndex(int source) {
    final i = _blocks.indexWhere((b) => b.source == source && !b.secondary);
    return i < 0 ? 0 : i;
  }

  int _signature(int chapter) {
    final t = _translation;
    if (_lang == null || t == null || chapter >= t.chapters.length) return 0;
    return t.chapters[chapter].where((x) => x != null).length;
  }

  void _layout(Size size, ReaderStyle style, {bool force = false}) {
    final sig = _signature(_chapter);
    final key = '$_chapter|${size.width.toStringAsFixed(0)}x${size.height.toStringAsFixed(0)}|'
        '${style.fontSize}|${style.lineHeight}|${style.fontFamily}|${style.justify}|$_lang|${style.direction}|$_bilingual';
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
        : Paginator.pageFor(_pages, _blocks, _displayIndex(_anchorBlock), _anchorFraction);
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
    final b = _blocks[s.block];
    final len = displayText(b).length;
    _anchorBlock = b.source < 0 ? s.block : b.source;
    // A page that starts with an original-language line belongs to the end
    // of the translated paragraph above it.
    _anchorFraction = b.secondary ? 0.999 : (len == 0 ? 0 : s.start / len);
  }

  /// Book blocks shown on the current page (main text only).
  List<int> get _sourcesOnPage {
    if (_pages.isEmpty) return const [];
    final out = <int>[];
    for (final s in _pages[_page.clamp(0, _pages.length - 1)].slices) {
      final b = _blocks[s.block];
      final src = b.source < 0 ? s.block : b.source;
      if (!out.contains(src)) out.add(src);
    }
    return out;
  }

  /// Counts reading time and notices when the book is finished.
  void _turned() {
    _stats.pageTurned();
    final content = _content;
    if (content == null) return;
    if (_chapter == content.chapters.length - 1 && _page >= _pages.length - 1 && _stats.markFinished(book.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _celebrateFinished();
      });
    }
  }

  Future<void> _celebrateFinished() async {
    final engagement = context.read<Engagement>();
    await showFinishedDialog(context, book.title, _stats);
    if (!mounted) return;
    if (engagement.celebrate()) await showStarPrompt(context);
  }

  // ------------------------------------------------------------ navigation

  void _next({bool auto = false}) {
    if (!auto && _readingAloud) _stopAloud();
    final content = _content;
    if (content == null) return;
    if (_page < _pages.length - 1) {
      setState(() {
        _direction = 1;
        _page++;
        _setAnchorFromPage();
      });
      _turned();
    } else if (_chapter < content.chapters.length - 1) {
      setState(() {
        _direction = 1;
        _chapter++;
        _anchorBlock = 0;
        _anchorFraction = 0;
        _layoutKey = '';
      });
      _stats.pageTurned();
      _prioritize();
    } else {
      if (_stats.markFinished(book.id)) {
        _celebrateFinished();
      } else {
        showMessage(context, tr('You have reached the end of the book.'));
      }
    }
    _scheduleSave();
  }

  void _previous() {
    if (_readingAloud) _stopAloud();
    if (_content == null) return;
    if (_page > 0) {
      setState(() {
        _direction = -1;
        _page--;
        _setAnchorFromPage();
      });
      _stats.pageTurned();
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

  // ------------------------------------------------------------ read aloud

  void _stopAloud() {
    _aloud.stop();
    if (mounted) setState(() => _readingAloud = false);
  }

  Future<void> _toggleReadAloud() async {
    if (_readingAloud) return _stopAloud();
    final lang = languageByCode(_lang ?? book.sourceLang);
    if (lang == null) return;
    final locale = await _aloud.voiceFor(lang);
    if (!mounted) return;
    if (locale == null) {
      await showNoVoiceDialog(context, lang.nativeName);
      return;
    }
    setState(() {
      _readingAloud = true;
      _menu = false;
    });
    while (mounted && _readingAloud && _pages.isNotEmpty) {
      final page = _pages[_page.clamp(0, _pages.length - 1)];
      final pieces = <String>[];
      var waiting = false;
      for (final sl in page.slices) {
        final b = _blocks[sl.block];
        if (b.secondary || b.kind == BlockKind.separator) continue;
        if (b.pending) {
          waiting = true;
          continue;
        }
        pieces.add(displayText(b).substring(sl.start, sl.end));
      }
      if (waiting && pieces.isEmpty) {
        // This page isn't translated yet: wait for it, if it's being translated.
        final job = context.read<TranslationService>().job(book.id, _lang!);
        if (job == null || !job.active) {
          showMessage(context, tr('This part is not translated yet.'));
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 3));
        continue;
      }
      final finished = await _aloud.speakAll(locale, pieces);
      if (!finished || !mounted || !_readingAloud) break;
      final before = '$_chapter/$_page';
      _next(auto: true);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (before == '$_chapter/$_page') break; // end of the book
    }
    if (mounted && _readingAloud) _stopAloud();
  }

  // ------------------------------------------------------------ quotes

  Future<void> _shareQuote() async {
    final content = _content;
    if (content == null) return;
    final blocks = content.chapters[_chapter].blocks;
    final items = <(String, String?)>[];
    for (final src in _sourcesOnPage) {
      if (src >= blocks.length || blocks[src].kind == BlockKind.separator) continue;
      final shown = _blocks[_displayIndex(src)];
      if (shown.text.trim().length < 15) continue;
      final original = _lang != null && !shown.pending ? blocks[src].text : null;
      items.add((shown.text, original == shown.text ? null : original));
    }
    if (items.isEmpty) {
      showMessage(context, tr('There is no passage on this page to share.'));
      return;
    }
    setState(() => _menu = false);
    var choice = items.first;
    if (items.length > 1) {
      final picked = await showModalBottomSheet<(String, String?)>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
            child: ListView(shrinkWrap: true, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(tr('Choose a passage to share'), style: Theme.of(context).textTheme.titleMedium),
              ),
              for (final it in items)
                ListTile(
                  leading: const Icon(Icons.format_quote),
                  title: Text(it.$1, maxLines: 4, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(context, it),
                ),
            ]),
          ),
        ),
      );
      if (picked == null || !mounted) return;
      choice = picked;
    }
    final lang = languageByCode(_lang);
    await showShareCard(
      context,
      QuoteCard(
        text: choice.$1,
        original: choice.$2,
        title: book.title,
        author: book.author,
        languageName: lang == null ? null : '${lang.nativeName} · ${tr('translated with BookIt')}',
      ),
      fileName: 'bookit-quote.png',
      text: '“${choice.$1.length > 200 ? '${choice.$1.substring(0, 200)}…' : choice.$1}” — ${book.title}\n\n$kShareLine',
    );
  }

  // ------------------------------------------------------------ bookmarks

  Bookmark? get _bookmarkHere {
    if (_pages.isEmpty) return null;
    final blocksOnPage = _sourcesOnPage.toSet();
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
                if (_pages.length != _footerPageCount) {
                  // The header/footer were built before this layout; refresh them.
                  _footerPageCount = _pages.length;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() {});
                  });
                }
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
                Text(tr('Page {n} of {total}', {'n': _page + 1, 'total': _pages.length}), style: TextStyle(color: rt.muted, fontSize: 12)),
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
            onLongPress: _shareQuote,
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              final rtl = style.direction == TextDirection.rtl;
              if (v < -150) rtl ? _previous() : _next();
              if (v > 150) rtl ? _next() : _previous();
            },
          ),
        ),
      ),
      if (_readingAloud && !_menu)
        Positioned(
          left: 0,
          right: 0,
          bottom: 40,
          child: SafeArea(
            child: Center(
              child: Material(
                color: Theme.of(context).colorScheme.inverseSurface,
                shape: const StadiumBorder(),
                elevation: 4,
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: _stopAloud,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.graphic_eq, size: 18, color: Theme.of(context).colorScheme.onInverseSurface),
                      const SizedBox(width: 8),
                      Text(tr('Reading aloud · tap to stop'),
                          style: TextStyle(color: Theme.of(context).colorScheme.onInverseSurface)),
                    ]),
                  ),
                ),
              ),
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
                  label: Text(lang?.nativeName ?? tr('Original')),
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
                  tooltip: tr('Bookmark this page'),
                  icon: Icon(_bookmarkHere != null ? Icons.bookmark : Icons.bookmark_border),
                  onPressed: _toggleBookmark,
                ),
                IconButton(
                  tooltip: tr('Contents'),
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
                          child: Text(tr('Translate')),
                        ),
                    ]),
                  ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(children: [
                    ActionChip(
                      avatar: Icon(_readingAloud ? Icons.stop : Icons.headphones, size: 18),
                      label: Text(_readingAloud ? tr('Stop reading') : tr('Read aloud')),
                      onPressed: _toggleReadAloud,
                    ),
                    const SizedBox(width: 8),
                    if (_lang != null) ...[
                      FilterChip(
                        avatar: const Icon(Icons.subject, size: 18),
                        label: Text(tr('Show original too')),
                        selected: settings.bilingual,
                        onSelected: (v) => setState(() {
                          settings.update((s) => s.bilingual = v);
                          _layoutKey = '';
                        }),
                      ),
                      const SizedBox(width: 8),
                    ],
                    ActionChip(
                      avatar: const Icon(Icons.format_quote, size: 18),
                      label: Text(tr('Share a quote')),
                      onPressed: _shareQuote,
                    ),
                  ]),
                ),
                const SizedBox(height: 4),
                Row(children: [
                  IconButton(
                    tooltip: tr('Previous chapter'),
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
                    tooltip: tr('Next chapter'),
                    icon: const Icon(Icons.skip_next),
                    onPressed: _chapter < content.chapters.length - 1 ? () => goToChapter(_chapter + 1) : null,
                  ),
                  IconButton(
                    tooltip: tr('Text settings'),
                    icon: const Icon(Icons.text_fields),
                    onPressed: () => showReaderSettings(context),
                  ),
                ]),
                Text(
                  tr('Chapter {n} of {total} · {p} of book',
                      {'n': _chapter + 1, 'total': content.chapters.length, 'p': percent(_progress)}),
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
