// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/modules/storage_monitoring/models/storage_info.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/widgets/rpc_permissions_dialog.dart';

/// Modal dialog for one-click SQM installation with dual package options:
/// 1. `sqm-scripts` (Backend only, recommended for low storage; clearly notes no LuCI web controls)
/// 2. `luci-app-sqm` (Web interface + scripts; requires ~500 KB free storage)
///
/// On-demand storage assessment is performed strictly when this dialog opens.
class SqmInstallDialog extends ConsumerStatefulWidget {
  const SqmInstallDialog({super.key});

  @override
  ConsumerState<SqmInstallDialog> createState() => _SqmInstallDialogState();
}

class _SqmInstallDialogState extends ConsumerState<SqmInstallDialog> {
  bool _isLoadingStorage = true;
  bool _isStorageReadOnly = false;
  int? _availableBytes;
  String _targetMountPath = '/overlay';
  PackageManagerEngine _pkgMgr = PackageManagerEngine.none;

  @override
  void initState() {
    super.initState();
    final appState = ref.read(appStateProvider);
    _pkgMgr = appState.capabilities?.packageEngine ?? PackageManagerEngine.none;
    _assessStorageAndCapabilities(appState);
  }

  Future<void> _assessStorageAndCapabilities(AppState appState) async {
    _pkgMgr = appState.capabilities?.packageEngine ?? PackageManagerEngine.none;

    final dashboardData = appState.dashboardData;
    final storageOverview = StorageOverview.fromRpcData(
      dashboardData?['mountPoints'] ?? dashboardData?['sysInfo'],
      isReviewerMode: appState.reviewerModeEnabled,
    );
    final targetMount = storageOverview.overlayFs ?? storageOverview.rootFs;

    _targetMountPath = targetMount?.mountPath ?? '/overlay';
    _isStorageReadOnly =
        targetMount != null &&
        targetMount.isReadOnly &&
        targetMount.mountPath != '/rom';

    // Live on-demand disk space query
    int? freeBytes;
    try {
      freeBytes = await appState.getFreeDiskSpace();
    } catch (_) {}

    if (mounted) {
      setState(() {
        _availableBytes = freeBytes;
        _isLoadingStorage = false;
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 KB';
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).round()} KB';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final appState = ref.watch(appStateProvider);
    final isRpcMissing = appState.isMissingRpcPackages;

    final isLowStorage =
        _availableBytes != null &&
        _availableBytes! > 0 &&
        _availableBytes! < 500 * 1024;
    final canInstall =
        !_isStorageReadOnly &&
        !isRpcMissing &&
        (_availableBytes == null || _availableBytes! > 0);

    return AlertDialog(
      actionsOverflowButtonSpacing: 8,
      actionsOverflowDirection: VerticalDirection.down,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.speed_rounded,
              color: theme.colorScheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: LuciSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n?.modSqmInstallTitle ?? 'Install Smart Queue Management',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _pkgMgr == PackageManagerEngine.apk
                      ? 'Package Engine: APK'
                      : _pkgMgr == PackageManagerEngine.opkg
                      ? 'Package Engine: OPKG'
                      : 'Bufferbloat Mitigation',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Live storage assessment indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.3,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isStorageReadOnly
                        ? Icons.error_outline_rounded
                        : (isLowStorage
                              ? Icons.warning_amber_rounded
                              : (_availableBytes == null
                                    ? Icons.help_outline_rounded
                                    : Icons.storage_rounded)),
                    size: 16,
                    color: _isStorageReadOnly
                        ? theme.colorScheme.error
                        : (isLowStorage
                              ? LuciStatusColors.warningColor(context)
                              : (_availableBytes == null
                                    ? theme.colorScheme.onSurfaceVariant
                                    : LuciStatusColors.connectedColor(
                                        context,
                                      ))),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isLoadingStorage
                          ? 'Checking storage in $_targetMountPath...'
                          : (_availableBytes != null
                                ? 'Free space in $_targetMountPath: ${_formatBytes(_availableBytes!)}'
                                : 'Free space in $_targetMountPath: Unavailable'),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: LuciSpacing.md),

            if (isRpcMissing) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: LuciStatusColors.warningBg(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: LuciStatusColors.warningBorder(context),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      color: LuciStatusColors.warningColor(context),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Package installation is restricted because router RPC permissions are missing.',
                        style: TextStyle(
                          fontSize: 12,
                          color: LuciStatusColors.warningText(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: LuciSpacing.sm),
            ],

            if (_isStorageReadOnly) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: LuciStatusColors.errorBg(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: LuciStatusColors.errorBorder(context),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: theme.colorScheme.error,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n?.modSqmStorageReadOnlyNotice ??
                            'Storage filesystem is read-only or full. Package installation cannot proceed.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: LuciStatusColors.errorText(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: LuciSpacing.sm),
            ] else if (isLowStorage) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: LuciStatusColors.warningBg(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: LuciStatusColors.warningBorder(context),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: LuciStatusColors.warningColor(context),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Storage is limited (${_formatBytes(_availableBytes!)} free). Package installation requires sufficient flash space for scripts and kernel dependencies.',
                        style: TextStyle(
                          fontSize: 12,
                          color: LuciStatusColors.warningText(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: LuciSpacing.sm),
            ],

            Text(
              'Package to Install:',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: LuciSpacing.xs),

            // sqm-scripts primary card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.primary, width: 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'sqm-scripts',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          l10n?.modSqmOptionBackendOnlyTag ?? 'Core Service',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n?.modSqmOptionScriptsDesc ??
                        'Installs core traffic shaping scripts. Ideal for storage-constrained routers.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.25,
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            l10n?.modSqmNoticeNoLuciWeb ??
                                'SQM controls will be fully accessible within YALA, but will NOT appear in the LuCI browser web interface.',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
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
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(l10n?.actionCancel ?? 'Cancel'),
        ),
        if (isRpcMissing)
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop(null);
              RpcPermissionsDialog.show(
                context,
                actionName: 'SQM Installation',
              );
            },
            icon: const Icon(Icons.build_circle_outlined, size: 18),
            label: const Text('Fix Permissions'),
            style: FilledButton.styleFrom(
              backgroundColor: LuciStatusColors.warningColor(context),
            ),
          )
        else
          FilledButton.icon(
            onPressed: canInstall
                ? () => Navigator.of(context).pop('sqm-scripts')
                : null,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(l10n?.actionInstallNow ?? 'Install Now'),
          ),
      ],
    );
  }
}
