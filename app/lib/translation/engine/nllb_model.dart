import 'dart:io';

import 'package:onnxruntime/onnxruntime.dart';

import 'ort_tensors.dart';

/// Runs the NLLB-200 encoder and the merged (KV-cache) decoder exported by
/// Hugging Face Optimum, with batched greedy decoding.
class NllbModel {
  static const encoderFile = 'encoder_model_quantized.onnx';
  static const decoderFile = 'decoder_model_merged_quantized.onnx';

  static const int _heads = 16;
  static const int _headDim = 64;
  static const int _eos = 2;
  static const int _pad = 1;

  final OrtSession _encoder;
  final OrtSession _decoder;
  final List<String> _pastNames;
  final List<String> _decoderOutputs;
  final int vocabSize;

  NllbModel._(this._encoder, this._decoder, this._pastNames, this._decoderOutputs, this.vocabSize);

  static bool _envReady = false;

  static NllbModel load(String dir, {int threads = 0, int vocabSize = 256206}) {
    if (!_envReady) {
      OrtEnv.instance.init();
      _envReady = true;
    }
    OrtSessionOptions options() {
      final o = OrtSessionOptions();
      if (threads > 0) o.setIntraOpNumThreads(threads);
      return o;
    }

    final enc = OrtSession.fromFile(File('$dir/$encoderFile'), options());
    final dec = OrtSession.fromFile(File('$dir/$decoderFile'), options());
    final past = dec.inputNames.where((n) => n.startsWith('past_key_values')).toList();
    return NllbModel._(enc, dec, past, dec.outputNames, vocabSize);
  }

  void release() {
    _encoder.release();
    _decoder.release();
  }

  /// Translates a batch of already-encoded sources (`[lang] ... </s>`).
  /// Returns generated target ids (without the leading `</s> tgt_lang` and
  /// without the final `</s>`).
  List<List<int>> generate(List<List<int>> sources, int targetLangId, {int? maxNewTokens}) {
    if (sources.isEmpty) return const [];
    final b = sources.length;
    final s = sources.map((e) => e.length).reduce((a, c) => a > c ? a : c);
    final ids = List<int>.filled(b * s, _pad);
    final mask = List<int>.filled(b * s, 0);
    for (var i = 0; i < b; i++) {
      for (var j = 0; j < sources[i].length; j++) {
        ids[i * s + j] = sources[i][j];
        mask[i * s + j] = 1;
      }
    }
    final limit = maxNewTokens ?? (s * 2 + 16).clamp(24, 400);

    final runOptions = OrtRunOptions();
    final inputIds = OrtTensors.int64(ids, [b, s]);
    final attention = OrtTensors.int64(mask, [b, s]);
    final encOut = _encoder.run(runOptions, {'input_ids': inputIds, 'attention_mask': attention});
    inputIds.release();
    final hidden = encOut[0]!;

    final outputs = List.generate(b, (_) => <int>[]);
    final finished = List<bool>.filled(b, false);

    // Step 1: no cache. Past tensors are zero-length.
    var past = <String, OrtValue>{
      for (final n in _pastNames) n: OrtTensors.emptyFloat([b, _heads, 0, _headDim]),
    };
    var stepIds = <int>[];
    for (var i = 0; i < b; i++) {
      stepIds.addAll([_eos, targetLangId]);
    }
    var stepLen = 2;
    var useCache = false;

    try {
      for (var step = 0; step < limit; step++) {
        final idsT = OrtTensors.int64(stepIds, [b, stepLen]);
        final cacheT = OrtTensors.boolean([useCache], [1]);
        final inputs = <String, OrtValue>{
          'input_ids': idsT,
          'encoder_attention_mask': attention,
          'encoder_hidden_states': hidden,
          'use_cache_branch': cacheT,
          ...past,
        };
        final res = _decoder.run(runOptions, inputs);
        idsT.release();
        cacheT.release();
        for (final v in past.values) {
          v.release();
        }

        final logitsValue = res[0]!;
        final logits = OrtTensors.floatView(logitsValue, b * stepLen * vocabSize);
        final next = <int>[];
        for (var i = 0; i < b; i++) {
          if (finished[i]) {
            next.add(_pad);
            continue;
          }
          final base = (i * stepLen + stepLen - 1) * vocabSize;
          var best = 0;
          var bestScore = logits[base];
          for (var v = 1; v < vocabSize; v++) {
            final x = logits[base + v];
            if (x > bestScore) {
              bestScore = x;
              best = v;
            }
          }
          if (best == _eos) {
            finished[i] = true;
          } else {
            outputs[i].add(best);
            if (_isLooping(outputs[i])) finished[i] = true;
          }
          next.add(best);
        }
        logitsValue.release();

        past = <String, OrtValue>{};
        for (var k = 1; k < res.length; k++) {
          final name = _decoderOutputs[k].replaceFirst('present', 'past_key_values');
          past[name] = res[k]!;
        }
        if (finished.every((f) => f)) break;
        stepIds = next;
        stepLen = 1;
        useCache = true;
      }
    } finally {
      for (final v in past.values) {
        v.release();
      }
      hidden.release();
      attention.release();
      runOptions.release();
    }
    for (final o in outputs) {
      _trimRepeats(o);
    }
    return outputs;
  }

  /// Detects degenerate repetition (the same 1..8-token pattern 4+ times).
  static bool _isLooping(List<int> seq) {
    for (var n = 1; n <= 8; n++) {
      if (seq.length < n * 4) break;
      var same = true;
      for (var r = 1; r < 4 && same; r++) {
        for (var k = 0; k < n; k++) {
          if (seq[seq.length - 1 - k] != seq[seq.length - 1 - k - r * n]) {
            same = false;
            break;
          }
        }
      }
      if (same) return true;
    }
    return false;
  }

  static void _trimRepeats(List<int> seq) {
    for (var n = 1; n <= 8; n++) {
      while (seq.length >= n * 4) {
        var same = true;
        for (var r = 1; r < 4 && same; r++) {
          for (var k = 0; k < n; k++) {
            if (seq[seq.length - 1 - k] != seq[seq.length - 1 - k - r * n]) {
              same = false;
              break;
            }
          }
        }
        if (!same) break;
        seq.removeRange(seq.length - n * 3, seq.length);
      }
    }
  }
}

