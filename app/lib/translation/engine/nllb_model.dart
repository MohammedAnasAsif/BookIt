import 'dart:io';

import 'package:onnxruntime/onnxruntime.dart';

import 'ort_tensors.dart';

/// Runs NLLB-200 (ONNX export from Hugging Face Optimum) with batched greedy
/// decoding and a key/value cache:
///  * the encoder reads the source sentence once,
///  * `decoder_model` handles the first step and produces the cache,
///  * `decoder_with_past_model` produces every following token.
///
/// (The single "merged" decoder file in the same export fails at runtime,
/// which is why two decoder files are used.)
class NllbModel {
  static const encoderFile = 'encoder_model_quantized.onnx';
  static const firstDecoderFile = 'decoder_model_quantized.onnx';
  static const decoderFile = 'decoder_with_past_model_quantized.onnx';

  static const int _eos = 2;
  static const int _pad = 1;

  final OrtSession _encoder;
  final OrtSession _first;
  final OrtSession _next;
  final List<String> _firstOutputs;
  final List<String> _nextInputs;
  final List<String> _nextOutputs;
  final int vocabSize;

  NllbModel._(this._encoder, this._first, this._next, this.vocabSize)
      : _firstOutputs = _first.outputNames,
        _nextInputs = _next.inputNames,
        _nextOutputs = _next.outputNames;

  static bool _envReady = false;

  static NllbModel load(String dir, {int threads = 0, int vocabSize = 256206}) {
    if (!_envReady) {
      OrtEnv.instance.init();
      _envReady = true;
    }
    return NllbModel._(
      OrtTensors.openSession('$dir${Platform.pathSeparator}$encoderFile', threads: threads),
      OrtTensors.openSession('$dir${Platform.pathSeparator}$firstDecoderFile', threads: threads),
      OrtTensors.openSession('$dir${Platform.pathSeparator}$decoderFile', threads: threads),
      vocabSize,
    );
  }

  void release() {
    _encoder.release();
    _first.release();
    _next.release();
  }

  /// Translates a batch of already-encoded sources (`[lang] ... </s>`).
  /// Returns the generated target ids for each source, without special tokens.
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
    final encoderPast = <String, OrtValue>{};
    var decoderPast = <String, OrtValue>{};

    // Picks the next token for every sequence from the logits of the last
    // position and records it.
    List<int> pick(OrtValue logitsValue, int stepLen) {
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
          if (_isLooping(outputs[i]) || outputs[i].length >= limit) finished[i] = true;
        }
        next.add(best);
      }
      return next;
    }

    try {
      // ---- first step: [</s>, tgt_lang]
      final startIds = <int>[];
      for (var i = 0; i < b; i++) {
        startIds.addAll([_eos, targetLangId]);
      }
      final firstIds = OrtTensors.int64(startIds, [b, 2]);
      final res = _first.run(runOptions, {
        'input_ids': firstIds,
        'encoder_attention_mask': attention,
        'encoder_hidden_states': hidden,
      });
      firstIds.release();
      var next = pick(res[0]!, 2);
      res[0]!.release();
      for (var k = 1; k < res.length; k++) {
        final name = _firstOutputs[k].replaceFirst('present', 'past_key_values');
        if (name.contains('.encoder.')) {
          encoderPast[name] = res[k]!;
        } else {
          decoderPast[name] = res[k]!;
        }
      }

      // ---- following steps: one token at a time with the cache
      final wantsHidden = _nextInputs.contains('encoder_hidden_states');
      for (var step = 1; step < limit && !finished.every((f) => f); step++) {
        final stepIds = OrtTensors.int64(next, [b, 1]);
        final inputs = <String, OrtValue>{
          'input_ids': stepIds,
          'encoder_attention_mask': attention,
          if (wantsHidden) 'encoder_hidden_states': hidden,
        };
        for (final name in _nextInputs) {
          if (!name.startsWith('past_key_values')) continue;
          final v = decoderPast[name] ?? encoderPast[name];
          if (v == null) throw StateError('Missing cache input $name');
          inputs[name] = v;
        }
        final out = _next.run(runOptions, inputs);
        stepIds.release();
        next = pick(out[0]!, 1);
        out[0]!.release();
        final newPast = <String, OrtValue>{};
        for (var k = 1; k < out.length; k++) {
          final name = _nextOutputs[k].replaceFirst('present', 'past_key_values');
          if (name.contains('.encoder.')) {
            // Some exports repeat the (unchanged) cross-attention cache.
            out[k]!.release();
          } else {
            newPast[name] = out[k]!;
          }
        }
        for (final v in decoderPast.values) {
          v.release();
        }
        decoderPast = newPast;
      }
    } finally {
      for (final v in decoderPast.values) {
        v.release();
      }
      for (final v in encoderPast.values) {
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
      if (_repeats(seq, n)) return true;
    }
    return false;
  }

  static bool _repeats(List<int> seq, int n) {
    for (var r = 1; r < 4; r++) {
      for (var k = 0; k < n; k++) {
        if (seq[seq.length - 1 - k] != seq[seq.length - 1 - k - r * n]) return false;
      }
    }
    return true;
  }

  static void _trimRepeats(List<int> seq) {
    for (var n = 1; n <= 8; n++) {
      while (seq.length >= n * 4 && _repeats(seq, n)) {
        seq.removeRange(seq.length - n * 3, seq.length);
      }
    }
  }
}
