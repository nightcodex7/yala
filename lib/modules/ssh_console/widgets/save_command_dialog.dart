// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';

class SaveCommandDialog extends StatefulWidget {
  final String initialCommand;

  const SaveCommandDialog({super.key, required this.initialCommand});

  static Future<Map<String, String>?> show(
    BuildContext context, {
    required String initialCommand,
  }) {
    return showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => SaveCommandDialog(initialCommand: initialCommand),
    );
  }

  @override
  State<SaveCommandDialog> createState() => _SaveCommandDialogState();
}

class _SaveCommandDialogState extends State<SaveCommandDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _cmdCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _cmdCtrl = TextEditingController(text: widget.initialCommand);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cmdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(l10n?.sshTerminalSaveCommand ?? 'Save Command'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              maxLength: 80,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n?.sshCommandName ?? 'Command Name',
                hintText: l10n?.sshCommandNameHint ?? 'e.g. Check uptime',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cmdCtrl,
              maxLength: 500,
              maxLines: 3,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: 'Command',
                hintText: l10n?.sshCommandTextHint ?? 'e.g. uptime',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.security,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n?.sshCommandSecretWarning ??
                          'Warning: Do not store passwords or secrets in saved commands.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n?.actionCancel ?? 'Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            final cmd = _cmdCtrl.text.trim();
            if (name.isNotEmpty && cmd.isNotEmpty) {
              Navigator.of(context).pop({'name': name, 'command': cmd});
            }
          },
          child: Text(l10n?.actionSave ?? 'Save'),
        ),
      ],
    );
  }
}
