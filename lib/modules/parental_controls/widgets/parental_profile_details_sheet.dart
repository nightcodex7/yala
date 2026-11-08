// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/client.dart';
import '../models/parental_profile.dart';
import '../controllers/parental_controls_controller.dart';
import 'parental_profile_avatar.dart';

const Color _emerald = Color(0xFF10B981);

/// Modal bottom sheet displaying detailed status, active parental controls,
/// and assigned devices with real-time bandwidth metrics.
class ParentalProfileDetailsSheet extends ConsumerStatefulWidget {
  final ParentalProfile initialProfile;
  final bool hasFirewall;
  final bool hasFileExec;
  final void Function(PauseDuration) onPause;
  final VoidCallback onResume;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onToggleEnabled;

  const ParentalProfileDetailsSheet({
    super.key,
    required this.initialProfile,
    required this.hasFirewall,
    required this.hasFileExec,
    required this.onPause,
    required this.onResume,
    required this.onEdit,
    required this.onDelete,
    this.onToggleEnabled,
  });

  static Future<void> show({
    required BuildContext context,
    required ParentalProfile profile,
    required bool hasFirewall,
    required bool hasFileExec,
    required void Function(PauseDuration) onPause,
    required VoidCallback onResume,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
    VoidCallback? onToggleEnabled,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ParentalProfileDetailsSheet(
        initialProfile: profile,
        hasFirewall: hasFirewall,
        hasFileExec: hasFileExec,
        onPause: onPause,
        onResume: onResume,
        onEdit: onEdit,
        onDelete: onDelete,
        onToggleEnabled: onToggleEnabled,
      ),
    );
  }

  @override
  ConsumerState<ParentalProfileDetailsSheet> createState() =>
      _ParentalProfileDetailsSheetState();
}

