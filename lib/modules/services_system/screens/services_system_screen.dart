// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/widgets/luci_collapsible_card.dart';
import '../models/services_system_info.dart';
import '../models/ddns_info.dart';

class ServicesSystemScreen extends ConsumerStatefulWidget {
  const ServicesSystemScreen({super.key});

  @override
  ConsumerState<ServicesSystemScreen> createState() =>
      _ServicesSystemScreenState();
}

class _ServicesSystemScreenState extends ConsumerState<ServicesSystemScreen> {
  /// Stores staged enable/disable toggles for modified init scripts.
  /// Format: {scriptName: desiredEnabledStatus}
  final Map<String, bool> _stagedInitScriptStates = {};
  bool _isSaving = false;

  bool get _hasUnsavedChanges => _stagedInitScriptStates.isNotEmpty;

  void _toggleInitScriptState(InitScript script, bool newValue) {
    setState(() {
      if (newValue == script.isEnabled) {
        _stagedInitScriptStates.remove(script.name);
      } else {
        _stagedInitScriptStates[script.name] = newValue;
      }
    });
  }

  void _discardChanges() {
    setState(() {
      _stagedInitScriptStates.clear();
    });
    if (mounted) {
      context.showToastInfo('Discarded all unsaved init script changes.');
    }
  }

