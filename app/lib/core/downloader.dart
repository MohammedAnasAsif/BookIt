import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class DownloadCancelled implements Exception {
  @override
  String toString() => 'Download cancelled';
}

/// Lets the caller stop a running download.
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// HTTP helpers with progress reporting and resumable downloads.
class Downloader {
  static final http.Client _client = IOClient(_httpClient());

  /// dart:io does not use the Windows proxy settings by itself; read them so
  /// BookIt works on networks where the browser goes through a proxy.
  static HttpClient _httpClient() {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    final proxy = _windowsProxy();
    if (proxy != null) c.findProxy = (uri) => 'PROXY $proxy; DIRECT';
    return c;
  }

  static String? _windowsProxy() {
    if (!Platform.isWindows) return null;
    try {
      const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
      final enabled = Process.runSync('reg', ['query', key, '/v', 'ProxyEnable']).stdout.toString();
      if (!RegExp(r'ProxyEnable\s+REG_DWORD\s+0x1').hasMatch(enabled)) return null;
      final server = Process.runSync('reg', ['query', key, '/v', 'ProxyServer']).stdout.toString();
      final m = RegExp(r'ProxyServer\s+REG_SZ\s+(\S+)').firstMatch(server);
      if (m == null) return null;
      var value = m.group(1)!;
      // "http=host:port;https=host:port" or "host:port"
      final https = RegExp(r'https=([^;]+)').firstMatch(value);
      final http = RegExp(r'http=([^;]+)').firstMatch(value);
      value = https?.group(1) ?? http?.group(1) ?? value;
      return value.replaceFirst(RegExp(r'^https?://'), '');
    } catch (_) {
      return null;
    }
  }
  static const _ua = 'BookIt/0.1 (open-source e-reader; https://github.com/MohammedAnasAsif/BookIt)';

  static Future<Uint8List> getBytes(String url, {Duration timeout = const Duration(seconds: 60)}) async {
    final r = await _client.get(Uri.parse(url), headers: {'User-Agent': _ua}).timeout(timeout);
    if (r.statusCode != 200) throw HttpException('HTTP ${r.statusCode} for $url');
    return r.bodyBytes;
  }

  static Future<String> getString(String url, {Duration timeout = const Duration(seconds: 30)}) async {
    final r = await _client.get(Uri.parse(url), headers: {'User-Agent': _ua}).timeout(timeout);
    if (r.statusCode != 200) throw HttpException('HTTP ${r.statusCode} for $url');
    return r.body;
  }

  /// Downloads [url] into [dest], resuming a previous partial download
  /// (`dest.part`) when possible. [onProgress] gets bytes received so far and
  /// the total size (or -1 when unknown).
  static Future<void> toFile(
    String url,
    File dest, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancel,
    int? expectedSize,
  }) async {
    final part = File('${dest.path}.part');
    await dest.parent.create(recursive: true);
    var existing = await part.exists() ? await part.length() : 0;
    if (expectedSize != null && existing > expectedSize) {
      await part.delete();
      existing = 0;
    }

    var attempt = 0;
    while (true) {
      attempt++;
      try {
        await _downloadOnce(url, part, existing, onProgress, cancel, expectedSize);
        break;
      } on DownloadCancelled {
        rethrow;
      } catch (e) {
        if (attempt >= 5) rethrow;
        await Future<void>.delayed(Duration(seconds: 2 * attempt));
        existing = await part.exists() ? await part.length() : 0;
      }
    }
    final size = await part.length();
    if (expectedSize != null && size != expectedSize) {
      throw HttpException('Download incomplete ($size of $expectedSize bytes)');
    }
    if (await dest.exists()) await dest.delete();
    await part.rename(dest.path);
  }

  static Future<void> _downloadOnce(
    String url,
    File part,
    int existing,
    void Function(int, int)? onProgress,
    CancelToken? cancel,
    int? expectedSize,
  ) async {
    final req = http.Request('GET', Uri.parse(url));
    req.headers['User-Agent'] = _ua;
    if (existing > 0) req.headers['Range'] = 'bytes=$existing-';
    final resp = await _client.send(req).timeout(const Duration(seconds: 60));
    if (resp.statusCode == 416 && expectedSize != null && existing == expectedSize) {
      onProgress?.call(existing, expectedSize);
      return;
    }
    if (resp.statusCode != 200 && resp.statusCode != 206) {
      throw HttpException('HTTP ${resp.statusCode} for $url');
    }
    final append = resp.statusCode == 206 && existing > 0;
    var received = append ? existing : 0;
    final total = resp.contentLength == null
        ? (expectedSize ?? -1)
        : (append ? existing + resp.contentLength! : resp.contentLength!);
    final sink = part.openWrite(mode: append ? FileMode.append : FileMode.write);
    var lastReport = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      await for (final chunk in resp.stream.timeout(const Duration(seconds: 60))) {
        if (cancel?.isCancelled ?? false) throw DownloadCancelled();
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now();
        if (now.difference(lastReport).inMilliseconds > 200) {
          lastReport = now;
          onProgress?.call(received, total);
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    onProgress?.call(received, total);
  }
}
