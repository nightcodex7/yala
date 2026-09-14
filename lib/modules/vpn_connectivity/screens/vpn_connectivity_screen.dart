// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/widgets/luci_collapsible_card.dart';
import '../models/vpn_info.dart';

class VpnConnectivityScreen extends ConsumerWidget {
  const VpnConnectivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    final overview = VpnConnectivityOverview.fromDashboardData(
      appState.dashboardData,
      isReviewerMode: appState.reviewerModeEnabled,
    );

    final hasWg = overview.wireguardInterfaces.isNotEmpty;
    final hasOvpn = overview.openvpnInstances.isNotEmpty;
    final hasTs = overview.tailscale.isConfigured;
    final hasNextDns = overview.nextdns.isConfigured;
    final hasCf = overview.cloudflared.isConfigured;

    final children = <Widget>[];
    final unconfiguredCards = <Widget>[];
    final configuredSections = <_ConfiguredVpnSection>[];

    // WireGuard
    if (hasWg) {
      final sortedWg =
          List<WireguardInterface>.from(overview.wireguardInterfaces)
            ..sort((a, b) {
              if (a.isUp != b.isUp) return a.isUp ? -1 : 1;
              return a.name.compareTo(b.name);
            });

      configuredSections.add(
        _ConfiguredVpnSection(
          defaultPriority: 0,
          isActive: sortedWg.any((w) => w.isUp),
          header: _buildSectionHeader(
            context,
            'WireGuard VPN Interfaces & Peers',
            Icons.shield_outlined,
          ),
          cards: sortedWg
              .map((wg) => _buildWireguardCard(context, ref, wg))
              .toList(),
        ),
      );
    } else {
      unconfiguredCards.add(
        _buildUnconfiguredCard(
          context,
          title: 'WireGuard VPN',
          message:
              'No WireGuard interfaces or peer configurations found on this router.',
          icon: Icons.shield_outlined,
        ),
      );
    }

    // OpenVPN
    if (hasOvpn) {
      final sortedOvpn = List<OpenVpnInstance>.from(overview.openvpnInstances)
        ..sort((a, b) {
          if (a.isRunning != b.isRunning) return a.isRunning ? -1 : 1;
          return a.name.compareTo(b.name);
        });

      configuredSections.add(
        _ConfiguredVpnSection(
          defaultPriority: 1,
          isActive: sortedOvpn.any((o) => o.isRunning),
          header: _buildSectionHeader(
            context,
            'OpenVPN Tunnels',
            Icons.lock_outline,
          ),
          cards: [_buildOpenVpnCard(context, ref, sortedOvpn)],
        ),
      );
    } else {
      unconfiguredCards.add(
        _buildUnconfiguredCard(
          context,
          title: 'OpenVPN Tunnels',
          message:
              'No OpenVPN instances configured in router setup (/etc/config/openvpn).',
          icon: Icons.lock_outline,
        ),
      );
    }

    // Tailscale
    if (hasTs) {
      configuredSections.add(
        _ConfiguredVpnSection(
          defaultPriority: 2,
          isActive: overview.tailscale.isRunning,
          header: _buildSectionHeader(
            context,
            'Tailscale Mesh VPN',
            Icons.hub_outlined,
          ),
          cards: [_buildTailscaleCard(context, ref, overview.tailscale)],
        ),
      );
    } else {
      unconfiguredCards.add(
        _buildUnconfiguredCard(
          context,
          title: 'Tailscale Mesh VPN',
          message:
              'No Tailscale configuration or authenticated node found on this router.',
          icon: Icons.hub_outlined,
        ),
      );
    }

    // NextDNS
    if (hasNextDns) {
      configuredSections.add(
        _ConfiguredVpnSection(
          defaultPriority: 3,
          isActive: overview.nextdns.isRunning || overview.nextdns.isEnabled,
          header: _buildSectionHeader(
            context,
            'NextDNS Encrypted Resolver',
            Icons.security_outlined,
          ),
          cards: [_buildNextDnsCard(context, ref, overview.nextdns)],
        ),
      );
    } else {
      unconfiguredCards.add(
        _buildUnconfiguredCard(
          context,
          title: 'NextDNS Resolver',
          message:
              'No NextDNS profile ID or resolver configuration found on this router.',
          icon: Icons.security_outlined,
        ),
      );
    }

