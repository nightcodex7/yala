// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import '../models/account_access_models.dart';
import '../utils/account_access_l10n.dart';
import 'account_section_container.dart';

/// Card presenting other verified access capabilities and subsystems
/// detected in the current router environment.
class AccountSubsystemsCard extends StatelessWidget {
  final List<SubsystemAccessInfo> subsystems;

  const AccountSubsystemsCard({super.key, required this.subsystems});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AccountSectionContainer(
      title:
          l10n?.accountSectionOtherCaps ?? 'Other Verified Access Capabilities',
      icon: Icons.layers_outlined,
      subtitle:
          l10n?.accountSubsystemsSubtitle ??
          'OpenWrt subsystem architectures and integrated services',
      child: Column(
        children: subsystems
            .map((sub) => _buildSubsystemItem(context, sub))
            .toList(),
      ),
    );
  }

  Widget _buildSubsystemItem(BuildContext context, SubsystemAccessInfo sub) {
    final theme = Theme.of(context);

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
              Expanded(
                child: Text(
                  AccountAccessL10n.getSubsystemName(context, sub),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.6,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  AccountAccessL10n.getSubsystemStatus(context, sub),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            AccountAccessL10n.getSubsystemDetail(context, sub),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
