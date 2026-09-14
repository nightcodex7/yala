// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import '../models/dhcp_dns_info.dart';

class DhcpDnsCard extends ConsumerWidget {
  const DhcpDnsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    final overview = DhcpDnsOverview.fromDashboardData(appState.dashboardData);

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
                        Icons.dns_outlined,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'DHCP & DNS Server',
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
                  '.${overview.dnsConfig.localDomain} Domain',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    context,
                    label: 'Active Leases',
                    value: '${overview.activeLeases.length}',
                    icon: Icons.badge_outlined,
                    color: Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildMetricTile(
                    context,
                    label: 'Static Mappings',
                    value: '${overview.staticMappings.length}',
                    icon: Icons.pin_drop_outlined,
                    color: Colors.teal,
                  ),
                ),
                Expanded(
                  child: _buildMetricTile(
                    context,
                    label: 'Upstream DNS',
                    value:
                        overview.dnsConfig.upstreamDnsServers.firstOrNull ??
                        '1.1.1.1',
                    icon: Icons.public_outlined,
                    color: Colors.indigo,
                  ),
                ),
                Expanded(
                  child: _buildMetricTile(
                    context,
                    label: 'DNS Rebind',
                    value: overview.dnsConfig.rebindProtection ? 'ON' : 'OFF',
                    icon: Icons.verified_user_outlined,
                    color: overview.dnsConfig.rebindProtection
                        ? Colors.green
                        : Colors.grey,
                  ),
                ),
              ],
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
