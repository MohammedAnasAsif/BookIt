import 'package:flutter/material.dart';

import '../../core/languages.dart';

/// Bottom sheet listing every language, Indian languages first, searchable by
/// English or native name. Returns the chosen [Language].
Future<Language?> pickLanguage(
  BuildContext context, {
  String title = 'Read in which language?',
  String? exclude,
  String? selected,
}) {
  return showModalBottomSheet<Language>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _LanguageSheet(title: title, exclude: exclude, selected: selected),
  );
}

class _LanguageSheet extends StatefulWidget {
  final String title;
  final String? exclude;
  final String? selected;
  const _LanguageSheet({required this.title, this.exclude, this.selected});

  @override
  State<_LanguageSheet> createState() => _LanguageSheetState();
}

class _LanguageSheetState extends State<_LanguageSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final langs = kLanguages
        .where((l) => l.code != widget.exclude)
        .where((l) => q.isEmpty || l.name.toLowerCase().contains(q) || l.nativeName.toLowerCase().contains(q))
        .toList();
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(widget.title, style: theme.textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: false,
              decoration: InputDecoration(
                hintText: 'Search languages',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              controller: controller,
              children: [
                for (final group in LanguageGroup.values) ...[
                  if (langs.any((l) => l.group == group))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                      child: Text(group.label.toUpperCase(),
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: theme.colorScheme.primary, letterSpacing: 1.1)),
                    ),
                  for (final l in langs.where((l) => l.group == group))
                    ListTile(
                      title: Text(l.nativeName, style: const TextStyle(fontSize: 18)),
                      subtitle: l.nativeName == l.name ? null : Text(l.name),
                      trailing: l.code == widget.selected ? Icon(Icons.check, color: theme.colorScheme.primary) : null,
                      onTap: () => Navigator.pop(context, l),
                    ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
