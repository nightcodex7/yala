// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../models/network_topology.dart';
import '../models/router_capabilities.dart';
import '../design/luci_design_system.dart';
import '../l10n/app_localizations.dart';
import 'luci_loading_states.dart';

class NetworkTopologyCard extends StatelessWidget {
  final NetworkTopology? topology;
  final VoidCallback? onRetry;
  final bool isLoading;

  const NetworkTopologyCard({
    super.key,
    required this.topology,
    this.onRetry,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    if (isLoading) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
        shape: RoundedRectangleBorder(
          borderRadius: LuciCardStyles.standardRadius,
          side: BorderSide(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.10),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.13,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.hub_outlined,
                      color: colorScheme.primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n?.headerSwitchTopology ??
                              'Switch Topology & VLANs',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const LuciSkeleton(
                          width: 120,
                          height: 12,
                          borderRadius: BorderRadius.all(Radius.circular(4)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: List.generate(
                  4,
                  (index) => const Padding(
                    padding: EdgeInsets.only(right: 8.0),
                    child: LuciSkeleton(
                      width: 38,
                      height: 38,
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (topology == null || !topology!.isAvailable) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
        shape: RoundedRectangleBorder(
          borderRadius: LuciCardStyles.standardRadius,
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.hub_outlined,
                  color: colorScheme.onSurfaceVariant,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n?.switchTopologyUnavailable ??
                          'Switch Topology Unavailable',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      topology?.errorMessage ??
                          'Configuration payload empty or probing unsupported.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  tooltip: l10n?.reprobeCapabilities ?? 'Re-probe Capabilities',
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  color: colorScheme.primary,
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (topology!.isZeroVlans) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
        shape: RoundedRectangleBorder(
          borderRadius: LuciCardStyles.standardRadius,
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lan_outlined,
                  color: colorScheme.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n?.flatNetworkTitle ??
                          'Flat Network (0 Configured VLANs)',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n?.flatNetworkMessage(
                            topology!.modelType == NetworkModel.dsa
                                ? "DSA bridge"
                                : "switch",
                          ) ??
                          'Router uses a single unsegmented ${topology!.modelType == NetworkModel.dsa ? "DSA bridge" : "switch"} interface.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isDsa = topology!.modelType == NetworkModel.dsa;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: LuciCardStyles.standardRadius,
        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(LuciSpacing.md),
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
                        isDsa
                            ? Icons.hub_outlined
                            : Icons.settings_input_component,
                        color: colorScheme.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isDsa
                              ? (l10n?.dsaSwitchTopology ??
                                    'DSA Switch Topology')
                              : (l10n?.legacySwconfigTopology ??
                                    'Legacy swconfig Topology'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isDsa ? 'DSA Engine' : 'swconfig Engine',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuciSpacing.sm),
            const Divider(height: 1),
            const SizedBox(height: LuciSpacing.sm),
            Text(
              l10n?.configuredVlansHeader ??
                  'Configured VLANs & Port Memberships',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ...topology!.vlans.map((vlan) => _buildVlanRow(context, vlan)),
          ],
        ),
      ),
    );
  }

  Widget _buildVlanRow(BuildContext context, VlanConfig vlan) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isWanVlan = vlan.vid <= 0 || vlan.name.toLowerCase().contains('wan');
    final tagText = isWanVlan ? 'WAN' : 'VID ${vlan.vid}';
    final tagBgColor = isWanVlan
        ? Colors.amber.shade700.withValues(alpha: 0.2)
        : colorScheme.secondaryContainer;
    final tagTextColor = isWanVlan
        ? Colors.amber.shade900
        : colorScheme.onSecondaryContainer;

    return Container(
      margin: const EdgeInsets.only(bottom: 8.0),
      padding: const EdgeInsets.all(10.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: tagBgColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tagText,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: tagTextColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  vlan.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: vlan.ports
                .map((port) => _buildPortBadge(context, port))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPortBadge(BuildContext context, TopologyPort port) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isUp = port.isUp;
    final isWan = port.isWan;
    final isCpu = port.isCpu;
    final isTagged = port.isTagged;

    final Color badgeColor;
    if (!isUp) {
      badgeColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.45);
    } else if (isWan) {
      badgeColor = Colors.amber.shade700;
    } else if (isCpu) {
      badgeColor = colorScheme.tertiary;
    } else if (isTagged) {
      badgeColor = colorScheme.primary;
    } else {
      badgeColor = colorScheme.secondary;
    }

    final IconData portIcon;
    if (isWan) {
      portIcon = Icons.public;
    } else if (isCpu) {
      portIcon = Icons.memory;
    } else {
      portIcon = Icons.settings_ethernet;
    }

    final tooltipMessage = isCpu
        ? 'Internal CPU / SoC Interconnect'
        : (isWan ? 'WAN Interface' : 'Switch Port');

    return Tooltip(
      message: tooltipMessage,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: !isUp
              ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.2)
              : badgeColor.withValues(alpha: 0.12),
          border: Border.all(
            color: !isUp
                ? colorScheme.outlineVariant.withValues(alpha: 0.4)
                : badgeColor.withValues(alpha: 0.45),
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(portIcon, size: 14, color: badgeColor),
            const SizedBox(width: 5),
            Text(
              port.name,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: isUp ? FontWeight.bold : FontWeight.normal,
                color: badgeColor,
              ),
            ),
            if (port.linkSpeed != null && isUp) ...[
              const SizedBox(width: 4),
              Text(
                '(${port.linkSpeed})',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: badgeColor.withValues(alpha: 0.85),
                ),
              ),
            ],
            if (!isUp) ...[
              const SizedBox(width: 4),
              Text(
                '(Down)',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                  color: badgeColor,
                ),
              ),
            ],
            if (isTagged) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  'T',
                  style: TextStyle(
                    color: isUp ? Colors.white : colorScheme.surface,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
