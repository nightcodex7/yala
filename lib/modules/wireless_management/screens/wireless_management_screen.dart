// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/utils/os_platform_integration.dart';
import 'package:yet_another_luci_app/modules/dhcp_dns/models/dhcp_dns_info.dart';
import 'package:yet_another_luci_app/widgets/luci_app_bar.dart';
import 'package:yet_another_luci_app/widgets/luci_collapsible_card.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import '../models/wireless_info.dart';
import '../widgets/wireless_interface_card.dart';
import '../widgets/edit_radio_dialog.dart';
import '../widgets/add_ssid_dialog.dart';
import 'package:yet_another_luci_app/widgets/luci_guardrail.dart';
import '../widgets/wireless_rollback_banner.dart';
import 'wifi_access_control_screen.dart';
import 'guest_wifi_management_screen.dart';

class WirelessManagementScreen extends ConsumerStatefulWidget {
  final bool showBack;
  final bool isTabActive;

  const WirelessManagementScreen({
    super.key,
    this.showBack = false,
    this.isTabActive = true,
  });

  @override
  ConsumerState<WirelessManagementScreen> createState() =>
      _WirelessManagementScreenState();
}

class _WirelessManagementScreenState
    extends ConsumerState<WirelessManagementScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  Timer? _refreshTimer;
  bool _isStationsExpanded = false;
  bool _migrationChecked = false;
  Widget? _lastRenderedWidget;
  String? _lastSelectedRouterId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startRefreshTimerIfNeeded();
    // Run migration check after first frame so BuildContext is fully mounted
    WidgetsBinding.instance.addPostFrameCallback((_) => _runMigrationCheck());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Checks for and auto-fixes any anonymous wifi-iface sections (cfg######)
  /// that would trigger LuCI's "Wireless configuration migration" dialog.
  Future<void> _runMigrationCheck() async {
    if (_migrationChecked || !mounted) return;
    _migrationChecked = true;

    final appState = ref.read(appStateProvider);
    final migrated = await appState.migrateAnonymousWirelessSections();

    if (migrated > 0 && mounted) {
      context.showToastSuccess(
        'Auto-fixed $migrated anonymous wireless section${migrated > 1 ? 's' : ''}',
        subtitle:
            'Renamed to wifinet# — LuCI migration dialog will no longer appear.',
      );
      // Refresh so the UI picks up the new section names
      await appState.fetchDashboardData();
    }
  }

  void _startRefreshTimerIfNeeded() {
    _refreshTimer?.cancel();
    if (_isStationsExpanded && widget.isTabActive) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted) {
          ref.read(appStateProvider).fetchDashboardData();
        }
      });
    }
  }

  void _toggleStationsExpansion(bool expanded) {
    if (_isStationsExpanded != expanded) {
      setState(() {
        _isStationsExpanded = expanded;
      });
      _startRefreshTimerIfNeeded();
    }
  }

  @override
  void didUpdateWidget(WirelessManagementScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isTabActive != oldWidget.isTabActive) {
      if (widget.isTabActive) {
        _lastRenderedWidget = null;
        _startRefreshTimerIfNeeded();
      } else {
        _refreshTimer?.cancel();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (widget.isTabActive &&
          _isStationsExpanded &&
          (_refreshTimer == null || !_refreshTimer!.isActive)) {
        _startRefreshTimerIfNeeded();
        ref.read(appStateProvider).fetchDashboardData();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _refreshTimer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final appState = ref.watch(appStateProvider);
    final currentRouterId = appState.selectedRouter?.id;
    if (currentRouterId != _lastSelectedRouterId) {
      _lastSelectedRouterId = currentRouterId;
      _lastRenderedWidget = null;
    }

    if (!widget.isTabActive && _lastRenderedWidget != null) {
      return _lastRenderedWidget!;
    }

    final overview = WirelessOverview.fromDashboardData(
      appState.dashboardData,
      isReviewerMode: appState.reviewerModeEnabled,
    );

    int totalStationCount = 0;
    for (final radio in overview.radios) {
      for (final iface in radio.interfaces) {
        totalStationCount += iface.stations.length;
      }
    }

    final hasGuestNetworks = overview.radios.any(
      (radio) => radio.interfaces.any(
        (iface) => iface.isGuestInterface(
          appState.customGuestSections,
          appState.excludedGuestSections,
        ),
      ),
    );

    final scaffold = Scaffold(
      appBar: LuciAppBar(title: 'Wireless', showBack: widget.showBack),
      body: Column(
        children: [
          const WirelessRollbackBanner(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await appState.fetchDashboardData();
              },
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  // Top Summary Header & Action Bar
                  _buildWirelessHeaderCard(
                    context,
                    overview,
                    hasGuestNetworks,
                  ),
                  const SizedBox(height: 14),
                  if (overview.radios.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32.0),
                      child: LuciEmptyState(
                        title: 'No Wireless Radios Found',
                        message:
                            'No active wireless devices or radios were detected on this router. Pull down to refresh data.',
                        icon: Icons.wifi_off_rounded,
                        actionLabel: 'Refresh',
                        onAction: () async {
                          await appState.fetchDashboardData();
                        },
                      ),
                    )
                  else
                    ...overview.radios.map(
                      (radio) =>
                          _buildRadioCard(context, radio, overview, appState),
                    ),
                  const SizedBox(height: 16),
                  LuciCollapsibleCard(
                    title: 'Connected Wireless Stations',
                    icon: Icons.devices_other_outlined,
                    count: totalStationCount,
                    initiallyExpanded: _isStationsExpanded,
                    onExpansionChanged: _toggleStationsExpansion,
                    child: _buildStationsList(context, overview, appState),
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    final Widget result;
    if (widget.showBack || appState.isAccessControlPendingConfirmation) {
      result = PopScope(
        canPop: widget.showBack && !appState.isAccessControlPendingConfirmation,
        onPopInvokedWithResult: (didPop, popResult) async {
          if (didPop) return;
          final canExit = await LuciGuardrail.confirmStagedChangesOrExit(
            context,
            appState,
          );
          if (canExit && context.mounted) {
            if (widget.showBack && Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          }
        },
        child: scaffold,
      );
    } else {
      result = scaffold;
    }
    _lastRenderedWidget = result;
    return result;
  }

  Widget _buildWirelessHeaderCard(
    BuildContext context,
    WirelessOverview overview,
    bool hasGuestNetworks,
  ) {
    final theme = Theme.of(context);

    int totalSsidCount = 0;
    for (final r in overview.radios) {
      totalSsidCount += r.interfaces.length;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.cell_tower_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Wireless Overview',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              // Mini Summary Metrics Badges
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${overview.radios.length} Radios • $totalSsidCount SSIDs',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const GuestWifiManagementScreen(),
                      ),
                    );
                  },
                  icon: Icon(
                    Icons.shield_moon_rounded,
                    size: 16,
                    color: hasGuestNetworks
                        ? theme.colorScheme.onTertiaryContainer
                        : theme.colorScheme.onSecondary,
                  ),
                  label: Text(
                    'Guest Networks',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: hasGuestNetworks
                          ? theme.colorScheme.onTertiaryContainer
                          : theme.colorScheme.onSecondary,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: hasGuestNetworks
                        ? theme.colorScheme.tertiaryContainer
                        : theme.colorScheme.secondary,
                    side: BorderSide(
                      color: (hasGuestNetworks
                              ? theme.colorScheme.tertiary
                              : theme.colorScheme.secondary)
                          .withValues(alpha: 0.3),
                      width: 0.8,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const WifiAccessControlScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.security_rounded, size: 16),
                  label: const Text(
                    'Access Control',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getBandColor(String bandLabel, ColorScheme colorScheme) {
    final lower = bandLabel.toLowerCase();
    if (lower.contains('2.4')) return colorScheme.secondary;
    if (lower.contains('5')) return colorScheme.primary;
    if (lower.contains('6')) return colorScheme.tertiary;
    return colorScheme.primary;
  }

  Widget _buildRadioCard(
    BuildContext context,
    WirelessRadio radio,
    WirelessOverview overview,
    AppState appState,
  ) {
    final theme = Theme.of(context);
    final freqStr = radio.formattedFrequency ?? 'Ch ${radio.channel}';
    final bandColor = _getBandColor(radio.bandLabel, theme.colorScheme);

    final regularIfaces = radio.interfaces
        .where(
          (i) => !i.isGuestInterface(
            appState.customGuestSections,
            appState.excludedGuestSections,
          ),
        )
        .toList();
    final guestIfaces = radio.interfaces
        .where(
          (i) => i.isGuestInterface(
            appState.customGuestSections,
            appState.excludedGuestSections,
          ),
        )
        .toList();

    final minimalSummary = radio.isUp
        ? '${radio.bandLabel} • Ch ${radio.channel} • ${radio.interfaces.length} SSID${radio.interfaces.length == 1 ? '' : 's'} (${regularIfaces.length} main, ${guestIfaces.length} guest)'
        : 'DISABLED • ${radio.bandLabel} • Ch ${radio.channel}';

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          childrenPadding: const EdgeInsets.only(
            left: 14,
            right: 14,
            bottom: 14,
          ),
          leading: CircleAvatar(
            backgroundColor: bandColor.withValues(alpha: 0.15),
            child: Icon(Icons.wifi, color: bandColor),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    radio.name.toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: radio.isUp
                      ? LuciStatusColors.connected.withValues(alpha: 0.15)
                      : Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  radio.isUp ? 'ACTIVE' : 'DISABLED',
                  style: TextStyle(
                    color: radio.isUp ? LuciStatusColors.connected : Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 9.0,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              minimalSummary,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11.5,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded, size: 19),
                tooltip: 'Add Virtual SSID Interface',
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                onPressed: () =>
                    _showAddSsidDialog(context, overview.radios, radio),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.settings_outlined, size: 19),
                tooltip: 'Edit Physical Radio Settings',
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                onPressed: () => _showEditRadioDialog(context, radio),
              ),
            ],
          ),
          children: [
            const SizedBox(height: 4),
            // Sleek Horizontal Radio Spec Pills
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.35,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildRadioMetricPill(
                      context,
                      'TX Power',
                      '${radio.txPowerDbm ?? 20} dBm',
                      Icons.bolt_rounded,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _buildRadioMetricPill(
                      context,
                      'Frequency',
                      freqStr,
                      Icons.graphic_eq_rounded,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _buildRadioMetricPill(
                      context,
                      'Country',
                      radio.country,
                      Icons.public_rounded,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (regularIfaces.isNotEmpty) ...[
              Row(
                children: [
                  Icon(
                    Icons.wifi_rounded,
                    size: 15,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Primary Networks & SSIDs',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${regularIfaces.length}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ...regularIfaces.map(
                (iface) => WirelessInterfaceCard(
                  radio: radio,
                  interface: iface,
                  onToggleEnabled: (val) =>
                      _handleToggleSsid(context, radio, iface, val, appState),
                ),
              ),
            ],
            if (guestIfaces.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.shield_moon_rounded,
                    size: 15,
                    color: theme.colorScheme.tertiary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Guest Networks & SSIDs',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${guestIfaces.length}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ...guestIfaces.map(
                (iface) => WirelessInterfaceCard(
                  radio: radio,
                  interface: iface,
                  onToggleEnabled: (val) =>
                      _handleToggleSsid(context, radio, iface, val, appState),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRadioMetricPill(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.primary),
        const SizedBox(width: 5),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 9.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleToggleSsid(
    BuildContext context,
    WirelessRadio radio,
    WirelessInterface iface,
    bool enable,
    AppState appState,
  ) async {
    bool isConnectedToThisSsid = false;
    // Check if any connected client station matches active app session or router connection
    for (final st in iface.stations) {
      if (st.macAddress.toUpperCase() ==
          (appState.dashboardData?['activeSessionMac']
              ?.toString()
              .toUpperCase())) {
        isConnectedToThisSsid = true;
        break;
      }
    }

    // Guard rail: Prevent disabling the last enabled SSID on a radio (would lose all wireless access)
    if (!enable) {
      final enabledInterfacesOnRadio = radio.interfaces
          .where((i) => i.mode.toLowerCase() == 'ap' && i.isEnabled)
          .toList();

      if (enabledInterfacesOnRadio.length == 1 &&
          enabledInterfacesOnRadio.first.sectionName == iface.sectionName) {
        if (!context.mounted) return;
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.block_rounded, color: Colors.red, size: 36),
            title: const Text('Cannot Disable Last SSID'),
            content: Text(
              'Disabling "${iface.ssid}" would leave no active wireless networks on ${radio.name} (${radio.bandLabel}). '
              'You would lose all wireless connectivity. Please enable another SSID first or keep this one enabled.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
    }

    if (!enable && isConnectedToThisSsid) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(
            Icons.warning_amber_rounded,
            color: Colors.orange,
            size: 36,
          ),
          title: const Text('Self-Disconnect Warning'),
          content: Text(
            'You\'re currently connected via network "${iface.ssid}". Disabling it will disconnect your session; the app will attempt to reconnect automatically once you rejoin a working network.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Proceed & Disconnect'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${enable ? "Enable" : "Disable"} SSID?'),
          content: Text(
            'Are you sure you want to ${enable ? "enable" : "disable"} SSID "${iface.ssid}" on ${radio.name}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(enable ? 'Enable' : 'Disable'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final actionKey = 'toggle_ssid_${iface.sectionName}';
    if (!context.mounted) return;
    context.showToastLoading(
      '${enable ? "Enabling" : "Disabling"} SSID "${iface.ssid}"...',
      actionKey: actionKey,
    );

    final success = await appState.setSsidEnabled(
      iface.sectionName,
      enable,
      context: context,
    );

    if (!context.mounted) return;
    if (success) {
      unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.medium));
      context.showToastSuccess(
        'SSID "${iface.ssid}" ${enable ? "enabled" : "disabled"} successfully.',
        actionKey: actionKey,
      );
    } else {
      unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));
      context.showToastError(
        'Failed to update SSID "${iface.ssid}".',
        actionKey: actionKey,
      );
    }
  }

  Widget _buildStationsList(
    BuildContext context,
    WirelessOverview overview,
    AppState appState,
  ) {
    final dhcpOverview = DhcpDnsOverview.fromDashboardData(
      appState.dashboardData,
      isReviewerMode: appState.reviewerModeEnabled,
    );

    final allStations = <Map<String, dynamic>>[];
    for (final radio in overview.radios) {
      for (final iface in radio.interfaces) {
        for (final st in iface.stations) {
          allStations.add({
            'station': st,
            'ssid': iface.ssid,
            'band': radio.bandLabel,
          });
        }
      }
    }

    allStations.sort((a, b) {
      final stA = a['station'] as WirelessStation;
      final stB = b['station'] as WirelessStation;
      final aSig = stA.signalDbm ?? -999;
      final bSig = stB.signalDbm ?? -999;
      return aSig.compareTo(bSig); // Higher dBm station at bottom of list
    });

    if (allStations.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(child: Text('No wireless stations connected.')),
        ),
      );
    }

    String normMac(String m) => m
        .toUpperCase()
        .replaceAll('-', ':')
        .split(':')
        .map((b) => b.length == 1 ? '0$b' : b)
        .join(':');

    String? resolveHostname(String macStr) {
      final macNorm = normMac(macStr);
      for (final st in dhcpOverview.staticMappings) {
        if (normMac(st.macAddress) == macNorm &&
            st.hostname.isNotEmpty &&
            st.hostname != 'Unnamed Host') {
          return st.hostname;
        }
      }
      for (final l in dhcpOverview.activeLeases) {
        if (normMac(l.macAddress) == macNorm &&
            l.hostname.isNotEmpty &&
            l.hostname != 'Anonymous Device') {
          return l.hostname;
        }
      }
      return null;
    }

    return Column(
      children: allStations.map((item) {
        final st = item['station'] as WirelessStation;
        final ssid = item['ssid'] as String;
        final band = item['band'] as String;

        final hostname = resolveHostname(st.macAddress);
        final hasName =
            hostname != null &&
            hostname.isNotEmpty &&
            normMac(hostname) != normMac(st.macAddress);
        final titleText = hasName ? hostname : st.macAddress;
        final subtitleText = hasName
            ? 'MAC: ${st.macAddress} • SSID: $ssid ($band)'
            : 'SSID: $ssid ($band)';

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: _getSignalColor(
                    st.signalDbm,
                  ).withValues(alpha: 0.12),
                  child: Icon(
                    Icons.wifi,
                    color: _getSignalColor(st.signalDbm),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titleText,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitleText,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      st.formattedSignal,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _getSignalColor(st.signalDbm),
                        fontSize: 12,
                      ),
                    ),
                    if (st.rxRate != null)
                      Text(
                        'Rx: ${_formatBandwidthRate(st.rxRate)}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (st.txRate != null)
                      Text(
                        'Tx: ${_formatBandwidthRate(st.txRate)}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (st.rxRate == null && st.txRate == null)
                      Text(
                        st.signalQualityLabel,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
                PopupMenuButton<String>(
                  tooltip: '',
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (val) {
                    final isPaused = appState.isInternetPaused(st.macAddress);
                    if (val == 'pause') {
                      _toggleInternetPause(
                        context,
                        st.macAddress,
                        titleText,
                        !isPaused,
                        appState,
                      );
                    }
                  },
                  itemBuilder: (ctx) {
                    final isPaused = appState.isInternetPaused(st.macAddress);
                    return [
                      PopupMenuItem(
                        value: 'pause',
                        child: Row(
                          children: [
                            Icon(
                              isPaused
                                  ? Icons.play_circle_outline
                                  : Icons.pause_circle_outline,
                              color: isPaused
                                  ? LuciStatusColors.connected
                                  : Colors.orange,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isPaused ? 'Resume Internet' : 'Pause Internet',
                            ),
                          ],
                        ),
                      ),
                    ];
                  },
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _toggleInternetPause(
    BuildContext context,
    String mac,
    String name,
    bool pause,
    AppState appState,
  ) async {
    final actionKey = 'pause_internet_$mac';
    context.showToastLoading(
      '${pause ? "Pausing" : "Resuming"} internet for $name...',
      actionKey: actionKey,
    );
    final success = await appState.pauseClientInternet(
      mac,
      pause: pause,
      context: context,
    );
    if (!context.mounted) return;
    if (success) {
      unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.medium));
      context.showToastSuccess(
        'Internet ${pause ? "paused" : "restored"} for $name.',
        actionKey: actionKey,
      );
    } else {
      unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));
      context.showToastError(
        'Failed to ${pause ? "pause" : "resume"} internet for $name.',
        actionKey: actionKey,
      );
    }
  }

  String _formatBandwidthRate(num? rawRate) {
    if (rawRate == null) return 'N/A';
    double rate = rawRate.toDouble();
    if (rate <= 0) return '0 Mbps';

    double rateMbps;
    if (rate >= 10000000) {
      rateMbps = rate / 1000000;
    } else if (rate >= 1000 || (rate >= 1000 && rate % 1 == 0)) {
      rateMbps = rate / 1000;
    } else {
      rateMbps = rate;
    }

    if (rateMbps >= 1000) {
      final gbps = rateMbps / 1000;
      return '${gbps % 1 == 0 ? gbps.toInt() : gbps.toStringAsFixed(1)} Gbps';
    } else if (rateMbps >= 1) {
      return '${rateMbps % 1 == 0 ? rateMbps.toInt() : rateMbps.toStringAsFixed(1)} Mbps';
    } else if (rateMbps > 0) {
      final kbps = (rateMbps * 1000).round();
      if (kbps >= 1) {
        return '$kbps Kbps';
      } else {
        final bytes = (rateMbps * 1000000 / 8).round();
        return '$bytes Bytes';
      }
    }
    return '0 Mbps';
  }

  Color _getSignalColor(int? signal) {
    if (signal == null) return Colors.grey;
    if (signal >= -50) return Colors.green;
    if (signal >= -65) return Colors.teal;
    if (signal >= -75) return Colors.orange;
    return Colors.red;
  }

  void _showEditRadioDialog(BuildContext context, WirelessRadio radio) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => EditRadioDialog(radio: radio),
    );
  }

  void _showAddSsidDialog(
    BuildContext context,
    List<WirelessRadio> radios,
    WirelessRadio targetRadio,
  ) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AddSsidDialog(radios: radios, targetRadio: targetRadio),
    );
  }
}
