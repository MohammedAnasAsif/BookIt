import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/languages.dart';
import '../../data/library_store.dart';
import '../../data/settings_store.dart';
import '../../models/book.dart';
import '../../translation/translation_service.dart';
import '../widgets/format.dart';

const kOriginal = '__original__';
const kTranslateNew = '__translate__';

/// Text size, spacing, font and colour theme.
Future<void> showReaderSettings(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) {
      final s = context.watch<SettingsStore>();
      final theme = Theme.of(context);
      Widget row(String label, Widget child) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(children: [
              SizedBox(width: 96, child: Text(label, style: theme.textTheme.bodyMedium)),
              Expanded(child: child),
            ]),
          );
      return SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          row(
            'Text size',
            Row(children: [
              IconButton.filledTonal(
                icon: const Text('A', style: TextStyle(fontSize: 14)),
                onPressed: s.fontSize > 12 ? () => s.update((x) => x.fontSize -= 1) : null,
              ),
              Expanded(child: Center(child: Text(s.fontSize.toStringAsFixed(0)))),
              IconButton.filledTonal(
                icon: const Text('A', style: TextStyle(fontSize: 22)),
                onPressed: s.fontSize < 40 ? () => s.update((x) => x.fontSize += 1) : null,
              ),
            ]),
          ),
          row(
            'Font',
            SegmentedButton<ReaderFont>(
              segments: const [
                ButtonSegment(value: ReaderFont.serif, label: Text('Serif', style: TextStyle(fontFamily: 'serif'))),
                ButtonSegment(value: ReaderFont.sans, label: Text('Sans')),
              ],
              selected: {s.font},
              showSelectedIcon: false,
              onSelectionChanged: (v) => s.update((x) => x.font = v.first),
            ),
          ),
          row(
            'Spacing',
            SegmentedButton<double>(
              segments: const [
                ButtonSegment(value: 1.3, icon: Icon(Icons.density_small)),
                ButtonSegment(value: 1.55, icon: Icon(Icons.density_medium)),
                ButtonSegment(value: 1.85, icon: Icon(Icons.density_large)),
              ],
              selected: {
                [1.3, 1.55, 1.85].reduce((a, b) => (a - s.lineHeight).abs() < (b - s.lineHeight).abs() ? a : b)
              },
              showSelectedIcon: false,
              onSelectionChanged: (v) => s.update((x) => x.lineHeight = v.first),
            ),
          ),
          row(
            'Margins',
            SegmentedButton<double>(
              segments: const [
                ButtonSegment(value: 12, label: Text('Narrow')),
                ButtonSegment(value: 24, label: Text('Normal')),
                ButtonSegment(value: 44, label: Text('Wide')),
              ],
              selected: {
                [12.0, 24.0, 44.0].reduce((a, b) => (a - s.margin).abs() < (b - s.margin).abs() ? a : b)
              },
              showSelectedIcon: false,
              onSelectionChanged: (v) => s.update((x) => x.margin = v.first),
            ),
          ),
          row(
            'Alignment',
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, icon: Icon(Icons.format_align_justify)),
                ButtonSegment(value: false, icon: Icon(Icons.format_align_left)),
              ],
              selected: {s.justify},
              showSelectedIcon: false,
              onSelectionChanged: (v) => s.update((x) => x.justify = v.first),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final t in ReaderTheme.values)
                  GestureDetector(
                    onTap: () => s.update((x) => x.readerTheme = t),
                    child: Column(children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: t.background,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: s.readerTheme == t ? theme.colorScheme.primary : theme.dividerColor,
                            width: s.readerTheme == t ? 3 : 1,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text('Aa', style: TextStyle(color: t.text, fontFamily: 'serif', fontSize: 16)),
                      ),
                      const SizedBox(height: 4),
                      Text(t.label, style: theme.textTheme.labelSmall),
                    ]),
                  ),
              ],
            ),
          ),
        ]),
      );
    },
  );
}

/// Choose between the original and the available translations.
/// Returns [kOriginal], a language code, or [kTranslateNew].
Future<String?> showEditionPicker(BuildContext context, Book book, String? current) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) {
      final library = context.watch<LibraryStore>();
      final service = context.watch<TranslationService>();
      final langs = library.translationLangs(book.id).toList()..sort();
      final source = languageByCode(book.sourceLang);
      return ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 24), children: [
        ListTile(
          leading: const Icon(Icons.menu_book),
          title: Text('Original${source != null ? ' · ${source.nativeName}' : ''}'),
          trailing: current == null ? const Icon(Icons.check) : null,
          onTap: () => Navigator.pop(context, kOriginal),
        ),
        for (final l in langs)
          Builder(builder: (context) {
            final lang = languageByCode(l);
            final job = service.job(book.id, l);
            final sub = job == null
                ? null
                : job.status == JobStatus.done
                    ? 'Fully translated'
                    : '${percent(job.fraction)} translated${job.active ? ' · in progress' : ''}';
            return ListTile(
              leading: const Icon(Icons.translate),
              title: Text(lang?.label ?? l),
              subtitle: sub == null ? null : Text(sub),
              trailing: current == l ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, l),
            );
          }),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('Translate into another language…'),
          onTap: () => Navigator.pop(context, kTranslateNew),
        ),
      ]);
    },
  );
}

/// Table of contents and bookmarks. Returns where to go.
Future<ReadingPosition?> showContentsSheet(
  BuildContext context, {
  required List<String> chapters,
  required int current,
  required List<Bookmark> bookmarks,
  required bool Function(int chapter) chapterDone,
}) {
  return showModalBottomSheet<ReadingPosition>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, controller) => DefaultTabController(
        length: 2,
        child: Column(children: [
          const TabBar(tabs: [Tab(text: 'Contents'), Tab(text: 'Bookmarks')]),
          Expanded(
            child: TabBarView(children: [
              ListView.builder(
                controller: controller,
                itemCount: chapters.length,
                itemBuilder: (context, i) => ListTile(
                  selected: i == current,
                  title: Text(chapters[i], maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: chapterDone(i) ? null : const Icon(Icons.hourglass_empty, size: 16),
                  onTap: () => Navigator.pop(context, ReadingPosition(i, 0, 0)),
                ),
              ),
              bookmarks.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('No bookmarks yet. Tap the bookmark icon while reading to add one.',
                            textAlign: TextAlign.center),
                      ),
                    )
                  : ListView(controller: controller, children: [
                      for (final b in bookmarks)
                        ListTile(
                          leading: const Icon(Icons.bookmark),
                          title: Text(
                            b.position.chapter < chapters.length ? chapters[b.position.chapter] : 'Bookmark',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(b.snippet, maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: Text(percent(b.position.progress)),
                          onTap: () => Navigator.pop(context, b.position),
                        ),
                    ]),
            ]),
          ),
        ]),
      ),
    ),
  );
}
