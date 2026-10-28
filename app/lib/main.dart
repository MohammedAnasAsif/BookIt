import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/app_paths.dart';
import 'data/library_store.dart';
import 'data/settings_store.dart';
import 'demo.dart';
import 'translation/translation_service.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPaths.init();
  final settings = SettingsStore();
  await settings.load();
  final library = LibraryStore();
  await library.load();
  final translations = TranslationService(library)..accurate = settings.accurateTranslation;
  settings.addListener(() => translations.accurate = settings.accurateTranslation);
  await translations.init();
  final demo = parseDemo(args);
  if (demo != null) await seedDemo(demo, library, settings);

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: library),
      ChangeNotifierProvider.value(value: translations),
    ],
    child: BookItApp(demo: demo),
  ));
}
