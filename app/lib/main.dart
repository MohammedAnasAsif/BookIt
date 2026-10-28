import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/app_paths.dart';
import 'data/library_store.dart';
import 'data/settings_store.dart';
import 'translation/translation_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPaths.init();
  final settings = SettingsStore();
  await settings.load();
  final library = LibraryStore();
  await library.load();
  final translations = TranslationService(library);
  await translations.init();

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: library),
      ChangeNotifierProvider.value(value: translations),
    ],
    child: const BookItApp(),
  ));
}
