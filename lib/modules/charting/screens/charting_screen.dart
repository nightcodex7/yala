// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import '../../system_monitoring/models/system_metrics.dart';
import '../services/metrics_chart_engine.dart';
import '../widgets/realtime_line_chart.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';

class ChartingScreen extends ConsumerWidget {
  const ChartingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsData = ref.watch(metricsChartEngineProvider);
    final engine = ref.read(metricsChartEngineProvider.notifier);

    final appState = ref.watch(appStateProvider);

    // Listen for periodic app state telemetry ticks to push samples safely without build-loop recursion
    ref.listen(appStateProvider, (previous, next) {
      final sysInfo = next.dashboardData?['sysInfo'] as Map<String, dynamic>?;
      final boardInfo =
          next.dashboardData?['boardInfo'] as Map<String, dynamic>?;
      final systemMetrics = SystemMetrics.fromSysInfo(
        sysInfo,
        boardInfo: boardInfo,
      );
      engine.addSample(
        cpuUsage: systemMetrics.cpuUsagePercent,
        ramUsage: systemMetrics.memoryUsagePercent,
        rxRate: next.currentRxRate,
        txRate: next.currentTxRate,
      );
    });

    if (metricsData.pollingIntervalSeconds !=
        appState.throughputIntervalSeconds) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        engine.updatePollingInterval(appState.throughputIntervalSeconds);
      });
    }

    // Seed initial sample if buffer is empty
    if (metricsData.cpuHistory.isEmpty) {
      final sysInfo =
          appState.dashboardData?['sysInfo'] as Map<String, dynamic>?;
      final boardInfo =
          appState.dashboardData?['boardInfo'] as Map<String, dynamic>?;
      final systemMetrics = SystemMetrics.fromSysInfo(
        sysInfo,
        boardInfo: boardInfo,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (metricsData.cpuHistory.isEmpty) {
          engine.addSample(
            cpuUsage: systemMetrics.cpuUsagePercent,
            ramUsage: systemMetrics.memoryUsagePercent,
            rxRate: appState.currentRxRate,
            txRate: appState.currentTxRate,
          );
        }
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Real-Time Metrics')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildConfigCard(context, ref, engine, metricsData),
          const SizedBox(height: 16),
          _buildChartCard(
            context,
            title: 'CPU Usage (%)',
            icon: Icons.memory,
            color: Colors.orange,
            chart: RealtimeLineChart(
              minY: 0,
              maxY: 100,
              maxPoints: metricsData.maxPoints,
              valueFormatter: (v) => '${v.toStringAsFixed(1)}%',
              series: [
                ChartSeriesData(
                  spots: metricsData.cpuHistory,
                  gradientColors: [
                    Colors.orange.shade700,
                    Colors.orange.shade300,
                  ],
                  label: 'CPU Usage',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildChartCard(
            context,
            title: 'RAM Usage (%)',
            icon: Icons.pie_chart,
            color: Colors.blue,
            chart: RealtimeLineChart(
              minY: 0,
              maxY: 100,
              maxPoints: metricsData.maxPoints,
              valueFormatter: (v) => '${v.toStringAsFixed(1)}%',
              series: [
                ChartSeriesData(
                  spots: metricsData.ramHistory,
                  gradientColors: [Colors.blue.shade700, Colors.blue.shade300],
                  label: 'RAM Usage',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildChartCard(
            context,
            title: 'Network RX / TX Throughput',
            icon: Icons.swap_vert,
            color: Colors.teal,
            chart: RealtimeLineChart(
              maxPoints: metricsData.maxPoints,
              valueFormatter: _formatSpeed,
              series: [
                ChartSeriesData(
                  spots: metricsData.txHistory,
                  gradientColors: [LuciColors.tx, LuciColors.txLight],
                  label: 'TX (Upload)',
                ),
                ChartSeriesData(
                  spots: metricsData.rxHistory,
                  gradientColors: [LuciColors.rx, LuciColors.rxLight],
                  label: 'RX (Download)',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildThroughputTableCard(context, appState),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildConfigCard(
    BuildContext context,
    WidgetRef ref,
    MetricsChartEngine engine,
    RealtimeMetricsData metricsData,
  ) {
    final theme = Theme.of(context);
    final currentInterval = metricsData.pollingIntervalSeconds;
    final currentWindow = metricsData.timeWindowSeconds;

    final windowOptions = [30, 60, 120, 300];

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Polling Engine Interval',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${currentInterval}s',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            Slider(
              value: currentInterval.toDouble(),
              min: 1.0,
              max: 10.0,
              divisions: 9,
              label: '${currentInterval}s',
              onChanged: (val) {
                final interval = val.toInt();
                engine.updatePollingInterval(interval);
                ref.read(appStateProvider).setThroughputInterval(interval);
              },
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Rolling Chart Window',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${currentWindow}s',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: windowOptions.map((opt) {
                final label = opt >= 60 ? '${opt ~/ 60}m' : '${opt}s';
                return ButtonSegment<int>(
                  value: opt,
                  label: Text(label, style: const TextStyle(fontSize: 12)),
                );
              }).toList(),
              selected: {currentWindow},
              onSelectionChanged: (Set<int> selected) {
                if (selected.isNotEmpty) {
                  engine.updateTimeWindow(selected.first);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required Widget chart,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            chart,
          ],
        ),
      ),
    );
  }

  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond <= 0) return '0 bps';
    final bits = bytesPerSecond * 8;
    if (bits < 1000) return '${bits.toStringAsFixed(0)} bps';
    if (bits < 1000000) return '${(bits / 1000).toStringAsFixed(1)} Kbps';
    return '${(bits / 1000000).toStringAsFixed(2)} Mbps';
  }

  Widget _buildThroughputTableCard(BuildContext context, dynamic appState) {
    final devices =
        appState.dashboardData?['networkDevices'] as Map<String, dynamic>?;
    final statsMap = <String, Map<String, num>>{};

    if (devices != null) {
      devices.forEach((devName, devData) {
        if (devData is Map<String, dynamic> && devData['stats'] is Map) {
          final rawStats = devData['stats'] as Map;
          statsMap[devName] = {
            'rx_bytes': (rawStats['rx_bytes'] as num?) ?? 0,
            'tx_bytes': (rawStats['tx_bytes'] as num?) ?? 0,
            'rx_packets': (rawStats['rx_packets'] as num?) ?? 0,
            'tx_packets': (rawStats['tx_packets'] as num?) ?? 0,
            'rx_errors': (rawStats['rx_errors'] as num?) ?? 0,
            'tx_errors': (rawStats['tx_errors'] as num?) ?? 0,
          };
        }
      });
    }

    if (statsMap.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

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
                  Icons.table_chart_outlined,
                  size: 20,
                  color: Colors.teal,
                ),
                const SizedBox(width: 8),
                Text(
                  'RX/TX Throughput Metrics (Tabular)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 44,
                dataRowMaxHeight: 44,
                columns: const [
                  DataColumn(
                    label: Text(
                      'Device',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'RX Bytes',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'TX Bytes',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'RX Packets',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'TX Packets',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Errors',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                rows: statsMap.entries.map((entry) {
                  final stats = entry.value;
                  final rxBytes = _formatBytes(stats['rx_bytes'] ?? 0);
                  final txBytes = _formatBytes(stats['tx_bytes'] ?? 0);
                  final rxPackets = stats['rx_packets']?.toString() ?? '0';
                  final txPackets = stats['tx_packets']?.toString() ?? '0';
                  final errors =
                      (stats['rx_errors'] ?? 0) + (stats['tx_errors'] ?? 0);

                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          entry.key,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      DataCell(Text(rxBytes)),
                      DataCell(Text(txBytes)),
                      DataCell(Text(rxPackets)),
                      DataCell(Text(txPackets)),
                      DataCell(
                        Text(
                          '$errors',
                          style: TextStyle(
                            color: errors > 0 ? Colors.red : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(num bytes) {
    if (bytes <= 0) return '0 B';
    final double b = bytes.toDouble();
    if (b >= 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (b >= 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (b >= 1024) {
      return '${(b / 1024).toStringAsFixed(0)} KB';
    }
    return '${b.toStringAsFixed(0)} B';
  }
}
