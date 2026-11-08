// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import '../models/adguard_models.dart';

/// Card presenting high-level AdGuard Home DNS statistics:
/// Total queries, blocked queries, block rate %, and average processing time.
class AdGuardStatsCard extends StatelessWidget {
  final AdGuardStats? stats;
  final String? statsError;
  final AdGuardStatsPeriod selectedPeriod;
  final ValueChanged<AdGuardStatsPeriod>? onPeriodChanged;

  const AdGuardStatsCard({
    super.key,
    required this.stats,
    this.statsError,
    this.selectedPeriod = AdGuardStatsPeriod.all,
    this.onPeriodChanged,
  });

  String _getPeriodLabel(AppLocalizations? l10n, AdGuardStatsPeriod period) {
    switch (period) {
      case AdGuardStatsPeriod.all:
        return l10n?.aghPeriodAll ?? 'All Time';
      case AdGuardStatsPeriod.hours24:
        return l10n?.aghPeriod24Hours ?? '24 Hours';
      case AdGuardStatsPeriod.days7:
        return l10n?.aghPeriod7Days ?? '7 Days';
      case AdGuardStatsPeriod.days30:
        return l10n?.aghPeriod30Days ?? '30 Days';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final totalQueries = stats?.numDnsQueries ?? 0;
    final blockedQueries = stats?.numBlockedFiltering ?? 0;
    final blockRate = stats?.blockRatePercentage ?? 0.0;
    final avgProcessing = stats?.avgProcessingTime != null
        ? '${(stats!.avgProcessingTime * 1000).toStringAsFixed(1)} ms'
        : '—';

    final hasActivity = totalQueries > 0;
    final blockedColor = blockedQueries > 0
        ? colorScheme.error
        : colorScheme.onSurfaceVariant;
    final blockRateColor = (hasActivity && blockRate > 0)
        ? LuciStatusColors.warningColor(context)
        : colorScheme.onSurfaceVariant;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.bar_chart_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n?.aghStatistics ?? 'Statistics',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                PopupMenuButton<AdGuardStatsPeriod>(
                  key: const Key('agh_stats_period_button'),
                  tooltip: l10n?.aghStatsPeriod ?? 'Time Period',
                  initialValue: selectedPeriod,
                  onSelected: onPeriodChanged,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.6,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colorScheme.outlineVariant,
                        width: 0.6,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _getPeriodLabel(l10n, selectedPeriod),
                          key: const Key('agh_stats_period_label'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_drop_down,
                          size: 16,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                  itemBuilder: (context) {
                    return AdGuardStatsPeriod.values.map((period) {
                      return PopupMenuItem<AdGuardStatsPeriod>(
                        key: Key('agh_stats_period_${period.name}'),
                        value: period,
                        child: Row(
                          children: [
                            if (selectedPeriod == period)
                              Icon(
                                Icons.check,
                                size: 16,
                                color: colorScheme.primary,
                              )
                            else
                              const SizedBox(width: 16),
                            const SizedBox(width: 8),
                            Text(_getPeriodLabel(l10n, period)),
                          ],
                        ),
                      );
                    }).toList();
                  },
                ),
              ],
            ),
            if (statsError != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade700, width: 0.8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: Colors.amber.shade900,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n?.aghStatsDegraded ??
                            'Statistics unavailable from AdGuard Home',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),

            // 2x2 Grid of Metrics
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    context,
                    title: l10n?.aghTotalQueries ?? 'Total Queries',
                    value: _formatCount(totalQueries),
                    keyName: 'agh_stat_total_queries',
                    icon: Icons.query_builder,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricTile(
                    context,
                    title: l10n?.aghBlockedQueries ?? 'Blocked Queries',
                    value: _formatCount(blockedQueries),
                    keyName: 'agh_stat_blocked_queries',
                    icon: Icons.block_flipped,
                    color: blockedColor,
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
                    title: l10n?.aghBlockRate ?? 'Block Rate',
                    value: '${blockRate.toStringAsFixed(1)}%',
                    keyName: 'agh_stat_block_rate',
                    icon: Icons.pie_chart_outline_rounded,
                    color: blockRateColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricTile(
                    context,
                    title: l10n?.aghAvgLatency ?? 'Average Processing',
                    value: avgProcessing,
                    keyName: 'agh_stat_avg_latency',
                    icon: Icons.speed_rounded,
                    color: Colors.teal.shade700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatCount(int number) {
    return number.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }

  Widget _buildMetricTile(
    BuildContext context, {
    required String title,
    required String value,
    required String keyName,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            key: Key(keyName),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
