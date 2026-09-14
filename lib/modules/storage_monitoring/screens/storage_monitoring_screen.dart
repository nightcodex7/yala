// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/luci_app_bar.dart';
import 'package:yet_another_luci_app/widgets/luci_collapsible_card.dart';
import '../models/storage_info.dart';

class StorageMonitoringScreen extends ConsumerWidget {
  const StorageMonitoringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);

    if (appState.isDashboardLoading && appState.dashboardData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Storage Monitoring')),
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
        title: const Text('Storage Monitoring'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Storage',
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
                    'No Storage Data Found',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
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
                      label: const Text('Refresh Data'),
                    ),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  _buildSectionHeader(
                    context,
                    'Filesystem Usage Overview',
                    Icons.pie_chart_outline,
                  ),
                  const SizedBox(height: 8),
                  _buildOverallUsageCard(context, storage),
                  const SizedBox(height: 16),
                  _buildSectionHeader(
                    context,
                    'Overlay FS Status',
                    Icons.layers_outlined,
                  ),
                  const SizedBox(height: 8),
                  _buildOverlayFsCard(context, storage.overlayFs),
                  const SizedBox(height: 16),
                  _buildSectionHeader(
                    context,
                    'Flash Memory & Root FS',
                    Icons.memory_outlined,
                  ),
                  const SizedBox(height: 8),
                  _buildFlashMemoryCard(context, storage.rootFs),
                  const SizedBox(height: 16),
                  _buildSectionHeader(
                    context,
                    'Mounted Storage Devices (${storage.mountPoints.length})',
                    Icons.storage_outlined,
                  ),
                  const SizedBox(height: 8),
                  if (storage.mountPoints.length > 2)
                    LuciCollapsibleCard(
                      title: 'All Mounted Storage Devices',
                      count: storage.mountPoints.length,
                      subtitle:
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
    IconData icon,
  ) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
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
              children: [
                const Text(
                  'Total System Storage',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
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
                      ? Colors.red
                      : (percent > 65 ? Colors.orange : Colors.teal),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatColumn(
                  'Total Space',
                  StorageOverview.formatBytes(storage.totalSizeBytes),
                ),
                _buildStatColumn(
                  'Used Space',
                  StorageOverview.formatBytes(storage.totalUsedBytes),
                ),
                _buildStatColumn(
                  'Free Space',
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

  Widget _buildOverlayFsCard(BuildContext context, MountPointItem? overlay) {
    if (overlay == null) {
      return Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Overlay filesystem (/overlay) is either integrated into Root FS or not separately mounted.',
                  style: TextStyle(fontSize: 13),
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
                  'Overlay Active on ${overlay.device}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 20),
            _buildDetailRow('Mount Target', overlay.mountPath),
            _buildDetailRow('Block Device', overlay.device),
            _buildDetailRow(
              'Filesystem Type',
              overlay.filesystemType.toUpperCase(),
            ),
            _buildDetailRow(
              'Used Space',
              '${StorageOverview.formatBytes(overlay.usedBytes)} (${overlay.usedPercent.toStringAsFixed(1)}%)',
            ),
            _buildDetailRow(
              'Available Space',
              StorageOverview.formatBytes(overlay.availableBytes),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlashMemoryCard(BuildContext context, MountPointItem? root) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'On-board Flash Memory Info',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildDetailRow('Root Directory', root?.mountPath ?? '/'),
            _buildDetailRow('Flash Device', root?.device ?? '/dev/root'),
            _buildDetailRow(
              'Root FS Format',
              (root?.filesystemType ?? 'squashfs').toUpperCase(),
            ),
            _buildDetailRow(
              'Size',
              StorageOverview.formatBytes(root?.sizeBytes ?? 0),
            ),
            _buildDetailRow(
              'Free Space',
              StorageOverview.formatBytes(root?.availableBytes ?? 0),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMountPointCard(BuildContext context, MountPointItem item) {
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
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            item.isTmp ? Icons.folder_zip_outlined : Icons.sd_storage_outlined,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          titleLabel,
          style: const TextStyle(fontWeight: FontWeight.bold),
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
            child: SelectableText(
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
