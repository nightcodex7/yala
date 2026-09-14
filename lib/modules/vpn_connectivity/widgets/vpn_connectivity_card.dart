// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import '../models/vpn_info.dart';

class VpnConnectivityCard extends ConsumerWidget {
  const VpnConnectivityCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    final overview = VpnConnectivityOverview.fromDashboardData(
      appState.dashboardData,
      isReviewerMode: appState.reviewerModeEnabled,
    );

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.vpn_lock_outlined,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'VPN & Secure Tunnels',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${overview.activeServicesCount}/${overview.totalConfiguredServices} Active',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildActiveConnectionsRow(context, overview),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveConnectionsRow(
    BuildContext context,
    VpnConnectivityOverview overview,
  ) {
    final activeTiles = <Widget>[];

    final activeWg = overview.wireguardInterfaces.where((w) => w.isUp).toList();
    if (activeWg.isNotEmpty) {
      activeTiles.add(
        Expanded(
          child: _buildMetricTile(
            context,
            label: 'WireGuard',
            value: '${activeWg.length} Active',
            icon: Icons.shield_outlined,
            color: Colors.blue,
          ),
        ),
      );
    }

    final activeOvpn = overview.openvpnInstances
        .where((o) => o.isRunning)
        .toList();
    if (activeOvpn.isNotEmpty) {
      activeTiles.add(
        Expanded(
          child: _buildMetricTile(
            context,
            label: 'OpenVPN',
            value: '${activeOvpn.length} Active',
            icon: Icons.lock_outline,
            color: Colors.green,
          ),
        ),
      );
    }

    if (overview.tailscale.isConfigured && overview.tailscale.isRunning) {
      activeTiles.add(
        Expanded(
          child: _buildMetricTile(
            context,
            label: 'Tailscale',
            value: overview.tailscale.backendState.toUpperCase(),
            icon: Icons.hub_outlined,
            color: Colors.teal,
          ),
        ),
      );
    }

    if (overview.nextdns.isConfigured &&
        overview.nextdns.isEnabled &&
        overview.nextdns.isRunning) {
      activeTiles.add(
        Expanded(
          child: _buildMetricTile(
            context,
            label: 'NextDNS',
            value: 'ENCRYPTED',
            icon: Icons.security_outlined,
            color: Colors.indigo,
          ),
        ),
      );
    }

    if (overview.cloudflared.isConfigured && overview.cloudflared.isRunning) {
      activeTiles.add(
        Expanded(
          child: _buildMetricTile(
            context,
            label: 'Cloudflared',
            value: 'ACTIVE',
            icon: Icons.cloud_done_outlined,
            color: Colors.orange,
          ),
        ),
      );
    }

    if (activeTiles.isNotEmpty) {
      return Row(children: activeTiles);
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shield_outlined,
            size: 16,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 8),
          Text(
            'No Active Connections',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            fontSize: 10,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