    // Cloudflared
    if (hasCf) {
      configuredSections.add(
        _ConfiguredVpnSection(
          defaultPriority: 4,
          isActive: overview.cloudflared.isRunning,
          header: _buildSectionHeader(
            context,
            'Cloudflare Tunnels (cloudflared)',
            Icons.cloud_done_outlined,
          ),
          cards: [_buildCloudflaredCard(context, ref, overview.cloudflared)],
        ),
      );
    } else {
      unconfiguredCards.add(
        _buildUnconfiguredCard(
          context,
          title: 'Cloudflare Tunnel (cloudflared)',
          message:
              'No Cloudflare Tunnel ID or token configuration found on this router.',
          icon: Icons.cloud_off_outlined,
        ),
      );
    }

    // Sort configured sections: Active / Running / Up services FIRST at top priority!
    configuredSections.sort((a, b) {
      if (a.isActive != b.isActive) {
        return a.isActive ? -1 : 1;
      }
      return a.defaultPriority.compareTo(b.defaultPriority);
    });

    for (final sec in configuredSections) {
      children.add(sec.header);
      children.add(const SizedBox(height: 8));
      for (final card in sec.cards) {
        children.add(card);
      }
      children.add(const SizedBox(height: 16));
    }

    // Unconfigured Services (Bottom of page - Collapsible by default)
    if (unconfiguredCards.isNotEmpty) {
      if (children.isNotEmpty) {
        children.add(const Divider(height: 32, thickness: 1));
      }
      children.add(
        LuciCollapsibleCard(
          title: 'Unconfigured Tunnels & Services',
          count: unconfiguredCards.length,
          subtitle:
              '${unconfiguredCards.length} inactive tunnel profiles • Tap to view',
          icon: Icons.do_not_disturb_on_outlined,
          iconColor: Colors.grey,
          child: Column(children: unconfiguredCards),
        ),
      );
    }

    children.add(const SizedBox(height: 32));

    return Scaffold(
      appBar: AppBar(
        title: const Text('VPN & Secure Tunnels'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Status',
            onPressed: () async {
              await appState.fetchDashboardData();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await appState.fetchDashboardData();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 100.0),
          children: children,
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

  Widget _buildWireguardCard(
    BuildContext context,
    WidgetRef ref,
    WireguardInterface wg,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.blue,
                      child: Icon(Icons.vpn_key, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Interface: ${wg.name.toUpperCase()}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: wg.isUp
                            ? Colors.green.withValues(alpha: 0.15)
                            : Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        wg.isUp ? 'UP' : 'DOWN',
                        style: TextStyle(
                          color: wg.isUp ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        wg.isUp ? Icons.power_settings_new : Icons.play_arrow,
                        size: 20,
                      ),
                      tooltip: wg.isUp ? 'Bring Down' : 'Bring Up',
                      onPressed: () => _confirmToggleProvider(
                        context,
                        ref,
                        title:
                            '${wg.isUp ? "Bring Down" : "Bring Up"} Interface "${wg.name}"?',
                        message:
                            'Are you sure you want to ${wg.isUp ? "bring down" : "bring up"} the WireGuard interface "${wg.name}" on the router?',
                        action: () async {
                          final appState = ref.read(appStateProvider);
                          await appState.toggleWireguardInterface(
                            wg.name,
                            !wg.isUp,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildDetailRow('Public Key', wg.publicKey),
            _buildDetailRow('Listen Port', '${wg.listenPort}'),
            const Divider(height: 20),
            Text(
              'Connected WireGuard Peers (${wg.peers.length})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (wg.peers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  'No active peers configured or connected.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              )
            else
              ...wg.peers.map((p) => _buildPeerTile(context, p)),
          ],
        ),
      ),
    );
  }

  Widget _buildPeerTile(BuildContext context, WireguardPeer peer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Peer: ${peer.publicKey}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                peer.formattedHandshake,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.blue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _buildDetailRow('Endpoint', peer.endpoint ?? 'N/A'),
          _buildDetailRow('Allowed IPs', peer.allowedIps.join(', ')),
          _buildDetailRow(
            'Traffic Transferred',
            'RX: ${_formatBytes(peer.rxBytes)} / TX: ${_formatBytes(peer.txBytes)}',
          ),
        ],
      ),
    );
  }

