// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import '../controllers/adguard_controller.dart';

/// Interactive modal dialog for viewing, editing, and saving custom user rules
/// in AdGuard Home (`/control/filtering/set_rules`).
class AdGuardCustomRulesDialog extends StatefulWidget {
  final AdGuardController controller;
  final List<String>? initialRules;

  const AdGuardCustomRulesDialog({
    super.key,
    required this.controller,
    this.initialRules,
  });

  /// Displays the custom rules dialog and returns `true` if rules were saved.
  static Future<bool?> show(
    BuildContext context, {
    required AdGuardController controller,
    List<String>? initialRules,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AdGuardCustomRulesDialog(
        controller: controller,
        initialRules: initialRules,
      ),
    );
  }

  @override
  State<AdGuardCustomRulesDialog> createState() =>
      _AdGuardCustomRulesDialogState();
}

class _AdGuardCustomRulesDialogState extends State<AdGuardCustomRulesDialog> {
  late final TextEditingController _textController;
  bool _isSaving = false;
  String? _errorMessage;
  int _ruleCount = 0;

  @override
  void initState() {
    super.initState();
    final existingRules =
        widget.initialRules ??
        widget.controller.currentState.filtering?.userRules ??
        [];
    _textController = TextEditingController(text: existingRules.join('\n'));
    _ruleCount = _countRules(_textController.text);
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final count = _countRules(_textController.text);
    if (count != _ruleCount) {
      setState(() {
        _ruleCount = count;
      });
    }
  }

  int _countRules(String text) {
    if (text.isEmpty) return 0;
    return text
        .split('\n')
        .where((line) => line.trim().isNotEmpty && !line.trim().startsWith('!'))
        .length;
  }

  List<String> _parseRules(String text) {
    return text
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  Future<void> _saveRules() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final rules = _parseRules(_textController.text);
    final success = await widget.controller.updateUserRules(rules);

    if (!mounted) return;

    if (success) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n?.aghSaveRulesSuccess ?? 'Custom rules saved successfully',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    } else {
      final l10n = AppLocalizations.of(context);
      setState(() {
        _isSaving = false;
        _errorMessage =
            widget.controller.currentState.filteringError ??
            (l10n?.aghSaveRulesError ?? 'Failed to save custom rules');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      key: const Key('agh_custom_rules_dialog'),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      title: Row(
        children: [
          Icon(Icons.rule_rounded, color: colorScheme.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n?.aghCustomRulesTitle ?? 'Custom Filtering Rules',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$_ruleCount ${l10n?.aghRulesCount ?? 'rules'}',
              key: const Key('agh_custom_rules_count_badge'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n?.aghCustomRulesHint ??
                    'Add custom blocking rules, exceptions, or host overrides (one per line).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (_errorMessage != null) ...[
                Container(
                  key: const Key('agh_custom_rules_error_banner'),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: colorScheme.error.withValues(alpha: 0.5),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 16,
                        color: colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          key: const Key('agh_custom_rules_error_text'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outlineVariant,
                    width: 0.8,
                  ),
                ),
                child: TextField(
                  key: const Key('agh_custom_rules_text_field'),
                  controller: _textController,
                  enabled: !_isSaving,
                  maxLines: 12,
                  minLines: 8,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                  ),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.all(12),
                    border: InputBorder.none,
                    hintText:
                        '# Example rules:\n||example.com^\n@@||allowed.com^\n127.0.0.1 host.local\n! comment',
                    hintStyle: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: colorScheme.outline.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('agh_custom_rules_cancel_button'),
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n?.actionCancel ?? 'Cancel'),
        ),
        FilledButton(
          key: const Key('agh_custom_rules_save_button'),
          onPressed: _isSaving ? null : _saveRules,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(l10n?.actionSave ?? 'Save'),
        ),
      ],
    );
  }
}
