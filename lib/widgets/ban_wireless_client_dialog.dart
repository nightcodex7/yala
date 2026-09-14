// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';

/// Context-aware dialog for Banning a wireless client with flexible time customization,
/// dynamic Date & Time pickers, preset durations, and self-device safety guardrails.
class BanWirelessClientDialog extends StatefulWidget {
  const BanWirelessClientDialog({
    super.key,
    required this.macAddress,
    required this.displayName,
    this.ipAddress,
    this.ssid,
    this.iface,
    this.isAlreadyBanned = false,
    required this.onBanConfirmed,
    this.onUnbanConfirmed,
  });

  final String macAddress;
  final String displayName;
  final String? ipAddress;
  final String? ssid;
  final String? iface;
  final bool isAlreadyBanned;

  /// Callback executed when ban is confirmed with duration in seconds
  final Future<void> Function(int banTimeSeconds) onBanConfirmed;

  /// Optional callback executed if user chooses to unban from dialog
  final Future<void> Function()? onUnbanConfirmed;

  @override
  State<BanWirelessClientDialog> createState() =>
      _BanWirelessClientDialogState();
}

class _BanWirelessClientDialogState extends State<BanWirelessClientDialog> {
  // Preset options in seconds
  static const List<Map<String, dynamic>> _presetOptions = [
    {'label': '5 Mins', 'seconds': 300},
    {'label': '15 Mins', 'seconds': 900},
    {'label': '1 Hour', 'seconds': 3600},
    {'label': '24 Hours', 'seconds': 86400},
    {'label': 'Custom Date & Time', 'seconds': -1},
  ];

  int _selectedPresetSeconds = 300; // Default 5 minutes
  DateTime _customEndDateTime = DateTime.now().add(const Duration(minutes: 30));
  bool _isSubmitting = false;
  bool _isSelfDevice = false;

  @override
  void initState() {
    super.initState();
    _checkSelfDeviceStatus();
  }

  Future<void> _checkSelfDeviceStatus() async {
    final isSelf = await SelfDeviceGuard.isSelfDevice(
      widget.macAddress,
      widget.ipAddress,
    );
    if (mounted) {
      setState(() => _isSelfDevice = isSelf);
    }
  }

  int get _effectiveBanSeconds {
    if (_selectedPresetSeconds != -1) {
      return _selectedPresetSeconds;
    }
    final now = DateTime.now();
    final diff = _customEndDateTime.difference(now).inSeconds;
    return diff > 0 ? diff : 0;
  }

  bool get _isValidDuration => _effectiveBanSeconds >= 30;

  String _formatDurationString(int seconds) {
    if (seconds <= 0) return 'Invalid duration';
    final duration = Duration(seconds: seconds);
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;
    final secs = duration.inSeconds % 60;

    final parts = <String>[];
    if (days > 0) parts.add('$days day${days > 1 ? "s" : ""}');
    if (hours > 0) parts.add('$hours hr${hours > 1 ? "s" : ""}');
    if (minutes > 0) parts.add('$minutes min${minutes > 1 ? "s" : ""}');
    if (parts.isEmpty) parts.add('$secs sec${secs > 1 ? "s" : ""}');

    return parts.join(' ');
  }

  String _formatDateTime(DateTime dt, {bool includeYear = true}) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    final weekday = weekdays[dt.weekday - 1];
    final month = months[dt.month - 1];
    final day = dt.day.toString().padLeft(2, '0');
    final hour12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final hourStr = hour12.toString().padLeft(2, '0');
    final minuteStr = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';

