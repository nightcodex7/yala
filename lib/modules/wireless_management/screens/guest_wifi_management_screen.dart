// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';
import 'package:yet_another_luci_app/widgets/add_static_lease_dialog.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/widgets/luci_guardrail.dart';
import 'package:yet_another_luci_app/widgets/ban_wireless_client_dialog.dart';
import '../models/wireless_info.dart';
import '../widgets/wireless_interface_card.dart';
import '../widgets/provision_guest_network_dialog.dart';
import '../widgets/wifi_qr_dialog.dart';
import '../widgets/wireless_rollback_banner.dart';

class _GuestStationPair {
  final WirelessStation station;
  final WirelessInterface interface;

  _GuestStationPair({required this.station, required this.interface});
}

/// Dedicated, full-featured management dashboard for Guest Wi-Fi networks.
/// Features master control switch, connected guest client statistics, subnet & firewall
/// isolation status, and quick network provisioning.
class GuestWifiManagementScreen extends ConsumerWidget {
  const GuestWifiManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final appState = ref.watch(appStateProvider);
    final overview = WirelessOverview.fromDashboardData(
      appState.dashboardData,
      isReviewerMode: appState.reviewerModeEnabled,
    );
    final hasWriteAccess =
        (appState.capabilities?.hasUciWriteAccess ?? true) &&
        appState.isAdministrativeUser;

    final allGuestIfaces = overview.radios
        .expand((r) => r.interfaces)
        .where(
          (i) => i.isGuestInterface(
            appState.customGuestSections,
            appState.excludedGuestSections,
          ),
        )
        .toList();

    final activeGuestCount = allGuestIfaces.where((i) => i.isEnabled).length;

    final guestStationPairs = <_GuestStationPair>[];
    for (final iface in allGuestIfaces) {
      for (final st in iface.stations) {
        guestStationPairs.add(_GuestStationPair(station: st, interface: iface));
      }
    }

    final allEnabled =
        allGuestIfaces.isNotEmpty && activeGuestCount == allGuestIfaces.length;

