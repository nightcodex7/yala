// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/utils/os_platform_integration.dart';
import '../models/parental_profile.dart';
import '../controllers/parental_controls_controller.dart';
import '../widgets/add_edit_profile_dialog.dart';
import '../widgets/parental_profile_card.dart';

class ParentalControlsScreen extends ConsumerStatefulWidget {
  const ParentalControlsScreen({super.key});

  @override
  ConsumerState<ParentalControlsScreen> createState() =>
      _ParentalControlsScreenState();
}

class _ParentalControlsScreenState extends ConsumerState<ParentalControlsScreen>
    with WidgetsBindingObserver {
  final _controller = ParentalControlsController.instance;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.store.addListener(_onStoreChange);
    _initController();
  }

  Future<void> _initController() async {
    final appState = ref.read(appStateProvider);
    await _controller.loadStore(appState);
    _controller.startExpiryTimer(appState);
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.store.removeListener(_onStoreChange);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    _controller.handleLifecycleState(state, ref.read(appStateProvider));
  }

  void _onStoreChange() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _pauseProfile(
    ParentalProfile profile,
    PauseDuration duration,
  ) async {
    if (!mounted) return;
    final actionKey = 'pause_profile_${profile.id}';
    context.showToastLoading(
      'Pausing internet for ${profile.name}…',
      actionKey: actionKey,
    );

    final appState = ref.read(appStateProvider);
    final result = await _controller.pauseProfile(
      profile,
      duration,
      appState,
      context: context,
    );

    if (!mounted) return;

    if (result.success) {
      unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.medium));
      context.showToastSuccess(result.message, actionKey: actionKey);
    } else {
      unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));
      context.showToastError(result.message, actionKey: actionKey);
    }
  }

  Future<void> _resumeProfile(ParentalProfile profile) async {
    if (!mounted) return;
    final actionKey = 'resume_profile_${profile.id}';
    context.showToastLoading(
      'Resuming internet for ${profile.name}…',
      actionKey: actionKey,
    );

    final appState = ref.read(appStateProvider);
    final result = await _controller.resumeProfile(profile, appState: appState);

    if (!mounted) return;

    if (result.success) {
      unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.medium));
      context.showToastSuccess(result.message, actionKey: actionKey);
    } else {
      unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));
      context.showToastError(result.message, actionKey: actionKey);
    }
  }

  void _openAddProfile() {
    showDialog(
      context: context,
      builder: (ctx) => AddEditProfileDialog(
        allProfiles: _controller.store.profiles,
        onSave: (profile) async {
          final appState = ref.read(appStateProvider);
          final res = await _controller.addProfile(profile, appState);
          if (mounted && res.message.isNotEmpty) {
            context.showToastSuccess(res.message);
          }
        },
      ),
    );
  }

  void _openEditProfile(ParentalProfile profile) {
    showDialog(
      context: context,
      builder: (ctx) => AddEditProfileDialog(
        existing: profile,
        allProfiles: _controller.store.profiles,
        onSave: (updated) async {
          final appState = ref.read(appStateProvider);
          final res = await _controller.updateProfile(
            updated,
            profile,
            appState,
          );
          if (mounted && res.message.isNotEmpty) {
            context.showToastSuccess(res.message);
          }
        },
      ),
    );
  }

  void _confirmDeleteProfile(ParentalProfile profile) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Profile'),
        content: Text(
          'Delete "${profile.name}"? This will not affect current firewall rules.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final appState = ref.read(appStateProvider);
              final res = await _controller.deleteProfile(profile.id, appState);
              if (mounted && res.message.isNotEmpty) {
                context.showToastInfo(res.message);
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = ref.watch(appStateProvider);
    final caps = appState.capabilities;
    final isReviewerMode = appState.reviewerModeEnabled;
    final hasFirewall = caps == null || caps.hasUciWriteAccess;
    final hasFileExec = caps == null || caps.hasFileExec;
    final profiles = _controller.store.profiles;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parental Controls'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Activity Log',
            onPressed: () => _showActivityLog(context),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Capability banners ──────────────────────────────────────
          if (!hasFirewall)
            const _CapabilityBanner(
              icon: Icons.shield_outlined,
              color: Colors.orange,
              message:
                  'No UCI write access detected. Internet pause and content filter '
                  'features require root/admin access to the router.',
            ),
          if (!hasFileExec)
            const _CapabilityBanner(
              icon: Icons.schedule_rounded,
              color: Colors.blue,
              message:
                  'File execution unavailable. Time schedules require '
                  'the file.exec ubus method (available when luci-mod-rpc is installed).',
            ),
          if (isReviewerMode)
            _CapabilityBanner(
              icon: Icons.rate_review_outlined,
              color: theme.colorScheme.primary,
              message:
                  'Reviewer Mode — changes are simulated and not sent to a real router.',
            ),

          // ── Body ────────────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : profiles.isEmpty
                ? _EmptyState(onAdd: _openAddProfile)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: profiles.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (ctx, i) {
                      final profile = profiles[i];
                      return ParentalProfileCard(
                        profile: profile,
                        hasFirewall: hasFirewall,
                        hasFileExec: hasFileExec,
                        onPause: (duration) => _pauseProfile(profile, duration),
                        onResume: () => _resumeProfile(profile),
                        onEdit: () => _openEditProfile(profile),
                        onDelete: () => _confirmDeleteProfile(profile),
                        onToggleEnabled: () async {
                          final appState = ref.read(appStateProvider);
                          final res = await _controller.toggleProfileEnabled(
                            profile.id,
                            appState,
                          );
                          if (mounted &&
                              context.mounted &&
                              res.message.isNotEmpty) {
                            context.showToastInfo(res.message);
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddProfile,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Profile'),
      ),
    );
  }

  void _showActivityLog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (_, ctrl) => StatefulBuilder(
          builder: (ctx2, setSheetState) {
            final theme = Theme.of(ctx2);
            final log = _controller.store.activityLog;
            return Column(
              children: [
                // Drag handle
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
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                  child: Row(
                    children: [
                      const Icon(Icons.history_rounded),
                      const SizedBox(width: 10),
                      Text(
                        'Activity Log',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (log.isNotEmpty)
                        TextButton(
                          onPressed: () async {
                            final appState = ref.read(appStateProvider);
                            await _controller.clearActivityLog(appState);
                            setSheetState(() {});
                          },
                          child: const Text('Clear'),
                        ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: log.isEmpty
                      ? Center(
                          child: Text(
                            'No activity recorded yet.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: ctrl,
                          itemCount: log.length,
                          itemBuilder: (_, i) {
                            final e = log[i];
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                _iconForEvent(e.eventType),
                                size: 20,
                                color: _colorForEvent(e.eventType, theme),
                              ),
                              title: Text(
                                '${e.profileName}: ${e.eventType.label}',
                              ),
                              subtitle: Text(
                                _formatTs(e.timestamp) +
                                    (e.detail != null ? ' · ${e.detail}' : ''),
                                style: theme.textTheme.bodySmall,
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static IconData _iconForEvent(ParentalEventType t) {
    switch (t) {
      case ParentalEventType.paused:
      case ParentalEventType.schedulePaused:
      case ParentalEventType.limitReached:
        return Icons.pause_circle_outline;
      case ParentalEventType.resumed:
      case ParentalEventType.scheduleResumed:
      case ParentalEventType.limitOverridden:
        return Icons.play_circle_outline;
      case ParentalEventType.profileCreated:
        return Icons.person_add_outlined;
      case ParentalEventType.profileDeleted:
        return Icons.person_remove_outlined;
      case ParentalEventType.profileUpdated:
        return Icons.edit_outlined;
      case ParentalEventType.contentFilterApplied:
        return Icons.dns_outlined;
    }
  }

  static Color _colorForEvent(ParentalEventType t, ThemeData theme) {
    switch (t) {
      case ParentalEventType.paused:
      case ParentalEventType.schedulePaused:
      case ParentalEventType.limitReached:
        return Colors.orange;
      case ParentalEventType.resumed:
      case ParentalEventType.scheduleResumed:
      case ParentalEventType.limitOverridden:
        return Colors.green;
      case ParentalEventType.profileCreated:
      case ParentalEventType.profileDeleted:
      case ParentalEventType.profileUpdated:
      case ParentalEventType.contentFilterApplied:
        return theme.colorScheme.primary;
    }
  }

  static String _formatTs(DateTime dt) {
    final l = dt.toLocal();
    final h = l.hour.toString().padLeft(2, '0');
    final m = l.minute.toString().padLeft(2, '0');
    return '${l.day}/${l.month} $h:$m';
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

class _CapabilityBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;

  const _CapabilityBanner({
    required this.icon,
    required this.color,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                color: color.withValues(alpha: 0.9),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.family_restroom_rounded,
              size: 72,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 20),
            Text(
              'No Profiles Yet',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Create a profile for each family member or device group. '
              'Assign devices to a profile to manage internet access, '
              'schedules, and content filtering.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create First Profile'),
            ),
          ],
        ),
      ),
    );
  }
}
