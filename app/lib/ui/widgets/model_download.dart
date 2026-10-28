import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../translation/translation_service.dart';
import 'format.dart';

/// Makes sure the translation model is on the device. Shows an explanation
/// and the download progress. Returns true when the model is ready.
Future<bool> ensureModelPack(BuildContext context) async {
  final service = context.read<TranslationService>();
  if (service.packState == PackState.installed) return true;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _ModelDialog(),
  );
  return ok == true && service.packState == PackState.installed;
}

class _ModelDialog extends StatefulWidget {
  const _ModelDialog();

  @override
  State<_ModelDialog> createState() => _ModelDialogState();
}

class _ModelDialogState extends State<_ModelDialog> {
  bool _closing = false;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<TranslationService>();
    final theme = Theme.of(context);
    if (s.packState == PackState.installed && !_closing) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
    }
    final downloading = s.packState == PackState.downloading;
    return AlertDialog(
      icon: const Icon(Icons.translate, size: 36),
      title: const Text('One-time download'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'To translate books on your device, BookIt needs its translation model '
            '(${formatBytes(ModelPack.totalBytes)}). You download it only once — after that, '
            'translating and reading work without internet, for free.',
          ),
          const SizedBox(height: 12),
          Text('Use Wi-Fi if you can. You can keep using the app while it downloads.',
              style: theme.textTheme.bodySmall),
          if (downloading) ...[
            const SizedBox(height: 20),
            LinearProgressIndicator(value: s.packFraction),
            const SizedBox(height: 8),
            Text('${formatBytes(s.packReceived)} of ${formatBytes(ModelPack.totalBytes)}',
                style: theme.textTheme.bodySmall),
          ],
          if (s.packError != null) ...[
            const SizedBox(height: 12),
            Text(s.packError!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
      actions: [
        if (downloading) ...[
          TextButton(
            onPressed: () {
              s.cancelPackDownload();
            },
            child: const Text('Stop'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continue in background'),
          ),
        ] else ...[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
          FilledButton(
            onPressed: () => s.downloadPack(),
            child: Text(s.packError != null ? 'Try again' : 'Download'),
          ),
        ],
      ],
    );
  }
}
