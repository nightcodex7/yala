// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/luci_loading_states.dart';
import '../models/dhcp_dns_info.dart';
import '../utils/dns_provider_resolver.dart';

class DhcpDnsCard extends ConsumerWidget {
  const DhcpDnsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    final overview = DhcpDnsOverview.fromDashboardData(appState.dashboardData);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;

    final isCardLoading =
        appState.isDashboardLoading && appState.dashboardData == null;

    final domain = overview.dnsConfig.localDomain.trim();
    final localDomainDisplay = domain.isNotEmpty
        ? (domain.startsWith('.') ? domain : '.$domain')
        : '.lan';

    final forwarderText = _formatDnsForwarder(overview);
    final isRebindProtected = overview.dnsConfig.rebindProtection;
    final rebindText = isRebindProtected
        ? (l10n?.statusEnabled ?? 'Enabled')
        : (l10n?.statusDisabled ?? 'OFF');

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Header: Icon, single-line Title, and compact Domain badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.dns_outlined, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n?.dhcpDnsTitle ?? 'DHCP & DNS Management',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7.0,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                      width: 0.8,
                    ),
                  ),
                  child: isCardLoading
                      ? const LuciSkeleton(
                          width: 30,
                          height: 12,
                          borderRadius: BorderRadius.all(Radius.circular(3)),
                        )
                      : Text(
                          localDomainDisplay,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 2. Body: Responsive 4-metric display optimized for all screen and font scales
            LayoutBuilder(
              builder: (context, constraints) {
                final textScale = MediaQuery.textScalerOf(context).scale(1.0);
                final bool isCompact =
                    constraints.maxWidth < 340 || textScale > 1.25;

                final tileLeases = _buildMetricTile(
                  context,
                  label: l10n?.dhcpDnsActiveLeases ?? 'Active Leases',
                  value: '${overview.activeLeases.length}',
                  icon: Icons.devices_outlined,
                  color: Colors.blue,
                  isLoading: isCardLoading,
                  semanticsLabel:
                      '${l10n?.dhcpDnsActiveLeases ?? "Active Leases"}: ${overview.activeLeases.length}',
                );

                final tileStatic = _buildMetricTile(
                  context,
                  label: l10n?.dhcpDnsStaticMappings ?? 'Static Mappings',
                  value: '${overview.staticMappings.length}',
                  icon: Icons.push_pin_outlined,
                  color: Colors.teal,
                  isLoading: isCardLoading,
                  semanticsLabel:
                      '${l10n?.dhcpDnsStaticMappings ?? "Static Mappings"}: ${overview.staticMappings.length}',
                );

                final tileForwarder = _buildMetricTile(
                  context,
                  label: l10n?.dhcpDnsForwarders ?? 'DNS Forwarders',
                  value: forwarderText,
                  icon: Icons.public_outlined,
                  color: Colors.indigo,
                  isLoading: isCardLoading,
                  semanticsLabel:
                      overview.resolvedDnsSummary ??
                      '${l10n?.dhcpDnsForwarders ?? "DNS Forwarders"}: $forwarderText',
                );

                final tileRebind = _buildMetricTile(
                  context,
                  label: l10n?.dhcpCardDnsRebind ?? 'DNS Rebind',
                  value: rebindText,
                  icon: Icons.verified_user_outlined,
                  color: isRebindProtected
                      ? Colors.green
                      : (isDarkMode
                            ? Colors.grey.shade400
                            : Colors.grey.shade600),
                  valueColor: isRebindProtected
                      ? Colors.green
                      : (isDarkMode
                            ? Colors.grey.shade400
                            : Colors.grey.shade600),
                  isLoading: isCardLoading,
                  semanticsLabel:
                      '${l10n?.dhcpCardDnsRebind ?? "DNS Rebind"}: $rebindText',
                );

                if (isCompact) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(child: tileLeases),
                          const SizedBox(width: 8),
                          Expanded(child: tileStatic),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: tileForwarder),
                          const SizedBox(width: 8),
                          Expanded(child: tileRebind),
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: tileLeases),
                    Expanded(child: tileStatic),
                    Expanded(child: tileForwarder),
                    Expanded(child: tileRebind),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDnsForwarder(DhcpDnsOverview overview) {
    final servers = overview.dnsConfig.upstreamDnsServers;
    if (servers.isEmpty) return 'ISP Default';
    final first = servers.first.trim();
    if (first.isEmpty ||
        first.toLowerCase().contains('isp default') ||
        first.toLowerCase().contains('dynamic dns')) {
      return 'ISP Default';
    }

    // When dnsmasq forwards to a local loopback proxy (e.g. 127.0.0.1#5053),
    // display the real upstream DNS provider (e.g. "Quad9 (DoH)").
    if (DnsProviderResolver.isLoopback(first)) {
      if (overview.resolvedDnsProvider != null &&
          overview.resolvedDnsProvider!.isNotEmpty) {
        if (servers.length > 1) {
          return '${overview.resolvedDnsProvider!} (+${servers.length - 1})';
        }
        return overview.resolvedDnsProvider!;
      }
    }

    if (servers.length > 1) {
      return '$first (+${servers.length - 1})';
    }
    return first;
  }

  Widget _buildMetricTile(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    Color? valueColor,
    bool isLoading = false,
    String? semanticsLabel,
  }) {
    final theme = Theme.of(context);
    return Semantics(
      label: semanticsLabel ?? '$label: $value',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 5),
          SizedBox(
            height: 28,
            child: Center(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  fontSize: 10.5,
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 3),
          if (isLoading)
            const LuciSkeleton(
              width: 32,
              height: 14,
              borderRadius: BorderRadius.all(Radius.circular(3)),
            )
          else
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 12.0,
                  color: valueColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}
