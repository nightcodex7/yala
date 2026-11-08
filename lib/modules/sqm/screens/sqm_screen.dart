// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/luci_loading_states.dart';
import 'package:yet_another_luci_app/widgets/luci_loading_view.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import '../controllers/sqm_controller.dart';
import '../models/sqm_overview.dart';
import '../models/sqm_queue.dart';
import '../widgets/sqm_install_card.dart';
import '../widgets/sqm_install_dialog.dart';
import '../widgets/sqm_queue_card.dart';
import '../widgets/sqm_status_card.dart';
import '../widgets/sqm_flow_offloading_dialog.dart';

/// Screen for Smart Queue Management (SQM) / Bufferbloat mitigation.
class SqmScreen extends ConsumerStatefulWidget {
  final String? routerId;
  const SqmScreen({super.key, this.routerId});

  @override
  ConsumerState<SqmScreen> createState() => _SqmScreenState();
}

class _SqmScreenState extends ConsumerState<SqmScreen> {
  bool _isInstalling = false;
  bool _isRefreshing = false;
  String? _activeRouterId;
  SqmController? _controller;

  String _resolveRouterId() {
    return widget.routerId ??
        ref.read(appStateProvider).selectedRouter?.id ??
        'default';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _activeRouterId = _resolveRouterId();
      _controller = ref.read(sqmControllerProvider(_activeRouterId!).notifier);
      _controller?.refresh(forceTelemetry: true);
      _controller?.startLiveTelemetry();
    });
  }

  @override
  void didUpdateWidget(covariant SqmScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routerId != widget.routerId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _controller?.stopLiveTelemetry();
        _activeRouterId = _resolveRouterId();
        _controller = ref.read(
          sqmControllerProvider(_activeRouterId!).notifier,
        );
        _controller?.refresh(forceTelemetry: true);
        _controller?.startLiveTelemetry();
      });
    }
  }

  @override
  void dispose() {
    _controller?.stopLiveTelemetry();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      final routerId = _activeRouterId ?? _resolveRouterId();
      await ref
          .read(sqmControllerProvider(routerId).notifier)
          .refresh(forceTelemetry: true);
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _openInstallDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final appState = ref.read(appStateProvider);
    final SqmController controller =
        _controller ??
        ref.read(
          sqmControllerProvider(_activeRouterId ?? _resolveRouterId()).notifier,
        );

    final selectedPkg = await showDialog<String>(
      context: context,
      builder: (ctx) => const SqmInstallDialog(),
    );

    if (selectedPkg == null || !mounted) return;

    setState(() => _isInstalling = true);
    const actionKey = 'sqm_package_install';

    if (mounted && context.mounted) {
      context.showToastLoading(
        l10n?.modSqmInstalling(selectedPkg) ?? 'Installing $selectedPkg...',
        actionKey: actionKey,
      );
    }

    final res = await controller.installSqmPackage();

    if (mounted && context.mounted) {
      setState(() => _isInstalling = false);

      if (res.isSuccess) {
        context.showToastSuccess(
          l10n?.modSqmInstallSuccess ?? 'SQM installed successfully!',
          actionKey: actionKey,
        );
        // Post-install verification and refresh
        await appState.fetchDashboardData();
      } else {
        context.showToastError(
          l10n?.modSqmInstallFailedTitle ?? 'Installation Failed',
          subtitle: res.userFriendlyPackageError,
          actionKey: actionKey,
        );

        final errorText =
            res.errorMessage ??
            'Unknown error occurred while installing $selectedPkg';
        final isReadOnlyError = errorText.toLowerCase().contains(
          'read-only file system',
        );
        final isStorageError = res.isInsufficientStorage || isReadOnlyError;
        final isOomError = res.isMemoryExhausted;

        // Show detailed output dialog for diagnosis
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            actionsOverflowButtonSpacing: 8,
            actionsOverflowDirection: VerticalDirection.down,
            title: Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: Theme.of(ctx).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isStorageError
                        ? (isReadOnlyError
                              ? 'Filesystem is Read-Only'
                              : 'Insufficient Storage Space')
                        : (isOomError
                              ? 'Memory Exhaustion (OOM)'
                              : (l10n?.pkgExecutionOutputTitle ??
                                    'Installation Output')),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isOomError) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade900.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.amber.shade700.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.memory_rounded,
                            color: Colors.amber.shade800,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'The router ran out of RAM while resolving package dependencies and terminated the package manager.\n\nTo resolve this:\n• Enable zram-swap or configure external swap space\n• Stop memory-intensive background services temporarily\n• Install packages individually or use an image with pre-baked packages',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.amber.shade900,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (isStorageError) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade900.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.amber.shade700.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.amber.shade800,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isReadOnlyError
                                  ? 'The router\'s root filesystem is mounted read-only because there is no space left in the flash overlay partition (/overlay).\n\nTo resolve this:\n• Free up flash space or remove unused packages\n• Run "firstboot" via SSH to reset the overlay\n• Use Extroot (USB drive) for expanded storage'
                                  : 'The router does not have enough storage space on the flash partition to install this package.\n\nTo resolve this:\n• Free up flash space or remove unused packages\n• Use Extroot (USB drive) for expanded storage',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.amber.shade900,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SelectableText(
                    errorText,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n?.btnOk ?? 'OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _confirmUninstall(
    BuildContext context,
    SqmOverview overview,
  ) async {
    final l10n = AppLocalizations.of(context);
    final appState = ref.read(appStateProvider);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Theme.of(ctx).colorScheme.error,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(l10n?.modSqmUninstallDialogTitle ?? 'Uninstall SQM?'),
            ),
          ],
        ),
        content: Text(
          l10n?.modSqmUninstallDialogContent ??
              'This will stop the SQM service and remove SQM packages from your router. Active queue shaping will cease.',
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
            child: Text(l10n?.actionUninstall ?? 'Uninstall'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    const actionKey = 'sqm_uninstall';
    if (mounted && context.mounted) {
      context.showToastLoading(
        l10n?.modSqmUninstallingToast ?? 'Uninstalling SQM...',
        actionKey: actionKey,
      );
    }

    // Try removing luci-app-sqm first, then sqm-scripts
    await appState.removePackage('luci-app-sqm');
    final res = await appState.removePackage('sqm-scripts');

    if (mounted && context.mounted) {
      if (res.isSuccess) {
        context.showToastSuccess(
          l10n?.modSqmUninstallSuccessToast ?? 'SQM removed successfully.',
          actionKey: actionKey,
        );
        final routerId = _activeRouterId ?? _resolveRouterId();
        SqmController.clearSessionCache(routerId);
        await ref.read(sqmControllerProvider(routerId).notifier).refresh();
      } else {
        context.showToastError(
          l10n?.modSqmUninstallFailedToast ?? 'Failed to remove SQM packages.',
          subtitle: res.userFriendlyPackageError,
          actionKey: actionKey,
        );
      }
      await appState.fetchDashboardData();
    }
  }

  Future<void> _addNewQueue(SqmOverview overview) async {
    final l10n = AppLocalizations.of(context);

    if (overview.hasAnyFlowOffloading) {
      final proceed = await showFlowOffloadingWarningDialog(context, ref: ref);
      if (proceed != true || !mounted) {
        return;
      }
    }

    // If an existing queue template is present in the router and not yet enabled/configured,
    // utilize the existing one instead of unnecessarily creating duplicate queue instances.
    if (overview.queues.isNotEmpty) {
      final existingTemplate = overview.queues.firstWhere(
        (q) => !q.enabled || !q.isConfigured,
        orElse: () => overview.queues.first,
      );

      if (!existingTemplate.enabled || !existingTemplate.isConfigured) {
        final useExisting = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            actionsOverflowButtonSpacing: 8,
            actionsOverflowDirection: VerticalDirection.down,
            title: Row(
              children: [
                Icon(
                  Icons.tune_rounded,
                  color: Theme.of(ctx).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Existing Template Present',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
            content: Text(
              'Your router already has an existing queue template (${existingTemplate.displayName(primaryWanInterface: overview.primaryWanInterface)}).\n\n'
              'To keep your configuration robust, we recommend configuring and utilizing this existing template directly.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Create New Anyway'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Use Existing Template'),
              ),
            ],
          ),
        );

        if (useExisting == true || useExisting == null) {
          return;
        }
      }
    }

    // Generate unique name that doesn't collide with existing queues or router network interfaces
    int counter = 1;
    String newName = 'sqm$counter';
    final existingNames = overview.queues
        .map((q) => q.name.toLowerCase())
        .toSet();
    final interfaceNames = overview.networkInterfaces
        .map((i) => i.toLowerCase())
        .toSet();
    while (existingNames.contains(newName.toLowerCase()) ||
        interfaceNames.contains(newName.toLowerCase())) {
      counter++;
      newName = 'sqm$counter';
    }

    final assignedInterfaces = overview.queues
        .map((q) => q.interface.toLowerCase())
        .toSet();
    final candidateInterface = overview.networkInterfaces.firstWhere(
      (iface) =>
          !assignedInterfaces.contains(iface.toLowerCase()) && iface.isNotEmpty,
      orElse: () => overview.primaryWanInterface ?? 'wan',
    );

    final newQueue = SqmQueue(
      name: newName,
      enabled: true,
      interface: candidateInterface,
      download: 0,
      upload: 0,
      qdisc: 'cake',
      script: 'piece_of_cake.qos',
    );

    final routerId = _activeRouterId ?? _resolveRouterId();
    final success = await ref
        .read(sqmControllerProvider(routerId).notifier)
        .saveQueue(newQueue, context: mounted ? context : null);
    if (mounted && context.mounted) {
      if (success) {
        context.showToastSuccess(
          l10n?.modSqmQueueCreatedToast(newName) ??
              'Created new queue $newName.',
        );
        await _refresh();
      } else {
        context.showToastError(
          l10n?.modSqmQueueCreateFailedToast ?? 'Failed to create new queue.',
          subtitle:
              l10n?.toastErrorCheckPermissionsOrUci ??
              'Check router permissions or UCI configuration.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final routerId = _resolveRouterId();
    final sqmState = ref.watch(sqmControllerProvider(routerId));
    final overview = SqmOverview.fromSqmState(sqmState);

    final isInitialLoading = sqmState.isLoading && sqmState.lastUpdated == null;
    final isDiscoveryFailed =
        !sqmState.isLoading &&
        !overview.isInstalled &&
        sqmState.errorMessage != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n?.modSqmName ?? 'Smart Queue Management'),
        actions: [
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            tooltip: l10n?.actionRefresh ?? 'Refresh',
            onPressed: _refresh,
          ),
          if (overview.isInstalled)
            PopupMenuButton<String>(
              onSelected: (val) {
                if (val == 'uninstall') {
                  _confirmUninstall(context, overview);
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'uninstall',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        color: Theme.of(context).colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n?.actionUninstall ?? 'Uninstall SQM',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (isInitialLoading)
              const LuciLoadingView(
                padding: EdgeInsets.symmetric(vertical: 8),
                skeleton: Column(
                  children: [
                    LuciCardSkeleton(),
                    SizedBox(height: LuciSpacing.md),
                    LuciCardSkeleton(),
                  ],
                ),
              )
            else if (isDiscoveryFailed)
              _buildDiscoveryErrorView(
                context,
                l10n,
                theme,
                sqmState.errorMessage!,
              )
            else if (!overview.isInstalled)
              SqmInstallCard(
                onInstallTap: () => _openInstallDialog(context),
                isInstalling: _isInstalling,
              )
            else ...[
              // Status Card
              SqmStatusCard(
                routerId: routerId,
                sqmState: sqmState,
                overview: overview,
                onRefresh: _refresh,
              ),

              if (overview.hasAnyFlowOffloading) ...[
                const SizedBox(height: LuciSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.colorScheme.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: theme.colorScheme.error,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n?.modSqmFlowOffloadWarningBanner ??
                              'Flow offloading is active in Firewall. Forwarded traffic will bypass SQM queue shaping.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: LuciSpacing.md),

              // Queue Instances Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n?.modSqmQueuesTitle ?? 'Configured Queues',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _addNewQueue(overview),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(
                      l10n?.modSqmBtnAddQueue ?? 'Add Queue',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),

              if (overview.queues.isEmpty)
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.speed_rounded,
                          size: 40,
                          color: LuciStatusColors.inactive,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n?.modSqmNoQueuesTitle ?? 'No Queues Configured',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n?.modSqmNoQueuesDesc ??
                              'Add a queue on your WAN interface to start mitigating bufferbloat.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => _addNewQueue(overview),
                          icon: const Icon(Icons.add_rounded),
                          label: Text(l10n?.modSqmBtnAddQueue ?? 'Add Queue'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...overview.queues.map(
                  (q) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SqmQueueCard(
                      key: ValueKey(q.name),
                      queue: q,
                      routerId: routerId,
                      sqmState: sqmState,
                      overview: overview,
                      availableInterfaces: overview.networkInterfaces,
                      availableQdiscs: overview.availableQdiscs,
                      availableScripts: overview.availableScripts,
                      hasFlowOffloading: overview.hasAnyFlowOffloading,
                      onSaved: _refresh,
                      onDeleted: _refresh,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoveryErrorView(
    BuildContext context,
    AppLocalizations? l10n,
    ThemeData theme,
    String errorMessage,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 40,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: LuciSpacing.md),
            Text(
              l10n?.sqmDiscoveryErrorTitle ?? 'Unable to check SQM status',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: LuciSpacing.xs),
            Text(
              l10n?.sqmDiscoveryErrorDesc ??
                  'Router communication failed or returned an incomplete response.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: LuciSpacing.lg),
            FilledButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(l10n?.sqmRetryDiscovery ?? 'Retry Discovery'),
            ),
          ],
        ),
      ),
    );
  }
}
