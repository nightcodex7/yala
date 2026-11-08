// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/services/local_network_permission_service.dart';

/// Modal bottom sheet dialog providing an educational in-app prominent disclosure
/// and settings recovery flow for local network access (`ACCESS_LOCAL_NETWORK`).
///
/// Designed in accordance with Google Play's Restricted Permissions policy (answer/18100766).
class LocalNetworkPermissionDialog extends StatelessWidget {
  final bool isPermanentlyDenied;

  const LocalNetworkPermissionDialog({
    super.key,
    this.isPermanentlyDenied = false,
  });

  /// Displays the prominent disclosure or settings recovery sheet.
  static Future<bool?> show(
    BuildContext context, {
    bool isPermanentlyDenied = false,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => LocalNetworkPermissionDialog(
        isPermanentlyDenied: isPermanentlyDenied,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    final title = isPermanentlyDenied
        ? (l10n?.localNetworkPermissionDeniedTitle ??
              'Local Network Access Denied')
        : (l10n?.localNetworkPermissionTitle ?? 'Local Network Permission');

    final desc = isPermanentlyDenied
        ? (l10n?.localNetworkPermissionDeniedDesc ??
              'Local network access was denied. Yala requires this permission to communicate with your router gateway over the local network. You can enable it in device Settings.')
        : (l10n?.localNetworkPermissionDesc ??
              'Yet Another LuCI App connects directly to your OpenWrt router gateway (such as 192.168.1.1) to manage Wi-Fi, firewall, and system settings.');

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: CircleAvatar(
              radius: 32,
              backgroundColor: isPermanentlyDenied
                  ? colorScheme.errorContainer
                  : colorScheme.primaryContainer,
              child: Icon(
                isPermanentlyDenied ? Icons.gpp_bad_rounded : Icons.lan_rounded,
                size: 36,
                color: isPermanentlyDenied
                    ? colorScheme.onErrorContainer
                    : colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            desc,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (!isPermanentlyDenied) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Column(
                children: [
                  _buildBullet(
                    context,
                    Icons.lock_outline_rounded,
                    l10n?.localNetworkPermissionBulletNoExfiltration ??
                        'No internet exfiltration — All communication remains strictly between your device and your local router.',
                  ),
                  const SizedBox(height: 8),
                  _buildBullet(
                    context,
                    Icons.shield_outlined,
                    l10n?.localNetworkPermissionBulletPrivacy ??
                        'Privacy preserved — Yala never collects, tracks, or shares your local network devices.',
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (isPermanentlyDenied) ...[
            FilledButton.icon(
              icon: const Icon(Icons.settings_rounded),
              label: Text(
                l10n?.localNetworkPermissionBtnOpenSettings ??
                    'Open App Settings',
              ),
              onPressed: () {
                Navigator.of(context).pop(false);
                LocalNetworkPermissionService.openAppSettings();
              },
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n?.actionCancel ?? 'Cancel'),
            ),
          ] else ...[
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                l10n?.localNetworkPermissionBtnContinue ?? 'Continue',
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n?.actionCancel ?? 'Cancel'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBullet(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
