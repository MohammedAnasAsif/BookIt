import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/version.dart';
import '../data/engagement.dart';
import '../data/reading_stats.dart';
import '../l10n/strings.dart';
import 'share_cards.dart';

Future<void> openLink(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

/// "You finished the book!" with the reader's stats and a share button.
Future<void> showFinishedDialog(BuildContext context, String title, ReadingStats stats) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.celebration, size: 36),
      title: Text(tr('You finished the book!')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Text(tr('{n} books finished · {d}-day streak',
            {'n': stats.finishedBooks.length, 'd': stats.streak})),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Close'))),
        FilledButton.icon(
          icon: const Icon(Icons.share, size: 18),
          label: Text(tr('Share my reading')),
          onPressed: () {
            Navigator.pop(context);
            showShareCard(context, StatsCard(stats: stats), fileName: 'bookit-reading.png');
          },
        ),
      ],
    ),
  );
}

/// A gentle, rare request to star the project on GitHub.
Future<void> showStarPrompt(BuildContext context) {
  final engagement = context.read<Engagement>();
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.star_rounded, size: 40, color: Color(0xFFE39B2D)),
      title: Text(tr('Enjoying BookIt?')),
      content: Text(tr(
          'BookIt is free and made by volunteers. A star on GitHub helps more readers find it. It takes a few seconds.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Maybe later'))),
        FilledButton.icon(
          icon: const Icon(Icons.star_outline, size: 18),
          label: Text(tr('Star on GitHub')),
          onPressed: () {
            engagement.markStarred();
            Navigator.pop(context);
            openLink(kRepoUrl);
          },
        ),
      ],
    ),
  );
}

Future<void> showNoVoiceDialog(BuildContext context, String languageName) {
  final how = Platform.isWindows
      ? tr('On Windows: Settings › Time & language › Speech › Add voices.')
      : tr('On Android: Settings › System › Languages › Text-to-speech output, then install voice data for your language.');
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.record_voice_over_outlined),
      title: Text(tr('No {lang} voice on this device', {'lang': languageName})),
      content: Text('${tr('BookIt reads aloud with the voices installed on your device. You can add one for free:')}\n\n$how'),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('OK')))],
    ),
  );
}

/// Shown on Home when a newer version is out.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final e = context.watch<Engagement>();
    if (!e.showUpdate) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(children: [
            Icon(Icons.system_update, color: scheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(tr('BookIt {v} is available', {'v': e.latestVersion ?? ''}),
                  style: TextStyle(color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600)),
            ),
            TextButton(onPressed: () => openLink(kReleasesUrl), child: Text(tr('Download'))),
            IconButton(
              tooltip: tr('Close'),
              icon: const Icon(Icons.close, size: 18),
              onPressed: e.dismissUpdate,
            ),
          ]),
        ),
      ),
    );
  }
}

/// Streak, today's progress towards the daily goal, and the last 7 days.
class StreakCard extends StatelessWidget {
  const StreakCard({super.key});

  @override
  Widget build(BuildContext context) {
    final stats = context.watch<ReadingStats>();
    if (!stats.hasAnyReading) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = stats.minutesToday;
    final goal = stats.goalMinutes;
    final week = stats.lastWeek;
    final maxM = week.fold<int>(goal, (a, b) => b > a ? b : a).clamp(1, 100000);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => showShareCard(context, StatsCard(stats: stats), fileName: 'bookit-reading.png'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.local_fire_department, color: Color(0xFFE39B2D)),
                  const SizedBox(width: 4),
                  Text('${stats.streak}', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                ]),
                Text(tr('day streak'), style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                Text(tr('{m} of {g} min today', {'m': today, 'g': goal}), style: theme.textTheme.bodyMedium),
                const SizedBox(height: 6),
                SizedBox(
                  width: 120,
                  child: LinearProgressIndicator(
                    value: (today / goal).clamp(0, 1).toDouble(),
                    borderRadius: BorderRadius.circular(4),
                    minHeight: 6,
                    color: const Color(0xFFE39B2D),
                  ),
                ),
              ]),
              const SizedBox(width: 20),
              Expanded(
                child: SizedBox(
                  height: 70,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Container(
                            height: (week[i] / maxM * 64).clamp(3.0, 64.0),
                            decoration: BoxDecoration(
                              color: week[i] >= goal ? const Color(0xFFE39B2D) : scheme.primary.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: tr('Share my reading'),
                icon: const Icon(Icons.ios_share),
                onPressed: () => showShareCard(context, StatsCard(stats: stats), fileName: 'bookit-reading.png'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
