import 'dart:convert';

import 'core/app_paths.dart';
import 'data/library_store.dart';
import 'data/settings_store.dart';
import 'models/book.dart';
import 'models/book_content.dart';

/// Screens that can be opened directly with `--demo=<name>` (used by CI to
/// take screenshots of the built app).
enum DemoScreen { home, library, store, settings, reader, readerDark, readerMenu, languages }

DemoScreen? parseDemo(List<String> args) {
  for (final a in args) {
    if (a.startsWith('--demo=')) {
      final name = a.substring(7).replaceAll('-', '').toLowerCase();
      for (final d in DemoScreen.values) {
        if (d.name.toLowerCase() == name) return d;
      }
    }
  }
  return null;
}

const demoBookId = 'demo-lamplighter';

/// A short original story bundled for demos and first-run screenshots.
BookContent demoContent() {
  const ch1 = [
    'The lamplighter of Temple Street was the last person in the town who still believed the evening '
        'needed help to arrive. Every day at dusk he walked the length of the street with his ladder on '
        'his shoulder, and every day his daughter Meena walked one step behind him, counting the lamps.',
    'There were thirty-two of them. Meena knew each one by its crack or its crooked post, the way other '
        'children knew the dogs of the neighbourhood. The lamp outside the sweet shop always flickered '
        'twice before it caught. The lamp by the old well leaned towards the water as if it were thirsty.',
    '“Why do we light them,” she asked one evening, “when the moon is already so bright?”',
    'Her father set the ladder against the thirtieth post and climbed it slowly. “The moon is for '
        'everyone,” he said. “These are for the people who are still walking home.”',
    'She thought about that for a long time. After that evening she no longer counted the lamps. '
        'She counted the people instead: the tailor with his bundle of cloth, the boy who sold newspapers, '
        'the tired nurse from the hospital who always smiled at them.',
    'When the last lamp was lit, the two of them stood at the end of the street and looked back. The '
        'light ran all the way to the temple gate like a river that had decided to stay.',
  ];
  const ch2 = [
    'Years later, the town council decided that the lamps would light themselves. Men came with wires '
        'and small grey boxes, and one evening the whole street glowed at once, without a single ladder.',
    'Meena, who was grown now and worked in the library, walked home that night slowly. She passed the '
        'sweet shop, where the new lamp did not flicker, and the old well, where the new lamp stood straight.',
    'At the end of the street she found her father sitting on the low wall, his ladder beside him, '
        'watching the light with an expression she could not read.',
    '“They do not need us any more,” he said.',
    '“The people walking home still need someone to notice them,” Meena said, and she sat down next to '
        'him. Together they counted the tailor, the newspaper boy, and a nurse who was very tired but '
        'smiled anyway.',
    'The lamps burned all night. Neither of them was in a hurry to leave.',
  ];
  return BookContent(
    title: "The Lamplighter's Daughter",
    author: 'BookIt sample story',
    language: 'en',
    chapters: [
      Chapter('1. Thirty-Two Lamps', [
        const Block(BlockKind.heading1, '1. Thirty-Two Lamps'),
        for (final t in ch1) Block(BlockKind.paragraph, t),
      ]),
      Chapter('2. The Grey Boxes', [
        const Block(BlockKind.heading1, '2. The Grey Boxes'),
        for (final t in ch2) Block(BlockKind.paragraph, t),
        const Block(BlockKind.separator, '', noTranslate: true),
        const Block(BlockKind.quote, 'This short story was written for BookIt and may be shared freely.'),
      ]),
    ],
  );
}

/// Adds the sample story to the library (once) and prepares settings for a demo.
Future<void> seedDemo(DemoScreen demo, LibraryStore library, SettingsStore settings) async {
  if (library.byId(demoBookId) == null) {
    final dir = AppPaths.bookDir(demoBookId);
    await dir.create(recursive: true);
    await AppPaths.bookContent(demoBookId).writeAsString(jsonEncode(demoContent().toJson()));
    final book = Book(
      id: demoBookId,
      title: "The Lamplighter's Daughter",
      author: 'BookIt sample story',
      source: 'import',
      sourceLang: 'eng_Latn',
      lastOpenedAt: DateTime.now(),
      position: const ReadingPosition(0, 0, 0, 0.12),
    );
    await library.save(book);
    await library.load();
  }
  settings.preferredLang ??= 'tam_Taml';
  if (demo == DemoScreen.readerDark) settings.readerTheme = ReaderTheme.dark;
  if (demo == DemoScreen.reader || demo == DemoScreen.readerMenu) settings.readerTheme = ReaderTheme.sepia;
}
