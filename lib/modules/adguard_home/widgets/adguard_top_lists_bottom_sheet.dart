// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import '../models/adguard_models.dart';

/// Modal bottom sheet presenting complete lists of Top Blocked Domains,
/// Top Queried Domains, and Top Clients with search and ranking badges.
class AdGuardTopListsBottomSheet extends StatefulWidget {
  final AdGuardStats? stats;
  final int initialTabIndex;

  const AdGuardTopListsBottomSheet({
    super.key,
    required this.stats,
    this.initialTabIndex = 0,
  });

  /// Opens the modal bottom sheet gliding up from the bottom of the screen.
  static Future<void> show(
    BuildContext context, {
    required AdGuardStats? stats,
    int initialTabIndex = 0,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => AdGuardTopListsBottomSheet(
        stats: stats,
        initialTabIndex: initialTabIndex,
      ),
    );
  }

  @override
  State<AdGuardTopListsBottomSheet> createState() =>
      _AdGuardTopListsBottomSheetState();
}

class _AdGuardTopListsBottomSheetState extends State<AdGuardTopListsBottomSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final topBlocked = widget.stats?.topBlockedDomains ?? const [];
    final topQueried = widget.stats?.topQueriedDomains ?? const [];
    final topClients = widget.stats?.topClients ?? const [];

    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return Container(
      key: const Key('agh_top_lists_bottom_sheet'),
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
            child: Row(
              children: [
                Icon(
                  Icons.leaderboard_outlined,
                  size: 22,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n?.aghTopLists ?? 'Top Activity',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('agh_top_lists_sheet_close_button'),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: l10n?.actionClose ?? 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // TabBar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TabBar(
              controller: _tabController,
              isScrollable: false,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              tabs: [
                Tab(
                  key: const Key('agh_top_sheet_tab_blocked'),
                  text:
                      '${l10n?.aghTopBlocked ?? 'Blocked'} (${topBlocked.length})',
                ),
                Tab(
                  key: const Key('agh_top_sheet_tab_queried'),
                  text:
                      '${l10n?.aghTopQueried ?? 'Queried'} (${topQueried.length})',
                ),
                Tab(
                  key: const Key('agh_top_sheet_tab_clients'),
                  text:
                      '${l10n?.aghTopClients ?? 'Clients'} (${topClients.length})',
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 4.0,
            ),
            child: TextField(
              key: const Key('agh_top_lists_sheet_search_field'),
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                hintText:
                    l10n?.aghSearchDomainsOrClients ??
                    'Search domains or clients...',
                isDense: true,
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.35,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSheetList(
                  context,
                  items: topBlocked
                      .map((e) => (name: e.identifier, count: e.count))
                      .toList(),
                  emptyMessage: l10n?.aghNoData ?? 'No data available',
                  keyPrefix: 'agh_sheet_top_blocked',
                  barColor: Colors.red.shade400,
                ),
                _buildSheetList(
                  context,
                  items: topQueried
                      .map((e) => (name: e.identifier, count: e.count))
                      .toList(),
                  emptyMessage: l10n?.aghNoData ?? 'No data available',
                  keyPrefix: 'agh_sheet_top_queried',
                  barColor: colorScheme.primary,
                ),
                _buildSheetList(
                  context,
                  items: topClients
                      .map((e) => (name: e.identifier, count: e.count))
                      .toList(),
                  emptyMessage: l10n?.aghNoData ?? 'No data available',
                  keyPrefix: 'agh_sheet_top_clients',
                  barColor: Colors.teal.shade400,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSheetList(
    BuildContext context, {
    required List<({String name, int count})> items,
    required String emptyMessage,
    required String keyPrefix,
    required Color barColor,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    final filtered = _searchQuery.isEmpty
        ? items
        : items
              .where((e) => e.name.toLowerCase().contains(_searchQuery))
              .toList();

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 36,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 8),
              Text(
                _searchQuery.isNotEmpty
                    ? (l10n?.aghNoData ?? 'No matching results')
                    : emptyMessage,
                key: Key('${keyPrefix}_empty'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final maxCount = items.fold<int>(
      1,
      (max, item) => item.count > max ? item.count : max,
    );

    return ListView.separated(
      key: Key('${keyPrefix}_list'),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const Divider(height: 12),
      itemBuilder: (context, index) {
        final item = filtered[index];
        final fraction = (item.count / maxCount).clamp(0.0, 1.0);
        // Find original rank in full unfiltered list
        final originalRank = items.indexOf(item) + 1;

        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            Clipboard.setData(ClipboardData(text: item.name));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Copied "${item.name}" to clipboard'),
                duration: const Duration(seconds: 1),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Rank badge
                    Container(
                      width: 26,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: originalRank <= 3
                            ? barColor.withValues(alpha: 0.2)
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#$originalRank',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: originalRank <= 3
                              ? barColor
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.name,
                        key: Key('${keyPrefix}_${index}_name'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${item.count}',
                      key: Key('${keyPrefix}_${index}_count'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: fraction,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(barColor),
                    minHeight: 5,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
