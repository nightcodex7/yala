// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import '../models/account_access_models.dart';
import '../utils/account_access_l10n.dart';
import 'account_section_container.dart';

/// Card reporting the actual authentication and transport connection methods
/// utilized by the current YALA session with distinct, non-interchangeable states.
class AccountMethodsCard extends StatelessWidget {
  final List<ConnectionMethodInfo> methods;

  const AccountMethodsCard({super.key, required this.methods});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AccountSectionContainer(
      title:
          l10n?.accountSectionAuthMethods ??
          'Authentication & Connection Methods',
      icon: Icons.hub_outlined,
      subtitle:
          l10n?.accountMethodsSubtitle ??
          'Audited session communication channels and daemon states',
      child: Column(
        children: methods.map((m) => _buildMethodItem(context, m)).toList(),
      ),
    );
  }

  Widget _buildMethodItem(BuildContext context, ConnectionMethodInfo method) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final (statusText, statusBg, statusBorder, statusColor) =
        _resolveStatusStyle(context, method.status);

    final IconData methodIcon = _resolveMethodIcon(method.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(methodIcon, size: 18, color: statusColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AccountAccessL10n.getMethodName(context, method),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      method.endpointOrPort,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: statusBorder),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            AccountAccessL10n.getMethodExplanation(context, method),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: 12,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.7,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  l10n?.accountEvidencePrefix(
                        AccountAccessL10n.getEvidence(
                          context,
                          method.evidenceSource,
                        ),
                      ) ??
                      'Evidence: ${method.evidenceSource}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _resolveMethodIcon(String id) {
    switch (id) {
      case 'luci_http':
        return Icons.language_rounded;
      case 'luci_rpc':
        return Icons.api_rounded;
      case 'ssh':
        return Icons.terminal_rounded;
      default:
        return Icons.cable_rounded;
    }
  }

  (String, Color, Color, Color) _resolveStatusStyle(
    BuildContext context,
    ConnectionMethodStatus status,
  ) {
    final l10n = AppLocalizations.of(context);
    switch (status) {
      case ConnectionMethodStatus.activeAndVerified:
        return (
          l10n?.accountStatusActiveAndVerified ?? 'Active and verified',
          LuciStatusColors.successBg(context),
          LuciStatusColors.successBorder(context),
          LuciStatusColors.successText(context),
        );
      case ConnectionMethodStatus.availableUnverified:
        return (
          l10n?.accountStatusAvailableUnverified ?? 'Available but unverified',
          LuciStatusColors.warningBg(context),
          LuciStatusColors.warningBorder(context),
          LuciStatusColors.warningText(context),
        );
      case ConnectionMethodStatus.unavailable:
        return (
          l10n?.accountStatusUnavailable ?? 'Unavailable',
          LuciStatusColors.errorBg(context),
          LuciStatusColors.errorBorder(context),
          LuciStatusColors.errorText(context),
        );
      case ConnectionMethodStatus.permissionDenied:
        return (
          l10n?.accountStatusPermissionDenied ?? 'Permission denied',
          LuciStatusColors.errorBg(context),
          LuciStatusColors.errorBorder(context),
          LuciStatusColors.errorText(context),
        );
      case ConnectionMethodStatus.notTested:
        return (
          l10n?.accountStatusNotTested ?? 'Not tested',
          Theme.of(context).colorScheme.surfaceContainerHighest,
          Theme.of(context).colorScheme.outlineVariant,
          Theme.of(context).colorScheme.onSurfaceVariant,
        );
      case ConnectionMethodStatus.unknown:
        return (
          l10n?.accountStatusUnknown ?? 'Unknown',
          LuciStatusColors.warningBg(context),
          LuciStatusColors.warningBorder(context),
          LuciStatusColors.warningText(context),
        );
      case ConnectionMethodStatus.notApplicable:
        return (
          l10n?.accountStatusNotApplicable ?? 'Not applicable',
          Theme.of(context).colorScheme.surfaceContainerHighest,
          Theme.of(context).colorScheme.outlineVariant,
          Theme.of(context).colorScheme.onSurfaceVariant,
        );
    }
  }
}
