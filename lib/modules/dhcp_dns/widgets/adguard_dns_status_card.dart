// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/modules/adguard_home/controllers/adguard_controller.dart';
import 'package:yet_another_luci_app/modules/adguard_home/models/adguard_models.dart';
import 'package:yet_another_luci_app/modules/adguard_home/screens/adguard_home_screen.dart';

/// DHCP & DNS screen AdGuard Home integration status card.
///
/// Features:
/// - Reuses existing [adguardControllerProvider] and domain models directly.
/// - Strictly capability-gated using 4 mutually exclusive precedence states:
///   1. State 1 (Not installed): Renders `const SizedBox.shrink()` with 0 footprint.
///   2. State 2 (API unreachable or auth required): Informational/degraded card.
///   3. State 3 (API authenticated, DNS not operational): Informational card.
///      (Labels "Stopped" strictly when `status.running == false`).
///   4. State 4 (Fully operational): Active sinkhole card with metrics and topology.
/// - Reviewer Mode offline safe: operates 100% in-memory with zero external side effects.
/// - Navigates directly to [AdGuardHomeScreen] on action tap.
class AdGuardDnsStatusCard extends ConsumerStatefulWidget {
  final String routerId;

  const AdGuardDnsStatusCard({super.key, required this.routerId});

  @override
  ConsumerState<AdGuardDnsStatusCard> createState() =>
      _AdGuardDnsStatusCardState();
}

class _AdGuardDnsStatusCardState extends ConsumerState<AdGuardDnsStatusCard> {
  @override
  void initState() {
    super.initState();
    _checkInitialProbe();
  }

