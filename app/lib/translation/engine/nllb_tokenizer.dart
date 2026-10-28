import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'precompiled_normalizer.dart';

/// Pure-Dart tokenizer for NLLB-200 that reproduces the Hugging Face
/// `tokenizer.json` pipeline: Precompiled normalizer -> Metaspace
/// pre-tokenizer -> BPE with merges -> `[src_lang] ... </s>` template.
class NllbTokenizer {
  static const int bosId = 0;
  static const int padId = 1;
  static const int eosId = 2;
  static const int unkId = 3;
  static const String _space = '▁'; // ▁

  final List<String> _idToPiece;
  final Map<String, int> _pieceToId;

  /// (leftId << 20 | rightId) -> (rank << 20 | mergedId)
  final Map<int, int> _merges;
  final PrecompiledNormalizer? _normalizer;

  /// `Replace` normalizers applied after the charsmap: (regex, replacement).
  final List<(RegExp, String)> _replacements;
  final List<(String, String)> _replacementSources;
  final Set<int> _specialIds;
  final Map<String, List<int>> _wordCache = {};

  NllbTokenizer._(this._idToPiece, this._pieceToId, this._merges, this._normalizer, this._specialIds,
      this._replacementSources)
      : _replacements = [for (final r in _replacementSources) (RegExp(r.$1), r.$2)];

  int get vocabSize => _idToPiece.length;

  /// Id of a language code token such as `tam_Taml`, or null if unknown.
  int? langId(String code) => _pieceToId[code];

  bool hasLanguage(String code) => _pieceToId.containsKey(code);

  /// Loads from the compact cache next to [tokenizerJson] when present,
  /// otherwise parses `tokenizer.json` and writes the cache for next time.
  static Future<NllbTokenizer> load(File tokenizerJson) async {
    final cache = File('${tokenizerJson.path}.bin');
    if (await cache.exists()) {
      try {
        return fromCompactBytes(await cache.readAsBytes());
      } catch (_) {
        // fall through and rebuild
      }
    }
    final tok = fromJsonString(await tokenizerJson.readAsString());
    try {
      await cache.writeAsBytes(tok.toCompactBytes(), flush: true);
    } catch (_) {}
    return tok;
  }

  factory NllbTokenizer.fromJsonString(String jsonText) {
    final j = jsonDecode(jsonText) as Map<String, dynamic>;
    final model = j['model'] as Map<String, dynamic>;
    if (model['type'] != 'BPE') {
      throw UnsupportedError('Expected a BPE tokenizer, got ${model['type']}');
    }
    final vocab = (model['vocab'] as Map).cast<String, dynamic>();
    final pieceToId = <String, int>{};
    var maxId = 0;
    vocab.forEach((piece, id) {
      final i = (id as num).toInt();
      pieceToId[piece] = i;
      if (i > maxId) maxId = i;
    });
    final specialIds = <int>{bosId, padId, eosId, unkId};
    for (final t in (j['added_tokens'] as List? ?? const [])) {
      final m = t as Map<String, dynamic>;
      final i = (m['id'] as num).toInt();
      pieceToId[m['content'] as String] = i;
      if (m['special'] == true) specialIds.add(i);
      if (i > maxId) maxId = i;
    }
    final idToPiece = List<String>.filled(maxId + 1, '');
    pieceToId.forEach((p, i) => idToPiece[i] = p);

    final merges = <int, int>{};
    final rawMerges = model['merges'] as List? ?? const [];
    for (var rank = 0; rank < rawMerges.length; rank++) {
      final m = rawMerges[rank];
      String a, b;
      if (m is String) {
        final sp = m.indexOf(' ');
        a = m.substring(0, sp);
        b = m.substring(sp + 1);
      } else {
        final l = m as List;
        a = l[0] as String;
        b = l[1] as String;
      }
      final ia = pieceToId[a], ib = pieceToId[b], im = pieceToId[a + b];
      if (ia == null || ib == null || im == null) continue;
      final key = (ia << 20) | ib;
      merges.putIfAbsent(key, () => (rank << 20) | im);
    }

    PrecompiledNormalizer? normalizer;
    final replacements = <(String, String)>[];
    final norm = j['normalizer'];
    if (norm is Map) {
      final list = norm['type'] == 'Sequence' ? (norm['normalizers'] as List) : [norm];
      for (final n in list) {
        if (n is! Map) continue;
        if (n['type'] == 'Precompiled' && n['precompiled_charsmap'] != null) {
          normalizer = PrecompiledNormalizer.fromBase64(n['precompiled_charsmap'] as String);
        } else if (n['type'] == 'Replace') {
          final pat = n['pattern'];
          final content = (n['content'] as String?) ?? '';
          if (pat is Map && pat['Regex'] is String) {
            replacements.add((pat['Regex'] as String, content));
          } else if (pat is Map && pat['String'] is String) {
            replacements.add((RegExp.escape(pat['String'] as String), content));
          }
        }
      }
    }
    return NllbTokenizer._(idToPiece, pieceToId, merges, normalizer, specialIds, replacements);
  }

  // ---------------------------------------------------------------- caching

  static const _magic = 0x424B544B; // "BKTK"

