// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/widgets/rpc_permissions_dialog.dart';

/// Card displayed when Smart Queue Management (SQM) is not installed on the router.
class SqmInstallCard extends ConsumerWidget {
  final VoidCallback onInstallTap;
  final bool isInstalling;

  const SqmInstallCard({
    super.key,
    required this.onInstallTap,
    this.isInstalling = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final appState = ref.watch(appStateProvider);
    final pkgMgr =
        appState.capabilities?.packageEngine ?? PackageManagerEngine.none;

    final pkgMgrBadgeText = pkgMgr == PackageManagerEngine.apk
        ? 'APK'
        : pkgMgr == PackageManagerEngine.opkg
        ? 'OPKG'
        : 'OpenWrt';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.speed_rounded,
                    color: theme.colorScheme.primary,
                    size: 32,
                  ),
                ),
                const SizedBox(width: LuciSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n?.modSqmName ?? 'Smart Queue Management',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              pkgMgrBadgeText,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n?.modSqmNotInstalledBadge ?? 'Not Installed',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: LuciStatusColors.inactive,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuciSpacing.md),
            Text(
              l10n?.modSqmIntroDesc ??
                  'Smart Queue Management (SQM) solves bufferbloat by maintaining low network latency under heavy upload and download loads using modern queue disciplines like CAKE and FQ-CoDel.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: LuciSpacing.md),
            _buildFeatureBullet(
              context,
              icon: Icons.network_check_rounded,
              title:
                  l10n?.modSqmBulletBufferbloatTitle ??
                  'Eliminates Bufferbloat',
              subtitle:
                  l10n?.modSqmBulletBufferbloatDesc ??
                  'Keeps gaming ping low and video calls stable even when downloads max out your bandwidth.',
            ),
            const SizedBox(height: LuciSpacing.sm),
            _buildFeatureBullet(
              context,
              icon: Icons.alt_route_rounded,
              title:
                  l10n?.modSqmBulletAlgorithmsTitle ??
                  'CAKE & FQ-CoDel Support',
              subtitle:
                  l10n?.modSqmBulletAlgorithmsDesc ??
                  'Advanced packet scheduling algorithms designed specifically for edge routers.',
            ),
            const SizedBox(height: LuciSpacing.sm),
            _buildFeatureBullet(
              context,
              icon: Icons.layers_outlined,
              title:
                  l10n?.modSqmBulletOverheadTitle ??
                  'Framing Overhead Compensation',
              subtitle:
                  l10n?.modSqmBulletOverheadDesc ??
                  'Compensate for DSL, PPPoE, or Cable per-packet framing overhead.',
            ),
            const SizedBox(height: LuciSpacing.lg),
            if (appState.isMissingRpcPackages) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade900.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.amber.shade700.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      color: Colors.amber.shade800,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Router RPC permissions missing. Installing packages requires RPC execution permissions.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: LuciSpacing.md),
            ],
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: isInstalling
                    ? null
                    : (appState.isMissingRpcPackages
                          ? () => RpcPermissionsDialog.show(
                              context,
                              actionName: 'SQM Installation',
                            )
                          : onInstallTap),
                style: appState.isMissingRpcPackages
                    ? FilledButton.styleFrom(
                        backgroundColor: Colors.amber.shade800,
                        foregroundColor: Colors.white,
                      )
                    : null,
                icon: isInstalling
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        appState.isMissingRpcPackages
                            ? Icons.lock_outline_rounded
                            : Icons.download_rounded,
                      ),
                label: Text(
                  isInstalling
                      ? (l10n?.modSqmInstallingButton ?? 'Installing...')
                      : (appState.isMissingRpcPackages
                            ? 'Fix Permissions to Install'
                            : (l10n?.modSqmInstallButton ?? 'Install SQM')),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureBullet(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: LuciSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
