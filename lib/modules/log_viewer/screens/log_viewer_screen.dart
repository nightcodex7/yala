// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import '../controllers/log_viewer_controller.dart';
import '../models/log_entry.dart';
import '../models/log_fetch_result.dart';
import '../widgets/log_entry_tile.dart';
import '../widgets/log_filter_bar.dart';

class LogViewerScreen extends ConsumerStatefulWidget {
  const LogViewerScreen({super.key});

  @override
  ConsumerState<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends ConsumerState<LogViewerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _syslogScrollController = ScrollController();
  final ScrollController _kernelScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _syslogScrollController.dispose();
    _kernelScrollController.dispose();
    super.dispose();
  }

  ScrollController get _activeScrollController => _tabController.index == 0
      ? _syslogScrollController
      : _kernelScrollController;

  void _scrollToBottom() {
    if (_activeScrollController.hasClients) {
      _activeScrollController.animateTo(
        _activeScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _scrollToTop() {
    if (_activeScrollController.hasClients) {
      _activeScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _copyFiltered(List<LogEntry> entries) {
    final text = entries.map((e) => e.raw).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    final l10n = AppLocalizations.of(context);
    LuciToastManager.showSuccess(
      context,
      l10n?.logViewerCopied ?? 'Log copied to clipboard',
    );
  }

  Widget _buildResultView({
    required BuildContext context,
    required bool isLoading,
    required LogFetchResult? result,
    required ScrollController scrollController,
    required LogViewerState state,
    required VoidCallback onRetry,
  }) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l10n?.logViewerLoading ?? 'Fetching logs...'),
          ],
        ),
      );
    }

    if (result == null) {
      return Center(
        child: Text(l10n?.logViewerEmpty ?? 'No log entries found'),
      );
    }

    if (result is LogFetchPermissionError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                l10n?.logViewerErrorPermission ??
                    'Permission denied — check RPC ACLs',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l10n?.logViewerRefresh ?? 'Refresh'),
              ),
            ],
          ),
        ),
      );
    }

    if (result is LogFetchBinaryMissing) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.extension_off_outlined,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                l10n?.logViewerErrorBinaryMissing ??
                    'Log utility not found on this router',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l10n?.logViewerRefresh ?? 'Refresh'),
              ),
            ],
          ),
        ),
      );
    }

    if (result is LogFetchTimeout) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.timer_off_outlined,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                l10n?.logViewerErrorTimeout ?? 'Log fetch timed out',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l10n?.logViewerRefresh ?? 'Refresh'),
              ),
            ],
          ),
        ),
      );
    }

    if (result is LogFetchRpcError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                result.message ??
                    l10n?.logViewerErrorGeneric ??
                    'Failed to load logs',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l10n?.logViewerRefresh ?? 'Refresh'),
              ),
            ],
          ),
        ),
      );
    }

    if (result is LogFetchSuccess) {
      final filtered = state.filterEntries(result.entries);
      if (filtered.isEmpty) {
        return Center(
          child: Text(l10n?.logViewerEmpty ?? 'No log entries found'),
        );
      }

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 4.0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${filtered.length} / ${result.entries.length} lines',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  l10n?.logViewerTimestampNote ??
                      'Timestamps reported by router clock',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: filtered.length,
              itemBuilder: (ctx, idx) => LogEntryTile(entry: filtered[idx]),
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appStateProvider.select((s) => s.selectedRouter));
    final routerId = router?.id ?? '';
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(logViewerControllerProvider(routerId));
    final controller = ref.read(logViewerControllerProvider(routerId).notifier);

    // Current visible entries for copy all
    List<LogEntry> currentEntries = [];
    final activeResult = _tabController.index == 0
        ? state.syslogResult
        : state.kernelResult;
    if (activeResult is LogFetchSuccess) {
      currentEntries = state.filterEntries(activeResult.entries);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n?.logViewerTitle ?? 'System & Kernel Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all),
            tooltip: l10n?.logViewerCopyAll ?? 'Copy All',
            onPressed: currentEntries.isNotEmpty
                ? () => _copyFiltered(currentEntries)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n?.logViewerRefresh ?? 'Refresh',
            onPressed: state.isLoading
                ? null
                : () => controller.refreshBoth(context: context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          onTap: (_) => setState(() {}),
          tabs: [
            Tab(text: l10n?.logViewerSyslogTab ?? 'System Log'),
            Tab(text: l10n?.logViewerKernelTab ?? 'Kernel Log'),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'scroll_top',
            tooltip: l10n?.logViewerScrollToTop ?? 'Scroll to top',
            onPressed: _scrollToTop,
            child: const Icon(Icons.keyboard_arrow_up),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.small(
            heroTag: 'scroll_bottom',
            tooltip: l10n?.logViewerScrollToBottom ?? 'Scroll to bottom',
            onPressed: _scrollToBottom,
            child: const Icon(Icons.keyboard_arrow_down),
          ),
        ],
      ),
      body: Column(
        children: [
          LogFilterBar(
            filterText: state.filterText,
            selectedLevel: state.selectedLevel,
            linesToFetch: state.linesToFetch,
            onFilterChanged: controller.setFilterText,
            onLevelChanged: controller.setSelectedLevel,
            onLinesChanged: controller.setLinesToFetch,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildResultView(
                  context: context,
                  isLoading: state.isLoadingSyslog,
                  result: state.syslogResult,
                  scrollController: _syslogScrollController,
                  state: state,
                  onRetry: () => controller.loadSyslog(context: context),
                ),
                _buildResultView(
                  context: context,
                  isLoading: state.isLoadingKernel,
                  result: state.kernelResult,
                  scrollController: _kernelScrollController,
                  state: state,
                  onRetry: () => controller.loadKernelLog(context: context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
