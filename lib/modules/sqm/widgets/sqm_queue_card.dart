// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import '../controllers/sqm_controller.dart';
import '../models/sqm_overview.dart';
import '../models/sqm_preset.dart';
import '../models/sqm_queue.dart';
import '../models/sqm_telemetry.dart';
import 'sqm_flow_offloading_dialog.dart';

/// Card for editing and managing a specific SQM queue instance with live telemetry.
class SqmQueueCard extends ConsumerStatefulWidget {
  final SqmQueue queue;
  final SqmOverview? overview;
  final SqmState? sqmState;
  final String? routerId;
  final List<String> availableInterfaces;
  final List<String> availableQdiscs;
  final List<String> availableScripts;
  final bool hasFlowOffloading;
  final VoidCallback onSaved;
  final VoidCallback onDeleted;

  const SqmQueueCard({
    super.key,
    required this.queue,
    this.overview,
    this.sqmState,
    this.routerId,
    required this.availableInterfaces,
    required this.availableQdiscs,
    required this.availableScripts,
    this.hasFlowOffloading = false,
    required this.onSaved,
    required this.onDeleted,
  });

  @override
  ConsumerState<SqmQueueCard> createState() => _SqmQueueCardState();
}

class _SqmQueueCardState extends ConsumerState<SqmQueueCard> {
  late bool _enabled;
  late String _selectedInterface;
  late String _selectedQdisc;
  late String _selectedScript;
  late String _selectedLinklayer;
  late TextEditingController _downloadController;
  late TextEditingController _uploadController;
  late TextEditingController _overheadController;

  bool _qdiscAdvanced = false;
  bool _squashDscp = true;
  bool _squashIngress = true;
  String _ingressEcn = 'ECN';
  String _egressEcn = 'NOECN';
  bool _debugLogging = false;
  int _verbosity = 5;

