import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/settings_store.dart';
import 'ui/home_screen.dart';
import 'ui/library_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/store_screen.dart';

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
  const BookItApp({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.select<SettingsStore, ThemeMode>((s) => s.appTheme);
    return MaterialApp(
      title: 'BookIt',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: mode,
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _destinations = [
    (Icons.home_outlined, Icons.home, 'Home'),
    (Icons.collections_bookmark_outlined, Icons.collections_bookmark, 'Library'),
    (Icons.storefront_outlined, Icons.storefront, 'Free books'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  void _go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(onOpenStore: () => _go(2), onOpenLibrary: () => _go(1)),
      const LibraryScreen(),
      const StoreScreen(),
      const SettingsScreen(),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final body = IndexedStack(index: _index, children: pages);
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
                NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
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
            NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
        ],
      ),
    );
  }
}
