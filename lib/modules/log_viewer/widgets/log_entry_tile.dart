// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import '../models/log_entry.dart';
import 'log_level_badge.dart';

class LogEntryTile extends StatelessWidget {
  final LogEntry entry;

  const LogEntryTile({super.key, required this.entry});

  void _copyRaw(BuildContext context) {
    Clipboard.setData(ClipboardData(text: entry.raw));
    final l10n = AppLocalizations.of(context);
    LuciToastManager.showSuccess(
      context,
      l10n?.logViewerCopied ?? 'Log copied to clipboard',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onLongPress: () => _copyRaw(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                LogLevelBadge(level: entry.level),
                const SizedBox(width: 8),
                if (entry.timestamp != null) ...[
                  Text(
                    entry.timestamp!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (entry.tag != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      entry.tag!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            SelectableText(
              entry.message.isNotEmpty ? entry.message : entry.raw,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.3,
              ),
            ),
            const SizedBox(height: 4),
            Divider(
              height: 1,
              color: theme.dividerColor.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}
