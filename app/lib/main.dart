import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/app_paths.dart';
import 'data/engagement.dart';
import 'data/library_store.dart';
import 'data/reading_stats.dart';
import 'l10n/strings.dart';
import 'data/settings_store.dart';
import 'demo.dart';
import 'translation/translation_service.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPaths.init();
  final settings = SettingsStore();
  await settings.load();
  for (final a in args) {
    if (a.startsWith('--ui=')) settings.appLanguage = a.substring(5); // screenshots
  }
  L10n.use(settings.appLanguage);
  final stats = ReadingStats();
  await stats.load();
  final engagement = Engagement();
  await engagement.load();
  final library = LibraryStore();
  await library.load();
  final translations = TranslationService(library)..accurate = settings.accurateTranslation;
  settings.addListener(() => translations.accurate = settings.accurateTranslation);
  translations.onBookTranslated = (_) => engagement.celebrateLater();
  await translations.init();
  final demo = parseDemo(args);
  if (demo != null) await seedDemo(demo, library, settings, stats);

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: library),
      ChangeNotifierProvider.value(value: translations),
      ChangeNotifierProvider.value(value: stats),
      ChangeNotifierProvider.value(value: engagement),
    ],
    child: BookItApp(demo: demo),
  ));
}
