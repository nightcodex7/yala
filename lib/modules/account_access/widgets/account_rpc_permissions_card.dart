// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import '../models/account_access_models.dart';
import '../utils/account_access_l10n.dart';
import 'account_section_container.dart';

/// Card displaying effective LuCI RPC and ubus permissions per capability group,
/// evaluated strictly without performing configuration writes.
class AccountRpcPermissionsCard extends StatefulWidget {
  final List<RpcCapabilityPermission> capabilities;

  const AccountRpcPermissionsCard({super.key, required this.capabilities});

  @override
  State<AccountRpcPermissionsCard> createState() =>
      _AccountRpcPermissionsCardState();
}

class _AccountRpcPermissionsCardState extends State<AccountRpcPermissionsCard> {
  String _selectedCategoryKey = 'all';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    final categoryMap = {
      'all': l10n?.accountRpcCatAll ?? 'All',
      'Core System': l10n?.accountRpcCatCoreSystem ?? 'Core System',
      'Network & Interfaces':
          l10n?.accountRpcCatNetwork ?? 'Network & Interfaces',
      'Security & Firewall':
          l10n?.accountRpcCatSecurity ?? 'Security & Firewall',
      'Services & Management':
          l10n?.accountRpcCatServices ?? 'Services & Management',
    };

    final filtered = _selectedCategoryKey == 'all'
        ? widget.capabilities
        : widget.capabilities
              .where((c) => c.category == _selectedCategoryKey)
              .toList();

    return AccountSectionContainer(
      title: l10n?.accountSectionLuciRpc ?? 'LuCI RPC Permissions',
      icon: Icons.vpn_key_outlined,
      subtitle:
          l10n?.accountRpcSubtitle ??
          'Effective session capabilities and ubus ACL authorizations',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Non-destructive evaluation disclaimer banner
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.4,
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n?.accountRpcDisclaimer ??
                        'Evaluated from authoritative OpenWrt session ACLs and read-only schema queries. No configuration changes are performed to test write access.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Category Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categoryMap.entries.map((entry) {
                final isSelected = _selectedCategoryKey == entry.key;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(
                      entry.value,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedCategoryKey = entry.key);
                      }
                    },
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 0,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // List of capabilities
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  l10n?.accountRpcNoCapsInCategory ??
                      'No capabilities found in this category.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            ...filtered.map((cap) => _buildCapabilityItem(context, cap)),
        ],
      ),
    );
  }

  Widget _buildCapabilityItem(
    BuildContext context,
    RpcCapabilityPermission cap,
  ) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

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
                  AccountAccessL10n.getCapabilityTitle(context, cap),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.6,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  AccountAccessL10n.getCategoryLabel(context, cap.category),
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Dual Badges: Read vs Write Authorization
          Row(
            children: [
              Expanded(
                child: _buildPermissionBadge(
                  context,
                  prefix: l10n?.accountPrefixRead ?? 'Read:',
                  status: cap.readStatus,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPermissionBadge(
                  context,
                  prefix: l10n?.accountPrefixWrite ?? 'Write:',
                  status: cap.writeStatus,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Explanation
          Text(
            AccountAccessL10n.getCapabilityExplanation(context, cap),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 11.5,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 4),

          // Evidence Source
          Row(
            children: [
              Icon(
                Icons.account_tree_outlined,
                size: 11,
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
                          cap.evidenceSource,
                        ),
                      ) ??
                      'Evidence: ${cap.evidenceSource}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionBadge(
    BuildContext context, {
    required String prefix,
    required PermissionAccessStatus status,
  }) {
    final (label, bg, border, textColor, icon) = _resolvePermissionStyle(
      context,
      status,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            '$prefix ',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: textColor.withValues(alpha: 0.8),
            ),
          ),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  (String, Color, Color, Color, IconData) _resolvePermissionStyle(
    BuildContext context,
    PermissionAccessStatus status,
  ) {
    final l10n = AppLocalizations.of(context);
    switch (status) {
      case PermissionAccessStatus.verifiedReadAccess:
        return (
          l10n?.accountPermVerifiedRead ?? 'Verified Read',
          LuciStatusColors.successBg(context),
          LuciStatusColors.successBorder(context),
          LuciStatusColors.successText(context),
          Icons.check_circle_outline_rounded,
        );
      case PermissionAccessStatus.verifiedWriteAuthorization:
        return (
          l10n?.accountPermAuthorizedWrite ?? 'Authorized Write',
          LuciStatusColors.successBg(context),
          LuciStatusColors.successBorder(context),
          LuciStatusColors.successText(context),
          Icons.check_circle_outline_rounded,
        );
      case PermissionAccessStatus.verifiedDenied:
        return (
          l10n?.accountPermDenied ?? 'Denied',
          LuciStatusColors.errorBg(context),
          LuciStatusColors.errorBorder(context),
          LuciStatusColors.errorText(context),
          Icons.cancel_outlined,
        );
      case PermissionAccessStatus.notTested:
        return (
          l10n?.accountPermNotTested ?? 'Not Tested (No Mutation)',
          LuciStatusColors.warningBg(context),
          LuciStatusColors.warningBorder(context),
          LuciStatusColors.warningText(context),
          Icons.help_outline_rounded,
        );
      case PermissionAccessStatus.unknown:
        return (
          l10n?.accountPermUnknown ?? 'Unknown',
          Theme.of(context).colorScheme.surfaceContainerHighest,
          Theme.of(context).colorScheme.outlineVariant,
          Theme.of(context).colorScheme.onSurfaceVariant,
          Icons.help_outline_rounded,
        );
      case PermissionAccessStatus.notSupported:
        return (
          l10n?.accountPermNotSupported ?? 'Not Supported',
          Theme.of(context).colorScheme.surfaceContainerHighest,
          Theme.of(context).colorScheme.outlineVariant,
          Theme.of(context).colorScheme.onSurfaceVariant,
          Icons.block_rounded,
        );
      case PermissionAccessStatus.notApplicable:
        return (
          l10n?.accountPermNotApplicable ?? 'Not Applicable',
          Theme.of(context).colorScheme.surfaceContainerHighest,
          Theme.of(context).colorScheme.outlineVariant,
          Theme.of(context).colorScheme.onSurfaceVariant,
          Icons.remove_circle_outline_rounded,
        );
    }
  }
}
