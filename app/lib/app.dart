import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'data/engagement.dart';
import 'data/library_store.dart';
import 'models/book.dart';
import 'data/settings_store.dart';
import 'data/catalog.dart';
import 'data/discover.dart';
import 'ui/trending_book_screen.dart';
import 'demo.dart';
import 'data/reading_stats.dart';
import 'ui/book_actions.dart';
import 'ui/share_cards.dart';
import 'core/languages.dart';
import 'ui/engagement_ui.dart';
import 'ui/catalog_book_screen.dart';
import 'translation/translation_service.dart';
import 'ui/reader/reader_screen.dart';
import 'ui/widgets/language_picker.dart';
import 'ui/home_screen.dart';
import 'ui/library_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/store_screen.dart';
import 'l10n/strings.dart';

class BookItColors {
  static const ink = Color(0xFF1F2A44);
  static const saffron = Color(0xFFE39B2D);
  static const paper = Color(0xFFFBF8F2);
}

ThemeData _theme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: BookItColors.ink,
    brightness: brightness,
    secondary: BookItColors.saffron,
  );
  final dark = brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xFF14161B) : BookItColors.paper,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF14161B) : BookItColors.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'serif',
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: dark ? Colors.white : BookItColors.ink,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xFF1E2128) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: EdgeInsets.zero,
    ),
    chipTheme: const ChipThemeData(showCheckmark: false),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF1A1C22) : Colors.white,
      indicatorColor: scheme.secondaryContainer,
    ),
  );
}

class BookItApp extends StatelessWidget {
  final DemoScreen? demo;
  const BookItApp({super.key, this.demo});

  @override
  Widget build(BuildContext context) {
    final mode = context.select<SettingsStore, ThemeMode>((s) => s.appTheme);
    final appLang = context.select<SettingsStore, String?>((s) => s.appLanguage);
    L10n.use(appLang);
    return MaterialApp(
      title: 'BookIt',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: mode,
      locale: Locale(L10n.code),
      supportedLocales: [for (final l in kAppLanguages) Locale(l.$1)],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Rebuild every screen when the menu language changes.
      home: HomeShell(key: ValueKey(L10n.code), demo: demo),
    );
  }
}

class HomeShell extends StatefulWidget {
  final DemoScreen? demo;
  const HomeShell({super.key, this.demo});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// Tabs are only built once they are opened, so hidden screens don't start
  /// downloading covers before the visible ones.
  final Set<int> _opened = {0};

