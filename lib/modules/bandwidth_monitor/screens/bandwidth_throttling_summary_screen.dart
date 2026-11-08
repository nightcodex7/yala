// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/models/client_speed_limit.dart';
import 'package:yet_another_luci_app/widgets/client_speed_limit_dialog.dart';
import 'package:yet_another_luci_app/widgets/luci_app_bar.dart';
import 'package:yet_another_luci_app/widgets/luci_refresh_components.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';

/// Summary screen displaying all clients with active speed throttling
/// for the currently selected router profile.
class BandwidthThrottlingSummaryScreen extends ConsumerStatefulWidget {
  final String? routerId;

  const BandwidthThrottlingSummaryScreen({super.key, this.routerId});

  @override
  ConsumerState<BandwidthThrottlingSummaryScreen> createState() =>
      _BandwidthThrottlingSummaryScreenState();
}

class _BandwidthThrottlingSummaryScreenState
    extends ConsumerState<BandwidthThrottlingSummaryScreen> {
  late Future<List<Map<String, dynamic>>> _throttledFuture;
  bool _isProcessing = false;

  String? get _effectiveRouterId =>
      widget.routerId ?? ref.read(appStateProvider).selectedRouter?.id;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh([String? targetRouterId]) {
    final appState = ref.read(appStateProvider);
    final rKey =
        targetRouterId ?? widget.routerId ?? appState.selectedRouter?.id;
    setState(() {
      _throttledFuture = appState.fetchThrottledClients(routerId: rKey);
    });
  }

  Future<void> _removeLimit(String mac, String displayName) async {
    if (_isProcessing) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dialogL10n = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(
            dialogL10n?.bandwidthThrottlingRemoveConfirmTitle ??
                'Remove Speed Limit',
          ),
          content: Text(
            dialogL10n?.bandwidthThrottlingRemoveConfirmDesc(displayName) ??
                'Are you sure you want to remove bandwidth restrictions for $displayName?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(dialogL10n?.actionCancel ?? 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: Text(dialogL10n?.pkgMgrBtnRemove ?? 'Remove'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);
    final appState = ref.read(appStateProvider);
    final rKey = _effectiveRouterId;
    final success = await appState.removeClientSpeedLimit(
      mac,
      routerId: rKey,
      context: mounted ? context : null,
    );

    if (mounted) {
      final postL10n = AppLocalizations.of(context);
      setState(() => _isProcessing = false);
      if (success) {
        context.showToastSuccess(
          postL10n?.bandwidthThrottlingRemoveSuccess(displayName) ??
              'Speed limit removed for $displayName',
        );
        _refresh(rKey);
      } else {
        context.showToastError(
          postL10n?.bandwidthThrottlingRemoveFailed ??
              'Failed to remove speed limit',
        );
      }
    }
  }

  void _editLimit(Client? client, ClientSpeedLimit limit) async {
    final targetClient =
        client ??
        Client(
          ipAddress: limit.ipAddress,
          macAddress: limit.targetMac,
          hostname: limit.hostname ?? limit.targetMac,
          ipv6Addresses: limit.ipv6Addresses,
        );

    final changed = await ClientSpeedLimitDialog.show(
      context,
      client: targetClient,
      initialLimit: limit,
      routerId: _effectiveRouterId,
    );

    if (changed == true && mounted) {
      _refresh(_effectiveRouterId);
    }
  }

  Future<void> _showAddRestrictionSheet() async {
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final rKey = _effectiveRouterId;

    List<Client> allClients = appState.clients;
    if (allClients.isEmpty) {
      try {
        allClients = await appState.fetchClientsForSelectedRouter();
      } catch (_) {
        allClients = appState.clients;
      }
    }

    if (!mounted) return;

    final l10n = AppLocalizations.of(context);
    if (allClients.isEmpty) {
      final routerName = router?.displayName ?? "this router";
      context.showToastInfo(
        l10n?.bandwidthThrottlingNoClientsDetected(routerName) ??
            'No clients currently detected on $routerName',
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        final sheetL10n = AppLocalizations.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    const Icon(Icons.traffic_rounded),
                    const SizedBox(width: 10),
                    Text(
                      sheetL10n?.bandwidthThrottlingSelectDevice ??
                          'Select Device to Throttle',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: sheetL10n?.actionClose ?? 'Close',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: allClients.length,
                  itemBuilder: (ctx, i) {
                    final c = allClients[i];
                    final isRestricted =
                        appState
                            .getClientSpeedLimit(c.macAddress, routerId: rKey)
                            ?.isEffectivelyRestricted ??
                        false;

                    return ListTile(
                      leading: Icon(
                        c.connectionType == ConnectionType.wireless
                            ? Icons.wifi_rounded
                            : Icons.settings_ethernet_rounded,
                        color: c.isConnected ? Colors.green : Colors.grey,
                      ),
                      title: Text(c.displayName),
                      subtitle: Text('${c.ipAddress} • ${c.macAddress}'),
                      trailing: isRestricted
                          ? Chip(
                              label: Text(
                                sheetL10n?.bandwidthThrottlingChipThrottled ??
                                    'Throttled',
                                style: const TextStyle(fontSize: 10),
                              ),
                              visualDensity: VisualDensity.compact,
                            )
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _editLimit(
                          c,
                          appState.getClientSpeedLimit(
                                c.macAddress,
                                routerId: rKey,
                              ) ??
                              ClientSpeedLimit.unrestricted(
                                targetMac: c.macAddress,
                                ipAddress: c.ipAddress,
                                hostname: c.displayName,
                              ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final router = ref.watch(appStateProvider.select((s) => s.selectedRouter));

    ref.listen<String?>(appStateProvider.select((s) => s.selectedRouter?.id), (
      prev,
      next,
    ) {
      if (prev != next && widget.routerId == null) {
        _refresh(next);
      }
    });

    ref.listen<int>(
      appStateProvider.select(
        (s) => s
            .getActiveSpeedLimitsForRouter(routerId: _effectiveRouterId)
            .length,
      ),
      (prev, next) {
        if (prev != next) {
          _refresh(_effectiveRouterId);
        }
      },
    );

    return Scaffold(
      appBar: LuciAppBar(
        titleWidget: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n?.bandwidthThrottlingTitle ?? 'Bandwidth Throttling'),
            Text(
              router != null
                  ? (router.name != null && router.name!.trim().isNotEmpty
                        ? '${router.name} (${router.ipAddress})'
                        : router.ipAddress)
                  : 'Active Router',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: l10n?.bandwidthThrottlingAddLimit ?? 'Add Speed Limit',
            onPressed: _showAddRestrictionSheet,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l10n?.actionRefresh ?? 'Refresh',
            onPressed: _refresh,
          ),
        ],
      ),
      body: LuciPullToRefresh(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _throttledFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final items = snapshot.data ?? [];

            if (items.isEmpty) {
              return _buildEmptyState(context, router);
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildHeaderSummaryCard(context, items),
                const SizedBox(height: 16),
                Text(
                  l10n?.bandwidthThrottlingThrottledDevices(items.length) ??
                      'Throttled Devices (${items.length})',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                ...items.map((item) {
                  final limit = item['limit'] as ClientSpeedLimit;
                  final client = item['client'] as Client?;
                  final displayName = item['displayName'] as String;
                  final ip = item['ipAddress'] as String;
                  final mac = item['targetMac'] as String;
                  final isConnected = item['isConnected'] as bool;
                  final connType = item['connectionType'] as ConnectionType;

                  return _buildThrottledClientCard(
                    context,
                    limit: limit,
                    client: client,
                    displayName: displayName,
                    ip: ip,
                    mac: mac,
                    isConnected: isConnected,
                    connType: connType,
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeaderSummaryCard(
    BuildContext context,
    List<Map<String, dynamic>> items,
  ) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    double totalDlBits = 0;
    double totalUlBits = 0;
    int activeCount = 0;

    for (final item in items) {
      final l = item['limit'] as ClientSpeedLimit;
      if (l.enabled) {
        activeCount++;
        totalDlBits += l.downloadBitsPerSecond;
        totalUlBits += l.uploadBitsPerSecond;
      }
    }

    final totalDlStr = totalDlBits > 0
        ? Client.formatSpeed(totalDlBits / 8.0, speedUnit: 'bits')
        : '0 Mbps';
    final totalUlStr = totalUlBits > 0
        ? Client.formatSpeed(totalUlBits / 8.0, speedUnit: 'bits')
        : '0 Mbps';

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.traffic_rounded,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n?.bandwidthThrottlingActiveRestrictions(
                              activeCount,
                            ) ??
                            '$activeCount Active Speed ${activeCount == 1 ? "Restriction" : "Restrictions"}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Total throttled bandwidth allocation',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.arrow_downward_rounded,
                            size: 14,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            l10n?.bandwidthThrottlingMaxCombinedDl ??
                                'Max Combined DL',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        totalDlStr,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 32,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.arrow_upward_rounded,
                            size: 14,
                            color: Colors.teal,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            l10n?.bandwidthThrottlingMaxCombinedUl ??
                                'Max Combined UL',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        totalUlStr,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThrottledClientCard(
    BuildContext context, {
    required ClientSpeedLimit limit,
    required Client? client,
    required String displayName,
    required String ip,
    required String mac,
    required bool isConnected,
    required ConnectionType connType,
  }) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                // Connection indicator & icon
                Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        connType == ConnectionType.wireless
                            ? Icons.wifi_rounded
                            : Icons.settings_ethernet_rounded,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isConnected ? Colors.green : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '$ip • $mac',
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
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                // Download chip
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.arrow_downward_rounded,
                        size: 13,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        limit.formattedDownloadSpeed,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Upload chip
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.arrow_upward_rounded,
                        size: 13,
                        color: Colors.teal,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        limit.formattedUploadSpeed,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Edit button
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip:
                      l10n?.bandwidthThrottlingEditTooltip ??
                      'Edit Speed Limit',
                  onPressed: _isProcessing
                      ? null
                      : () => _editLimit(client, limit),
                ),
                // Remove button
                IconButton(
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: _isProcessing
                        ? colorScheme.outlineVariant
                        : colorScheme.error,
                  ),
                  tooltip:
                      l10n?.bandwidthThrottlingRemoveTooltip ??
                      'Remove Speed Limit',
                  onPressed: _isProcessing
                      ? null
                      : () => _removeLimit(mac, displayName),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, dynamic router) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.4,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.traffic_rounded,
                size: 56,
                color: colorScheme.primary.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n?.bandwidthThrottlingEmptyTitle ??
                  'No Speed Restrictions Active',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              router != null
                  ? (l10n?.bandwidthThrottlingEmptyDescRouter(
                          router.displayName,
                        ) ??
                        'No bandwidth limits are configured for ${router.displayName}. Cap download and upload speeds for any client connected to this profile.')
                  : (l10n?.bandwidthThrottlingEmptyDescFallback ??
                        'Speed restrictions let you cap maximum download and upload speeds for specific client devices on the active router profile.'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _showAddRestrictionSheet,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(
                l10n?.bandwidthThrottlingAddLimit ?? 'Add Speed Limit',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