class _ParentalProfileDetailsSheetState
    extends ConsumerState<ParentalProfileDetailsSheet> {
  final _controller = ParentalControlsController.instance;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final appState = ref.watch(appStateProvider);
    const speedUnit = 'bytes';

    // Fetch the freshest instance of this profile from the store
    final profile =
        _controller.store.getProfile(widget.initialProfile.id) ??
        widget.initialProfile;

    final accent = ParentalProfileAvatar.parseColor(profile.color);
    final isPaused = profile.isPaused;
    final isBypassed = !profile.isEnabled;
    final isBedtime =
        profile.hasSchedule && profile.schedule!.isTimeInBlockWindow();
    final minutesUsed = _controller.store.getProfileDailyMinutesUsed(profile);
    final isQuotaReached = profile.isDailyLimitReached(minutesUsed);
    final isOperationPending = _controller.isProfileOperationPending(
      profile.id,
    );

    // Filter assigned clients from appState
    final assignedClients = <Client>[];
    final offlineMacs = <String>[];

    for (final rawMac in profile.macAddresses) {
      final clean = rawMac.trim().toLowerCase();
      final match = appState.clients.firstWhere(
        (c) => c.macAddress.trim().toLowerCase() == clean,
        orElse: () => Client(
          ipAddress: '',
          macAddress: rawMac,
          hostname: rawMac,
          isConnected: false,
        ),
      );
      if (match.ipAddress.isNotEmpty) {
        assignedClients.add(match);
      } else {
        offlineMacs.add(rawMac);
      }
    }

    // Calculate aggregated bandwidth
    double totalRxSpeed = 0;
    double totalTxSpeed = 0;
    for (final c in assignedClients) {
      totalRxSpeed += c.rxSpeed ?? 0;
      totalTxSpeed += c.txSpeed ?? 0;
    }

    final formattedTotalDown = Client.formatSpeed(
      totalTxSpeed,
      speedUnit: speedUnit,
    );
    final formattedTotalUp = Client.formatSpeed(
      totalRxSpeed,
      speedUnit: speedUnit,
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.50,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Column(
          children: [
            // ── Operation In-Progress Progress Bar ──────────────────────────
            if (isOperationPending) const LinearProgressIndicator(minHeight: 3),

            // ── Header ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
              child: Row(
                children: [
                  ParentalProfileAvatar(
                    icon: profile.icon,
                    colorHex: profile.color,
                    size: 56,
                    isPaused: isPaused,
                    isBypassed: isBypassed,
                    isBedtime: isBedtime,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        _buildStatusPill(
                          theme: theme,
                          l10n: l10n,
                          isPaused: isPaused,
                          isBypassed: isBypassed,
                          isBedtime: isBedtime,
                          hasMacs: profile.hasMacs,
                          remaining: profile.timeRemainingInPause,
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: l10n?.parentalProfileBtnEdit ?? 'Edit Profile',
                    onPressed: isOperationPending
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            widget.onEdit();
                          },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // ── Scrollable Body ────────────────────────────────────────────
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                children: [
                  // ── Live Status Card ──────────────────────────────────────
                  _buildLiveStatusCard(
                    theme: theme,
                    l10n: l10n,
                    accent: accent,
                    profile: profile,
                    isPaused: isPaused,
                    isBypassed: isBypassed,
                    isBedtime: isBedtime,
                    isQuotaReached: isQuotaReached,
                    minutesUsed: minutesUsed,
                    isOperationPending: isOperationPending,
                  ),
                  const SizedBox(height: 16),

                  // ── Applied Parental Controls Overview ───────────────────
                  _buildSectionHeader(
                    theme: theme,
                    title: 'Active Controls',
                    icon: Icons.tune_rounded,
                  ),
                  const SizedBox(height: 8),
                  _buildAppliedControlsGrid(
                    theme: theme,
                    l10n: l10n,
                    profile: profile,
                    accent: accent,
                    isBedtime: isBedtime,
                    isQuotaReached: isQuotaReached,
                    minutesUsed: minutesUsed,
                  ),
                  const SizedBox(height: 20),

                  // ── Assigned Devices & Live Bandwidth ────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionHeader(
                        theme: theme,
                        title:
                            'Assigned Devices (${profile.macAddresses.length})',
                        icon: Icons.devices_rounded,
                      ),
                      if (assignedClients.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '↓ $formattedTotalDown  ↑ $formattedTotalUp',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (profile.macAddresses.isEmpty)
                    _buildNoDevicesCard(theme: theme, l10n: l10n)
                  else ...[
                    ...assignedClients.map(
                      (client) => _buildDeviceCard(
                        theme: theme,
                        client: client,
                        speedUnit: speedUnit,
                        isOnline: true,
                      ),
                    ),
                    ...offlineMacs.map(
                      (mac) => _buildOfflineDeviceCard(
                        theme: theme,
                        macAddress: mac,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Footer Quick Actions ───────────────────────────────────────
            _buildFooterActions(
              theme: theme,
              l10n: l10n,
              profile: profile,
              isPaused: isPaused,
              isOperationPending: isOperationPending,
            ),
          ],
        );
      },
    );
  }

  // ── Helper Widgets ────────────────────────────────────────────────────────

  Widget _buildSectionHeader({
    required ThemeData theme,
    required String title,
    required IconData icon,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusPill({
    required ThemeData theme,
    required AppLocalizations? l10n,
    required bool isPaused,
    required bool isBypassed,
    required bool isBedtime,
    required bool hasMacs,
    required Duration? remaining,
  }) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    if (isBypassed) {
      bg = theme.colorScheme.surfaceContainerHighest;
      fg = theme.colorScheme.onSurfaceVariant;
      label = 'Bypassed (Unrestricted)';
      icon = Icons.shield_outlined;
    } else if (!hasMacs) {
      bg = theme.colorScheme.surfaceContainerHighest;
      fg = theme.colorScheme.onSurfaceVariant;
      label = 'Ready • 0 Devices';
      icon = Icons.info_outline;
    } else if (isPaused) {
      bg = LuciStatusColors.warningBg(context);
      fg = LuciStatusColors.warningText(context);
      if (remaining != null) {
        final h = remaining.inHours;
        final m = remaining.inMinutes % 60;
        final s = remaining.inSeconds % 60;
        final timeStr = h > 0
            ? '${h}h ${m}m left'
            : m > 0
            ? '${m}m ${s}s left'
            : '${s}s left';
        label = 'Paused ($timeStr)';
      } else {
        label = l10n?.parentalProfilePaused ?? 'Paused';
      }
      icon = Icons.pause_circle_filled;
    } else if (isBedtime) {
      bg = Colors.indigo.withValues(alpha: 0.12);
      fg = Colors.indigo;
      label = l10n?.parentalProfileBedtimeLabel ?? 'Bedtime Active';
      icon = Icons.bedtime_rounded;
    } else {
      bg = _emerald.withValues(alpha: 0.12);
      fg = _emerald;
      label = 'Protection Active';
      icon = Icons.verified_user_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveStatusCard({
    required ThemeData theme,
    required AppLocalizations? l10n,
    required Color accent,
    required ParentalProfile profile,
    required bool isPaused,
    required bool isBypassed,
    required bool isBedtime,
    required bool isQuotaReached,
    required int minutesUsed,
    required bool isOperationPending,
  }) {
    if (isPaused) {
      final expiry = profile.pauseExpiresAt;
      final expiryFormatted = expiry != null
          ? 'Auto-resumes at ${expiry.toLocal().hour.toString().padLeft(2, '0')}:${expiry.toLocal().minute.toString().padLeft(2, '0')}'
          : 'Internet is paused indefinitely.';

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: LuciStatusColors.warningBg(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: LuciStatusColors.warningBorder(context),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.pause_circle_filled_rounded,
                  color: LuciStatusColors.warningColor(context),
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Internet Paused',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: LuciStatusColors.warningText(context),
                        ),
                      ),
                      Text(
                        expiryFormatted,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: LuciStatusColors.warningText(
                            context,
                          ).withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isOperationPending ? null : widget.onResume,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                  l10n?.parentalProfileResumeInternet ?? 'Resume Internet Now',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _emerald,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (isBedtime) {
      final sched = profile.schedule!;
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.indigo.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.indigo.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.bedtime_rounded, color: Colors.indigo, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bedtime Restriction In Effect',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Internet access blocks automatically until ${sched.resumeTimeFormatted} (${sched.activeDaysLabel}).',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (isQuotaReached) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.deepOrange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.deepOrange.withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.hourglass_bottom_rounded,
              color: Colors.deepOrange,
              size: 26,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Daily Usage Quota Reached',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.deepOrange,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Total limit of ${_formatMinutes(profile.dailyTimeLimitMinutes ?? 0)} has been used today. Access automatically resets tomorrow.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    String normalSubtitle;
    if (isBypassed) {
      normalSubtitle =
          'Rules are paused. Devices have full unrestricted access.';
    } else if (profile.hasSchedule && profile.hasContentFilter) {
      normalSubtitle =
          'Bedtime schedule set (${profile.schedule!.blockTimeFormatted} → ${profile.schedule!.resumeTimeFormatted}) · DNS filter actively operating.';
    } else if (profile.hasSchedule) {
      normalSubtitle =
          'Bedtime schedule active: ${profile.schedule!.blockTimeFormatted} → ${profile.schedule!.resumeTimeFormatted} (${profile.schedule!.activeDaysLabel}).';
    } else if (profile.hasContentFilter) {
      normalSubtitle =
          'DNS content filter (${profile.contentFilter.label}) actively protecting devices.';
    } else {
      normalSubtitle = 'Protections and policies active on the router.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_rounded, color: accent, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isBypassed
                      ? 'Guardrails Temporarily Bypassed'
                      : 'Protections Fully Enforced',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  normalSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppliedControlsGrid({
    required ThemeData theme,
    required AppLocalizations? l10n,
    required ParentalProfile profile,
    required Color accent,
    required bool isBedtime,
    required bool isQuotaReached,
    required int minutesUsed,
  }) {
    final dnsLabel = profile.contentFilter.label;
    final dnsIps = profile.customDnsServers.isNotEmpty
        ? profile.customDnsServers.join(', ')
        : profile.contentFilter.primaryServers.join(', ');

    final scheduleText = profile.hasSchedule && profile.schedule != null
        ? '${profile.schedule!.blockTimeFormatted} → ${profile.schedule!.resumeTimeFormatted}'
        : 'No schedule configured';

    final daysText = profile.hasSchedule && profile.schedule != null
        ? profile.schedule!.activeDaysLabel
        : 'Disabled';

    final timeLimitText = profile.hasTimeLimit
        ? _formatMinutes(profile.dailyTimeLimitMinutes ?? 0)
        : 'No daily time limit';

    return Column(
      children: [
        // Content filter card
        _buildControlInfoTile(
          theme: theme,
          icon: Icons.dns_rounded,
          iconColor: Colors.blue,
          title: 'DNS Content Filter',
          subtitle: dnsLabel,
          detail: dnsIps.isNotEmpty ? dnsIps : null,
          tag: profile.hasContentFilter ? 'Enforced' : 'Off',
          tagColor: profile.hasContentFilter ? _emerald : Colors.grey,
        ),
        const SizedBox(height: 8),

        // Bedtime schedule card
        _buildControlInfoTile(
          theme: theme,
          icon: Icons.bedtime_outlined,
          iconColor: Colors.indigo,
          title: 'Bedtime Schedule',
          subtitle: scheduleText,
          detail: profile.hasSchedule ? daysText : null,
          tag: profile.hasSchedule
              ? (isBedtime ? 'Blocking Now' : 'Scheduled')
              : 'Off',
          tagColor: profile.hasSchedule
              ? (isBedtime ? Colors.deepPurple : Colors.indigo)
              : Colors.grey,
        ),
        const SizedBox(height: 8),

        // Daily limit card
        _buildControlInfoTile(
          theme: theme,
          icon: Icons.timer_outlined,
          iconColor: Colors.orange,
          title: 'Daily Usage Quota',
          subtitle: timeLimitText,
          detail: profile.hasTimeLimit
              ? 'Used today: ${_formatMinutes(minutesUsed)}'
              : null,
          tag: isQuotaReached
              ? 'Quota Reached'
              : (profile.hasTimeLimit ? 'Active' : 'Off'),
          tagColor: isQuotaReached
              ? Colors.red
              : (profile.hasTimeLimit ? Colors.orange : Colors.grey),
        ),
      ],
    );
  }

  Widget _buildControlInfoTile({
    required ThemeData theme,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    String? detail,
    required String tag,
    required Color tagColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (detail != null && detail.isNotEmpty)
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: tagColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              tag,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: tagColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard({
    required ThemeData theme,
    required Client client,
    required String speedUnit,
    required bool isOnline,
  }) {
    final downSpeed =
        client.formattedDownloadSpeedWithUnit(speedUnit) ?? '0 B/s';
    final upSpeed = client.formattedUploadSpeedWithUnit(speedUnit) ?? '0 B/s';

    final displayName = client.hostname.isNotEmpty && client.hostname != 'N/A'
        ? client.hostname
        : client.vendor != null && client.vendor!.isNotEmpty
        ? client.vendor!
        : client.macAddress;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          // Device Icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.smartphone_rounded,
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),

          // Hostname & MAC
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: _emerald,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${client.ipAddress} • ${client.macAddress.toUpperCase()}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Live Bandwidth Speeds
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.arrow_downward_rounded,
                    size: 13,
                    color: _emerald,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    downSpeed,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _emerald,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.arrow_upward_rounded,
                    size: 13,
                    color: Colors.blue,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    upSpeed,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineDeviceCard({
    required ThemeData theme,
    required String macAddress,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.25,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.devices_other_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  macAddress.toUpperCase(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Not currently active on network',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Offline',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoDevicesCard({
    required ThemeData theme,
    required AppLocalizations? l10n,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.devices_other_rounded,
              size: 32,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              'No Devices Assigned',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Assign child devices to start enforcing DNS filtering and time restrictions.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () {
                Navigator.pop(context);
                widget.onEdit();
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Assign Devices'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooterActions({
    required ThemeData theme,
    required AppLocalizations? l10n,
    required ParentalProfile profile,
    required bool isPaused,
    required bool isOperationPending,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          if (widget.onToggleEnabled != null)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isOperationPending ? null : widget.onToggleEnabled,
                icon: Icon(
                  profile.isEnabled
                      ? Icons.shield_outlined
                      : Icons.shield_rounded,
                  size: 18,
                ),
                label: Text(profile.isEnabled ? 'Bypass' : 'Enable'),
              ),
            ),
          if (widget.onToggleEnabled != null) const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: isPaused
                ? FilledButton.icon(
                    onPressed: isOperationPending ? null : widget.onResume,
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: Text(
                      l10n?.parentalProfileResumeInternet ?? 'Resume Internet',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _emerald,
                      foregroundColor: Colors.white,
                    ),
                  )
                : FilledButton.icon(
                    onPressed:
                        (isOperationPending ||
                            !widget.hasFirewall ||
                            !profile.hasMacs ||
                            !profile.isEnabled)
                        ? null
                        : () => _showDurationPicker(context),
                    icon: const Icon(Icons.pause_circle_outline, size: 20),
                    label: Text(
                      l10n?.parentalProfilePauseInternet ?? 'Pause Internet',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: LuciStatusColors.warningColor(context),
                      foregroundColor: Colors.black,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _showDurationPicker(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Pause internet for how long?',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(height: 8),
              ...PauseDuration.values.map(
                (d) => ListTile(
                  leading: Icon(
                    Icons.pause_circle_outline,
                    color: LuciStatusColors.warningColor(context),
                  ),
                  title: Text(_getPauseDurationLabel(l10n, d)),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onPause(d);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getPauseDurationLabel(AppLocalizations? l10n, PauseDuration d) {
    switch (d) {
      case PauseDuration.fifteenMinutes:
        return '15 Minutes';
      case PauseDuration.thirtyMinutes:
        return l10n?.parentalProfilePause30m ?? d.label;
      case PauseDuration.oneHour:
        return l10n?.parentalProfilePause1h ?? d.label;
      case PauseDuration.untilTomorrow:
        return l10n?.parentalProfilePauseBedtime ?? d.label;
      case PauseDuration.indefinite:
        return l10n?.parentalProfilePauseIndefinitely ?? d.label;
    }
  }

  String _formatMinutes(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m per day';
    if (h > 0) return '${h}h per day';
    return '${m}m per day';
  }
}