  @override
  void initState() {
    super.initState();
    final engagement = context.read<Engagement>();
    engagement.starPrompt.addListener(_maybeAskForStar);
    if (widget.demo == null) {
      Future.delayed(const Duration(seconds: 4), () => engagement.checkForUpdate());
    }
    final demo = widget.demo;
    if (demo == null) return;
    _index = switch (demo) {
      DemoScreen.library => 1,
      DemoScreen.store => 2,
      DemoScreen.settings => 3,
      _ => 0,
    };
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (demo == DemoScreen.readNow || demo == DemoScreen.bookPage) {
        await _demoCatalogBook(demo);
        return;
      }
      if (demo == DemoScreen.trending) {
        final navigator = Navigator.of(context);
        final d = await DiscoverData.load();
        final list = d.bestsellers.isNotEmpty ? d.bestsellers : d.trending;
        if (list.isNotEmpty && mounted) {
          await navigator.push(MaterialPageRoute(builder: (_) => TrendingBookScreen(book: list.first)));
        }
        return;
      }
      if (demo == DemoScreen.statsCard) {
        showShareCard(context, StatsCard(stats: context.read<ReadingStats>()), fileName: 'stats.png');
        return;
      }
      final book = context.read<LibraryStore>().byId(demoBookId);
      if (book == null) return;
      if (demo == DemoScreen.bilingual || demo == DemoScreen.quote) {
        await _demoTranslated(book, demo);
        return;
      }
      if (demo == DemoScreen.reader || demo == DemoScreen.readerDark || demo == DemoScreen.readerMenu) {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ReaderScreen(book: book, startWithMenu: demo == DemoScreen.readerMenu)));
      } else if (demo == DemoScreen.languages) {
        pickLanguage(context, title: tr('Translate into…'), exclude: 'eng_Latn', selected: 'tam_Taml');
      } else if (demo == DemoScreen.translate) {
        _demoTranslate(book);
      }
    });
  }

  /// CI demos that use the Tamil translation made by the end-to-end test
  /// (falls back to the original when there is none).
  Future<void> _demoTranslated(Book book, DemoScreen demo) async {
    final navigator = Navigator.of(context);
    final library = context.read<LibraryStore>();
    final t = await context.read<TranslationService>().translation(book.id, 'tam_Taml');
    if (!mounted) return;
    book.readingLang = t == null ? null : 'tam_Taml';
    if (demo == DemoScreen.bilingual) {
      await navigator.push(MaterialPageRoute(builder: (_) => ReaderScreen(book: book)));
      return;
    }
    final content = await library.content(book.id);
    if (!mounted) return;
    final blocks = content.chapters.first.blocks;
    final i = blocks.indexWhere((b) => !b.isHeading && b.text.length > 60);
    if (i < 0) return;
    final translated = t?.text(0, i);
    await showShareCard(
      context,
      QuoteCard(
        text: translated ?? blocks[i].text,
        original: translated == null ? null : blocks[i].text,
        title: book.title,
        author: book.author,
        languageName: translated == null ? null : '${languageByCode('tam_Taml')!.nativeName} · ${tr('translated with BookIt')}',
      ),
      fileName: 'quote.png',
    );
  }

  /// CI demos for the free library: open a book page, or "Read now".
  Future<void> _demoCatalogBook(DemoScreen demo) async {
    final navigator = Navigator.of(context);
    final library = context.read<LibraryStore>();
    final catalog = await LocalCatalog.load();
    final book = catalog.byId(1342);
    if (book == null || !mounted) return;
    if (demo == DemoScreen.bookPage) {
      await navigator.push(MaterialPageRoute(builder: (_) => CatalogBookScreen(book: book)));
      return;
    }
    try {
      final b = await library.addFromCatalog(book, temporary: true);
      if (!mounted) return;
      await openReader(context, b, original: true);
    } catch (e) {
      if (mounted) await showErrorDialog(context, tr('Could not get this book'), e);
    }
  }

  /// End-to-end demo used by CI: download the model, translate the sample
  /// story into Tamil and open it in the reader.
  Future<void> _demoTranslate(Book book) async {
    final service = context.read<TranslationService>();
    final navigator = Navigator.of(context);
    if (service.packState != PackState.installed) await service.downloadPack();
    await service.start(book, 'tam_Taml', fromChapter: 0);
    book.readingLang = 'tam_Taml';
    if (!mounted) return;
    await navigator.push(MaterialPageRoute(builder: (_) => ReaderScreen(book: book)));
  }

  @override
  void dispose() {
    context.read<Engagement>().starPrompt.removeListener(_maybeAskForStar);
    super.dispose();
  }

  void _maybeAskForStar() {
    final e = context.read<Engagement>();
    if (!e.starPrompt.value || !mounted) return;
    e.starPrompt.value = false;
    showStarPrompt(context);
  }

  static const _destinations = [
    (Icons.home_outlined, Icons.home, 'Home'),
    (Icons.collections_bookmark_outlined, Icons.collections_bookmark, 'Library'),
    (Icons.storefront_outlined, Icons.storefront, 'Free books'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  void _go(int i) => setState(() {
        _index = i;
        _opened.add(i);
      });

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        onOpenStore: () => _go(2),
        onOpenLibrary: () => _go(1),
        onSearch: () {
          _go(2);
          storeSearchRequest.value++;
        },
      ),
      const LibraryScreen(),
      const StoreScreen(),
      const SettingsScreen(),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 840;
    _opened.add(_index);
    final body = IndexedStack(
      index: _index,
      children: [for (var i = 0; i < pages.length; i++) _opened.contains(i) ? pages[i] : const SizedBox.shrink()],
    );
    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: _go,
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Image.asset('assets/icon.png', width: 40, height: 40),
            ),
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(tr(d.$3))),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _go,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: tr(d.$3)),
        ],
      ),
    );
  }
}
