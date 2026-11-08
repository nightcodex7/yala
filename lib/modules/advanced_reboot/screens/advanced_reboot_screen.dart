// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/app_localizations.dart';
import '../../../design/luci_design_system.dart';
import '../../../widgets/luci_app_bar.dart';
import '../controllers/advanced_reboot_controller.dart';
import '../models/reboot_capability.dart';
import '../models/reboot_state.dart';

class _RebootCard extends StatelessWidget {
  final Widget child;
  final Color? color;

  const _RebootCard({required this.child, this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: child,
    );
  }
}

class AdvancedRebootScreen extends ConsumerStatefulWidget {
  const AdvancedRebootScreen({super.key});

  @override
  ConsumerState<AdvancedRebootScreen> createState() =>
      _AdvancedRebootScreenState();
}

class _AdvancedRebootScreenState extends ConsumerState<AdvancedRebootScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(advancedRebootControllerProvider);
    final controller = ref.read(advancedRebootControllerProvider.notifier);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: LuciAppBar(
        title: l10n?.advRebootTitle ?? 'Advanced Reboot',
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.description_outlined),
            tooltip:
                l10n?.advRebootTooltipDiagnostics ??
                'View Diagnostics & Evidence',
            onPressed: state.capabilities != null
                ? () => _showDiagnosticsSheet(context, state.capabilities!)
                : null,
          ),
          IconButton(
            icon: state.isDetecting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            tooltip: l10n?.advRebootTooltipRedetect ?? 'Re-detect Capabilities',
            onPressed: state.isDetecting
                ? null
                : () => controller.detectCapabilities(),
          ),
        ],
      ),
      body: SafeArea(
        child: state.isDetecting && state.capabilities == null
            ? _buildInitialLoadingView(theme, l10n)
            : RefreshIndicator(
                onRefresh: () => controller.detectCapabilities(),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (state.progress.isBusy || !state.progress.isIdle)
                        _buildExecutionStatusCard(
                          context,
                          state.progress,
                          controller,
                          l10n,
                        ),
                      if (state.detectionError != null)
                        _buildDetectionErrorBanner(
                          context,
                          state.detectionError!,
                        ),
                      if (state.capabilities != null) ...[
                        _buildEnvironmentOverviewCard(
                          context,
                          state.capabilities!,
                          l10n,
                        ),
                        const SizedBox(height: 16),
                        _buildSectionHeader(
                          context,
                          l10n?.advRebootAvailableOperations ??
                              'Available Operations',
                        ),
                        const SizedBox(height: 8),
                        _buildStandardRebootCard(
                          context,
                          state,
                          controller,
                          l10n,
                        ),
                        const SizedBox(height: 12),
                        _buildAlternatePartitionCard(
                          context,
                          state,
                          controller,
                          l10n,
                        ),
                        const SizedBox(height: 12),
                        _buildPowerOffCard(context, state, controller, l10n),
                      ],
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildInitialLoadingView(ThemeData theme, AppLocalizations? l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              l10n?.advRebootAnalyzingBootEnv ?? 'Analyzing Boot Environment',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n?.advRebootAnalyzingBootEnvDesc ??
                  'Reading MTD partitions, board identifier, and bootloader configuration non-destructively...',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetectionErrorBanner(BuildContext context, String error) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  error,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEnvironmentOverviewCard(
    BuildContext context,
    AdvancedRebootCapabilities caps,
    AppLocalizations? l10n,
  ) {
    final theme = Theme.of(context);
    final env = caps.environment;
    final altCap =
        caps.capabilities[RebootOperationType.alternatePartitionBoot];
    final bool isDualBootSupported = altCap?.isSupported ?? false;
    final String mechanismBadge =
        env.discoveredMechanismName ??
        (isDualBootSupported
            ? (l10n?.advRebootBadgeNativeDualBoot ?? 'Native Dual-Boot')
            : (env.hasDualPartitionLayout
                  ? (l10n?.advRebootBadgeDualBootUnverified ??
                        'Dual-Boot (Unverified)')
                  : (l10n?.advRebootBadgeSingleBootLayout ??
                        'Single-Boot Layout')));
    final CapabilityStatus badgeStatus = isDualBootSupported
        ? CapabilityStatus.supported
        : (env.hasDualPartitionLayout
              ? CapabilityStatus.unknown
              : CapabilityStatus.supported);

    final String activeSlotText;
    if (env.activeSlot != null) {
      if (env.activeOs != null && env.activeOs!.isNotEmpty) {
        activeSlotText =
            l10n?.advRebootSlotWithOs(env.activeSlot!, env.activeOs!) ??
            'Slot ${env.activeSlot} (${env.activeOs})';
      } else {
        activeSlotText =
            l10n?.advRebootSlotWithoutOs(env.activeSlot!) ??
            'Slot ${env.activeSlot}';
      }
    } else {
      activeSlotText = env.hasDualPartitionLayout
          ? (l10n?.advRebootDualPartitionUnknown ??
                'Dual Partition (Slot Unknown)')
          : (l10n?.advRebootSinglePartitionLayout ?? 'Single Partition Layout');
    }

    final String? alternateSlotText;
    if (env.alternateSlot != null) {
      if (env.alternateOs != null && env.alternateOs!.isNotEmpty) {
        alternateSlotText =
            l10n?.advRebootSlotWithOs(env.alternateSlot!, env.alternateOs!) ??
            'Slot ${env.alternateSlot} (${env.alternateOs})';
      } else {
        alternateSlotText =
            l10n?.advRebootSlotWithoutOs(env.alternateSlot!) ??
            'Slot ${env.alternateSlot}';
      }
    } else {
      alternateSlotText = null;
    }

    return _RebootCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.memory_rounded,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    env.model.isNotEmpty
                        ? env.model
                        : (l10n?.advRebootRouterEnvironment ??
                              'Router Environment'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildStatusChip(context, mechanismBadge, badgeStatus),
              ],
            ),
            const SizedBox(height: 12),
            _buildEnvRow(
              context,
              l10n?.advRebootBoardId ?? 'Board ID',
              env.boardName.isEmpty
                  ? (l10n?.advRebootUnknown ?? 'Unknown')
                  : env.boardName,
            ),
            _buildEnvRow(
              context,
              l10n?.advRebootArchitecture ?? 'Architecture',
              env.targetArchitecture.isEmpty
                  ? 'Generic'
                  : env.targetArchitecture,
            ),
            _buildEnvRow(
              context,
              l10n?.advRebootRelease ?? 'Release',
              env.releaseVersion.isEmpty ? 'OpenWrt' : env.releaseVersion,
            ),
            _buildEnvRow(
              context,
              l10n?.advRebootActiveBootSlot ?? 'Active Boot Slot',
              activeSlotText,
              isBold: true,
            ),
            if (alternateSlotText != null)
              _buildEnvRow(
                context,
                l10n?.advRebootAlternateBootSlot ?? 'Alternate Boot Slot',
                alternateSlotText,
                isBold: true,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnvRow(
    BuildContext context,
    String label,
    String value, {
    bool isBold = false,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildStandardRebootCard(
    BuildContext context,
    AdvancedRebootState state,
    AdvancedRebootController controller,
    AppLocalizations? l10n,
  ) {
    final theme = Theme.of(context);
    final cap = state.capabilities?.standardReboot;
    final isBusy = state.progress.isBusy;

    return _RebootCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.restart_alt_rounded,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n?.advRebootStandardRebootTitle ??
                        'Standard System Reboot',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _buildStatusChip(
                  context,
                  _statusLabel(CapabilityStatus.supported, l10n),
                  CapabilityStatus.supported,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _resolveStandardRebootDescription(cap, l10n),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                  l10n?.advRebootBtnStandardReboot ?? 'Reboot Router',
                ),
                onPressed: isBusy
                    ? null
                    : () => _confirmStandardReboot(context, controller, l10n),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlternatePartitionCard(
    BuildContext context,
    AdvancedRebootState state,
    AdvancedRebootController controller,
    AppLocalizations? l10n,
  ) {
    final theme = Theme.of(context);
    final cap = state.capabilities?.alternatePartitionBoot;
    final targetSlot = cap?.targetIdentifier;
    final isSupported = cap?.isSupported ?? false;
    final isBusy = state.progress.isBusy;

    final String buttonLabel;
    if (targetSlot != null) {
      if (state.capabilities?.environment.alternateOs != null &&
          state.capabilities!.environment.alternateOs!.isNotEmpty) {
        buttonLabel =
            l10n?.advRebootBtnRebootToSlotWithOs(
              targetSlot,
              state.capabilities!.environment.alternateOs!,
            ) ??
            'Reboot to Slot $targetSlot (${state.capabilities!.environment.alternateOs})';
      } else {
        buttonLabel =
            l10n?.advRebootBtnRebootToSlotWithoutOs(targetSlot) ??
            'Reboot to Slot $targetSlot';
      }
    } else {
      buttonLabel =
          l10n?.advRebootBtnAltUnavailable ?? 'Alternate Boot Unavailable';
    }

    final warningText = _resolveAltPartitionWarning(cap, l10n);

    return _RebootCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.alt_route_rounded,
                  color: isSupported
                      ? LuciStatusColors.warningColor(context)
                      : theme.colorScheme.outline,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n?.advRebootAltPartitionTitle ??
                        'Alternate Firmware Partition',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _buildStatusChip(
                  context,
                  _statusLabel(cap?.status ?? CapabilityStatus.unknown, l10n),
                  cap?.status ?? CapabilityStatus.unknown,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _resolveAltPartitionDescription(
                cap,
                state.capabilities?.environment ??
                    const DeviceBootEnvironment(
                      boardName: '',
                      model: '',
                      releaseVersion: '',
                    ),
                l10n,
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (warningText != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: LuciStatusColors.warningBg(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: LuciStatusColors.warningBorder(context),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: LuciStatusColors.warningColor(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        warningText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: LuciStatusColors.warningText(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                icon: const Icon(Icons.swap_calls_rounded, size: 18),
                label: Text(buttonLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: isSupported
                      ? LuciStatusColors.warningColor(context)
                      : null,
                  foregroundColor: isSupported ? Colors.white : null,
                ),
                onPressed: (isSupported && !isBusy && targetSlot != null)
                    ? () => _confirmAlternatePartitionReboot(
                        context,
                        controller,
                        targetSlot,
                        l10n,
                        alternateOs:
                            state.capabilities?.environment.alternateOs,
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPowerOffCard(
    BuildContext context,
    AdvancedRebootState state,
    AdvancedRebootController controller,
    AppLocalizations? l10n,
  ) {
    final theme = Theme.of(context);
    final cap = state.capabilities?.powerOff;
    final isSupported = cap?.isSupported ?? false;
    final isBusy = state.progress.isBusy;

    return _RebootCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.power_settings_new_rounded,
                  color: isSupported
                      ? theme.colorScheme.error
                      : theme.colorScheme.outline,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n?.advRebootPowerOffTitle ?? 'Power Off Router',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _buildStatusChip(
                  context,
                  _statusLabel(
                    cap?.status ?? CapabilityStatus.unsupported,
                    l10n,
                  ),
                  cap?.status ?? CapabilityStatus.unsupported,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _resolvePowerOffDescription(
                cap,
                state.capabilities?.environment ??
                    const DeviceBootEnvironment(
                      boardName: '',
                      model: '',
                      releaseVersion: '',
                    ),
                l10n,
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.power_settings_new_rounded, size: 18),
                label: Text(l10n?.advRebootBtnPowerOff ?? 'Power Off'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isSupported ? theme.colorScheme.error : null,
                ),
                onPressed: (isSupported && !isBusy)
                    ? () => _confirmPowerOff(context, controller, l10n)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExecutionStatusCard(
    BuildContext context,
    RebootExecutionProgress progress,
    AdvancedRebootController controller,
    AppLocalizations? l10n,
  ) {
    final theme = Theme.of(context);
    final isTerminal = progress.isTerminal;
    final isSuccess = progress.isSucceeded;
    final isError = progress.isFailed || progress.isOutcomeUnknown;

    final cardColor = isSuccess
        ? LuciStatusColors.successBg(context)
        : isError
        ? theme.colorScheme.errorContainer.withValues(alpha: 0.25)
        : theme.colorScheme.primaryContainer.withValues(alpha: 0.25);

    final iconColor = isSuccess
        ? LuciStatusColors.connectedColor(context)
        : isError
        ? theme.colorScheme.error
        : theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _RebootCard(
        color: cardColor,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (progress.isBusy)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  else
                    Icon(
                      isSuccess
                          ? Icons.check_circle_rounded
                          : isError
                          ? Icons.error_outline_rounded
                          : Icons.info_outline_rounded,
                      color: iconColor,
                      size: 22,
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _stateHeading(progress.state, l10n),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: iconColor,
                      ),
                    ),
                  ),
                  if (progress.canCancel)
                    TextButton(
                      onPressed: () => controller.cancel(),
                      child: Text(l10n?.actionCancel ?? 'Cancel'),
                    )
                  else if (isTerminal)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      tooltip: l10n?.actionDismiss ?? 'Dismiss',
                      onPressed: () => controller.resetProgress(),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _resolveProgressMessage(progress, l10n),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (progress.failureReason != null) ...[
                const SizedBox(height: 6),
                Text(
                  l10n?.advRebootDetailsPrefix(progress.failureReason!) ??
                      'Details: ${progress.failureReason}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
              if (progress.isReconnecting) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: progress.pollAttempt / progress.maxPollAttempts,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(
    BuildContext context,
    String text,
    CapabilityStatus status,
  ) {
    Color bg;
    Color fg;

    switch (status) {
      case CapabilityStatus.supported:
        bg = LuciStatusColors.successBg(context);
        fg = LuciStatusColors.connectedColor(context);
        break;
      case CapabilityStatus.unsupported:
        bg = Theme.of(context).colorScheme.surfaceContainerHighest;
        fg = Theme.of(context).colorScheme.onSurfaceVariant;
        break;
      case CapabilityStatus.unknown:
        bg = LuciStatusColors.warningBg(context);
        fg = LuciStatusColors.warningColor(context);
        break;
      case CapabilityStatus.error:
        bg = LuciStatusColors.errorBg(context);
        fg = LuciStatusColors.errorColor(context);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  String _statusLabel(CapabilityStatus status, AppLocalizations? l10n) {
    switch (status) {
      case CapabilityStatus.supported:
        return l10n?.advRebootStatusSupported ?? 'Supported';
      case CapabilityStatus.unsupported:
        return l10n?.advRebootStatusUnsupported ?? 'Unsupported';
      case CapabilityStatus.unknown:
        return l10n?.advRebootStatusUnknown ?? 'Unknown / Unverified';
      case CapabilityStatus.error:
        return l10n?.advRebootStatusError ?? 'Error';
    }
  }

  String _stateHeading(RebootExecutionState state, AppLocalizations? l10n) {
    switch (state) {
      case RebootExecutionState.idle:
        return l10n?.advRebootStateIdle ?? 'Idle';
      case RebootExecutionState.preflight:
        return l10n?.advRebootStatePreflight ?? 'Validating Prerequisites';
      case RebootExecutionState.awaitingConfirmation:
        return l10n?.advRebootStateAwaitingConfirmation ??
            'Awaiting Confirmation';
      case RebootExecutionState.executing:
        return l10n?.advRebootStateExecuting ?? 'Sending Commands';
      case RebootExecutionState.waitingForDisconnect:
        return l10n?.advRebootStateWaitingForDisconnect ?? 'Waiting for Reboot';
      case RebootExecutionState.reconnecting:
        return l10n?.advRebootStateReconnecting ?? 'Reconnecting to Router';
      case RebootExecutionState.verifying:
        return l10n?.advRebootStateVerifying ?? 'Verifying Boot Outcome';
      case RebootExecutionState.succeeded:
        return l10n?.advRebootStateSucceeded ?? 'Operation Complete';
      case RebootExecutionState.failed:
        return l10n?.advRebootStateFailed ?? 'Operation Failed';
      case RebootExecutionState.outcomeUnknown:
        return l10n?.advRebootStateOutcomeUnknown ?? 'Outcome Unknown';
      case RebootExecutionState.cancelled:
        return l10n?.advRebootStateCancelled ?? 'Operation Cancelled';
    }
  }

  String _resolveStandardRebootDescription(
    OperationCapability? cap,
    AppLocalizations? l10n,
  ) {
    if (cap == null || cap.isSupported) {
      return l10n?.advRebootStandardRebootDesc ??
          'Performs a standard OpenWrt operating system restart. Available unconditionally on all reachable routers.';
    }
    return cap.reason;
  }

  String _resolveAltPartitionDescription(
    OperationCapability? cap,
    DeviceBootEnvironment env,
    AppLocalizations? l10n,
  ) {
    if (cap == null) {
      return l10n?.advRebootAltPartitionEvaluating ??
          'Evaluating dual-partition boot capability...';
    }
    if (cap.isSupported &&
        cap.targetIdentifier != null &&
        env.activeSlot != null) {
      return l10n?.advRebootAltPartitionSupportedDesc(
            env.activeSlot!,
            cap.targetIdentifier!,
          ) ??
          cap.reason;
    }
    if (!env.hasDualPartitionLayout) {
      return l10n?.advRebootAltPartitionSingleLayoutDesc ??
          'Single firmware partition layout detected. This router hardware does not support dual-boot switching.';
    }
    if (cap.reason.toLowerCase().contains('missing') ||
        cap.reason.toLowerCase().contains('utilities') ||
        cap.missingOrConflictingEvidence.isNotEmpty) {
      return l10n?.advRebootAltPartitionMissingUtilsDesc ?? cap.reason;
    }
    if (cap.isUnknown || !cap.isSupported) {
      return l10n?.advRebootAltPartitionUnverifiedDesc ?? cap.reason;
    }
    return cap.reason;
  }

  String? _resolveAltPartitionWarning(
    OperationCapability? cap,
    AppLocalizations? l10n,
  ) {
    if (cap == null || cap.warningMessage == null) return null;
    if (cap.isSupported && cap.targetIdentifier != null) {
      return l10n?.advRebootAltPartitionWarning(cap.targetIdentifier!) ??
          cap.warningMessage;
    }
    return cap.warningMessage;
  }

  String _resolvePowerOffDescription(
    OperationCapability? cap,
    DeviceBootEnvironment env,
    AppLocalizations? l10n,
  ) {
    if (cap == null) {
      return l10n?.advRebootPowerOffDesc ??
          'Power off capability evaluated per platform.';
    }
    if (cap.isSupported) {
      return l10n?.advRebootPowerOffSupportedDesc ??
          'Hardware ACPI / PMIC power management is supported. Device will power off completely.';
    }
    if (cap.isUnsupported) {
      final platform = env.boardName.isNotEmpty
          ? env.boardName
          : (env.targetArchitecture.isNotEmpty
                ? env.targetArchitecture
                : 'embedded platform');
      return l10n?.advRebootPowerOffUnsupportedDesc(platform) ?? cap.reason;
    }
    return cap.reason;
  }

  String _resolveProgressMessage(
    RebootExecutionProgress progress,
    AppLocalizations? l10n,
  ) {
    if (l10n == null || progress.message.isEmpty) return progress.message;
    final msg = progress.message;

    if (msg == 'Performing pre-flight safety validations...') {
      return l10n.advRebootProgPreflight;
    }
    if (msg.startsWith('Operation cancelled')) {
      return l10n.advRebootProgCancelled;
    }
    if (msg == 'Dispatching operation commands to router...') {
      return l10n.advRebootProgExecuting;
    }
    if (msg == 'Waiting for device to shut down...') {
      return l10n.advRebootProgWaitingShutdown;
    }
    if (msg == 'Waiting for router to initiate reboot...') {
      return l10n.advRebootProgWaitingReboot;
    }
    if (msg ==
        'Router is rebooting. Waiting for router to come back online...') {
      return l10n.advRebootProgRebooting;
    }
    if (msg.startsWith('Polling for router availability')) {
      return l10n.advRebootProgPolling(
        progress.pollAttempt,
        progress.maxPollAttempts,
      );
    }
    if (msg == 'Router is back online. Verifying boot outcome...') {
      return l10n.advRebootProgVerifying;
    }
    if (msg == 'Router rebooted successfully.') {
      return l10n.advRebootProgRebootSuccess;
    }
    if (msg.startsWith('Device has powered down successfully')) {
      return l10n.advRebootProgPowerOffSuccess;
    }
    if (msg.startsWith(
      'Reboot was initiated, but the router did not become reachable',
    )) {
      return l10n.advRebootProgTimeout;
    }

    return progress.message;
  }

  void _confirmStandardReboot(
    BuildContext context,
    AdvancedRebootController controller,
    AppLocalizations? l10n,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n?.advRebootDialogStandardTitle ?? 'Reboot Router?'),
        content: Text(
          l10n?.advRebootDialogStandardMsg ??
              'This will restart the router operating system. The app will disconnect until the router completes its reboot cycle.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n?.actionCancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              controller.executeOperation(RebootOperationType.standardReboot);
            },
            child: Text(l10n?.dialogRebootConfirm ?? 'Reboot'),
          ),
        ],
      ),
    );
  }

  void _confirmAlternatePartitionReboot(
    BuildContext context,
    AdvancedRebootController controller,
    String targetSlot,
    AppLocalizations? l10n, {
    String? alternateOs,
  }) {
    final String titleText;
    if (alternateOs != null && alternateOs.isNotEmpty) {
      titleText =
          l10n?.advRebootDialogAltTitleWithOs(targetSlot, alternateOs) ??
          'Reboot into Partition Slot $targetSlot ($alternateOs)?';
    } else {
      titleText =
          l10n?.advRebootDialogAltTitleWithoutOs(targetSlot) ??
          'Reboot into Partition Slot $targetSlot?';
    }

    final String targetDesc;
    if (alternateOs != null && alternateOs.isNotEmpty) {
      targetDesc =
          l10n?.advRebootDialogAltDescWithOs(alternateOs, targetSlot) ??
          'You are switching the router to boot into $alternateOs on Slot $targetSlot on next restart.';
    } else {
      targetDesc =
          l10n?.advRebootDialogAltDescWithoutOs(targetSlot) ??
          'You are switching the router to boot from Slot $targetSlot on next restart.';
    }

    final String confirmBtnText =
        l10n?.advRebootDialogAltConfirmBtn(targetSlot) ??
        'Switch to Slot $targetSlot & Reboot';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titleText),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                targetDesc,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                l10n?.advRebootDialogSafetyNotesTitle ??
                    'Important Safety Considerations:',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                '• ${l10n?.advRebootDialogSafetyNote1 ?? 'The alternate partition may contain an older or different OpenWrt build.'}\n'
                '• ${l10n?.advRebootDialogSafetyNote2 ?? 'Network configuration, Wi-Fi passwords, and LAN IP addresses may differ.'}\n'
                '• ${l10n?.advRebootDialogSafetyNote3 ?? 'If the alternate partition uses a different subnet, you must reconnect your device manually.'}',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n?.actionCancel ?? 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: LuciStatusColors.warningColor(ctx),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              controller.executeOperation(
                RebootOperationType.alternatePartitionBoot,
                targetSlot: targetSlot,
              );
            },
            child: Text(confirmBtnText),
          ),
        ],
      ),
    );
  }

  void _confirmPowerOff(
    BuildContext context,
    AdvancedRebootController controller,
    AppLocalizations? l10n,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n?.advRebootDialogPowerOffTitle ?? 'Power Off Router?'),
        content: Text(
          l10n?.advRebootDialogPowerOffMsg ??
              'This will shut down the router hardware. Network and internet access will terminate immediately.\n\n'
                  'Automatic reconnection is NOT possible. You will need physical access to press the power button or cycle power to turn the router back on.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n?.actionCancel ?? 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              controller.executeOperation(RebootOperationType.powerOff);
            },
            child: Text(l10n?.advRebootDialogPowerOffConfirmBtn ?? 'Shut Down'),
          ),
        ],
      ),
    );
  }

  void _showDiagnosticsSheet(
    BuildContext context,
    AdvancedRebootCapabilities caps,
  ) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final sanitizedText = caps.toSanitizedDiagnosticString();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.85,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n?.advRebootDiagnosticsTitle ?? 'Boot Diagnostics',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    tooltip:
                        l10n?.advRebootCopyReportTooltip ??
                        'Copy Diagnostic Report',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: sanitizedText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            l10n?.advRebootCopiedToast ??
                                'Diagnostics copied to clipboard (sanitized)',
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 24),
                    child: SelectionArea(
                      child: Text(
                        sanitizedText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
