import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/app_paths.dart';
import '../core/keep_awake.dart';
import '../core/downloader.dart';
import '../data/library_store.dart';
import '../models/book.dart';
import 'engine/nllb_model.dart';
import 'translation_data.dart';
import 'translation_worker.dart';

/// A downloadable file of the translation model.
class ModelFile {
  final String name;
  final String url;
  final int size;
  const ModelFile(this.name, this.url, this.size);
}

/// The on-device translation model: Meta's NLLB-200 (distilled, 600M
/// parameters, 8-bit), exported to ONNX by the Hugging Face community.
/// It translates between 200 languages, including 20 Indian languages.
class ModelPack {
  static const id = 'nllb-200-distilled-600M';
  static const displayName = 'NLLB-200 translation model';
  static const license = 'CC-BY-NC 4.0 (free for non-commercial use)';
  static const _base = 'https://huggingface.co/Xenova/nllb-200-distilled-600M/resolve/main';
  static const files = [
    ModelFile('tokenizer.json', '$_base/tokenizer.json', 17331224),
    ModelFile(NllbModel.encoderFile, '$_base/onnx/${NllbModel.encoderFile}', 419120483),
    ModelFile(NllbModel.firstDecoderFile, '$_base/onnx/${NllbModel.firstDecoderFile}', 470533055),
    ModelFile(NllbModel.decoderFile, '$_base/onnx/${NllbModel.decoderFile}', 445006987),
  ];
  static int get totalBytes => files.fold(0, (n, f) => n + f.size);
  static Directory get dir => Directory('${AppPaths.models.path}/$id');
}

enum PackState { notInstalled, downloading, installed }

enum JobStatus { queued, starting, running, paused, done, error }

class JobProgress {
  final String bookId;
  final String lang;
  JobStatus status;
  int done = 0;
  int total = 0;
  int chapter = 0;
  double blocksPerMinute = 0;
  String message = '';

  JobProgress(this.bookId, this.lang, this.status);

  String get key => '$bookId|$lang';
  double get fraction => total == 0 ? 0 : (done / total).clamp(0, 1).toDouble();
  bool get active => status == JobStatus.queued || status == JobStatus.starting || status == JobStatus.running;

  Duration? get eta {
    if (blocksPerMinute <= 0.1 || total == 0) return null;
    return Duration(seconds: ((total - done) / blocksPerMinute * 60).round());
  }

  Map<String, dynamic> toJson() => {
        'bookId': bookId,
        'lang': lang,
        'status': status.name,
        if (status == JobStatus.error && message.isNotEmpty) 'message': message,
      };
}

class _Running {
  final JobProgress job;
  final Isolate isolate;
  final ReceivePort port;
  SendPort? commands;
  _Running(this.job, this.isolate, this.port);
}

/// Owns the translation model download and the queue of book translations.
/// Only one book is translated at a time (the model needs a lot of memory).
class TranslationService extends ChangeNotifier {
  final LibraryStore library;
  TranslationService(this.library);

  /// When true, sentences are translated one at a time (more accurate, slower).
  bool accurate = false;

  /// Called when a whole book has finished translating.
  void Function(JobProgress job)? onBookTranslated;

  PackState packState = PackState.notInstalled;
  int packReceived = 0;
  String? packError;
  CancelToken? _packCancel;

  final Map<String, JobProgress> _jobs = {};
  final List<String> _queue = [];
  _Running? _running;
  final Map<String, TranslationData> _live = {};
  Timer? _notifyTimer;

  Iterable<JobProgress> get jobs => _jobs.values;
  JobProgress? job(String bookId, String lang) => _jobs['$bookId|$lang'];
  JobProgress? activeJobFor(String bookId) {
    for (final j in _jobs.values) {
      if (j.bookId == bookId && j.active) return j;
    }
    return null;
  }

  double get packFraction => packReceived / ModelPack.totalBytes;

  Future<void> init() async {
    packState = await _packInstalled() ? PackState.installed : PackState.notInstalled;
    try {
      final f = AppPaths.jobs();
      if (await f.exists()) {
        for (final j in (jsonDecode(await f.readAsString()) as List)) {
          final m = j as Map<String, dynamic>;
          final status = JobStatus.values.asNameMap()[m['status']] ?? JobStatus.paused;
          final job = JobProgress(m['bookId'] as String, m['lang'] as String,
              status == JobStatus.done ? JobStatus.done : JobStatus.paused);
          if (status == JobStatus.error) {
            job.status = JobStatus.error;
            job.message = (m['message'] as String?) ?? '';
          }
          if (library.byId(job.bookId) == null) continue;
          _jobs[job.key] = job;
          await _refreshCounts(job);
          if (status == JobStatus.queued || status == JobStatus.running || status == JobStatus.starting) {
            job.status = JobStatus.queued;
            _queue.add(job.key);
          }
        }
      }
    } catch (_) {}
    notifyListeners();
    if (packState == PackState.installed) _pump();
  }

