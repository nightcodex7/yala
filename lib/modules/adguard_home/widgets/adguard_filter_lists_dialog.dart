// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import '../controllers/adguard_controller.dart';
import '../models/adguard_models.dart';

/// Interactive modal dialog for viewing, toggling, adding, editing, removing,
/// and refreshing AdGuard Home filter lists (blocklists and allowlists).
class AdGuardFilterListsDialog extends StatefulWidget {
  final AdGuardController controller;

  const AdGuardFilterListsDialog({super.key, required this.controller});

  /// Displays the filter lists management dialog.
  static Future<void> show(
    BuildContext context, {
    required AdGuardController controller,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AdGuardFilterListsDialog(controller: controller),
    );
  }

  @override
  State<AdGuardFilterListsDialog> createState() =>
      _AdGuardFilterListsDialogState();
}

class _AdGuardFilterListsDialogState extends State<AdGuardFilterListsDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _searchController.addListener(() {
      final query = _searchController.text.trim().toLowerCase();
      if (query != _searchQuery) {
        setState(() {
          _searchQuery = query;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String _formatNumber(int number) {
    try {
      return NumberFormat.decimalPattern().format(number);
    } catch (_) {
      return number.toString();
    }
  }

  String _formatTimestamp(String? isoString, AppLocalizations? l10n) {
    if (isoString == null || isoString.isEmpty) {
      return l10n?.aghFilterListNeverUpdated ?? 'Never updated';
    }
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(dt);
      return l10n?.aghFilterListUpdated(dateStr) ?? 'Updated: $dateStr';
    } catch (_) {
      return l10n?.aghFilterListUpdated(isoString) ?? 'Updated: $isoString';
    }
  }

  Future<void> _refreshLists() async {
    final success = await widget.controller.refreshFilterLists();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n?.aghFilterListRefreshSuccess ??
                'Filter lists updated successfully',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _toggleList(AdGuardFilterList list, bool value) async {
    final success = await widget.controller.toggleFilterList(
      list: list,
      enabled: value,
    );
    if (!mounted) return;
    if (success) {
      setState(() {});
    }
  }

  Future<void> _openAddDialog() async {
    final defaultWhitelist = _tabController.index == 1;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => _AddFilterListDialog(
        controller: widget.controller,
        initialWhitelist: defaultWhitelist,
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openEditDialog(AdGuardFilterList list) async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) =>
          _EditFilterListDialog(controller: widget.controller, list: list),
    );
    if (mounted) setState(() {});
  }

  Future<void> _confirmRemoveList(AdGuardFilterList list) async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        key: const Key('agh_delete_confirm_dialog'),
        title: Text(l10n?.aghRemoveFilterList ?? 'Remove Filter List'),
        content: Text(
          l10n?.aghRemoveFilterListConfirm(list.name) ??
              'Are you sure you want to remove "${list.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(MaterialLocalizations.of(dialogCtx).cancelButtonLabel),
          ),
          FilledButton(
            key: const Key('agh_delete_confirm_button'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogCtx).colorScheme.error,
              foregroundColor: Theme.of(dialogCtx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(l10n?.aghRemoveFilterList ?? 'Remove'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final success = await widget.controller.removeFilterList(
      url: list.url.isNotEmpty ? list.url : list.name,
      whitelist: list.whitelist,
    );
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n?.aghFilterListRemoveSuccess ??
                'Filter list removed successfully',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      setState(() {});
    }
  }

  List<AdGuardFilterList> _filterItems(List<AdGuardFilterList> items) {
    if (_searchQuery.isEmpty) return items;
    return items.where((item) {
      return item.name.toLowerCase().contains(_searchQuery) ||
          item.url.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = widget.controller.currentState;

    final blocklists = state.filtering?.filterLists ?? const [];
    final allowlists = state.filtering?.whitelistFilters ?? const [];

    final filteredBlocklists = _filterItems(blocklists);
    final filteredAllowlists = _filterItems(allowlists);

    return Dialog(
      key: const Key('agh_filter_lists_dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_list_rounded,
                    color: colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n?.aghFilterListsTitle ?? 'Filter Lists',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (state.isMutatingFilterLists)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    IconButton(
                      key: const Key('agh_filter_lists_refresh_button'),
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip:
                          l10n?.aghRefreshFilterLists ?? 'Check for Updates',
                      onPressed: _refreshLists,
                    ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Error Banner (dismissible)
            if (state.filterListActionError != null)
              Container(
                key: const Key('agh_filter_list_error_banner'),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colorScheme.error.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: colorScheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.filterListActionError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: colorScheme.onErrorContainer,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        widget.controller.clearFilterListActionError();
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: TextField(
                key: const Key('agh_filter_lists_search_field'),
                controller: _searchController,
                decoration: InputDecoration(
                  hintText:
                      l10n?.aghFilterListsSearch ?? 'Search filter lists…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                          },
                        )
                      : null,
                  isDense: true,
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            // Tab Bar
            TabBar(
              controller: _tabController,
              tabs: [
                Tab(
                  key: const Key('agh_filter_lists_tab_blocklists'),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(l10n?.aghBlocklistsTab ?? 'Blocklists'),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${blocklists.length}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Tab(
                  key: const Key('agh_filter_lists_tab_allowlists'),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(l10n?.aghAllowlistsTab ?? 'Allowlists'),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${allowlists.length}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 1),

            // Tab Contents
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildListTab(
                    items: filteredBlocklists,
                    isWhitelist: false,
                    l10n: l10n,
                    theme: theme,
                    colorScheme: colorScheme,
                    isMutating: state.isMutatingFilterLists,
                  ),
                  _buildListTab(
                    items: filteredAllowlists,
                    isWhitelist: true,
                    l10n: l10n,
                    theme: theme,
                    colorScheme: colorScheme,
                    isMutating: state.isMutatingFilterLists,
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Bottom Actions Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    key: const Key('agh_filter_lists_update_button'),
                    icon: state.isMutatingFilterLists
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded, size: 16),
                    label: Text(
                      l10n?.aghRefreshFilterLists ?? 'Check for Updates',
                    ),
                    onPressed: state.isMutatingFilterLists
                        ? null
                        : _refreshLists,
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    key: const Key('agh_add_filter_list_button'),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(l10n?.aghAddFilterList ?? 'Add Filter List'),
                    onPressed: state.isMutatingFilterLists
                        ? null
                        : _openAddDialog,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListTab({
    required List<AdGuardFilterList> items,
    required bool isWhitelist,
    required AppLocalizations? l10n,
    required ThemeData theme,
    required ColorScheme colorScheme,
    required bool isMutating,
  }) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.filter_list_off_rounded,
                size: 48,
                color: colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                _searchQuery.isNotEmpty
                    ? (l10n?.aghNoData ?? 'No data available')
                    : (l10n?.aghFilterListsEmpty ??
                          'No filter lists configured'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshLists,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: items.length,
        separatorBuilder: (_, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = items[index];
          final itemKey = item.url.isNotEmpty ? item.url : '${item.id}';
          return Container(
            key: Key('agh_filter_list_tile_$itemKey'),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.35,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Title and Switch
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (item.url.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              item.url,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      key: Key('agh_filter_list_toggle_$itemKey'),
                      value: item.enabled,
                      onChanged: isMutating
                          ? null
                          : (val) => _toggleList(item, val),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Bottom row: Rules chip, last updated timestamp, actions
                Row(
                  children: [
                    // Rules count chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isWhitelist
                            ? Colors.teal.withValues(alpha: 0.12)
                            : colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.rule_rounded,
                            size: 13,
                            color: isWhitelist
                                ? Colors.teal.shade700
                                : colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            l10n?.aghFilterListRules(
                                  _formatNumber(item.rulesCount),
                                ) ??
                                '${_formatNumber(item.rulesCount)} rules',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isWhitelist
                                  ? Colors.teal.shade800
                                  : colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Last updated text
                    Expanded(
                      child: Text(
                        _formatTimestamp(item.lastUpdated, l10n),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Edit button
                    IconButton(
                      key: Key('agh_filter_list_edit_$itemKey'),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: l10n?.aghEditFilterList ?? 'Edit',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: isMutating
                          ? null
                          : () => _openEditDialog(item),
                    ),
                    const SizedBox(width: 4),
                    // Delete button
                    IconButton(
                      key: Key('agh_filter_list_delete_$itemKey'),
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: colorScheme.error,
                      ),
                      tooltip: l10n?.aghRemoveFilterList ?? 'Remove',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: isMutating
                          ? null
                          : () => _confirmRemoveList(item),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Curated preset filter lists for quick addition.
class _FilterPreset {
  final String name;
  final String url;
  final bool whitelist;

  const _FilterPreset({
    required this.name,
    required this.url,
    required this.whitelist,
  });
}

const List<_FilterPreset> _curatedPresets = [
  _FilterPreset(
    name: 'AdGuard DNS filter',
    url: 'https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt',
    whitelist: false,
  ),
  _FilterPreset(
    name: 'AdAway Default Blocklist',
    url: 'https://adaway.org/hosts.txt',
    whitelist: false,
  ),
  _FilterPreset(
    name: 'OISD Basic',
    url: 'https://small.oisd.nl',
    whitelist: false,
  ),
  _FilterPreset(
    name: 'Steven Black Unified',
    url: 'https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts',
    whitelist: false,
  ),
  _FilterPreset(
    name: "Peter Lowe's List",
    url:
        'https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext',
    whitelist: false,
  ),
];

/// Modal Dialog for adding a new filter list or allowlist.
class _AddFilterListDialog extends StatefulWidget {
  final AdGuardController controller;
  final bool initialWhitelist;

  const _AddFilterListDialog({
    required this.controller,
    required this.initialWhitelist,
  });

  @override
  State<_AddFilterListDialog> createState() => _AddFilterListDialogState();
}

class _AddFilterListDialogState extends State<_AddFilterListDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late bool _whitelist;
  bool _isSubmitting = false;
  String? _dialogError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _urlController = TextEditingController();
    _whitelist = widget.initialWhitelist;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _applyPreset(_FilterPreset preset) {
    setState(() {
      _nameController.text = preset.name;
      _urlController.text = preset.url;
      _whitelist = preset.whitelist;
      _dialogError = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _dialogError = null;
    });

    final success = await widget.controller.addFilterList(
      name: _nameController.text.trim(),
      url: _urlController.text.trim(),
      whitelist: _whitelist,
    );

    if (!mounted) return;

    if (success) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n?.aghFilterListAddSuccess ?? 'Filter list added successfully',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isSubmitting = false;
        _dialogError =
            widget.controller.currentState.filterListActionError ??
            'Failed to add filter list';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      key: const Key('agh_add_filter_list_dialog'),
      title: Text(l10n?.aghAddFilterList ?? 'Add Filter List'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_dialogError != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 18,
                          color: colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _dialogError!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Presets
                Text(
                  l10n?.aghFilterListPresets ?? 'Curated Presets',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _curatedPresets.map((preset) {
                    final isSelected = _urlController.text == preset.url;
                    return ActionChip(
                      key: Key('agh_filter_list_preset_${preset.name}'),
                      avatar: isSelected
                          ? const Icon(Icons.check_rounded, size: 14)
                          : null,
                      label: Text(
                        preset.name,
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: _isSubmitting
                          ? null
                          : () => _applyPreset(preset),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Type segmented selector
                Text(
                  l10n?.aghFilterListType ?? 'List Type',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment<bool>(
                      value: false,
                      label: Text(l10n?.aghFilterListBlocklist ?? 'Blocklist'),
                      icon: const Icon(Icons.block_rounded, size: 16),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      label: Text(l10n?.aghFilterListAllowlist ?? 'Allowlist'),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                    ),
                  ],
                  selected: {_whitelist},
                  onSelectionChanged: _isSubmitting
                      ? null
                      : (newSelection) {
                          setState(() {
                            _whitelist = newSelection.first;
                          });
                        },
                ),
                const SizedBox(height: 14),

                // Name input
                TextFormField(
                  key: const Key('agh_add_filter_name_input'),
                  controller: _nameController,
                  enabled: !_isSubmitting,
                  decoration: InputDecoration(
                    labelText: l10n?.aghFilterListName ?? 'List Name',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n?.aghFilterListNameRequired ??
                          'Please enter a list name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // URL input
                TextFormField(
                  key: const Key('agh_add_filter_url_input'),
                  controller: _urlController,
                  enabled: !_isSubmitting,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: l10n?.aghFilterListUrl ?? 'List URL',
                    hintText: 'https://...',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n?.aghFilterListUrlRequired ??
                          'Please enter a list URL';
                    }
                    final uri = Uri.tryParse(value.trim());
                    if (uri == null ||
                        (!uri.isScheme('http') && !uri.isScheme('https')) ||
                        uri.host.isEmpty) {
                      return l10n?.aghFilterListInvalidUrl ??
                          'Please enter a valid HTTP or HTTPS URL';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          key: const Key('agh_add_filter_submit_button'),
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n?.aghAddFilterList ?? 'Add'),
        ),
      ],
    );
  }
}

/// Modal Dialog for editing an existing filter list.
class _EditFilterListDialog extends StatefulWidget {
  final AdGuardController controller;
  final AdGuardFilterList list;

  const _EditFilterListDialog({required this.controller, required this.list});

  @override
  State<_EditFilterListDialog> createState() => _EditFilterListDialogState();
}

class _EditFilterListDialogState extends State<_EditFilterListDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late bool _enabled;
  bool _isSubmitting = false;
  String? _dialogError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.list.name);
    _urlController = TextEditingController(
      text: widget.list.url.isNotEmpty ? widget.list.url : widget.list.name,
    );
    _enabled = widget.list.enabled;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _dialogError = null;
    });

    final originalUrl = widget.list.url.isNotEmpty
        ? widget.list.url
        : widget.list.name;

    final success = await widget.controller.editFilterList(
      url: originalUrl,
      name: _nameController.text.trim(),
      newUrl: _urlController.text.trim(),
      enabled: _enabled,
      whitelist: widget.list.whitelist,
    );

    if (!mounted) return;

    if (success) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n?.aghFilterListUpdateSuccess ??
                'Filter list updated successfully',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isSubmitting = false;
        _dialogError =
            widget.controller.currentState.filterListActionError ??
            'Failed to update filter list';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      key: const Key('agh_edit_filter_list_dialog'),
      title: Text(l10n?.aghEditFilterList ?? 'Edit Filter List'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_dialogError != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 18,
                          color: colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _dialogError!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Name input
                TextFormField(
                  key: const Key('agh_edit_filter_name_input'),
                  controller: _nameController,
                  enabled: !_isSubmitting,
                  decoration: InputDecoration(
                    labelText: l10n?.aghFilterListName ?? 'List Name',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n?.aghFilterListNameRequired ??
                          'Please enter a list name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // URL input
                TextFormField(
                  key: const Key('agh_edit_filter_url_input'),
                  controller: _urlController,
                  enabled: !_isSubmitting,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: l10n?.aghFilterListUrl ?? 'List URL',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n?.aghFilterListUrlRequired ??
                          'Please enter a list URL';
                    }
                    final uri = Uri.tryParse(value.trim());
                    if (uri == null ||
                        (!uri.isScheme('http') && !uri.isScheme('https')) ||
                        uri.host.isEmpty) {
                      return l10n?.aghFilterListInvalidUrl ??
                          'Please enter a valid HTTP or HTTPS URL';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Enabled switch
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _enabled
                        ? (l10n?.aghActionEnable ?? 'Enabled')
                        : (l10n?.aghActionDisable ?? 'Disabled'),
                    style: theme.textTheme.bodyMedium,
                  ),
                  value: _enabled,
                  onChanged: _isSubmitting
                      ? null
                      : (val) {
                          setState(() {
                            _enabled = val;
                          });
                        },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          key: const Key('agh_edit_filter_submit_button'),
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(MaterialLocalizations.of(context).saveButtonLabel),
        ),
      ],
    );
  }
}
