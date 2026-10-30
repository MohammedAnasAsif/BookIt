import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart' show SharePlus, ShareParams;

import '../core/app_paths.dart';
import '../data/reading_stats.dart';
import '../l10n/strings.dart';
import 'book_actions.dart';
import 'engagement_ui.dart';

const _ink = Color(0xFF1F2A44);
const _saffron = Color(0xFFE39B2D);
const _paper = Color(0xFFFBF8F2);
const kShareLine = 'Read free books in your own language with BookIt: https://github.com/MohammedAnasAsif/BookIt';

/// Card size in logical pixels; exported at 3x (1080×1350).
const _cardSize = Size(360, 450);

String _serif() => Platform.isWindows ? 'Georgia' : 'serif';

class _Brand extends StatelessWidget {
  final Color color;
  const _Brand({this.color = _ink});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Image.asset('assets/icon.png', width: 20, height: 20),
        ),
        const SizedBox(width: 6),
        Text('BookIt', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(tr('· free books in your language'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color.withValues(alpha: 0.6), fontSize: 10.5)),
        ),
      ]);
}

/// A passage from a book, ready to post.
class QuoteCard extends StatelessWidget {
  final String text;
  final String? original;
  final String title;
  final String author;
  final String? languageName;

  const QuoteCard({
    super.key,
    required this.text,
    required this.title,
    required this.author,
    this.original,
    this.languageName,
  });

  static String _clip(String s, int max) => s.length <= max ? s : '${s.substring(0, max).trimRight()}…';

  @override
  Widget build(BuildContext context) {
    final quote = _clip(text.trim(), original != null ? 300 : 480);
    final orig = original == null ? null : _clip(original!.trim(), 180);
    return SizedBox.fromSize(
      size: _cardSize,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: _paper),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 36, height: 4, color: _saffron),
            const SizedBox(height: 6),
            Text('“', style: TextStyle(fontSize: 64, height: 1, color: _saffron.withValues(alpha: 0.9), fontFamily: _serif())),
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                // Shrink the text until the passage (and its original) fit.
                final width = c.maxWidth;
                double heightAt(double size) {
                  final main = TextPainter(
                    text: TextSpan(text: quote, style: TextStyle(fontSize: size, height: 1.45, fontFamily: _serif())),
                    textDirection: TextDirection.ltr,
                  )..layout(maxWidth: width);
                  var h = main.height;
                  main.dispose();
                  if (orig != null) {
                    final o = TextPainter(
                      text: TextSpan(text: orig, style: TextStyle(fontSize: (size * 0.6).clamp(10.5, 14.0), height: 1.4, fontStyle: FontStyle.italic)),
                      textDirection: TextDirection.ltr,
                    )..layout(maxWidth: width);
                    h += 10 + o.height;
                    o.dispose();
                  }
                  return h;
                }

                var size = 26.0;
                while (size > 11 && heightAt(size) > c.maxHeight) {
                  size -= 1;
                }
                return ClipRect(
                    child: OverflowBox(
                  alignment: Alignment.topLeft,
                  maxHeight: double.infinity,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(quote, style: TextStyle(fontSize: size, height: 1.45, color: _ink, fontFamily: _serif())),
                  if (orig != null) ...[
                    const SizedBox(height: 10),
                    Text(orig,
                        style: TextStyle(
                            fontSize: (size * 0.6).clamp(10.5, 14.0),
                            height: 1.4,
                            color: _ink.withValues(alpha: 0.55),
                            fontStyle: FontStyle.italic)),
                  ],
                ]),
                ));
              }),
            ),
            const SizedBox(height: 12),
            Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, color: _ink, fontSize: 14)),
            if (author.isNotEmpty)
              Text(author, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _ink.withValues(alpha: 0.7), fontSize: 12.5)),
            if (languageName != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(languageName!, style: const TextStyle(color: _saffron, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 14),
            const _Brand(),
          ]),
        ),
      ),
    );
  }
}

