// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/widgets/luci_app_bar.dart';
import '../controllers/account_access_controller.dart';
import '../models/account_access_models.dart';
import '../utils/account_access_l10n.dart';
import '../widgets/account_diagnostics_card.dart';
import '../widgets/account_section_container.dart';
import 'account_detail_screen.dart';

/// Screen presenting the minimalistic Account Management and Access Inspector.
///
/// Displays available accounts on the router first, explicitly reporting single-user
/// vs multi-account status, and allows tapping an account to inspect detailed
/// effective RPC permissions, SSH reachability, and subsystem capabilities.
class AccountAccessScreen extends ConsumerWidget {
  const AccountAccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(accountAccessControllerProvider);
    final controller = ref.read(accountAccessControllerProvider.notifier);

    final title = l10n?.accountAndAccessTitle ?? 'Account & Access';

    return Scaffold(
      appBar: LuciAppBar(
        title: title,
        showBack: true,
        actions: [
          IconButton(
            icon: state.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            tooltip: l10n?.actionRefresh ?? 'Refresh',
            onPressed: state.isLoading ? null : () => controller.refresh(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: state.isLoading && state.snapshot == null
            ? _buildInitialLoadingView(context, theme)
            : RefreshIndicator(
                onRefresh: () => controller.refresh(),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Top Banner: Strictly Read-Only Guarantee Notice
                      _buildReadOnlyNotice(context, theme),
                      const SizedBox(height: 14),

                      // If an inspection error occurred
                      if (state.errorMessage != null && state.snapshot == null)
                        _buildErrorCard(
                          context,
                          theme,
                          state.errorMessage!,
                          controller,
                        ),

                      if (state.snapshot != null) ...[
                        // Section 1: Router Accounts List (Minimalist Master View)
                        _buildAccountsSection(context, theme, state.snapshot!),
                        const SizedBox(height: 14),

                        // Section 2: Diagnostics Summary & Sanitized Telemetry
                        AccountDiagnosticsCard(snapshot: state.snapshot!),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildReadOnlyNotice(BuildContext context, ThemeData theme) {
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
              l10n?.accountReadOnlyNotice ??
                  'Read-Only Access Inspector: Evaluates authenticated router identity, effective RPC capabilities, and SSH channels non-destructively. No passwords, credentials, or router settings can be modified here.',
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

  Widget _buildAccountsSection(
    BuildContext context,
    ThemeData theme,
    AccountAccessSnapshot snapshot,
  ) {
    final l10n = AppLocalizations.of(context);
    final activeAccount = snapshot.activeAccount;
    final otherAccounts = snapshot.otherAccounts;

    return AccountSectionContainer(
      title: l10n?.accountRouterAccountsTitle ?? 'Router Accounts',
      icon: Icons.manage_accounts_outlined,
      subtitle:
          l10n?.accountRouterAccountsSubtitle ??
          'Accounts identified on this router. Tap an account to reveal its effective access & permissions.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Active Account Card
          _buildActiveAccountTile(context, theme, activeAccount, snapshot),

          const SizedBox(height: 12),

          // Secondary accounts or Single-User OpenWrt explanation
          if (otherAccounts.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
              child: Text(
                l10n?.accountOtherAccountsTitle(otherAccounts.length) ??
                    'Other Configured Accounts (${otherAccounts.length})',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final other in otherAccounts) ...[
              _buildSecondaryAccountTile(context, theme, other, snapshot),
              const SizedBox(height: 8),
            ],
          ] else ...[
            // Explicit Single-User / No Other Accounts indicator
            _buildNoOtherAccountsCard(
              context,
              theme,
              activeAccount.username,
              snapshot,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActiveAccountTile(
    BuildContext context,
    ThemeData theme,
    RouterAccountEntry account,
    AccountAccessSnapshot snapshot,
  ) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => AccountDetailScreen(
                snapshot: snapshot,
                accountEntry: account,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.admin_panel_settings_rounded,
                      color: theme.colorScheme.primary,
                      size: 22,
                    ),
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
                                account.username,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildActiveBadge(context),
                            if (!account.isConfirmedByRouter) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  l10n?.accountProfileLabelOnly ??
                                      'Profile Label Only',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          AccountAccessL10n.getAccountRole(
                            context,
                            account.role,
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n?.accountViewAccess ?? 'View Access',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    account.isConfirmedByRouter
                        ? Icons.verified_user_outlined
                        : Icons.info_outline_rounded,
                    size: 14,
                    color: account.isConfirmedByRouter
                        ? LuciStatusColors.successText(context)
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      account.isConfirmedByRouter
                          ? (l10n?.accountConfirmedViaUnixShell ??
                                'Confirmed independently via router UNIX shell (root)')
                          : (l10n?.accountUnconfirmedSessionApi ??
                                'Identity unconfirmed by LuCI session API (local profile label only)'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: account.isConfirmedByRouter
                            ? LuciStatusColors.successText(context)
                            : theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryAccountTile(
    BuildContext context,
    ThemeData theme,
    RouterAccountEntry account,
    AccountAccessSnapshot snapshot,
  ) {
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => AccountDetailScreen(
                snapshot: snapshot,
                accountEntry: account,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person_outline_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.username,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${AccountAccessL10n.getAccountRole(context, account.role)} • ${AccountAccessL10n.getAccountSource(context, account.source)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoOtherAccountsCard(
    BuildContext context,
    ThemeData theme,
    String primaryUsername,
    AccountAccessSnapshot snapshot,
  ) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.group_off_outlined,
            size: 22,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n?.accountNoOtherAccountsTitle ??
                      'No Other Accounts Configured',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n?.accountNoOtherAccountsDesc(primaryUsername) ??
                      'This router operates with a single administrator account ($primaryUsername). No secondary operator or guest user accounts were detected in rpcd configuration or system logins.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveBadge(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: LuciStatusColors.successBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: LuciStatusColors.successBorder(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LuciStatusIndicators.statusDot(context, true, size: 6),
          const SizedBox(width: 4),
          Text(
            l10n?.accountStatusActiveBadge ?? 'ACTIVE',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: LuciStatusColors.successText(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialLoadingView(BuildContext context, ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            l10n?.accountAuditingLoading ??
                'Auditing account identity & effective permissions...',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(
    BuildContext context,
    ThemeData theme,
    String error,
    AccountAccessController controller,
  ) {
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n?.accountInspectionErrorTitle ?? 'Inspection Error',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () => controller.refresh(),
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(l10n?.accountRetryInspection ?? 'Retry Inspection'),
            ),
          ),
        ],
      ),
    );
  }
}
