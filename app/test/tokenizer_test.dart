import 'dart:convert';
import 'dart:io';

import 'package:bookit/translation/engine/nllb_tokenizer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Compares the Dart tokenizer with reference ids produced by the Python
/// `transformers` tokenizer. Needs `tokenizer.json`; CI downloads it and sets
/// NLLB_TOKENIZER. Skipped otherwise.
void main() {
  final path = Platform.environment['NLLB_TOKENIZER'];
  final available = path != null && File(path).existsSync();

  group('NllbTokenizer', () {
    late NllbTokenizer tok;
    setUpAll(() async {
      if (available) tok = await NllbTokenizer.load(File(path));
    });

    test('matches reference token ids', () {
      final fx = jsonDecode(File('test/fixtures/token_fixtures.json').readAsStringSync()) as Map<String, dynamic>;
      for (final item in (fx['items'] as List).cast<Map<String, dynamic>>()) {
        final ids = tok.encodeSource(item['text'] as String, item['lang'] as String, maxTokens: 10000);
        expect(ids, (item['ids'] as List).cast<int>(), reason: 'text: ${item['text']}');
      }
      (fx['lang_ids'] as Map).forEach((k, v) => expect(tok.langId(k as String), v));
    }, skip: !available);

    test('broad agreement on book text', () {
      final f = File(Platform.environment['NLLB_BROAD_FIXTURES'] ?? 'test/fixtures/broad_fixtures_eng.json');
      final items = (jsonDecode(f.readAsStringSync()) as List).cast<Map<String, dynamic>>();
      if (items.isEmpty) return;
      var same = 0;
      final failures = <String>[];
      for (final it in items) {
        final ids = tok.encodeSource(it['text'] as String, (it['lang'] as String?) ?? 'eng_Latn', maxTokens: 10000);
        if (_eq(ids, (it['ids'] as List).cast<int>())) {
          same++;
        } else if (failures.length < 5) {
          failures.add(it['text'] as String);
        }
      }
      final rate = same / items.length;
      // ignore: avoid_print
      print('tokenizer agreement: $same/${items.length} = ${(rate * 100).toStringAsFixed(2)}%');
      expect(rate, greaterThan(0.99), reason: 'first mismatches: $failures');
    }, skip: !available);

    test('decode round trip', () {
      final ids = tok.encodeText('नमस्ते दुनिया, यह एक परीक्षण है।');
      expect(tok.decode(ids), 'नमस्ते दुनिया, यह एक परीक्षण है।');
    }, skip: !available);

    test('compact cache gives identical results', () {
      final again = NllbTokenizer.fromCompactBytes(tok.toCompactBytes());
      for (final s in ['Hello   world.\tTabs', 'Café naïve — ½', 'मैं आज बाज़ार जा रहा हूँ।']) {
        expect(again.encodeSource(s, 'eng_Latn'), tok.encodeSource(s, 'eng_Latn'));
      }
    }, skip: !available);
  });
}

bool _eq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
