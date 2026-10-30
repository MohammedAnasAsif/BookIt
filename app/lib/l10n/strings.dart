import 'dart:ui' show PlatformDispatcher;

import 'bn.dart';
import 'hi.dart';
import 'mr.dart';
import 'ta.dart';
import 'te.dart';

/// Languages the app's own menus are available in.
const kAppLanguages = <(String, String)>[
  ('en', 'English'),
  ('hi', 'हिन्दी'),
  ('bn', 'বাংলা'),
  ('ta', 'தமிழ்'),
  ('te', 'తెలుగు'),
  ('mr', 'मराठी'),
];

const Map<String, Map<String, String>> _tables = {
  'hi': hiStrings,
  'bn': bnStrings,
  'ta': taStrings,
  'te': teStrings,
  'mr': mrStrings,
};

/// The language of the menus. English text is the key; each language file
/// maps it to a translation. Missing entries fall back to English.
class L10n {
  static String code = 'en';
  static Map<String, String> _table = const {};

  /// [choice] is the user's setting (null = follow the device).
  static void use(String? choice) {
    var c = choice ?? PlatformDispatcher.instance.locale.languageCode;
    if (!_tables.containsKey(c)) c = 'en';
    code = c;
    _table = _tables[c] ?? const {};
  }

  static bool has(String code) => code == 'en' || _tables.containsKey(code);
}

/// Translates a menu string. `{name}` placeholders are filled from [args].
String tr(String english, [Map<String, Object?>? args]) {
  var s = L10n._table[english] ?? english;
  if (args != null) {
    args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  }
  return s;
}