/// Reading streak and the last seven days.
class StatsCard extends StatelessWidget {
  final ReadingStats stats;
  const StatsCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final week = stats.lastWeek;
    final maxM = week.fold<int>(stats.goalMinutes, (a, b) => b > a ? b : a).clamp(1, 100000);
    final today = DateTime.now();
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return SizedBox.fromSize(
      size: _cardSize,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_ink, Color(0xFF2E3B5E)]),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('My reading week'), style: const TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${stats.streak}',
                  style: TextStyle(color: Colors.white, fontSize: 64, height: 1, fontWeight: FontWeight.w700, fontFamily: _serif())),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(tr('day streak'), style: const TextStyle(color: _saffron, fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              const Spacer(),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Icon(Icons.local_fire_department, color: _saffron, size: 40),
              ),
            ]),
            const SizedBox(height: 18),
            Text(tr('{n} minutes read this week', {'n': stats.minutesThisWeek}),
                style: const TextStyle(color: Colors.white, fontSize: 15)),
            const SizedBox(height: 14),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Text(week[i] > 0 ? '${week[i]}' : '', style: const TextStyle(color: Colors.white70, fontSize: 10)),
                        const SizedBox(height: 3),
                        LayoutBuilder(builder: (context, c) {
                          final h = (c.maxHeight.isFinite ? c.maxHeight : 120.0);
                          return Container(
                            height: (week[i] / maxM * 120).clamp(4.0, h),
                            decoration: BoxDecoration(
                              color: week[i] >= stats.goalMinutes ? _saffron : Colors.white.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        }),
                        const SizedBox(height: 4),
                        Text(days[DateTime(today.year, today.month, today.day - 6 + i).weekday - 1],
                            style: const TextStyle(color: Colors.white60, fontSize: 11)),
                      ]),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 14),
            Text(tr('{n} books finished · {p} pages', {'n': stats.finishedBooks.length, 'p': stats.pagesTurned}),
                style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
            const SizedBox(height: 12),
            const _Brand(color: Colors.white),
          ]),
        ),
      ),
    );
  }
}

/// Shows [card] in a preview dialog with a Share/Save button that exports it
/// as a PNG image.
Future<void> showShareCard(BuildContext context, Widget card, {required String fileName, String? text}) {
  final key = GlobalKey();
  return showDialog(
    context: context,
    builder: (context) {
      var busy = false;
      return StatefulBuilder(builder: (context, setState) {
        final mobile = Platform.isAndroid || Platform.isIOS;
        return AlertDialog(
          contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          content: FittedBox(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: RepaintBoundary(key: key, child: card),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Close'))),
            FilledButton.icon(
              icon: Icon(mobile ? Icons.share : Icons.download),
              label: Text(mobile ? tr('Share') : tr('Save image')),
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      try {
                        final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
                        final image = await boundary.toImage(pixelRatio: 3);
                        final data = await image.toByteData(format: ui.ImageByteFormat.png);
                        final bytes = data!.buffer.asUint8List();
                        if (!context.mounted) return;
                        await shareImage(context, fileName, bytes, text: text);
                      } catch (e) {
                        if (context.mounted) showMessage(context, '${tr('Could not create the image')}: $e');
                      } finally {
                        if (context.mounted) setState(() => busy = false);
                      }
                    },
            ),
          ],
        );
      });
    },
  );
}

Future<void> shareImage(BuildContext context, String name, List<int> bytes, {String? text}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final dir = Directory(p.join(AppPaths.cache.path, 'share'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'image/png')], text: text ?? kShareLine));
    return;
  }
  final location = await getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: [XTypeGroup(label: tr('PNG image'), extensions: ['png'])],
  );
  if (location == null) return;
  await File(location.path).writeAsBytes(bytes, flush: true);
  if (context.mounted) showMessage(context, '${tr('Saved')} ${p.basename(location.path)}');
}

/// Shares a link to BookIt (text only).
Future<void> shareApp(BuildContext context) async {
  if (Platform.isAndroid || Platform.isIOS) {
    await SharePlus.instance.share(ShareParams(text: kShareLine));
  } else {
    await openLink('https://github.com/MohammedAnasAsif/BookIt');
  }
}
