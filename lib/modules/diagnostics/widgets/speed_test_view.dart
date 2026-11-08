// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../design/luci_design_system.dart';
import '../../../l10n/app_localizations.dart';
import '../../../main.dart';
import '../../../widgets/rpc_permissions_dialog.dart';
import '../controllers/speed_test_controller.dart';
import '../models/speed_test_models.dart';

class SpeedTestView extends ConsumerWidget {
  const SpeedTestView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(speedTestControllerProvider);
    final controller = ref.read(speedTestControllerProvider.notifier);
    final selectedRouter = ref.watch(
      appStateProvider.select((s) => s.selectedRouter),
    );
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: LuciSpacing.md,
        vertical: LuciSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Vantage Point & Transport Header Banner
          _buildVantageBanner(
            context,
            state,
            l10n,
            currentRouterName: selectedRouter?.displayName,
          ),
          const SizedBox(height: LuciSpacing.md),

          // 2. Primary Metrics Cards (Download & Upload)
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  context,
                  title: l10n?.speedTestMetricDownload ?? 'DOWNLOAD',
                  value: state.result?.downloadSpeedMbps != null
                      ? state.result!.downloadSpeedMbps!.toStringAsFixed(1)
                      : (state.isRunning &&
                                state.progress?.stage ==
                                    SpeedTestStage.measuringDownload &&
                                state.progress?.currentSpeedMbps != null
                            ? state.progress!.currentSpeedMbps!.toStringAsFixed(
                                1,
                              )
                            : '--'),
                  unit: 'Mbps',
                  icon: Icons.arrow_downward_rounded,
                  accentColor: Colors.blue.shade600,
                  isActive:
                      state.progress?.stage == SpeedTestStage.measuringDownload,
                ),
              ),
              const SizedBox(width: LuciSpacing.sm),
              Expanded(
                child: _buildMetricCard(
                  context,
                  title: l10n?.speedTestMetricUpload ?? 'UPLOAD',
                  value: state.result?.uploadSpeedMbps != null
                      ? state.result!.uploadSpeedMbps!.toStringAsFixed(1)
                      : (state.isRunning &&
                                state.progress?.stage ==
                                    SpeedTestStage.measuringUpload &&
                                state.progress?.currentSpeedMbps != null
                            ? state.progress!.currentSpeedMbps!.toStringAsFixed(
                                1,
                              )
                            : '--'),
                  unit: 'Mbps',
                  icon: Icons.arrow_upward_rounded,
                  accentColor: Colors.purple.shade600,
                  isActive:
                      state.progress?.stage == SpeedTestStage.measuringUpload,
                ),
              ),
            ],
          ),
          const SizedBox(height: LuciSpacing.sm),

          // 3. Secondary Metrics Row (Latency, Jitter, Loaded Latency)
          Row(
            children: [
              Expanded(
                child: _buildSmallMetricCard(
                  context,
                  title: l10n?.speedTestMetricIdlePing ?? 'Idle Ping',
                  value: state.result?.idleLatencyMs != null
                      ? '${state.result!.idleLatencyMs!.toStringAsFixed(1)} ms'
                      : (state.progress?.currentLatencyMs != null
                            ? '${state.progress!.currentLatencyMs!.toStringAsFixed(1)} ms'
                            : '--'),
                  icon: Icons.timer_outlined,
                ),
              ),
              const SizedBox(width: LuciSpacing.xs),
              Expanded(
                child: _buildSmallMetricCard(
                  context,
                  title: l10n?.speedTestMetricJitter ?? 'Jitter',
                  value: state.result?.jitterMs != null
                      ? '${state.result!.jitterMs!.toStringAsFixed(1)} ms'
                      : (state.progress?.currentJitterMs != null
                            ? '${state.progress!.currentJitterMs!.toStringAsFixed(1)} ms'
                            : '--'),
                  icon: Icons.compare_arrows_rounded,
                ),
              ),
              const SizedBox(width: LuciSpacing.xs),
              Expanded(
                child: _buildSmallMetricCard(
                  context,
                  title: l10n?.speedTestMetricLoadedPing ?? 'Loaded Ping',
                  value: state.result?.loadedLatencyMs != null
                      ? '${state.result!.loadedLatencyMs!.toStringAsFixed(1)} ms'
                      : 'N/A',
                  icon: Icons.speed_rounded,
                  tooltip:
                      l10n?.speedTestLoadedPingTooltip ??
                      'Latency measured during active network load',
                ),
              ),
            ],
          ),
          const SizedBox(height: LuciSpacing.md),

          // 4. Progress and Status Card
          if (state.isRunning || state.progress != null) ...[
            Container(
              padding: const EdgeInsets.all(LuciSpacing.md),
              decoration: LuciCardStyles.standardCard(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _getLocalizedStatus(
                            state.progress?.statusMessage,
                            l10n,
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (state.isRunning) ...[
                        const SizedBox(width: LuciSpacing.sm),
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: LuciSpacing.sm),
                  LinearProgressIndicator(
                    value: state.isRunning
                        ? (state.progress?.progressPercent ?? 0.0)
                        : (state.result != null ? 1.0 : 0.0),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: LuciSpacing.md),
          ],

          // 5. Error Banner if test failed
          if (state.errorMessage != null) ...[
            Builder(
              builder: (ctx) {
                final isPermissionError =
                    state.result?.isRpcPermissionError == true ||
                    (state.errorMessage?.contains(
                          'RPC execution permissions',
                        ) ??
                        false);
                return Container(
                  padding: const EdgeInsets.all(LuciSpacing.md),
                  decoration: BoxDecoration(
                    color: isPermissionError
                        ? colorScheme.errorContainer.withValues(alpha: 0.9)
                        : colorScheme.errorContainer.withValues(alpha: 0.8),
                    borderRadius: LuciCardStyles.standardRadius,
                    border: isPermissionError
                        ? Border.all(
                            color: colorScheme.error.withValues(alpha: 0.4),
                          )
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            isPermissionError
                                ? Icons.admin_panel_settings_outlined
                                : Icons.error_outline_rounded,
                            color: colorScheme.onErrorContainer,
                            size: 20,
                          ),
                          const SizedBox(width: LuciSpacing.sm),
                          Expanded(
                            child: Text(
                              isPermissionError
                                  ? (l10n?.speedTestRpcPermissionRequired ??
                                        state.errorMessage!)
                                  : state.errorMessage!,
                              style: TextStyle(
                                color: colorScheme.onErrorContainer,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (isPermissionError) ...[
                        const SizedBox(height: LuciSpacing.sm),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.tonalIcon(
                            onPressed: () => RpcPermissionsDialog.show(
                              context,
                              actionName: 'Router Speed Test',
                            ),
                            icon: const Icon(Icons.build_rounded, size: 16),
                            label: Text(
                              l10n?.speedTestBtnOpenRpcSetup ??
                                  'Open RPC Setup',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: LuciSpacing.md),
          ],

          // 6. Action Button (Start / Cancel)
          if (state.isRunning)
            OutlinedButton.icon(
              onPressed: () => controller.cancelTest(),
              icon: const Icon(Icons.cancel_rounded),
              label: Text(l10n?.speedTestBtnCancel ?? 'Cancel Speed Test'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.error,
                side: BorderSide(color: colorScheme.error),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: LuciCardStyles.standardRadius,
                ),
              ),
            )
          else
            FilledButton.icon(
              onPressed: () => controller.startTest(),
              icon: const Icon(Icons.speed_rounded),
              label: Text(
                state.result != null
                    ? (l10n?.speedTestBtnRerun ?? 'Run Router Speed Test Again')
                    : (l10n?.speedTestBtnStart ?? 'Start Router Speed Test'),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: LuciCardStyles.standardRadius,
                ),
              ),
            ),
          const SizedBox(height: LuciSpacing.md),

          // 7. Context & Methodology Disclaimer
          Container(
            padding: const EdgeInsets.all(LuciSpacing.md),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: LuciCardStyles.standardRadius,
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: LuciSpacing.xs),
                    Text(
                      l10n?.speedTestContextTitle ??
                          'Measurement Context & Limitations',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: LuciSpacing.xs),
                Text(
                  '• ${l10n?.speedTestContextBullet1 ?? 'Vantage point: OpenWrt Router WAN interface.'}\n'
                  '• ${l10n?.speedTestContextBullet2 ?? 'Server endpoint: Cloudflare Anycast (speed.cloudflare.com).'}\n'
                  '• ${l10n?.speedTestContextBullet3 ?? 'Measures direct throughput and latency from the router WAN interface to Cloudflare Anycast.'}\n'
                  '• ${l10n?.speedTestContextBullet4 ?? 'Completely eliminates device Wi-Fi or cellular radio interference.'}',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (state.result?.timestamp != null) ...[
                  const Divider(height: 16),
                  Text(
                    l10n?.speedTestLastTested(
                          state.result!.timestamp
                              .toLocal()
                              .toString()
                              .split('.')
                              .first,
                        ) ??
                        'Last tested: ${state.result!.timestamp.toLocal().toString().split('.').first}',
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVantageBanner(
    BuildContext context,
    SpeedTestState state,
    AppLocalizations? l10n, {
    String? currentRouterName,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fallbackTransport =
        currentRouterName != null && currentRouterName.isNotEmpty
        ? 'Router WAN ($currentRouterName)'
        : 'Router WAN';
    final transport = state.result?.connectionType ?? fallbackTransport;

    return Container(
      padding: const EdgeInsets.all(LuciSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: LuciCardStyles.standardRadius,
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.router_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: LuciSpacing.sm),
              Expanded(
                child: Text(
                  l10n?.speedTestVantageTitle ??
                      'Router Internet Speed Test (WAN)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: LuciSpacing.sm + 2),
          _buildBannerBullet(
            context,
            l10n?.speedTestVantagePoint(transport) ??
                'Vantage Point: Direct OpenWrt router WAN interface ($transport)',
          ),
          const SizedBox(height: 5),
          _buildBannerBullet(
            context,
            l10n?.speedTestEndpoint ??
                'Endpoint: Cloudflare Anycast edge (speed.cloudflare.com)',
          ),
          const SizedBox(height: 5),
          _buildBannerBullet(
            context,
            l10n?.speedTestParamMethodology ??
                'Methodology: Multi-stage steady-state buffer warmup & sustained throughput measurement via LuCI RPC',
          ),
          const SizedBox(height: 5),
          _buildBannerBullet(
            context,
            l10n?.speedTestParamIsolation ??
                'Radio Isolation: Completely eliminates client device Wi-Fi or cellular skew',
          ),
        ],
      ),
    );
  }

  String _getLocalizedStatus(String? raw, AppLocalizations? l10n) {
    if (raw == null) return l10n?.speedTestPreparing ?? 'Preparing test...';
    if (raw.contains('completed successfully')) {
      return l10n?.speedTestSuccess ??
          'Router speed test completed successfully';
    }
    if (raw.contains('cancelled by user')) {
      return l10n?.speedTestCancelled ?? 'Speed test cancelled by user';
    }
    return raw;
  }

  Widget _buildBannerBullet(BuildContext context, String text) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5, right: 8),
          child: Icon(Icons.circle, size: 5, color: colorScheme.primary),
        ),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: colorScheme.onPrimaryContainer.withValues(alpha: 0.9),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color accentColor,
    required bool isActive,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(LuciSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: LuciCardStyles.standardRadius,
        border: Border.all(
          color: isActive
              ? accentColor
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: isActive ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 0.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Icon(icon, size: 18, color: accentColor),
            ],
          ),
          const SizedBox(height: LuciSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: value == '--'
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallMetricCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    String? tooltip,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final card = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LuciSpacing.sm,
        vertical: LuciSpacing.sm,
      ),
      decoration: LuciCardStyles.standardCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip, child: card);
    }
    return card;
  }
}
