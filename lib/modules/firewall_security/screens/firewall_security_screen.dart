// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/widgets/luci_collapsible_card.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/widgets/luci_guardrail.dart';
import '../models/firewall_info.dart';
import '../widgets/add_port_forward_dialog.dart';
import '../widgets/advanced_port_forward_dialog.dart';
import '../widgets/advanced_custom_rule_dialog.dart';
import '../widgets/block_incoming_traffic_dialog.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';

class FirewallSecurityScreen extends ConsumerStatefulWidget {
  const FirewallSecurityScreen({super.key});

  @override
  ConsumerState<FirewallSecurityScreen> createState() =>
      _FirewallSecurityScreenState();
}

class _FirewallSecurityScreenState
    extends ConsumerState<FirewallSecurityScreen> {
  /// Stores staged enable/disable toggles for modified custom firewall rules.
  /// Format: {sectionKey: desiredEnabledStatus}
  final Map<String, bool> _stagedCustomRuleStates = {};
  bool? _stagedSoftwareFlowOffload;
  bool? _stagedHardwareFlowOffload;
  bool _isSaving = false;

  bool get _hasUnsavedChanges =>
      _stagedCustomRuleStates.isNotEmpty ||
      _stagedSoftwareFlowOffload != null ||
      _stagedHardwareFlowOffload != null;

  int get _totalUnsavedCount =>
      _stagedCustomRuleStates.length +
      (_stagedSoftwareFlowOffload != null ? 1 : 0) +
      (_stagedHardwareFlowOffload != null ? 1 : 0);

  void _toggleCustomRuleState(FirewallCustomRule rule, bool newValue) {
    setState(() {
      if (newValue == rule.enabled) {
        _stagedCustomRuleStates.remove(rule.sectionKey);
      } else {
        _stagedCustomRuleStates[rule.sectionKey] = newValue;
      }
    });
  }

  void _toggleSoftwareFlowOffload(FirewallDefaultPolicy policy, bool newValue) {
    setState(() {
      if (newValue == policy.flowOffloading) {
        _stagedSoftwareFlowOffload = null;
      } else {
        _stagedSoftwareFlowOffload = newValue;
      }
      // If software flow offloading is disabled, hardware flow offloading must also be turned off
      final effectiveSoftware =
          _stagedSoftwareFlowOffload ?? policy.flowOffloading;
      if (!effectiveSoftware) {
        if (policy.flowOffloadingHw) {
          _stagedHardwareFlowOffload = false;
        } else {
          _stagedHardwareFlowOffload = null;
        }
      }
    });
  }

  void _toggleHardwareFlowOffload(FirewallDefaultPolicy policy, bool newValue) {
    setState(() {
      if (newValue == policy.flowOffloadingHw) {
        _stagedHardwareFlowOffload = null;
      } else {
        _stagedHardwareFlowOffload = newValue;
      }
    });
  }

  void _discardChanges() {
    setState(() {
      _stagedCustomRuleStates.clear();
      _stagedSoftwareFlowOffload = null;
      _stagedHardwareFlowOffload = null;
    });
    if (mounted) {
      final l10n = AppLocalizations.of(context);
      context.showToastInfo(
        'Changes Discarded',
        subtitle:
            l10n?.firewallDiscardedCustomRules ??
            'Discarded all unsaved firewall changes.',
      );
    }
  }

  Future<bool> _showConfirmAndDiscardDialog() async {
    return LuciGuardrail.confirmUnsavedChanges(
      context,
      unsavedCount: _totalUnsavedCount,
      itemLabel: 'firewall setting(s)',
    );
  }

  Future<void> _confirmAndDiscardChanges() async {
    final confirm = await _showConfirmAndDiscardDialog();
    if (confirm) {
      _discardChanges();
    }
  }

  Future<bool> _saveChanges() async {
    if (!_hasUnsavedChanges || _isSaving) return true;

    setState(() {
      _isSaving = true;
    });

    final appState = ref.read(appStateProvider);
    final backend =
        appState.capabilities?.firewallBackend ?? FirewallBackend.fw4;
    final uciFirewall = appState.dashboardData?['uciFirewallConfig'];
    final overview = FirewallOverview.fromUciData(
      uciFirewall,
      backend: backend,
      isReviewerMode: appState.reviewerModeEnabled,
    );

    final modifiedEntries = Map<String, bool>.from(_stagedCustomRuleStates);
    final isFlowOffloadStaged =
        _stagedSoftwareFlowOffload != null ||
        _stagedHardwareFlowOffload != null;

    final succeededRules = <String>[];
    final failedRules = <String>[];
    bool flowOffloadSuccess = true;

    const actionKey = 'save_firewall_rules';
    if (mounted) {
      context.showToastLoading(
        'Saving Changes',
        subtitle: 'Saving firewall changes and reloading service...',
        actionKey: actionKey,
      );
    }

    bool caughtError = false;
    try {
      // 1. Save flow offloading if staged
      if (isFlowOffloadStaged) {
        final defPolicy = overview.defaultPolicy;
        final targetSoft =
            _stagedSoftwareFlowOffload ?? defPolicy.flowOffloading;
        final targetHw = targetSoft
            ? (_stagedHardwareFlowOffload ?? defPolicy.flowOffloadingHw)
            : false;

        flowOffloadSuccess = await appState.updateFirewallFlowOffloading(
          software: targetSoft,
          hardware: targetHw,
          sectionKey: defPolicy.sectionKey,
          context: mounted ? context : null,
        );
      }

      // 2. Save custom rules
      for (final entry in modifiedEntries.entries) {
        if (!mounted) break;
        final sectionKey = entry.key;
        final targetEnabled = entry.value;

        final success = await appState.updateFirewallCustomRuleStatus(
          sectionKey,
          targetEnabled,
          context: mounted ? context : null,
        );

        if (success) {
          succeededRules.add(sectionKey);
        } else {
          failedRules.add(sectionKey);
        }
      }
    } catch (e) {
      caughtError = true;
      if (mounted) {
        context.showToastError(
          'Firewall Save Error',
          subtitle: LuciToastManager.parseErrorReason(e),
          actionKey: actionKey,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          for (final secKey in succeededRules) {
            _stagedCustomRuleStates.remove(secKey);
          }
          if (flowOffloadSuccess) {
            _stagedSoftwareFlowOffload = null;
            _stagedHardwareFlowOffload = null;
          }
          _isSaving = false;
        });
      }
    }

    unawaited(appState.fetchDashboardData());

    if (!mounted) {
      return !caughtError && failedRules.isEmpty && flowOffloadSuccess;
    }

    if (!caughtError && failedRules.isEmpty && flowOffloadSuccess) {
      context.showToastSuccess(
        'Firewall Saved',
        subtitle: 'Firewall settings and rules saved successfully.',
        actionKey: actionKey,
      );
      return true;
    } else if (!caughtError) {
      final l10n = AppLocalizations.of(context);
      final errors = <String>[];
      if (!flowOffloadSuccess) {
        errors.add('Failed to update Flow Offloading settings.');
      }
      if (failedRules.isNotEmpty) {
        errors.add('Failed to update ${failedRules.length} custom rule(s).');
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          actionsOverflowButtonSpacing: 8,
          actionsOverflowDirection: VerticalDirection.down,
          title: Text(
            l10n?.firewallRuleSaveWarning ?? 'Firewall Rule Save Warning',
          ),
          content: SingleChildScrollView(child: Text(errors.join('\n\n'))),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n?.actionConfirm ?? 'OK'),
            ),
          ],
        ),
      );
      return false;
    }
    return false;
  }

  Future<bool?> _showUnsavedChangesDialog() async {
    final l10n = AppLocalizations.of(context);
    final action = await LuciGuardrail.confirmSaveOrDiscardChanges(
      context,
      count: _totalUnsavedCount,
      itemLabel: 'firewall setting/rule change(s)',
      title:
          l10n?.firewallUnsavedCustomRulesTitle ??
          'Unsaved Firewall Rule Changes',
    );

    if (action == 'discard') {
      _discardChanges();
      return true;
    } else if (action == 'save') {
      final saved = await _saveChanges();
      return saved;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final backend = ref.watch(
      appStateProvider.select(
        (s) => s.capabilities?.firewallBackend ?? FirewallBackend.fw4,
      ),
    );
    final uciFirewall = ref.watch(
      appStateProvider.select((s) => s.dashboardData?['uciFirewallConfig']),
    );
    final isReviewerMode = ref.watch(
      appStateProvider.select((s) => s.reviewerModeEnabled),
    );

    final overview = FirewallOverview.fromUciData(
      uciFirewall,
      backend: backend,
      isReviewerMode: isReviewerMode,
    );

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final titlePrefix = l10n?.firewallTitle ?? 'Firewall & Security';
    return PopScope(
      canPop: !_hasUnsavedChanges && !_isSaving,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final shouldLeave = await _showUnsavedChangesDialog();
        if (shouldLeave == true && mounted) {
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                titlePrefix,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                backend == FirewallBackend.fw4
                    ? 'fw4 / nftables'
                    : 'fw3 / iptables',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          actions: [
            if (_hasUnsavedChanges)
              IconButton(
                icon: const Icon(Icons.undo),
                tooltip: l10n?.btnRevert ?? 'Discard Changes',
                onPressed: _isSaving ? null : _confirmAndDiscardChanges,
              ),
            if (_hasUnsavedChanges)
              IconButton(
                icon: const Icon(Icons.save),
                tooltip: l10n?.btnApplyChanges ?? 'Save Changes',
                onPressed: _isSaving ? null : () => _saveChanges(),
              ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            await ref.read(appStateProvider).refreshFirewallState();
          },
          child: !overview.isAvailable
              ? _buildUnavailableView(context, ref, overview)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 100.0),
                  children: [
                    _buildProtectionStatusCard(context, overview),
                    const SizedBox(height: 16),
                    _buildQuickActionsSection(context),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 8),
                    _buildSectionHeader(
                      context,
                      l10n?.firewallAdvancedSettingsTitle ??
                          'Advanced Settings',
                      Icons.settings_outlined,
                    ),
                    const SizedBox(height: 12),
                    _buildSectionHeader(
                      context,
                      l10n?.firewallGlobalPoliciesTitle ??
                          'Global Default Policies',
                      Icons.shield_outlined,
                    ),
                    const SizedBox(height: 8),
                    _buildDefaultPoliciesCard(context, overview.defaultPolicy),
                    const SizedBox(height: 16),
                    _buildSectionHeader(
                      context,
                      l10n?.firewallFlowOffloadingTitle ??
                          'Routing & Flow Offloading',
                      Icons.speed_rounded,
                    ),
                    const SizedBox(height: 8),
                    _buildFlowOffloadingCard(context, overview.defaultPolicy),
                    const SizedBox(height: 16),
                    _buildSectionHeader(
                      context,
                      l10n?.firewallZonesOverviewTitle ??
                          'Firewall Zones Overview',
                      Icons.layers_outlined,
                    ),
                    const SizedBox(height: 8),
                    ...overview.zones.map(
                      (zone) => _buildZoneCard(context, zone),
                    ),
                    const SizedBox(height: 16),
                    LuciCollapsibleCard(
                      title:
                          l10n?.zoneForwardingTitle ??
                          'Inter-Zone Forwarding Rules',
                      count: overview.forwardings.length,
                      subtitle:
                          l10n?.firewallInterZonePoliciesCount(
                            overview.forwardings.length,
                          ) ??
                          '${overview.forwardings.length} inter-zone policies',
                      icon: Icons.alt_route_outlined,
                      iconColor: Colors.blue,
                      childBuilder: (ctx) =>
                          _buildForwardingsCard(context, overview.forwardings),
                    ),
                    const SizedBox(height: 16),
                    LuciCollapsibleCard(
                      title: l10n?.portForwardsTitle ?? 'Port Forwards',
                      count: overview.portForwards.length,
                      subtitle:
                          l10n?.firewallPortForwardsCount(
                            overview.portForwards.length,
                          ) ??
                          '${overview.portForwards.length} port forward rules',
                      icon: Icons.import_export_outlined,
                      iconColor: Colors.orange,
                      childBuilder: (ctx) =>
                          _buildPortForwardingsList(context, overview),
                    ),
                    const SizedBox(height: 16),
                    LuciCollapsibleCard(
                      title: l10n?.customRulesTitle ?? 'Custom Firewall Rules',
                      count: overview.customRules.length,
                      subtitle:
                          l10n?.firewallCustomRulesCount(
                            overview.customRules.length,
                          ) ??
                          '${overview.customRules.length} custom rules',
                      icon: Icons.rule_outlined,
                      iconColor: Colors.teal,
                      childBuilder: (ctx) =>
                          _buildCustomRulesList(context, overview),
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
        ),
        bottomNavigationBar: _hasUnsavedChanges
            ? _buildUnsavedChangesBottomBar(context)
            : null,
      ),
    );
  }

  Widget _buildUnavailableView(
    BuildContext context,
    WidgetRef ref,
    FirewallOverview overview,
  ) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shield_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Firewall Configuration Unavailable',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              overview.errorMessage ??
                  'The firewall configuration could not be loaded or parsed.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () =>
                  ref.read(appStateProvider).redetectCapabilities(),
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(
                AppLocalizations.of(context)?.firewallReprobeCapabilities ??
                    'Re-probe Capabilities',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProtectionStatusCard(
    BuildContext context,
    FirewallOverview overview,
  ) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shield_rounded,
                color: Colors.green,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n?.firewallShieldActive ?? 'Firewall Shield',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green, width: 0.8),
                        ),
                        child: Text(
                          l10n?.statusActive ?? 'ACTIVE',
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n?.firewallShieldActiveSubtitle ??
                        'Defending your home network against unauthorized incoming traffic.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.75,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsSection(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          context,
          l10n?.firewallQuickActionsTitle ?? 'Quick Actions',
          Icons.bolt_outlined,
        ),
        const SizedBox(height: 8),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => AddPortForwardDialog.show(context),
                    child: Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.door_sliding_outlined,
                              color: theme.colorScheme.onPrimaryContainer,
                              size: 22,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            l10n?.firewallOpenPortTitle ?? 'Open a Port',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n?.firewallOpenPortSubtitle ??
                                'Allow external devices to reach an app on your network.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => BlockIncomingTrafficDialog.show(context),
                    child: Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.block_rounded,
                              color: theme.colorScheme.onErrorContainer,
                              size: 22,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            l10n?.firewallBlockIncomingTitle ??
                                'Block an Incoming Connection',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n?.firewallBlockIncomingSubtitle ??
                                'Prevent an external address or connection from reaching your network.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    IconData icon, {
    int maxLines = 2,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: maxLines,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildDefaultPoliciesCard(
    BuildContext context,
    FirewallDefaultPolicy def,
  ) {
    final l10n = AppLocalizations.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildPolicyRow(
              l10n?.firewallDefaultInput ?? 'Default Input',
              def.input,
            ),
            const Divider(),
            _buildPolicyRow(
              l10n?.firewallDefaultOutput ?? 'Default Output',
              def.output,
            ),
            const Divider(),
            _buildPolicyRow(
              l10n?.firewallDefaultForward ?? 'Default Forward',
              def.forward,
            ),
            const Divider(),
            _buildPolicyRow(
              l10n?.firewallSynFloodProtection ?? 'SYN Flood Protection',
              def.synFlood
                  ? (l10n?.firewallStatusEnabled ?? 'ENABLED')
                  : (l10n?.firewallStatusDisabled ?? 'DISABLED'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlowOffloadingCard(
    BuildContext context,
    FirewallDefaultPolicy def,
  ) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final currentSoftware = _stagedSoftwareFlowOffload ?? def.flowOffloading;
    final isSoftwareStaged = _stagedSoftwareFlowOffload != null;

    final currentHardware = currentSoftware
        ? (_stagedHardwareFlowOffload ?? def.flowOffloadingHw)
        : false;
    final isHardwareStaged = _stagedHardwareFlowOffload != null;

    final hasAnyOffload = currentSoftware || currentHardware;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              l10n?.firewallSoftwareOffloadingTitle ??
                                  'Software Flow Offloading',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (isSoftwareStaged) ...[
                            const SizedBox(width: 8),
                            _buildStagedBadge(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n?.firewallSoftwareOffloadingSubtitle ??
                            'Software-based packet offloading for routing/NAT. Reduces CPU load and boosts throughput, but bypasses SQM shaping.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch(
                  value: currentSoftware,
                  onChanged: _isSaving
                      ? null
                      : (val) => _toggleSoftwareFlowOffload(def, val),
                ),
              ],
            ),
            const Divider(height: 24),
            Opacity(
              opacity: currentSoftware ? 1.0 : 0.45,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                l10n?.firewallHardwareOffloadingTitle ??
                                    'Hardware Flow Offloading',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (isHardwareStaged) ...[
                              const SizedBox(width: 8),
                              _buildStagedBadge(),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n?.firewallHardwareOffloadingSubtitle ??
                              'Requires chipset hardware NAT support. Only active when Software Flow Offloading is enabled.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Switch(
                    value: currentHardware,
                    onChanged: (_isSaving || !currentSoftware)
                        ? null
                        : (val) => _toggleHardwareFlowOffload(def, val),
                  ),
                ],
              ),
            ),
            if (hasAnyOffload) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade900.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.amber.shade700.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.amber.shade800,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l10n?.firewallFlowOffloadingSqmWarning ??
                            'Flow offloading bypasses Traffic Control (tc). When enabled, SQM (Smart Queue Management) cannot shape forwarded traffic or mitigate bufferbloat.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade900,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStagedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.amber.shade700, width: 0.8),
      ),
      child: Text(
        'STAGED',
        style: TextStyle(
          color: Colors.amber.shade900,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _buildZoneCard(BuildContext context, FirewallZone zone) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isWan = zone.name.toLowerCase().contains('wan');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        isWan ? Icons.public : Icons.router,
                        color: isWan ? Colors.red : theme.colorScheme.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Zone: ${zone.name.toUpperCase()}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (zone.masquerade) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'MASQUERADE (NAT)',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n?.firewallCoveredNetworks(zone.networks.join(", ")) ??
                  'Covered Networks: ${zone.networks.join(", ")}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildCompactRuleTile(
                  l10n?.firewallTileInput ?? 'Input',
                  zone.input,
                ),
                _buildCompactRuleTile(
                  l10n?.firewallTileOutput ?? 'Output',
                  zone.output,
                ),
                _buildCompactRuleTile(
                  l10n?.firewallTileForward ?? 'Forward',
                  zone.forward,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForwardingsCard(
    BuildContext context,
    List<FirewallForwarding> forwardings,
  ) {
    if (forwardings.isEmpty) {
      final l10n = AppLocalizations.of(context);
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            l10n?.firewallNoZoneRules ?? 'No zone forwarding rules configured.',
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          children: forwardings.map((fwd) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Chip(
                    label: Text(
                      fwd.srcZone.toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12.0),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.grey,
                    ),
                  ),
                  Chip(
                    label: Text(
                      fwd.destZone.toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPortForwardingsList(
    BuildContext context,
    FirewallOverview overview,
  ) {
    final pfs = overview.portForwards;
    final l10n = AppLocalizations.of(context);
    final appState = ref.read(appStateProvider);
    final canModify = appState.capabilities?.canModifyFirewall ?? true;
    final clients = appState.clients;

    return Column(
      children: [
        if (canModify) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add Port Forward'),
                onPressed: () =>
                    AdvancedPortForwardDialog.show(context, overview: overview),
              ),
            ),
          ),
        ],
        if (pfs.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                l10n?.firewallNoPortRules ?? 'No port forwarding rules active.',
              ),
            ),
          )
        else
          ...pfs.map((pf) {
            final matchedClient = clients.cast<Client?>().firstWhere(
              (c) => c != null && c.ipAddress.trim() == pf.destIp.trim(),
              orElse: () => null,
            );
            final deviceName = matchedClient != null
                ? ClientNamingHelper.getDisplayName(
                    matchedClient.macAddress,
                    appState: appState,
                    client: matchedClient,
                  )
                : null;
            final destDisplay = deviceName != null
                ? '$deviceName (${pf.destIp}:${pf.destPort})'
                : '${pf.destIp}:${pf.destPort}';

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.compare_arrows)),
                title: Text(
                  pf.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${pf.srcZone.toUpperCase()}:${pf.srcPort} ➔ $destDisplay (${pf.proto.toUpperCase()})',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: canModify
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            tooltip: 'Edit port forward',
                            onPressed: () => AdvancedPortForwardDialog.show(
                              context,
                              initialPortForward: pf,
                              overview: overview,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            tooltip: 'Delete port forward',
                            onPressed: () => _confirmDeletePortForward(pf),
                          ),
                        ],
                      )
                    : null,
                onTap: canModify
                    ? () => AdvancedPortForwardDialog.show(
                        context,
                        initialPortForward: pf,
                        overview: overview,
                      )
                    : null,
              ),
            );
          }),
      ],
    );
  }

  Future<void> _confirmDeletePortForward(FirewallPortForwarding pf) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Port Forward?'),
        content: Text('Are you sure you want to delete "${pf.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final appState = ref.read(appStateProvider);
      final success = await appState.deleteFirewallPortForward(
        pf.sectionKey,
        context: context,
      );
      if (success && mounted) {
        LuciToastManager.showSuccess(
          context,
          'Port forward "${pf.name}" deleted successfully.',
        );
      }
    }
  }

  Widget _buildCustomRulesList(
    BuildContext context,
    FirewallOverview overview,
  ) {
    final rules = overview.customRules;
    final appState = ref.read(appStateProvider);
    final canModify = appState.capabilities?.canModifyFirewall ?? true;

    return Column(
      children: [
        if (canModify) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add_moderator_outlined),
                label: const Text('Add Security Rule'),
                onPressed: () =>
                    AdvancedCustomRuleDialog.show(context, overview: overview),
              ),
            ),
          ),
        ],
        if (rules.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'No custom security rules defined (default zone policies active).',
              ),
            ),
          )
        else
          ...rules.asMap().entries.map((entry) {
            return _buildCustomRuleCard(
              context: context,
              overview: overview,
              rules: rules,
              index: entry.key,
              r: entry.value,
              canModify: canModify,
            );
          }),
      ],
    );
  }

  Widget _buildCustomRuleCard({
    required BuildContext context,
    required FirewallOverview overview,
    required List<FirewallCustomRule> rules,
    required int index,
    required FirewallCustomRule r,
    required bool canModify,
  }) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isStaged = _stagedCustomRuleStates.containsKey(r.sectionKey);
    final currentEnabled = _stagedCustomRuleStates[r.sectionKey] ?? r.enabled;
    final policyColor = _getPolicyColor(r.target);

    final trafficDetails = <String>[];
    if (r.destPort != null && r.destPort!.isNotEmpty) {
      trafficDetails.add(
        l10n?.firewallRulePort(r.destPort!) ?? 'Port: ${r.destPort}',
      );
    }
    if (r.srcIp != null && r.srcIp!.isNotEmpty) {
      trafficDetails.add(l10n?.firewallRuleIp(r.srcIp!) ?? 'IP: ${r.srcIp}');
    }
    final trafficSuffix = trafficDetails.isNotEmpty
        ? ' (${trafficDetails.join(", ")})'
        : '';
    final flowText =
        '${r.srcZone.toUpperCase()} ➔ ${r.destZone.toUpperCase()}$trafficSuffix';
    final originalStatus = r.enabled
        ? (l10n?.firewallRuleStatusEnabled.toUpperCase() ?? 'ENABLED')
        : (l10n?.firewallRuleStatusDisabled.toUpperCase() ?? 'DISABLED');
    final subtitleText = isStaged
        ? '$flowText • ${l10n?.firewallRuleOriginalStatus(originalStatus) ?? "Original: $originalStatus"}'
        : flowText;

    Widget buildTargetBadge() {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: policyColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: r.isUnrecognizedTarget
              ? Border.all(color: Colors.amber.shade700, width: 1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (r.isUnrecognizedTarget) ...[
              Icon(
                Icons.warning_amber_rounded,
                size: 12,
                color: Colors.amber.shade700,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              r.target,
              style: TextStyle(
                color: r.isUnrecognizedTarget
                    ? Colors.amber.shade800
                    : policyColor,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }

    Widget buildStagedBadge() {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.amber.shade700, width: 0.8),
        ),
        child: Text(
          l10n?.chipStaged ?? 'STAGED',
          style: TextStyle(
            color: Colors.amber.shade900,
            fontWeight: FontWeight.bold,
            fontSize: 10,
          ),
        ),
      );
    }

    final reorderUpButton = IconButton(
      icon: const Icon(Icons.arrow_upward, size: 18),
      tooltip: l10n?.firewallRuleMoveUpTooltip ?? 'Move up',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      onPressed: (index > 0 && !_isSaving)
          ? () => _handleReorderRule(rules, index, -1)
          : null,
    );

    final reorderDownButton = IconButton(
      icon: const Icon(Icons.arrow_downward, size: 18),
      tooltip: l10n?.firewallRuleMoveDownTooltip ?? 'Move down',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      onPressed: (index < rules.length - 1 && !_isSaving)
          ? () => _handleReorderRule(rules, index, 1)
          : null,
    );

    final editButton = IconButton(
      icon: const Icon(Icons.edit_outlined, size: 18),
      tooltip: l10n?.firewallRuleEditTooltip ?? 'Edit rule',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      onPressed: () => AdvancedCustomRuleDialog.show(
        context,
        initialRule: r,
        overview: overview,
      ),
    );

    final deleteButton = IconButton(
      icon: const Icon(Icons.delete_outline, size: 18),
      tooltip: l10n?.firewallRuleDeleteTooltip ?? 'Delete rule',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      onPressed: () => _confirmDeleteCustomRule(r),
    );

    final enableSwitch = Switch.adaptive(
      value: currentEnabled,
      onChanged: _isSaving
          ? null
          : (newValue) => _toggleCustomRuleState(r, newValue),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        decoration: BoxDecoration(
          color: isStaged
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.12)
              : null,
          borderRadius: BorderRadius.circular(14),
          border: isStaged
              ? Border.all(color: theme.colorScheme.primary, width: 1.5)
              : null,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: canModify
              ? () => AdvancedCustomRuleDialog.show(
                  context,
                  initialRule: r,
                  overview: overview,
                )
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 14.0,
              vertical: 12.0,
            ),
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final isWide = constraints.maxWidth >= 540;

                if (isWide) {
                  return Row(
                    children: [
                      Icon(
                        currentEnabled
                            ? Icons.check_circle
                            : Icons.pause_circle_filled,
                        color: currentEnabled
                            ? LuciStatusColors.connected
                            : Colors.grey,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    r.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isStaged) ...[
                                  const SizedBox(width: 6),
                                  buildStagedBadge(),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitleText,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      buildTargetBadge(),
                      const SizedBox(width: 8),
                      if (canModify) ...[
                        reorderUpButton,
                        const SizedBox(width: 2),
                        reorderDownButton,
                        const SizedBox(width: 4),
                        editButton,
                        const SizedBox(width: 2),
                        deleteButton,
                        const SizedBox(width: 6),
                      ],
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          enableSwitch,
                          const SizedBox(width: 4),
                          Text(
                            currentEnabled
                                ? (l10n?.firewallRuleStatusEnabled ?? 'Enabled')
                                : (l10n?.firewallRuleStatusDisabled ??
                                      'Disabled'),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: currentEnabled
                                  ? LuciStatusColors.connected
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }

                // Constrained / Mobile layout: structured secondary row for controls
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          currentEnabled
                              ? Icons.check_circle
                              : Icons.pause_circle_filled,
                          color: currentEnabled
                              ? LuciStatusColors.connected
                              : Colors.grey,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  r.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isStaged) ...[
                                const SizedBox(width: 6),
                                buildStagedBadge(),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        buildTargetBadge(),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 30,
                        top: 4,
                        bottom: 6,
                      ),
                      child: Text(
                        subtitleText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      color: theme.dividerColor.withValues(alpha: 0.25),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              enableSwitch,
                              const SizedBox(width: 4),
                              Text(
                                currentEnabled
                                    ? (l10n?.firewallRuleStatusEnabled ??
                                          'Enabled')
                                    : (l10n?.firewallRuleStatusDisabled ??
                                          'Disabled'),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: currentEnabled
                                      ? LuciStatusColors.connected
                                      : theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          if (canModify)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                reorderUpButton,
                                const SizedBox(width: 2),
                                reorderDownButton,
                                const SizedBox(width: 4),
                                editButton,
                                const SizedBox(width: 2),
                                deleteButton,
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleReorderRule(
    List<FirewallCustomRule> rules,
    int currentIndex,
    int delta,
  ) async {
    if (_hasUnsavedChanges) {
      LuciToastManager.showWarning(
        context,
        'Please save or discard unsaved changes before reordering rules.',
      );
      return;
    }

    final targetRule = rules[currentIndex];
    final siblingRule = rules[currentIndex + delta];
    final expectedOrder = rules.map((r) => r.sectionKey).toList();

    const actionKey = 'reorder_firewall_rule';
    context.showToastLoading(
      'Reordering Rules',
      subtitle: 'Updating firewall rule priority...',
      actionKey: actionKey,
    );

    final appState = ref.read(appStateProvider);
    final success = await appState.reorderFirewallCustomRules(
      targetSectionKey: targetRule.sectionKey,
      siblingSectionKey: siblingRule.sectionKey,
      expectedRuleOrder: expectedOrder,
      context: mounted ? context : null,
    );

    if (!mounted) return;
    if (success) {
      context.showToastSuccess(
        'Rules Reordered',
        subtitle: 'Firewall rule order updated successfully.',
        actionKey: actionKey,
      );
    } else {
      context.showToastError(
        'Reorder Failed',
        subtitle: 'Unable to update rule order in firewall configuration.',
        actionKey: actionKey,
      );
    }
  }

  Future<void> _confirmDeleteCustomRule(FirewallCustomRule r) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Security Rule?'),
        content: Text('Are you sure you want to delete "${r.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final appState = ref.read(appStateProvider);
      final success = await appState.deleteFirewallCustomRule(
        r.sectionKey,
        context: context,
      );
      if (mounted) {
        if (success) {
          LuciToastManager.showSuccess(
            context,
            'Security rule "${r.name}" deleted successfully.',
          );
        } else {
          LuciToastManager.showError(
            context,
            'Failed to delete "${r.name}"',
            subtitle:
                l10n?.toastErrorCheckPermissionsOrFirewall ??
                'Check router permissions or firewall configuration.',
          );
        }
      }
    }
  }

  Widget _buildPolicyRow(String title, String policy) {
    final color = _getPolicyColor(policy);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              policy,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactRuleTile(String label, String policy) {
    final color = _getPolicyColor(policy);
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(
          policy,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Color _getPolicyColor(String policy) {
    switch (policy.toUpperCase()) {
      case 'ACCEPT':
      case 'ENABLED':
        return LuciStatusColors.connected;
      case 'REJECT':
        return Colors.orange;
      case 'DROP':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  Widget _buildUnsavedChangesBottomBar(BuildContext context) {
    final theme = Theme.of(context);
    final count = _totalUnsavedCount;
    final text =
        _stagedCustomRuleStates.isNotEmpty &&
            (_stagedSoftwareFlowOffload != null ||
                _stagedHardwareFlowOffload != null)
        ? '$count items modified'
        : _stagedCustomRuleStates.isNotEmpty
        ? '$count rule(s) modified'
        : '$count setting(s) modified';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Icon(Icons.edit_note, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            OutlinedButton(
              onPressed: _isSaving ? null : _confirmAndDiscardChanges,
              child: Text(
                AppLocalizations.of(context)?.actionDiscard ?? 'Discard',
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _isSaving ? null : () => _saveChanges(),
              icon: _isSaving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check, size: 18),
              label: Text(AppLocalizations.of(context)?.actionSave ?? 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}