  Widget _buildOpenVpnCard(
    BuildContext context,
    WidgetRef ref,
    List<OpenVpnInstance> instances,
  ) {
    if (instances.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('No OpenVPN instances configured.'),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: instances.map((ovpn) {
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: ovpn.isRunning
                  ? Colors.green.withValues(alpha: 0.15)
                  : Colors.grey.withValues(alpha: 0.2),
              child: Icon(
                Icons.lock,
                color: ovpn.isRunning ? Colors.green : Colors.grey,
              ),
            ),
            title: Text(
              ovpn.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Device: ${ovpn.dev} • Proto: ${ovpn.proto.toUpperCase()}:${ovpn.port}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: ovpn.isRunning
                        ? Colors.green.withValues(alpha: 0.15)
                        : Colors.grey.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    ovpn.isRunning ? 'RUNNING' : 'STOPPED',
                    style: TextStyle(
                      color: ovpn.isRunning ? Colors.green : Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: ovpn.isRunning,
                  onChanged: (val) => _confirmToggleProvider(
                    context,
                    ref,
                    title: '${val ? "Start" : "Stop"} OpenVPN "${ovpn.name}"?',
                    message:
                        'Are you sure you want to ${val ? "start" : "stop"} the OpenVPN instance "${ovpn.name}" on the router?',
                    action: () async {
                      final appState = ref.read(appStateProvider);
                      await appState.toggleOpenVpnInstance(ovpn.name, val);
                    },
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTailscaleCard(
    BuildContext context,
    WidgetRef ref,
    TailscaleStatus ts,
  ) {
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
                Expanded(
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.teal,
                        child: Icon(Icons.hub, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          ts.nodeName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: ts.isRunning
                            ? Colors.teal.withValues(alpha: 0.15)
                            : Colors.grey.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        ts.backendState.toUpperCase(),
                        style: TextStyle(
                          color: ts.isRunning ? Colors.teal : Colors.grey,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: ts.isRunning,
                      onChanged: (val) => _confirmToggleProvider(
                        context,
                        ref,
                        title: '${val ? "Enable" : "Disable"} Tailscale?',
                        message:
                            'Are you sure you want to ${val ? "enable" : "disable"} the Tailscale mesh daemon on the router?',
                        action: () async {
                          final appState = ref.read(appStateProvider);
                          await appState.toggleTailscale(val);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 20),
            _buildDetailRow(
              'Tailscale IP',
              ts.tailscaleIp.isNotEmpty ? ts.tailscaleIp : 'N/A',
            ),
            if (ts.tailnet.isNotEmpty)
              _buildDetailRow('Tailnet Account', ts.tailnet),
            if (ts.magicDns.isNotEmpty)
              _buildDetailRow('MagicDNS Domain', ts.magicDns),
            if (ts.peersCount > 0)
              _buildDetailRow('Mesh Peers', '${ts.peersCount} Connected Peers'),
            if (ts.isExitNode)
              _buildDetailRow(
                'Exit Node Capability',
                'ENABLED (Offers Exit Node)',
              ),
            _buildDetailRow('Backend Daemon State', ts.backendState),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _confirmToggleProvider(
                    context,
                    ref,
                    title: 'Restart Tailscale Service?',
                    message:
                        'Restarting Tailscale will temporarily drop active mesh connections.',
                    action: () async {
                      final appState = ref.read(appStateProvider);
                      await appState.restartVpnService('tailscale');
                    },
                  ),
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: const Text('Restart Daemon'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNextDnsCard(
    BuildContext context,
    WidgetRef ref,
    NextDnsStatus ndns,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.indigo,
                        child: Icon(
                          Icons.security,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          ndns.profileId.isNotEmpty
                              ? 'Profile: ${ndns.profileId}'
                              : 'NextDNS',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: ndns.isEnabled && ndns.isRunning,
                  onChanged: (val) => _confirmToggleProvider(
                    context,
                    ref,
                    title: '${val ? "Activate" : "Deactivate"} NextDNS?',
                    message:
                        'Are you sure you want to ${val ? "activate" : "deactivate"} encrypted NextDNS resolving on the router?',
                    action: () async {
                      final appState = ref.read(appStateProvider);
                      await appState.toggleNextDns(val);
                    },
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            _buildDetailRow(
              'Encrypted DNS Profile ID',
              ndns.profileId.isNotEmpty ? ndns.profileId : 'N/A',
            ),
            _buildDetailRow(
              'NextDNS Daemon Status',
              ndns.isEnabled
                  ? (ndns.isRunning
                        ? 'ACTIVE & ENCRYPTED'
                        : 'STOPPED / DEACTIVATED')
                  : 'DISABLED',
            ),
            _buildDetailRow(
              'Report Client Info',
              ndns.reportClientInfo ? 'ENABLED' : 'DISABLED',
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _confirmToggleProvider(
                    context,
                    ref,
                    title: 'Restart NextDNS Service?',
                    message:
                        'Restarting NextDNS will reload DNS filtering configurations.',
                    action: () async {
                      final appState = ref.read(appStateProvider);
                      await appState.restartVpnService('nextdns');
                    },
                  ),
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: const Text('Restart Resolver'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloudflaredCard(
    BuildContext context,
    WidgetRef ref,
    CloudflaredStatus cf,
  ) {
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
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.orange,
                      child: Icon(
                        Icons.cloud_done,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      cf.tunnelName.isNotEmpty
                          ? cf.tunnelName
                          : 'Cloudflare Tunnel',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: cf.isRunning
                            ? Colors.orange.withValues(alpha: 0.15)
                            : Colors.grey.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        cf.isRunning ? 'ACTIVE' : 'DISABLED',
                        style: TextStyle(
                          color: cf.isRunning
                              ? Colors.orange.shade800
                              : Colors.grey,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: cf.isRunning,
                      onChanged: (val) => _confirmToggleProvider(
                        context,
                        ref,
                        title:
                            '${val ? "Enable" : "Disable"} Cloudflare Tunnel?',
                        message:
                            'Are you sure you want to ${val ? "enable" : "disable"} the cloudflared zero-trust tunnel daemon on the router?',
                        action: () async {
                          final appState = ref.read(appStateProvider);
                          await appState.toggleCloudflared(val);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 20),
            _buildDetailRow('Tunnel ID', cf.tunnelId),
            _buildDetailRow(
              'Edge Connections',
              '${cf.connectionsCount} Active Edge Hops',
            ),
            _buildDetailRow(
              'Tunnel Status',
              cf.isRunning ? 'CONNECTED TO CLOUDFLARE EDGE' : 'INACTIVE',
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _confirmToggleProvider(
                    context,
                    ref,
                    title: 'Restart Cloudflared Service?',
                    message:
                        'Restarting Cloudflared will re-establish edge connection tunnels to Cloudflare Zero Trust.',
                    action: () async {
                      final appState = ref.read(appStateProvider);
                      await appState.restartVpnService('cloudflared');
                    },
                  ),
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: const Text('Restart Tunnel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmToggleProvider(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String message,
    required Future<void> Function() action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      if (ActionRateLimiter.isRateLimited(
        title,
        cooldown: const Duration(seconds: 2),
      )) {
        final remaining = ActionRateLimiter.getRemainingCooldown(
          title,
          cooldown: const Duration(seconds: 2),
        );
        context.showToastRateLimited(title, remaining);
        return;
      }

      final actionKey = 'vpn_action_${title.hashCode}';
      context.showToastLoading(
        'Applying configuration change...',
        subtitle: title,
        actionKey: actionKey,
      );
      await action();
      final appState = ref.read(appStateProvider);
      await appState.fetchDashboardData();

      if (context.mounted) {
        context.showToastSuccess(
          'Tunnel Configuration Updated',
          subtitle: 'State change applied successfully.',
          actionKey: actionKey,
        );
      }
    }
  }

  Widget _buildUnconfiguredCard(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: theme.colorScheme.onSurface.withValues(
                alpha: 0.1,
              ),
              child: Icon(
                icon,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.45,
                      ),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'NOT CONFIGURED',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  String _formatBytes(num bytes) {
    if (bytes <= 0) return '0 B';
    final double b = bytes.toDouble();
    if (b >= 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${b.toStringAsFixed(0)} B';
  }
}

class _ConfiguredVpnSection {
  final int defaultPriority;
  final bool isActive;
  final Widget header;
  final List<Widget> cards;

  _ConfiguredVpnSection({
    required this.defaultPriority,
    required this.isActive,
    required this.header,
    required this.cards,
  });
}
