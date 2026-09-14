// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/add_static_lease_dialog.dart';
import '../models/dhcp_dns_info.dart';

import 'package:yet_another_luci_app/widgets/luci_collapsible_card.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';

class DhcpDnsScreen extends ConsumerWidget {
  const DhcpDnsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    final dashboardData = Map<String, dynamic>.from(
      appState.dashboardData ?? {},
    );
    dashboardData['clients'] = appState.clients
        .map(
          (c) => {
            'macAddress': c.macAddress,
            'ipAddress': c.ipAddress,
            'name': c.displayName,
            'isStaticLease': c.isStaticLease,
            'isConnected': c.isConnected,
          },
        )
        .toList();
    final overview = DhcpDnsOverview.fromDashboardData(
      dashboardData,
      isReviewerMode: appState.reviewerModeEnabled,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('DHCP & DNS Management')),
      body: RefreshIndicator(
        onRefresh: () async {
          await appState.fetchDashboardData();
          await appState.fetchClientsForSelectedRouter();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 100.0),
          children: [
            _buildSectionHeader(
              context,
              'DNS Forwarders & Dnsmasq Config',
              Icons.dns_outlined,
            ),
            const SizedBox(height: 8),
            _buildDnsConfigCard(context, overview.dnsConfig),
            const SizedBox(height: 16),
            LuciCollapsibleCard(
              title: 'Active DHCP Leases',
              count: overview.activeLeases.length,
              subtitle: '${overview.activeLeases.length} active client leases',
              icon: Icons.badge_outlined,
              iconColor: Colors.blue,
              child: _buildLeasesList(
                context,
                ref,
                appState,
                overview.activeLeases,
                overview.staticMappings,
              ),
            ),
            const SizedBox(height: 16),
            LuciCollapsibleCard(
              title: 'Static IP Reservations',
              count: overview.staticMappings.length,
              subtitle:
                  '${overview.staticMappings.length} static IP mappings configured',
              icon: Icons.pin_drop_outlined,
              iconColor: Colors.teal,
              trailingAction: IconButton(
                icon: const Icon(Icons.add_circle_outline, color: Colors.teal),
                tooltip: 'Add Static Lease',
                onPressed: () => _showAddStaticLeaseDialog(context, ref),
              ),
              child: _buildStaticMappingsList(
                context,
                ref,
                appState,
                overview.staticMappings,
              ),
            ),
            const SizedBox(height: 32),
          ],
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
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildDnsConfigCard(BuildContext context, DnsmasqConfig config) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow(
              context,
              'Local Domain Name',
              '.${config.localDomain}',
            ),
            const Divider(height: 16),
            _buildDetailRow(
              context,
              'Upstream DNS Forwarders',
              config.upstreamDnsServers.join(', '),
            ),
            const Divider(height: 16),
            _buildDetailRow(
              context,
              'Rebind Protection',
              config.rebindProtection ? 'ENABLED' : 'DISABLED',
            ),
            const Divider(height: 16),
            _buildDetailRow(
              context,
              'Domain Needed (Strict Order)',
              config.domainNeeded ? 'ENABLED' : 'DISABLED',
            ),
            const Divider(height: 16),
            _buildDetailRow(
              context,
              'Authoritative Mode',
              config.authoritative ? 'ENABLED' : 'DISABLED',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeasesList(
    BuildContext context,
    WidgetRef ref,
    dynamic appState,
    List<DhcpLease> leases,
    List<DhcpStaticMapping> staticMappings,
  ) {
    if (leases.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('No active DHCP leases currently assigned.'),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // ignore: deprecated_member_use
      cacheExtent: 250.0,
      itemCount: leases.length,
      // ignore: deprecated_member_use
      findChildIndexCallback: (Key key) {
        if (key is ValueKey<String>) {
          final index = leases.indexWhere((l) => l.macAddress == key.value);
          return index != -1 ? index : null;
        }
        return null;
      },
      itemBuilder: (context, index) {
        final lease = leases[index];
        final normLeaseMac = lease.macAddress.toUpperCase().replaceAll(
          '-',
          ':',
        );
        final normLeaseIp = lease.ipAddress.trim();

        DhcpStaticMapping? matchingStatic;
        for (final m in staticMappings) {
          final mMacs = m.macAddress.toUpperCase().replaceAll('-', ':');
          final mIp = m.ipAddress.trim();
          if ((normLeaseMac.isNotEmpty &&
                  normLeaseMac != 'N/A' &&
                  mMacs.contains(normLeaseMac)) ||
              (normLeaseIp.isNotEmpty &&
                  normLeaseIp != 'N/A' &&
                  mIp == normLeaseIp)) {
            matchingStatic = m;
            break;
          }
        }
        final isStatic = matchingStatic != null;
        final leaseIcon = _resolveLeaseIcon(
          appState,
          lease.macAddress,
          lease.hostname,
        );

        return Card(
          key: ValueKey<String>(lease.macAddress),
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isStatic
                  ? Colors.teal.withValues(alpha: 0.15)
                  : Colors.blue.withValues(alpha: 0.15),
              child: Icon(
                leaseIcon,
                color: isStatic ? Colors.teal : Colors.blue,
              ),
            ),
            title: Text(
              lease.hostname,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('IP: ${lease.ipAddress} • MAC: ${lease.macAddress}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  lease.formattedExpiry,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                if (isStatic)
                  IconButton(
                    icon: const Icon(
                      Icons.edit_outlined,
                      size: 20,
                      color: Colors.teal,
                    ),
                    tooltip: 'Edit Static Lease',
                    onPressed: () => _showAddStaticLeaseDialog(
                      context,
                      ref,
                      existingMapping: matchingStatic,
                      lease: lease,
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(
                      Icons.bookmark_add_outlined,
                      size: 20,
                      color: Colors.blue,
                    ),
                    tooltip: 'Reserve as Static IP',
                    onPressed: () =>
                        _showAddStaticLeaseDialog(context, ref, lease: lease),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStaticMappingsList(
    BuildContext context,
    WidgetRef ref,
    dynamic appState,
    List<DhcpStaticMapping> mappings,
  ) {
    if (mappings.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('No static host reservations configured.'),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // ignore: deprecated_member_use
      cacheExtent: 250.0,
      itemCount: mappings.length,
      // ignore: deprecated_member_use
      findChildIndexCallback: (Key key) {
        if (key is ValueKey<String>) {
          final index = mappings.indexWhere((m) => m.macAddress == key.value);
          return index != -1 ? index : null;
        }
        return null;
      },
      itemBuilder: (context, index) {
        final mapping = mappings[index];
        final mappingIcon = _resolveLeaseIcon(
          appState,
          mapping.macAddress,
          mapping.hostname,
        );
        return Card(
          key: ValueKey<String>(mapping.macAddress),
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.teal.withValues(alpha: 0.15),
              child: Icon(mappingIcon, color: Colors.teal),
            ),
            title: Text(
              mapping.hostname,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Reserved IP: ${mapping.ipAddress} • MAC: ${mapping.macAddress}',
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
                    color: Colors.teal.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'STATIC',
                    style: TextStyle(
                      color: Colors.teal,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(
                    Icons.edit_outlined,
                    color: Colors.teal,
                    size: 20,
                  ),
                  tooltip: 'Edit Static Lease',
                  onPressed: () => _showAddStaticLeaseDialog(
                    context,
                    ref,
                    existingMapping: mapping,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                    size: 20,
                  ),
                  tooltip: 'Remove Static Lease',
                  onPressed: () =>
                      _confirmDeleteStaticLease(context, ref, mapping),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteStaticLease(
    BuildContext context,
    WidgetRef ref,
    DhcpStaticMapping mapping,
  ) async {
    if (ActionRateLimiter.isRateLimited(
      'delete_static_lease_${mapping.macAddress}',
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
          'Are you sure you want to remove the static IP reservation for "${mapping.hostname}" (${mapping.macAddress})?',
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
      final actionKey = 'delete_static_lease_${mapping.macAddress}';
      context.showToastLoading(
        'Removing static lease for ${mapping.hostname}...',
        actionKey: actionKey,
      );

      final appState = ref.read(appStateProvider);
      final success = await appState.deleteStaticLease(
        macAddress: mapping.macAddress,
        targetIp: mapping.ipAddress.isNotEmpty && mapping.ipAddress != 'N/A'
            ? mapping.ipAddress
            : null,
        hostname:
            mapping.hostname.isNotEmpty && mapping.hostname != 'Unnamed Host'
                ? mapping.hostname
                : null,
        duid: mapping.duid.isNotEmpty && mapping.duid != 'N/A'
            ? mapping.duid
            : null,
        context: context,
      );

      if (!context.mounted) return;

      if (success) {
        appState.invalidateStaticLeasesCache();
        context.showToastSuccess(
          'Static lease removed for ${mapping.hostname}.',
          actionKey: actionKey,
        );
        unawaited(appState.fetchDashboardData());
        unawaited(appState.fetchClientsForSelectedRouter());
      } else {
        context.showToastError(
          'Failed to remove static lease for ${mapping.hostname}.',
          actionKey: actionKey,
        );
      }
    }
  }

  void _showAddStaticLeaseDialog(
    BuildContext context,
    WidgetRef ref, {
    DhcpLease? lease,
    DhcpStaticMapping? existingMapping,
  }) {
    final appState = ref.read(appStateProvider);
    showDialog(
      context: context,
      builder: (dialogCtx) => AddStaticLeaseDialog(
        macAddress: lease?.macAddress ?? existingMapping?.macAddress,
        initialIp: lease?.ipAddress ?? existingMapping?.ipAddress,
        initialHostname: lease?.hostname ?? existingMapping?.hostname,
        existingMapping: existingMapping,
        allClients: appState.clients,
        onSaved: () async {
          await appState.fetchDashboardData();
          await appState.fetchClientsForSelectedRouter();
        },
      ),
    );
  }

  IconData _resolveLeaseIcon(
    dynamic appState,
    String macAddress,
    String hostname,
  ) {
    final normMac = ClientNamingHelper.normalizeMac(macAddress);
    final client = appState.findClientByMac(normMac);
    if (client != null && client.isConnected) {
      return ClientNamingHelper.getDeviceIcon(client, fallbackName: hostname);
    }
    return Icons.push_pin;
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}
