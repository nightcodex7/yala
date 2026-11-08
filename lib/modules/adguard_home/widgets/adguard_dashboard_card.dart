// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import '../controllers/adguard_controller.dart';
import '../models/adguard_models.dart';
import '../screens/adguard_home_screen.dart';

/// Compact dashboard card summarizing AdGuard Home metrics and protection status.
///
/// Strictly visibility-gated: renders ONLY when AdGuard Home is installed,
/// DNS is operational, API is reachable, and API is authenticated. Returns
/// `const SizedBox.shrink()` otherwise to prevent false-healthy indicators.
class AdGuardDashboardCard extends ConsumerStatefulWidget {
  final String? routerId;
  final VoidCallback? onTap;

  const AdGuardDashboardCard({super.key, this.routerId, this.onTap});

  @override
  ConsumerState<AdGuardDashboardCard> createState() =>
      _AdGuardDashboardCardState();
}

class _AdGuardDashboardCardState extends ConsumerState<AdGuardDashboardCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _triggerHydration();
    });
  }

  @override
  void didUpdateWidget(covariant AdGuardDashboardCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routerId != widget.routerId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _triggerHydration();
      });
    }
  }

  void _triggerHydration() {
    final effectiveRouterId =
        widget.routerId ??
        ref.read(appStateProvider).selectedRouter?.id ??
        'default';
    final caps = ref.read(routerCapabilitiesProvider);
    final controller = ref.read(
      adguardControllerProvider(effectiveRouterId).notifier,
    );
    controller.hydrateDashboardIfNeeded(
      hasRouterCapability: caps?.hasAdGuardHome ?? false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveRouterId =
        widget.routerId ??
        ref.watch(appStateProvider).selectedRouter?.id ??
        'default';

    final state = ref.watch(adguardControllerProvider(effectiveRouterId));
    final caps = state.capabilities;

    // Strict capability & connection status visibility gate
    final bool isVisible =
        caps.isInstalled &&
        caps.isDnsOperational &&
        caps.isApiReachable &&
        caps.isApiAuthenticated &&
        (state.connectionStatus == AdGuardConnectionStatus.authenticated ||
            state.connectionStatus == AdGuardConnectionStatus.degraded);

    if (!isVisible) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final protectionState =
        state.status?.protectionState ?? AdGuardProtectionState.disabled;
    final isEnabled = protectionState == AdGuardProtectionState.enabled;
    final isPaused = protectionState == AdGuardProtectionState.paused;

    final Color statusColor = isEnabled
        ? Colors.green
        : (isPaused ? Colors.amber.shade800 : colorScheme.error);

    final String statusText = isEnabled
        ? (l10n?.aghProtectionEnabled ?? 'Protection Enabled')
        : (isPaused
              ? (l10n?.aghProtectionPaused ?? 'Protection Paused')
              : (l10n?.aghProtectionDisabled ?? 'Protection Disabled'));

    final totalQueries = state.stats?.numDnsQueries ?? 0;
    final blockedQueries = state.stats?.numBlockedFiltering ?? 0;
    final blockRate = state.stats?.blockRatePercentage ?? 0.0;

    return Card(
      key: const Key('agh_dashboard_card'),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap:
            widget.onTap ??
            () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      AdGuardHomeScreen(routerId: effectiveRouterId),
                ),
              );
            },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n?.aghDashboardCardTitle ?? 'AdGuard Home',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (state.isExternal) ...[
                          const SizedBox(height: 1),
                          Text(
                            state.activeProfile != null &&
                                    state.activeProfile!.name !=
                                        'External Standalone'
                                ? '${state.activeProfile!.name} (External Standalone)'
                                : 'External Standalone',
                            key: const Key(
                              'agh_dashboard_card_external_subtitle',
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7.0,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.3),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          statusText,
                          key: const Key('agh_dashboard_card_status_chip'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Metrics Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStatItem(
                    context,
                    label: l10n?.aghTotalQueries ?? 'Queries',
                    value: '$totalQueries',
                    keyName: 'agh_dashboard_queries',
                  ),
                  _buildStatItem(
                    context,
                    label: l10n?.aghBlockedQueries ?? 'Blocked',
                    value: '$blockedQueries',
                    keyName: 'agh_dashboard_blocked',
                    valueColor: Theme.of(context).colorScheme.error,
                  ),
                  _buildStatItem(
                    context,
                    label: l10n?.aghBlockRate ?? 'Block Rate',
                    value: '${blockRate.toStringAsFixed(1)}%',
                    keyName: 'agh_dashboard_block_rate',
                    valueColor: LuciStatusColors.warningColor(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required String label,
    required String value,
    required String keyName,
    Color? valueColor,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          key: Key(keyName),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: valueColor ?? colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
