// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import '../models/system_metrics.dart';

class SystemMonitoringScreen extends ConsumerWidget {
  const SystemMonitoringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    final sysInfo = appState.dashboardData?['sysInfo'] as Map<String, dynamic>?;
    final boardInfo =
        appState.dashboardData?['boardInfo'] as Map<String, dynamic>?;
    final metrics = SystemMetrics.fromSysInfo(sysInfo, boardInfo: boardInfo);

    final hostname = boardInfo?['hostname']?.toString() ?? 'Router';
    final model = boardInfo?['model']?.toString() ?? 'OpenWrt Router';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('System Monitoring'),
            Text(
              '$hostname ($model)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await appState.fetchDashboardData();
        },
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _buildMetricDetailCard(
              context,
              title: 'CPU Status',
              icon: Icons.memory_outlined,
              color: Colors.orange,
              children: [
                _buildInfoRow(
                  'Estimated Usage',
                  '${metrics.cpuUsagePercent.toStringAsFixed(1)}%',
                ),
                _buildInfoRow('1 Min Load', metrics.load1m.toStringAsFixed(2)),
              ],
            ),
            const SizedBox(height: 12),
            _buildMetricDetailCard(
              context,
              title: 'RAM Memory',
              icon: Icons.pie_chart_outline,
              color: Colors.blue,
              children: [
                _buildInfoRow(
                  'Usage Percent',
                  '${metrics.memoryUsagePercent.toStringAsFixed(1)}%',
                ),
                _buildInfoRow(
                  'Used Memory',
                  _formatBytes(metrics.usedMemoryBytes),
                ),
                _buildInfoRow(
                  'Free Memory',
                  _formatBytes(metrics.freeMemoryBytes),
                ),
                _buildInfoRow(
                  'Buffered',
                  _formatBytes(metrics.bufferedMemoryBytes),
                ),
                _buildInfoRow(
                  'Cached',
                  _formatBytes(metrics.cachedMemoryBytes),
                ),
                _buildInfoRow(
                  'Total Memory',
                  _formatBytes(metrics.totalMemoryBytes),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildMetricDetailCard(
              context,
              title: 'Load Average',
              icon: Icons.speed_outlined,
              color: Colors.purple,
              children: [
                _buildInfoRow('1 Minute', metrics.load1m.toStringAsFixed(2)),
                _buildInfoRow('5 Minutes', metrics.load5m.toStringAsFixed(2)),
                _buildInfoRow('15 Minutes', metrics.load15m.toStringAsFixed(2)),
              ],
            ),
            const SizedBox(height: 12),
            _buildMetricDetailCard(
              context,
              title: 'System Uptime',
              icon: Icons.timer_outlined,
              color: Colors.green,
              children: [
                _buildInfoRow('Uptime', metrics.formattedUptime),
                _buildInfoRow('Total Seconds', '${metrics.uptimeSeconds} s'),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricDetailCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
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
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