  Future<bool> _packInstalled() async {
    for (final f in ModelPack.files) {
      final file = File('${ModelPack.dir.path}/${f.name}');
      if (!await file.exists() || await file.length() != f.size) return false;
    }
    return true;
  }

  Future<void> _persistJobs() async {
    try {
      await AppPaths.jobs().writeAsString(jsonEncode([for (final j in _jobs.values) j.toJson()]));
    } catch (_) {}
  }

  // ------------------------------------------------------------ model pack

  Future<void> downloadPack() async {
    if (packState == PackState.downloading) return;
    packState = PackState.downloading;
    packError = null;
    packReceived = 0;
    _packCancel = CancelToken();
    notifyListeners();
    try {
      var before = 0;
      for (final f in ModelPack.files) {
        final dest = File('${ModelPack.dir.path}/${f.name}');
        if (await dest.exists() && await dest.length() == f.size) {
          before += f.size;
          packReceived = before;
          notifyListeners();
          continue;
        }
        final base = before;
        await Downloader.toFile(f.url, dest, expectedSize: f.size, cancel: _packCancel, onProgress: (r, _) {
          packReceived = base + r;
          notifyListeners();
        });
        before += f.size;
      }
      packState = PackState.installed;
      _pump();
    } on DownloadCancelled {
      packState = PackState.notInstalled;
    } catch (e) {
      packState = PackState.notInstalled;
      packError = 'Download failed: $e';
    }
    notifyListeners();
  }

  void cancelPackDownload() => _packCancel?.cancel();

  Future<void> deletePack() async {
    packState = PackState.notInstalled;
    _queue.clear();
    await _stopRunning();
    for (final j in _jobs.values) {
      if (j.active) j.status = JobStatus.paused;
    }
    if (await ModelPack.dir.exists()) await ModelPack.dir.delete(recursive: true);
    await _persistJobs();
    notifyListeners();
  }

  // ------------------------------------------------------------ jobs

  /// Starts (or resumes) translating [book] into [lang].
  Future<void> start(Book book, String lang, {int? fromChapter}) async {
    final key = '${book.id}|$lang';
    final job = _jobs.putIfAbsent(key, () => JobProgress(book.id, lang, JobStatus.queued));
    if (job.status == JobStatus.done) return;
    job.status = JobStatus.queued;
    job.chapter = fromChapter ?? book.position.chapter;
    job.message = '';
    await _refreshCounts(job);
    _queue.remove(key);
    _queue.insert(0, key);
    library.registerTranslation(book.id, lang);
    await _persistJobs();
    notifyListeners();
    // A new request for another book takes over from a running one.
    if (_running != null && _running!.job.key != key) {
      final previous = _running!.job;
      await _stopRunning();
      previous.status = JobStatus.queued;
      if (!_queue.contains(previous.key)) _queue.add(previous.key);
    }
    _pump();
  }

  Future<void> pause(String bookId, String lang) async {
    final key = '$bookId|$lang';
    _queue.remove(key);
    final job = _jobs[key];
    if (_running?.job.key == key) await _stopRunning();
    if (job != null && job.status != JobStatus.done) job.status = JobStatus.paused;
    await _persistJobs();
    notifyListeners();
    _pump();
  }

  Future<void> cancelAndDelete(Book book, String lang) async {
    await pause(book.id, lang);
    _jobs.remove('${book.id}|$lang');
    _live.remove('${book.id}|$lang');
    await library.deleteTranslation(book, lang);
    await _persistJobs();
    notifyListeners();
  }

  /// The reader opened chapter [chapter]; translate it next.
  void prioritize(String bookId, String lang, int chapter) {
    final r = _running;
    if (r != null && r.job.bookId == bookId && r.job.lang == lang) {
      r.commands?.send(['priority', chapter]);
    }
  }

  Future<void> _refreshCounts(JobProgress job) async {
    try {
      final content = await library.content(job.bookId);
      final data = await translation(job.bookId, job.lang);
      job.total = content.translatableBlockCount;
      job.done = data?.translatedCount(content) ?? 0;
      if (job.total > 0 && job.done >= job.total) job.status = JobStatus.done;
    } catch (_) {}
  }

  /// Current translation data (live while a job is running).
  Future<TranslationData?> translation(String bookId, String lang) async {
    final key = '$bookId|$lang';
    final live = _live[key];
    if (live != null) return live;
    final data = await library.readTranslation(bookId, lang);
    if (data != null) _live[key] = data;
    return data;
  }

  TranslationData? cachedTranslation(String bookId, String lang) => _live['$bookId|$lang'];

  void _pump() {
    if (_running != null || packState != PackState.installed) {
      _updateWakelock();
      return;
    }
    while (_queue.isNotEmpty) {
      final key = _queue.removeAt(0);
      final job = _jobs[key];
      if (job == null || job.status != JobStatus.queued) continue;
      _launch(job);
      break;
    }
    _updateWakelock();
  }

