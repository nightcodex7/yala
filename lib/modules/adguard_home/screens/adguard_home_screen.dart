// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/luci_loading_view.dart';
import 'package:yet_another_luci_app/widgets/luci_loading_states.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import '../controllers/adguard_controller.dart';
import '../models/adguard_models.dart';
import '../utils/adguard_web_url_helper.dart';
import '../widgets/adguard_credentials_dialog.dart';
import '../widgets/adguard_process_card.dart';
import '../widgets/adguard_profile_dialog.dart';
import '../widgets/adguard_protection_card.dart';
import '../widgets/adguard_service_card.dart';
import '../widgets/adguard_stats_card.dart';
import '../widgets/adguard_status_card.dart';
import '../widgets/adguard_filtering_card.dart';
import '../widgets/adguard_filter_lists_dialog.dart';
import '../widgets/adguard_custom_rules_dialog.dart';
import '../widgets/adguard_top_lists_card.dart';
import '../widgets/adguard_topology_card.dart';

/// Full-screen view for managing AdGuard Home instances (local router or external host).
///
/// Features:
/// - Fast loading UX with [LuciLoadingView] and localized rotating captions.
/// - Multi-instance profile switching and external instance configuration.
/// - Auto-polling coordination, capability evaluation, and DNS topology.
/// - Process telemetry and service management (local router instances only).
/// - Statistics, top lists, and protection controls.
class AdGuardHomeScreen extends ConsumerStatefulWidget {
  final String? routerId;

  const AdGuardHomeScreen({super.key, this.routerId});

  @override
  ConsumerState<AdGuardHomeScreen> createState() => _AdGuardHomeScreenState();
}

class _AdGuardHomeScreenState extends ConsumerState<AdGuardHomeScreen> {
  String? _activeRouterId;
  AdGuardController? _controller;

