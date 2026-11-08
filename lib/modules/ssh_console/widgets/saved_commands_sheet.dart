// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import '../models/saved_ssh_command.dart';

class SavedCommandsSheet extends StatelessWidget {
  final List<SavedSshCommand> commands;
  final ValueChanged<SavedSshCommand> onRun;
  final ValueChanged<SavedSshCommand> onDelete;
  final VoidCallback? onAdd;
  final VoidCallback? onImport;

  const SavedCommandsSheet({
    super.key,
    required this.commands,
    required this.onRun,
    required this.onDelete,
    this.onAdd,
    this.onImport,
  });

  static Future<void> show(
    BuildContext context, {
    required List<SavedSshCommand> commands,
    required ValueChanged<SavedSshCommand> onRun,
    required ValueChanged<SavedSshCommand> onDelete,
    VoidCallback? onAdd,
    VoidCallback? onImport,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => SavedCommandsSheet(
        commands: commands,
        onRun: onRun,
        onDelete: onDelete,
        onAdd: onAdd,
        onImport: onImport,
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    SavedSshCommand cmd,
    AppLocalizations? l10n,
  ) async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.delete_outline_rounded,
          color: theme.colorScheme.error,
          size: 28,
        ),
        title: Text(
          l10n?.sshCommandDeleteConfirm ?? 'Delete this saved command?',
        ),
        content: Text(cmd.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n?.actionCancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            child: Text(l10n?.actionDelete ?? 'Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      onDelete(cmd);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.4,
                  ),
                ),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.bookmarks_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n?.sshTerminalSavedCommands ?? 'Saved Commands',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${commands.length} / 50',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (onImport != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.file_download_outlined, size: 20),
                    tooltip: l10n?.sshImportCommands ?? 'Import Commands',
                    onPressed: () {
                      Navigator.of(context).pop();
                      onImport!();
                    },
                  ),
                ],
                if (onAdd != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.add_rounded, size: 22),
                    tooltip: 'Add Command',
                    onPressed: () {
                      Navigator.of(context).pop();
                      onAdd!();
                    },
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: commands.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.bookmarks_outlined,
                            size: 48,
                            color: theme.colorScheme.outlineVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l10n?.sshNoSavedCommands ??
                                'No saved commands yet. Tap the bookmark icon after typing a command.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (onImport != null) ...[
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              icon: const Icon(
                                Icons.file_download_outlined,
                                size: 18,
                              ),
                              label: Text(
                                l10n?.sshImportCommands ?? 'Import Commands',
                              ),
                              onPressed: () {
                                Navigator.of(context).pop();
                                onImport!();
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    itemCount: commands.length,
                    itemBuilder: (ctx, idx) {
                      final cmd = commands[idx];
                      return ListTile(
                        title: Text(
                          cmd.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          cmd.command,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              tooltip: l10n?.actionDelete ?? 'Delete',
                              onPressed: () =>
                                  _confirmDelete(context, cmd, l10n),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                size: 22,
                              ),
                              tooltip: 'Run',
                              onPressed: () {
                                Navigator.of(context).pop();
                                onRun(cmd);
                              },
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          onRun(cmd);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
