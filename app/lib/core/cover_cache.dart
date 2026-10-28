import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_paths.dart';
import 'downloader.dart';

/// Downloads book covers once and keeps them on disk, so they show quickly
/// and also offline. Tries each URL in turn (main site, then a mirror) and
/// limits how many covers download at the same time.
class CoverCache {
  static final Map<String, Future<File?>> _inFlight = {};
  static final Set<String> _failed = {};
  static int _running = 0;
  static const _maxParallel = 6;
  static final Queue<Completer<void>> _waiting = Queue();

  static Directory get _dir => Directory(p.join(AppPaths.cache.path, 'covers'));

  static File _file(String key) => File(p.join(_dir.path, '${key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.jpg'));

  /// The cached cover file if it is already on disk (synchronous check).
  static File? cached(String key) {
    final f = _file(key);
    if (!f.existsSync() || f.lengthSync() < 200) return null;
    try {
      final raf = f.openSync();
      final head = raf.readSync(12);
      raf.closeSync();
      if (isImage(head)) return f;
      f.deleteSync(); // a broken download from an older version
    } catch (_) {}
    return null;
  }

  /// JPEG, PNG, GIF or WebP?
  static bool isImage(List<int> b) {
    if (b.length < 12) return false;
    if (b[0] == 0xFF && b[1] == 0xD8) return true;
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return true;
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return true;
    if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && b[8] == 0x57 && b[9] == 0x45) return true;
    return false;
  }

  static Future<File?> get(String key, List<String> urls) {
    final hit = cached(key);
    if (hit != null) return Future.value(hit);
    if (_failed.contains(key) || urls.isEmpty) return Future.value(null);
    return _inFlight.putIfAbsent(key, () => _download(key, urls).whenComplete(() => _inFlight.remove(key)));
  }

  static Future<File?> _download(String key, List<String> urls) async {
    await _acquire();
    try {
      await _dir.create(recursive: true);
      for (final url in urls) {
        try {
          final bytes = await Downloader.getBytes(url, timeout: const Duration(seconds: 30));
          if (bytes.length < 200 || !isImage(bytes)) {
            final preview = String.fromCharCodes(bytes.take(120).map((c) => c < 32 || c > 126 ? 46 : c));
            _log('$url: not an image (${bytes.length} bytes): $preview');
            continue;
          }
          final f = _file(key);
          await f.writeAsBytes(bytes, flush: true);
          return f;
        } catch (e) {
          _log('$url: $e');
        }
      }
      _failed.add(key);
      return null;
    } finally {
      _release();
    }
  }

  /// Records why covers fail (helps diagnose network problems).
  static void _log(String line) {
    try {
      File(p.join(AppPaths.root.path, 'cover_errors.log'))
          .writeAsStringSync('${DateTime.now().toIso8601String()} $line\n', mode: FileMode.append);
    } catch (_) {}
  }

  static Future<void> _acquire() async {
    if (_running < _maxParallel) {
      _running++;
      return;
    }
    final c = Completer<void>();
    _waiting.add(c);
    await c.future;
    _running++;
  }

  static void _release() {
    _running--;
    if (_waiting.isNotEmpty) _waiting.removeFirst().complete();
  }
}
