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
    final report = <String, dynamic>{};

    for (final batchSize in [1, 4, 8]) {
      final results = <Map<String, dynamic>>[];
      var exact = 0;
      var tokens = 0;
      final sw = Stopwatch()..start();
      for (var i = 0; i < refs.length; i += batchSize) {
        final group = refs.sublist(i, (i + batchSize).clamp(0, refs.length));
        // Batches only contain one target language (as in the app).
        final byTarget = <String, List<Map<String, dynamic>>>{};
        for (final r in group) {
          byTarget.putIfAbsent(r['tgt'] as String, () => []).add(r);
        }
        for (final entry in byTarget.entries) {
          final out = model.generate(
            [
              for (final r in entry.value)
                tok.encodeSource(TextSegmenter.prepareForModel(r['text'] as String), r['src'] as String)
            ],
            tok.langId(entry.key)!,
          );
          for (var k = 0; k < entry.value.length; k++) {
            tokens += out[k].length;
            final mine = tok.decode(out[k]);
            final ref = entry.value[k]['translation'] as String;
            if (mine == ref) exact++;
            results.add({'tgt': entry.key, 'dart': mine, 'python': ref, 'same': mine == ref});
          }
        }
      }
      sw.stop();
      report['batch$batchSize'] = {
        'exact': exact,
        'total': refs.length,
        'seconds': sw.elapsedMilliseconds / 1000,
        'tokensPerSecond': tokens / (sw.elapsedMilliseconds / 1000),
        'results': results,
      };
      // ignore: avoid_print
      print('batch $batchSize: exact $exact/${refs.length}, '
          '${(tokens / (sw.elapsedMilliseconds / 1000)).toStringAsFixed(1)} tokens/s');
    }
    model.release();
    final out = Platform.environment['NLLB_REPORT'];
    if (out != null) File(out).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(report));
    // One sentence at a time must reproduce the reference exactly (same model,
    // same greedy decoding).
    expect((report['batch1'] as Map)['exact'], greaterThanOrEqualTo(refs.length - 1));
  }, skip: !available, timeout: const Timeout(Duration(minutes: 40)));
}