    return PopScope(
      canPop: !appState.isAccessControlPendingConfirmation,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final canExit = await LuciGuardrail.confirmStagedChangesOrExit(
          context,
          appState,
        );
        if (canExit && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Guest Wi-Fi Dashboard'),
          centerTitle: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh Guest Status',
              onPressed: () {
                appState.fetchDashboardData();
                context.showToastInfo('Refreshed Guest Wi-Fi status');
              },
            ),
          ],
        ),
        body: Column(
          children: [
            const WirelessRollbackBanner(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await appState.fetchDashboardData();
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 100.0),
                  children: [
                    // Top Summary & Master Control Card
                    _buildMasterControlHeader(
                      context,
                      theme,
                      appState,
                      allGuestIfaces,
                      activeGuestCount,
                      guestStationPairs.length,
                      allEnabled,
                      hasWriteAccess,
                    ),
                    const SizedBox(height: 20),

                    // Quick Action Toolbar
                    _buildQuickActionToolbar(
                      context,
                      appState,
                      overview,
                      allGuestIfaces,
                      hasWriteAccess,
                    ),
                    const SizedBox(height: 24),

                    // Section Header: Guest Wireless SSIDs
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.shield_moon_rounded,
                              color: Colors.amber.shade800,
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Configured Guest Networks (${allGuestIfaces.length})',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        if (allGuestIfaces.isNotEmpty)
                          Text(
                            '$activeGuestCount active',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (allGuestIfaces.isEmpty)
                      _buildEmptyGuestCard(
                        context,
                        theme,
                        appState,
                        overview,
                        hasWriteAccess,
                      )
                    else
                      ...allGuestIfaces.map(
                        (iface) => WirelessInterfaceCard(
                          radio:
                              iface.radio ??
                              (overview.radios.isNotEmpty
                                  ? overview.radios.first
                                  : WirelessRadio(
                                      name: 'radio0',
                                      isUp: true,
                                      channel: 'auto',
                                      country: 'US',
                                      interfaces: [iface],
                                    )),
                          interface: iface,
                          onToggleEnabled: (enable) async {
                            if (!hasWriteAccess) {
                              context.showToastError(
                                'Read-only session: UCI write permission required.',
                              );
                              return;
                            }
                            await appState.setSsidEnabled(
                              iface.sectionName,
                              enable,
                              context: context,
                            );
                          },
                        ),
                      ),

                    const SizedBox(height: 28),

                    // Connected Guest Clients List with guest-specific controls
                    _buildConnectedGuestClientsSection(
                      context,
                      theme,
                      appState,
                      guestStationPairs,
                      hasWriteAccess,
                    ),
                    const SizedBox(height: 28),

                    // Guest Architecture & Subnet Firewall Status
                    _buildGuestSecurityArchitectureCard(context, theme),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMasterControlHeader(
    BuildContext context,
    ThemeData theme,
    AppState appState,
    List<WirelessInterface> guestIfaces,
    int activeCount,
    int totalStations,
    bool allEnabled,
    bool hasWriteAccess,
  ) {
    final isDarkMode = theme.brightness == Brightness.dark;
    final guestCardBg = Color.alphaBlend(
      theme.colorScheme.tertiary.withValues(alpha: isDarkMode ? 0.08 : 0.05),
      theme.colorScheme.surfaceContainerLow,
    );
    final guestBorderColor = theme.colorScheme.tertiary.withValues(
      alpha: isDarkMode ? 0.45 : 0.35,
    );

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: guestBorderColor, width: 1.2),
      ),
      color: guestCardBg,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiary.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.shield_moon_rounded,
                    color: theme.colorScheme.tertiary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Guest Wi-Fi Master Control',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        guestIfaces.isEmpty
                            ? 'No active guest SSIDs configured'
                            : '$activeCount of ${guestIfaces.length} networks enabled • $totalStations client${totalStations == 1 ? '' : 's'} connected',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (guestIfaces.isNotEmpty)
                  Switch(
                    value: allEnabled,
                    onChanged: hasWriteAccess
                        ? (enable) async {
                            final actionKey = 'toggle_all_guest_screen';
                            context.showToastLoading(
                              '${enable ? "Enabling" : "Disabling"} all Guest networks...',
                              actionKey: actionKey,
                            );
                            int count = 0;
                            for (final iface in guestIfaces) {
                              if (iface.isEnabled != enable) {
                                final res = await appState.setSsidEnabled(
                                  iface.sectionName,
                                  enable,
                                  context: context,
                                );
                                if (res) count++;
                              }
                            }
                            if (context.mounted) {
                              context.showToastSuccess(
                                enable
                                    ? 'Enabled $count Guest network interface${count == 1 ? '' : 's'}.'
                                    : 'Disabled $count Guest network interface${count == 1 ? '' : 's'}.',
                                actionKey: actionKey,
                              );
                            }
                          }
                        : (val) {
                            context.showToastError(
                              'Read-only session: UCI write permission required.',
                            );
                          },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionToolbar(
    BuildContext context,
    AppState appState,
    WirelessOverview overview,
    List<WirelessInterface> guestIfaces,
    bool hasWriteAccess,
  ) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        ElevatedButton.icon(
          onPressed: () {
            if (!hasWriteAccess) {
              context.showToastError(
                'Read-only session: UCI write permission required to create Guest Wi-Fi.',
              );
              return;
            }
            showDialog(
              context: context,
              builder: (ctx) =>
                  ProvisionGuestNetworkDialog(radios: overview.radios),
            );
          },
          icon: const Icon(Icons.add_moderator_rounded, size: 18),
          label: const Text('New Guest Wi-Fi'),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.tertiary,
            foregroundColor: theme.colorScheme.onTertiary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        if (guestIfaces.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () {
              final activeGuest = guestIfaces.firstWhere(
                (i) => i.isEnabled,
                orElse: () => guestIfaces.first,
              );
              showDialog(
                context: context,
                builder: (ctx) => WifiQrDialog(interface: activeGuest),
              );
            },
            icon: const Icon(Icons.qr_code_rounded, size: 18),
            label: const Text('Guest QR Code'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyGuestCard(
    BuildContext context,
    ThemeData theme,
    AppState appState,
    WirelessOverview overview,
    bool hasWriteAccess,
  ) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Icon(
              Icons.wifi_protected_setup_rounded,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            const Text(
              'No Guest Wi-Fi Networks Found',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              'Easily create an isolated guest network with 1-click presets or mark an existing wireless SSID as Guest.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                if (!hasWriteAccess) {
                  context.showToastError(
                    'Read-only session: UCI write permission required to create Guest Wi-Fi.',
                  );
                  return;
                }
                showDialog(
                  context: context,
                  builder: (ctx) =>
                      ProvisionGuestNetworkDialog(radios: overview.radios),
                );
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Create New Guest Wi-Fi'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedGuestClientsSection(
    BuildContext context,
    ThemeData theme,
    AppState appState,
    List<_GuestStationPair> guestStationPairs,
    bool hasWriteAccess,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.devices_other_rounded,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'Connected Guest Devices (${guestStationPairs.length})',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (guestStationPairs.isEmpty)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No clients currently associated with guest networks.',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...guestStationPairs.map((pair) {
            final st = pair.station;
            final iface = pair.interface;
            final client = appState.findClientByMac(st.macAddress);
            final displayName = ClientNamingHelper.getDisplayName(
              st.macAddress,
              appState: appState,
              client: client,
            );
            final macNorm = ClientNamingHelper.normalizeMac(st.macAddress);
            final ipAddress = client?.ipAddress ?? 'N/A';
            final isPaused = appState.pausedInternetMacs.contains(macNorm);
            final isStatic =
                (client != null && client.isStatic) ||
                appState.findStaticLeaseByMac(macNorm) != null;

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isPaused
                      ? Colors.red.shade400
                      : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          backgroundColor: isPaused
                              ? Colors.red.shade100
                              : Colors.amber.shade100,
                          child: Icon(
                            isPaused
                                ? Icons.block_rounded
                                : ClientNamingHelper.getDeviceIcon(client),
                            color: isPaused
                                ? Colors.red.shade900
                                : Colors.amber.shade900,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      displayName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          theme.colorScheme.tertiaryContainer,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: theme.colorScheme.tertiary
                                            .withValues(alpha: 0.4),
                                      ),
                                    ),
                                    child: Text(
                                      'Isolated Guest',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: theme
                                            .colorScheme
                                            .onTertiaryContainer,
                                      ),
                                    ),
                                  ),
                                  if (isPaused) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade700.withValues(
                                          alpha: 0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: Colors.red.shade800.withValues(
                                            alpha: 0.4,
                                          ),
                                        ),
                                      ),
                                      child: const Text(
                                        'PAUSED',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'IP: $ipAddress  •  MAC: $macNorm  •  SSID: ${iface.ssid}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Signal: ${st.formattedSignal} (${st.signalQualityLabel})  •  Noise: ${st.noiseDbm != null ? "${st.noiseDbm} dBm" : "N/A"}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    // Action controls specifically customized for Guest Wi-Fi
                    _buildJustifiedGuestActionButtons(
                      context,
                      buttons: [
                        // 1. Pause / Resume Internet Switch
                        OutlinedButton.icon(
                          onPressed: hasWriteAccess
                              ? () async {
                                  final nextPauseState = !isPaused;
                                  context.showToastLoading(
                                    '${nextPauseState ? "Pausing" : "Resuming"} internet access for $displayName...',
                                    actionKey: 'pause_guest_$macNorm',
                                  );
                                  final ok = await appState.pauseClientInternet(
                                    macNorm,
                                    pause: nextPauseState,
                                    context: context,
                                  );
                                  if (context.mounted) {
                                    if (ok) {
                                      context.showToastSuccess(
                                        '${nextPauseState ? "Paused" : "Resumed"} internet for $displayName',
                                        actionKey: 'pause_guest_$macNorm',
                                      );
                                    } else {
                                      context.showToastError(
                                        'Failed to update internet status for $displayName.',
                                        actionKey: 'pause_guest_$macNorm',
                                      );
                                    }
                                  }
                                }
                              : null,
                          icon: Icon(
                            isPaused
                                ? Icons.play_arrow_rounded
                                : Icons.pause_rounded,
                            size: 16,
                            color: isPaused
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                          ),
                          label: Text(
                            isPaused ? 'Resume Access' : 'Pause Access',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isPaused
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            minimumSize: const Size(0, 36),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            side: BorderSide(
                              color: isPaused
                                  ? Colors.green.shade400
                                  : Colors.red.shade300,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),

                        // 2. Ban Guest Client
                        OutlinedButton.icon(
                          onPressed: hasWriteAccess
                              ? () {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => BanWirelessClientDialog(
                                      macAddress: macNorm,
                                      displayName: displayName,
                                      ipAddress: ipAddress,
                                      ssid: iface.ssid,
                                      iface: iface.sectionName,
                                      isAlreadyBanned: appState
                                          .isWirelessBanned(macNorm),
                                      onBanConfirmed: (int banTimeSeconds) async {
                                        context.showToastLoading(
                                          'Banning $displayName...',
                                          actionKey: 'ban_$macNorm',
                                        );
                                        final res = await appState
                                            .banWirelessClient(
                                              macNorm,
                                              iface: iface.sectionName,
                                              banTimeSeconds: banTimeSeconds,
                                              context: context,
                                            );
                                        if (res) {
                                          if (context.mounted) {
                                            LuciToastManager.safeShowSuccess(
                                              context,
                                              'Banned $displayName from ${iface.ssid}',
                                              actionKey: 'ban_$macNorm',
                                            );
                                          }
                                        } else {
                                          if (context.mounted) {
                                            LuciToastManager.safeShowError(
                                              context,
                                              'Failed to ban $displayName',
                                              actionKey: 'ban_$macNorm',
                                            );
                                          }
                                        }
                                      },
                                    ),
                                  );
                                }
                              : null,
                          icon: const Icon(
                            Icons.block_rounded,
                            size: 16,
                            color: Colors.orange,
                          ),
                          label: const Text(
                            'Ban Client',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            minimumSize: const Size(0, 36),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            side: BorderSide(color: Colors.orange.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),

                        // 3. Static Lease Controls (Add or Edit / Remove)
                        if (!isStatic)
                          OutlinedButton.icon(
                            onPressed: hasWriteAccess
                                ? () {
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AddStaticLeaseDialog(
                                        macAddress: macNorm,
                                        initialIp: ipAddress != 'N/A'
                                            ? ipAddress
                                            : null,
                                        initialHostname: displayName != macNorm
                                            ? displayName
                                            : null,
                                        client: client,
                                        allClients: appState.clients,
                                        onSaved: () => appState
                                            .fetchClientsForSelectedRouter(),
                                      ),
                                    );
                                  }
                                : null,
                            icon: const Icon(
                              Icons.push_pin_outlined,
                              size: 16,
                              color: Colors.teal,
                            ),
                            label: Text(
                              'Static Lease',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal.shade800,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              minimumSize: const Size(0, 36),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              side: BorderSide(color: Colors.teal.shade400),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          )
                        else ...[
                          OutlinedButton.icon(
                            onPressed: hasWriteAccess
                                ? () {
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AddStaticLeaseDialog(
                                        macAddress: macNorm,
                                        initialIp: ipAddress != 'N/A'
                                            ? ipAddress
                                            : null,
                                        initialHostname: displayName != macNorm
                                            ? displayName
                                            : null,
                                        client: client,
                                        allClients: appState.clients,
                                        onSaved: () => appState
                                            .fetchClientsForSelectedRouter(),
                                      ),
                                    );
                                  }
                                : null,
                            icon: const Icon(
                              Icons.edit_outlined,
                              size: 16,
                              color: Colors.teal,
                            ),
                            label: Text(
                              'Edit Static Lease',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal.shade800,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              minimumSize: const Size(0, 36),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              side: BorderSide(color: Colors.teal.shade400),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: hasWriteAccess
                                ? () => _confirmRemoveStaticLease(
                                    context,
                                    macAddress: macNorm,
                                    displayName: displayName,
                                  )
                                : null,
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 16,
                              color: Colors.redAccent,
                            ),
                            label: const Text(
                              'Remove Lease',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.redAccent,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              minimumSize: const Size(0, 36),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              side: BorderSide(
                                color: Colors.redAccent.withValues(alpha: 0.5),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildGuestSecurityArchitectureCard(
    BuildContext context,
    ThemeData theme,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.security_rounded,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Guest Security & Firewall Guardrails',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildArchitectureTile(
              icon: Icons.alt_route_rounded,
              title: 'Subnet & Client Isolation',
              description:
                  'Guest clients are assigned to isolated subnet with inter-client communication blocked (isolate=1).',
            ),
            const Divider(height: 16),
            _buildArchitectureTile(
              icon: Icons.local_fire_department_rounded,
              title: 'Firewall Policy Forwarding',
              description:
                  'Outbound WAN traffic is permitted while LAN access (router admin portal & internal network devices) is strictly rejected.',
            ),
            const Divider(height: 16),
            _buildArchitectureTile(
              icon: Icons.verified_user_rounded,
              title: 'Atomic UCI Commit',
              description:
                  'All wireless configuration edits are applied directly to the router via atomic UCI commits.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArchitectureTile({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.amber.shade800),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmRemoveStaticLease(
    BuildContext context, {
    required String macAddress,
    required String displayName,
  }) async {
    if (ActionRateLimiter.isRateLimited(
      'delete_static_lease_$macAddress',
      cooldown: const Duration(milliseconds: 1200),
    )) {
      if (context.mounted) {
        context.showToastWarning(
          'Removal in progress. Please wait a moment...',
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_outline,
                color: Colors.redAccent,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Remove Static Lease',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to remove the static IP reservation for "$displayName" ($macAddress)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Remove Reservation'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final actionKey = 'remove_lease_$macAddress';
      context.showToastLoading(
        'Removing static lease for $displayName...',
        actionKey: actionKey,
      );

      final appState = AppState.instance;
      final success = await appState.deleteStaticLease(
        macAddress: macAddress,
        hostname: displayName != 'Unknown' && displayName.isNotEmpty
            ? displayName
            : null,
        context: context,
      );

      if (!context.mounted) return;

      if (success) {
        appState.invalidateStaticLeasesCache();
        context.showToastSuccess(
          'Static lease removed for $displayName.',
          actionKey: actionKey,
        );
        await appState.fetchClientsForSelectedRouter();
      } else {
        context.showToastError(
          'Failed to remove static lease for $displayName.',
          actionKey: actionKey,
        );
      }
    }
  }

  Widget _buildJustifiedGuestActionButtons(
    BuildContext context, {
    required List<Widget> buttons,
  }) {
    if (buttons.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth = constraints.maxWidth;

        if (availableWidth < 480) {
          final List<Widget> rows = [];
          for (int i = 0; i < buttons.length; i += 2) {
            if (i + 1 < buttons.length) {
              rows.add(
                Row(
                  children: [
                    Expanded(child: buttons[i]),
                    const SizedBox(width: 8),
                    Expanded(child: buttons[i + 1]),
                  ],
                ),
              );
            } else {
              rows.add(Row(children: [Expanded(child: buttons[i])]));
            }
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int r = 0; r < rows.length; r++) ...[
                if (r > 0) const SizedBox(height: 8),
                rows[r],
              ],
            ],
          );
        }

        return Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: buttons,
          ),
        );
      },
    );
  }
}
