import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/languages.dart';
import '../core/version.dart';
import '../data/engagement.dart';
import '../data/reading_stats.dart';
import '../data/settings_store.dart';
import '../translation/translation_service.dart';
import 'book_actions.dart';
import 'engagement_ui.dart';
import 'share_cards.dart';
import 'widgets/format.dart';
import 'widgets/language_picker.dart';
import 'widgets/model_download.dart';
import '../l10n/strings.dart';

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
    final stats = context.watch<ReadingStats>();
    final engagement = context.watch<Engagement>();

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
      appBar: AppBar(title: Text(tr('Settings'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          header(tr('Reading')),
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(tr('My reading language')),
            subtitle: Text(lang?.label ?? tr('Not chosen yet')),
            onTap: () async {
              final l = await pickLanguage(context, title: tr('Your reading language'), selected: settings.preferredLang);
              if (l != null) settings.update((s) => s.preferredLang = l.code);
            },
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(tr('Menu language')),
            subtitle: Text(settings.appLanguage == null
                ? '${tr('Same as device')} · ${kAppLanguages.firstWhere((l) => l.$1 == L10n.code).$2}'
                : kAppLanguages.firstWhere((l) => l.$1 == settings.appLanguage, orElse: () => kAppLanguages.first).$2),
            onTap: () async {
              final choice = await showDialog<String>(
                context: context,
                builder: (context) => SimpleDialog(
                  title: Text(tr('Menu language')),
                  children: [
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, ''),
                      child: Text(tr('Same as device')),
                    ),
                    for (final l in kAppLanguages)
                      SimpleDialogOption(onPressed: () => Navigator.pop(context, l.$1), child: Text(l.$2)),
                  ],
                ),
              );
              if (choice == null) return;
              settings.update((s) => s.appLanguage = choice.isEmpty ? null : choice);
            },
          ),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: Text(tr('Daily reading goal')),
            subtitle: Text(tr('{m} minutes a day', {'m': stats.goalMinutes})),
            trailing: DropdownButton<int>(
              value: stats.goalMinutes,
              underline: const SizedBox.shrink(),
              items: [for (final m in const [5, 10, 15, 20, 30, 45, 60]) DropdownMenuItem(value: m, child: Text('$m'))],
              onChanged: (m) {
                if (m != null) stats.setGoal(m);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: Text(tr('App theme')),
            trailing: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(value: ThemeMode.system, label: Text(tr('Auto'))),
                ButtonSegment(value: ThemeMode.light, label: Text(tr('Light'))),
                ButtonSegment(value: ThemeMode.dark, label: Text(tr('Dark'))),
              ],
              selected: {settings.appTheme},
              showSelectedIcon: false,
              onSelectionChanged: (v) => settings.update((s) => s.appTheme = v.first),
            ),
          ),
          header(tr('Translation')),
          ListTile(
            leading: const Icon(Icons.memory),
            title: Text(tr('Translation model')),
            subtitle: Text(packStatus),
            trailing: switch (service.packState) {
              PackState.installed => TextButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: Text(tr('Delete the translation model?')),
                        content: Text(
                            tr('Frees up space. Books you already translated stay readable. You can download the model again later.')),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
                          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Delete'))),
                        ],
                      ),
                    );
                    if (ok == true) await service.deletePack();
                  },
                  child: Text(tr('Delete')),
                ),
              PackState.downloading =>
                TextButton(onPressed: service.cancelPackDownload, child: Text(tr('Stop'))),
              PackState.notInstalled =>
                FilledButton.tonal(onPressed: () => ensureModelPack(context), child: Text(tr('Download'))),
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 20, 8),
            child: Text(tr(
                'BookIt translates on your device with NLLB-200 from Meta AI (200 languages, including 20 Indian languages). Nothing you read is sent anywhere.')),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.high_quality_outlined),
            title: Text(tr('Most accurate translation')),
            subtitle: Text(tr('Translates one sentence at a time. About 3× slower. Applies to the next book you start.')),
            value: settings.accurateTranslation,
            onChanged: (v) => settings.update((s) => s.accurateTranslation = v),
          ),
          for (final j in service.jobs.where((j) => j.active || j.status == JobStatus.paused))
            ListTile(
              leading: const Icon(Icons.pending_actions),
              title: Text('${languageByCode(j.lang)?.name ?? j.lang} · ${percent(j.fraction)}'),
              subtitle: Text(j.status.name),
            ),
          header(tr('Storage')),
          FutureBuilder<int>(
            future: _storage,
            builder: (_, s) => ListTile(
              leading: const Icon(Icons.storage),
              title: Text(tr('Space used by BookIt')),
              subtitle: Text(s.hasData ? formatBytes(s.data!) : 'Calculating…'),
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => setState(() => _storage = storageUsed()),
              ),
            ),
          ),
          header(tr('About')),
          ListTile(
            leading: const Icon(Icons.star_outline, color: Color(0xFFE39B2D)),
            title: Text(tr('Star BookIt on GitHub')),
            subtitle: Text(tr('Free apps grow when people star and share them. Thank you!')),
            onTap: () {
              engagement.markStarred();
              openLink(kRepoUrl);
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: Text(tr('Share BookIt with friends')),
            onTap: () => shareApp(context),
          ),
          ListTile(
            leading: const Icon(Icons.system_update_outlined),
            title: Text(tr('Version {v}', {'v': kAppVersion})),
            subtitle: Text(engagement.latestVersion != null
                ? tr('BookIt {v} is available', {'v': engagement.latestVersion!})
                : tr('Check for updates')),
            onTap: () async {
              if (engagement.latestVersion != null) return openLink(kReleasesUrl);
              await engagement.checkForUpdate(force: true);
              if (context.mounted && engagement.latestVersion == null) {
                showMessage(context, tr('You have the latest version.'));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: Text(tr('Report a problem or suggest an idea')),
            onTap: () => openLink(kIssuesUrl),
          ),
          ListTile(
            leading: const Icon(Icons.favorite_outline),
            title: Text(tr('BookIt is free and open source')),
            subtitle: Text(tr('Made so everyone can enjoy books in their own language. Contributions welcome.')),
            onTap: () => launchUrl(Uri.parse('https://github.com/MohammedAnasAsif/BookIt'),
                mode: LaunchMode.externalApplication),
          ),
          ListTile(
            leading: const Icon(Icons.local_library_outlined),
            title: Text(tr('Free books from Project Gutenberg')),
            subtitle: Text(tr('Public-domain e-books, made available by volunteers.')),
            onTap: () => launchUrl(Uri.parse('https://www.gutenberg.org'), mode: LaunchMode.externalApplication),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: Text(tr('Licences')),
            subtitle: const Text(
                'App: Apache 2.0 · Translation model: NLLB-200 by Meta AI, ${ModelPack.license}'),
            onTap: () => showLicensePage(context: context, applicationName: 'BookIt'),
          ),
        ],
      ),
    );
  }
}
