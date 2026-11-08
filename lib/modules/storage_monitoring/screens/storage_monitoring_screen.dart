// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/luci_app_bar.dart';
import 'package:yet_another_luci_app/widgets/luci_collapsible_card.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import '../models/storage_info.dart';

class StorageMonitoringScreen extends ConsumerWidget {
  const StorageMonitoringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final appState = ref.watch(appStateProvider);

    if (appState.isDashboardLoading && appState.dashboardData == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n?.storageMonTitle ?? 'Storage Monitoring'),
        ),
        body: const LuciLoadingWidget(),
      );
    }

    final mountData = appState.dashboardData?['mountPoints'];
    final storage = StorageOverview.fromRpcData(
      mountData,
      isReviewerMode: appState.reviewerModeEnabled,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n?.storageMonTitle ?? 'Storage Monitoring'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l10n?.storageMonTooltipRefresh ?? 'Refresh Storage',
            onPressed: () => appState.fetchDashboardData(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await appState.fetchDashboardData();
        },
        child: storage.mountPoints.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(24.0),
                children: [
                  const SizedBox(height: 60),
                  Icon(
                    Icons.sd_card_alert_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n?.storageMonNoDataTitle ?? 'No Storage Data Found',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n?.storageMonNoDataDesc ??
                        'Could not query filesystem mount points from the router. Ensure RPC permissions or busybox df executable are available.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: () => appState.fetchDashboardData(),
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n?.storageMonBtnRefresh ?? 'Refresh Data'),
                    ),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  _buildSectionHeader(
                    context,
                    l10n?.storageMonOverviewHeader ??
                        'Filesystem Usage Overview',
                    Icons.pie_chart_outline,
                  ),
                  const SizedBox(height: 8),
                  _buildOverallUsageCard(context, storage),
                  if (storage.hasExternalStorage) ...[
                    const SizedBox(height: 16),
                    _buildSectionHeader(
                      context,
                      l10n?.storageMonExternalDevicesSection(
                            storage.externalMounts.length,
                          ) ??
                          'External Storage Devices (${storage.externalMounts.length})',
                      Icons.usb_rounded,
                    ),
                    const SizedBox(height: 8),
                    ...storage.externalMounts.map(
                      (mp) => _buildExternalStorageCard(context, mp),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _buildSectionHeader(
                    context,
                    l10n?.storageMonOverlayHeader ?? 'Overlay FS Status',
                    Icons.layers_outlined,
                  ),
                  const SizedBox(height: 8),
                  _buildOverlayFsCard(context, storage.overlayFs),
                  const SizedBox(height: 16),
                  _buildSectionHeader(
                    context,
                    l10n?.storageMonFlashHeader ?? 'Flash Memory & Root FS',
                    Icons.memory_outlined,
                  ),
                  const SizedBox(height: 8),
                  _buildFlashMemoryCard(context, storage.rootFs),
                  const SizedBox(height: 16),
                  _buildSectionHeader(
                    context,
                    l10n?.storageMonMountedHeader(storage.mountPoints.length) ??
                        'Mounted Storage Devices (${storage.mountPoints.length})',
                    Icons.storage_outlined,
                  ),
                  const SizedBox(height: 8),
                  if (storage.mountPoints.length > 2)
                    LuciCollapsibleCard(
                      title:
                          l10n?.storageMonAllMountedTitle ??
                          'All Mounted Storage Devices',
                      count: storage.mountPoints.length,
                      subtitle:
                          l10n?.storageMonAllMountedSubtitle(
                            storage.mountPoints.length,
                          ) ??
                          '${storage.mountPoints.length} active filesystems • Tap to view all',
                      icon: Icons.storage_outlined,
                      iconColor: Colors.blue,
                      child: Column(
                        children: storage.mountPoints
                            .map((mp) => _buildMountPointCard(context, mp))
                            .toList(),
                      ),
                    )
                  else
                    Column(
                      children: storage.mountPoints
                          .map((mp) => _buildMountPointCard(context, mp))
                          .toList(),
                    ),
                  const SizedBox(height: 32),
                ],
              ),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    IconData icon, {
    int maxLines = 2,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: maxLines,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildOverallUsageCard(BuildContext context, StorageOverview storage) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final percent = storage.overallUsedPercent;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        l10n?.storageMonTotalSystemStorage ??
                            'Total System Storage',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (storage.hasExternalStorage)
                        _buildExternalStorageBadge(context, storage),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n?.storageMonPercentUsed(percent.toStringAsFixed(1)) ??
                      '${percent.toStringAsFixed(1)}% Used',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (percent / 100).clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  percent > 85
                      ? theme.colorScheme.error
                      : (percent > 65
                            ? LuciStatusColors.warningColor(context)
                            : LuciStatusColors.connectedColor(context)),
                ),
              ),
            ),
            if (storage.hasExternalStorage) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.memory,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${l10n?.storageMonInbuiltLabel ?? "Inbuilt"}: ${StorageOverview.formatBytes(storage.inbuiltStorageTotalBytes)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Icon(
                          Icons.usb_rounded,
                          size: 14,
                          color: theme.colorScheme.tertiary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${l10n?.storageMonExternalLabel ?? "External"}: ${StorageOverview.formatBytes(storage.externalStorageTotalBytes)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.tertiary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatColumn(
                  l10n?.storageMonTotalSpace ?? 'Total Space',
                  StorageOverview.formatBytes(storage.totalSizeBytes),
                ),
                _buildStatColumn(
                  l10n?.storageMonUsedSpace ?? 'Used Space',
                  StorageOverview.formatBytes(storage.totalUsedBytes),
                ),
                _buildStatColumn(
                  l10n?.storageMonFreeSpace ?? 'Free Space',
                  StorageOverview.formatBytes(
                    storage.totalSizeBytes - storage.totalUsedBytes,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExternalStorageBadge(
    BuildContext context,
    StorageOverview storage,
  ) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final sizeFormatted = StorageOverview.formatBytes(
      storage.externalStorageTotalBytes,
    );
    final badgeText =
        l10n?.storageMonExternalBadge(sizeFormatted) ??
        'External: $sizeFormatted';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.colorScheme.tertiary.withValues(alpha: 0.4),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.usb_rounded,
            size: 13,
            color: theme.colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 4),
          Text(
            badgeText,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 10.5,
              color: theme.colorScheme.onTertiaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExternalStorageCard(BuildContext context, MountPointItem item) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final percent = item.usedPercent;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.usb_rounded,
                        color: theme.colorScheme.tertiary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.mountPath,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item.filesystemType.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (percent / 100).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  percent > 90
                      ? theme.colorScheme.error
                      : (percent > 75
                            ? LuciStatusColors.warningColor(context)
                            : theme.colorScheme.tertiary),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildDetailRow(
              l10n?.storageMonBlockDevice ?? 'Block Device',
              item.device,
            ),
            _buildDetailRow(
              l10n?.storageMonMountTarget ?? 'Mount Target',
              item.mountPath,
            ),
            _buildDetailRow(
              l10n?.storageMonSize ?? 'Size',
              StorageOverview.formatBytes(item.sizeBytes),
            ),
            _buildDetailRow(
              l10n?.storageMonUsedSpace ?? 'Used Space',
              '${StorageOverview.formatBytes(item.usedBytes)} (${percent.toStringAsFixed(1)}%)',
            ),
            _buildDetailRow(
              l10n?.storageMonFreeSpace ?? 'Free Space',
              StorageOverview.formatBytes(item.availableBytes),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlayFsCard(BuildContext context, MountPointItem? overlay) {
    final l10n = AppLocalizations.of(context);
    if (overlay == null) {
      return Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.blue, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n?.storageMonOverlayMissing ??
                      'Overlay filesystem (/overlay) is either integrated into Root FS or not separately mounted.',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: Colors.green,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n?.storageMonOverlayActiveOn(overlay.device) ??
                      'Overlay Active on ${overlay.device}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 20),
            _buildDetailRow(
              l10n?.storageMonMountTarget ?? 'Mount Target',
              overlay.mountPath,
            ),
            _buildDetailRow(
              l10n?.storageMonBlockDevice ?? 'Block Device',
              overlay.device,
            ),
            _buildDetailRow(
              l10n?.storageMonFilesystemType ?? 'Filesystem Type',
              overlay.filesystemType.toUpperCase(),
            ),
            _buildDetailRow(
              l10n?.storageMonUsedSpace ?? 'Used Space',
              '${StorageOverview.formatBytes(overlay.usedBytes)} (${overlay.usedPercent.toStringAsFixed(1)}%)',
            ),
            _buildDetailRow(
              l10n?.storageMonAvailableSpace ?? 'Available Space',
              StorageOverview.formatBytes(overlay.availableBytes),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlashMemoryCard(BuildContext context, MountPointItem? root) {
    final l10n = AppLocalizations.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n?.storageMonFlashInfo ?? 'On-board Flash Memory Info',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildDetailRow(
              l10n?.storageMonRootDir ?? 'Root Directory',
              root?.mountPath ?? '/',
            ),
            _buildDetailRow(
              l10n?.storageMonFlashDevice ?? 'Flash Device',
              root?.device ?? '/dev/root',
            ),
            _buildDetailRow(
              l10n?.storageMonRootFsFormat ?? 'Root FS Format',
              (root?.filesystemType ?? 'squashfs').toUpperCase(),
            ),
            _buildDetailRow(
              l10n?.storageMonSize ?? 'Size',
              StorageOverview.formatBytes(root?.sizeBytes ?? 0),
            ),
            _buildDetailRow(
              l10n?.storageMonFreeSpace ?? 'Free Space',
              StorageOverview.formatBytes(root?.availableBytes ?? 0),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMountPointCard(BuildContext context, MountPointItem item) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final mountTarget = item.mountPath;
    final blockDevice = item.device;

    final String titleLabel;
    if (blockDevice.isNotEmpty &&
        blockDevice.toLowerCase() != 'unknown' &&
        blockDevice != mountTarget) {
      titleLabel = '$mountTarget ($blockDevice)';
    } else {
      titleLabel = mountTarget;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: item.isExternal
              ? theme.colorScheme.tertiaryContainer
              : theme.colorScheme.primaryContainer,
          child: Icon(
            item.isExternal
                ? Icons.usb_rounded
                : (item.isTmp
                      ? Icons.folder_zip_outlined
                      : Icons.sd_storage_outlined),
            color: item.isExternal
                ? theme.colorScheme.onTertiaryContainer
                : theme.colorScheme.onPrimaryContainer,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                titleLabel,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (item.isExternal) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  l10n?.storageMonExternalLabel ?? 'External',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          item.filesystemType.isNotEmpty
              ? item.filesystemType.toLowerCase()
              : 'fs',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              l10n?.storageMonUsedLabel(item.usedPercent.toStringAsFixed(0)) ??
                  '${item.usedPercent.toStringAsFixed(0)}% used',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              '${StorageOverview.formatBytes(item.usedBytes)} / ${StorageOverview.formatBytes(item.sizeBytes)}',
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
