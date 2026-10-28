import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/languages.dart';
import '../data/settings_store.dart';
import '../translation/translation_service.dart';
import 'book_actions.dart';
import 'widgets/format.dart';
import 'widgets/language_picker.dart';
import 'widgets/model_download.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<int>? _storage;

  @override
  void initState() {
    super.initState();
    _storage = storageUsed();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final service = context.watch<TranslationService>();
    final theme = Theme.of(context);
    final lang = languageByCode(settings.preferredLang);

    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
          child: Text(t.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary, letterSpacing: 1.1)),
        );

    final packStatus = switch (service.packState) {
      PackState.installed => 'Installed · ${formatBytes(ModelPack.totalBytes)} · works offline',
      PackState.downloading =>
        'Downloading ${percent(service.packFraction)} (${formatBytes(service.packReceived)} of ${formatBytes(ModelPack.totalBytes)})',
      PackState.notInstalled => 'Not downloaded (${formatBytes(ModelPack.totalBytes)})',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          header('Reading'),
          ListTile(
            leading: const Icon(Icons.translate),
            title: const Text('My reading language'),
            subtitle: Text(lang?.label ?? 'Not chosen yet'),
            onTap: () async {
              final l = await pickLanguage(context, title: 'Your reading language', selected: settings.preferredLang);
              if (l != null) settings.update((s) => s.preferredLang = l.code);
            },
          ),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('App theme'),
            trailing: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
              ],
              selected: {settings.appTheme},
              showSelectedIcon: false,
              onSelectionChanged: (v) => settings.update((s) => s.appTheme = v.first),
            ),
          ),
          header('Translation'),
          ListTile(
            leading: const Icon(Icons.memory),
            title: const Text('Translation model'),
            subtitle: Text(packStatus),
            trailing: switch (service.packState) {
              PackState.installed => TextButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Delete the translation model?'),
                        content: const Text(
                            'Frees up space. Books you already translated stay readable. You can download the model again later.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (ok == true) await service.deletePack();
                  },
                  child: const Text('Delete'),
                ),
              PackState.downloading =>
                TextButton(onPressed: service.cancelPackDownload, child: const Text('Stop')),
              PackState.notInstalled =>
                FilledButton.tonal(onPressed: () => ensureModelPack(context), child: const Text('Download')),
            },
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(72, 0, 20, 8),
            child: Text(
              'BookIt translates on your device with NLLB-200 from Meta AI (200 languages, including 20 Indian '
              'languages). Nothing you read is sent anywhere.',
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.high_quality_outlined),
            title: const Text('Most accurate translation'),
            subtitle: const Text('Translates one sentence at a time. About 3× slower. Applies to the next book you start.'),
            value: settings.accurateTranslation,
            onChanged: (v) => settings.update((s) => s.accurateTranslation = v),
          ),
          for (final j in service.jobs.where((j) => j.active || j.status == JobStatus.paused))
            ListTile(
              leading: const Icon(Icons.pending_actions),
              title: Text('${languageByCode(j.lang)?.name ?? j.lang} · ${percent(j.fraction)}'),
              subtitle: Text(j.status.name),
            ),
          header('Storage'),
          FutureBuilder<int>(
            future: _storage,
            builder: (_, s) => ListTile(
              leading: const Icon(Icons.storage),
              title: const Text('Space used by BookIt'),
              subtitle: Text(s.hasData ? formatBytes(s.data!) : 'Calculating…'),
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => setState(() => _storage = storageUsed()),
              ),
            ),
          ),
          header('About'),
          ListTile(
            leading: const Icon(Icons.favorite_outline),
            title: const Text('BookIt is free and open source'),
            subtitle: const Text('Made so everyone can enjoy books in their own language. Contributions welcome.'),
            onTap: () => launchUrl(Uri.parse('https://github.com/MohammedAnasAsif/BookIt'),
                mode: LaunchMode.externalApplication),
          ),
          ListTile(
            leading: const Icon(Icons.local_library_outlined),
            title: const Text('Free books from Project Gutenberg'),
            subtitle: const Text('Public-domain e-books, made available by volunteers.'),
            onTap: () => launchUrl(Uri.parse('https://www.gutenberg.org'), mode: LaunchMode.externalApplication),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Licences'),
            subtitle: const Text(
                'App: Apache 2.0 · Translation model: NLLB-200 by Meta AI, ${ModelPack.license}'),
            onTap: () => showLicensePage(context: context, applicationName: 'BookIt'),
          ),
        ],
      ),
    );
  }
}