  @override
  void didUpdateWidget(AdGuardDnsStatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routerId != widget.routerId) {
      _checkInitialProbe();
    }
  }

  void _checkInitialProbe() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = ref.read(adguardControllerProvider(widget.routerId));
      if (state.connectionStatus == AdGuardConnectionStatus.initial) {
        ref.read(adguardControllerProvider(widget.routerId).notifier).refresh();
      }
    });
  }

  void _navigateToAdGuardHome(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdGuardHomeScreen(routerId: widget.routerId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adguardControllerProvider(widget.routerId));
    final capabilities = state.capabilities;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // State 1 — AdGuard not installed: Zero visual footprint
    if (!capabilities.isInstalled) {
      return const SizedBox.shrink();
    }

    // State 2 — API unreachable or authentication required
    if (!capabilities.isApiReachable ||
        state.connectionStatus == AdGuardConnectionStatus.authRequired ||
        !capabilities.isApiAuthenticated) {
      return _buildDegradedCard(context, state, l10n, theme);
    }

    // State 3 — API authenticated but DNS is not operational
    if (!capabilities.isDnsOperational) {
      return _buildDnsNotOperationalCard(context, state, l10n, theme);
    }

    // State 4 — Fully operational
    return _buildOperationalCard(context, state, l10n, theme);
  }

  // ── State 2: Informational / Degraded Card ─────────────────────────────────

  Widget _buildDegradedCard(
    BuildContext context,
    AdGuardState state,
    AppLocalizations? l10n,
    ThemeData theme,
  ) {
    final colorScheme = theme.colorScheme;
    final isAuthReq =
        state.connectionStatus == AdGuardConnectionStatus.authRequired;

    final String badgeText = isAuthReq
        ? (l10n?.aghAuthRequiredBadge ?? 'Authentication Required')
        : (l10n?.aghApiUnreachableBadge ?? 'API Unreachable');

    final IconData badgeIcon = isAuthReq
        ? Icons.lock_outline_rounded
        : Icons.cloud_off_rounded;

    final Color badgeColor = Colors.amber.shade800;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Card(
        key: const Key('agh_dns_status_card_degraded'),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.dns_rounded, size: 20, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n?.aghDnsCardTitle ?? 'AdGuard Home DNS',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusChip(
                    badgeText,
                    badgeIcon,
                    badgeColor,
                    const Key('agh_dns_card_status_badge'),
                    theme,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Description
              Text(
                l10n?.aghDnsCardApiUnreachableDesc ??
                    'AdGuard Home detected, but management API is unauthenticated or unreachable.',
                key: const Key('agh_dns_card_description'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),

              // Action
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('agh_dns_card_manage_button'),
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: Text(
                    l10n?.aghManageAdGuardHome ?? 'Manage AdGuard Home',
                  ),
                  onPressed: () => _navigateToAdGuardHome(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── State 3: DNS Not Operational Card ─────────────────────────────────────

  Widget _buildDnsNotOperationalCard(
    BuildContext context,
    AdGuardState state,
    AppLocalizations? l10n,
    ThemeData theme,
  ) {
    final colorScheme = theme.colorScheme;
    final isStopped = state.status != null && state.status?.running == false;

    final String badgeText = isStopped
        ? (l10n?.aghDnsCardStoppedBadge ?? 'Stopped / Inactive')
        : (l10n?.aghDnsEngineNotOperationalBadge ?? 'DNS Not Operational');

    final IconData badgeIcon = isStopped
        ? Icons.stop_circle_outlined
        : Icons.warning_amber_rounded;

    final Color badgeColor = isStopped
        ? theme.colorScheme.error
        : LuciStatusColors.warningColor(context);

    final String descriptionText = isStopped
        ? (l10n?.aghDnsCardStoppedDesc ??
              'AdGuard Home DNS engine is stopped. Standard router DNS is active.')
        : (l10n?.aghDnsEngineNotOperationalDesc ??
              'AdGuard Home API is connected, but DNS engine is not operational.');

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Card(
        key: const Key('agh_dns_status_card_dns_not_operational'),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.dns_rounded, size: 20, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n?.aghDnsCardTitle ?? 'AdGuard Home DNS',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusChip(
                    badgeText,
                    badgeIcon,
                    badgeColor,
                    const Key('agh_dns_card_status_badge'),
                    theme,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Description
              Text(
                descriptionText,
                key: const Key('agh_dns_card_description'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),

              // Action
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('agh_dns_card_manage_button'),
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: Text(
                    l10n?.aghManageAdGuardHome ?? 'Manage AdGuard Home',
                  ),
                  onPressed: () => _navigateToAdGuardHome(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── State 4: Fully Operational Card ───────────────────────────────────────

  Widget _buildOperationalCard(
    BuildContext context,
    AdGuardState state,
    AppLocalizations? l10n,
    ThemeData theme,
  ) {
    final colorScheme = theme.colorScheme;
    final protectionState =
        state.status?.protectionState ?? AdGuardProtectionState.disabled;

    final isEnabled = protectionState == AdGuardProtectionState.enabled;
    final isPaused = protectionState == AdGuardProtectionState.paused;

    final Color badgeColor = isEnabled
        ? Colors.green.shade700
        : (isPaused ? Colors.amber.shade800 : colorScheme.error);

    final String badgeText = isEnabled
        ? (l10n?.aghProtectionEnabled ?? 'Protection Enabled')
        : (isPaused
              ? (l10n?.aghProtectionPaused ?? 'Protection Paused')
              : (l10n?.aghProtectionDisabled ?? 'Protection Disabled'));

    final IconData badgeIcon = isEnabled
        ? Icons.shield_rounded
        : (isPaused
              ? Icons.pause_circle_outline_rounded
              : Icons.shield_outlined);

    final totalQueries = state.stats?.numDnsQueries ?? 0;
    final blockedQueries = state.stats?.numBlockedFiltering ?? 0;
    final blockRate = state.stats?.blockRatePercentage ?? 0.0;
    final avgProcessingMs = (state.stats?.avgProcessingTime ?? 0.0) * 1000.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Card(
        key: const Key('agh_dns_status_card_operational'),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shield_rounded,
                    size: 20,
                    color: isEnabled
                        ? Colors.green.shade700
                        : colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n?.aghDnsCardTitle ?? 'AdGuard Home DNS',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusChip(
                    badgeText,
                    badgeIcon,
                    badgeColor,
                    const Key('agh_dns_card_status_badge'),
                    theme,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Metrics Row 1: Queries & Blocked
              Row(
                children: [
                  Expanded(
                    child: _buildMetricItem(
                      label: l10n?.aghTotalQueries ?? 'Total Queries',
                      value: '$totalQueries',
                      keyName: 'agh_dns_card_total_queries',
                      theme: theme,
                    ),
                  ),
                  Expanded(
                    child: _buildMetricItem(
                      label: l10n?.aghBlockedQueries ?? 'Blocked Queries',
                      value: '$blockedQueries',
                      keyName: 'agh_dns_card_blocked_queries',
                      valueColor: theme.colorScheme.error,
                      theme: theme,
                    ),
                  ),
                  Expanded(
                    child: _buildMetricItem(
                      label: l10n?.aghBlockRate ?? 'Block Rate',
                      value: '${blockRate.toStringAsFixed(1)}%',
                      keyName: 'agh_dns_card_block_rate',
                      valueColor: LuciStatusColors.warningColor(context),
                      theme: theme,
                    ),
                  ),
                  Expanded(
                    child: _buildMetricItem(
                      label: l10n?.aghAvgLatency ?? 'Average Processing',
                      value: '${avgProcessingMs.toStringAsFixed(1)} ms',
                      keyName: 'agh_dns_card_avg_latency',
                      theme: theme,
                    ),
                  ),
                ],
              ),

              // Topology section
              if (state.topology.mode != AdGuardTopologyMode.unknown) ...[
                const SizedBox(height: 14),
                Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.alt_route_rounded,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.topology.description,
                            key: const Key('agh_dns_card_topology_description'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n?.aghDnsCardInferredDisclaimer ??
                                'Inferred from router configuration',
                            key: const Key('agh_dns_card_topology_disclaimer'),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),

              // Action
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  key: const Key('agh_dns_card_manage_button'),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Text(
                    l10n?.aghManageAdGuardHome ?? 'Manage AdGuard Home',
                  ),
                  onPressed: () => _navigateToAdGuardHome(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helper Widgets ────────────────────────────────────────────────────────

  Widget _buildStatusChip(
    String label,
    IconData icon,
    Color color,
    Key key,
    ThemeData theme,
  ) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem({
    required String label,
    required String value,
    required String keyName,
    required ThemeData theme,
    Color? valueColor,
  }) {
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          key: Key(keyName),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: valueColor ?? colorScheme.onSurface,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
