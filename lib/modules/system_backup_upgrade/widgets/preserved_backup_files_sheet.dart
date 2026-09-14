// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/utils/os_platform_integration.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';

/// Interactive modal sheet to view, search, copy, and edit preserved backup files (sysupgrade -l & /etc/sysupgrade.conf)
/// with full Android, Tablet, Chromebook, and edge-case compatibility.
class PreservedBackupFilesSheet extends StatefulWidget {
  final AppState appState;
  final String initialFileList;
  final String initialConfContent;

  const PreservedBackupFilesSheet({
    super.key,
    required this.appState,
    required this.initialFileList,
    required this.initialConfContent,
  });

  static Future<void> show(
    BuildContext context, {
    required AppState appState,
    required String initialFileList,
    required String initialConfContent,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.45,
        builder: (context, scrollController) => PreservedBackupFilesSheet(
          appState: appState,
          initialFileList: initialFileList,
          initialConfContent: initialConfContent,
        ),
      ),
    );
  }

  @override
  State<PreservedBackupFilesSheet> createState() =>
      _PreservedBackupFilesSheetState();
}

class _PreservedBackupFilesSheetState extends State<PreservedBackupFilesSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _searchController;
  late TextEditingController _newPathController;
  late TextEditingController _confTextController;

  late String _fileListRaw;
  late String _confContentRaw;
  late String _initialConfContentRaw;

  List<String> _preservedPaths = [];
  List<String> _customConfPaths = [];
  List<String> _initialCustomConfPaths = [];

  bool _isRefreshing = false;
  bool _isSaving = false;
  bool _isRawMode = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController = TextEditingController();
    _newPathController = TextEditingController();

    _fileListRaw = widget.initialFileList;
    _confContentRaw = widget.initialConfContent;
    _initialConfContentRaw = widget.initialConfContent;
    _confTextController = TextEditingController(text: _confContentRaw);

    _parseData(updateInitial: true);

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });

    _confTextController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _newPathController.dispose();
    _confTextController.dispose();
    super.dispose();
  }

  void _parseData({bool updateInitial = false}) {
    // Parse sysupgrade -l paths
    _preservedPaths = _fileListRaw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !e.startsWith('#'))
        .toList();

    // Parse /etc/sysupgrade.conf custom entries
    _customConfPaths = _confContentRaw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !e.startsWith('#'))
        .toList();

    if (updateInitial) {
      _initialConfContentRaw = _confContentRaw;
      _initialCustomConfPaths = List<String>.from(_customConfPaths);
    }
  }

  bool get _hasUnsavedChanges {
    if (_isSaving) return false;
    if (_isRawMode) {
      return _confTextController.text.trim() != _initialConfContentRaw.trim();
    } else {
      final currentJoined = _customConfPaths.join('\n');
      final initialJoined = _initialCustomConfPaths.join('\n');
      return currentJoined != initialJoined;
    }
  }

  Future<bool> _confirmDiscardIfDirty() async {
    if (!_hasUnsavedChanges) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Text('Discard Unsaved Changes?'),
          ],
        ),
        content: const Text(
          'You have unsaved edits to /etc/sysupgrade.conf. Are you sure you want to exit without saving?',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Editing'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Discard'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: () async {
              Navigator.pop(ctx, false);
              await _saveCustomConfToRouter();
            },
            icon: const Icon(Icons.save_rounded, size: 16),
            label: const Text('Save & Apply'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<void> _refreshFromRouter() async {
    if (_hasUnsavedChanges) {
      final canProceed = await _confirmDiscardIfDirty();
      if (!canProceed) return;
    }

    setState(() => _isRefreshing = true);
    await OsPlatformIntegration.triggerHaptic(OsHapticType.light);

    try {
      String? freshList = await widget.appState.executeRouterCommandOutput(
        'sh',
        ['-c', 'sysupgrade -l'],
      );
      freshList ??= await widget.appState.executeRouterCommandOutput(
        'sysupgrade',
        ['-l'],
      );
      freshList ??= await widget.appState.executeRouterCommandOutput(
        '/sbin/sysupgrade',
        ['-l'],
      );

      String? freshConf = await widget.appState.executeRouterCommandOutput(
        'cat',
        ['/etc/sysupgrade.conf'],
      );
      freshConf ??= '';

      if (mounted) {
        setState(() {
          _fileListRaw = freshList ?? _fileListRaw;
          _confContentRaw = freshConf ?? _confContentRaw;
          _confTextController.text = _confContentRaw;
          _parseData(updateInitial: true);
          _isRefreshing = false;
        });
        context.showToastSuccess(
          'Refreshed preserved backup files from router.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRefreshing = false);
        context.showToastError(
          'Failed to refresh backup file list.',
          subtitle: e.toString(),
        );
      }
    }
  }

  Future<void> _saveCustomConfToRouter() async {
    setState(() => _isSaving = true);
    await OsPlatformIntegration.triggerHaptic(OsHapticType.medium);

    String newContent = '';
    if (_isRawMode) {
      newContent = _confTextController.text.trim();
    } else {
      final lines = <String>[];
      lines.add('## Keep custom files across sysupgrade updates');
      lines.addAll(_customConfPaths);
      newContent = lines.join('\n');
    }

    try {
      final escContent = newContent.replaceAll("'", "'\\''");
      final cmd = "cat << 'EOF' > /etc/sysupgrade.conf\n$escContent\nEOF";
      final success = await widget.appState.executeRouterCommand('sh', [
        '-c',
        cmd,
      ]);

      if (success) {
        _confContentRaw = newContent;
        _confTextController.text = newContent;
        _parseData(updateInitial: true);

        // Refresh sysupgrade -l list to show newly preserved files
        String? freshList = await widget.appState.executeRouterCommandOutput(
          'sh',
          ['-c', 'sysupgrade -l'],
        );
        if (freshList != null && freshList.trim().isNotEmpty) {
          _fileListRaw = freshList;
          _parseData(updateInitial: true);
        }

        if (mounted) {
          setState(() => _isSaving = false);
          context.showToastSuccess('Saved /etc/sysupgrade.conf to router!');
        }
      } else {
        if (mounted) {
          setState(() => _isSaving = false);
          context.showToastError(
            'Failed to save /etc/sysupgrade.conf to router.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        context.showToastError(
          'Error saving configuration',
          subtitle: e.toString(),
        );
      }
    }
  }

  void _addCustomPath() {
    final rawPath = _newPathController.text.trim();
    if (rawPath.isEmpty) return;

    if (!rawPath.startsWith('/')) {
      context.showToastInfo(
        'File path must start with "/" (e.g. /etc/cloudflared/config.yml)',
      );
      return;
    }

    if (_customConfPaths.contains(rawPath)) {
      context.showToastInfo('Path is already included in /etc/sysupgrade.conf');
      return;
    }

    setState(() {
      _customConfPaths.add(rawPath);
      _newPathController.clear();
      _confContentRaw = _customConfPaths.join('\n');
      _confTextController.text = _confContentRaw;
    });
    context.showToastSuccess(
      'Added path to list. Remember to tap "Save to Router".',
    );
  }

  void _removeCustomPath(String path) {
    setState(() {
      _customConfPaths.remove(path);
      _confContentRaw = _customConfPaths.join('\n');
      _confTextController.text = _confContentRaw;
    });
    context.showToastInfo('Removed "$path". Tap "Save to Router" to apply.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final filteredPaths = _preservedPaths.where((path) {
      if (_searchQuery.isEmpty) return true;
      return path.toLowerCase().contains(_searchQuery);
    }).toList();

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _confirmDiscardIfDirty();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          children: [
            // Drag Handle
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Modal Title Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.folder_special_rounded,
                      color: colorScheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Preserved Backup Files',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Files retained across firmware upgrades (sysupgrade)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh from Router',
                    icon: _isRefreshing
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.primary,
                            ),
                          )
                        : const Icon(Icons.refresh_rounded),
                    onPressed: _isRefreshing ? null : _refreshFromRouter,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () async {
                      final canExit = await _confirmDiscardIfDirty();
                      if (canExit && context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Tab Bar
            TabBar(
              controller: _tabController,
              labelColor: colorScheme.primary,
              unselectedLabelColor: colorScheme.onSurfaceVariant,
              indicatorColor: colorScheme.primary,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.list_alt_rounded, size: 18),
                      const SizedBox(width: 6),
                      Text('Preserved (${_preservedPaths.length})'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.edit_note_rounded, size: 18),
                      const SizedBox(width: 6),
                      const Text('Edit /etc/sysupgrade.conf'),
                    ],
                  ),
                ),
              ],
            ),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // TAB 1: Preserved File List (sysupgrade -l)
                  _buildPreservedListTab(
                    context,
                    colorScheme,
                    theme,
                    filteredPaths,
                  ),

                  // TAB 2: Edit Custom Config (/etc/sysupgrade.conf)
                  _buildEditConfTab(context, colorScheme, theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreservedListTab(
    BuildContext context,
    ColorScheme colorScheme,
    ThemeData theme,
    List<String> filteredPaths,
  ) {
    return Column(
      children: [
        // Search & Copy Header
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search preserved files...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colorScheme.outlineVariant),
                    ),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  final textToCopy = filteredPaths.join('\n');
                  unawaited(
                    OsPlatformIntegration.copyToClipboard(
                      context,
                      text: textToCopy,
                      label: 'Preserved Files List',
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy All', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),

        // Scrollable List
        Expanded(
          child: filteredPaths.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 40,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'No preserved files matching "$_searchQuery"'
                            : 'No preserved backup files returned from router.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  itemCount: filteredPaths.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (ctx, index) {
                    final path = filteredPaths[index];
                    final isCustom = _customConfPaths.any(
                      (cp) => path.startsWith(cp),
                    );

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.3,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            path.endsWith('/')
                                ? Icons.folder_outlined
                                : Icons.insert_drive_file_outlined,
                            size: 18,
                            color: isCustom ? Colors.teal : colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SelectableText(
                              path,
                              style: GoogleFonts.geistMono(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (isCustom)
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.teal.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: Colors.teal.withValues(alpha: 0.3),
                                ),
                              ),
                              child: const Text(
                                'Custom',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal,
                                ),
                              ),
                            ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Copy Path',
                            onPressed: () {
                              unawaited(
                                OsPlatformIntegration.copyToClipboard(
                                  context,
                                  text: path,
                                  label: 'File Path',
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEditConfTab(
    BuildContext context,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final hasUnsaved = _hasUnsavedChanges;

    return Column(
      children: [
        // Quick Add Path Header Bar
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newPathController,
                      decoration: InputDecoration(
                        hintText: 'Add path (e.g. /etc/cloudflared/config.yml)',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: colorScheme.outlineVariant,
                          ),
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.4),
                      ),
                      onSubmitted: (_) => _addCustomPath(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _addCustomPath,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        'Mode: ${_isRawMode ? "Raw Editor" : "Path List"} (${_customConfPaths.length} custom paths)',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (hasUnsaved) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.4),
                            ),
                          ),
                          child: const Text(
                            'Unsaved Changes',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _isRawMode = !_isRawMode;
                      });
                    },
                    icon: Icon(
                      _isRawMode ? Icons.list_rounded : Icons.code_rounded,
                      size: 16,
                    ),
                    label: Text(
                      _isRawMode ? 'Switch to List' : 'Switch to Code Editor',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Main Editor Area
        Expanded(
          child: _isRawMode
              ? Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: TextField(
                    controller: _confTextController,
                    maxLines: null,
                    expands: true,
                    style: GoogleFonts.geistMono(fontSize: 12),
                    decoration: const InputDecoration(
                      hintText:
                          '# Add files or directories to preserve across sysupgrade\n/etc/config/custom_app\n/etc/ssl/certs',
                      border: InputBorder.none,
                    ),
                  ),
                )
              : _customConfPaths.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.note_add_outlined,
                        size: 38,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No custom entries in /etc/sysupgrade.conf',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Add file/directory paths above to preserve them across updates.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _customConfPaths.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (ctx, index) {
                    final path = _customConfPaths[index];
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.3,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.tune_rounded,
                            size: 16,
                            color: Colors.teal,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SelectableText(
                              path,
                              style: GoogleFonts.geistMono(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: Colors.redAccent,
                            ),
                            tooltip: 'Remove Path',
                            onPressed: () => _removeCustomPath(path),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),

        // Bottom Action Bar: Save & Apply to Router (Context-Aware Button)
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _isSaving
                    ? colorScheme.primary
                    : hasUnsaved
                    ? Colors.teal
                    : colorScheme.surfaceContainerHighest,
                foregroundColor: _isSaving || hasUnsaved
                    ? Colors.white
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: hasUnsaved ? 2 : 0,
              ),
              onPressed: (_isSaving || !hasUnsaved)
                  ? null
                  : _saveCustomConfToRouter,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      hasUnsaved
                          ? Icons.save_rounded
                          : Icons.check_circle_outline_rounded,
                      size: 18,
                    ),
              label: Text(
                _isSaving
                    ? 'Saving & Applying to Router...'
                    : hasUnsaved
                    ? 'Save & Apply to Router'
                    : 'No Unsaved Changes (Saved)',
              ),
            ),
          ),
        ),
      ],
    );
  }
}
