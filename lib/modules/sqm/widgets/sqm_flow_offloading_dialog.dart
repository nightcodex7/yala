// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';

/// Shows a dedicated warning popup when flow offloading (software or hardware)
/// is detected on the router before enabling SQM.
///
/// Flow offloading bypasses the Linux kernel networking stack and Traffic
/// Control (tc), preventing SQM from shaping forwarded traffic.
///
/// Returns `true` if the user chooses "Enable Anyway" or successfully disables offloading,
/// or `false` if cancelled.
Future<bool> showFlowOffloadingWarningDialog(
  BuildContext context, {
  WidgetRef? ref,
}) async {
  final l10n = AppLocalizations.of(context);
  final theme = Theme.of(context);

  final result = await showDialog<dynamic>(
    context: context,
    builder: (ctx) => AlertDialog(
      actionsOverflowButtonSpacing: 8,
      actionsOverflowDirection: VerticalDirection.down,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.error.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.warning_amber_rounded,
              color: theme.colorScheme.error,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n?.modSqmFlowOffloadDialogTitle ?? 'Flow Offloading Active',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n?.modSqmFlowOffloadDialogContent ??
                  'Flow offloading is currently enabled in your router\'s firewall settings.\n\nWhen flow offloading is active, network traffic bypasses the Linux kernel networking stack and Traffic Control (tc) queueing disciplines. As a result, SQM cannot shape forwarded traffic or mitigate bufferbloat effectively.\n\nTo get the full benefit of SQM, flow offloading should be disabled in Firewall settings.\n\nDo you want to proceed with enabling SQM anyway?',
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n?.actionCancel ?? 'Cancel'),
        ),
        if (ref != null)
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop('disable'),
            child: const Text('Disable in Firewall'),
          ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n?.modSqmFlowOffloadBtnProceed ?? 'Enable Anyway'),
        ),
      ],
    ),
  );

  if (result == 'disable' && ref != null) {
    const actionKey = 'sqm_disable_flow_offload';
    if (context.mounted) {
      context.showToastLoading(
        'Disabling Flow Offloading',
        subtitle: 'Disabling firewall flow offloading and reloading...',
        actionKey: actionKey,
      );
    }
    final appState = ref.read(appStateProvider);
    final success = await appState.updateFirewallFlowOffloading(
      software: false,
      hardware: false,
      context: context.mounted ? context : null,
    );
    if (context.mounted) {
      if (success) {
        context.showToastSuccess(
          'Flow Offloading Disabled',
          subtitle: 'Firewall flow offloading disabled. SQM shaping active.',
          actionKey: actionKey,
        );
      } else {
        context.showToastError(
          'Failed to Disable Offloading',
          subtitle: 'Please check your firewall settings.',
          actionKey: actionKey,
        );
      }
    }
    return success;
  }

  return result == true;
}
