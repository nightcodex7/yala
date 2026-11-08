// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import '../controllers/adguard_controller.dart';
import '../models/adguard_models.dart';
import 'configure_router_dns_dialog.dart';
import 'revert_router_dns_dialog.dart';

/// Card displaying DNS topology and routing architecture inferred from
/// UCI configurations and listening ports.
///
/// NOTE: Adheres strictly to the invariant that inferred topology must never
/// claim verified packet-capture live traffic flow.
class AdGuardTopologyCard extends StatelessWidget {
  final AdGuardDnsTopology topology;
  final AdGuardController? controller;
  final String? routerId;

  const AdGuardTopologyCard({
    super.key,
    required this.topology,
    this.controller,
    this.routerId,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    String modeName;
    switch (topology.mode) {
      case AdGuardTopologyMode.adguardPrimary:
        modeName = l10n?.aghTopologyModeDirect ?? 'Direct Port 53';
        break;
      case AdGuardTopologyMode.dnsmasqForwarder:
        modeName =
            l10n?.aghTopologyModeDnsmasqUpstream ??
            'Dnsmasq -> AdGuard (Upstream)';
        break;
      case AdGuardTopologyMode.firewallRedirect:
        modeName = l10n?.aghTopologyModeRedirect ?? 'Port Forward / Redirect';
        break;
      case AdGuardTopologyMode.standalone:
        modeName =
            topology.routingStatus == AdGuardDnsRoutingStatus.externalStandalone
            ? (l10n?.aghRoutingExternalStandalone ?? 'External Standalone')
            : (l10n?.aghTopologyModeCustom ?? 'Custom / Non-Standard');
        break;
      case AdGuardTopologyMode.stopped:
        modeName = l10n?.aghStatusStopped ?? 'Stopped';
        break;
      case AdGuardTopologyMode.unknown:
        modeName = l10n?.aghTopologyModeUnknown ?? 'Unknown';
        break;
    }

    // Routing status label & coloring (8 states)
    String routingStatusName;
    Color routingStatusBg;
    Color routingStatusFg;

    switch (topology.routingStatus) {
      case AdGuardDnsRoutingStatus.apiReachableOnly:
        routingStatusName = l10n?.aghRoutingApiOnly ?? 'API Reachable Only';
        routingStatusBg = colorScheme.surfaceContainerHighest;
        routingStatusFg = colorScheme.onSurfaceVariant;
        break;
      case AdGuardDnsRoutingStatus.serviceRunningOnly:
        routingStatusName =
            l10n?.aghRoutingServiceRunning ?? 'Service Running Only';
        routingStatusBg = colorScheme.surfaceContainerHighest;
        routingStatusFg = colorScheme.onSurfaceVariant;
        break;
      case AdGuardDnsRoutingStatus.routerForwardingUnverified:
        routingStatusName =
            l10n?.aghRoutingForwardingUnverified ?? 'Forwarding Unverified';
        routingStatusBg = colorScheme.secondaryContainer;
        routingStatusFg = colorScheme.onSecondaryContainer;
        break;
      case AdGuardDnsRoutingStatus.routerForwardingVerified:
        routingStatusName =
            l10n?.aghRoutingForwardingVerified ?? 'Router Forwarding Verified';
        routingStatusBg = colorScheme.primaryContainer;
        routingStatusFg = colorScheme.onPrimaryContainer;
        break;
      case AdGuardDnsRoutingStatus.clientUsageVerified:
        routingStatusName =
            l10n?.aghRoutingClientVerified ?? 'Client Queries Verified';
        routingStatusBg = Colors.green.withValues(alpha: 0.15);
        routingStatusFg = Colors.green.shade800;
        break;
      case AdGuardDnsRoutingStatus.externalStandalone:
        routingStatusName =
            l10n?.aghRoutingExternalStandalone ?? 'External Standalone';
        routingStatusBg = colorScheme.surfaceContainerHighest;
        routingStatusFg = colorScheme.onSurfaceVariant;
        break;
      case AdGuardDnsRoutingStatus.misconfiguredOrUnavailable:
        routingStatusName =
            l10n?.aghRoutingMisconfigured ?? 'Routing Misconfigured';
        routingStatusBg = colorScheme.errorContainer;
        routingStatusFg = colorScheme.onErrorContainer;
        break;
      case AdGuardDnsRoutingStatus.unknown:
        routingStatusName = l10n?.aghRoutingUnknown ?? 'Routing Unknown';
        routingStatusBg = colorScheme.surfaceContainerHighest;
        routingStatusFg = colorScheme.onSurfaceVariant;
        break;
    }

    // IPv6 Status
    String ipv6StatusName;
    Color ipv6Color;
    switch (topology.ipv6Status) {
      case Ipv6DnsStatus.noBypassDetected:
        ipv6StatusName = l10n?.aghIpv6NoBypass ?? 'Aligned / No Bypass';
        ipv6Color = Colors.green.shade700;
        break;
      case Ipv6DnsStatus.externalAdvertisementBypass:
        ipv6StatusName =
            l10n?.aghIpv6ExternalBypass ?? 'External IPv6 DNS Advertised';
        ipv6Color = colorScheme.error;
        break;
      case Ipv6DnsStatus.unsupportedIpv6Listener:
        ipv6StatusName =
            l10n?.aghIpv6UnsupportedListener ?? 'No IPv6 Listener in AdGuard';
        ipv6Color = LuciStatusColors.warningColor(context);
        break;
      case Ipv6DnsStatus.unableToVerify:
        ipv6StatusName =
            l10n?.aghIpv6UnableToVerify ??
            'Unable to verify IPv6 advertisement';
        ipv6Color = colorScheme.onSurfaceVariant;
        break;
    }

    final forwardersStr = topology.forwarders.isNotEmpty
        ? topology.forwarders.join(', ')
        : 'None';

    final isForwarded =
        topology.routingStatus ==
            AdGuardDnsRoutingStatus.routerForwardingVerified ||
        topology.routingStatus ==
            AdGuardDnsRoutingStatus.routerForwardingUnverified ||
        topology.routingStatus == AdGuardDnsRoutingStatus.clientUsageVerified;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.hub_outlined, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n?.aghTopology ?? 'DNS Topology',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color:
                        topology.routingStatus ==
                            AdGuardDnsRoutingStatus.externalStandalone
                        ? colorScheme.surfaceContainerHighest
                        : colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    modeName,
                    key: const Key('agh_topology_mode_badge'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          topology.routingStatus ==
                              AdGuardDnsRoutingStatus.externalStandalone
                          ? colorScheme.onSurfaceVariant
                          : colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),

            // Routing Status Badge Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n?.aghRoutingStatus ?? 'Routing Status',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: routingStatusBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    routingStatusName,
                    key: const Key('agh_topology_routing_status_badge'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: routingStatusFg,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Metadata rows
            _buildRow(
              context,
              label: 'AdGuard DNS Port',
              value: '${topology.adguardDnsPort}',
              keyName: 'agh_topology_adguard_port',
            ),
            if (topology.dnsmasqPort > 0) ...[
              const SizedBox(height: 8),
              _buildRow(
                context,
                label:
                    topology.routingStatus ==
                        AdGuardDnsRoutingStatus.externalStandalone
                    ? 'Router Dnsmasq Port'
                    : 'Dnsmasq Port',
                value: '${topology.dnsmasqPort}',
                keyName: 'agh_topology_dnsmasq_port',
              ),
            ],
            const SizedBox(height: 8),
            _buildRow(
              context,
              label: 'Configured Forwarders',
              value: forwardersStr,
              keyName: 'agh_topology_forwarders',
            ),
            const SizedBox(height: 8),
            _buildRow(
              context,
              label: 'Firewall Redirect',
              value: topology.hasFirewallRedirect ? 'Active' : 'None',
              keyName: 'agh_topology_redirect',
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'IPv6 Handling',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Flexible(
                  child: Text(
                    ipv6StatusName,
                    key: const Key('agh_topology_ipv6_status'),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: ipv6Color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildRow(
              context,
              label: 'IPv6 Listener',
              value: topology.isIpv6Supported
                  ? (l10n?.aghTopologyIpv6Supported ?? 'IPv6 Supported')
                  : (l10n?.aghTopologyIpv6NotDetected ?? 'IPv6 Not Detected'),
              keyName: 'agh_topology_ipv6',
            ),

            if (topology.statusEvidence.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.35,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      topology.isClientUsageVerified
                          ? Icons.verified_user_outlined
                          : Icons.find_in_page_outlined,
                      size: 16,
                      color: topology.isClientUsageVerified
                          ? Colors.green
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        topology.statusEvidence,
                        key: const Key('agh_topology_status_evidence'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Mandatory Disclaimer Box
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n?.aghTopologyDisclaimer ??
                          'Inferred from configuration and telemetry; not raw live packet capture',
                      key: const Key('agh_topology_disclaimer_text'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Configure Router DNS Action Button
            if (controller != null && routerId != null) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('agh_configure_router_dns_btn'),
                  icon: Icon(
                    Icons.alt_route,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  label: Text(
                    isForwarded
                        ? (l10n?.aghReconfigureRouterDns ??
                              'Reconfigure Router DNS')
                        : (l10n?.aghConfigureRouterDns ??
                              'Configure Router DNS'),
                  ),
                  onPressed: () {
                    ConfigureRouterDnsDialog.show(
                      context,
                      controller: controller!,
                      routerId: routerId!,
                    );
                  },
                ),
              ),
              if (isForwarded || topology.forwarders.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const Key('agh_revert_router_dns_btn'),
                    icon: Icon(
                      Icons.delete_sweep_outlined,
                      size: 18,
                      color: colorScheme.error,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.error,
                      side: BorderSide(
                        color: colorScheme.error.withValues(alpha: 0.5),
                      ),
                    ),
                    label: Text(
                      l10n?.aghRevertRouterDns ?? 'Remove Forwarding',
                    ),
                    onPressed: () {
                      RevertRouterDnsDialog.show(
                        context,
                        controller: controller!,
                        routerId: routerId!,
                      );
                    },
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRow(
    BuildContext context, {
    required String label,
    required String value,
    required String keyName,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            key: Key(keyName),
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
