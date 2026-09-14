// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import '../models/system_metrics.dart';

class SystemMonitoringCard extends ConsumerWidget {
  const SystemMonitoringCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    final sysInfo = appState.dashboardData?['sysInfo'] as Map<String, dynamic>?;
    final boardInfo =
        appState.dashboardData?['boardInfo'] as Map<String, dynamic>?;
    final metrics = SystemMetrics.fromSysInfo(sysInfo, boardInfo: boardInfo);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0, left: 4.0),
              child: Row(
                children: [
                  Icon(
                    Icons.monitor_heart_outlined,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'System Vitals',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow =
                    constraints.maxWidth < 340 ||
                    MediaQuery.textScalerOf(context).scale(14) > 17;
                final cpuTile = _buildMetricTile(
                  context,
                  label: 'CPU Load',
                  value: '${metrics.cpuUsagePercent.toStringAsFixed(0)}%',
                  icon: Icons.memory_outlined,
                  color: Colors.orange,
                );
                final ramTile = _buildMetricTile(
                  context,
                  label: 'RAM Usage',
                  value: metrics.totalMemoryBytes > 0
                      ? '${metrics.memoryUsagePercent.toStringAsFixed(0)}%'
                      : 'N/A',
                  icon: Icons.pie_chart_outline,
                  color: Colors.blue,
                );
                final loadTile = _buildMetricTile(
                  context,
                  label: 'Load Avg',
                  value: metrics.load1m.toStringAsFixed(2),
                  icon: Icons.speed_outlined,
                  color: Colors.purple,
                );
                final uptimeTile = _buildMetricTile(
                  context,
                  label: 'Uptime',
                  value: metrics.formattedUptime,
                  icon: Icons.timer_outlined,
                  color: Colors.green,
                );

                if (isNarrow) {
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: cpuTile),
                          Expanded(child: ramTile),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: loadTile),
                          Expanded(child: uptimeTile),
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: cpuTile),
                    Expanded(child: ramTile),
                    Expanded(child: loadTile),
                    Expanded(child: uptimeTile),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
