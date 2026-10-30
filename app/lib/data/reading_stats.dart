import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/app_paths.dart';

/// Reading time per day, streaks and finished books. Stored in `stats.json`.
///
/// Time is counted from page turns: the time between two page turns counts,
/// up to [maxGap], so leaving the reader open doesn't inflate the numbers.
class ReadingStats extends ChangeNotifier {
  static const maxGap = Duration(minutes: 3);

  /// Seconds read per day, keyed `yyyy-mm-dd` (local time).
  final Map<String, int> secondsByDay = {};
  int pagesTurned = 0;
  final Set<String> finishedBooks = {};

  /// Daily goal in minutes.
  int goalMinutes = 15;

  DateTime? _lastTurn;
  DateTime Function() now = DateTime.now;

  static File get _file => File(p.join(AppPaths.root.path, 'stats.json'));

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      final j = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      fromJson(j);
    } catch (_) {}
  }

  void fromJson(Map<String, dynamic> j) {
    secondsByDay
      ..clear()
      ..addAll(((j['days'] as Map?) ?? {}).map((k, v) => MapEntry(k as String, (v as num).toInt())));
    pagesTurned = (j['pages'] as num?)?.toInt() ?? 0;
    finishedBooks
      ..clear()
      ..addAll(((j['finished'] as List?) ?? []).cast<String>());
    goalMinutes = (j['goal'] as num?)?.toInt() ?? goalMinutes;
  }

  Map<String, dynamic> toJson() => {
        'days': secondsByDay,
        'pages': pagesTurned,
        'finished': finishedBooks.toList(),
        'goal': goalMinutes,
      };

  Future<void> _save() async {
    try {
      await _file.writeAsString(jsonEncode(toJson()));
    } catch (_) {}
  }

  /// Called when the reader opens a book.
  void startSession() => _lastTurn = now();

  /// Called on every page turn.
  void pageTurned() {
    final t = now();
    final last = _lastTurn;
    _lastTurn = t;
    pagesTurned++;
    if (last != null) {
      var gap = t.difference(last);
      if (gap > maxGap) gap = maxGap;
      if (!gap.isNegative) {
        final k = dayKey(t);
        secondsByDay[k] = (secondsByDay[k] ?? 0) + gap.inSeconds;
      }
    }
    if (pagesTurned % 5 == 0) {
      notifyListeners();
      _save();
    }
  }

  /// Called when the reader closes.
  void endSession() {
    _lastTurn = null;
    notifyListeners();
    _save();
  }

  /// Returns true the first time a book is finished.
  bool markFinished(String bookId) {
    final added = finishedBooks.add(bookId);
    if (added) {
      notifyListeners();
      _save();
    }
    return added;
  }

  void setGoal(int minutes) {
    goalMinutes = minutes;
    notifyListeners();
    _save();
  }

  int minutesOn(DateTime day) => ((secondsByDay[dayKey(day)] ?? 0) / 60).floor();
  int get minutesToday => minutesOn(now());

  /// A day counts towards the streak after one minute of reading.
  bool _readOn(DateTime day) => (secondsByDay[dayKey(day)] ?? 0) >= 60;

  /// Consecutive days with reading, ending today (or yesterday, so the
  /// streak isn't shown as lost before the reader had a chance today).
  int get streak {
    var day = now();
    if (!_readOn(day)) day = day.subtract(const Duration(days: 1));
    var n = 0;
    while (_readOn(day)) {
      n++;
      day = DateTime(day.year, day.month, day.day - 1, 12);
    }
    return n;
  }

  int get bestStreak {
    final days = secondsByDay.entries.where((e) => e.value >= 60).map((e) => DateTime.parse(e.key)).toList()..sort();
    var best = 0, run = 0;
    DateTime? prev;
    for (final d in days) {
      run = (prev != null && DateTime(prev.year, prev.month, prev.day + 1) == d) ? run + 1 : 1;
      if (run > best) best = run;
      prev = d;
    }
    return best;
  }

  /// Minutes per day for the last 7 days, oldest first (ends today).
  List<int> get lastWeek {
    final t = now();
    return [for (var i = 6; i >= 0; i--) minutesOn(DateTime(t.year, t.month, t.day - i, 12))];
  }

  int get minutesThisWeek => lastWeek.fold(0, (a, b) => a + b);

  bool get hasAnyReading => secondsByDay.values.any((s) => s >= 60);
}
