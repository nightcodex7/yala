// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import '../models/account_access_models.dart';
import '../utils/account_access_l10n.dart';
import 'account_section_container.dart';

/// Card displaying the current router account identity, session validity,
/// and connection parameters with strict qualification of identity sources.
class AccountCurrentCard extends StatelessWidget {
  final CurrentAccountInfo account;

  const AccountCurrentCard({super.key, required this.account});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isConfirmed = account.isUsernameConfirmedByRouter;

    return AccountSectionContainer(
      title: l10n?.accountSectionCurrentAccount ?? 'Current Account',
      icon: Icons.account_circle_outlined,
      subtitle:
          l10n?.accountCurrentSubtitle ??
          'Active router session identity and credentials evaluation',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Primary Username Identity Banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isConfirmed
                  ? LuciStatusColors.successBg(context)
                  : LuciStatusColors.warningBg(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isConfirmed
                    ? LuciStatusColors.successBorder(context)
                    : LuciStatusColors.warningBorder(context),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isConfirmed
                      ? Icons.verified_user_rounded
                      : Icons.info_outline_rounded,
                  color: isConfirmed
                      ? LuciStatusColors.successText(context)
                      : LuciStatusColors.warningText(context),
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              account.displayUsername,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isConfirmed
                                    ? LuciStatusColors.successText(context)
                                    : LuciStatusColors.warningText(context),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface.withValues(
                                alpha: 0.8,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isConfirmed
                                  ? (l10n?.accountConfirmedByRouter ??
                                        'Confirmed by Router')
                                  : (l10n?.accountProfileLabelOnly ??
                                        'Profile Label Only'),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isConfirmed
                                    ? LuciStatusColors.successText(context)
                                    : LuciStatusColors.warningText(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AccountAccessL10n.getIdentitySource(context, account),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Key-Value Grid of Session Information
          _buildInfoRow(
            context,
            label: l10n?.accountAuthMethodLabel ?? 'Authentication Method',
            value: AccountAccessL10n.getAuthMethod(context, account.authMethod),
            icon: Icons.key_outlined,
          ),
          const Divider(height: 16),
          _buildInfoRow(
            context,
            label:
                l10n?.accountConnectionTransportLabel ?? 'Connection Transport',
            value: AccountAccessL10n.getConnectionTransport(
              context,
              account.connectionMethod,
            ),
            icon: Icons.cable_outlined,
          ),
          const Divider(height: 16),
          _buildInfoRow(
            context,
            label: l10n?.accountSessionStatusLabel ?? 'Session Status',
            value: AccountAccessL10n.getSessionStatus(
              context,
              account.sessionStatus,
            ),
            icon: Icons.security_outlined,
            valueColor: account.sessionStatus.contains('Active')
                ? LuciStatusColors.successText(context)
                : LuciStatusColors.errorText(context),
          ),
          const Divider(height: 16),
          _buildInfoRow(
            context,
            label: l10n?.accountSessionValidityLabel ?? 'Session Validity',
            value: AccountAccessL10n.getSessionValidity(
              context,
              account.sessionValidity,
            ),
            icon: Icons.fact_check_outlined,
          ),
          if (account.lastVerified != null) ...[
            const Divider(height: 16),
            _buildInfoRow(
              context,
              label: l10n?.accountLastVerificationLabel ?? 'Last Verification',
              value: _formatTimestamp(account.lastVerified!),
              icon: Icons.access_time_outlined,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    Color? valueColor,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor ?? theme.colorScheme.onSurface,
            ),
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
}
