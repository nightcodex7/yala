// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import '../models/storage_info.dart';

class StorageMonitoringCard extends ConsumerWidget {
  const StorageMonitoringCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    final mountData = appState.dashboardData?['mountPoints'];
    final storage = StorageOverview.fromRpcData(
      mountData,
      isReviewerMode: appState.reviewerModeEnabled,
    );

    final displayItems = storage.priorityDisplayMounts;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 14.0),
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
                        Icons.sd_storage_outlined,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Storage & Overlay',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${storage.mountedDevices.length} Mounts',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (displayItems.isEmpty)
              Text(
                'No storage devices detected.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey),
              )
            else
              Column(
                children: [
                  for (int i = 0; i < displayItems.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    _buildStorageBarForItem(
                      context,
                      item: displayItems[i],
                      index: i,
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStorageBarForItem(
    BuildContext context, {
    required MountPointItem item,
    required int index,
  }) {
    final mountTarget = item.mountPath;
    final blockDevice = item.device;

    final String label;
    if (blockDevice.isNotEmpty &&
        blockDevice.toLowerCase() != 'unknown' &&
        blockDevice != mountTarget) {
      label = '$mountTarget ($blockDevice)';
    } else {
      label = mountTarget;
    }

    final colors = [
      Colors.teal,
      Colors.indigo,
      Colors.amber.shade700,
      Colors.purple,
    ];
    final color = colors[index % colors.length];

    return _buildStorageBar(
      context,
      label: label,
      percent: item.usedPercent,
      used: item.usedBytes,
      total: item.sizeBytes,
      color: color,
    );
  }

  Widget _buildStorageBar(
    BuildContext context, {
    required String label,
    required double percent,
    required int used,
    required int total,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final formattedUsed = StorageOverview.formatBytes(used);
    final formattedTotal = StorageOverview.formatBytes(total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$formattedUsed / $formattedTotal (${percent.toStringAsFixed(0)}%)',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (percent / 100).clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
