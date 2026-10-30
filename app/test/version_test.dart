import 'dart:io';

import 'package:bookit/core/version.dart';
import 'package:bookit/data/reading_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('kAppVersion matches pubspec', () {
    final pub = File('pubspec.yaml').readAsStringSync();
    final v = RegExp(r'^version:\s*([0-9.]+)', multiLine: true).firstMatch(pub)!.group(1);
    expect(kAppVersion, v);
  });

  test('compareVersions', () {
    expect(compareVersions('v0.3.1', '0.3.0'), greaterThan(0));
    expect(compareVersions('0.3.0', '0.3.0'), 0);
    expect(compareVersions('0.2.9', '0.10.0'), lessThan(0));
  });

  test('reading streak and weekly minutes', () {
    final s = ReadingStats();
    var t = DateTime(2026, 10, 28, 20);
    s.now = () => t;
    // Two days ago, yesterday and today, 5 minutes each.
    for (final day in [26, 27, 28]) {
      t = DateTime(2026, 10, day, 20);
      s.startSession();
      for (var i = 0; i < 5; i++) {
        t = t.add(const Duration(minutes: 1));
        s.pageTurned();
      }
    }
    expect(s.streak, 3);
    expect(s.minutesToday, 5);
    expect(s.lastWeek.last, 5);
    expect(s.minutesThisWeek, 15);
    // A long pause only counts up to the gap limit.
    t = t.add(const Duration(hours: 2));
    s.pageTurned();
    expect(s.minutesToday, 5 + ReadingStats.maxGap.inMinutes);
    // Tomorrow, before reading, the streak still shows.
    t = DateTime(2026, 10, 29, 9);
    expect(s.streak, 3);
    t = DateTime(2026, 10, 31, 9);
    expect(s.streak, 0);
    expect(s.bestStreak, 3);
  });
}