  Uint8List toCompactBytes() {
    final out = BytesBuilder(copy: false);
    void u32(int v) => out.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
    u32(_magic);
    u32(2); // version
    u32(_idToPiece.length);
    for (final p in _idToPiece) {
      final b = utf8.encode(p);
      u32(b.length);
      out.add(b);
    }
    u32(_specialIds.length);
    for (final s in _specialIds) {
      u32(s);
    }
    final entries = _merges.entries.toList();
    u32(entries.length);
    final mb = ByteData(entries.length * 16);
    for (var i = 0; i < entries.length; i++) {
      mb.setUint64(i * 16, entries[i].key, Endian.little);
      mb.setUint64(i * 16 + 8, entries[i].value, Endian.little);
    }
    out.add(mb.buffer.asUint8List());
    final nb = _normalizer?.toBytes() ?? Uint8List(0);
    u32(nb.length);
    out.add(nb);
    u32(_replacementSources.length);
    for (final r in _replacementSources) {
      for (final s in [r.$1, r.$2]) {
        final b = utf8.encode(s);
        u32(b.length);
        out.add(b);
      }
    }
    return out.toBytes();
  }

  factory NllbTokenizer.fromCompactBytes(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    var o = 0;
    int u32() {
      final v = bd.getUint32(o, Endian.little);
      o += 4;
      return v;
    }

    if (u32() != _magic || u32() != 2) throw const FormatException('bad tokenizer cache');
    final n = u32();
    final idToPiece = List<String>.filled(n, '');
    final pieceToId = <String, int>{};
    for (var i = 0; i < n; i++) {
      final len = u32();
      final p = utf8.decode(Uint8List.sublistView(bytes, o, o + len));
      o += len;
      idToPiece[i] = p;
      if (p.isNotEmpty) pieceToId[p] = i;
    }
    final specials = <int>{};
    final ns = u32();
    for (var i = 0; i < ns; i++) {
      specials.add(u32());
    }
    final nm = u32();
    final merges = <int, int>{};
    for (var i = 0; i < nm; i++) {
      final k = bd.getUint64(o, Endian.little);
      final v = bd.getUint64(o + 8, Endian.little);
      o += 16;
      merges[k] = v;
    }
    final nl = u32();
    final normalizer =
        nl > 0 ? PrecompiledNormalizer.fromBytes(Uint8List.fromList(bytes.sublist(o, o + nl))) : null;
    o += nl;
    final nr = u32();
    final replacements = <(String, String)>[];
    String str() {
      final len = u32();
      final v = utf8.decode(Uint8List.sublistView(bytes, o, o + len));
      o += len;
      return v;
    }

    for (var i = 0; i < nr; i++) {
      final a = str();
      final b = str();
      replacements.add((a, b));
    }
    return NllbTokenizer._(idToPiece, pieceToId, merges, normalizer, specials, replacements);
  }

  // ---------------------------------------------------------------- encode

  String normalize(String text) {
    var s = _normalizer?.normalize(text) ?? text;
    for (final r in _replacements) {
      s = s.replaceAll(r.$1, r.$2);
    }
    return s;
  }

  /// Token ids of [text] without language or end tokens.
  List<int> encodeText(String text) {
    var s = normalize(text);
    if (s.isEmpty) return const [];
    s = s.replaceAll(' ', _space);
    if (!s.startsWith(_space)) s = '$_space$s';
    final ids = <int>[];
    // Metaspace split: every ▁ starts a new word.
    var start = 0;
    for (var i = 1; i <= s.length; i++) {
      if (i == s.length || s.codeUnitAt(i) == 0x2581) {
        ids.addAll(_encodeWord(s.substring(start, i)));
        start = i;
      }
    }
    return ids;
  }

  /// `[src_lang] tokens </s>` as expected by the encoder.
  List<int> encodeSource(String text, String srcLang, {int maxTokens = 250}) {
    final lang = _pieceToId[srcLang];
    if (lang == null) throw ArgumentError('Unknown language $srcLang');
    var body = encodeText(text);
    if (body.length > maxTokens) body = body.sublist(0, maxTokens);
    return [lang, ...body, eosId];
  }

  List<int> _encodeWord(String word) {
    final cached = _wordCache[word];
    if (cached != null) return cached;
    // Very long "words" (URLs, runs of symbols) are split to bound the cost.
    if (word.length > 120) {
      final out = <int>[];
      for (var i = 0; i < word.length; i += 100) {
        out.addAll(_bpe(word.substring(i, i + 100 > word.length ? word.length : i + 100)));
      }
      return out;
    }
    final r = _bpe(word);
    if (_wordCache.length > 60000) _wordCache.clear();
    _wordCache[word] = r;
    return r;
  }

  List<int> _bpe(String word) {
    final symbols = <int>[];
    for (final rune in word.runes) {
      final id = _pieceToId[String.fromCharCode(rune)];
      if (id == null) {
        if (symbols.isEmpty || symbols.last != unkId) symbols.add(unkId); // fuse_unk
      } else {
        symbols.add(id);
      }
    }
    while (symbols.length > 1) {
      var bestRank = -1, bestPos = -1, bestId = -1;
      for (var i = 0; i < symbols.length - 1; i++) {
        final m = _merges[(symbols[i] << 20) | symbols[i + 1]];
        if (m == null) continue;
        final rank = m >> 20;
        if (bestRank < 0 || rank < bestRank) {
          bestRank = rank;
          bestPos = i;
          bestId = m & 0xFFFFF;
        }
      }
      if (bestPos < 0) break;
      symbols[bestPos] = bestId;
      symbols.removeAt(bestPos + 1);
    }
    return symbols;
  }

  // ---------------------------------------------------------------- decode

  String decode(List<int> ids) {
    final sb = StringBuffer();
    for (final id in ids) {
      if (id < 0 || id >= _idToPiece.length) continue;
      if (_specialIds.contains(id)) continue;
      sb.write(_idToPiece[id]);
    }
    var s = sb.toString().replaceAll(_space, ' ');
    if (s.startsWith(' ')) s = s.substring(1);
    return s;
  }
}
