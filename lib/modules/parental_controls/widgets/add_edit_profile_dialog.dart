// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/client.dart';
import '../models/parental_profile.dart';
import '../models/parental_controls_store.dart';

/// Dialog for creating or editing a parental control profile.
/// Covers: name, icon, color, device MACs, schedule, time limit, content filter.
class AddEditProfileDialog extends ConsumerStatefulWidget {
  final ParentalProfile? existing;
  final List<ParentalProfile> allProfiles;
  final void Function(ParentalProfile) onSave;

  const AddEditProfileDialog({
    super.key,
    this.existing,
    required this.allProfiles,
    required this.onSave,
  });

  @override
  ConsumerState<AddEditProfileDialog> createState() =>
      _AddEditProfileDialogState();
}

class _AddEditProfileDialogState extends ConsumerState<AddEditProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _macCtrl;
  late final TextEditingController _customDns1Ctrl;
  late final TextEditingController _customDns2Ctrl;

  late String _selectedIcon;
  late String _selectedColor;
  late List<String> _macAddresses;
  late ContentFilterDns _contentFilter;
  TimeSchedule? _schedule;
  int? _dailyLimitMinutes;
  bool _hasTimeLimit = false;
  bool _hasSchedule = false;
  late bool _isEnabled;

  static const List<String> _colorOptions = [
    '#F97316',
    '#EF4444',
    '#A855F7',
    '#3B82F6',
    '#10B981',
    '#F59E0B',
    '#EC4899',
    '#6366F1',
  ];

  bool get _isEditing => widget.existing != null;

  static String generateNextProfileName(
    List<ParentalProfile> existingProfiles,
  ) {
    int maxIndex = 0;
    for (final p in existingProfiles) {
      final match = RegExp(
        r'^Profile\s+(\d+)$',
        caseSensitive: false,
      ).firstMatch(p.name);
      if (match != null) {
        final idx = int.tryParse(match.group(1)!) ?? 0;
        if (idx > maxIndex) maxIndex = idx;
      }
    }
    return 'Profile ${maxIndex + 1}';
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(
      text: e?.name ?? generateNextProfileName(widget.allProfiles),
    );
    _selectedIcon = e?.icon ?? kProfileIcons.first;
    _selectedColor = e?.color ?? _colorOptions.first;
    _macAddresses = List.from(e?.macAddresses ?? []);
    _contentFilter = e?.contentFilter ?? ContentFilterDns.none;
    _schedule = e?.schedule;
    _dailyLimitMinutes = e?.dailyTimeLimitMinutes;
    _hasSchedule = e?.schedule != null && (e?.schedule?.enabled ?? false);
    _hasTimeLimit = e?.dailyTimeLimitMinutes != null;
    _isEnabled = e?.isEnabled ?? true;
    _macCtrl = TextEditingController();
    _customDns1Ctrl = TextEditingController(
      text: (e?.customDnsServers.isNotEmpty ?? false)
          ? e!.customDnsServers[0]
          : '',
    );
    _customDns2Ctrl = TextEditingController(
      text: (e?.customDnsServers.length ?? 0) > 1 ? e!.customDnsServers[1] : '',
    );
    _schedule ??= const TimeSchedule(
      activeDays: {
        ScheduleDay.monday,
        ScheduleDay.tuesday,
        ScheduleDay.wednesday,
        ScheduleDay.thursday,
        ScheduleDay.friday,
      },
      blockHour: 22,
      blockMinute: 0,
      resumeHour: 7,
      resumeMinute: 0,
      enabled: false,
    );

    _nameCtrl.addListener(_onFieldChanged);
    _customDns1Ctrl.addListener(_onFieldChanged);
    _customDns2Ctrl.addListener(_onFieldChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final appState = ref.read(appStateProvider);
        if (appState.clients.isEmpty && !appState.isClientsLoading) {
          appState.fetchAggregatedClients().then((_) {
            if (mounted) setState(() {});
          });
        }
      }
    });
  }

  void _onFieldChanged() => setState(() {});

  @override
  void dispose() {
    _nameCtrl.removeListener(_onFieldChanged);
    _customDns1Ctrl.removeListener(_onFieldChanged);
    _customDns2Ctrl.removeListener(_onFieldChanged);
    _nameCtrl.dispose();
    _macCtrl.dispose();
    _customDns1Ctrl.dispose();
    _customDns2Ctrl.dispose();
    super.dispose();
  }

  bool get _isValid => _nameCtrl.text.trim().isNotEmpty;

  bool get _isDirty {
    final e = widget.existing;
    if (e == null) return true;

    if (_nameCtrl.text.trim() != e.name) return true;
    if (_selectedIcon != e.icon) return true;
    if (_selectedColor != e.color) return true;
    if (_isEnabled != e.isEnabled) return true;

    // MAC addresses comparison
    if (_macAddresses.length != e.macAddresses.length) return true;
    for (int i = 0; i < _macAddresses.length; i++) {
      if (_macAddresses[i] != e.macAddresses[i]) return true;
    }

    // Schedule comparison
    final existingHasSchedule = e.schedule != null && e.schedule!.enabled;
    if (_hasSchedule != existingHasSchedule) return true;
    if (_hasSchedule && e.schedule != null) {
      if (_schedule?.blockHour != e.schedule!.blockHour ||
          _schedule?.blockMinute != e.schedule!.blockMinute ||
          _schedule?.resumeHour != e.schedule!.resumeHour ||
          _schedule?.resumeMinute != e.schedule!.resumeMinute ||
          !setEquals(_schedule?.activeDays, e.schedule!.activeDays)) {
        return true;
      }
    }

    // Daily time limit comparison
    final existingHasTimeLimit = e.dailyTimeLimitMinutes != null;
    if (_hasTimeLimit != existingHasTimeLimit) return true;
    if (_hasTimeLimit && _dailyLimitMinutes != e.dailyTimeLimitMinutes) {
      return true;
    }

    // Content filter comparison
    if (_contentFilter != e.contentFilter) return true;

    // Custom DNS comparison
    final exDns1 = e.customDnsServers.isNotEmpty ? e.customDnsServers[0] : '';
    final exDns2 = e.customDnsServers.length > 1 ? e.customDnsServers[1] : '';
    if (_customDns1Ctrl.text.trim() != exDns1) return true;
    if (_customDns2Ctrl.text.trim() != exDns2) return true;

    return false;
  }

  bool get _canSave => _isValid && (_isEditing ? _isDirty : true);

  /// Formats a minute count into a human-readable label like "1h 30m" or "45m".
  static String _formatMinutes(int minutes) {
    if (minutes >= 60) {
      final h = minutes ~/ 60;
      final m = minutes % 60;
      return m > 0 ? '${h}h ${m}m' : '${h}h';
    }
    return '${minutes}m';
  }

  void _addMac() {
    final raw = _macCtrl.text.trim().toUpperCase();
    if (raw.isEmpty) return;
    final isValid = RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(raw);
    if (!isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid MAC address format (e.g. AA:BB:CC:DD:EE:FF)'),
        ),
      );
      return;
    }
    if (_macAddresses.any((m) => m.toUpperCase() == raw)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('MAC address already added')),
      );
      return;
    }
    setState(() {
      _macAddresses.add(raw);
      _macCtrl.clear();
    });
  }

  void _removeMac(String mac) => setState(() => _macAddresses.remove(mac));

  void _save() {
    if (!_isValid) return;
    final customDns = <String>[];
    if (_contentFilter == ContentFilterDns.custom) {
      if (_customDns1Ctrl.text.trim().isNotEmpty) {
        customDns.add(_customDns1Ctrl.text.trim());
      }
      if (_customDns2Ctrl.text.trim().isNotEmpty) {
        customDns.add(_customDns2Ctrl.text.trim());
      }
    }

    final profile = ParentalProfile(
      id: widget.existing?.id ?? ParentalControlsStore.generateId(),
      name: _nameCtrl.text.trim(),
      icon: _selectedIcon,
      color: _selectedColor,
      macAddresses: _macAddresses,
      isPaused: widget.existing?.isPaused ?? false,
      isEnabled: _isEnabled,
      pauseExpiresAt: widget.existing?.pauseExpiresAt,
      schedule: _hasSchedule ? _schedule?.copyWith(enabled: true) : null,
      dailyTimeLimitMinutes: _hasTimeLimit ? _dailyLimitMinutes : null,
      contentFilter: _contentFilter,
      customDnsServers: customDns,
    );
    widget.onSave(profile);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = ref.watch(appStateProvider);
    final availableClients = appState.clients;
    final screenH = MediaQuery.sizeOf(context).height;
    final maxH = (screenH - 32.0).clamp(200.0, 720.0);
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Discard Unsaved Changes?'),
            content: const Text(
              'You have unsaved profile changes. Are you sure you want to discard them?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep Editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        );
        if (confirmed == true && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 520, maxHeight: maxH),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 8, 0),
                child: Row(
                  children: [
                    Icon(
                      _isEditing
                          ? Icons.edit_rounded
                          : Icons.person_add_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _isEditing ? 'Edit Profile' : 'New Profile',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Profile Mode Toggle (Active / Bypassed) ───────
                        Material(
                          color: _isEnabled
                              ? theme.colorScheme.primaryContainer.withValues(
                                  alpha: 0.2,
                                )
                              : theme.colorScheme.errorContainer.withValues(
                                  alpha: 0.2,
                                ),
                          borderRadius: BorderRadius.circular(12),
                          clipBehavior: Clip.antiAlias,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _isEnabled
                                    ? theme.colorScheme.primary.withValues(
                                        alpha: 0.3,
                                      )
                                    : theme.colorScheme.error.withValues(
                                        alpha: 0.3,
                                      ),
                              ),
                            ),
                            child: SwitchListTile(
                              value: _isEnabled,
                              onChanged: (val) =>
                                  setState(() => _isEnabled = val),
                              activeThumbColor: theme.colorScheme.primary,
                              title: Text(
                                _isEnabled
                                    ? 'Profile Guardrails Active'
                                    : 'Profile Bypassed (Unrestricted)',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: _isEnabled
                                      ? theme.colorScheme.onSurface
                                      : theme.colorScheme.error,
                                ),
                              ),
                              subtitle: Text(
                                _isEnabled
                                    ? 'Schedule, DNS filters, and time limits are enforced.'
                                    : 'Devices under this profile enjoy unrestricted internet access without restrictions.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                              secondary: Icon(
                                _isEnabled
                                    ? Icons.shield_outlined
                                    : Icons.lock_open_rounded,
                                color: _isEnabled
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Name ──────────────────────────────────────────
                        TextFormField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Profile Name *',
                            hintText: 'e.g. Kids, Gaming PC, Teenager',
                            prefixIcon: Icon(Icons.badge_outlined),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Name is required'
                              : null,
                        ),
                        const SizedBox(height: 16),

                        // ── Icon picker ───────────────────────────────────
                        _SectionLabel('Profile Icon'),
                        const SizedBox(height: 8),
                        _IconPicker(
                          selected: _selectedIcon,
                          onSelect: (i) => setState(() => _selectedIcon = i),
                        ),
                        const SizedBox(height: 16),

                        // ── Color picker ─────────────────────────────────
                        _SectionLabel('Accent Color'),
                        const SizedBox(height: 8),
                        _ColorPicker(
                          colors: _colorOptions,
                          selected: _selectedColor,
                          onSelect: (c) => setState(() => _selectedColor = c),
                        ),
                        const SizedBox(height: 20),

                        // ── Device MACs ───────────────────────────────────
                        _SectionLabel('Assigned Devices'),
                        const SizedBox(height: 4),
                        Text(
                          'Select from connected network devices or enter MAC manually.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 10),

                        if (availableClients.isNotEmpty) ...[
                          Builder(
                            builder: (context) {
                              final uniqueClientsMap = <String, Client>{};
                              for (final c in availableClients) {
                                final normMac = c.macAddress
                                    .toUpperCase()
                                    .replaceAll('-', ':');
                                if (normMac.isNotEmpty &&
                                    normMac != 'N/A' &&
                                    normMac != '00:00:00:00:00:00') {
                                  if (!uniqueClientsMap.containsKey(normMac) ||
                                      (c.isConnected &&
                                          !uniqueClientsMap[normMac]!
                                              .isConnected)) {
                                    uniqueClientsMap[normMac] = c;
                                  }
                                }
                              }
                              final uniqueClients = uniqueClientsMap.values
                                  .toList();
                              if (uniqueClients.isEmpty) {
                                return const SizedBox.shrink();
                              }

                              return DropdownButtonFormField<String>(
                                key: ValueKey(
                                  'client_picker_${_macAddresses.length}',
                                ),
                                initialValue: null,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Pick from Connected Devices',
                                  hintText:
                                      'Select a connected device to add MAC...',
                                  prefixIcon: Icon(
                                    Icons.phonelink_setup_rounded,
                                  ),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: uniqueClients.map((client) {
                                  final macNorm = client.macAddress
                                      .toUpperCase()
                                      .replaceAll('-', ':');
                                  final isAlreadyAdded = _macAddresses.contains(
                                    macNorm,
                                  );
                                  final nameLabel =
                                      client.displayName.isNotEmpty
                                      ? client.displayName
                                      : (client.hostname.isNotEmpty
                                            ? client.hostname
                                            : 'Device');
                                  final typeIcon =
                                      client.connectionType ==
                                          ConnectionType.wireless
                                      ? '📶'
                                      : '🔌';
                                  return DropdownMenuItem<String>(
                                    value: macNorm,
                                    enabled: !isAlreadyAdded,
                                    child: Text(
                                      '$typeIcon $nameLabel ($macNorm)${isAlreadyAdded ? ' ✓ Added' : ''}',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isAlreadyAdded
                                            ? theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.38)
                                            : null,
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (selectedMac) {
                                  if (selectedMac == null) return;
                                  final client = uniqueClientsMap[selectedMac];
                                  if (!_macAddresses.contains(selectedMac)) {
                                    setState(() {
                                      _macAddresses.add(selectedMac);
                                      if (_nameCtrl.text.trim().isEmpty &&
                                          client != null) {
                                        final nameToUse =
                                            client.hostname.isNotEmpty &&
                                                client.hostname != '*' &&
                                                client.hostname != selectedMac
                                            ? client.hostname
                                            : client.displayName;
                                        if (nameToUse.isNotEmpty) {
                                          _nameCtrl.text = nameToUse;
                                        }
                                      }
                                    });
                                  }
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0,
                                ),
                                child: Text(
                                  'OR MANUAL MAC ENTRY',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                              const Expanded(child: Divider()),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _macCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'MAC Address',
                                  hintText: 'AA:BB:CC:DD:EE:FF',
                                  prefixIcon: Icon(Icons.devices_outlined),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                textCapitalization:
                                    TextCapitalization.characters,
                                onFieldSubmitted: (_) => _addMac(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              onPressed: _addMac,
                              icon: const Icon(Icons.add),
                              tooltip: 'Add MAC',
                            ),
                          ],
                        ),
                        if (_macAddresses.isEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'No devices assigned yet. Profile is pre-configured and ready for devices to be added later.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: _macAddresses
                                .map(
                                  (mac) => Chip(
                                    label: Text(
                                      mac,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    deleteIcon: const Icon(
                                      Icons.close,
                                      size: 14,
                                    ),
                                    onDeleted: () => _removeMac(mac),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                        const SizedBox(height: 20),

                        // ── Time Schedule ─────────────────────────────────
                        SwitchListTile.adaptive(
                          value: _hasSchedule,
                          onChanged: (v) => setState(() => _hasSchedule = v),
                          title: const Text('Block Schedule'),
                          subtitle: Text(
                            _hasSchedule && _schedule != null
                                ? 'Block ${_schedule!.blockTimeFormatted} → Resume ${_schedule!.resumeTimeFormatted} · ${_schedule!.activeDaysLabel}'
                                : 'Set recurring block/resume times',
                          ),
                          secondary: const Icon(Icons.schedule_rounded),
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (_hasSchedule && _schedule != null) ...[
                          _ScheduleEditor(
                            schedule: _schedule!,
                            onChanged: (s) => setState(() => _schedule = s),
                          ),
                          const SizedBox(height: 8),
                        ],

                        // ── Daily Time Limit ──────────────────────────────
                        SwitchListTile.adaptive(
                          value: _hasTimeLimit,
                          onChanged: (v) {
                            setState(() {
                              _hasTimeLimit = v;
                              if (v && _dailyLimitMinutes == null) {
                                _dailyLimitMinutes = 120;
                              }
                            });
                          },
                          title: const Text('Daily Time Limit'),
                          subtitle: Text(
                            _hasTimeLimit && _dailyLimitMinutes != null
                                ? '$_dailyLimitMinutes minutes per day'
                                : 'Limit total daily internet time',
                          ),
                          secondary: const Icon(Icons.timer_outlined),
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (_hasTimeLimit) ...[
                          Slider(
                            min: 15,
                            max: 480,
                            divisions: 31,
                            value: (_dailyLimitMinutes ?? 120).toDouble(),
                            label: _formatMinutes(_dailyLimitMinutes ?? 120),
                            onChanged: (v) =>
                                setState(() => _dailyLimitMinutes = v.round()),
                          ),
                          Center(
                            child: Text(
                              _formatMinutes(_dailyLimitMinutes ?? 120),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],

                        // ── Content Filtering ─────────────────────────────
                        _SectionLabel('Content Filtering (DNS)'),
                        const SizedBox(height: 8),
                        ...ContentFilterDns.values.map(
                          (opt) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            leading: Icon(
                              _contentFilter == opt
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              color: _contentFilter == opt
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                              size: 20,
                            ),
                            title: Text(
                              opt.label,
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              opt.description,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            onTap: () => setState(() => _contentFilter = opt),
                          ),
                        ),
                        if (_contentFilter == ContentFilterDns.custom) ...[
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _customDns1Ctrl,
                            decoration: const InputDecoration(
                              labelText: 'Primary DNS',
                              hintText: '1.1.1.1',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _customDns2Ctrl,
                            decoration: const InputDecoration(
                              labelText: 'Secondary DNS',
                              hintText: '8.8.8.8',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: FilledButton.icon(
                        onPressed: _canSave ? _save : null,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: Text(
                          _isEditing ? 'Save Changes' : 'Create Profile',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
    );
  }
}

// ── Internal helpers ──────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _IconPicker extends StatelessWidget {
  final String selected;
  final void Function(String) onSelect;
  const _IconPicker({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kProfileIcons.map((icon) {
        final isSelected = icon == selected;
        return GestureDetector(
          onTap: () => onSelect(icon),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
              color: isSelected
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: Center(
              child: Text(icon, style: const TextStyle(fontSize: 20)),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ColorPicker extends StatelessWidget {
  final List<String> colors;
  final String selected;
  final void Function(String) onSelect;
  const _ColorPicker({
    required this.colors,
    required this.selected,
    required this.onSelect,
  });

  Color _toColor(String hex) {
    try {
      return Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
    } catch (_) {
      return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: colors.map((c) {
        final isSelected = c == selected;
        final color = _toColor(c);
        return GestureDetector(
          onTap: () => onSelect(c),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.onSurface
                    : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: isSelected
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : null,
          ),
        );
      }).toList(),
    );
  }
}

class _ScheduleEditor extends StatelessWidget {
  final TimeSchedule schedule;
  final void Function(TimeSchedule) onChanged;
  const _ScheduleEditor({required this.schedule, required this.onChanged});

  Future<void> _pickTime(BuildContext context, {required bool isBlock}) async {
    final initial = isBlock
        ? TimeOfDay(hour: schedule.blockHour, minute: schedule.blockMinute)
        : TimeOfDay(hour: schedule.resumeHour, minute: schedule.resumeMinute);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    if (isBlock) {
      onChanged(
        schedule.copyWith(blockHour: picked.hour, blockMinute: picked.minute),
      );
    } else {
      onChanged(
        schedule.copyWith(resumeHour: picked.hour, resumeMinute: picked.minute),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time selectors
          Row(
            children: [
              Expanded(
                child: _TimeButton(
                  label: 'Block at',
                  time: schedule.blockTimeFormatted,
                  onTap: () => _pickTime(context, isBlock: true),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
              ),
              Expanded(
                child: _TimeButton(
                  label: 'Resume at',
                  time: schedule.resumeTimeFormatted,
                  onTap: () => _pickTime(context, isBlock: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Day selector
          Text(
            'Active on:',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: ScheduleDay.values.map((day) {
              final isActive = schedule.activeDays.contains(day);
              return FilterChip(
                label: Text(
                  day.shortLabel,
                  style: const TextStyle(fontSize: 11),
                ),
                selected: isActive,
                onSelected: (v) {
                  final newDays = Set<ScheduleDay>.from(schedule.activeDays);
                  if (v) {
                    newDays.add(day);
                  } else {
                    newDays.remove(day);
                  }
                  onChanged(schedule.copyWith(activeDays: newDays));
                },
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  final String label;
  final String time;
  final VoidCallback onTap;
  const _TimeButton({
    required this.label,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                time,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
