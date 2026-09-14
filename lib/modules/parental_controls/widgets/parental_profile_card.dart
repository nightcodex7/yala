// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import '../models/parental_profile.dart';

/// Profile summary card shown in the main parental controls list.
class ParentalProfileCard extends StatelessWidget {
  final ParentalProfile profile;
  final bool hasFirewall;
  final bool hasFileExec;
  final void Function(PauseDuration) onPause;
  final VoidCallback onResume;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onToggleEnabled;

  const ParentalProfileCard({
    super.key,
    required this.profile,
    required this.hasFirewall,
    required this.hasFileExec,
    required this.onPause,
    required this.onResume,
    required this.onEdit,
    required this.onDelete,
    this.onToggleEnabled,
  });

  Color _parseColor(String hex) {
    try {
      final clean = hex.replaceFirst('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return const Color(0xFFF97316);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = _parseColor(profile.color);
    final isPaused = profile.isPaused;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isPaused
              ? Colors.orange.withValues(alpha: 0.4)
              : accentColor.withValues(alpha: 0.2),
          width: isPaused ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                // Icon badge
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      profile.icon,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        profile.macAddresses.isEmpty
                            ? 'Ready • 0 devices assigned'
                            : '${profile.macAddresses.length} device${profile.macAddresses.length != 1 ? 's' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Status chip
                if (!profile.isEnabled)
                  const _BypassedStatusChip()
                else if (profile.macAddresses.isEmpty)
                  const _ReadyStatusChip()
                else if (isPaused)
                  _PauseStatusChip(profile: profile),
                const SizedBox(width: 4),
                // Menu
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                  onSelected: (v) {
                    if (v == 'edit') onEdit();
                    if (v == 'toggle_enabled') onToggleEnabled?.call();
                    if (v == 'delete') onDelete();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit Profile'),
                    ),
                    if (onToggleEnabled != null)
                      PopupMenuItem(
                        value: 'toggle_enabled',
                        child: Text(
                          profile.isEnabled
                              ? 'Bypass Restrictions'
                              : 'Enable Guardrails',
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'Delete',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Feature chips ─────────────────────────────────────────────
          if (profile.hasSchedule ||
              profile.hasTimeLimit ||
              profile.hasContentFilter)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (profile.hasSchedule)
                    _FeatureChip(
                      icon: Icons.schedule_rounded,
                      label: profile.schedule!.blockTimeFormatted,
                      color: hasFileExec ? Colors.blue : Colors.grey,
                      tooltip: hasFileExec
                          ? 'Schedule: block at ${profile.schedule!.blockTimeFormatted}'
                          : 'Schedule requires file.exec access',
                    ),
                  if (profile.hasTimeLimit)
                    _FeatureChip(
                      icon: Icons.timer_outlined,
                      label: '${profile.dailyTimeLimitMinutes}m/day',
                      color: Colors.purple,
                      tooltip:
                          'Daily time limit: ${profile.dailyTimeLimitMinutes} minutes',
                    ),
                  if (profile.hasContentFilter)
                    _FeatureChip(
                      icon: Icons.dns_outlined,
                      label: profile.contentFilter.label.split(' ').first,
                      color: hasFirewall ? Colors.teal : Colors.grey,
                      tooltip: profile.contentFilter.description,
                    ),
                ],
              ),
            ),

          // ── Actions ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                if (isPaused)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onResume,
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Resume Internet'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: _PauseButton(
                      enabled:
                          hasFirewall && profile.hasMacs && profile.isEnabled,
                      tooltip: !hasFirewall
                          ? 'Requires firewall write access'
                          : !profile.hasMacs
                          ? 'Add devices to this profile first'
                          : !profile.isEnabled
                          ? 'Profile is in Bypass mode (Unrestricted)'
                          : null,
                      onPause: onPause,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _BypassedStatusChip extends StatelessWidget {
  const _BypassedStatusChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_open_rounded, size: 12, color: Colors.amber),
          SizedBox(width: 4),
          Text(
            'Bypassed',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.amber,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadyStatusChip extends StatelessWidget {
  const _ReadyStatusChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.access_time_rounded, size: 12, color: Colors.blue),
          SizedBox(width: 4),
          Text(
            'Ready',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays a live countdown chip that ticks every second via an internal Timer.
class _PauseStatusChip extends StatefulWidget {
  final ParentalProfile profile;
  const _PauseStatusChip({required this.profile});

  @override
  State<_PauseStatusChip> createState() => _PauseStatusChipState();
}

class _PauseStatusChipState extends State<_PauseStatusChip> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Only tick if there is an expiry time; indefinite pauses don't need updates.
    if (widget.profile.pauseExpiresAt != null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.profile.timeRemainingInPause;
    final String label;
    if (remaining == null) {
      label = 'Paused';
    } else {
      final h = remaining.inHours;
      final m = remaining.inMinutes % 60;
      final s = remaining.inSeconds % 60;
      if (h > 0) {
        label = '${h}h ${m}m';
      } else if (m > 0) {
        label = '${m}m ${s}s';
      } else {
        label = '${s}s';
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.pause_circle_filled, size: 14, color: Colors.orange),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.orange,
            ),
          ),
        ],
      ),
    );
  }
}

class _PauseButton extends StatelessWidget {
  final bool enabled;
  final String? tooltip;
  final void Function(PauseDuration) onPause;

  const _PauseButton({
    required this.enabled,
    required this.onPause,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: OutlinedButton.icon(
        onPressed: enabled ? () => _showDurationPicker(context) : null,
        icon: const Icon(Icons.pause_circle_outline, size: 18),
        label: const Text('Pause Internet'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.orange,
          side: BorderSide(
            color: Colors.orange.withValues(alpha: enabled ? 0.6 : 0.3),
          ),
        ),
      ),
    );
  }

  void _showDurationPicker(BuildContext context) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      // Use fixed intrinsic size; safe on all screen heights
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag indicator
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 4),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.3,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
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
                  leading: const Icon(
                    Icons.pause_circle_outline,
                    color: Colors.orange,
                  ),
                  title: Text(d.label),
                  onTap: () {
                    Navigator.pop(ctx);
                    onPause(d);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String? tooltip;

  const _FeatureChip({
    required this.icon,
    required this.label,
    required this.color,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Chip(
        avatar: Icon(icon, size: 13, color: color),
        label: Text(label, style: TextStyle(fontSize: 11, color: color)),
        padding: EdgeInsets.zero,
        labelPadding: const EdgeInsets.fromLTRB(2, 0, 6, 0),
        backgroundColor: color.withValues(alpha: 0.09),
        side: BorderSide(color: color.withValues(alpha: 0.2)),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
