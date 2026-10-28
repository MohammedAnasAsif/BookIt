import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../models/book_content.dart';
import 'engine/nllb_model.dart';
import 'engine/nllb_tokenizer.dart';
import 'engine/text_segmenter.dart';
import 'translation_data.dart';

/// Everything a background translation needs; sent to the worker isolate.
class TranslationJobSpec {
  final String bookId;
  final String contentPath;
  final String translationPath;
  final String modelDir;
  final String sourceLang;
  final String targetLang;
  final int startChapter;
  final int threads;
  final int batchSize;
  final String engineName;

  const TranslationJobSpec({
    required this.bookId,
    required this.contentPath,
    required this.translationPath,
    required this.modelDir,
    required this.sourceLang,
    required this.targetLang,
    required this.startChapter,
    required this.threads,
    required this.batchSize,
    required this.engineName,
  });

  List<Object> toMessage() => [
        bookId,
        contentPath,
        translationPath,
        modelDir,
        sourceLang,
        targetLang,
        startChapter,
        threads,
        batchSize,
        engineName,
      ];

  factory TranslationJobSpec.fromMessage(List m) => TranslationJobSpec(
        bookId: m[0] as String,
        contentPath: m[1] as String,
        translationPath: m[2] as String,
        modelDir: m[3] as String,
        sourceLang: m[4] as String,
        targetLang: m[5] as String,
        startChapter: m[6] as int,
        threads: m[7] as int,
        batchSize: m[8] as int,
        engineName: m[9] as String,
      );
}

/// Messages sent from the worker:
///   {'type': 'ready', 'commands': SendPort}
///   {'type': 'status', 'message': String}
///   {'type': 'block', 'c': int, 'b': int, 't': String}
///   {'type': 'progress', 'done': int, 'total': int, 'chapter': int, 'blocksPerMinute': double}
///   {'type': 'finished', 'complete': bool}
///   {'type': 'error', 'message': String}
///
/// Commands accepted: 'stop', ['priority', chapterIndex].
Future<void> translationWorkerMain(List args) async {
  final SendPort out = args[0] as SendPort;
  final spec = TranslationJobSpec.fromMessage(args[1] as List);
  final commands = ReceivePort();
  out.send({'type': 'ready', 'commands': commands.sendPort});

  var stopRequested = false;
  final priorities = <int>[];
  commands.listen((msg) {
    if (msg == 'stop') stopRequested = true;
    if (msg is List && msg.isNotEmpty && msg[0] == 'priority') priorities.add(msg[1] as int);
  });

  NllbModel? model;
  try {
    out.send({'type': 'status', 'message': 'Opening book'});
    final content = BookContent.fromJson(
        jsonDecode(await File(spec.contentPath).readAsString()) as Map<String, dynamic>);
    final tFile = File(spec.translationPath);
    final data = await TranslationData.read(tFile) ??
        TranslationData.emptyFor(content, spec.targetLang, spec.sourceLang, spec.engineName);
    data.conformTo(content);

    out.send({'type': 'status', 'message': 'Loading translation model'});
    final tokenizer = await NllbTokenizer.load(File('${spec.modelDir}/tokenizer.json'));
    final tgtId = tokenizer.langId(spec.targetLang);
    if (tgtId == null || !tokenizer.hasLanguage(spec.sourceLang)) {
      throw StateError('Language pair ${spec.sourceLang} → ${spec.targetLang} is not supported');
    }
    await Future<void>.delayed(Duration.zero);
    model = NllbModel.load(spec.modelDir, threads: spec.threads);

    final total = content.translatableBlockCount;
    var done = data.translatedCount(content);
    final started = DateTime.now();
    var doneThisRun = 0;
    var lastSave = DateTime.now();
    var unsaved = 0;

    // Chapter order: from where the reader is, to the end, then wrap around.
    final n = content.chapters.length;
    final start = spec.startChapter.clamp(0, n == 0 ? 0 : n - 1);
    final order = <int>[for (var c = start; c < n; c++) c, for (var c = 0; c < start; c++) c];

    void progress(int chapter) {
      final minutes = DateTime.now().difference(started).inMilliseconds / 60000.0;
      out.send({
        'type': 'progress',
        'done': done,
        'total': total,
        'chapter': chapter,
        'blocksPerMinute': minutes > 0.05 ? doneThisRun / minutes : 0.0,
      });
    }

    Future<void> save() async {
      await data.write(tFile);
      lastSave = DateTime.now();
      unsaved = 0;
    }

    progress(start);
    out.send({'type': 'status', 'message': 'Translating'});

    final visited = <int>{};
    while (visited.length < order.length && !stopRequested) {
      // Pick the next chapter: a requested priority chapter first.
      int c = -1;
      while (priorities.isNotEmpty) {
        final p = priorities.removeAt(0);
        if (p >= 0 && p < n && !visited.contains(p)) {
          c = p;
          break;
        }
      }
      if (c < 0) c = order.firstWhere((x) => !visited.contains(x), orElse: () => -1);
      if (c < 0) break;
      visited.add(c);

      final blocks = content.chapters[c].blocks;
      // Collect pending sentence units for this chapter.
      final pending = <_Unit>[];
      final pieces = <int, List<String?>>{};
      for (var b = 0; b < blocks.length; b++) {
        final block = blocks[b];
        if (data.chapters[c][b] != null) continue;
        if (block.noTranslate || block.text.trim().isEmpty || hasNoLetters(block.text)) {
          data.chapters[c][b] = block.text;
          continue;
        }
        final sentences = TextSegmenter.split(block.text);
        pieces[b] = List<String?>.filled(sentences.length, null);
        for (var s = 0; s < sentences.length; s++) {
          pending.add(_Unit(b, s, tokenizer.encodeSource(sentences[s], spec.sourceLang)));
        }
      }

      var i = 0;
      while (i < pending.length && !stopRequested) {
        final batch = pending.sublist(i, (i + spec.batchSize).clamp(0, pending.length));
        i += batch.length;
        final results = model.generate([for (final u in batch) u.ids], tgtId);
        for (var k = 0; k < batch.length; k++) {
          final u = batch[k];
          pieces[u.block]![u.sentence] = tokenizer.decode(results[k]);
          final parts = pieces[u.block]!;
          if (parts.every((p) => p != null)) {
            final text = TextSegmenter.join(parts.cast<String>(), spec.targetLang);
            data.chapters[c][u.block] = text;
            done++;
            doneThisRun++;
            unsaved++;
            out.send({'type': 'block', 'c': c, 'b': u.block, 't': text});
          }
        }
        progress(c);
        if (unsaved >= 25 || DateTime.now().difference(lastSave).inSeconds > 20) await save();
        // Let commands (stop / priority) arrive.
        await Future<void>.delayed(Duration.zero);
        if (priorities.isNotEmpty && i < pending.length) {
          // Finish this chapter later: allow it to be picked again.
          visited.remove(c);
          break;
        }
      }
    }
    await save();
    progress(-1);
    out.send({'type': 'finished', 'complete': data.isComplete(content)});
  } catch (e, st) {
    out.send({'type': 'error', 'message': '$e', 'stack': '$st'});
  } finally {
    model?.release();
    commands.close();
  }
}

class _Unit {
  final int block;
  final int sentence;
  final List<int> ids;
  _Unit(this.block, this.sentence, this.ids);
}
