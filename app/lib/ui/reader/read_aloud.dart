import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import '../../core/keep_awake.dart';
import '../../core/languages.dart';

/// Reads text aloud with the device's own text-to-speech voices.
class ReadAloud {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  bool speaking = false;
  int _session = 0;

  Future<void> _init() async {
    if (_ready) return;
    _ready = true;
    await _tts.awaitSpeakCompletion(true);
  }

  /// The device voice locale for [lang] (e.g. `ta-IN`), or null if this
  /// device has no voice for it.
  Future<String?> voiceFor(Language lang) async {
    await _init();
    final iso = lang.iso1;
    if (iso == null) return null;
    try {
      final raw = await _tts.getLanguages;
      final all = <String>[for (final l in (raw as List? ?? const [])) l.toString()];
      String norm(String s) => s.replaceAll('_', '-').toLowerCase();
      final matches = all.where((l) => norm(l) == iso || norm(l).startsWith('$iso-')).toList();
      if (matches.isEmpty) return null;
      // Prefer the Indian variant for Indian languages and English.
      matches.sort((a, b) => (norm(b).endsWith('-in') ? 1 : 0) - (norm(a).endsWith('-in') ? 1 : 0));
      return matches.first;
    } catch (_) {
      return null;
    }
  }

  /// Speaks [pieces] one after another. Returns false if stopped early.
  Future<bool> speakAll(String locale, List<String> pieces) async {
    await _init();
    final session = ++_session;
    speaking = true;
    KeepAwake.set('read-aloud', true);
    await _tts.setLanguage(locale);
    for (final piece in pieces) {
      if (session != _session || !speaking) return false;
      final t = piece.trim();
      if (t.isEmpty) continue;
      await _tts.speak(t);
    }
    return session == _session && speaking;
  }

  Future<void> stop() async {
    speaking = false;
    _session++;
    KeepAwake.set('read-aloud', false);
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
