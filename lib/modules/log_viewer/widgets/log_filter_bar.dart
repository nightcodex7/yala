// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import '../models/log_entry.dart';

class LogFilterBar extends StatelessWidget {
  final String filterText;
  final LogLevel? selectedLevel;
  final int linesToFetch;
  final ValueChanged<String> onFilterChanged;
  final ValueChanged<LogLevel?> onLevelChanged;
  final ValueChanged<int> onLinesChanged;

  const LogFilterBar({
    super.key,
    required this.filterText,
    required this.selectedLevel,
    required this.linesToFetch,
    required this.onFilterChanged,
    required this.onLevelChanged,
    required this.onLinesChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      color: theme.colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: TextEditingController(text: filterText)
                      ..selection = TextSelection.fromPosition(
                        TextPosition(offset: filterText.length),
                      ),
                    onChanged: onFilterChanged,
                    decoration: InputDecoration(
                      hintText: l10n?.logViewerFilter ?? 'Filter logs...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: filterText.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => onFilterChanged(''),
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<int>(
                initialValue: linesToFetch,
                tooltip: l10n?.logViewerLines ?? 'Lines to fetch',
                onSelected: onLinesChanged,
                itemBuilder: (ctx) => [
                  const PopupMenuItem(value: 100, child: Text('100 lines')),
                  const PopupMenuItem(value: 200, child: Text('200 lines')),
                  const PopupMenuItem(value: 500, child: Text('500 lines')),
                  const PopupMenuItem(value: 1000, child: Text('1000 lines')),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Text('$linesToFetch', style: theme.textTheme.bodySmall),
                      const Icon(Icons.arrow_drop_down, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: Text(l10n?.logViewerLevelAll ?? 'All'),
                  selected: selectedLevel == null,
                  onSelected: (_) => onLevelChanged(null),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: Text(l10n?.logViewerLevelError ?? 'Error'),
                  selected: selectedLevel == LogLevel.error,
                  onSelected: (selected) =>
                      onLevelChanged(selected ? LogLevel.error : null),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: Text(l10n?.logViewerLevelWarn ?? 'Warning'),
                  selected: selectedLevel == LogLevel.warning,
                  onSelected: (selected) =>
                      onLevelChanged(selected ? LogLevel.warning : null),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: Text(l10n?.logViewerLevelInfo ?? 'Info'),
                  selected: selectedLevel == LogLevel.info,
                  onSelected: (selected) =>
                      onLevelChanged(selected ? LogLevel.info : null),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: Text(l10n?.logViewerLevelDebug ?? 'Debug'),
                  selected: selectedLevel == LogLevel.debug,
                  onSelected: (selected) =>
                      onLevelChanged(selected ? LogLevel.debug : null),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
