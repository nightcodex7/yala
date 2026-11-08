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
import 'package:yet_another_luci_app/models/network_access_policy.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';

/// Interactive card embedded inside the expanded client details in [ClientsScreen].
///
/// Features:
/// - Master Internet Access switch (hierarchical override over IPv4 and IPv6).
/// - Indented IPv4 and IPv6 sub-switches.
/// - Capability gating: IPv6 switch disabled if router lacks IPv6 internet firewall support.
/// - Truthful notices explaining that blocking IPv6 retains local home network communication.
/// - One-shot schedule duration picker (+1h, +2h, +8h, +24h, Custom, Always).
/// - Safety preflight with [SelfDeviceGuard] against self-lockout.
class DeviceNetworkAccessCard extends ConsumerStatefulWidget {
  final Client client;
  final bool isBottomSheet;

  const DeviceNetworkAccessCard({
    super.key,
    required this.client,
    this.isBottomSheet = false,
  });

  /// Opens a modal bottom sheet displaying the network access controls for [client].
  static Future<void> showAsBottomSheet(
    BuildContext context, {
    required Client client,
  }) async {
    final theme = Theme.of(context);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                client.displayName,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                client.ipAddress.isNotEmpty &&
                                        client.ipAddress != 'N/A'
                                    ? client.ipAddress
                                    : client.macAddress,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.of(ctx).pop(),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 16),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: DeviceNetworkAccessCard(
                      client: client,
                      isBottomSheet: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  ConsumerState<DeviceNetworkAccessCard> createState() =>
      _DeviceNetworkAccessCardState();
}

class _DeviceNetworkAccessCardState
    extends ConsumerState<DeviceNetworkAccessCard> {
  bool _isApplying = false;

  String _formatRemaining(DateTime expiry) {
    final diff = expiry.difference(DateTime.now());
    if (diff.isNegative) return '0m';
    if (diff.inHours >= 24) {
      final days = diff.inDays;
      final hours = diff.inHours % 24;
      return '${days}d ${hours}h';
    } else if (diff.inHours >= 1) {
      final hours = diff.inHours;
      final minutes = diff.inMinutes % 60;
      return '${hours}h ${minutes}m';
    } else {
      return '${diff.inMinutes}m';
    }
  }

  Future<void> _applyPolicy(NetworkAccessPolicy policy) async {
    if (_isApplying) return;
    setState(() => _isApplying = true);

    final actionKey = 'policy_${widget.client.macAddress}';
    final isBlocking = policy.isEffectivelyBlocked;

    if (ActionRateLimiter.isRateLimited(
      actionKey,
      cooldown: const Duration(seconds: 2),
    )) {
      final remaining = ActionRateLimiter.getRemainingCooldown(
        actionKey,
        cooldown: const Duration(seconds: 2),
      );
      if (mounted) {
        context.showToastRateLimited(
          '${isBlocking ? "Block" : "Allow"} Network Access',
          remaining,
        );
      }
      if (mounted) setState(() => _isApplying = false);
      return;
    }

    try {
      final appState = ref.read(appStateProvider);
      final success = await appState.setDeviceNetworkAccessPolicy(
        policy: policy,
        context: mounted ? context : null,
      );

      if (!mounted) return;
      if (success) {
        final targetDesc = widget.client.isDumbApClient
            ? '${widget.client.displayName} (Enforced at Main Router)'
            : widget.client.displayName;
        LuciToastManager.safeShowSuccess(
          context,
          isBlocking ? 'Network Access Blocked' : 'Network Access Restored',
          subtitle: 'Target: $targetDesc',
          actionKey: actionKey,
        );
      } else {
        final l10n = AppLocalizations.of(context);
        LuciToastManager.safeShowError(
          context,
          'Failed to update network access policy',
          subtitle:
              '${l10n?.toastErrorCheckPermissionsOrFirewall ?? "Check router firewall permissions or UCI configuration"} (${widget.client.displayName}).',
          actionKey: actionKey,
        );
      }
    } catch (e) {
      if (mounted) {
        LuciToastManager.safeShowError(
          context,
          'Failed to update network access policy',
          subtitle: LuciToastManager.parseErrorReason(e, context),
          actionKey: actionKey,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isApplying = false);
      }
    }
  }

  Future<void> _selectCustomExpiry(NetworkAccessPolicy currentPolicy) async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (pickedTime == null || !mounted) return;

    final targetDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (targetDateTime.isBefore(now)) {
      if (mounted) {
        LuciToastManager.showWarning(
          context,
          'Invalid Expiry Time',
          subtitle: 'Please choose a future date and time.',
        );
      }
      return;
    }

    await _applyPolicy(currentPolicy.copyWith(scheduleExpiry: targetDateTime));
  }

