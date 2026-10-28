/// Splits paragraphs into sentence-sized pieces for translation and joins the
/// translated pieces back together.
class TextSegmenter {
  static const _abbreviations = {
    'mr', 'mrs', 'ms', 'dr', 'st', 'sr', 'jr', 'prof', 'rev', 'gen', 'col', 'capt', 'lt', 'sgt',
    'mt', 'vs', 'etc', 'e.g', 'i.e', 'no', 'vol', 'ch', 'fig', 'p', 'pp', 'cf', 'esq', 'hon',
  };

  // Sentence-ending marks across scripts: Latin, Devanagari danda, CJK,
  // Arabic, Ethiopic, Armenian, Myanmar, Khmer.
  static final _end = RegExp('[.!?।॥。！？؟۔።։။។]');
  static final _closing = RegExp('[\'"’”»」』)\\]]');

  /// Returns sentences of [text]. Very long sentences are further split at
  /// commas/semicolons so each piece stays within [maxChars].
  static List<String> split(String text, {int maxChars = 600}) {
    final t = text.trim();
    if (t.isEmpty) return const [];
    final out = <String>[];
    var start = 0;
    var i = 0;
    while (i < t.length) {
      final ch = t[i];
      if (_end.hasMatch(ch)) {
        var j = i + 1;
        // swallow repeated marks and closing quotes/brackets: ?!" ...”
        while (j < t.length && (_end.hasMatch(t[j]) || _closing.hasMatch(t[j]))) {
          j++;
        }
        final atEnd = j >= t.length;
        final followedBySpace = !atEnd && _isSpace(t.codeUnitAt(j));
        final cjk = ch == '。' || ch == '！' || ch == '？';
        if (atEnd || followedBySpace || cjk) {
          if (ch == '.' && !atEnd && _isAbbreviation(t, start, i)) {
            i = j;
            continue;
          }
          final s = t.substring(start, j).trim();
          if (s.isNotEmpty) out.add(s);
          start = j;
        }
        i = j;
      } else {
        i++;
      }
    }
    final rest = t.substring(start).trim();
    if (rest.isNotEmpty) out.add(rest);

    // Merge tiny fragments ("Yes." "No!") into the previous sentence so the
    // model sees a little context, and split overly long ones.
    final merged = <String>[];
    for (final s in out) {
      if (merged.isNotEmpty && s.length < 12 && merged.last.length + s.length < 200) {
        merged[merged.length - 1] = '${merged.last} $s';
      } else {
        merged.add(s);
      }
    }
    final result = <String>[];
    for (final s in merged) {
      result.addAll(_splitLong(s, maxChars));
    }
    return result;
  }

  static bool _isSpace(int c) => c == 0x20 || c == 0x0A || c == 0x09 || c == 0xA0 || c == 0x3000;

  static bool _isAbbreviation(String t, int sentenceStart, int dot) {
    var k = dot - 1;
    while (k >= sentenceStart && t[k] != ' ' && t[k] != '(' && t[k] != '"' && t[k] != '“') {
      k--;
    }
    final word = t.substring(k + 1, dot).toLowerCase();
    if (word.isEmpty) return false;
    if (_abbreviations.contains(word)) return true;
    // Initials like "J." or "U.S."
    if (RegExp(r'^(\p{Lu}\.?)+$', unicode: true).hasMatch(t.substring(k + 1, dot))) return word.length <= 3;
    return false;
  }

  static List<String> _splitLong(String s, int maxChars) {
    if (s.length <= maxChars) return [s];
    final parts = <String>[];
    var rest = s;
    while (rest.length > maxChars) {
      var cut = -1;
      for (final mark in const ['; ', ': ', ', ', ' — ', ' – ', ' ']) {
        final idx = rest.lastIndexOf(mark, maxChars);
        if (idx > maxChars ~/ 3) {
          cut = idx + mark.length;
          break;
        }
      }
      if (cut <= 0) cut = maxChars;
      parts.add(rest.substring(0, cut).trim());
      rest = rest.substring(cut).trim();
    }
    if (rest.isNotEmpty) parts.add(rest);
    return parts;
  }

  /// Scripts written without spaces between sentences.
  static bool _noSpaceScript(String langCode) {
    final script = langCode.split('_').last;
    return const {'Hans', 'Hant', 'Jpan', 'Thai', 'Laoo', 'Khmr', 'Mymr'}.contains(script);
  }

  static String join(List<String> pieces, String targetLang) =>
      pieces.where((p) => p.trim().isNotEmpty).map((p) => p.trim()).join(_noSpaceScript(targetLang) ? '' : ' ');
}
