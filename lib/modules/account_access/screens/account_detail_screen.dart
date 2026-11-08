// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/widgets/luci_app_bar.dart';
import '../models/account_access_models.dart';
import '../widgets/account_current_card.dart';
import '../widgets/account_diagnostics_card.dart';
import '../widgets/account_methods_card.dart';
import '../widgets/account_rpc_permissions_card.dart';
import '../widgets/account_ssh_access_card.dart';
import '../widgets/account_subsystems_card.dart';

/// Screen presenting the detailed access, effective RPC capabilities, and permissions
/// for a specific account entry on the router.
class AccountDetailScreen extends StatelessWidget {
  final AccountAccessSnapshot snapshot;
  final RouterAccountEntry accountEntry;

  const AccountDetailScreen({
    super.key,
    required this.snapshot,
    required this.accountEntry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: LuciAppBar(
        title:
            l10n?.accountAccessAndPermissionsHeader(accountEntry.username) ??
            'Access & Permissions (${accountEntry.username})',
        showBack: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top security reminder banner
              _buildSecurityBanner(context, theme),
              const SizedBox(height: 14),

              // Section 1: Current Account Identity & Session Specs
              AccountCurrentCard(account: snapshot.account),

              // Section 2: Authentication & Connection Methods
              AccountMethodsCard(methods: snapshot.connectionMethods),

              // Section 3: LuCI RPC Permissions & Effective Access
              AccountRpcPermissionsCard(capabilities: snapshot.rpcCapabilities),

              // Section 4: SSH Access Inspection
              AccountSshAccessCard(ssh: snapshot.sshAccess),

              // Section 5: Other Verified Access Capabilities
              if (snapshot.subsystems.isNotEmpty)
                AccountSubsystemsCard(subsystems: snapshot.subsystems),

              // Section 6: Detection Status & Diagnostics
              AccountDiagnosticsCard(snapshot: snapshot),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityBanner(BuildContext context, ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
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
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n?.accountDetailedAccessNotice(accountEntry.username) ??
                  'Detailed Access Inspection for "${accountEntry.username}": Evaluates verified RPC ACLs, console reachability, and subsystem capabilities non-destructively.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                height: 1.35,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
