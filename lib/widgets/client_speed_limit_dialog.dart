// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/models/client_speed_limit.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';
import 'package:yet_another_luci_app/widgets/add_static_lease_dialog.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';

/// Modal bottom sheet dialog for configuring bandwidth and speed limits on a client device.
class ClientSpeedLimitDialog extends ConsumerStatefulWidget {
  final Client client;
  final ClientSpeedLimit? initialLimit;
  final String? routerId;

  const ClientSpeedLimitDialog({
    super.key,
    required this.client,
    this.initialLimit,
    this.routerId,
  });

  /// Opens the dialog as a modal bottom sheet.
  static Future<bool?> show(
    BuildContext context, {
    required Client client,
    ClientSpeedLimit? initialLimit,
    String? routerId,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => ClientSpeedLimitDialog(
        client: client,
        initialLimit: initialLimit,
        routerId: routerId,
      ),
    );
  }

  @override
  ConsumerState<ClientSpeedLimitDialog> createState() =>
      _ClientSpeedLimitDialogState();
}

class _ClientSpeedLimitDialogState
    extends ConsumerState<ClientSpeedLimitDialog> {
  late TextEditingController _downloadController;
  late TextEditingController _uploadController;
  String _downloadUnit = 'Mbps';
  String _uploadUnit = 'Mbps';
  bool _isSaving = false;
  String? _downloadError;
  String? _uploadError;

  // Suggestions required by user specification: 1, 2, 5, 10, 15 Mbps
  static const List<double> _downloadSuggestionsMbps = [
    1.0,
    2.0,
    5.0,
    10.0,
    15.0,
    25.0,
    50.0,
  ];

  static const List<Map<String, dynamic>> _uploadSuggestions = [
    {'value': 512.0, 'unit': 'Kbps', 'label': '512 Kbps'},
    {'value': 1.0, 'unit': 'Mbps', 'label': '1 Mbps'},
    {'value': 2.0, 'unit': 'Mbps', 'label': '2 Mbps'},
    {'value': 5.0, 'unit': 'Mbps', 'label': '5 Mbps'},
    {'value': 10.0, 'unit': 'Mbps', 'label': '10 Mbps'},
    {'value': 15.0, 'unit': 'Mbps', 'label': '15 Mbps'},
  ];

  @override
  void initState() {
    super.initState();
    final existing =
        widget.initialLimit ??
        ref
            .read(appStateProvider)
            .getClientSpeedLimit(widget.client.macAddress);

    if (existing != null && existing.isEffectivelyRestricted) {
      _downloadUnit = existing.downloadUnit;
      _uploadUnit = existing.uploadUnit;
      _downloadController = TextEditingController(
        text: existing.downloadValue > 0
            ? (existing.downloadValue == existing.downloadValue.roundToDouble()
                  ? existing.downloadValue.toInt().toString()
                  : existing.downloadValue.toString())
            : '',
      );
      _uploadController = TextEditingController(
        text: existing.uploadValue > 0
            ? (existing.uploadValue == existing.uploadValue.roundToDouble()
                  ? existing.uploadValue.toInt().toString()
                  : existing.uploadValue.toString())
            : '',
      );
    } else {
      _downloadController = TextEditingController(text: '10');
      _uploadController = TextEditingController(text: '2');
    }
  }

  @override
  void dispose() {
    _downloadController.dispose();
    _uploadController.dispose();
    super.dispose();
  }

  void _validate() {
    final l10n = mounted ? AppLocalizations.of(context) : null;
    setState(() {
      _downloadError = null;
      _uploadError = null;

      final dlVal = double.tryParse(_downloadController.text.trim()) ?? 0.0;
      final ulVal = double.tryParse(_uploadController.text.trim()) ?? 0.0;

      if (dlVal <= 0 && ulVal <= 0) {
        _downloadError =
            l10n?.speedLimitValidationEmpty ??
            'Enter at least one download or upload limit';
      } else {
        if (dlVal < 0) {
          _downloadError = l10n?.speedLimitValidationInvalid ?? 'Invalid value';
        }
        if (ulVal < 0) {
          _uploadError = l10n?.speedLimitValidationInvalid ?? 'Invalid value';
        }
      }
    });
  }

  Future<void> _handleSave() async {
    _validate();
    if (_downloadError != null || _uploadError != null) return;

    final dlVal = double.tryParse(_downloadController.text.trim()) ?? 0.0;
    final ulVal = double.tryParse(_uploadController.text.trim()) ?? 0.0;

    final normMac = ClientNamingHelper.normalizeMac(widget.client.macAddress);

    // Self device safety check
    final isSelf = await SelfDeviceGuard.isSelfDevice(normMac);
    if (isSelf && mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final dialogL10n = AppLocalizations.of(ctx);
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  dialogL10n?.speedLimitSelfDeviceWarningTitle ??
                      'Warning: Self Device',
                ),
              ],
            ),
            content: Text(
              dialogL10n?.speedLimitSelfDeviceWarningDesc ??
                  'This device is running Yala. Throttling its speed may affect your remote connection to the router. Proceed anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(dialogL10n?.actionCancel ?? 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(
                  dialogL10n?.speedLimitBtnProceedAnyway ?? 'Proceed Anyway',
                ),
              ),
            ],
          );
        },
      );
      if (proceed != true) return;
    }

    setState(() => _isSaving = true);
    final appState = ref.read(appStateProvider);

    final speedLimit = ClientSpeedLimit(
      targetMac: normMac,
      ipAddress: widget.client.ipAddress,
      ipv6Addresses: widget.client.ipv6Addresses ?? const [],
      downloadValue: dlVal,
      downloadUnit: _downloadUnit,
      uploadValue: ulVal,
      uploadUnit: _uploadUnit,
      enabled: true,
      hostname: widget.client.displayName,
      updatedAt: DateTime.now(),
    );

    final success = await appState.setClientSpeedLimit(
      speedLimit: speedLimit,
      routerId: widget.routerId,
      context: mounted ? context : null,
    );

    if (mounted) {
      final postL10n = AppLocalizations.of(context);
      setState(() => _isSaving = false);
      if (success) {
        context.showToastSuccess(
          postL10n?.speedLimitAppliedToast(widget.client.displayName) ??
              'Speed limit applied to ${widget.client.displayName}',
          subtitle: speedLimit.compactSummary,
        );
        Navigator.of(context).pop(true);
      } else {
        context.showToastError(
          postL10n?.speedLimitApplyFailedToast(widget.client.displayName) ??
              'Failed to apply speed limit to ${widget.client.displayName}',
        );
      }
    }
  }

  Future<void> _handleRemove() async {
    setState(() => _isSaving = true);
    final appState = ref.read(appStateProvider);
    final success = await appState.removeClientSpeedLimit(
      widget.client.macAddress,
      routerId: widget.routerId,
      context: mounted ? context : null,
    );

    if (mounted) {
      final postL10n = AppLocalizations.of(context);
      setState(() => _isSaving = false);
      if (success) {
        context.showToastSuccess(
          postL10n?.bandwidthThrottlingRemoveSuccess(
                widget.client.displayName,
              ) ??
              'Speed limit removed for ${widget.client.displayName}',
        );
        Navigator.of(context).pop(true);
      } else {
        context.showToastError(
          postL10n?.bandwidthThrottlingRemoveFailed ??
              'Failed to remove speed limit',
        );
      }
    }
  }

  Widget _buildUnitDropdown(
    String currentUnit,
    ValueChanged<String> onChanged,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentUnit,
          borderRadius: BorderRadius.circular(16),
          dropdownColor: theme.colorScheme.surfaceContainerHigh,
          elevation: 4,
          menuMaxHeight: 360,
          icon: const Icon(Icons.arrow_drop_down_rounded),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
          items: [
            DropdownMenuItem(
              value: 'Mbps',
              child: Text(
                'Mbps',
                style: TextStyle(color: theme.colorScheme.onSurface),
              ),
            ),
            DropdownMenuItem(
              value: 'Kbps',
              child: Text(
                'Kbps',
                style: TextStyle(color: theme.colorScheme.onSurface),
              ),
            ),
          ],
          onChanged: (val) {
            if (val != null) onChanged(val);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isStatic = widget.client.isStaticLease || widget.client.isStatic;
    final existing = ref.watch(
      appStateProvider.select(
        (s) => s.getClientSpeedLimit(
          widget.client.macAddress,
          routerId: widget.routerId,
        ),
      ),
    );
    final hasActiveLimit = existing != null && existing.isEffectivelyRestricted;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title and Client identity
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.4,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.traffic_rounded,
                      color: colorScheme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.client.displayName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${widget.client.ipAddress} • ${widget.client.macAddress}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: l10n?.actionClose ?? 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Download Rate Field
              Text(
                l10n?.speedLimitDownloadLabel ?? 'Download Limit',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _downloadController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*'),
                        ),
                      ],
                      decoration: InputDecoration(
                        hintText: 'e.g. 10',
                        prefixIcon: const Icon(
                          Icons.arrow_downward_rounded,
                          size: 20,
                        ),
                        isDense: true,
                        errorText: _downloadError,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onChanged: (_) => _validate(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildUnitDropdown(_downloadUnit, (newUnit) {
                    setState(() => _downloadUnit = newUnit);
                    _validate();
                  }),
                ],
              ),

              const SizedBox(height: 8),
              // Suggestions for Download
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _downloadSuggestionsMbps.map((mbps) {
                    final label = mbps == mbps.roundToDouble()
                        ? '${mbps.toInt()} Mbps'
                        : '$mbps Mbps';
                    final isSelected =
                        _downloadUnit == 'Mbps' &&
                        _downloadController.text.trim() ==
                            (mbps == mbps.roundToDouble()
                                ? mbps.toInt().toString()
                                : mbps.toString());

                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(label),
                        labelStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                        backgroundColor: isSelected
                            ? colorScheme.primaryContainer.withValues(
                                alpha: 0.5,
                              )
                            : colorScheme.surfaceContainerHighest.withValues(
                                alpha: 0.3,
                              ),
                        side: BorderSide(
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.outlineVariant.withValues(
                                  alpha: 0.4,
                                ),
                        ),
                        onPressed: () {
                          setState(() {
                            _downloadController.text =
                                mbps == mbps.roundToDouble()
                                ? mbps.toInt().toString()
                                : mbps.toString();
                            _downloadUnit = 'Mbps';
                          });
                          _validate();
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 16),

              // Upload Rate Field
              Text(
                l10n?.speedLimitUploadLabel ?? 'Upload Limit',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _uploadController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*'),
                        ),
                      ],
                      decoration: InputDecoration(
                        hintText: 'e.g. 2',
                        prefixIcon: const Icon(
                          Icons.arrow_upward_rounded,
                          size: 20,
                        ),
                        isDense: true,
                        errorText: _uploadError,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onChanged: (_) => _validate(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildUnitDropdown(_uploadUnit, (newUnit) {
                    setState(() => _uploadUnit = newUnit);
                    _validate();
                  }),
                ],
              ),

              const SizedBox(height: 8),
              // Suggestions for Upload
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _uploadSuggestions.map((item) {
                    final val = item['value'] as double;
                    final unit = item['unit'] as String;
                    final label = item['label'] as String;
                    final isSelected =
                        _uploadUnit == unit &&
                        _uploadController.text.trim() ==
                            (val == val.roundToDouble()
                                ? val.toInt().toString()
                                : val.toString());

                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(label),
                        labelStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                        backgroundColor: isSelected
                            ? colorScheme.primaryContainer.withValues(
                                alpha: 0.5,
                              )
                            : colorScheme.surfaceContainerHighest.withValues(
                                alpha: 0.3,
                              ),
                        side: BorderSide(
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.outlineVariant.withValues(
                                  alpha: 0.4,
                                ),
                        ),
                        onPressed: () {
                          setState(() {
                            _uploadController.text = val == val.roundToDouble()
                                ? val.toInt().toString()
                                : val.toString();
                            _uploadUnit = unit;
                          });
                          _validate();
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 16),

              // Dynamic IP / Static Lease Advisory
              if (!isStatic && widget.client.ipAddress != 'N/A') ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n?.speedLimitDynamicIpCallout ??
                              'Dynamic IP detected. Pinning a static DHCP lease ensures limits remain tied to this device permanently.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) =>
                                AddStaticLeaseDialog(client: widget.client),
                          );
                        },
                        child: Text(l10n?.speedLimitPinIpButton ?? 'Pin IP'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              const SizedBox(height: 12),

              // Action buttons
              Row(
                children: [
                  if (hasActiveLimit) ...[
                    OutlinedButton.icon(
                      onPressed: _isSaving ? null : _handleRemove,
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: colorScheme.error,
                        size: 16,
                      ),
                      label: Text(
                        l10n?.bandwidthThrottlingRemoveTooltip ??
                            'Remove Limit',
                        style: TextStyle(color: colorScheme.error),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(l10n?.actionCancel ?? 'Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _handleSave,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 16),
                      label: Text(l10n?.actionApply ?? 'Apply'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
