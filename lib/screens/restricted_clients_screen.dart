// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/utils/os_platform_integration.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import '../main.dart';

class RestrictedClientsScreen extends ConsumerStatefulWidget {
  const RestrictedClientsScreen({super.key});

  @override
  ConsumerState<RestrictedClientsScreen> createState() =>
      _RestrictedClientsScreenState();
}

class _RestrictedClientsScreenState
    extends ConsumerState<RestrictedClientsScreen> {
  bool _isLoading = true;
  Map<String, List<Map<String, dynamic>>> _liveData = {
    'restricted': [],
    'banned': [],
  };

  @override
  void initState() {
    super.initState();
    _fetchLiveData();
  }

  Future<void> _fetchLiveData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    final appState = ref.read(appStateProvider);
    final data = await appState.fetchRestrictedAndBannedClientsLive(
      context: context,
    );

    if (mounted) {
      final seenRestricted = <String>{};
      final cleanRestricted = <Map<String, dynamic>>[];
      for (final item in (data['restricted'] ?? [])) {
        final m = item['mac']?.toString().toUpperCase() ?? '';
        if (m.isNotEmpty && seenRestricted.add(m)) {
          cleanRestricted.add(item);
        }
      }

      final seenBanned = <String>{};
      final cleanBanned = <Map<String, dynamic>>[];
      for (final item in (data['banned'] ?? [])) {
        final m = item['mac']?.toString().toUpperCase() ?? '';
        if (m.isNotEmpty && seenBanned.add(m)) {
          cleanBanned.add(item);
        }
      }

      setState(() {
        _liveData = {'restricted': cleanRestricted, 'banned': cleanBanned};
        _isLoading = false;
      });
    }
  }

  Future<void> _handleUnpause(String mac, String name) async {
    final actionKey = 'unpause_$mac';
    final appState = ref.read(appStateProvider);
    if (mounted) {
      context.showToastLoading(
        'Resuming internet for $name...',
        actionKey: actionKey,
      );
    }

    final success = await appState.pauseClientInternet(
      mac,
      pause: false,
      context: context,
    );
    if (!mounted) return;

    if (success) {
      unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.medium));
      context.showToastSuccess(
        'Internet restored for $name.',
        actionKey: actionKey,
      );
      await _fetchLiveData();
    } else {
      unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));
      context.showToastError(
        'Failed to restore internet for $name.',
        actionKey: actionKey,
      );
    }
  }

  Future<void> _handleUnban(String mac, String name) async {
    final actionKey = 'unban_$mac';
    final appState = ref.read(appStateProvider);
    if (mounted) {
      context.showToastLoading(
        'Unbanning Wi-Fi access for $name...',
        actionKey: actionKey,
      );
    }

    final success = await appState.unbanWirelessClient(mac, context: context);

    if (success) {
      unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.medium));
      if (mounted) {
        LuciToastManager.safeShowSuccess(
          context,
          'Client $name unbanned successfully.',
          actionKey: actionKey,
        );
        await _fetchLiveData();
      }
    } else {
      unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));
      if (mounted) {
        LuciToastManager.safeShowError(
          context,
          'Failed to unban client $name.',
          actionKey: actionKey,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final restrictedList = _liveData['restricted'] ?? [];
    final bannedList = _liveData['banned'] ?? [];
    final totalCount = restrictedList.length + bannedList.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Banned Clients'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Live Router Fetch',
            onPressed: _fetchLiveData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Fetching live banned clients directly from router...'),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchLiveData,
              child: totalCount == 0
                  ? ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        const SizedBox(height: 60),
                        Icon(
                          Icons.verified_user_outlined,
                          size: 72,
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.6,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No Banned Clients',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'All connected devices have full network and Wi-Fi access. Any banned devices will appear here in real-time.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      children: [
                        if (restrictedList.isNotEmpty) ...[
                          _buildSectionHeader(
                            context,
                            title: 'Internet Paused Clients',
                            subtitle:
                                'Access restricted via router firewall rules',
                            icon: Icons.pause_circle_outline,
                            color: Colors.orange,
                            count: restrictedList.length,
                          ),
                          const SizedBox(height: 12),
                          ...restrictedList.map(
                            (client) => _buildRestrictedTile(
                              context,
                              client: client,
                              onAction: () => _handleUnpause(
                                client['mac'].toString(),
                                client['name'].toString(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        if (bannedList.isNotEmpty) ...[
                          _buildSectionHeader(
                            context,
                            title: 'Wi-Fi Banned Devices',
                            subtitle:
                                'Kicked & blacklisted from Wi-Fi association',
                            icon: Icons.block_outlined,
                            color: Colors.red,
                            count: bannedList.length,
                          ),
                          const SizedBox(height: 12),
                          ...bannedList.map(
                            (client) => _buildBannedTile(
                              context,
                              client: client,
                              onAction: () => _handleUnban(
                                client['mac'].toString(),
                                client['name'].toString(),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required int count,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRestrictedTile(
    BuildContext context, {
    required Map<String, dynamic> client,
    required VoidCallback onAction,
  }) {
    final theme = Theme.of(context);
    final mac = client['mac']?.toString() ?? '';
    final name = client['name']?.toString() ?? mac;
    final ip = client['ip']?.toString() ?? 'N/A';
    final source = client['source']?.toString() ?? 'Firewall Rule';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: Colors.orange.withValues(alpha: 0.15),
          child: const Icon(Icons.pause, color: Colors.orange),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('IP: $ip • MAC: $mac'),
            const SizedBox(height: 2),
            Text(
              'Context: $source',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
        trailing: FilledButton.tonalIcon(
          onPressed: onAction,
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('Resume'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green.withValues(alpha: 0.15),
            foregroundColor: Colors.green.shade700,
          ),
        ),
      ),
    );
  }

  Widget _buildBannedTile(
    BuildContext context, {
    required Map<String, dynamic> client,
    required VoidCallback onAction,
  }) {
    final theme = Theme.of(context);
    final mac = client['mac']?.toString() ?? '';
    final name = client['name']?.toString() ?? mac;
    final ip = client['ip']?.toString() ?? 'N/A';
    final source = client['source']?.toString() ?? 'Wi-Fi Access Control';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: Colors.red.withValues(alpha: 0.15),
          child: const Icon(Icons.block, color: Colors.red),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('IP: $ip • MAC: $mac'),
            const SizedBox(height: 2),
            Text(
              'Context: $source',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.red.shade700,
              ),
            ),
          ],
        ),
        trailing: FilledButton.tonalIcon(
          onPressed: onAction,
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('Unban'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.blue.withValues(alpha: 0.15),
            foregroundColor: Colors.blue.shade700,
          ),
        ),
      ),
    );
  }
}
