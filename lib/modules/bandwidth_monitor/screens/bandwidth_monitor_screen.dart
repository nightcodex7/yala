// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/modules/bandwidth_monitor/controllers/bandwidth_monitor_controller.dart';
import 'package:yet_another_luci_app/modules/bandwidth_monitor/models/bandwidth_data.dart';
import 'package:yet_another_luci_app/modules/core/luci_module_registry.dart';
import 'package:yet_another_luci_app/modules/bandwidth_monitor/screens/bandwidth_throttling_summary_screen.dart';
import 'package:yet_another_luci_app/widgets/luci_app_bar.dart';
import 'package:yet_another_luci_app/widgets/luci_refresh_components.dart';

class BandwidthMonitorScreen extends ConsumerStatefulWidget {
  const BandwidthMonitorScreen({super.key});

  @override
  ConsumerState<BandwidthMonitorScreen> createState() =>
      _BandwidthMonitorScreenState();
}

class _BandwidthMonitorScreenState extends ConsumerState<BandwidthMonitorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _expandedMacs = {};
  String _usageFilter = 'all'; // 'all', 'connected', 'offline'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bandwidthMonitorProvider);
    final controller = ref.read(bandwidthMonitorProvider.notifier);
    final speedUnit = ref.watch(
      appStateProvider.select((s) => s.dashboardPreferences.speedUnit),
    );
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: LuciAppBar(
        title: l10n?.modBandwidthMonitorName ?? 'Bandwidth Monitor',
        showBack: true,
        actions: [
          IconButton(
            icon: Icon(
              state.isStreaming
                  ? Icons.pause_circle_outline_rounded
                  : Icons.play_circle_outline_rounded,
              color: state.isStreaming ? colorScheme.primary : Colors.grey,
            ),
            tooltip: state.isStreaming
                ? (l10n?.bandwidthPauseStream ?? 'Pause Live Stream')
                : (l10n?.bandwidthResumeStream ?? 'Resume Live Stream'),
            onPressed: () => controller.toggleStreaming(),
          ),
          IconButton(
            icon: const Icon(Icons.traffic_rounded),
            tooltip: l10n?.bandwidthThrottlingTooltip ?? 'Bandwidth Throttling',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (ctx) => const BandwidthThrottlingSummaryScreen(),
                ),
              );
            },
          ),
          PopupMenuButton<int>(
            icon: const Icon(Icons.timer_outlined),
            tooltip: 'Polling Interval',
            initialValue: state.pollingIntervalSeconds,
            onSelected: (val) => controller.setPollingInterval(val),
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 1, child: Text('1s Interval')),
              const PopupMenuItem(value: 2, child: Text('2s Interval')),
              const PopupMenuItem(value: 3, child: Text('3s Interval')),
              const PopupMenuItem(value: 5, child: Text('5s Interval')),
            ],
          ),
        ],
      ),
      body: LuciPullToRefresh(
        onRefresh: () async {
          await controller.refreshData();
        },
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: _buildHeaderSummary(
                  context,
                  state,
                  speedUnit,
                  l10n,
                  colorScheme,
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverTabBarDelegate(
                TabBar(
                  controller: _tabController,
                  labelColor: colorScheme.primary,
                  unselectedLabelColor: colorScheme.onSurfaceVariant,
                  indicatorColor: colorScheme.primary,
                  indicatorSize: TabBarIndicatorSize.tab,
                  tabs: [
                    Tab(
                      icon: const Icon(Icons.devices_rounded, size: 18),
                      text: l10n?.bandwidthLiveDevices ?? 'Live Devices',
                    ),
                    Tab(
                      icon: const Icon(Icons.analytics_outlined, size: 18),
                      text: l10n?.bandwidthUsageStats ?? 'Usage Stats',
                    ),
                  ],
                ),
                colorScheme.surface,
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildLiveDevicesTab(
                context,
                state,
                controller,
                speedUnit,
                l10n,
                colorScheme,
              ),
              _buildUsageStatsTab(
                context,
                state,
                controller,
                l10n,
                colorScheme,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSummary(
    BuildContext context,
    BandwidthMonitorState state,
    String speedUnit,
    AppLocalizations? l10n,
    ColorScheme colorScheme,
  ) {
    final summary = state.summary;
    final isStreaming = state.isStreaming;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isStreaming ? Colors.green : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isStreaming ? 'STREAMING LIVE' : 'STREAM PAUSED',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: isStreaming ? Colors.green : Colors.grey,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${state.pollingIntervalSeconds}s interval • ${summary.connectedDevicesCount} devices',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _buildMetricBlock(
                    label: l10n?.bandwidthTotalDownload ?? 'Download',
                    value: summary.formattedDownloadSpeed(speedUnit),
                    icon: Icons.arrow_downward_rounded,
                    color: Colors.teal,
                    peakValue: summary.formattedPeakDownload(speedUnit),
                  ),
                ),
                Container(
                  width: 1,
                  height: 48,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
                Expanded(
                  child: _buildMetricBlock(
                    label: l10n?.bandwidthTotalUpload ?? 'Upload',
                    value: summary.formattedUploadSpeed(speedUnit),
                    icon: Icons.arrow_upward_rounded,
                    color: Colors.orange.shade700,
                    peakValue: summary.formattedPeakUpload(speedUnit),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricBlock({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required String peakValue,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Peak: $peakValue',
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildLiveDevicesTab(
    BuildContext context,
    BandwidthMonitorState state,
    BandwidthMonitorController controller,
    String speedUnit,
    AppLocalizations? l10n,
    ColorScheme colorScheme,
  ) {
    if (state.isLoading && state.devices.isEmpty) {
      return const LuciLoadingWidget();
    }

    final devices = state.filteredAndSortedDevices;

    return ListView(
      key: const PageStorageKey('live_devices_tab'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // Search & Filter controls
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => controller.setSearchQuery(val),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText:
                        l10n?.bandwidthSearchPlaceholder ??
                        'Search devices by name, IP, MAC...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              controller.setSearchQuery('');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 0,
                    ),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<BandwidthSortMode>(
              icon: Icon(Icons.sort_rounded, color: colorScheme.primary),
              tooltip: 'Sort by',
              initialValue: state.sortMode,
              onSelected: (mode) => controller.setSortMode(mode),
              itemBuilder: (ctx) => [
                CheckedPopupMenuItem(
                  value: BandwidthSortMode.name,
                  checked: state.sortMode == BandwidthSortMode.name,
                  child: Text(
                    l10n?.bandwidthSortName ?? 'Device Name',
                    style: TextStyle(
                      fontWeight: state.sortMode == BandwidthSortMode.name
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: state.sortMode == BandwidthSortMode.name
                          ? colorScheme.primary
                          : null,
                    ),
                  ),
                ),
                CheckedPopupMenuItem(
                  value: BandwidthSortMode.downloadSpeed,
                  checked: state.sortMode == BandwidthSortMode.downloadSpeed,
                  child: Text(
                    l10n?.bandwidthSortDownload ?? 'Highest Download',
                    style: TextStyle(
                      fontWeight:
                          state.sortMode == BandwidthSortMode.downloadSpeed
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: state.sortMode == BandwidthSortMode.downloadSpeed
                          ? colorScheme.primary
                          : null,
                    ),
                  ),
                ),
                CheckedPopupMenuItem(
                  value: BandwidthSortMode.uploadSpeed,
                  checked: state.sortMode == BandwidthSortMode.uploadSpeed,
                  child: Text(
                    l10n?.bandwidthSortUpload ?? 'Highest Upload',
                    style: TextStyle(
                      fontWeight:
                          state.sortMode == BandwidthSortMode.uploadSpeed
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: state.sortMode == BandwidthSortMode.uploadSpeed
                          ? colorScheme.primary
                          : null,
                    ),
                  ),
                ),
                CheckedPopupMenuItem(
                  value: BandwidthSortMode.totalUsage,
                  checked: state.sortMode == BandwidthSortMode.totalUsage,
                  child: Text(
                    l10n?.bandwidthSortTotal ?? 'Highest Total Data',
                    style: TextStyle(
                      fontWeight: state.sortMode == BandwidthSortMode.totalUsage
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: state.sortMode == BandwidthSortMode.totalUsage
                          ? colorScheme.primary
                          : null,
                    ),
                  ),
                ),
                CheckedPopupMenuItem(
                  value: BandwidthSortMode.ip,
                  checked: state.sortMode == BandwidthSortMode.ip,
                  child: Text(
                    l10n?.bandwidthSortIp ?? 'IP Address',
                    style: TextStyle(
                      fontWeight: state.sortMode == BandwidthSortMode.ip
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: state.sortMode == BandwidthSortMode.ip
                          ? colorScheme.primary
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (devices.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: LuciEmptyState(
              icon: Icons.devices_other,
              title: state.searchQuery.isEmpty
                  ? (l10n?.bandwidthNoDevicesFound ?? 'No Connected Devices')
                  : (l10n?.bandwidthNoMatchingDevices ?? 'No Matching Devices'),
              message: state.searchQuery.isEmpty
                  ? 'No active client devices are currently reporting traffic.'
                  : 'Try searching with a different device name, IP, or MAC.',
            ),
          )
        else
          ...devices.map(
            (item) =>
                _buildDeviceCard(context, item, speedUnit, colorScheme, l10n),
          ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildDeviceCard(
    BuildContext context,
    DeviceBandwidthItem item,
    String speedUnit,
    ColorScheme colorScheme,
    AppLocalizations? l10n,
  ) {
    final isExpanded = _expandedMacs.contains(item.macAddress);
    final hasActiveTraffic = item.hasActiveSpeed;

    return Card(
      elevation: isExpanded ? 2.5 : 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: hasActiveTraffic
            ? BorderSide(color: Colors.teal.withValues(alpha: 0.4), width: 1.2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedMacs.remove(item.macAddress);
            } else {
              _expandedMacs.add(item.macAddress);
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: item.isWireless
                          ? colorScheme.primary.withValues(alpha: 0.12)
                          : colorScheme.secondary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      item.isWireless
                          ? Icons.wifi_rounded
                          : Icons.settings_ethernet_rounded,
                      size: 20,
                      color: item.isWireless
                          ? colorScheme.primary
                          : colorScheme.secondary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                item.ipAddress,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (item.ssid != null && item.ssid!.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text(
                                '•',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  item.ssid!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Live Speed Pills
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: hasActiveTraffic
                              ? Colors.teal.withValues(alpha: 0.14)
                              : colorScheme.surfaceContainerHighest.withValues(
                                  alpha: 0.4,
                                ),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: hasActiveTraffic
                                ? Colors.teal.withValues(alpha: 0.4)
                                : Colors.transparent,
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.arrow_downward_rounded,
                              size: 11,
                              color: Colors.teal,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              item.formattedDownloadSpeed(speedUnit),
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: hasActiveTraffic
                              ? Colors.orange.withValues(alpha: 0.14)
                              : colorScheme.surfaceContainerHighest.withValues(
                                  alpha: 0.4,
                                ),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: hasActiveTraffic
                                ? Colors.orange.withValues(alpha: 0.4)
                                : Colors.transparent,
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.arrow_upward_rounded,
                              size: 11,
                              color: Colors.orange.shade700,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              item.formattedUploadSpeed(speedUnit),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Expanded details
              if (isExpanded) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildDetailRow('MAC Address', item.macAddress),
                    ),
                    if (item.formattedPhyRate != null)
                      Expanded(
                        child: _buildDetailRow(
                          'Link Rate (PHY)',
                          item.formattedPhyRate!,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: _buildDetailRow(
                        'Session Transfer',
                        '↓ ${item.formattedTotalDownloaded}  ↑ ${item.formattedTotalUploaded}',
                      ),
                    ),
                    Expanded(
                      child: _buildDetailRow(
                        'Peak Speed',
                        '↓ ${item.formattedPeakDownload(speedUnit)}  ↑ ${item.formattedPeakUpload(speedUnit)}',
                      ),
                    ),
                  ],
                ),
                if (item.formattedConnectedTime != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDetailRow(
                          'Connection Duration',
                          item.formattedConnectedTime!,
                        ),
                      ),
                    ],
                  ),
                ],
                if (item.signalDbm != null ||
                    item.activeConnections != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (item.signalDbm != null)
                        Expanded(
                          child: _buildDetailRow(
                            'Signal',
                            '${item.signalDbm} dBm (${item.signalQuality ?? ""})',
                          ),
                        ),
                      if (item.activeConnections != null)
                        Expanded(
                          child: _buildDetailRow(
                            'Active Connections',
                            '${item.activeConnections} conns',
                          ),
                        ),
                    ],
                  ),
                ],
                if (item.topProtocol != null) ...[
                  const SizedBox(height: 4),
                  _buildDetailRow(
                    'Primary Layer 7 Protocol',
                    item.topProtocol!,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
        Text(
          value,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildUsageStatsTab(
    BuildContext context,
    BandwidthMonitorState state,
    BandwidthMonitorController controller,
    AppLocalizations? l10n,
    ColorScheme colorScheme,
  ) {
    if (state.isLoading &&
        state.usageStats.isEmpty &&
        state.nlbwmonReport == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final knownClients = ref.read(appStateProvider).clients;

    // Use state.usageStats if populated, otherwise construct from nlbwmonReport/knownClients
    final List<UsageStatsItem> allUsage;
    if (state.usageStats.isNotEmpty) {
      allUsage = state.usageStats;
    } else if (state.nlbwmonReport != null &&
        state.nlbwmonReport!.records.isNotEmpty) {
      allUsage = state.nlbwmonReport!.records.map((rec) {
        final normMac = rec.mac.toUpperCase().replaceAll('-', ':');
        Client? matchingClient;
        for (final c in knownClients) {
          if (c.normalizedMac == normMac ||
              (rec.ip != null && c.ipAddress == rec.ip)) {
            matchingClient = c;
            break;
          }
        }
        return UsageStatsItem(
          mac: rec.mac,
          ip: rec.ip ?? matchingClient?.ipAddress,
          displayName:
              matchingClient?.displayName ??
              (rec.ip != null ? rec.ip! : rec.mac),
          isConnected: matchingClient?.isConnected ?? false,
          downloadBytes: rec.rxBytes,
          uploadBytes: rec.txBytes,
          totalBytes: rec.totalBytes,
          conns: rec.conns,
          layer7: rec.layer7,
          connectionType:
              matchingClient?.connectionType ?? ConnectionType.unknown,
          fromNlbwmon: true,
        );
      }).toList();
    } else {
      allUsage = const [];
    }

    // Filter items based on selected tab chip: 'all', 'connected', 'offline'
    final filteredItems = allUsage.where((item) {
      if (_usageFilter == 'connected') return item.isConnected;
      if (_usageFilter == 'offline') return !item.isConnected;
      return true;
    }).toList();

    final totalCount = allUsage.length;
    final connectedCount = allUsage.where((i) => i.isConnected).length;
    final offlineCount = allUsage.where((i) => !i.isConnected).length;

    final periodVal =
        (state.selectedPeriod != null &&
            state.nlbwmonPeriods.contains(state.selectedPeriod))
        ? state.selectedPeriod
        : null;

    return ListView(
      key: const PageStorageKey('usage_stats_tab'),
      padding: const EdgeInsets.all(16),
      children: [
        // If nlbwmon is NOT installed: show an informational banner while still rendering session stats
        if (!state.isNlbwmonInstalled)
          Card(
            elevation: 0,
            color: Colors.blue.withValues(alpha: 0.08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Colors.blue.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: Colors.blue,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Session Bandwidth Usage',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n?.bandwidthNlbwmonNotInstalledDesc ??
                              'Install luci-app-nlbwmon to track persistent monthly usage across reboots.',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      final registry = LuciModuleRegistry.instance;
                      final packageModule = registry.getModule(
                        'package_manager',
                      );
                      if (packageModule != null && context.mounted) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (ctx) => packageModule.buildScreen(ctx),
                          ),
                        );
                      }
                    },
                    child: Text(
                      l10n?.bandwidthInstallNlbwmon ?? 'Install',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Period selector if nlbwmon is installed and has periods
        if (state.isNlbwmonInstalled && state.nlbwmonPeriods.isNotEmpty)
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_outlined, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Period: ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String?>(
                    value: periodVal,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    borderRadius: BorderRadius.circular(16),
                    dropdownColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHigh,
                    elevation: 4,
                    menuMaxHeight: 360,
                    icon: const Icon(Icons.arrow_drop_down_rounded),
                    hint: const Text('Current Period'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Current Period'),
                      ),
                      ...state.nlbwmonPeriods.map(
                        (p) => DropdownMenuItem(value: p, child: Text(p)),
                      ),
                    ],
                    onChanged: (val) => controller.setSelectedPeriod(val),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),

        // Filter chips: All, Connected, Not Connected
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                label: Text('All ($totalCount)'),
                selected: _usageFilter == 'all',
                onSelected: (sel) {
                  if (sel) setState(() => _usageFilter = 'all');
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                avatar: const Icon(Icons.circle, size: 9, color: Colors.green),
                label: Text('Connected ($connectedCount)'),
                selected: _usageFilter == 'connected',
                onSelected: (sel) {
                  if (sel) setState(() => _usageFilter = 'connected');
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                avatar: const Icon(
                  Icons.circle_outlined,
                  size: 9,
                  color: Colors.grey,
                ),
                label: Text('Not Connected ($offlineCount)'),
                selected: _usageFilter == 'offline',
                onSelected: (sel) {
                  if (sel) setState(() => _usageFilter = 'offline');
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Host Accounting Card
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      state.isNlbwmonInstalled
                          ? (l10n?.bandwidthNlbwmonTitle ??
                                'Persistent Bandwidth Accounting (nlbwmon)')
                          : 'Device Bandwidth Usage',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${filteredItems.length} devices',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (filteredItems.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        _usageFilter == 'offline'
                            ? 'No disconnected/offline devices found with recorded usage.'
                            : (_usageFilter == 'connected'
                                  ? 'No connected devices currently found.'
                                  : 'No usage records found for this period.'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  ...filteredItems.map((item) {
                    final isMacName =
                        item.displayName.toUpperCase().replaceAll('-', ':') ==
                        item.mac.toUpperCase().replaceAll('-', ':');
                    final isIpName =
                        item.ip != null &&
                        item.ip!.isNotEmpty &&
                        item.displayName.trim() == item.ip!.trim();
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: item.isConnected
                                  ? Colors.green
                                  : Colors.grey.shade400,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 4,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.displayName,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (!isMacName) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    item.mac,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                if (item.ip != null &&
                                    item.ip!.isNotEmpty &&
                                    !isIpName) ...[
                                  const SizedBox(height: 1.5),
                                  Text(
                                    item.ip!,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (item.conns > 0 || item.layer7 != null) ...[
                            const SizedBox(width: 4),
                            Text(
                              item.layer7 != null
                                  ? '${item.conns}c • ${item.layer7}'
                                  : '${item.conns} conns',
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                item.formattedTotalBytes,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.arrow_downward_rounded,
                                    size: 10,
                                    color: Colors.teal,
                                  ),
                                  Text(
                                    item.formattedDownloadBytes,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.teal,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.arrow_upward_rounded,
                                    size: 10,
                                    color: Colors.orange.shade700,
                                  ),
                                  Text(
                                    item.formattedUploadBytes,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.orange.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color backgroundColor;

  _SliverTabBarDelegate(this.tabBar, this.backgroundColor);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: backgroundColor, child: tabBar);
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return tabBar != oldDelegate.tabBar ||
        backgroundColor != oldDelegate.backgroundColor;
  }
}