  String _resolveRouterId() {
    return widget.routerId ??
        ref.read(appStateProvider).selectedRouter?.id ??
        'default';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _activeRouterId = _resolveRouterId();
      _controller = ref.read(
        adguardControllerProvider(_activeRouterId!).notifier,
      );
      _controller?.loadProfiles();
      _controller?.startPolling();
    });
  }

  @override
  void didUpdateWidget(covariant AdGuardHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routerId != widget.routerId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _controller?.stopPolling(updateState: false);
        _activeRouterId = _resolveRouterId();
        _controller = ref.read(
          adguardControllerProvider(_activeRouterId!).notifier,
        );
        _controller?.loadProfiles();
        _controller?.startPolling();
      });
    }
  }

  @override
  void dispose() {
    _controller?.stopPolling(updateState: false);
    super.dispose();
  }

  String _getPollingLabel(
    AppLocalizations? l10n,
    AdGuardPollingInterval interval,
  ) {
    switch (interval) {
      case AdGuardPollingInterval.off:
        return l10n?.aghPollingOff ?? 'Off';
      case AdGuardPollingInterval.s5:
        return l10n?.aghPolling5s ?? '5 seconds';
      case AdGuardPollingInterval.s10:
        return l10n?.aghPolling10s ?? '10 seconds';
      case AdGuardPollingInterval.s30:
        return l10n?.aghPolling30s ?? '30 seconds';
      case AdGuardPollingInterval.manual:
        return l10n?.aghPollingManual ?? 'Manual only';
    }
  }

  @override
  Widget build(BuildContext context) {
    final routerId = _resolveRouterId();
    _activeRouterId = routerId;

    final appState = ref.watch(appStateProvider);
    final state = ref.watch(adguardControllerProvider(routerId));
    final controller = ref.read(adguardControllerProvider(routerId).notifier);
    _controller = controller;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isReviewerMode = appState.reviewerModeEnabled;
    final routerHost = appState.selectedRouter?.ipAddress ?? '192.168.1.1';
    final effectiveHost = state.isExternal
        ? (state.activeProfile?.host ?? '127.0.0.1')
        : routerHost;
    final effectiveUseHttps = state.isExternal
        ? (state.activeProfile?.useHttps ?? false)
        : (appState.selectedRouter?.useHttps ?? false);
    final effectiveHttpPort = state.isExternal
        ? (state.activeProfile?.port ?? 3000)
        : (state.status?.httpPort ?? state.capabilities.discoveredHttpPort);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n?.modAdGuardHomeName ?? 'AdGuard Home'),
            if (state.activeProfile != null)
              Text(
                state.activeProfile!.name,
                key: const Key('agh_active_profile_subtitle'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: [
          // Profile Selector Popup Menu
          PopupMenuButton<String>(
            key: const Key('agh_profile_selector_button'),
            tooltip: 'Instance Profiles',
            icon: const Icon(Icons.dns_outlined),
            onSelected: (value) async {
              if (value == 'add_external') {
                await AdGuardProfileDialog.show(
                  context,
                  controller: controller,
                );
              } else if (value.startsWith('edit_')) {
                await AdGuardProfileDialog.show(
                  context,
                  controller: controller,
                  initialProfile: state.activeProfile,
                );
              } else if (value.startsWith('delete_')) {
                final profileId = value.substring('delete_'.length);
                final profileToDelete = state.profiles.firstWhere(
                  (p) => p.id == profileId,
                  orElse: () => state.activeProfile!,
                );
                if (profileToDelete.type != AdGuardInstanceType.externalHost) {
                  return;
                }
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(
                      l10n?.aghDeleteProfileTitle ?? 'Delete Instance Profile?',
                    ),
                    content: Text(
                      'Are you sure you want to delete profile "${profileToDelete.name}"? Stored credentials for this instance will be permanently removed.',
                    ),
                    actions: [
                      TextButton(
                        key: const Key('agh_delete_profile_cancel_button'),
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: Text(l10n?.actionCancel ?? 'Cancel'),
                      ),
                      FilledButton(
                        key: const Key('agh_delete_profile_confirm_button'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(ctx).colorScheme.error,
                          foregroundColor: Theme.of(ctx).colorScheme.onError,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: Text(l10n?.actionDelete ?? 'Delete'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && context.mounted) {
                  try {
                    await controller.deleteExternalProfile(profileId);
                  } catch (e) {
                    if (context.mounted) {
                      context.showToastError(
                        'Failed to delete profile',
                        subtitle: LuciToastManager.parseErrorReason(e),
                      );
                    }
                  }
                }
              } else {
                final selected = state.profiles.firstWhere(
                  (p) => p.id == value,
                  orElse: () => state.activeProfile!,
                );
                await controller.selectProfile(selected);
              }
            },
            itemBuilder: (context) {
              return [
                ...state.profiles.map((profile) {
                  final isCurrent = state.activeProfile?.id == profile.id;
                  final isExt =
                      profile.type == AdGuardInstanceType.externalHost;
                  return PopupMenuItem<String>(
                    key: Key('agh_profile_item_${profile.id}'),
                    value: profile.id,
                    child: Row(
                      children: [
                        Icon(
                          isExt ? Icons.dns_outlined : Icons.router_outlined,
                          size: 18,
                          color: isCurrent ? colorScheme.primary : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            profile.name,
                            style: TextStyle(
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isCurrent ? colorScheme.primary : null,
                            ),
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.check,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                        ],
                      ],
                    ),
                  );
                }),
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  key: const Key('agh_add_external_profile_button'),
                  value: 'add_external',
                  child: Row(
                    children: [
                      const Icon(Icons.add_rounded, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n?.aghAddExternalInstance ??
                              'Add External Instance',
                        ),
                      ),
                    ],
                  ),
                ),
                if (state.isExternal && state.activeProfile != null) ...[
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    key: const Key('agh_edit_active_profile_button'),
                    value: 'edit_${state.activeProfile!.id}',
                    child: Row(
                      children: [
                        const Icon(Icons.edit_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n?.aghEditCurrentProfile ??
                                'Edit Current Profile',
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    key: const Key('agh_delete_active_profile_button'),
                    value: 'delete_${state.activeProfile!.id}',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Delete Current Profile',
                            style: TextStyle(color: colorScheme.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ];
            },
          ),

          // Polling Interval Selector Popup Menu
          PopupMenuButton<AdGuardPollingInterval>(
            key: const Key('agh_polling_interval_button'),
            tooltip: l10n?.aghPollingInterval ?? 'Polling Interval',
            icon: const Icon(Icons.timer_outlined),
            initialValue: state.pollingInterval,
            onSelected: (interval) {
              controller.setPollingInterval(interval);
            },
            itemBuilder: (context) {
              return AdGuardPollingInterval.values.map((interval) {
                return PopupMenuItem<AdGuardPollingInterval>(
                  key: Key('agh_polling_${interval.name}'),
                  value: interval,
                  child: Row(
                    children: [
                      if (state.pollingInterval == interval)
                        Icon(Icons.check, size: 16, color: colorScheme.primary)
                      else
                        const SizedBox(width: 16),
                      const SizedBox(width: 8),
                      Text(_getPollingLabel(l10n, interval)),
                    ],
                  ),
                );
              }).toList();
            },
          ),

          // Open Web UI Action
          IconButton(
            key: const Key('agh_appbar_web_ui_button'),
            tooltip: l10n?.aghWebInterface ?? 'Open Web Interface',
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: () {
              AdGuardWebUrlHelper.launchWebInterface(
                context: context,
                isReviewerMode: isReviewerMode,
                host: effectiveHost,
                port: effectiveHttpPort,
                useHttps: effectiveUseHttps,
              );
            },
          ),

          // Refresh Button
          IconButton(
            key: const Key('agh_appbar_refresh_button'),
            tooltip: l10n?.actionRefresh ?? 'Refresh',
            icon: state.isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: state.isRefreshing ? null : () => controller.refresh(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => controller.refresh(),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          children: [
            if (state.isInitialLoading)
              const LuciLoadingView(
                key: Key('agh_initial_loading_view'),
                padding: EdgeInsets.symmetric(vertical: 8),
                skeleton: Column(
                  children: [
                    LuciCardSkeleton(),
                    SizedBox(height: 16),
                    LuciCardSkeleton(),
                  ],
                ),
              )
            else if (state.isDiscoveryFailed)
              _buildConnectionErrorView(context, controller, state, l10n, theme)
            else ...[
              // Connection Status Banners
              if (state.connectionStatus ==
                  AdGuardConnectionStatus.authRequired)
                _buildAuthRequiredBanner(context, controller, l10n, theme),

              if (state.connectionStatus ==
                  AdGuardConnectionStatus.invalidEndpoint)
                _buildBanner(
                  context,
                  icon: Icons.error_outline,
                  color: Colors.red.shade700,
                  message:
                      l10n?.aghInvalidEndpoint ??
                      'The configured HTTP port returned a response that is not AdGuard Home.',
                  keyName: 'agh_invalid_endpoint_banner',
                ),

              if (state.connectionStatus ==
                  AdGuardConnectionStatus.apiUnreachable)
                _buildBanner(
                  context,
                  icon: Icons.cloud_off_rounded,
                  color: Colors.amber.shade800,
                  message:
                      l10n?.aghApiUnreachable ??
                      'Unable to reach AdGuard Home API.',
                  keyName: 'agh_api_unreachable_banner',
                  trailing: TextButton(
                    onPressed: () => controller.refresh(),
                    child: Text(l10n?.actionRetry ?? 'Retry'),
                  ),
                ),

              if (state.connectionStatus == AdGuardConnectionStatus.degraded)
                _buildBanner(
                  context,
                  icon: Icons.warning_amber_rounded,
                  color: Colors.amber.shade800,
                  message:
                      l10n?.aghDegradedState ??
                      'Some AdGuard Home telemetry is degraded.',
                  keyName: 'agh_degraded_banner',
                ),

              if (state.generalError != null &&
                  state.connectionStatus !=
                      AdGuardConnectionStatus.apiUnreachable &&
                  state.connectionStatus !=
                      AdGuardConnectionStatus.invalidEndpoint &&
                  state.connectionStatus !=
                      AdGuardConnectionStatus.authRequired)
                _buildBanner(
                  context,
                  icon: Icons.error_outline_rounded,
                  color: Colors.red.shade700,
                  message: state.generalError!,
                  keyName: 'agh_general_error_banner',
                  trailing: TextButton(
                    onPressed: () => controller.refresh(),
                    child: Text(l10n?.actionRetry ?? 'Retry'),
                  ),
                ),

              // External Topology Disclaimer
              if (state.isExternal)
                _buildExternalTopologyNotice(context, theme),

              // Main Status Card
              AdGuardStatusCard(
                status: state.status,
                routerHost: effectiveHost,
                isReviewerMode: isReviewerMode,
                useHttps: effectiveUseHttps,
              ),

              // Protection Control Card
              AdGuardProtectionCard(
                status: state.status,
                isMutating: state.isMutatingProtection,
                actionError: state.protectionActionError,
                onSetProtection: ({required bool enabled, Duration? duration}) {
                  return controller.setProtection(
                    enabled: enabled,
                    duration: duration,
                  );
                },
              ),

              // Filtering & Rules Card
              AdGuardFilteringCard(
                filtering: state.filtering,
                filteringError: state.filteringError,
                isLoading: state.isLoading && state.filtering == null,
                onManageFilterLists: () => AdGuardFilterListsDialog.show(
                  context,
                  controller: controller,
                ),
                onManageUserRules: () => AdGuardCustomRulesDialog.show(
                  context,
                  controller: controller,
                  initialRules: state.filtering?.userRules,
                ),
              ),

              // Statistics Overview Card
              AdGuardStatsCard(
                stats: state.stats,
                statsError: state.statsError,
                selectedPeriod: state.statsPeriod,
                onPeriodChanged: (period) => controller.setStatsPeriod(period),
              ),

              // Top Lists Card (Blocked, Queried, Clients)
              AdGuardTopListsCard(stats: state.stats),

              // DNS Topology Card
              AdGuardTopologyCard(
                topology: state.topology,
                controller: controller,
                routerId: widget.routerId,
              ),

              // Host Process Telemetry Card (Local router instances only)
              if (!state.isExternal)
                AdGuardProcessCard(
                  telemetry: state.processTelemetry,
                  processError: state.processTelemetryError,
                ),

              // Service Management Card (Local router instances only)
              if (!state.isExternal)
                AdGuardServiceCard(
                  isRunning: state.status?.running ?? false,
                  isManageable: state.capabilities.isServiceManageable,
                  isManaging: state.isManagingService,
                  actionError: state.serviceActionError,
                  isAutostartEnabled: state.capabilities.isServiceEnabled,
                  onToggleAutostart: (val) =>
                      controller.setServiceAutostart(val),
                  onStart: () => controller.startService(),
                  onStop: () => controller.stopService(),
                  onRestart: () => controller.restartService(),
                ),

              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExternalTopologyNotice(BuildContext context, ThemeData theme) {
    return Container(
      key: const Key('agh_external_topology_disclaimer'),
      margin: const EdgeInsets.only(bottom: 8.0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'External AdGuard Home instance: Router DNS forwarding is unverified. Ensure your router or network clients point to this instance for filtering.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionErrorView(
    BuildContext context,
    AdGuardController controller,
    AdGuardState state,
    AppLocalizations? l10n,
    ThemeData theme,
  ) {
    return Center(
      key: const Key('agh_discovery_error_view'),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 32),
            Icon(
              Icons.cloud_off_rounded,
              size: 56,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              l10n?.aghUnreachableTitle ?? 'AdGuard Home Unreachable',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _getLocalizedAghError(
                state.statusError ?? state.generalError,
                l10n,
              ),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('agh_error_retry_button'),
              onPressed: () => controller.refresh(),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n?.actionRetry ?? 'Retry'),
            ),
            if (!state.isExternal) ...[
              const SizedBox(height: 24),
              Card(
                key: const Key('agh_unreachable_setup_guide_card'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ),
                color: theme.colorScheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n?.aghManagementTitle ??
                                  'AdGuard Home Management',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        l10n?.aghManagementGuide ??
                            'YALA manages existing AdGuard Home instances and does not install software on the router.\n\n'
                                '• Router-local instance: Install and configure AdGuard Home independently (via SSH or your package manager), ensure the service is running, then tap Retry.\n'
                                '• External instance: If running AdGuard Home on a Raspberry Pi, NAS, or server, add an external profile.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          key: const Key('agh_configure_external_button'),
                          onPressed: () => AdGuardProfileDialog.show(
                            context,
                            controller: controller,
                          ),
                          icon: const Icon(Icons.add_link_rounded, size: 18),
                          label: Text(
                            l10n?.aghAddExternalProfile ??
                                'Add External Profile',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  String _getLocalizedAghError(String? raw, AppLocalizations? l10n) {
    if (raw == null) {
      return l10n?.aghNetworkErrorSubtitle ??
          'Network connection failure communicating with AdGuard Home';
    }
    if (raw.contains('Network connection failure') ||
        raw.contains('failure communicating')) {
      return l10n?.aghNetworkErrorSubtitle ?? raw;
    }
    return raw;
  }

  Widget _buildAuthRequiredBanner(
    BuildContext context,
    AdGuardController controller,
    AppLocalizations? l10n,
    ThemeData theme,
  ) {
    return Container(
      key: const Key('agh_auth_required_banner'),
      margin: const EdgeInsets.only(bottom: 8.0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade700, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline, color: Colors.amber.shade900, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n?.aghAuthRequired ??
                      'AdGuard Home Authentication Required',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n?.aghCredentialsSubtitle ??
                'Enter HTTP credentials for AdGuard Home to enable statistics and protection management.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.amber.shade900,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              key: const Key('agh_enter_credentials_button'),
              onPressed: () {
                AdGuardCredentialsDialog.show(context, controller: controller);
              },
              child: Text(l10n?.aghEnterCredentials ?? 'Enter Credentials'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBanner(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String message,
    required String keyName,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    return Container(
      key: Key(keyName),
      margin: const EdgeInsets.only(bottom: 8.0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1.0),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      ),
    );
  }
}
