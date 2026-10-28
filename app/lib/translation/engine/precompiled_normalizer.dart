import 'dart:convert';
import 'dart:typed_data';

import 'package:characters/characters.dart';

/// Re-implementation of the SentencePiece "precompiled charsmap" normalizer
/// used by Hugging Face `tokenizers` (`Precompiled` normalizer).
///
/// The charsmap is a darts-clone double-array trie over UTF-8 bytes whose
/// values point into a blob of NUL-terminated replacement strings. The
/// behaviour (grapheme first, then per character; first trie match wins)
/// deliberately mirrors the reference implementation so token ids match the
/// Python tokenizer exactly.
class PrecompiledNormalizer {
  final Uint32List _trie;
  final Uint8List _normalized;
  final Map<String, String?> _cache = {};

  PrecompiledNormalizer._(this._trie, this._normalized);

  factory PrecompiledNormalizer.fromBase64(String charsmap) =>
      PrecompiledNormalizer.fromBytes(base64.decode(charsmap));

  factory PrecompiledNormalizer.fromBytes(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    final trieSize = bd.getUint32(0, Endian.little);
    final units = trieSize ~/ 4;
    final trie = Uint32List(units);
    for (var i = 0; i < units; i++) {
      trie[i] = bd.getUint32(4 + i * 4, Endian.little);
    }
    final normalized = Uint8List.fromList(bytes.sublist(4 + trieSize));
    return PrecompiledNormalizer._(trie, normalized);
  }

  Uint8List toBytes() {
    final out = BytesBuilder();
    final head = ByteData(4)..setUint32(0, _trie.length * 4, Endian.little);
    out.add(head.buffer.asUint8List());
    final trieBytes = ByteData(_trie.length * 4);
    for (var i = 0; i < _trie.length; i++) {
      trieBytes.setUint32(i * 4, _trie[i], Endian.little);
    }
    out.add(trieBytes.buffer.asUint8List());
    out.add(_normalized);
    return out.toBytes();
  }

  // darts-clone unit helpers
  static bool _hasLeaf(int unit) => ((unit >> 8) & 1) == 1;
  static int _value(int unit) => unit & 0x7fffffff;
  static int _label(int unit) => unit & (0x80000000 | 0xFF);
  static int _offset(int unit) => (unit >> 10) << ((unit & (1 << 9)) >> 6);

  /// Returns the replacement for the first (shortest) trie match that is a
  /// prefix of [bytes], or null when nothing matches.
  String? _transform(List<int> bytes) {
    if (_trie.isEmpty) return null;
    var nodePos = 0;
    var unit = _trie[nodePos];
    nodePos ^= _offset(unit);
    for (final c in bytes) {
      if (c == 0) break;
      nodePos ^= c;
      if (nodePos < 0 || nodePos >= _trie.length) return null;
      unit = _trie[nodePos];
      if (_label(unit) != c) return null;
      nodePos ^= _offset(unit);
      if (nodePos < 0 || nodePos >= _trie.length) return null;
      if (_hasLeaf(unit)) {
        final index = _value(_trie[nodePos]);
        var end = index;
        while (end < _normalized.length && _normalized[end] != 0) {
          end++;
        }
        return utf8.decode(_normalized.sublist(index, end), allowMalformed: true);
      }
    }
    return null;
  }

  String? _transformCached(String chunk) {
    final cached = _cache[chunk];
    if (cached != null || _cache.containsKey(chunk)) return cached;
    final r = _transform(utf8.encode(chunk));
    if (_cache.length < 20000) _cache[chunk] = r;
    return r;
  }

  String normalize(String input) {
    final sb = StringBuffer();
    for (final grapheme in input.characters) {
      if (utf8.encode(grapheme).length < 6) {
        final norm = _transformCached(grapheme);
        if (norm != null) {
          sb.write(norm);
          continue;
        }
      }
      for (final rune in grapheme.runes) {
        final ch = String.fromCharCode(rune);
        final norm = _transformCached(ch);
        sb.write(norm ?? ch);
      }
    }
    return sb.toString();
  }
}
