import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/app_paths.dart';

enum ReaderTheme { white, sepia, gray, dark, black }

extension ReaderThemeColors on ReaderTheme {
  Color get background => switch (this) {
        ReaderTheme.white => const Color(0xFFFFFFFF),
        ReaderTheme.sepia => const Color(0xFFF6EEDC),
        ReaderTheme.gray => const Color(0xFF5A5A5C),
        ReaderTheme.dark => const Color(0xFF1C1C1E),
        ReaderTheme.black => const Color(0xFF000000),
      };
  Color get text => switch (this) {
        ReaderTheme.white => const Color(0xFF1A1A1A),
        ReaderTheme.sepia => const Color(0xFF3B2F20),
        ReaderTheme.gray => const Color(0xFFEDEDED),
        ReaderTheme.dark => const Color(0xFFD9D6CF),
        ReaderTheme.black => const Color(0xFFBDBAB3),
      };
  Color get muted => text.withValues(alpha: 0.55);
  bool get isDark => this == ReaderTheme.dark || this == ReaderTheme.black || this == ReaderTheme.gray;
  String get label => switch (this) {
        ReaderTheme.white => 'White',
        ReaderTheme.sepia => 'Sepia',
        ReaderTheme.gray => 'Gray',
        ReaderTheme.dark => 'Dark',
        ReaderTheme.black => 'Black',
      };
}

enum ReaderFont { serif, sans }

/// User preferences, persisted as JSON.
class SettingsStore extends ChangeNotifier {
  double fontSize = 19;
  double lineHeight = 1.55;
  double margin = 24;
  ReaderTheme readerTheme = ReaderTheme.white;
  ReaderFont font = ReaderFont.serif;
  bool justify = true;

  /// Translate one sentence at a time: identical to the reference model
  /// output but about 3× slower than batched translation.
  bool accurateTranslation = false;

  /// Preferred translation language (FLORES code), e.g. `tam_Taml`.
  String? preferredLang;
  ThemeMode appTheme = ThemeMode.system;

  Future<void> load() async {
    try {
      final f = AppPaths.settings();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      fontSize = (j['fontSize'] as num?)?.toDouble() ?? fontSize;
      lineHeight = (j['lineHeight'] as num?)?.toDouble() ?? lineHeight;
      margin = (j['margin'] as num?)?.toDouble() ?? margin;
      readerTheme = ReaderTheme.values.asNameMap()[j['readerTheme']] ?? readerTheme;
      font = ReaderFont.values.asNameMap()[j['font']] ?? font;
      justify = (j['justify'] as bool?) ?? justify;
      accurateTranslation = (j['accurateTranslation'] as bool?) ?? accurateTranslation;
      preferredLang = j['preferredLang'] as String?;
      appTheme = ThemeMode.values.asNameMap()[j['appTheme']] ?? appTheme;
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      await AppPaths.settings().writeAsString(jsonEncode({
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'margin': margin,
        'readerTheme': readerTheme.name,
        'font': font.name,
        'justify': justify,
        'accurateTranslation': accurateTranslation,
        'preferredLang': preferredLang,
        'appTheme': appTheme.name,
      }));
    } catch (_) {}
  }

  void update(void Function(SettingsStore s) change) {
    change(this);
    notifyListeners();
    _save();
  }
}