    if (includeYear) {
      return '$weekday, $month $day, ${dt.year} • $hourStr:$minuteStr $period';
    } else {
      return '$month $day, $hourStr:$minuteStr $period';
    }
  }

  Future<void> _selectCustomDateTime() async {
    final now = DateTime.now();
    final initialDate = _customEndDateTime.isAfter(now)
        ? _customEndDateTime
        : now.add(const Duration(minutes: 30));

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Select Ban End Date',
    );

    if (pickedDate == null || !mounted) return;

    final initialTime = TimeOfDay.fromDateTime(initialDate);
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: 'Select Ban End Time',
    );

    if (pickedTime == null || !mounted) return;

    final newDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (newDateTime.isBefore(now.add(const Duration(seconds: 30)))) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ban end time must be at least 30 seconds in the future.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    if (mounted) {
      setState(() {
        _customEndDateTime = newDateTime;
        _selectedPresetSeconds = -1; // Switch to custom preset mode
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formattedCustomDate = _formatDateTime(
      _customEndDateTime,
      includeYear: true,
    );
    final effectiveSeconds = _effectiveBanSeconds;
    final banEndTimeStr = _formatDateTime(
      DateTime.now().add(Duration(seconds: effectiveSeconds)),
      includeYear: false,
    );

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actionsOverflowButtonSpacing: 8,
      actionsOverflowDirection: VerticalDirection.down,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: widget.isAlreadyBanned
                  ? Colors.orange.withValues(alpha: 0.15)
                  : Colors.red.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              widget.isAlreadyBanned
                  ? Icons.timer_outlined
                  : Icons.block_rounded,
              color: widget.isAlreadyBanned
                  ? Colors.orange.shade800
                  : Colors.red.shade700,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isAlreadyBanned
                      ? 'Edit Ban Duration'
                      : 'Ban Client from Wi-Fi',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Layer-2 Association Prevention',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Self-device Critical Warning Guardrail
            if (_isSelfDevice) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.red.shade400, width: 1.2),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.red.shade700,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'WARNING: Banning your current device will sever your Wi-Fi access to this router.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Client Context Awareness Card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.6,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.devices_rounded,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'MAC: ${widget.macAddress.toUpperCase()}${widget.ipAddress != null ? " • IP: ${widget.ipAddress}" : ""}',
                    style: GoogleFonts.geistMono(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (widget.ssid != null && widget.ssid!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Target SSID: ${widget.ssid}${widget.iface != null ? " (${widget.iface})" : ""}',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Ban Duration Preset Selector
            const Text(
              'Select Ban Duration:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presetOptions.map((preset) {
                final int seconds = preset['seconds'] as int;
                final bool isSelected = _selectedPresetSeconds == seconds;

                return ChoiceChip(
                  label: Text(preset['label'] as String),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      if (seconds == -1) {
                        _selectCustomDateTime();
                      } else {
                        setState(() => _selectedPresetSeconds = seconds);
                      }
                    }
                  },
                  selectedColor: Colors.orange.shade800.withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: isSelected
                        ? Colors.orange.shade900
                        : theme.colorScheme.onSurface,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            // Custom Date & Time Picker Card
            InkWell(
              onTap: _selectCustomDateTime,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _selectedPresetSeconds == -1
                      ? Colors.orange.shade50.withValues(alpha: 0.5)
                      : theme.colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.3,
                        ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _selectedPresetSeconds == -1
                        ? Colors.orange.shade700
                        : theme.colorScheme.outlineVariant,
                    width: _selectedPresetSeconds == -1 ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.access_time_filled_rounded,
                      color: _selectedPresetSeconds == -1
                          ? Colors.orange.shade900
                          : theme.colorScheme.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedPresetSeconds == -1
                                ? 'Custom Ban Expiry'
                                : 'Set Custom Date & Time...',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: _selectedPresetSeconds == -1
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            formattedCustomDate,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _selectedPresetSeconds == -1
                                  ? Colors.orange.shade900
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.edit_calendar_rounded,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Dynamic Summary Banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isValidDuration
                    ? Colors.orange.shade900.withValues(alpha: 0.08)
                    : Colors.red.shade900.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isValidDuration
                      ? Colors.orange.shade700.withValues(alpha: 0.4)
                      : Colors.red.shade400,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isValidDuration
                        ? Icons.info_outline_rounded
                        : Icons.error_outline_rounded,
                    size: 20,
                    color: _isValidDuration
                        ? Colors.orange.shade900
                        : Colors.red.shade700,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isValidDuration
                          ? 'Banned for ${_formatDurationString(effectiveSeconds)} (Ends $banEndTimeStr)'
                          : 'Please select a valid future date & time.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _isValidDuration
                            ? Colors.orange.shade900
                            : Colors.red.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
      actions: [
        if (widget.isAlreadyBanned && widget.onUnbanConfirmed != null)
          TextButton.icon(
            onPressed: _isSubmitting
                ? null
                : () async {
                    setState(() => _isSubmitting = true);
                    try {
                      await widget.onUnbanConfirmed!();
                      if (context.mounted) Navigator.of(context).pop();
                    } finally {
                      if (mounted) setState(() => _isSubmitting = false);
                    }
                  },
            icon: const Icon(
              Icons.lock_open_rounded,
              size: 16,
              color: Colors.green,
            ),
            label: const Text(
              'Unban Client',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: (_isValidDuration && !_isSubmitting)
              ? () async {
                  setState(() => _isSubmitting = true);
                  try {
                    await widget.onBanConfirmed(_effectiveBanSeconds);
                    if (context.mounted) Navigator.of(context).pop();
                  } finally {
                    if (mounted) setState(() => _isSubmitting = false);
                  }
                }
              : null,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.block_rounded, size: 16),
          label: Text(widget.isAlreadyBanned ? 'Update Ban' : 'Ban Client'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.orange.shade900,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}
