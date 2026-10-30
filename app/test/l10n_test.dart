import 'dart:io';

import 'package:bookit/l10n/bn.dart';
import 'package:bookit/l10n/hi.dart';
import 'package:bookit/l10n/mr.dart';
import 'package:bookit/l10n/strings.dart';
import 'package:bookit/l10n/ta.dart';
import 'package:bookit/l10n/te.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every `tr('…')` string in the app should have a translation in each menu
/// language, with the same `{placeholders}`.
void main() {
  final tables = {'hi': hiStrings, 'bn': bnStrings, 'ta': taStrings, 'te': teStrings, 'mr': mrStrings};
  final keys = <String>{'Home', 'Library', 'Free books', 'Settings'};
  final call = RegExp(r"\btr\(\s*((?:'(?:[^'\\]|\\.)*'\s*)+)");
  final lit = RegExp(r"'((?:[^'\\]|\\.)*)'");
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
    for (final m in call.allMatches(f.readAsStringSync())) {
      keys.add(lit.allMatches(m.group(1)!).map((x) => x.group(1)!.replaceAll(r"\'", "'")).join());
    }
  }
  Set<String> ph(String s) => RegExp(r'\{\w+\}').allMatches(s).map((m) => m.group(0)!).toSet();

  for (final e in tables.entries) {
    test('menu strings: ${e.key}', () {
      final missing = keys.where((k) => !e.value.containsKey(k)).toList();
      expect(missing, isEmpty, reason: 'Add these to lib/l10n/${e.key}.dart');
      for (final k in keys) {
        expect(ph(e.value[k]!), ph(k), reason: k);
      }
    });
  }

  test('tr fills placeholders', () {
    L10n.use('ta');
    expect(tr('Page {n} of {total}', {'n': 3, 'total': 9}), 'பக்கம் 3 / 9');
    L10n.use('en');
    expect(tr('Page {n} of {total}', {'n': 3, 'total': 9}), 'Page 3 of 9');
  });
}