  Widget _buildScheduleChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;

    return ActionChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected
              ? colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      backgroundColor: isSelected
          ? colorScheme.primary.withValues(alpha: 0.15)
          : theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: isDarkMode ? 0.3 : 0.5,
            ),
      side: BorderSide(
        color: isSelected
            ? colorScheme.primary.withValues(alpha: 0.5)
            : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        width: 0.8,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      visualDensity: VisualDensity.compact,
      onPressed: _isApplying ? null : onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final appState = ref.watch(appStateProvider);

    final policy = appState.getDeviceNetworkAccessPolicy(
      widget.client.macAddress,
    );
    final supportsIpv6 =
        appState.capabilities?.supportsIpv6InternetFirewall ?? false;
    final isDarkMode = theme.brightness == Brightness.dark;

    // Status pill determination
    final String statusLabel;
    final Color statusColor;
    if (policy.isIpv4OnlyBlocked) {
      statusLabel = 'IPv4 BLOCKED';
      statusColor = LuciStatusColors.warningColor(context);
    } else if (policy.isIpv6OnlyBlocked) {
      statusLabel = 'IPv6 BLOCKED';
      statusColor = LuciStatusColors.warningColor(context);
    } else if (policy.isEffectivelyBlocked) {
      statusLabel = 'BLOCKED';
      statusColor = colorScheme.error;
    } else {
      statusLabel = 'ALLOWED';
      statusColor = LuciStatusColors.connectedColor(context);
    }

    return Container(
      margin: widget.isBottomSheet
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: isDarkMode ? 0.35 : 0.25,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 16, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n?.clientNetworkAccessTitle ?? 'Network Access',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (_isApplying) ...[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.4),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          if (widget.client.isDumbApClient) ...[
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.indigo.shade700.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.indigo.shade600.withValues(alpha: 0.3),
                  width: 0.8,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.settings_input_antenna_rounded,
                    size: 14,
                    color: isDarkMode
                        ? Colors.indigo.shade200
                        : Colors.indigo.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Connected via ${widget.client.apName ?? "Dumb AP"}. Internet firewall rules are enforced at the Main Router gateway.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        color: isDarkMode
                            ? Colors.indigo.shade200
                            : Colors.indigo.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),

          // Master Internet Access Switch
          Row(
            children: [
              Icon(
                Icons.language_rounded,
                size: 16,
                color: policy.effectiveInternetAccess
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n?.clientInternetAccess ?? 'Internet Access',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      policy.effectiveInternetAccess ? 'Allowed' : 'Blocked',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: policy.effectiveInternetAccess
                            ? LuciStatusColors.connectedColor(context)
                            : colorScheme.error,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: policy.effectiveInternetAccess,
                onChanged: _isApplying
                    ? null
                    : (val) async {
                        if (!val) {
                          // User is turning off internet (blocking)
                          final safe =
                              await SelfDeviceGuard.checkSelfActionGuardrail(
                                context,
                                actionName: 'Block Internet Access',
                                targetMac: widget.client.macAddress,
                                targetIp: widget.client.ipAddress,
                                targetHostname: widget.client.displayName,
                              );
                          if (!safe) return;
                          await _applyPolicy(
                            NetworkAccessPolicy.blocked(
                              widget.client.macAddress,
                            ),
                          );
                        } else {
                          // User is turning on internet (unblocking)
                          await _applyPolicy(
                            NetworkAccessPolicy.unrestricted(
                              widget.client.macAddress,
                            ),
                          );
                        }
                      },
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Sub-controls for IPv4 and IPv6 Internet
          Padding(
            padding: const EdgeInsets.only(left: 14.0),
            child: Column(
              children: [
                // IPv4 Control
                Row(
                  children: [
                    Icon(
                      Icons.trip_origin_rounded,
                      size: 12,
                      color: policy.effectiveIpv4Access
                          ? colorScheme.primary
                          : colorScheme.outline,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n?.clientIpv4Internet ?? 'IPv4 Internet',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: !policy.effectiveInternetAccess
                              ? theme.colorScheme.onSurface.withValues(
                                  alpha: 0.45,
                                )
                              : null,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Switch.adaptive(
                      value: policy.effectiveIpv4Access,
                      onChanged:
                          (!_isApplying && policy.effectiveInternetAccess)
                          ? (val) async {
                              if (!val && !policy.ipv6Access) {
                                final safe =
                                    await SelfDeviceGuard.checkSelfActionGuardrail(
                                      context,
                                      actionName: 'Block IPv4 Internet',
                                      targetMac: widget.client.macAddress,
                                      targetIp: widget.client.ipAddress,
                                      targetHostname: widget.client.displayName,
                                    );
                                if (!safe) return;
                              }
                              await _applyPolicy(
                                policy.copyWith(ipv4Access: val),
                              );
                            }
                          : null,
                    ),
                  ],
                ),

                // IPv6 Control
                Row(
                  children: [
                    Icon(
                      Icons.trip_origin_rounded,
                      size: 12,
                      color: (supportsIpv6 && policy.effectiveIpv6Access)
                          ? colorScheme.primary
                          : colorScheme.outline,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n?.clientIpv6Internet ?? 'IPv6 Internet',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color:
                                  (!supportsIpv6 ||
                                      !policy.effectiveInternetAccess)
                                  ? theme.colorScheme.onSurface.withValues(
                                      alpha: 0.45,
                                    )
                                  : null,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (!supportsIpv6)
                            Text(
                              l10n?.clientIpv6NotSupportedDesc ??
                                  'IPv6 Internet is not configured on this router.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 10,
                                color: colorScheme.outline,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: supportsIpv6 ? policy.effectiveIpv6Access : false,
                      onChanged:
                          (!_isApplying &&
                              policy.effectiveInternetAccess &&
                              supportsIpv6)
                          ? (val) async {
                              if (!val && !policy.ipv4Access) {
                                final safe =
                                    await SelfDeviceGuard.checkSelfActionGuardrail(
                                      context,
                                      actionName: 'Block IPv6 Internet',
                                      targetMac: widget.client.macAddress,
                                      targetIp: widget.client.ipAddress,
                                      targetHostname: widget.client.displayName,
                                    );
                                if (!safe) return;
                              }
                              await _applyPolicy(
                                policy.copyWith(ipv6Access: val),
                              );
                            }
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Explanatory Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.4,
                    )
                  : theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.6,
                    ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 14, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    !policy.effectiveInternetAccess
                        ? (l10n?.clientGlobalBlockedDesc ??
                              'Global internet access is blocked. IPv4 and IPv6 traffic are both blocked.')
                        : (l10n?.clientIpv6InternetDesc ??
                              'Blocking IPv6 Internet stops public IPv6 web access. Local communication on your home network remains active.'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Schedule / Duration selector (Active when device is blocked)
          if (policy.isEffectivelyBlocked) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 14,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  l10n?.clientAccessScheduleTitle ?? 'Access Duration',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  policy.scheduleExpiry != null
                      ? (policy.isExpired
                            ? (l10n?.clientScheduleExpired ??
                                  'Schedule expired')
                            : (l10n?.clientScheduleExpiresIn(
                                    _formatRemaining(policy.scheduleExpiry!),
                                  ) ??
                                  'Expires in ${_formatRemaining(policy.scheduleExpiry!)}'))
                      : (l10n?.clientScheduleAlways ?? 'Always'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: policy.scheduleExpiry != null
                        ? LuciStatusColors.warningColor(context)
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _buildScheduleChip(
                  label: l10n?.clientScheduleAlways ?? 'Always',
                  isSelected: policy.scheduleExpiry == null,
                  onTap: () =>
                      _applyPolicy(policy.copyWith(clearScheduleExpiry: true)),
                ),
                _buildScheduleChip(
                  label: '+1h',
                  isSelected: false,
                  onTap: () => _applyPolicy(
                    policy.copyWith(
                      scheduleExpiry: DateTime.now().add(
                        const Duration(hours: 1),
                      ),
                    ),
                  ),
                ),
                _buildScheduleChip(
                  label: '+2h',
                  isSelected: false,
                  onTap: () => _applyPolicy(
                    policy.copyWith(
                      scheduleExpiry: DateTime.now().add(
                        const Duration(hours: 2),
                      ),
                    ),
                  ),
                ),
                _buildScheduleChip(
                  label: '+8h',
                  isSelected: false,
                  onTap: () => _applyPolicy(
                    policy.copyWith(
                      scheduleExpiry: DateTime.now().add(
                        const Duration(hours: 8),
                      ),
                    ),
                  ),
                ),
                _buildScheduleChip(
                  label: '+24h',
                  isSelected: false,
                  onTap: () => _applyPolicy(
                    policy.copyWith(
                      scheduleExpiry: DateTime.now().add(
                        const Duration(hours: 24),
                      ),
                    ),
                  ),
                ),
                _buildScheduleChip(
                  label: l10n?.clientScheduleCustom ?? 'Custom',
                  isSelected: false,
                  onTap: () => _selectCustomExpiry(policy),
                ),
              ],
            ),
          ],
          if (widget.isBottomSheet) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: policy.isEffectivelyBlocked
                  ? FilledButton.icon(
                      onPressed: _isApplying
                          ? null
                          : () async {
                              await _applyPolicy(
                                NetworkAccessPolicy.unrestricted(
                                  widget.client.macAddress,
                                ),
                              );
                            },
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: Text(
                        l10n?.btnResumeAccess ?? 'Resume Full Access',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: LuciStatusColors.connectedColor(
                          context,
                        ),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    )
                  : (policy.hasAnyRestriction
                        ? FilledButton.icon(
                            onPressed: _isApplying
                                ? null
                                : () async {
                                    await _applyPolicy(
                                      NetworkAccessPolicy.unrestricted(
                                        widget.client.macAddress,
                                      ),
                                    );
                                  },
                            icon: const Icon(
                              Icons.check_circle_outline,
                              size: 18,
                            ),
                            label: const Text(
                              'Restore Full Access',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          )
                        : OutlinedButton.icon(
                            onPressed: _isApplying
                                ? null
                                : () async {
                                    final safe =
                                        await SelfDeviceGuard.checkSelfActionGuardrail(
                                          context,
                                          actionName: 'Block Internet Access',
                                          targetMac: widget.client.macAddress,
                                          targetIp: widget.client.ipAddress,
                                          targetHostname:
                                              widget.client.displayName,
                                        );
                                    if (!safe) return;
                                    await _applyPolicy(
                                      NetworkAccessPolicy.blocked(
                                        widget.client.macAddress,
                                      ),
                                    );
                                  },
                            icon: const Icon(Icons.pause_rounded, size: 18),
                            label: Text(
                              l10n?.btnPauseAccess ?? 'Pause Access',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colorScheme.error,
                              side: BorderSide(
                                color: colorScheme.error.withValues(alpha: 0.6),
                                width: 1.0,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          )),
            ),
          ],
        ],
      ),
    );
  }
}
