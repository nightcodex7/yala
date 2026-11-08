// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import '../models/account_access_models.dart';
import '../utils/account_access_l10n.dart';
import 'account_section_container.dart';

/// Dedicated card inspecting SSH reachability, daemon configuration,
/// independent account verification, and read-only shell capabilities.
class AccountSshAccessCard extends StatelessWidget {
  final SshAccessInfo ssh;

  const AccountSshAccessCard({super.key, required this.ssh});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final (statusText, statusBg, statusBorder, statusColor) =
        _resolveReachabilityStyle(context, ssh.reachability);

    return AccountSectionContainer(
      title: l10n?.accountSectionSsh ?? 'SSH Access',
      icon: Icons.terminal_rounded,
      subtitle:
          l10n?.accountSshSubtitle ??
          'Terminal daemon reachability and read-only shell identity audit',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // SSH Reachability Header Status Banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: statusBorder),
            ),
            child: Row(
              children: [
                Icon(
                  ssh.reachability == SshReachabilityStatus.verifiedWorking
                      ? Icons.check_circle_rounded
                      : Icons.info_outline_rounded,
                  color: statusColor,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AccountAccessL10n.getSshExplanation(context, ssh),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface,
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

          // Structured SSH Technical Audit Details
          _buildInfoRow(
            context,
            label: l10n?.accountSshReachabilityLabel ?? 'SSH Reachability',
            value: statusText,
            valueColor: statusColor,
            icon: Icons.network_ping_rounded,
          ),
          const Divider(height: 14),
          _buildInfoRow(
            context,
            label: l10n?.accountSshPortLabel ?? 'SSH Listening Port',
            value:
                '${ssh.port ?? 22} (${AccountAccessL10n.getSshPortSource(context, ssh.portSource)})',
            icon: Icons.meeting_room_outlined,
          ),
          const Divider(height: 14),
          _buildInfoRow(
            context,
            label: l10n?.accountSshDaemonStatusLabel ?? 'Daemon Service Status',
            value: AccountAccessL10n.getSshDaemonStatus(
              context,
              ssh.daemonStatus,
            ),
            icon: Icons.settings_ethernet_rounded,
          ),
          const Divider(height: 14),
          _buildInfoRow(
            context,
            label: l10n?.accountSshActiveSessionLabel ?? 'Active SSH Session',
            value: ssh.hasActiveConnection
                ? (l10n?.accountSshActiveConnected ?? 'Connected and verified')
                : (l10n?.accountSshActiveNone ?? 'No active session'),
            valueColor: ssh.hasActiveConnection
                ? LuciStatusColors.successText(context)
                : null,
            icon: Icons.link_rounded,
          ),
          const Divider(height: 14),
          _buildInfoRow(
            context,
            label:
                l10n?.accountSshVerifiedIdentityLabel ??
                'Verified Account Identity',
            value: ssh.isIdentityConfirmed
                ? (l10n?.accountSshIdentityConfirmed(
                        ssh.authenticatedUser ?? '',
                      ) ??
                      '${ssh.authenticatedUser} (confirmed via UNIX shell)')
                : (l10n?.accountSshIdentityUnverified ?? 'Unverified via SSH'),
            valueColor: ssh.isIdentityConfirmed
                ? LuciStatusColors.successText(context)
                : LuciStatusColors.warningText(context),
            icon: Icons.person_pin_circle_outlined,
          ),
          const Divider(height: 14),
          _buildInfoRow(
            context,
            label: l10n?.accountSshCmdTestLabel ?? 'Read-Only Command Test',
            value: ssh.readOnlyExecutionSucceeded == true
                ? (l10n?.accountSshCmdTestSuccess ??
                      'Executed "id -u -n" successfully')
                : (ssh.readOnlyExecutionSucceeded == false
                      ? (l10n?.accountSshCmdTestFailed ??
                            'Command execution rejected or failed')
                      : (l10n?.accountStatusNotTested ?? 'Not tested')),
            icon: Icons.play_arrow_outlined,
          ),
          if (ssh.executionOutput != null) ...[
            const Divider(height: 14),
            _buildInfoRow(
              context,
              label: l10n?.accountSshCmdOutputLabel ?? 'Command Probe Output',
              value: AccountAccessL10n.getSshOutput(
                context,
                ssh.executionOutput!,
              ),
              icon: Icons.notes_rounded,
            ),
          ],
          const SizedBox(height: 14),

          // Security Guarantee Callout Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AccountAccessL10n.getSshSecurityNotes(
                      context,
                      ssh.securityNotes,
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 10.5,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
          size: 15,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 155,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor ?? theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  (String, Color, Color, Color) _resolveReachabilityStyle(
    BuildContext context,
    SshReachabilityStatus status,
  ) {
    final l10n = AppLocalizations.of(context);
    switch (status) {
      case SshReachabilityStatus.verifiedWorking:
        return (
          l10n?.accountSshStatusVerifiedWorking ??
              'Verified Working & Authenticated',
          LuciStatusColors.successBg(context),
          LuciStatusColors.successBorder(context),
          LuciStatusColors.successText(context),
        );
      case SshReachabilityStatus.reachableUnverified:
        return (
          l10n?.accountSshStatusReachableUnverified ?? 'Port Open (Unverified)',
          LuciStatusColors.warningBg(context),
          LuciStatusColors.warningBorder(context),
          LuciStatusColors.warningText(context),
        );
      case SshReachabilityStatus.portClosedOrUnreachable:
        return (
          l10n?.accountSshStatusPortClosed ?? 'Port Closed or Unreachable',
          LuciStatusColors.errorBg(context),
          LuciStatusColors.errorBorder(context),
          LuciStatusColors.errorText(context),
        );
      case SshReachabilityStatus.permissionDenied:
        return (
          l10n?.accountSshStatusPermissionDenied ??
              'Permission Denied (Invalid Credentials)',
          LuciStatusColors.errorBg(context),
          LuciStatusColors.errorBorder(context),
          LuciStatusColors.errorText(context),
        );
      case SshReachabilityStatus.notTested:
        return (
          l10n?.accountSshStatusNotTested ?? 'Not Verified (Probes Deferred)',
          Theme.of(context).colorScheme.surfaceContainerHighest,
          Theme.of(context).colorScheme.outlineVariant,
          Theme.of(context).colorScheme.onSurfaceVariant,
        );
      case SshReachabilityStatus.unknown:
        return (
          l10n?.accountSshStatusUnknown ?? 'Unknown Reachability',
          LuciStatusColors.warningBg(context),
          LuciStatusColors.warningBorder(context),
          LuciStatusColors.warningText(context),
        );
      case SshReachabilityStatus.notInstalledOrDisabled:
        return (
          l10n?.accountSshStatusNotInstalled ?? 'Not Detected / Disabled',
          Theme.of(context).colorScheme.surfaceContainerHighest,
          Theme.of(context).colorScheme.outlineVariant,
          Theme.of(context).colorScheme.onSurfaceVariant,
        );
    }
  }
}
