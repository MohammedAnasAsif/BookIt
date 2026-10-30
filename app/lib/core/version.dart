/// The app version shown in Settings and used for the update check.
/// Keep in sync with `version:` in pubspec.yaml (a test checks this).
const kAppVersion = '0.3.0';

const kRepoUrl = 'https://github.com/MohammedAnasAsif/BookIt';
const kReleasesUrl = '$kRepoUrl/releases/latest';
const kIssuesUrl = '$kRepoUrl/issues/new/choose';

/// Compares dotted version numbers: negative if [a] < [b].
int compareVersions(String a, String b) {
  List<int> parts(String v) =>
      v.replaceFirst(RegExp('^v'), '').split(RegExp(r'[.+-]')).take(3).map((x) => int.tryParse(x) ?? 0).toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}
