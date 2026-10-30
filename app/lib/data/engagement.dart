import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/app_paths.dart';
import '../core/downloader.dart';
import '../core/version.dart';

/// The "star us on GitHub" prompt and the new-version notice.
/// Stored in `engagement.json`.
class Engagement extends ChangeNotifier {
  /// Moments worth celebrating (finished a book, finished a translation).
  int happyMoments = 0;
  int starPromptsShown = 0;
  bool starred = false;

  /// Newest version on GitHub, if newer than this app.
  String? latestVersion;
  String? dismissedVersion;
  DateTime? lastUpdateCheck;

  /// Set when it's a good moment to show the star prompt (Home shows it).
  final starPrompt = ValueNotifier<bool>(false);

  /// For moments that happen away from a screen (a translation finishing).
  void celebrateLater() {
    if (celebrate()) starPrompt.value = true;
  }

  static File get _file => File(p.join(AppPaths.root.path, 'engagement.json'));

  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      final j = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      happyMoments = (j['happy'] as num?)?.toInt() ?? 0;
      starPromptsShown = (j['starPrompts'] as num?)?.toInt() ?? 0;
      starred = (j['starred'] as bool?) ?? false;
      latestVersion = j['latest'] as String?;
      dismissedVersion = j['dismissed'] as String?;
      lastUpdateCheck = DateTime.tryParse((j['checked'] as String?) ?? '');
      if (latestVersion != null && compareVersions(latestVersion!, kAppVersion) <= 0) latestVersion = null;
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      await _file.writeAsString(jsonEncode({
        'happy': happyMoments,
        'starPrompts': starPromptsShown,
        'starred': starred,
        'latest': latestVersion,
        'dismissed': dismissedVersion,
        'checked': lastUpdateCheck?.toIso8601String(),
      }));
    } catch (_) {}
  }

  /// Records a happy moment; returns true when it's a good time to ask for a
  /// star (the first and the fourth such moment, never once starred).
  bool celebrate() {
    happyMoments++;
    final ask = !starred && starPromptsShown < 2 && (happyMoments == 1 || happyMoments == 4);
    if (ask) starPromptsShown++;
    _save();
    return ask;
  }

  void markStarred() {
    starred = true;
    _save();
    notifyListeners();
  }

  bool get showUpdate => latestVersion != null && latestVersion != dismissedVersion;

  void dismissUpdate() {
    dismissedVersion = latestVersion;
    _save();
    notifyListeners();
  }

  /// Asks GitHub for the newest release, at most once a day.
  Future<void> checkForUpdate({bool force = false}) async {
    final last = lastUpdateCheck;
    if (!force && last != null && DateTime.now().difference(last) < const Duration(hours: 20)) return;
    try {
      final body = await Downloader.getString('https://api.github.com/repos/MohammedAnasAsif/BookIt/releases/latest',
          timeout: const Duration(seconds: 15));
      final tag = (jsonDecode(body) as Map<String, dynamic>)['tag_name'] as String?;
      lastUpdateCheck = DateTime.now();
      if (tag != null && compareVersions(tag, kAppVersion) > 0) {
        latestVersion = tag.replaceFirst(RegExp('^v'), '');
      } else {
        latestVersion = null;
      }
      await _save();
      notifyListeners();
    } catch (_) {}
  }
}
