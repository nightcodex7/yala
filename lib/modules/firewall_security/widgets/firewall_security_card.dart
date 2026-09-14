// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import '../models/firewall_info.dart';

class FirewallSecurityCard extends ConsumerWidget {
  const FirewallSecurityCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    final backend =
        appState.capabilities?.firewallBackend ?? FirewallBackend.fw4;
    final uciFirewall = appState.dashboardData?['uciFirewallConfig'];
    final overview = FirewallOverview.fromUciData(
      uciFirewall,
      backend: backend,
      isReviewerMode: appState.reviewerModeEnabled,
    );

    final defPolicy = overview.defaultPolicy;

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
                Row(
                  children: [
                    Icon(
                      Icons.security_outlined,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Firewall & Security',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${overview.zones.length} Zones',
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
                  child: _buildPolicyTile(
                    context,
                    label: 'Input Policy',
                    value: defPolicy.input,
                    color: _getPolicyColor(defPolicy.input),
                  ),
                ),
                Expanded(
                  child: _buildPolicyTile(
                    context,
                    label: 'Output Policy',
                    value: defPolicy.output,
                    color: _getPolicyColor(defPolicy.output),
                  ),
                ),
                Expanded(
                  child: _buildPolicyTile(
                    context,
                    label: 'Forward Policy',
                    value: defPolicy.forward,
                    color: _getPolicyColor(defPolicy.forward),
                  ),
                ),
                Expanded(
                  child: _buildPolicyTile(
                    context,
                    label: 'SYN Flood',
                    value: defPolicy.synFlood ? 'PROTECTED' : 'OFF',
                    color: defPolicy.synFlood ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPolicyTile(
    BuildContext context, {
    required String label,
    required String value,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            fontSize: 10,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Color _getPolicyColor(String policy) {
    switch (policy.toUpperCase()) {
      case 'ACCEPT':
        return Colors.green;
      case 'REJECT':
        return Colors.orange;
      case 'DROP':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }
}