  Future<void> _confirmAndDiscardChanges() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard Unsaved Changes?'),
        content: Text(
          'Are you sure you want to discard staged changes for ${_stagedInitScriptStates.length} init script(s)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _discardChanges();
    }
  }

  Future<bool> _saveChanges() async {
    if (!_hasUnsavedChanges || _isSaving) return true;

    setState(() {
      _isSaving = true;
    });

    final appState = ref.read(appStateProvider);
    final modifiedEntries = Map<String, bool>.from(_stagedInitScriptStates);
    final succeededScripts = <String>[];
    final failedScripts = <String>[];

    if (mounted) {
      context.showToastInfo(
        'Saving Init Scripts',
        subtitle: 'Saving ${modifiedEntries.length} init script change(s)...',
      );
    }

    for (final entry in modifiedEntries.entries) {
      final scriptName = entry.key;
      final targetEnabled = entry.value;
      final action = targetEnabled ? 'enable' : 'disable';

      final success = await appState.manageServiceAction(
        scriptName,
        action,
        context: context,
      );

      if (success) {
        succeededScripts.add(scriptName);
      } else {
        failedScripts.add(scriptName);
      }
    }

    setState(() {
      for (final name in succeededScripts) {
        _stagedInitScriptStates.remove(name);
      }
      _isSaving = false;
    });

    await appState.fetchDashboardData();

    if (!mounted) return failedScripts.isEmpty;

    if (failedScripts.isEmpty) {
      context.showToastSuccess(
        'Init Scripts Updated',
        subtitle: 'Successfully updated ${succeededScripts.length} script(s).',
      );
      return true;
    } else {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Init Script Save Warning'),
          content: Text(
            'Updated ${succeededScripts.length} script(s), but failed to update ${failedScripts.length} script(s):\n\n'
            '${failedScripts.join(", ")}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return false;
    }
  }

  Future<bool?> _showUnsavedChangesDialog() async {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved Init Script Changes'),
        content: Text(
          'You have ${_stagedInitScriptStates.length} unsaved change(s) to startup init scripts. Would you like to save them before leaving?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () {
              _discardChanges();
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Discard & Leave'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop(false);
              final saved = await _saveChanges();
              if (saved && mounted) {
                Navigator.of(context).pop();
              }
            },
            child: const Text('Save & Exit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final overview = ServicesSystemOverview.fromDashboardData(
      appState.dashboardData,
      isReviewerMode: appState.reviewerModeEnabled,
    );
    final ddnsOverview = DdnsOverview.fromDashboardData(
      appState.dashboardData,
      isReviewerMode: appState.reviewerModeEnabled,
    );

    return PopScope(
      canPop: !_hasUnsavedChanges && !_isSaving,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final shouldLeave = await _showUnsavedChangesDialog();
        if (shouldLeave == true && mounted) {
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Services & System'),
          actions: [
            if (_hasUnsavedChanges)
              IconButton(
                icon: const Icon(Icons.undo),
                tooltip: 'Discard Changes',
                onPressed: _isSaving ? null : _confirmAndDiscardChanges,
              ),
            if (_hasUnsavedChanges)
              IconButton(
                icon: const Icon(Icons.save),
                tooltip: 'Save Changes',
                onPressed: _isSaving ? null : () => _saveChanges(),
              ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            await appState.fetchDashboardData();
          },
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              LuciCollapsibleCard(
                title: 'Procd System Services',
                count: overview.services.length,
                subtitle:
                    '${overview.services.length} system services configured',
                icon: Icons.miscellaneous_services_outlined,
                iconColor: Colors.teal,
                child: Column(
                  children: overview.services
                      .map((svc) => _buildProcdServiceCard(context, ref, svc))
                      .toList(),
                ),
              ),
              const SizedBox(height: 16),
              LuciCollapsibleCard(
                title: 'Startup Init Scripts',
                count: overview.initScripts.length,
                subtitle:
                    '${overview.initScripts.length} /etc/init.d startup scripts',
                icon: Icons.playlist_add_check_outlined,
                iconColor: Colors.blue,
                child: _buildInitScriptsCard(context, overview.initScripts),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: _buildSectionHeader(
                      context,
                      'System Scheduled Cron Jobs',
                      Icons.schedule_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _isSaving
                        ? null
                        : () => _showAddEditCronDialog(
                            context,
                            cronJobs: overview.cronJobs,
                          ),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text(
                      'Add Task',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildCronJobsCard(context, overview.cronJobs),
              const SizedBox(height: 16),
              _buildDdnsSectionHeader(context, ddnsOverview),
              const SizedBox(height: 8),
              if (!ddnsOverview.isInstalled)
                _buildDdnsUninstalledBanner(context)
              else
                _buildDdnsInstancesCard(context, ddnsOverview),
              const SizedBox(height: 80),
            ],
          ),
        ),
        bottomNavigationBar: _hasUnsavedChanges
            ? _buildUnsavedChangesBottomBar(context)
            : null,
      ),
    );
  }

  Future<void> _saveCronJobsList(List<String> cronLines) async {
    setState(() {
      _isSaving = true;
    });

    final appState = ref.read(appStateProvider);
    final success = await appState.saveCronJobs(cronLines, context: context);

    setState(() {
      _isSaving = false;
    });

    if (!mounted) return;

    if (success) {
      context.showToastSuccess(
        'Cron Updated',
        subtitle: 'System cron jobs updated successfully.',
      );
      await appState.fetchDashboardData();
    } else {
      context.showToastError(
        'Update Failed',
        subtitle: 'Failed to update system cron jobs.',
      );
    }
  }

  void _showAddEditCronDialog(
    BuildContext context, {
    required List<CronJob> cronJobs,
    CronJob? existingJob,
    int? index,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _CronJobEditDialog(
        existingJob: existingJob,
        onSave: (newExpression, newCommand, isEnabled) async {
          final updatedJobs = List<CronJob>.from(cronJobs);
          final newLine = isEnabled
              ? '$newExpression $newCommand'
              : '# $newExpression $newCommand';
          final updatedJob = CronJob.fromCronLine(newLine);

          if (index != null && index >= 0 && index < updatedJobs.length) {
            updatedJobs[index] = updatedJob;
          } else {
            updatedJobs.add(updatedJob);
          }

          final cronLines = updatedJobs.map((j) => j.toCronLine()).toList();
          await _saveCronJobsList(cronLines);
        },
      ),
    );
  }

  void _confirmDeleteCronJob(int index, List<CronJob> cronJobs) {
    final targetJob = cronJobs[index];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Scheduled Task?'),
        content: Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text:
                    'Are you sure you want to delete this scheduled cron job?\n\n',
              ),
              TextSpan(
                text: targetJob.command,
                style: GoogleFonts.geistMono(fontWeight: FontWeight.bold),
              ),
              TextSpan(text: '\nSchedule: ${targetJob.expression}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final updatedJobs = List<CronJob>.from(cronJobs)..removeAt(index);
              final cronLines = updatedJobs.map((j) => j.toCronLine()).toList();
              await _saveCronJobsList(cronLines);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _toggleCronJobEnabled(
    int index,
    List<CronJob> cronJobs,
    bool enable,
  ) async {
    final updatedJobs = List<CronJob>.from(cronJobs);
    final target = updatedJobs[index];
    updatedJobs[index] = target.copyWith(isCommented: !enable);

    final cronLines = updatedJobs.map((j) => j.toCronLine()).toList();
    await _saveCronJobsList(cronLines);
  }

  Widget _buildCronJobsCard(BuildContext context, List<CronJob> cronJobs) {
    if (cronJobs.isEmpty) {
      return Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              const Icon(Icons.schedule, size: 36, color: Colors.grey),
              const SizedBox(height: 8),
              const Text(
                'No system cron jobs scheduled',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Add scheduled background maintenance tasks or system scripts.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isSaving
                    ? null
                    : () => _showAddEditCronDialog(context, cronJobs: cronJobs),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Create First Task'),
              ),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: cronJobs.asMap().entries.map((entry) {
          final index = entry.key;
          final cron = entry.value;
          final isEnabled = !cron.isCommented;
          final scheduleText = CronValidator.describeSchedule(cron.expression);

          return Column(
            children: [
              if (index > 0)
                const Divider(height: 1, indent: 16, endIndent: 16),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: isEnabled
                          ? theme.colorScheme.primary.withValues(alpha: 0.15)
                          : theme.colorScheme.onSurface.withValues(alpha: 0.12),
                      child: Icon(
                        Icons.schedule,
                        color: isEnabled
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.38,
                              ),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  cron.command,
                                  style: GoogleFonts.geistMono(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: isEnabled
                                        ? null
                                        : theme.disabledColor,
                                    decoration: isEnabled
                                        ? null
                                        : TextDecoration.lineThrough,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isEnabled
                                      ? LuciStatusColors.connected.withValues(
                                          alpha: 0.15,
                                        )
                                      : Colors.grey.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isEnabled ? 'ACTIVE' : 'DISABLED',
                                  style: TextStyle(
                                    color: isEnabled
                                        ? LuciStatusColors.connected
                                        : Colors.grey,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 9,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Schedule: ${cron.expression} • $scheduleText',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Switch.adaptive(
                      value: isEnabled,
                      onChanged: _isSaving
                          ? null
                          : (val) =>
                                _toggleCronJobEnabled(index, cronJobs, val),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: 'Edit Task',
                      onPressed: _isSaving
                          ? null
                          : () => _showAddEditCronDialog(
                              context,
                              cronJobs: cronJobs,
                              existingJob: cron,
                              index: index,
                            ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: theme.colorScheme.error,
                      ),
                      tooltip: 'Delete Task',
                      onPressed: _isSaving
                          ? null
                          : () => _confirmDeleteCronJob(index, cronJobs),
                    ),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildProcdServiceCard(
    BuildContext context,
    WidgetRef ref,
    ProcdService svc,
  ) {
    return Card(
      key: ValueKey(svc.name),
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: svc.isRunning
                            ? LuciStatusColors.connected.withValues(alpha: 0.15)
                            : Colors.red.withValues(alpha: 0.15),
                        child: Icon(
                          svc.isRunning ? Icons.play_arrow : Icons.stop,
                          color: svc.isRunning
                              ? LuciStatusColors.connected
                              : Colors.red,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              svc.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              svc.description,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: svc.isRunning
                        ? LuciStatusColors.successBg(context)
                        : LuciStatusColors.errorBg(context),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: svc.isRunning
                          ? LuciStatusColors.successBorder(context)
                          : LuciStatusColors.errorBorder(context),
                    ),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      svc.isRunning
                          ? (svc.pid != null
                                ? 'RUNNING (PID ${svc.pid})'
                                : 'RUNNING')
                          : 'STOPPED',
                      key: ValueKey('${svc.name}_${svc.isRunning}_${svc.pid}'),
                      style: TextStyle(
                        color: svc.isRunning
                            ? LuciStatusColors.successText(context)
                            : LuciStatusColors.errorText(context),
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final actionKey = 'service_restart_${svc.name}';
                    final appState = ref.read(appStateProvider);
                    if (context.mounted) {
                      context.showToastLoading(
                        'Restarting ${svc.name}...',
                        actionKey: actionKey,
                      );
                    }
                    final success = await appState.manageServiceAction(
                      svc.name,
                      'restart',
                    );
                    await appState.fetchDashboardData();
                    if (context.mounted) {
                      if (success) {
                        context.showToastSuccess(
                          'Successfully restarted ${svc.name}',
                          actionKey: actionKey,
                        );
                      } else {
                        context.showToastError(
                          'Failed to restart ${svc.name}',
                          actionKey: actionKey,
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Restart', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final targetAction = svc.isRunning ? 'stop' : 'start';
                    final actionKey = 'service_${targetAction}_${svc.name}';
                    final appState = ref.read(appStateProvider);
                    if (context.mounted) {
                      context.showToastLoading(
                        '${targetAction == "stop" ? "Stopping" : "Starting"} ${svc.name}...',
                        actionKey: actionKey,
                      );
                    }
                    final success = await appState.manageServiceAction(
                      svc.name,
                      targetAction,
                    );
                    await appState.fetchDashboardData();
                    if (context.mounted) {
                      if (success) {
                        context.showToastSuccess(
                          'Successfully performed $targetAction for ${svc.name}',
                          actionKey: actionKey,
                        );
                      } else {
                        context.showToastError(
                          'Failed to $targetAction ${svc.name}',
                          actionKey: actionKey,
                        );
                      }
                    }
                  },
                  icon: Icon(
                    svc.isRunning ? Icons.stop : Icons.play_arrow,
                    size: 16,
                  ),
                  label: Text(
                    svc.isRunning ? 'Stop' : 'Start',
                    style: const TextStyle(fontSize: 11),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitScriptsCard(
    BuildContext context,
    List<InitScript> initScripts,
  ) {
    if (initScripts.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('No init startup scripts found.'),
        ),
      );
    }

    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: initScripts.map((init) {
          final isStaged = _stagedInitScriptStates.containsKey(init.name);
          final currentEnabled =
              _stagedInitScriptStates[init.name] ?? init.isEnabled;

          return Container(
            key: ValueKey(init.name),
            decoration: BoxDecoration(
              color: isStaged
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.12)
                  : null,
              border: isStaged
                  ? Border(
                      left: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 4,
                      ),
                    )
                  : null,
            ),
            child: ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: Colors.blue.withValues(alpha: 0.15),
                child: Text(
                  '${init.startPriority}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      init.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isStaged) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Colors.amber.shade700,
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        'STAGED',
                        style: TextStyle(
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.bold,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                isStaged
                    ? 'Priority: ${init.startPriority} • Original: ${init.isEnabled ? "ENABLED" : "DISABLED"}'
                    : 'Startup Order Priority: ${init.startPriority}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: currentEnabled
                          ? LuciStatusColors.connected.withValues(alpha: 0.15)
                          : Colors.grey.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      currentEnabled ? 'ENABLED' : 'DISABLED',
                      style: TextStyle(
                        color: currentEnabled
                            ? LuciStatusColors.connected
                            : Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch.adaptive(
                    value: currentEnabled,
                    onChanged: _isSaving
                        ? null
                        : (newValue) => _toggleInitScriptState(init, newValue),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildUnsavedChangesBottomBar(BuildContext context) {
    final theme = Theme.of(context);
    final count = _stagedInitScriptStates.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Icon(Icons.edit_note, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$count script(s) modified',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            OutlinedButton(
              onPressed: _isSaving ? null : _confirmAndDiscardChanges,
              child: const Text('Discard'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _isSaving ? null : () => _saveChanges(),
              icon: _isSaving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check, size: 18),
              label: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDdnsSectionHeader(BuildContext context, DdnsOverview ddns) {
    final appState = ref.read(appStateProvider);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: _buildSectionHeader(
            context,
            'Dynamic DNS (DDNS)',
            Icons.dns_outlined,
          ),
        ),
        const SizedBox(width: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ddns.isInstalled) ...[
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: ddns.isGlobalEnabled,
                  onChanged: (val) async {
                    final success = await appState.toggleGlobalDdns(val);
                    await appState.fetchDashboardData();
                    if (context.mounted) {
                      if (success) {
                        context.showToastSuccess(
                          'DDNS service ${val ? "enabled" : "disabled"}',
                        );
                      } else {
                        context.showToastError(
                          'Failed to update DDNS service state',
                        );
                      }
                    }
                  },
                ),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: () =>
                    _showAddEditDdnsDialog(context, existingInstance: null),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add DDNS', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              tooltip: 'DDNS Menu',
              onSelected: (choice) {
                if (choice == 'install_pkg') {
                  _installDdnsPackage(context);
                } else if (choice == 'uninstall_pkg') {
                  _confirmUninstallDdnsPackage(context);
                } else if (choice == 'refresh') {
                  appState.fetchDashboardData();
                }
              },
              itemBuilder: (ctx) => [
                if (!ddns.isInstalled)
                  const PopupMenuItem(
                    value: 'install_pkg',
                    child: Row(
                      children: [
                        Icon(Icons.download, size: 18),
                        SizedBox(width: 8),
                        Text('Install DDNS Core Package'),
                      ],
                    ),
                  ),
                if (ddns.isInstalled)
                  const PopupMenuItem(
                    value: 'uninstall_pkg',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          color: LuciColors.error,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Uninstall DDNS Package',
                          style: TextStyle(color: LuciColors.error),
                        ),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: 'refresh',
                  child: Row(
                    children: [
                      Icon(Icons.refresh, size: 18),
                      SizedBox(width: 8),
                      Text('Refresh Status'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDdnsUninstalledBanner(BuildContext context) {
    return Card(
      elevation: 0,
      color: LuciStatusColors.warningBg(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: LuciStatusColors.warningBorder(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: LuciStatusColors.warningText(context),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'DDNS Core Package (ddns-scripts) Not Installed',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: LuciStatusColors.warningText(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Dynamic DNS updates router IP addresses automatically with services like Cloudflare, No-IP, DuckDNS, DynDNS, and FreeDNS. One-tap install will automatically fetch DDNS scripts for your router.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _installDdnsPackage(context),
                icon: const Icon(Icons.download, size: 18),
                label: const Text('One-Tap Install DDNS Package'),
                style: FilledButton.styleFrom(
                  backgroundColor: LuciColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDdnsInstancesCard(BuildContext context, DdnsOverview ddns) {
    if (ddns.instances.isEmpty) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const Icon(Icons.dns_outlined, size: 40, color: Colors.grey),
              const SizedBox(height: 8),
              const Text(
                'No Dynamic DNS configurations found',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'Add a DDNS provider to keep your domain pointing to your router automatically.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () =>
                    _showAddEditDdnsDialog(context, existingInstance: null),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add DDNS Instance'),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: ddns.instances
            .map((instance) => _buildDdnsInstanceTile(context, instance))
            .toList(),
      ),
    );
  }

  Widget _buildDdnsInstanceTile(BuildContext context, DdnsInstance instance) {
    final appState = ref.read(appStateProvider);
    final preset = kDdnsProviderPresets.firstWhere(
      (p) => p.serviceName == instance.serviceName,
      orElse: () => kDdnsProviderPresets.last,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: instance.enabled
            ? Theme.of(context).cardColor
            : Theme.of(context).cardColor.withAlpha(180),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withAlpha(50),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: instance.enabled
                        ? LuciStatusColors.successBg(context)
                        : LuciStatusColors.infoBg(context),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: instance.enabled
                          ? LuciStatusColors.successBorder(context)
                          : LuciStatusColors.infoBorder(context),
                    ),
                  ),
                  child: Text(
                    preset.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: instance.enabled
                          ? LuciStatusColors.successText(context)
                          : LuciStatusColors.infoText(context),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    instance.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: instance.enabled,
                    onChanged: (val) async {
                      final updated = instance.copyWith(enabled: val);
                      final ok = await appState.saveDdnsInstance(updated);
                      await appState.fetchDashboardData();
                      if (context.mounted) {
                        if (ok) {
                          context.showToastSuccess(
                            '${instance.name} ${val ? "enabled" : "disabled"}',
                          );
                        } else {
                          context.showToastError('Failed to update instance');
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.language, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Lookup: ${instance.lookupHost.isNotEmpty ? instance.lookupHost : (instance.domain.isNotEmpty ? instance.domain : "N/A")}',
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.swap_horiz, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  'Interface: ${instance.interface.toUpperCase()} • Interval: ${instance.checkInterval} ${instance.checkUnit}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                if (instance.statusStr != null) ...[
                  const Spacer(),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: instance.statusStr!.contains('Synced')
                          ? LuciStatusColors.successBg(context)
                          : LuciStatusColors.warningBg(context),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: instance.statusStr!.contains('Synced')
                            ? LuciStatusColors.successBorder(context)
                            : LuciStatusColors.warningBorder(context),
                      ),
                    ),
                    child: Text(
                      instance.statusStr!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: instance.statusStr!.contains('Synced')
                            ? LuciStatusColors.successText(context)
                            : LuciStatusColors.warningText(context),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _testDdnsConfiguration(instance),
                  icon: const Icon(Icons.published_with_changes, size: 14),
                  label: const Text(
                    'Test Config',
                    style: TextStyle(fontSize: 11),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Edit Configuration',
                  onPressed: () => _showAddEditDdnsDialog(
                    context,
                    existingInstance: instance,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: LuciColors.error,
                    size: 18,
                  ),
                  tooltip: 'Delete Configuration',
                  onPressed: () =>
                      _confirmDeleteDdnsInstance(context, instance.name),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _installDdnsPackage(BuildContext context) async {
    final appState = ref.read(appStateProvider);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Install DDNS Scripts Package'),
        content: const Text(
          'This will install the official OpenWrt ddns-scripts core package and dynamic DNS provider scripts.\n\nDo you want to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Install Now'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    const actionKey = 'install_ddns_scripts';
    if (context.mounted) {
      context.showToastLoading(
        'Installing ddns-scripts package...',
        actionKey: actionKey,
      );
    }

    final success = await appState.managePackage(
      packageName: 'ddns-scripts',
      action: 'install',
    );

    if (mounted && context.mounted) {
      if (success) {
        context.showToastSuccess(
          'ddns-scripts package installed successfully!',
          actionKey: actionKey,
        );
      } else {
        context.showToastError(
          'Failed to install ddns-scripts package.',
          actionKey: actionKey,
        );
      }
      await appState.fetchDashboardData();
    }
  }

  Future<void> _confirmUninstallDdnsPackage(BuildContext context) async {
    final appState = ref.read(appStateProvider);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: LuciColors.error),
            SizedBox(width: 8),
            Text('Uninstall DDNS Package?'),
          ],
        ),
        content: const Text(
          'This will remove ddns-scripts from your router. Any active dynamic DNS updates will be disabled.\n\nAre you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: LuciColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Uninstall'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final success = await appState.managePackage(
      packageName: 'ddns-scripts',
      action: 'remove',
    );
    if (mounted && context.mounted) {
      if (success) {
        context.showToastSuccess('DDNS package uninstalled.');
      } else {
        context.showToastError('Failed to uninstall DDNS package.');
      }
      await appState.fetchDashboardData();
    }
  }

  Future<void> _confirmDeleteDdnsInstance(
    BuildContext context,
    String name,
  ) async {
    final appState = ref.read(appStateProvider);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete DDNS "$name"?'),
        content: Text(
          'Are you sure you want to delete configuration section "$name"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: LuciColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final success = await appState.deleteDdnsInstance(name);
      if (context.mounted) {
        await appState.fetchDashboardData();
        if (context.mounted) {
          if (success) {
            context.showToastSuccess('Deleted DDNS instance "$name".');
          } else {
            context.showToastError('Failed to delete DDNS instance "$name".');
          }
        }
      }
    }
  }

  Future<void> _testDdnsConfiguration(DdnsInstance instance) async {
    final navigator = Navigator.of(context);
    final appState = ref.read(appStateProvider);
    unawaited(
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Testing DDNS lookup & resolution...'),
            ],
          ),
        ),
      ),
    );

    final res = await appState.testDdnsConfiguration(instance);

    if (!mounted) return;
    navigator.pop();

    unawaited(
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(
                res.isValid ? Icons.check_circle_outline : Icons.error_outline,
                color: res.isValid ? LuciColors.success : LuciColors.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  res.isValid
                      ? 'Validation Test Passed'
                      : 'Validation Test Failed',
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (res.errorMessage != null)
                  Text(
                    res.errorMessage!,
                    style: const TextStyle(
                      color: LuciColors.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                if (res.testOutput != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      res.testOutput!,
                      style: GoogleFonts.geistMono(
                        fontSize: 11,
                        color: Colors.greenAccent,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddEditDdnsDialog(
    BuildContext context, {
    DdnsInstance? existingInstance,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => _DdnsEditDialog(
        existingInstance: existingInstance,
        onSave: (instance) async {
          final appState = ref.read(appStateProvider);
          final success = await appState.saveDdnsInstance(instance);
          if (context.mounted) {
            await appState.fetchDashboardData();
            if (context.mounted) {
              if (success) {
                context.showToastSuccess(
                  'DDNS Saved',
                  subtitle: 'DDNS instance saved successfully!',
                );
              } else {
                context.showToastError(
                  'Save Failed',
                  subtitle: 'Failed to save DDNS instance.',
                );
              }
            }
          }
          return success;
        },
        onTest: (instance) async {
          final appState = ref.read(appStateProvider);
          return appState.testDdnsConfiguration(instance);
        },
      ),
    );
  }
}

class CronPreset {
  final String label;
  final String expression;
  const CronPreset(this.label, this.expression);
}

const List<CronPreset> kCronPresets = [
  CronPreset('Every 5 Minutes', '*/5 * * * *'),
  CronPreset('Every 15 Minutes', '*/15 * * * *'),
  CronPreset('Every Hour', '0 * * * *'),
  CronPreset('Every Day at Midnight (12:00 AM)', '0 0 * * *'),
  CronPreset('Every Day at 4:00 AM', '0 4 * * *'),
  CronPreset('Every Weekday (Mon-Fri) at Midnight', '0 0 * * 1-5'),
  CronPreset('Every Sunday at Midnight', '0 0 * * 0'),
  CronPreset('First Day of Every Month at Midnight', '0 0 1 * *'),
  CronPreset('Custom Expression', ''),
];

class CronValidator {
  static String? validateExpression(String expr) {
    final trimmed = expr.trim();
    if (trimmed.isEmpty) return 'Cron expression cannot be empty';

    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length != 5) {
      return 'Must contain 5 fields: minute hour day-of-month month day-of-week';
    }

    final fields = [
      (parts[0], 'Minute', 0, 59),
      (parts[1], 'Hour', 0, 23),
      (parts[2], 'Day of Month', 1, 31),
      (parts[3], 'Month', 1, 12),
      (parts[4], 'Day of Week', 0, 7),
    ];

    for (final f in fields) {
      final err = _validateField(f.$1, f.$2, f.$3, f.$4);
      if (err != null) return err;
    }

    return null;
  }

  static String? _validateField(String value, String name, int min, int max) {
    if (value == '*') return null;

    if (value.contains('/')) {
      final subparts = value.split('/');
      if (subparts.length != 2) return 'Invalid step format in $name';
      final step = int.tryParse(subparts[1]);
      if (step == null || step <= 0) return 'Invalid step number in $name';
      if (subparts[0] != '*') {
        final err = _validateField(subparts[0], name, min, max);
        if (err != null) return err;
      }
      return null;
    }

    if (value.contains(',')) {
      for (final item in value.split(',')) {
        final err = _validateField(item, name, min, max);
        if (err != null) return err;
      }
      return null;
    }

    if (value.contains('-')) {
      final range = value.split('-');
      if (range.length != 2) return 'Invalid range in $name';
      final start = int.tryParse(range[0]);
      final end = int.tryParse(range[1]);
      if (start == null || end == null) return 'Invalid range numbers in $name';
      if (start < min || start > max || end < min || end > max) {
        return '$name range must be between $min and $max';
      }
      if (start > end) return '$name start cannot exceed end';
      return null;
    }

    final numVal = int.tryParse(value);
    if (numVal == null) return 'Invalid character in $name';
    if (numVal < min || numVal > max) {
      return '$name must be between $min and $max';
    }

    return null;
  }

  static String describeSchedule(String expr) {
    final trimmed = expr.trim();
    if (validateExpression(trimmed) != null) return 'Custom schedule';

    for (final preset in kCronPresets) {
      if (preset.expression == trimmed) {
        return preset.label;
      }
    }

    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 5) {
      final min = parts[0];
      final hour = parts[1];
      final dom = parts[2];
      final mon = parts[3];
      final dow = parts[4];

      if (min == '*' && hour == '*' && dom == '*' && mon == '*' && dow == '*') {
        return 'Runs every minute';
      }
      if (min.startsWith('*/') &&
          hour == '*' &&
          dom == '*' &&
          mon == '*' &&
          dow == '*') {
        return 'Runs every ${min.substring(2)} minutes';
      }
      if (hour.startsWith('*/') && dom == '*' && mon == '*' && dow == '*') {
        final step = hour.substring(2);
        final m = int.tryParse(min) ?? 0;
        final mStr = m.toString().padLeft(2, '0');
        return 'Runs every $step hours at :$mStr';
      }

      final h = int.tryParse(hour);
      final m = int.tryParse(min);

      if (h != null && m != null) {
        final period = h >= 12 ? 'PM' : 'AM';
        final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
        final mStr = m.toString().padLeft(2, '0');
        final timeStr = '$h12:$mStr $period';

        if (dom == '*' && mon == '*' && dow == '*') {
          return 'Runs every day at $timeStr';
        }
        if (dom == '*' && mon == '*' && (dow == '0' || dow == '7')) {
          return 'Runs every Sunday at $timeStr';
        }
        if (dom == '*' && mon == '*' && dow == '1-5') {
          return 'Runs on weekdays (Mon-Fri) at $timeStr';
        }
        if (dom != '*' && mon == '*' && dow == '*') {
          return 'Runs on day $dom of every month at $timeStr';
        }
      }
    }
    return 'Runs on schedule ($trimmed)';
  }

  static String? validateCommand(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return 'Command cannot be empty';
    if (trimmed.contains('\n') || trimmed.contains('\r')) {
      return 'Command cannot contain newlines';
    }
    if (trimmed.length > 500) {
      return 'Command is too long (max 500 characters)';
    }
    return null;
  }

  static String? checkDangerousCommandWarning(String command) {
    final lower = command.toLowerCase();
    if (lower.contains('rm -rf /') ||
        lower.contains('rm -rf *') ||
        lower.contains('mkfs')) {
      return 'CAUTION: This command contains potentially destructive removal operations!';
    }
    if (lower.contains('dd if=') && lower.contains('of=/dev/')) {
      return 'CAUTION: Direct raw disk writes detected!';
    }
    return null;
  }
}

class _CronJobEditDialog extends StatefulWidget {
  final CronJob? existingJob;
  final Function(String expression, String command, bool isEnabled) onSave;

  const _CronJobEditDialog({this.existingJob, required this.onSave});

  @override
  State<_CronJobEditDialog> createState() => _CronJobEditDialogState();
}

class _CronJobEditDialogState extends State<_CronJobEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _exprController;
  late TextEditingController _cmdController;
  late bool _isEnabled;
  String? _selectedPreset;

  @override
  void initState() {
    super.initState();
    final job = widget.existingJob;
    _exprController = TextEditingController(
      text: job?.expression ?? '0 4 * * *',
    );
    _cmdController = TextEditingController(text: job?.command ?? '');
    _isEnabled = !(job?.isCommented ?? false);

    _matchPreset(_exprController.text);
  }

  bool get _isDirty {
    if (widget.existingJob == null) return true;
    final job = widget.existingJob!;
    return _exprController.text.trim() != job.expression ||
        _cmdController.text.trim() != job.command ||
        _isEnabled != !job.isCommented;
  }

  void _matchPreset(String expr) {
    final trimmed = expr.trim();
    for (final preset in kCronPresets) {
      if (preset.expression == trimmed) {
        _selectedPreset = preset.label;
        return;
      }
    }
    _selectedPreset = 'Custom Expression';
  }

  @override
  void dispose() {
    _exprController.dispose();
    _cmdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existingJob != null;
    final dangerousWarning = CronValidator.checkDangerousCommandWarning(
      _cmdController.text,
    );
    final isValid =
        CronValidator.validateExpression(_exprController.text) == null &&
        CronValidator.validateCommand(_cmdController.text) == null;
    final canSave = isValid && (!isEditing || _isDirty);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            isEditing ? Icons.edit_calendar : Icons.add_alarm,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isEditing ? 'Edit Scheduled Task' : 'Add New Scheduled Task',
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _selectedPreset,
                decoration: const InputDecoration(
                  labelText: 'Schedule Preset',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.speed),
                ),
                items: kCronPresets.map((preset) {
                  return DropdownMenuItem<String>(
                    value: preset.label,
                    child: Text(
                      preset.label,
                      style: const TextStyle(fontSize: 13),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedPreset = value;
                      final match = kCronPresets.firstWhere(
                        (p) => p.label == value,
                      );
                      if (match.expression.isNotEmpty) {
                        _exprController.text = match.expression;
                      }
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _exprController,
                decoration: const InputDecoration(
                  labelText: 'Cron Expression (5 fields)',
                  hintText: 'min hour dom month dow (e.g. 0 4 * * *)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.timelapse),
                ),
                style: GoogleFonts.geistMono(fontSize: 13),
                validator: (value) =>
                    CronValidator.validateExpression(value ?? ''),
                onChanged: (val) {
                  setState(() {
                    _matchPreset(val);
                  });
                },
              ),
              const SizedBox(height: 6),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _exprController,
                builder: (context, val, _) {
                  final desc = CronValidator.describeSchedule(val.text);
                  final err = CronValidator.validateExpression(val.text);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: err == null
                          ? theme.colorScheme.primaryContainer.withValues(
                              alpha: 0.25,
                            )
                          : theme.colorScheme.errorContainer.withValues(
                              alpha: 0.3,
                            ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          err == null
                              ? Icons.info_outline
                              : Icons.warning_amber_rounded,
                          size: 14,
                          color: err == null
                              ? theme.colorScheme.primary
                              : theme.colorScheme.error,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            err ?? desc,
                            style: TextStyle(
                              fontSize: 11,
                              color: err == null
                                  ? theme.colorScheme.onSurfaceVariant
                                  : theme.colorScheme.error,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cmdController,
                decoration: const InputDecoration(
                  labelText: 'Command to Execute',
                  hintText: '/sbin/reboot or /usr/bin/ping-check.sh',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.terminal),
                ),
                style: GoogleFonts.geistMono(fontSize: 13),
                validator: (value) =>
                    CronValidator.validateCommand(value ?? ''),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _buildCommandChip('/sbin/reboot', 'Reboot Router'),
                  _buildCommandChip('/usr/bin/ping-check.sh', 'Ping Check'),
                  _buildCommandChip('/sbin/wifi reload', 'Reload Wi-Fi'),
                  _buildCommandChip(
                    '/etc/init.d/network restart',
                    'Restart Net',
                  ),
                  _buildCommandChip('/etc/init.d/ddns restart', 'Restart DDNS'),
                ],
              ),
              if (dangerousWarning != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade700),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning,
                        size: 16,
                        color: Colors.amber.shade900,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          dangerousWarning,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Task Active State',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                subtitle: Text(
                  _isEnabled
                      ? 'Task is enabled and will run on schedule'
                      : 'Task is disabled (commented out)',
                  style: const TextStyle(fontSize: 11),
                ),
                value: _isEnabled,
                onChanged: (val) => setState(() => _isEnabled = val),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: canSave
              ? () {
                  if (_formKey.currentState!.validate()) {
                    Navigator.of(context).pop();
                    widget.onSave(
                      _exprController.text.trim(),
                      _cmdController.text.trim(),
                      _isEnabled,
                    );
                  }
                }
              : null,
          icon: const Icon(Icons.check, size: 16),
          label: Text(isEditing ? 'Save Task' : 'Add Task'),
        ),
      ],
    );
  }

  Widget _buildCommandChip(String cmd, String label) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 10)),
      avatar: const Icon(Icons.add, size: 12),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onPressed: () {
        setState(() {
          _cmdController.text = cmd;
        });
      },
    );
  }
}

class _DdnsEditDialog extends StatefulWidget {
  final DdnsInstance? existingInstance;
  final Future<bool> Function(DdnsInstance instance) onSave;
  final Future<DdnsValidationResult> Function(DdnsInstance instance) onTest;

  const _DdnsEditDialog({
    this.existingInstance,
    required this.onSave,
    required this.onTest,
  });

  @override
  State<_DdnsEditDialog> createState() => _DdnsEditDialogState();
}

class _DdnsEditDialogState extends State<_DdnsEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _lookupHostController;
  late TextEditingController _domainController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late TextEditingController _updateUrlController;
  late TextEditingController _ipUrlController;
  late TextEditingController _checkIntervalController;
  late TextEditingController _forceIntervalController;

  late String _selectedServiceName;
  late String _interface;
  late String _ipSource;
  late String _checkUnit;
  late String _forceUnit;
  late bool _enabled;
  late bool _useHttps;
  bool _obscurePassword = true;
  bool _isSaving = false;
  bool _isTesting = false;
  DdnsValidationResult? _testResult;

  @override
  void initState() {
    super.initState();
    final inst = widget.existingInstance;
    _selectedServiceName =
        inst?.serviceName ?? kDdnsProviderPresets.first.serviceName;
    _nameController = TextEditingController(text: inst?.name ?? 'myddns_ipv4');
    _lookupHostController = TextEditingController(text: inst?.lookupHost ?? '');
    _domainController = TextEditingController(text: inst?.domain ?? '');
    _usernameController = TextEditingController(text: inst?.username ?? '');
    _passwordController = TextEditingController(text: inst?.password ?? '');
    _updateUrlController = TextEditingController(text: inst?.updateUrl ?? '');
    _ipUrlController = TextEditingController(
      text: (inst?.ipUrl != null && inst!.ipUrl.isNotEmpty)
          ? inst.ipUrl
          : 'https://ipv4.icanhazip.com',
    );
    _checkIntervalController = TextEditingController(
      text: (inst?.checkInterval ?? 10).toString(),
    );
    _forceIntervalController = TextEditingController(
      text: (inst?.forceInterval ?? 24).toString(),
    );

    _interface = inst?.interface ?? 'wan';
    _ipSource = inst?.ipSource ?? 'web';
    _checkUnit = inst?.checkUnit ?? 'minutes';
    _forceUnit = inst?.forceUnit ?? 'hours';
    _enabled = inst?.enabled ?? true;
    _useHttps = inst?.useHttps ?? true;
  }

  bool get _isDirty {
    if (widget.existingInstance == null) return true;
    final inst = widget.existingInstance!;
    return _nameController.text.trim() != inst.name ||
        _lookupHostController.text.trim() != inst.lookupHost ||
        _domainController.text.trim() != inst.domain ||
        _usernameController.text.trim() != inst.username ||
        _passwordController.text.trim() != inst.password ||
        _selectedServiceName != inst.serviceName ||
        _interface != inst.interface ||
        _ipSource != inst.ipSource ||
        _ipUrlController.text.trim() != inst.ipUrl ||
        _updateUrlController.text.trim() != inst.updateUrl ||
        _checkIntervalController.text.trim() != inst.checkInterval.toString() ||
        _checkUnit != inst.checkUnit ||
        _enabled != inst.enabled ||
        _useHttps != inst.useHttps;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _lookupHostController.dispose();
    _domainController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _updateUrlController.dispose();
    _ipUrlController.dispose();
    _checkIntervalController.dispose();
    _forceIntervalController.dispose();
    super.dispose();
  }

  DdnsProviderPreset get _currentPreset => kDdnsProviderPresets.firstWhere(
    (p) => p.serviceName == _selectedServiceName,
    orElse: () => kDdnsProviderPresets.last,
  );

  DdnsInstance _buildCurrentInstance() {
    return DdnsInstance(
      name: _nameController.text.trim(),
      enabled: _enabled,
      serviceName: _selectedServiceName,
      lookupHost: _lookupHostController.text.trim(),
      domain: _domainController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text.trim(),
      interface: _interface,
      ipSource: _ipSource,
      ipUrl: _ipUrlController.text.trim(),
      updateUrl: _updateUrlController.text.trim(),
      useHttps: _useHttps,
      checkInterval: int.tryParse(_checkIntervalController.text) ?? 10,
      checkUnit: _checkUnit,
      forceInterval: int.tryParse(_forceIntervalController.text) ?? 24,
      forceUnit: _forceUnit,
    );
  }

  Future<void> _runTest() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    final testRes = await widget.onTest(_buildCurrentInstance());
    if (mounted) {
      setState(() {
        _isTesting = false;
        _testResult = testRes;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final ok = await widget.onSave(_buildCurrentInstance());
    if (mounted) {
      setState(() => _isSaving = false);
      if (ok) Navigator.of(context).pop();
    }
  }

  Widget _buildUrlChip(String url, String label) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 10)),
      avatar: const Icon(Icons.add_link, size: 12),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onPressed: () {
        setState(() {
          _ipUrlController.text = url;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preset = _currentPreset;
    final isEditing = widget.existingInstance != null;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.dns_outlined, color: LuciColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isEditing ? 'Edit DDNS Configuration' : 'Add DDNS Configuration',
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Provider Selector
                DropdownButtonFormField<String>(
                  initialValue: _selectedServiceName,
                  decoration: const InputDecoration(
                    labelText: 'Service Provider',
                    prefixIcon: Icon(Icons.hub_outlined),
                  ),
                  items: kDdnsProviderPresets
                      .map(
                        (p) => DropdownMenuItem(
                          value: p.serviceName,
                          child: Text(p.label),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedServiceName = val;
                      });
                    }
                  },
                ),
                const SizedBox(height: 10),

                // Dynamic Provider Hints Banner
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: LuciStatusColors.infoBg(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: LuciStatusColors.infoBorder(context),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: LuciStatusColors.infoText(context),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${preset.label} Setup Hint',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: LuciStatusColors.infoText(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '• Username: ${preset.usernameHint}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      Text(
                        '• Password/Token: ${preset.passwordHint}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      Text(
                        '• Domain: ${preset.domainHint}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Name & Enable
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _nameController,
                        enabled: !isEditing,
                        decoration: const InputDecoration(
                          labelText: 'Instance Section Name',
                          hintText: 'e.g. myddns_ipv4',
                        ),
                        validator: (val) => (val == null || val.trim().isEmpty)
                            ? 'Enter section name'
                            : null,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      children: [
                        const Text('Enabled', style: TextStyle(fontSize: 11)),
                        Switch(
                          value: _enabled,
                          onChanged: (v) => setState(() => _enabled = v),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Lookup Host & Domain
                TextFormField(
                  controller: _lookupHostController,
                  decoration: InputDecoration(
                    labelText: 'Lookup Hostname',
                    hintText: preset.lookupHostHint,
                    prefixIcon: const Icon(Icons.language),
                  ),
                  validator: (val) => (val == null || val.trim().isEmpty)
                      ? 'Enter lookup hostname'
                      : null,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _domainController,
                  decoration: InputDecoration(
                    labelText: 'Registered Domain',
                    hintText: preset.domainHint,
                    prefixIcon: const Icon(Icons.domain),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),

                // Username & Password
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: 'Username / Auth ID',
                    hintText: preset.usernameHint,
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password / API Token',
                    hintText: preset.passwordHint,
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),

                if (preset.requiresCustomUrl) ...[
                  TextFormField(
                    controller: _updateUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Custom Update URL',
                      hintText:
                          'https://[USERNAME]:[PASSWORD]@customddns.com/update?host=[DOMAIN]&ip=[IP]',
                      prefixIcon: Icon(Icons.link),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                ],

                // IP Source & Interface
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _ipSource,
                        decoration: const InputDecoration(
                          labelText: 'IP address source',
                          helperText: 'Method used to determine system IP',
                          helperMaxLines: 2,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'web',
                            child: Text('URL / Web Service'),
                          ),
                          DropdownMenuItem(
                            value: 'network',
                            child: Text('Network Interface'),
                          ),
                          DropdownMenuItem(
                            value: 'interface',
                            child: Text('Direct Interface'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _ipSource = v!),
                      ),
                    ),
                    if (_ipSource != 'web') ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _interface,
                          decoration: const InputDecoration(
                            labelText: 'Network Interface',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'wan',
                              child: Text('WAN (IPv4)'),
                            ),
                            DropdownMenuItem(
                              value: 'wan6',
                              child: Text('WAN6 (IPv6)'),
                            ),
                            DropdownMenuItem(value: 'lan', child: Text('LAN')),
                          ],
                          onChanged: (v) => setState(() => _interface = v!),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),

                // Conditional URL to Detect Field matching OpenWrt LuCI DDNS screenshot!
                if (_ipSource == 'web') ...[
                  TextFormField(
                    controller: _ipUrlController,
                    decoration: const InputDecoration(
                      labelText: 'URL to detect',
                      hintText: 'https://ipv4.icanhazip.com',
                      prefixIcon: Icon(Icons.travel_explore),
                    ),
                    validator: (val) =>
                        (_ipSource == 'web' &&
                            (val == null || val.trim().isEmpty))
                        ? 'Enter URL to detect system IP'
                        : null,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 4.0),
                    child: Text(
                      'Defines the Web page to read systems IP-Address from.\nExample for IPv4 : http://checkip.dyndns.com\nExample for IPv6 : http://checkipv6.dyndns.com',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.8,
                        ),
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _buildUrlChip(
                        'https://ipv4.icanhazip.com',
                        'icanhazip (IPv4)',
                      ),
                      _buildUrlChip(
                        'http://checkip.dyndns.com',
                        'DynDNS (IPv4)',
                      ),
                      _buildUrlChip('https://api.ipify.org', 'ipify (IPv4)'),
                      _buildUrlChip(
                        'http://checkipv6.dyndns.com',
                        'DynDNS (IPv6)',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                // HTTPS switch & check interval
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _checkIntervalController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Check Interval',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: _checkUnit,
                        decoration: const InputDecoration(labelText: 'Unit'),
                        items: const [
                          DropdownMenuItem(
                            value: 'minutes',
                            child: Text('Minutes'),
                          ),
                          DropdownMenuItem(
                            value: 'hours',
                            child: Text('Hours'),
                          ),
                          DropdownMenuItem(value: 'days', child: Text('Days')),
                        ],
                        onChanged: (v) => setState(() => _checkUnit = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      children: [
                        const Text('Use HTTPS', style: TextStyle(fontSize: 11)),
                        Switch(
                          value: _useHttps,
                          onChanged: (v) => setState(() => _useHttps = v),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Live Validation Test Output Box
                if (_isTesting)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Performing DNS resolution test on router...',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),

                if (_testResult != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _testResult!.isValid
                          ? LuciStatusColors.successBg(context)
                          : LuciStatusColors.errorBg(context),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _testResult!.isValid
                            ? LuciStatusColors.successBorder(context)
                            : LuciStatusColors.errorBorder(context),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _testResult!.isValid
                                  ? Icons.check_circle_outline
                                  : Icons.error_outline,
                              size: 16,
                              color: _testResult!.isValid
                                  ? LuciStatusColors.successText(context)
                                  : LuciStatusColors.errorText(context),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _testResult!.isValid
                                  ? 'Test Passed'
                                  : 'Test Failed',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: _testResult!.isValid
                                    ? LuciStatusColors.successText(context)
                                    : LuciStatusColors.errorText(context),
                              ),
                            ),
                          ],
                        ),
                        if (_testResult!.errorMessage != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            _testResult!.errorMessage!,
                            style: TextStyle(
                              fontSize: 11,
                              color: LuciStatusColors.errorText(context),
                            ),
                          ),
                        ],
                        if (_testResult!.testOutput != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _testResult!.testOutput!,
                              style: GoogleFonts.geistMono(
                                fontSize: 10,
                                color: Colors.greenAccent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
      ),
      actionsOverflowButtonSpacing: 8,
      actionsOverflowDirection: VerticalDirection.down,
      actions: [
        OutlinedButton.icon(
          onPressed: (_isSaving || _isTesting) ? null : _runTest,
          icon: const Icon(Icons.published_with_changes, size: 14),
          label: const Text('Test Config'),
        ),
        TextButton(
          onPressed: (_isSaving || _isTesting)
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_isSaving || _isTesting || (isEditing && !_isDirty))
              ? null
              : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(isEditing ? 'Save Instance' : 'Add Instance'),
        ),
      ],
    );
  }
}