  bool _isSaving = false;
  bool _isDeleting = false;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _initFromQueue(widget.queue);
  }

  @override
  void didUpdateWidget(covariant SqmQueueCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.queue != widget.queue) {
      _initFromQueue(widget.queue);
    }
  }

  void _initFromQueue(SqmQueue q) {
    _enabled = q.enabled;
    _selectedInterface = q.interface;
    _selectedQdisc = q.qdisc;
    _selectedScript = q.script;
    _selectedLinklayer = q.linklayer;

    // Convert kbit/s to Mbps
    _downloadController = TextEditingController(
      text: q.download > 0 ? (q.download / 1000.0).toString() : '0',
    );
    _uploadController = TextEditingController(
      text: q.upload > 0 ? (q.upload / 1000.0).toString() : '0',
    );
    _overheadController = TextEditingController(text: q.overhead.toString());

    _qdiscAdvanced = q.qdiscAdvanced;
    _squashDscp = q.squashDscp;
    _squashIngress = q.squashIngress;
    _ingressEcn = q.ingressEcn;
    _egressEcn = q.egressEcn;
    _debugLogging = q.debugLogging;
    _verbosity = q.verbosity;
  }

  @override
  void dispose() {
    _downloadController.dispose();
    _uploadController.dispose();
    _overheadController.dispose();
    super.dispose();
  }

  Future<void> _saveQueue() async {
    if (_isSaving) return;

    if (_enabled && widget.hasFlowOffloading && !widget.queue.enabled) {
      final proceed = await showFlowOffloadingWarningDialog(context, ref: ref);
      if (proceed != true || !mounted) {
        return;
      }
    }

    if (!mounted) return;

    final double dlMbps =
        double.tryParse(_downloadController.text.trim()) ?? 0.0;
    final double ulMbps = double.tryParse(_uploadController.text.trim()) ?? 0.0;
    final int overhead = int.tryParse(_overheadController.text.trim()) ?? 0;

    if (_enabled && dlMbps <= 0 && ulMbps <= 0) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          actionsOverflowButtonSpacing: 8,
          actionsOverflowDirection: VerticalDirection.down,
          title: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: LuciStatusColors.warningColor(ctx),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Zero Bandwidth Configured',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          content: const Text(
            'Both download and upload speeds are set to 0 Mbps. With zero bandwidth, SQM will not perform any traffic shaping or bufferbloat mitigation.\n\nDo you want to save anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save Anyway'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) {
        return;
      }
    }

    setState(() => _isSaving = true);

    final l10n = AppLocalizations.of(context);
    final actionKey = 'save_sqm_${widget.queue.name}';

    if (mounted) {
      context.showToastLoading(
        l10n?.modSqmSavingQueueToast(widget.queue.name) ??
            'Saving SQM queue ${widget.queue.name}...',
        actionKey: actionKey,
      );
    }

    final updatedQueue = SqmQueue(
      name: widget.queue.name,
      enabled: _enabled,
      interface: _selectedInterface,
      download: (dlMbps * 1000).round(),
      upload: (ulMbps * 1000).round(),
      qdisc: _selectedQdisc,
      script: _selectedScript,
      linklayer: _selectedLinklayer,
      overhead: overhead,
      qdiscAdvanced: _qdiscAdvanced,
      squashDscp: _squashDscp,
      squashIngress: _squashIngress,
      ingressEcn: _ingressEcn,
      egressEcn: _egressEcn,
      debugLogging: _debugLogging,
      verbosity: _verbosity,
    );

    final bool success;
    if (widget.routerId != null) {
      success = await ref
          .read(sqmControllerProvider(widget.routerId!).notifier)
          .saveQueue(updatedQueue, context: mounted ? context : null);
    } else {
      final appState = ref.read(appStateProvider);
      success = await appState.saveSqmQueue(updatedQueue);
    }

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        context.showToastSuccess(
          l10n?.modSqmQueueSavedToast ?? 'SQM configuration saved and applied.',
          actionKey: actionKey,
        );
        widget.onSaved();
      } else {
        context.showToastError(
          l10n?.modSqmQueueSaveFailedToast ??
              'Failed to save SQM configuration.',
          subtitle:
              l10n?.toastErrorCheckPermissionsOrUci ??
              'Check router permissions or UCI configuration.',
          actionKey: actionKey,
        );
      }
    }
  }

  Future<void> _confirmDelete() async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        title: Text(
          l10n?.modSqmDeleteDialogTitle(widget.queue.name) ??
              'Delete Queue ${widget.queue.name}?',
        ),
        content: Text(
          l10n?.modSqmDeleteDialogContent ??
              'This will permanently delete this SQM queue instance configuration.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n?.actionCancel ?? 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n?.actionDelete ?? 'Delete'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isDeleting = true);
    final actionKey = 'delete_sqm_${widget.queue.name}';

    if (mounted) {
      context.showToastLoading(
        l10n?.modSqmDeletingQueueToast ?? 'Deleting SQM queue...',
        actionKey: actionKey,
      );
    }

    final bool success;
    if (widget.routerId != null) {
      success = await ref
          .read(sqmControllerProvider(widget.routerId!).notifier)
          .deleteQueue(widget.queue.name, context: mounted ? context : null);
    } else {
      final appState = ref.read(appStateProvider);
      success = await appState.deleteSqmQueue(widget.queue.name);
    }

    if (mounted) {
      setState(() => _isDeleting = false);
      if (success) {
        context.showToastSuccess(
          l10n?.modSqmQueueDeletedToast ?? 'SQM queue deleted.',
          actionKey: actionKey,
        );
        widget.onDeleted();
      } else {
        context.showToastError(
          l10n?.modSqmQueueDeleteFailedToast ?? 'Failed to delete SQM queue.',
          subtitle:
              l10n?.toastErrorCheckPermissionsOrUci ??
              'Check router permissions or UCI configuration.',
          actionKey: actionKey,
        );
      }
    }
  }

  void _applyOverheadPreset(int overhead, String linklayer) {
    setState(() {
      _overheadController.text = overhead.toString();
      _selectedLinklayer = linklayer;
    });
  }

  void _applyPreset(SqmPreset preset) {
    setState(() {
      _selectedQdisc = preset.qdisc;
      _selectedScript = preset.script;
      _selectedLinklayer = preset.linklayer;
      _overheadController.text = preset.overhead.toString();
      _qdiscAdvanced = preset.qdiscAdvanced;
    });
  }

  void _scaleBandwidth(double factor) {
    final dl = double.tryParse(_downloadController.text.trim()) ?? 0.0;
    final ul = double.tryParse(_uploadController.text.trim()) ?? 0.0;
    if (dl > 0) {
      final newDl = dl * factor;
      _downloadController.text = newDl % 1 == 0
          ? newDl.toInt().toString()
          : newDl.toStringAsFixed(1);
    }
    if (ul > 0) {
      final newUl = ul * factor;
      _uploadController.text = newUl % 1 == 0
          ? newUl.toInt().toString()
          : newUl.toStringAsFixed(1);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // Interface options ensuring selected interface is in the list
    final interfaces = Set<String>.from(widget.availableInterfaces);
    if (_selectedInterface.isNotEmpty) {
      interfaces.add(_selectedInterface);
    }
    final sortedInterfaces = interfaces.toList()..sort();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Queue header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _enabled
                        ? theme.colorScheme.primary.withValues(alpha: 0.12)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.tune_rounded,
                    color: _enabled
                        ? theme.colorScheme.primary
                        : LuciStatusColors.inactiveColor(context),
                    size: 22,
                  ),
                ),
                const SizedBox(width: LuciSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.queue.displayName(
                                primaryWanInterface:
                                    widget.overview?.primaryWanInterface,
                              ),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (widget.queue.isDefaultTemplate) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Router Template',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        _enabled
                            ? (l10n?.modSqmQueueEnabled ??
                                  'Active & Shaping Traffic')
                            : (l10n?.modSqmQueueDisabled ?? 'Disabled'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _enabled
                              ? LuciStatusColors.connected
                              : LuciStatusColors.inactive,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _enabled,
                  onChanged: (val) async {
                    if (val && widget.hasFlowOffloading) {
                      final proceed = await showFlowOffloadingWarningDialog(
                        context,
                        ref: ref,
                      );
                      if (proceed != true) {
                        return;
                      }
                    }
                    setState(() => _enabled = val);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  color: theme.colorScheme.error,
                  tooltip: l10n?.actionDelete ?? 'Delete Queue',
                  onPressed: _isDeleting ? null : _confirmDelete,
                ),
              ],
            ),

            const SizedBox(height: LuciSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: LuciSpacing.md),

            // Connection Profile & Default Templates Selector
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Connection Profile & Template',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Select an OpenWrt template optimized for your internet connection type:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 8),

            // Presets Horizontal Selector Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: SqmPreset.presets.map((preset) {
                  final isSelected =
                      _selectedQdisc == preset.qdisc &&
                      _selectedScript == preset.script &&
                      _selectedLinklayer == preset.linklayer &&
                      (int.tryParse(_overheadController.text.trim()) ?? 0) ==
                          preset.overhead;

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      selected: isSelected,
                      onSelected: (_) => _applyPreset(preset),
                      avatar: Icon(
                        preset.icon,
                        size: 15,
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.primary,
                      ),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            preset.title,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                            ),
                          ),
                          if (preset.badge != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white.withValues(alpha: 0.25)
                                    : theme.colorScheme.primary.withValues(
                                        alpha: 0.12,
                                      ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                preset.badge!,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? theme.colorScheme.onPrimary
                                      : theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            // Active Preset Description Banner
            Builder(
              builder: (ctx) {
                final matched = SqmPreset.match(
                  SqmQueue(
                    name: widget.queue.name,
                    interface: _selectedInterface,
                    qdisc: _selectedQdisc,
                    script: _selectedScript,
                    linklayer: _selectedLinklayer,
                    overhead:
                        int.tryParse(_overheadController.text.trim()) ?? 0,
                  ),
                );

                if (matched != null) {
                  return Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 15,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            matched.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),

            const SizedBox(height: LuciSpacing.md),

            // Interface dropdown
            Text(
              l10n?.modSqmInterfaceLabel ?? 'Network Interface',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: LuciSpacing.xs),
            DropdownButtonFormField<String>(
              initialValue: sortedInterfaces.contains(_selectedInterface)
                  ? _selectedInterface
                  : (sortedInterfaces.isNotEmpty
                        ? sortedInterfaces.first
                        : null),
              isExpanded: true,
              borderRadius: BorderRadius.circular(16),
              dropdownColor: theme.colorScheme.surfaceContainerHigh,
              elevation: 4,
              menuMaxHeight: 360,
              icon: const Icon(Icons.arrow_drop_down_rounded),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                isDense: true,
              ),
              items: sortedInterfaces.map((iface) {
                final label = widget.overview?.interfaceLabel(iface) ?? iface;
                return DropdownMenuItem<String>(
                  value: iface,
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedInterface = val);
              },
            ),

            const SizedBox(height: LuciSpacing.md),

            // Download & Upload Bandwidth Fields
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.arrow_downward_rounded,
                            size: 16,
                            color: LuciColors.rx,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            l10n?.modSqmDownloadLabel ?? 'Download (Mbps)',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
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
                          hintText: 'e.g. 100',
                          suffixText: 'Mbps',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: LuciSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.arrow_upward_rounded,
                            size: 16,
                            color: LuciColors.tx,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            l10n?.modSqmUploadLabel ?? 'Upload (Mbps)',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
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
                          hintText: 'e.g. 20',
                          suffixText: 'Mbps',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Quick Sweet-Spot:',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text(
                    '90% (Sweet Spot)',
                    style: TextStyle(fontSize: 11),
                  ),
                  onPressed: () => _scaleBandwidth(0.90),
                ),
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('85%', style: TextStyle(fontSize: 11)),
                  onPressed: () => _scaleBandwidth(0.85),
                ),
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('95%', style: TextStyle(fontSize: 11)),
                  onPressed: () => _scaleBandwidth(0.95),
                ),
              ],
            ),

            const SizedBox(height: LuciSpacing.md),

            // Queueing Discipline (qdisc) and Setup Script
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n?.modSqmQdiscLabel ?? 'Queue Discipline',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue:
                            widget.availableQdiscs.contains(_selectedQdisc)
                            ? _selectedQdisc
                            : 'cake',
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(16),
                        dropdownColor: theme.colorScheme.surfaceContainerHigh,
                        elevation: 4,
                        menuMaxHeight: 360,
                        icon: const Icon(Icons.arrow_drop_down_rounded),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          isDense: true,
                        ),
                        items: widget.availableQdiscs.map((qd) {
                          return DropdownMenuItem<String>(
                            value: qd,
                            child: Text(
                              qd,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedQdisc = val;
                              if (val == 'cake') {
                                _selectedScript = 'piece_of_cake.qos';
                              } else {
                                _selectedScript = 'simple.qos';
                              }
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: LuciSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n?.modSqmScriptLabel ?? 'Setup Script',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue:
                            widget.availableScripts.contains(_selectedScript)
                            ? _selectedScript
                            : (widget.availableScripts.isNotEmpty
                                  ? widget.availableScripts.first
                                  : 'piece_of_cake.qos'),
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(16),
                        dropdownColor: theme.colorScheme.surfaceContainerHigh,
                        elevation: 4,
                        menuMaxHeight: 360,
                        icon: const Icon(Icons.arrow_drop_down_rounded),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          isDense: true,
                        ),
                        items: widget.availableScripts.map((sc) {
                          return DropdownMenuItem<String>(
                            value: sc,
                            child: Text(
                              sc.replaceAll('.qos', ''),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedScript = val);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: LuciSpacing.md),

            // Link Layer Framing and Overhead Presets
            Text(
              l10n?.modSqmLinklayerLabel ?? 'Link Layer Framing & Overhead',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    initialValue:
                        ['none', 'ethernet', 'atm'].contains(_selectedLinklayer)
                        ? _selectedLinklayer
                        : 'none',
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(16),
                    dropdownColor: theme.colorScheme.surfaceContainerHigh,
                    elevation: 4,
                    menuMaxHeight: 360,
                    icon: const Icon(Icons.arrow_drop_down_rounded),
                    decoration: InputDecoration(
                      labelText: l10n?.modSqmFramingLabel ?? 'Framing',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'none',
                        child: Text('None (Fiber/LAN)'),
                      ),
                      DropdownMenuItem(
                        value: 'ethernet',
                        child: Text('Ethernet'),
                      ),
                      DropdownMenuItem(value: 'atm', child: Text('ATM (ADSL)')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedLinklayer = val);
                    },
                  ),
                ),
                const SizedBox(width: LuciSpacing.sm),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _overheadController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
                    ],
                    decoration: InputDecoration(
                      labelText: l10n?.modSqmOverheadLabel ?? 'Overhead',
                      suffixText: 'B',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Overhead Presets Quick Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ActionChip(
                    label: const Text(
                      'VDSL PPPoE (44B)',
                      style: TextStyle(fontSize: 11),
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _applyOverheadPreset(44, 'ethernet'),
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    label: const Text(
                      'Cable DOCSIS (34B)',
                      style: TextStyle(fontSize: 11),
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _applyOverheadPreset(34, 'ethernet'),
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    label: const Text(
                      'ADSL ATM (40B)',
                      style: TextStyle(fontSize: 11),
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _applyOverheadPreset(40, 'atm'),
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    label: const Text(
                      'None (0B)',
                      style: TextStyle(fontSize: 11),
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _applyOverheadPreset(0, 'none'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: LuciSpacing.md),

            // Live Queue Telemetry Section
            _buildTelemetrySection(context),

            const SizedBox(height: LuciSpacing.md),

            // Collapsible Advanced Settings
            InkWell(
              onTap: () => setState(() => _showAdvanced = !_showAdvanced),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      _showAdvanced
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_right_rounded,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n?.modSqmAdvancedOptionsTitle ??
                          'Advanced Queue Options',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_showAdvanced) ...[
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  l10n?.modSqmQdiscAdvanced ?? 'Enable Advanced Qdisc Options',
                ),
                value: _qdiscAdvanced,
                onChanged: (val) => setState(() => _qdiscAdvanced = val),
              ),
              if (_qdiscAdvanced) ...[
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    l10n?.modSqmSquashDscp ?? 'Squash DSCP Ingress/Egress',
                  ),
                  value: _squashDscp,
                  onChanged: (val) => setState(() => _squashDscp = val),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    l10n?.modSqmSquashIngress ?? 'Squash Ingress DSCP',
                  ),
                  value: _squashIngress,
                  onChanged: (val) => setState(() => _squashIngress = val),
                ),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _ingressEcn,
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(16),
                        dropdownColor: theme.colorScheme.surfaceContainerHigh,
                        elevation: 4,
                        menuMaxHeight: 360,
                        icon: const Icon(Icons.arrow_drop_down_rounded),
                        decoration: InputDecoration(
                          labelText: l10n?.modSqmIngressEcn ?? 'Ingress ECN',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.all(8),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'ECN', child: Text('ECN')),
                          DropdownMenuItem(
                            value: 'NOECN',
                            child: Text('NOECN'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _ingressEcn = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _egressEcn,
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(16),
                        dropdownColor: theme.colorScheme.surfaceContainerHigh,
                        elevation: 4,
                        menuMaxHeight: 360,
                        icon: const Icon(Icons.arrow_drop_down_rounded),
                        decoration: InputDecoration(
                          labelText: l10n?.modSqmEgressEcn ?? 'Egress ECN',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.all(8),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'NOECN',
                            child: Text('NOECN'),
                          ),
                          DropdownMenuItem(value: 'ECN', child: Text('ECN')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _egressEcn = val);
                        },
                      ),
                    ),
                  ],
                ),
              ],
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(l10n?.modSqmDebugLogging ?? 'Enable Debug Logging'),
                value: _debugLogging,
                onChanged: (val) => setState(() => _debugLogging = val),
              ),
              if (_debugLogging) ...[
                const SizedBox(height: 6),
                DropdownButtonFormField<int>(
                  initialValue: (_verbosity >= 0 && _verbosity <= 10)
                      ? _verbosity
                      : 5,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(16),
                  dropdownColor: theme.colorScheme.surfaceContainerHigh,
                  elevation: 4,
                  menuMaxHeight: 360,
                  icon: const Icon(Icons.arrow_drop_down_rounded),
                  decoration: InputDecoration(
                    labelText: 'Verbosity Level (0-10)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    isDense: true,
                  ),
                  items: List.generate(11, (i) {
                    final label = i == 0
                        ? '0 (Silent)'
                        : i == 5
                        ? '5 (Default)'
                        : i == 8
                        ? '8 (Verbose)'
                        : i == 10
                        ? '10 (Trace)'
                        : '$i';
                    return DropdownMenuItem<int>(value: i, child: Text(label));
                  }),
                  onChanged: (val) {
                    if (val != null) setState(() => _verbosity = val);
                  },
                ),
              ],
            ],

            const SizedBox(height: LuciSpacing.lg),

            // Save and Apply Button
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _saveQueue,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline_rounded, size: 20),
                label: Text(
                  _isSaving
                      ? 'Saving...'
                      : (l10n?.actionSave ?? 'Save & Apply'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetrySection(BuildContext context) {
    if (widget.sqmState == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final iface = _selectedInterface.isNotEmpty
        ? _selectedInterface
        : widget.queue.interface;
    final telemetry = widget.sqmState!.telemetryByInterface[iface];
    final prevTelemetry = widget.sqmState!.previousTelemetryByInterface[iface];
    final memBytes = telemetry?.memoryUsedBytes;
    final capBps = telemetry?.capacityEstimateBps;
    final ecnMarks = telemetry?.ecnMarked;
    final newFlows = telemetry?.newFlowCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        const SizedBox(height: LuciSpacing.md),

        // Telemetry header
        Row(
          children: [
            Icon(
              Icons.insights_rounded,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${l10n?.modSqmTelemetryTitle ?? "Queue Telemetry"} ($iface)',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (telemetry != null) ...[
              if (telemetry.hasRecentDropActivity(prevTelemetry))
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: LuciStatusColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: LuciStatusColors.warning.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.trending_down_rounded,
                        size: 13,
                        color: LuciStatusColors.warning,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l10n?.modSqmTelemetryRecentDropsBadge ??
                            'Recent Drop Activity',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: LuciStatusColors.warning,
                        ),
                      ),
                    ],
                  ),
                )
              else if (telemetry.hasBacklog)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: LuciStatusColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    l10n?.modSqmTelemetryBacklogActive(
                          telemetry.backlogPackets.toString(),
                          Client.formatBytes(telemetry.backlogBytes),
                        ) ??
                        '${telemetry.backlogPackets} pkts (${Client.formatBytes(telemetry.backlogBytes)})',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: LuciStatusColors.warning,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: LuciStatusColors.connected.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    l10n?.modSqmTelemetryBacklogClean ?? '0 pkts (Clean)',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: LuciStatusColors.connected,
                    ),
                  ),
                ),
            ],
          ],
        ),

        const SizedBox(height: 10),

        if (telemetry == null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _enabled
                        ? (l10n?.modSqmTelemetryWaitingForData(iface) ??
                              'Waiting for queue traffic on $iface...')
                        : (l10n?.modSqmOperatingStateInactive ?? 'Inactive'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          )
        else ...[
          // Metrics 2x2 grid
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.35,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildTelemetryMetric(
                        label: l10n?.modSqmTelemetrySentLabel ?? 'Sent Traffic',
                        value: Client.formatBytes(telemetry.sentBytes),
                        subtitle: '${telemetry.sentPackets} pkts',
                        theme: theme,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTelemetryMetric(
                        label:
                            l10n?.modSqmTelemetryBacklogLabel ??
                            'Instantaneous Backlog',
                        value: telemetry.hasBacklog
                            ? '${telemetry.backlogPackets} pkts'
                            : '0 pkts',
                        subtitle: telemetry.hasBacklog
                            ? Client.formatBytes(telemetry.backlogBytes)
                            : (l10n?.modSqmTelemetryBacklogClean ?? 'Clean'),
                        valueColor: telemetry.hasBacklog
                            ? LuciStatusColors.warning
                            : LuciStatusColors.connected,
                        theme: theme,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildTelemetryMetric(
                        label:
                            l10n?.modSqmTelemetryCumulativeDropsLabel ??
                            'Cumulative Drops',
                        value: '${telemetry.droppedPackets}',
                        subtitle:
                            '${telemetry.dropRatePercent.toStringAsFixed(2)}% rate',
                        valueColor: telemetry.hasCumulativeDrops
                            ? LuciStatusColors.warning
                            : null,
                        theme: theme,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTelemetryMetric(
                        label:
                            l10n?.modSqmTelemetryCumulativeOverlimitsLabel ??
                            'Cumulative Overlimits',
                        value: '${telemetry.overlimits}',
                        subtitle: telemetry.requeues > 0
                            ? '${telemetry.requeues} requeues'
                            : 'Cumulative total',
                        valueColor: telemetry.hasCumulativeOverlimits
                            ? LuciStatusColors.warning
                            : null,
                        theme: theme,
                      ),
                    ),
                  ],
                ),

                // CAKE specifics: memory & capacity estimate
                if ((memBytes != null && memBytes > 0) ||
                    (capBps != null && capBps > 0)) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (memBytes != null && memBytes > 0)
                        Expanded(
                          child: _buildTelemetryMetric(
                            label:
                                l10n?.modSqmTelemetryMemoryLabel ??
                                'Memory Used',
                            value: Client.formatBytes(memBytes),
                            theme: theme,
                          ),
                        ),
                      if (capBps != null && capBps > 0) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTelemetryMetric(
                            label:
                                l10n?.modSqmTelemetryCapacityLabel ??
                                'Capacity Estimate',
                            value:
                                '${(capBps / 1000000).toStringAsFixed(1)} Mbps',
                            theme: theme,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],

                // FQ-CoDel specifics: ECN marks & new flows
                if ((ecnMarks != null && ecnMarks > 0) ||
                    (newFlows != null && newFlows > 0)) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (ecnMarks != null && ecnMarks > 0)
                        Expanded(
                          child: _buildTelemetryMetric(
                            label: l10n?.modSqmTelemetryEcnLabel ?? 'ECN Marks',
                            value: '$ecnMarks',
                            theme: theme,
                          ),
                        ),
                      if (newFlows != null && newFlows > 0) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTelemetryMetric(
                            label:
                                l10n?.modSqmTelemetryNewFlowsLabel ??
                                'New Flows',
                            value: '$newFlows',
                            theme: theme,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],

                // CAKE Tins list if present
                if (telemetry.tinStats.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    l10n?.modSqmTelemetryTinsTitle ?? 'CAKE Priority Tins',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...telemetry.tinStats.map(
                    (tin) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            tin.name,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${tin.sentPackets ?? 0} pkts | ${tin.droppedPackets} drop | ${tin.backlogPackets} backlog',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 10),
                Text(
                  l10n?.modSqmTelemetryCumulativeNote ??
                      'Drops and overlimits are cumulative Linux Traffic Control counters since queue start. Instantaneous backlog shows current queue state.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.8,
                    ),
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTelemetryMetric({
    required String label,
    required String value,
    String? subtitle,
    Color? valueColor,
    required ThemeData theme,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 1),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 10,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}