  void _updateWakelock() {
    KeepAwake.set('translation', _running != null);
  }

  Future<void> _launch(JobProgress job) async {
    final book = library.byId(job.bookId);
    if (book == null) return;
    job.status = JobStatus.starting;
    job.message = 'Starting…';
    notifyListeners();

    // Make sure the live copy has the right shape before the worker writes.
    final content = await library.content(job.bookId);
    final key = job.key;
    final existing = await translation(job.bookId, job.lang);
    final live = existing ?? TranslationData.emptyFor(content, job.lang, book.sourceLang, ModelPack.id);
    live.conformTo(content);
    _live[key] = live;
    if (existing == null) await live.write(AppPaths.translation(job.bookId, job.lang));

    final cores = Platform.numberOfProcessors;
    final mobile = Platform.isAndroid || Platform.isIOS;
    final threads = mobile ? math.max(2, math.min(4, cores - 2)) : math.max(2, math.min(8, cores - 1));
    final spec = TranslationJobSpec(
      bookId: job.bookId,
      contentPath: AppPaths.bookContent(job.bookId).path,
      translationPath: AppPaths.translation(job.bookId, job.lang).path,
      modelDir: ModelPack.dir.path,
      sourceLang: book.sourceLang,
      targetLang: job.lang,
      startChapter: job.chapter,
      threads: threads,
      batchSize: accurate ? 1 : (mobile ? 4 : 8),
      engineName: ModelPack.id,
    );

    final port = ReceivePort();
    final isolate = await Isolate.spawn(translationWorkerMain, [port.sendPort, spec.toMessage()],
        debugName: 'translation-$key');
    final running = _Running(job, isolate, port);
    _running = running;
    _updateWakelock();
    port.listen((msg) => _onWorkerMessage(running, msg as Map));
  }

  void _onWorkerMessage(_Running r, Map msg) {
    final job = r.job;
    switch (msg['type']) {
      case 'ready':
        r.commands = msg['commands'] as SendPort;
      case 'status':
        job.message = msg['message'] as String;
        if (job.message == 'Translating') job.status = JobStatus.running;
        _notifySoon();
      case 'block':
        final data = _live[job.key];
        final c = msg['c'] as int, b = msg['b'] as int;
        if (data != null && c < data.chapters.length && b < data.chapters[c].length) {
          data.chapters[c][b] = msg['t'] as String;
        }
        _notifySoon();
      case 'progress':
        job.done = msg['done'] as int;
        job.total = msg['total'] as int;
        if ((msg['chapter'] as int) >= 0) job.chapter = msg['chapter'] as int;
        job.blocksPerMinute = (msg['blocksPerMinute'] as num).toDouble();
        job.status = JobStatus.running;
        _notifySoon();
      case 'finished':
        job.status = (msg['complete'] as bool) ? JobStatus.done : JobStatus.paused;
        job.message = '';
        _finish(r);
        if (job.status == JobStatus.done) onBookTranslated?.call(job);
      case 'error':
        job.status = JobStatus.error;
        job.message = msg['message'] as String;
        debugPrint('Translation error: ${msg['message']}\n${msg['stack']}');
        _logError('${DateTime.now().toIso8601String()} ${job.bookId} ${job.lang}: ${msg['message']}\n${msg['stack']}\n');
        _finish(r);
    }
  }

  void _logError(String text) {
    try {
      File('${AppPaths.root.path}${Platform.pathSeparator}translation_errors.log')
          .writeAsStringSync(text, mode: FileMode.append);
    } catch (_) {}
  }

  void _finish(_Running r) {
    r.port.close();
    r.isolate.kill(priority: Isolate.beforeNextEvent);
    if (_running == r) _running = null;
    _persistJobs();
    notifyListeners();
    _pump();
  }

  Future<void> _stopRunning() async {
    final r = _running;
    if (r == null) return;
    final done = Completer<void>();
    // Ask nicely so the worker saves; force-stop after a timeout.
    r.commands?.send('stop');
    Timer(const Duration(seconds: 8), () {
      if (!done.isCompleted) done.complete();
    });
    final poll = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_running != r && !done.isCompleted) done.complete();
    });
    await done.future;
    poll.cancel();
    if (_running == r) {
      r.isolate.kill(priority: Isolate.immediate);
      r.port.close();
      _running = null;
    }
    // Reload what the worker saved so the live copy is consistent.
    final data = await library.readTranslation(r.job.bookId, r.job.lang);
    if (data != null) _live[r.job.key] = data;
    _updateWakelock();
  }

  void _notifySoon() {
    if (_notifyTimer?.isActive ?? false) return;
    _notifyTimer = Timer(const Duration(milliseconds: 400), notifyListeners);
  }
}
