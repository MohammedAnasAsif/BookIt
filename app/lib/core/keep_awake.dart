import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen on while any part of the app needs it (translating,
/// reading aloud).
class KeepAwake {
  static final Set<String> _reasons = {};

  static void set(String reason, bool on) {
    final before = _reasons.isNotEmpty;
    on ? _reasons.add(reason) : _reasons.remove(reason);
    final after = _reasons.isNotEmpty;
    if (before == after) return;
    try {
      (after ? WakelockPlus.enable() : WakelockPlus.disable()).catchError((_) {});
    } catch (_) {}
  }
}
