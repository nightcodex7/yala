// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import '../models/account_access_models.dart';
import 'account_section_container.dart';

/// Card presenting inspector detection status, audit timings,
/// and sanitized diagnostic findings.
class AccountDiagnosticsCard extends StatefulWidget {
  final AccountAccessSnapshot snapshot;

  const AccountDiagnosticsCard({super.key, required this.snapshot});

  @override
  State<AccountDiagnosticsCard> createState() => _AccountDiagnosticsCardState();
}

class _AccountDiagnosticsCardState extends State<AccountDiagnosticsCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final s = widget.snapshot;

    return AccountSectionContainer(
      title:
          l10n?.accountSectionDiagnostics ?? 'Detection Status & Diagnostics',
      icon: Icons.analytics_outlined,
      subtitle:
          l10n?.accountDiagnosticsSubtitle ??
          'Inspection telemetry, audit timings, and sanitized probe events',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Inspector Telemetry Header Grid
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              children: [
                _buildMetricRow(
                  context,
                  label:
                      l10n?.accountAuditCompletedAtLabel ??
                      'Audit Completed At',
                  value: _formatTimestamp(s.inspectedAt),
                ),
                const Divider(height: 12),
                _buildMetricRow(
                  context,
                  label:
                      l10n?.accountExecutionDurationLabel ??
                      'Execution Duration',
                  value: '${s.inspectionDuration.inMilliseconds} ms',
                ),
                const Divider(height: 12),
                _buildMetricRow(
                  context,
                  label:
                      l10n?.accountInspectionScopeLabel ?? 'Inspection Scope',
                  value: s.isPartialInspection
                      ? (l10n?.accountInspectionScopePartial ??
                            'Partial (Some probes deferred)')
                      : (l10n?.accountInspectionScopeComprehensive ??
                            'Comprehensive Audit'),
                ),
                const Divider(height: 12),
                _buildMetricRow(
                  context,
                  label:
                      l10n?.accountConfigMutationsLabel ??
                      'Configuration Mutations',
                  value:
                      l10n?.accountConfigMutationsValue ??
                      '0 writes performed (Strictly Read-Only)',
                  valueColor: theme.colorScheme.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Diagnostic Events Accordion Toggle
          InkWell(
            key: const ValueKey('diagnostics_accordion_toggle'),
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.3,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.2,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n?.accountSanitizedAuditTrailTitle(
                            s.diagnostics.length,
                          ) ??
                          'Sanitized Audit Trail (${s.diagnostics.length} events)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    _isExpanded
                        ? (l10n?.accountAuditTrailHide ?? 'Hide')
                        : (l10n?.accountAuditTrailShow ?? 'Show'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Collapsible Event List
          if (_isExpanded) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.25,
                  ),
                ),
              ),
              child: s.diagnostics.isEmpty
                  ? Text(
                      l10n?.accountNoDiagnosticEvents ??
                          'No diagnostic events recorded.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: s.diagnostics.map((d) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '[${_formatTimeOnly(d.timestamp)}]',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      d.message,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: d.isWarning
                                            ? LuciStatusColors.warningColor(
                                                context,
                                              )
                                            : theme.colorScheme.onSurface,
                                      ),
                                    ),
                                    if (d.evidence != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        d.evidence!,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricRow(
    BuildContext context, {
    required String label,
    required String value,
    Color? valueColor,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: valueColor ?? theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  String _formatTimestamp(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final second = dt.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second (${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')})';
  }

  String _formatTimeOnly(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final second = dt.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}
