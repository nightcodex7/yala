// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import '../controllers/sqm_controller.dart';
import '../models/sqm_overview.dart';
import '../models/sqm_telemetry.dart';
import 'sqm_flow_offloading_dialog.dart';

/// Card showing the SQM daemon service running/enabled status, service controls,
/// operating state badges, and live telemetry polling indicator.
class SqmStatusCard extends ConsumerStatefulWidget {
  final String? routerId;
  final SqmOverview? overview;
  final SqmState? sqmState;
  final VoidCallback onRefresh;

  const SqmStatusCard({
    super.key,
    this.routerId,
    this.overview,
    this.sqmState,
    required this.onRefresh,
  });

  @override
  ConsumerState<SqmStatusCard> createState() => _SqmStatusCardState();
}

class _SqmStatusCardState extends ConsumerState<SqmStatusCard> {
  bool _isToggling = false;

  SqmOverview get _effectiveOverview {
    if (widget.overview != null) return widget.overview!;
    if (widget.sqmState != null) {
      return SqmOverview.fromSqmState(widget.sqmState!);
    }
    return const SqmOverview(isInstalled: false);
  }

  Future<void> _toggleService(bool enable) async {
    if (_isToggling) return;

    final overview = _effectiveOverview;
    if (enable && overview.hasAnyFlowOffloading) {
      final proceed = await showFlowOffloadingWarningDialog(context, ref: ref);
      if (proceed != true || !mounted) {
        return;
      }
    }

    if (!mounted) return;

    setState(() => _isToggling = true);

    final l10n = AppLocalizations.of(context);
    const actionKey = 'sqm_service_toggle';

    if (mounted) {
      context.showToastLoading(
        enable
            ? (l10n?.modSqmEnablingService ?? 'Enabling SQM service...')
            : (l10n?.modSqmDisablingService ?? 'Disabling SQM service...'),
        actionKey: actionKey,
      );
    }

    final bool success;
    if (widget.routerId != null) {
      success = await ref
          .read(sqmControllerProvider(widget.routerId!).notifier)
          .toggleService(enable, context: mounted ? context : null);
    } else {
      final appState = ref.read(appStateProvider);
      success = await appState.toggleSqmService(enable);
    }

    if (mounted) {
      setState(() => _isToggling = false);
      if (success) {
        context.showToastSuccess(
          enable
              ? (l10n?.modSqmServiceEnabledToast ??
                    'SQM service started and enabled.')
              : (l10n?.modSqmServiceDisabledToast ?? 'SQM service stopped.'),
          actionKey: actionKey,
        );
        widget.onRefresh();
      } else {
        context.showToastError(
          l10n?.modSqmServiceToggleFailed ?? 'Failed to update SQM service.',
          subtitle:
              l10n?.toastErrorCheckPermissionsOrService ??
              'Check router permissions or SQM package installation.',
          actionKey: actionKey,
        );
      }
    }
  }

  Future<void> _restartService() async {
    if (_isToggling) return;
    setState(() => _isToggling = true);

    final l10n = AppLocalizations.of(context);
    const actionKey = 'sqm_service_restart';

    if (mounted) {
      context.showToastLoading(
        l10n?.modSqmRestartingService ?? 'Restarting SQM...',
        actionKey: actionKey,
      );
    }

    final bool success;
    if (widget.routerId != null) {
      success = await ref
          .read(sqmControllerProvider(widget.routerId!).notifier)
          .restartService(context: mounted ? context : null);
    } else {
      final appState = ref.read(appStateProvider);
      success = await appState.manageServiceAction(
        'sqm',
        'restart',
        context: mounted ? context : null,
      );
    }

    if (mounted) {
      setState(() => _isToggling = false);
      if (success) {
        context.showToastSuccess(
          l10n?.modSqmServiceRestartedToast ?? 'SQM service restarted.',
          actionKey: actionKey,
        );
        widget.onRefresh();
      } else {
        context.showToastError(
          l10n?.modSqmServiceRestartFailed ?? 'Failed to restart SQM.',
          subtitle:
              l10n?.toastErrorCheckPermissionsOrService ??
              'Check router permissions or init script availability.',
          actionKey: actionKey,
        );
      }
    }
  }

  Widget _buildOperatingStateChip(
    SqmOperatingState state,
    AppLocalizations? l10n,
    ThemeData theme,
  ) {
    final (Color color, String label, IconData icon) = switch (state) {
      SqmOperatingState.active => (
        LuciStatusColors.connected,
        l10n?.modSqmOperatingStateActive ?? 'Active',
        Icons.check_circle_outline_rounded,
      ),
      SqmOperatingState.flowOffloadingConflict => (
        LuciStatusColors.warning,
        l10n?.modSqmOperatingStateConflict ?? 'Offloading Conflict',
        Icons.warning_amber_rounded,
      ),
      SqmOperatingState.telemetryUnavailable ||
      SqmOperatingState.tcCommandUnavailable => (
        theme.colorScheme.tertiary,
        l10n?.modSqmOperatingStateTelemetryUnavailable ?? 'Telemetry N/A',
        Icons.info_outline_rounded,
      ),
      SqmOperatingState.inactive || SqmOperatingState.notInstalled => (
        LuciStatusColors.inactive,
        l10n?.modSqmOperatingStateInactive ?? 'Inactive',
        Icons.pause_circle_outline_rounded,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final overview = _effectiveOverview;
    final isRunning = overview.isServiceRunning;
    final isEnabled = overview.isServiceEnabled;
    final isLive = widget.sqmState?.isTelemetryPolling ?? false;
    final opState = widget.sqmState?.operatingState;

    final statusColor = isRunning
        ? LuciStatusColors.connected
        : (isEnabled ? LuciStatusColors.warning : LuciStatusColors.inactive);

    final statusText = isRunning
        ? (l10n?.modSqmStatusRunning ?? 'Running')
        : (isEnabled
              ? (l10n?.modSqmStatusStoppedEnabled ??
                    'Stopped (Enabled at boot)')
              : (l10n?.modSqmStatusDisabled ?? 'Disabled'));

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              l10n?.modSqmServiceControlTitle ??
                                  'SQM Daemon Service',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isLive) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: LuciStatusColors.connected.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: LuciStatusColors.connected.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: const BoxDecoration(
                                      color: LuciStatusColors.connected,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    l10n?.modSqmTelemetryLiveBadge ??
                                        'Live (3s)',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: LuciStatusColors.connected,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (opState != null)
                            _buildOperatingStateChip(opState, l10n, theme),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        statusText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isToggling)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch(
                    value: isRunning,
                    onChanged: (val) => _toggleService(val),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isEnabled
                      ? (l10n?.modSqmBootEnabled ??
                            'Starts automatically at boot')
                      : (l10n?.modSqmBootDisabled ?? 'Manual start only'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                TextButton.icon(
                  onPressed: _isToggling ? null : _restartService,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(
                    l10n?.modSqmBtnRestartService ?? 'Restart',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
