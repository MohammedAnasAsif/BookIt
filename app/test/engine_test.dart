import 'dart:convert';
import 'dart:io';

import 'package:bookit/translation/engine/nllb_model.dart';
import 'package:bookit/translation/engine/nllb_tokenizer.dart';
import 'package:bookit/translation/engine/text_segmenter.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end check of the on-device engine against reference translations
/// from the Python implementation. Runs in the "Engine test" workflow, which
/// downloads the model and sets NLLB_MODEL_DIR. Skipped otherwise.
void main() {
  final dir = Platform.environment['NLLB_MODEL_DIR'];
  final available = dir != null && File('$dir/${NllbModel.encoderFile}').existsSync();

  test('translates like the reference implementation', () async {
    final tok = await NllbTokenizer.load(File('$dir/tokenizer.json'));
    final model = NllbModel.load(dir!, threads: 2);
    final refs = (jsonDecode(File(Platform.environment['NLLB_REFERENCE']!).readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    final results = <Map<String, dynamic>>[];
    var exact = 0;
    final sw = Stopwatch()..start();
    // Batch all English sources per target language, like the app does.
    final byTarget = <String, List<Map<String, dynamic>>>{};
    for (final r in refs) {
      byTarget.putIfAbsent('${r['src']}>${r['tgt']}', () => []).add(r);
    }
    var tokens = 0;
    for (final group in byTarget.values) {
      final src = group.first['src'] as String;
      final tgt = group.first['tgt'] as String;
      final out = model.generate(
        [for (final r in group) tok.encodeSource(TextSegmenter.prepareForModel(r['text'] as String), src)],
        tok.langId(tgt)!,
      );
      for (var i = 0; i < group.length; i++) {
        tokens += out[i].length;
        final mine = tok.decode(out[i]);
        final ref = group[i]['translation'] as String;
        if (mine == ref) exact++;
        results.add({'tgt': tgt, 'text': group[i]['text'], 'dart': mine, 'python': ref, 'same': mine == ref});
      }
    }
    sw.stop();
    model.release();
    final report = {
      'exact': exact,
      'total': refs.length,
      'seconds': sw.elapsedMilliseconds / 1000,
      'tokens': tokens,
      'tokensPerSecond': tokens / (sw.elapsedMilliseconds / 1000),
      'results': results,
    };
    final out = Platform.environment['NLLB_REPORT'];
    if (out != null) File(out).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(report));
    // ignore: avoid_print
    print('exact matches: $exact/${refs.length} in ${sw.elapsedMilliseconds} ms');
    // Batched (padded) decoding can differ in tiny numeric ways; most outputs
    // must still be identical to the unbatched reference.
    expect(exact / refs.length, greaterThanOrEqualTo(0.75));
  }, skip: !available, timeout: const Timeout(Duration(minutes: 30)));
}
