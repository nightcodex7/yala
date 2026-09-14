// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/luci_app_bar.dart';

import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/widgets/luci_loading_states.dart';
import 'package:yet_another_luci_app/widgets/luci_refresh_components.dart';

import 'package:yet_another_luci_app/utils/client_naming_helper.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';
import 'package:yet_another_luci_app/utils/os_platform_integration.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/widgets/add_static_lease_dialog.dart';
import 'package:yet_another_luci_app/widgets/ban_wireless_client_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/modules/dhcp_dns/models/dhcp_dns_info.dart';
import 'package:yet_another_luci_app/modules/wireless_management/models/wireless_info.dart';

class ClientsScreen extends ConsumerStatefulWidget {
  final bool isTabActive;

  const ClientsScreen({
    super.key,
    this.isTabActive = true,
  });

  @override
  ConsumerState<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends ConsumerState<ClientsScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;
  String _searchQuery = '';
  final Set<String> _expandedClientMacs = {};
  final Set<String> _expandedIpv6Macs = {};
  late TextEditingController _searchController;
  Timer? _searchDebounceTimer;
  Timer? _autoRefreshTimer;
  bool _aggregateAllRouters = true;
  List<Client> _cachedClients = [];
  Future<List<Client>>? _clientsFuture;
  String? _lastSelectedRouterId;
  dynamic _lastDashboardUpdated;
  DateTime? _lastFetchTime;
  bool _showOnlyActiveConnected = false;
  ClientCategoryFilter _categoryFilter = ClientCategoryFilter.all;
  bool _hasSeenRestrictedTooltip = true;
  Widget? _lastRenderedScaffold;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchController = TextEditingController();
    _searchController.addListener(_onSearchChanged);
    // Initialize toggle from persisted state
    final initState = ref.read(appStateProvider);
    _aggregateAllRouters = initState.clientsAggregateAllRouters;
    _lastSelectedRouterId = initState.selectedRouter?.id;
    _lastDashboardUpdated = initState.dashboardData?['_lastUpdated'];
    // Pre-populate cached clients so tab switching displays existing data instantly (0ms delay)
    if (initState.clients.isNotEmpty) {
      _cachedClients = List<Client>.from(initState.clients);
    }
    _computeClientsFuture();
    if (widget.isTabActive) {
      _startAutoRefreshTimer();
    }
    _checkRestrictedTooltipState();
  }

  Future<void> _checkRestrictedTooltipState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen =
          prefs.getBool('has_seen_restricted_clients_tooltip') ?? false;
      if (mounted) {
        setState(() {
          _hasSeenRestrictedTooltip = seen;
        });
      }
    } catch (_) {}
  }

  Future<void> _dismissRestrictedTooltip() async {
    setState(() {
      _hasSeenRestrictedTooltip = true;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_seen_restricted_clients_tooltip', true);
    } catch (_) {}
  }

  void _startAutoRefreshTimer() {
    _autoRefreshTimer?.cancel();
    if (!widget.isTabActive) return;
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted && widget.isTabActive) {
        setState(() {
          _computeClientsFuture();
        });
      }
    });
  }

  void _onSearchChanged() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted && _searchQuery != _searchController.text) {
        setState(() {
          _searchQuery = _searchController.text;
        });
      }
    });
  }

  void _computeClientsFuture() {
    _lastFetchTime = DateTime.now();
    final appState = ref.read(appStateProvider);
    final future = _aggregateAllRouters
        ? appState.fetchAggregatedClients()
        : appState.fetchClientsForSelectedRouter();
    _clientsFuture = future;
    future.then((list) {
      if (mounted) {
        setState(() {
          _cachedClients = list;
        });
      }
    });
  }

  @override
  void didUpdateWidget(ClientsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isTabActive != oldWidget.isTabActive) {
      if (widget.isTabActive) {
        _lastRenderedScaffold = null;
        final now = DateTime.now();
        final shouldFetch = _lastFetchTime == null ||
            now.difference(_lastFetchTime!) > const Duration(seconds: 15) ||
            _cachedClients.isEmpty;
        if (shouldFetch) {
          _computeClientsFuture();
        }
        _startAutoRefreshTimer();
      } else {
        _autoRefreshTimer?.cancel();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRefreshTimer?.cancel();
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (widget.isTabActive &&
          (_autoRefreshTimer == null || !_autoRefreshTimer!.isActive)) {
        _startAutoRefreshTimer();
        _computeClientsFuture();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _autoRefreshTimer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final watchedAppState = ref.watch(appStateProvider);
    if (watchedAppState.requestedClientCategoryFilter != null) {
      final reqFilter = watchedAppState.requestedClientCategoryFilter!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _categoryFilter = reqFilter;
          });
        }
        watchedAppState.requestedClientCategoryFilter = null;
      });
    }
    // Recompute future when selected router changes or (if active) dashboard data timestamp changes
    final currentId = watchedAppState.selectedRouter?.id;
    if (currentId != _lastSelectedRouterId) {
      _lastRenderedScaffold = null;
    }
    if (!widget.isTabActive && _lastRenderedScaffold != null) {
      return _lastRenderedScaffold!;
    }

    final lastUpdated = watchedAppState.dashboardData?['_lastUpdated'];
    if (currentId != _lastSelectedRouterId ||
        (widget.isTabActive && lastUpdated != _lastDashboardUpdated)) {
      _lastSelectedRouterId = currentId;
      _lastDashboardUpdated = lastUpdated;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            (widget.isTabActive || currentId != _lastSelectedRouterId)) {
          setState(() {
            _computeClientsFuture();
          });
        }
      });
    }
    Future<List<Client>>? future = _clientsFuture;
    final scaffold = FutureBuilder<List<Client>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          _cachedClients = snapshot.data!;
        }
        final aggregatedClients = (snapshot.hasData && snapshot.data != null)
            ? snapshot.data!
            : _cachedClients;
        final appState = watchedAppState;
        final hasDumbApContext =
            appState.hasDumbAp ||
            appState.routers.length > 1 ||
            appState.clients.any((c) => c.isDumbApClient) ||
            aggregatedClients.any((c) => c.isDumbApClient) ||
            _cachedClients.any((c) => c.isDumbApClient) ||
            _categoryFilter == ClientCategoryFilter.dumbAp;
        return Scaffold(
          appBar: const LuciAppBar(title: 'Clients'),
          body: Stack(
            children: [
              LuciPullToRefresh(
                onRefresh: () async {
                  // Trigger a refresh by re-fetching dashboard data for selected router
                  await ref.read(appStateProvider).fetchDashboardData();
                  setState(() {
                    _computeClientsFuture();
                  });
                },
                child: Builder(
                  builder: (context) {
                    final appState = ref.watch(appStateProvider);
                    final isLoading =
                        snapshot.connectionState == ConnectionState.waiting &&
                        (aggregatedClients.isEmpty);
                    final dashboardError = appState.dashboardError;

                    if (isLoading) {
                      return Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: LuciSpacing.md,
                        ),
                        child: Column(
                          children: [
                            SizedBox(height: LuciSpacing.md),
                            // Search bar skeleton
                            LuciSkeleton(
                              width: double.infinity,
                              height: 56,
                              borderRadius: BorderRadius.circular(
                                LuciSpacing.sm,
                              ),
                            ),
                            SizedBox(height: LuciSpacing.md),
                            // Client list skeletons
                            Expanded(
                              child: ListView.separated(
                                itemCount: 6,
                                separatorBuilder: (context, index) =>
                                    SizedBox(height: LuciSpacing.sm),
                                itemBuilder: (context, index) =>
                                    LuciListItemSkeleton(
                                      showLeading: true,
                                      showTrailing: true,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    if (dashboardError != null && aggregatedClients.isEmpty) {
                      return LuciErrorDisplay(
                        title: 'Failed to Load Clients',
                        message:
                            'Could not connect to the router. Please check your network connection and the router\'s IP address.',
                        actionLabel: 'Retry',
                        onAction: () =>
                            ref.read(appStateProvider).fetchDashboardData(),
                        icon: Icons.wifi_off_rounded,
                      );
                    }

                    final clients = aggregatedClients;

                    // Include synthetic client entries for banned/paused MACs that are not in aggregatedClients
                    final allBannedMacs = <String>{
                      ...appState.bannedWirelessMacs,
                      ...appState.pausedInternetMacs,
                    };

                    final extraBannedClients = <Client>[];
                    if (allBannedMacs.isNotEmpty) {
                      final existingMacs = clients
                          .map((c) => c.normalizedMac)
                          .toSet();
                      for (final mac in allBannedMacs) {
                        final normMac = mac.toUpperCase().replaceAll('-', ':');
                        if (!existingMacs.contains(normMac)) {
                          extraBannedClients.add(
                            Client(
                              ipAddress: 'N/A',
                              macAddress: normMac,
                              hostname: normMac,
                              isConnected: false,
                              connectionType: ConnectionType.wireless,
                            ),
                          );
                        }
                      }
                    }

                    final guestSsids = <String>{};
                    final guestIfaces = <String>{};
                    if (watchedAppState.dashboardData != null) {
                      final overview = WirelessOverview.fromDashboardData(
                        watchedAppState.dashboardData,
                        isReviewerMode: watchedAppState.reviewerModeEnabled,
                      );
                      for (final r in overview.radios) {
                        for (final i in r.interfaces) {
                          if (i.isGuestInterface(
                            watchedAppState.customGuestSections,
                            watchedAppState.excludedGuestSections,
                          )) {
                            if (i.ssid.isNotEmpty) {
                              guestSsids.add(i.ssid);
                            }
                            if (i.sectionName.isNotEmpty) {
                              guestIfaces.add(i.sectionName);
                            }
                            if (i.ifName.isNotEmpty) {
                              guestIfaces.add(i.ifName);
                            }
                          }
                        }
                      }
                    }

                    final List<Client> allClientsForView =
                        extraBannedClients.isEmpty
                            ? clients
                            : [...clients, ...extraBannedClients];

                    final query = _searchQuery.trim().toLowerCase();
                    final hasQuery = query.isNotEmpty;
                    final hasBannedOrPaused = allBannedMacs.isNotEmpty;

                    final filteredClients = allClientsForView.where((client) {
                      final isBannedOrPaused = hasBannedOrPaused &&
                          allBannedMacs.contains(client.normalizedMac);

                      if (_categoryFilter == ClientCategoryFilter.banned) {
                        if (!isBannedOrPaused) return false;
                      } else {
                        // Exclude banned/paused clients from Total, Wired, Wireless, Dumb AP options
                        if (isBannedOrPaused) return false;

                        if (_showOnlyActiveConnected && !client.isConnected) {
                          return false;
                        }
                        if (_categoryFilter == ClientCategoryFilter.wired &&
                            (!client.isConnected ||
                                client.connectionType !=
                                    ConnectionType.wired)) {
                          return false;
                        }
                        if (_categoryFilter == ClientCategoryFilter.wireless &&
                            (!client.isConnected ||
                                client.connectionType !=
                                    ConnectionType.wireless)) {
                          return false;
                        }
                        if (_categoryFilter == ClientCategoryFilter.dumbAp &&
                            !client.isDumbApClient) {
                          return false;
                        }
                      }

                      if (!hasQuery) return true;

                      return client.displayName.toLowerCase().contains(query) ||
                          client.ipAddress.contains(query) ||
                          client.normalizedMac.toLowerCase().contains(query) ||
                          client.hostname.toLowerCase().contains(query) ||
                          (client.vendor != null &&
                              client.vendor!.toLowerCase().contains(query)) ||
                          (client.dnsName != null &&
                              client.dnsName!.toLowerCase().contains(query)) ||
                          (client.ssid != null &&
                              client.ssid!.toLowerCase().contains(query)) ||
                          (client.apName != null &&
                              client.apName!.toLowerCase().contains(query));
                    }).toList();

                    final clientMacToIndex = <String, int>{
                      for (int i = 0; i < filteredClients.length; i++)
                        filteredClients[i].macAddress: i,
                    };

                    return Column(
                      children: [
                        if (!_hasSeenRestrictedTooltip)
                          Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 6.0,
                            ),
                            padding: const EdgeInsets.all(12.0),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer.withValues(
                                alpha: 0.7,
                              ),
                              borderRadius: BorderRadius.circular(16.0),
                              border: Border.all(
                                color: colorScheme.primary.withValues(
                                  alpha: 0.3,
                                ),
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary.withValues(
                                      alpha: 0.15,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.shield_rounded,
                                    color: colorScheme.primary,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Banned Clients Hub',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12.5,
                                          color: colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'All banned Wi-Fi devices and internet-paused clients are automatically moved to the Banned Clients section. Tap the "Banned" count in the summary bar to view and manage them.',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: colorScheme.onPrimaryContainer
                                              .withValues(alpha: 0.85),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: _dismissRestrictedTooltip,
                                  tooltip: 'Dismiss hint',
                                ),
                              ],
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 6.0,
                          ),
                          child: SizedBox(
                            height: 40,
                            child: TextField(
                              autofocus: false,
                              controller: _searchController,
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurface,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12.0,
                                  vertical: 0.0,
                                ),
                                hintText: 'Search by name, IP, MAC, vendor...',
                                prefixIcon: Icon(
                                  Icons.search,
                                  size: 19,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                prefixIconConstraints: const BoxConstraints(
                                  minWidth: 38,
                                  minHeight: 38,
                                ),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        padding: EdgeInsets.zero,
                                        iconSize: 18,
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          setState(() {
                                            _searchController.clear();
                                          });
                                        },
                                        tooltip: 'Clear search',
                                      )
                                    : null,
                                suffixIconConstraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                                filled: true,
                                fillColor: colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.65),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14.0),
                                  borderSide: BorderSide.none,
                                ),
                                hintStyle: TextStyle(
                                  fontSize: 13,
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 16.0,
                            right: 16.0,
                            bottom: 6.0,
                          ),
                          child: Row(
                            children: [
                              if (hasDumbApContext) ...[
                                Expanded(
                                  child: _buildFilterChip(
                                    icon: _showOnlyActiveConnected
                                        ? Icons.wifi_tethering
                                        : Icons.devices_other,
                                    label: 'Active Connected Only',
                                    isSelected: _showOnlyActiveConnected,
                                    onTap: () {
                                      setState(() {
                                        _showOnlyActiveConnected =
                                            !_showOnlyActiveConnected;
                                      });
                                    },
                                    colorScheme: colorScheme,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildFilterChip(
                                    icon: Icons.settings_input_antenna_rounded,
                                    label: 'Show Dumb AP Clients',
                                    isSelected:
                                        _categoryFilter ==
                                        ClientCategoryFilter.dumbAp,
                                    onTap: () {
                                      setState(() {
                                        _categoryFilter =
                                            _categoryFilter ==
                                                ClientCategoryFilter.dumbAp
                                            ? ClientCategoryFilter.all
                                            : ClientCategoryFilter.dumbAp;
                                      });
                                    },
                                    colorScheme: colorScheme,
                                  ),
                                ),
                              ] else ...[
                                _buildFilterChip(
                                  icon: _showOnlyActiveConnected
                                      ? Icons.wifi_tethering
                                      : Icons.devices_other,
                                  label: 'Active Connected Only',
                                  isSelected: _showOnlyActiveConnected,
                                  onTap: () {
                                    setState(() {
                                      _showOnlyActiveConnected =
                                          !_showOnlyActiveConnected;
                                    });
                                  },
                                  colorScheme: colorScheme,
                                ),
                              ],
                            ],
                          ),
                        ),
                        _buildClientSummaryRow(
                          clients,
                          colorScheme,
                          theme.textTheme,
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: filteredClients.isEmpty
                              ? LuciEmptyState(
                                  title:
                                      _categoryFilter ==
                                          ClientCategoryFilter.banned
                                      ? 'No Banned Clients'
                                      : (_categoryFilter ==
                                                ClientCategoryFilter.dumbAp
                                            ? 'No Dumb AP Clients'
                                            : (_searchQuery.isEmpty
                                                  ? 'No Active Clients Found'
                                                  : 'No Matching Clients')),
                                  message:
                                      _categoryFilter ==
                                          ClientCategoryFilter.banned
                                      ? 'No clients are currently banned from Wi-Fi or internet access.'
                                      : (_categoryFilter ==
                                                ClientCategoryFilter.dumbAp
                                            ? 'No clients are currently associated with the secondary Access Point.'
                                            : (_searchQuery.isEmpty
                                                  ? 'No clients are currently connected to the router. Pull down to refresh the list.'
                                                  : 'No clients match your search criteria. Try a different search term.')),
                                  icon:
                                      _categoryFilter ==
                                          ClientCategoryFilter.banned
                                      ? Icons.shield_outlined
                                      : (_categoryFilter ==
                                                ClientCategoryFilter.dumbAp
                                            ? Icons
                                                  .settings_input_antenna_rounded
                                            : Icons.people_outline),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.only(
                                    bottom: 100,
                                  ),
                                  // ignore: deprecated_member_use
                                  cacheExtent: 500.0,
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior
                                          .onDrag,
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                      // ignore: deprecated_member_use
                                      findChildIndexCallback: (Key key) {
                                        if (key is ValueKey<String>) {
                                          return clientMacToIndex[key.value];
                                        }
                                        return null;
                                      },
                                      separatorBuilder: (context, idx) =>
                                          const SizedBox(height: 4),
                                      itemCount: filteredClients.length,
                                      itemBuilder: (context, index) {
                                        final client = filteredClients[index];
                                        final isExpanded = _expandedClientMacs
                                            .contains(client.macAddress);

                                        final isIpv6Expanded = _expandedIpv6Macs
                                            .contains(client.macAddress);
                                        return RepaintBoundary(
                                          key: ValueKey<String>(
                                            client.macAddress,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16.0,
                                              vertical: 8.0,
                                            ),
                                            child: _UnifiedClientCard(
                                              client: client,
                                              isExpanded: isExpanded,
                                              isIpv6Expanded: isIpv6Expanded,
                                              guestSsids: guestSsids,
                                              guestIfaces: guestIfaces,
                                              allClients: clients,
                                              onRefreshNeeded: () {
                                                setState(() {
                                                  _computeClientsFuture();
                                                });
                                              },
                                          onToggleIpv6: () {
                                            setState(() {
                                              if (isIpv6Expanded) {
                                                _expandedIpv6Macs.remove(
                                                  client.macAddress,
                                                );
                                              } else {
                                                _expandedIpv6Macs.add(
                                                  client.macAddress,
                                                );
                                              }
                                            });
                                          },
                                          onTap: () {
                                            setState(() {
                                              if (isExpanded) {
                                                _expandedClientMacs.remove(
                                                  client.macAddress,
                                                );
                                              } else {
                                                _expandedClientMacs.add(
                                                  client.macAddress,
                                                );
                                              }
                                            });
                                          },
                                        ),
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
            ],
          ),
        );
      },
    );
    _lastRenderedScaffold = scaffold;
    return scaffold;
  }

  Widget _buildFilterChip({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    final activeColor =
        isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant;
    final bgColor = isSelected
        ? colorScheme.primary.withValues(alpha: 0.14)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.45);
    final borderColor = isSelected
        ? colorScheme.primary.withValues(alpha: 0.4)
        : colorScheme.outlineVariant.withValues(alpha: 0.25);

    return Semantics(
      button: true,
      toggled: isSelected,
      label: label,
      child: Material(
        color: bgColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: borderColor, width: 1),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: activeColor),
                const SizedBox(width: 6),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                        color: activeColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClientSummaryRow(
    List<Client> clients,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final appState = ref.watch(appStateProvider);

    int totalCount = 0;
    int wiredCount = 0;
    int wirelessCount = 0;
    int dumbApCount = 0;
    bool hasAnyDumbApClient = false;

    for (final c in clients) {
      if (c.isDumbApClient) {
        hasAnyDumbApClient = true;
      }
      final normMac = c.macAddress.toUpperCase().replaceAll('-', ':');
      if (appState.isWirelessBanned(normMac) ||
          appState.isInternetPaused(normMac)) {
        continue;
      }

      if (!_showOnlyActiveConnected || c.isConnected) {
        totalCount++;
      }
      if (c.isConnected) {
        if (c.connectionType == ConnectionType.wired) {
          wiredCount++;
        } else if (c.connectionType == ConnectionType.wireless) {
          wirelessCount++;
        }
      }
      if (c.isDumbApClient && (!_showOnlyActiveConnected || c.isConnected)) {
        dumbApCount++;
      }
    }

    final bannedCount =
        appState.pausedInternetMacs.length + appState.bannedWirelessMacs.length;

    final hasDumbAp =
        appState.hasDumbAp ||
        appState.routers.length > 1 ||
        hasAnyDumbApClient ||
        _categoryFilter == ClientCategoryFilter.dumbAp;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Expanded(
              child: _buildSummaryItem(
                icon: Icons.devices_rounded,
                label: 'Total',
                count: totalCount,
                color: colorScheme.primary,
                isSelected: _categoryFilter == ClientCategoryFilter.all,
                onTap: () {
                  setState(() {
                    _categoryFilter = ClientCategoryFilter.all;
                  });
                },
                colorScheme: colorScheme,
              ),
            ),
            Container(
              width: 1,
              height: 20,
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
            Expanded(
              child: _buildSummaryItem(
                icon: Icons.lan_outlined,
                label: 'Wired',
                count: wiredCount,
                color: colorScheme.secondary,
                isSelected: _categoryFilter == ClientCategoryFilter.wired,
                onTap: () {
                  setState(() {
                    _categoryFilter = ClientCategoryFilter.wired;
                  });
                },
                colorScheme: colorScheme,
              ),
            ),
            Container(
              width: 1,
              height: 20,
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
            Expanded(
              child: _buildSummaryItem(
                icon: Icons.wifi_rounded,
                label: 'Wireless',
                count: wirelessCount,
                color: colorScheme.tertiary,
                isSelected: _categoryFilter == ClientCategoryFilter.wireless,
                onTap: () {
                  setState(() {
                    _categoryFilter = ClientCategoryFilter.wireless;
                  });
                },
                colorScheme: colorScheme,
              ),
            ),
            if (hasDumbAp) ...[
              Container(
                width: 1,
                height: 20,
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
              Expanded(
                child: _buildSummaryItem(
                  icon: Icons.settings_input_antenna_rounded,
                  label: 'Dumb AP',
                  count: dumbApCount,
                  color: Colors.indigo,
                  isSelected: _categoryFilter == ClientCategoryFilter.dumbAp,
                  onTap: () {
                    setState(() {
                      _categoryFilter = ClientCategoryFilter.dumbAp;
                    });
                  },
                  colorScheme: colorScheme,
                ),
              ),
            ],
            Container(
              width: 1,
              height: 20,
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
            Expanded(
              child: _buildSummaryItem(
                icon: Icons.block_rounded,
                label: 'Banned',
                count: bannedCount,
                color: bannedCount > 0
                    ? Colors.red
                    : colorScheme.onSurfaceVariant,
                isSelected: _categoryFilter == ClientCategoryFilter.banned,
                onTap: () {
                  setState(() {
                    _categoryFilter = ClientCategoryFilter.banned;
                  });
                },
                colorScheme: colorScheme,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final (Color bg, Color fg, Color border) = switch (label) {
      'Total' => (
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
        colorScheme.primary.withValues(alpha: 0.35),
      ),
      'Wired' => (
        colorScheme.secondaryContainer,
        colorScheme.onSecondaryContainer,
        colorScheme.secondary.withValues(alpha: 0.35),
      ),
      'Wireless' => (
        colorScheme.tertiaryContainer,
        colorScheme.onTertiaryContainer,
        colorScheme.tertiary.withValues(alpha: 0.35),
      ),
      'Dumb AP' => (
        Colors.indigo.withValues(alpha: isDark ? 0.3 : 0.12),
        isDark ? Colors.indigo.shade200 : Colors.indigo.shade900,
        Colors.indigo.withValues(alpha: 0.4),
      ),
      'Banned' => (
        Colors.red.withValues(alpha: isDark ? 0.3 : 0.12),
        isDark ? Colors.red.shade200 : Colors.red.shade900,
        Colors.red.withValues(alpha: 0.4),
      ),
      _ => (
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
        colorScheme.primary.withValues(alpha: 0.35),
      ),
    };

    final activeColor = isSelected ? fg : colorScheme.onSurfaceVariant;
    final countColor = isSelected ? fg : colorScheme.onSurface;

    return Material(
      color: isSelected ? bg : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: isSelected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: border, width: 0.8),
                )
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: activeColor),
                const SizedBox(width: 5),
                Text(
                  '$label: ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: activeColor,
                  ),
                ),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: countColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String normalizeMac(String mac) => mac.toUpperCase().replaceAll('-', ':');
}

class _UnifiedClientCard extends StatefulWidget {
  final Client client;
  final bool isExpanded;
  final bool isIpv6Expanded;
  final VoidCallback onTap;
  final VoidCallback? onToggleIpv6;
  final Set<String> guestSsids;
  final Set<String> guestIfaces;
  final List<Client> allClients;
  final VoidCallback onRefreshNeeded;

  const _UnifiedClientCard({
    required this.client,
    required this.isExpanded,
    this.isIpv6Expanded = false,
    required this.onTap,
    this.onToggleIpv6,
    this.guestSsids = const {},
    this.guestIfaces = const {},
    this.allClients = const [],
    required this.onRefreshNeeded,
  });

  @override
  State<_UnifiedClientCard> createState() => _UnifiedClientCardState();
}

class _UnifiedClientCardState extends State<_UnifiedClientCard> {

  // --- Three-state neighbor reachability helpers ---

  /// Opacity for the entire card based on neighbor reachability state.
  double _clientOpacity(Client client) {
    if (!client.isConnected) return 0.55;
    switch (client.neighState) {
      case NeighborReachability.reachable:
        return 1.0;
      case NeighborReachability.stale:
        return 0.75;
      case NeighborReachability.failed:
        return 0.55;
      case NeighborReachability.unknown:
        // /proc/net/arp fallback: use legacy binary behavior
        return client.isConnected ? 1.0 : 0.55;
    }
  }

  /// Status dot color: green (reachable), amber (stale/idle), grey (offline).
  Color _statusDotColor(Client client) {
    if (!client.isConnected) return Colors.grey.shade400;
    switch (client.neighState) {
      case NeighborReachability.reachable:
        return LuciStatusColors.connected;
      case NeighborReachability.stale:
        return LuciStatusColors.warning;
      case NeighborReachability.failed:
        return Colors.grey.shade400;
      case NeighborReachability.unknown:
        return client.isConnected
            ? LuciStatusColors.connected
            : Colors.grey.shade400;
    }
  }

  /// Tooltip describing the connectivity state in plain language.
  String _statusTooltip(Client client) {
    if (!client.isConnected) return 'Client is offline (Lease active)';
    switch (client.neighState) {
      case NeighborReachability.reachable:
        return 'Client is online';
      case NeighborReachability.stale:
        return 'Client is idle (no recent traffic)';
      case NeighborReachability.failed:
        return 'Client is offline (Lease active)';
      case NeighborReachability.unknown:
        return client.isConnected
            ? 'Client is online'
            : 'Client is offline (Lease active)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: widget.isExpanded ? 6 : 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18.0),
        side: BorderSide(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.10),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedScale(
        scale: widget.isExpanded ? 1.01 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: Column(
          children: [
            Opacity(
              opacity: _clientOpacity(widget.client),
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(18.0),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14.0,
                    vertical: 12.0,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Stack(
                        alignment: Alignment.topRight,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10.0),
                            decoration: BoxDecoration(
                              color: widget.client.isConnected
                                  ? colorScheme.primaryContainer
                                  : colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.4),
                              shape: BoxShape.circle,
                              border: widget.client.isConnected
                                  ? Border.all(
                                      color: colorScheme.primary
                                          .withValues(alpha: 0.25),
                                      width: 0.8,
                                    )
                                  : null,
                            ),
                            child: AnimatedScale(
                              scale: widget.isExpanded ? 1.05 : 1.0,
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOutCubic,
                              child: Icon(
                                ClientNamingHelper.getDeviceIcon(widget.client),
                                color: widget.client.isConnected
                                    ? colorScheme.onPrimaryContainer
                                    : colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.7),
                                size: 20,
                                semanticLabel: 'Client icon',
                              ),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Tooltip(
                              message: _statusTooltip(widget.client),
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: _statusDotColor(widget.client),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: colorScheme.surface,
                                    width: 1.8,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.client.displayName,
                              style: LuciTextStyles.cardTitle(context),
                              semanticsLabel:
                                  'Client name: ${widget.client.displayName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _buildMinimalClientSubtitle(widget.client),
                              style: LuciTextStyles.cardSubtitle(context),
                              semanticsLabel:
                                  'Client details: ${_buildMinimalClientSubtitle(widget.client)}',
                            ),
                            if (widget.client.vendor != null &&
                                widget.client.vendor!.isNotEmpty)
                              Text(
                                widget.client.vendor!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurface.withValues(
                                    alpha: 0.65,
                                  ),
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                semanticsLabel:
                                    'Vendor: ${widget.client.vendor}',
                              ),
                            _buildBadgePills(context, widget.client),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        widget.isExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: colorScheme.onSurfaceVariant,
                        size: 26,
                        semanticLabel: widget.isExpanded
                            ? 'Collapse details'
                            : 'Expand details',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.isExpanded)
              Column(
                children: [
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _buildClientDetails(context, widget.client),
                ],
              ),
          ],
        ),
      ),
    );
  }

  bool _isGuestClient(Client client) {
    if (client.connectionType != ConnectionType.wireless) return false;
    if (client.ssid != null &&
        client.ssid!.isNotEmpty &&
        widget.guestSsids.contains(client.ssid)) {
      return true;
    }
    if (client.wirelessIface != null &&
        client.wirelessIface!.isNotEmpty &&
        widget.guestIfaces.contains(client.wirelessIface)) {
      return true;
    }
    final ssidLower = client.ssid?.toLowerCase() ?? '';
    final ifaceLower = client.wirelessIface?.toLowerCase() ?? '';
    return ssidLower.contains('guest') || ifaceLower.contains('guest');
  }

  Widget _buildBadgePills(BuildContext context, Client client) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appState = AppState.instance;
    final pills = <Widget>[];

    final isGuest = _isGuestClient(client);
    final isPaused = appState.isInternetPaused(client.macAddress);
    final isBanned = appState.isWirelessBanned(client.macAddress);
    final normMac = client.macAddress.toUpperCase().replaceAll('-', ':');
    final isStatic =
        client.isStatic || appState.configuredStaticLeaseMacs.contains(normMac);

    Widget buildPill({
      required String label,
      required IconData icon,
      required Color bg,
      required Color border,
      required Color fg,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: fg,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 1. Connection & SSID Pill
    if (client.isConnected &&
        client.connectionType == ConnectionType.wireless) {
      final labelText = (client.ssid != null && client.ssid!.isNotEmpty)
          ? 'Wi-Fi • ${client.ssid}'
          : 'Wi-Fi';
      pills.add(
        buildPill(
          label: labelText,
          icon: Icons.wifi_rounded,
          bg: colorScheme.primaryContainer,
          border: colorScheme.primary.withValues(alpha: 0.3),
          fg: colorScheme.onPrimaryContainer,
        ),
      );
    } else if (client.isConnected &&
        client.connectionType == ConnectionType.wired) {
      pills.add(
        buildPill(
          label: 'Wired',
          icon: Icons.lan_rounded,
          bg: colorScheme.secondaryContainer,
          border: colorScheme.secondary.withValues(alpha: 0.3),
          fg: colorScheme.onSecondaryContainer,
        ),
      );
    }

    // 2. Static Lease Pill
    if (isStatic) {
      pills.add(
        buildPill(
          label: 'STATIC',
          icon: Icons.push_pin_rounded,
          bg: Colors.teal.shade700.withValues(alpha: 0.15),
          border: Colors.teal.shade600.withValues(alpha: 0.4),
          fg: theme.brightness == Brightness.dark
              ? Colors.teal.shade200
              : Colors.teal.shade800,
        ),
      );
    }

    // 3. Dumb AP Pill
    if (client.isDumbApClient) {
      final apLabel = client.apName != null && client.apName!.isNotEmpty
          ? 'Dumb AP • ${client.apName}'
          : 'Dumb AP';
      pills.add(
        buildPill(
          label: apLabel,
          icon: Icons.settings_input_antenna_rounded,
          bg: Colors.indigo.shade700.withValues(alpha: 0.15),
          border: Colors.indigo.shade600.withValues(alpha: 0.4),
          fg: theme.brightness == Brightness.dark
              ? Colors.indigo.shade200
              : Colors.indigo.shade800,
        ),
      );
    }

    // 3. Isolated Guest Pill
    if (isGuest) {
      pills.add(
        buildPill(
          label: 'Isolated Guest',
          icon: Icons.shield_moon_rounded,
          bg: Colors.amber.shade700.withValues(alpha: 0.15),
          border: Colors.amber.shade700.withValues(alpha: 0.4),
          fg: theme.brightness == Brightness.dark
              ? Colors.amber.shade300
              : Colors.amber.shade900,
        ),
      );
    }

    // 4. Banned / Paused Access Pill
    if (isBanned) {
      pills.add(
        buildPill(
          label: 'Wi-Fi Banned',
          icon: Icons.block_rounded,
          bg: Colors.red.shade700.withValues(alpha: 0.15),
          border: Colors.red.shade700.withValues(alpha: 0.4),
          fg: theme.brightness == Brightness.dark
              ? Colors.red.shade300
              : Colors.red.shade900,
        ),
      );
    } else if (isPaused) {
      pills.add(
        buildPill(
          label: 'PAUSED',
          icon: Icons.pause_circle_filled_rounded,
          bg: Colors.orange.shade700.withValues(alpha: 0.15),
          border: Colors.orange.shade700.withValues(alpha: 0.4),
          fg: theme.brightness == Brightness.dark
              ? Colors.orange.shade300
              : Colors.orange.shade900,
        ),
      );
    }

    if (pills.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: pills,
      ),
    );
  }

  /// Classifies an IPv6 address into a human-readable type label.
  static String _classifyIPv6(String ipv6) {
    final lower = ipv6.toLowerCase().split('/').first.split('%').first;
    if (lower.startsWith('fe80')) return 'Link-Local IPv6';
    if (lower.startsWith('fd') || lower.startsWith('fc')) {
      return 'Private IPv6 (ULA)';
    }
    return 'Public IPv6';
  }

  /// Sort priority for IPv6 types: public first, private second, link-local last.
  static int _ipv6SortPriority(String label) {
    if (label.startsWith('Public')) return 0;
    if (label.startsWith('Private')) return 1;
    return 2;
  }

  Widget _buildClientDetails(BuildContext context, Client client) {
    final theme = Theme.of(context);

    Widget detailRow(
      String title,
      String value, {
      Color? valueColor,
      VoidCallback? onTap,
      String? semanticsLabel,
    }) {
      final isIpv6Value = title.contains('IPv6');
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 3.5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                title,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
                semanticsLabel: title,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        isIpv6Value ? value.replaceAll(':', ':\u200B') : value,
                        style:
                            (valueColor != null
                                    ? LuciTextStyles.detailValue(
                                        context,
                                      ).copyWith(color: valueColor)
                                    : LuciTextStyles.detailValue(context))
                                .copyWith(fontSize: 12),
                        textAlign: TextAlign.end,
                      ),
                    ),
                    if (onTap != null)
                      GestureDetector(
                        onTap: onTap,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6.0),
                          child: Icon(
                            Icons.copy_all_rounded,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.7),
                            semanticLabel: 'Copy',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Build classified IPv6 rows, sorted: public → private → link-local
    List<Widget> ipv6Rows = [];
    if (client.ipv6Addresses != null && client.ipv6Addresses!.isNotEmpty) {
      // Deduplicate IPv6 list
      final uniqueV6 = <String>{};
      final deduplicatedV6 = <String>[];
      for (final addr in client.ipv6Addresses!) {
        final norm = addr.trim().toLowerCase();
        if (norm.isNotEmpty && uniqueV6.add(norm)) {
          deduplicatedV6.add(addr.trim());
        }
      }

      final classified = deduplicatedV6.map((ipv6) {
        final label = _classifyIPv6(ipv6);
        return (label: label, address: ipv6);
      }).toList();
      classified.sort(
        (a, b) =>
            _ipv6SortPriority(a.label).compareTo(_ipv6SortPriority(b.label)),
      );

      final displayEntries = (classified.length > 1 && !widget.isIpv6Expanded)
          ? classified.take(1).toList()
          : classified;

      ipv6Rows = displayEntries
          .map(
            (entry) => detailRow(
              entry.label,
              entry.address,
              onTap: () =>
                  _copyToClipboard(context, entry.address, entry.label),
              semanticsLabel: '${entry.label}: ${entry.address}',
            ),
          )
          .toList();

      if (classified.length > 1) {
        final remainingCount = classified.length - 1;
        ipv6Rows.add(
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 14.0,
              vertical: 2.0,
            ),
            child: InkWell(
              onTap: widget.onToggleIpv6,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 3.0,
                  horizontal: 6.0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.isIpv6Expanded
                          ? 'Collapse IPv6 addresses'
                          : 'Show $remainingCount more IPv6 address${remainingCount > 1 ? 'es' : ''}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      widget.isIpv6Expanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 15,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.12,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 4),
          detailRow(
            'IP Address',
            client.ipAddress,
            onTap: () =>
                _copyToClipboard(context, client.ipAddress, 'IP Address'),
            semanticsLabel: 'IP Address: ${client.ipAddress}',
          ),
          ...ipv6Rows,
          detailRow(
            'MAC Address',
            client.macAddress,
            onTap: () =>
                _copyToClipboard(context, client.macAddress, 'MAC Address'),
            semanticsLabel: 'MAC Address: ${client.macAddress}',
          ),
          if (client.vendor != null && client.vendor!.isNotEmpty)
            detailRow(
              'Vendor',
              client.vendor!,
              semanticsLabel: 'Vendor: ${client.vendor}',
            ),
          if (client.dnsName != null && client.dnsName!.isNotEmpty)
            detailRow(
              'DNS Name',
              client.dnsName!,
              onTap: () =>
                  _copyToClipboard(context, client.dnsName!, 'DNS Name'),
              semanticsLabel: 'DNS Name: ${client.dnsName}',
            ),
          const SizedBox(height: 2),
          const Divider(height: 1, indent: 14, endIndent: 14),
          const SizedBox(height: 2),
          detailRow(
            'Lease Time Remaining',
            client.formattedLeaseTime,
            valueColor: client.formattedLeaseTime == 'Expired'
                ? theme.colorScheme.error
                : (client.formattedLeaseTime == 'No active lease'
                      ? theme.colorScheme.onSurfaceVariant
                      : null),
            semanticsLabel:
                'Lease Time Remaining: ${client.formattedLeaseTime}',
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 14.0,
              vertical: 6.0,
            ),
            child: ListenableBuilder(
              listenable: AppState.instance,
              builder: (ctx, _) {
                final appState = AppState.instance;
                final isDarkMode = theme.brightness == Brightness.dark;
                final colorScheme = theme.colorScheme;
                final isPaused = appState.isInternetPaused(client.macAddress);
                final isBanned = appState.isWirelessBanned(client.macAddress);
                final canPause = client.isConnected || isPaused;

                final actionButtons = <Widget>[];

                // 0. Unban & Edit Ban Controls (if currently banned)
                if (isBanned) {
                  actionButtons.add(
                    OutlinedButton.icon(
                      onPressed: () => _unbanWirelessClient(context, client),
                      icon: Icon(
                        Icons.check_circle_outline_rounded,
                        size: 14,
                        color: colorScheme.primary,
                      ),
                      label: Text(
                        'Unban Client',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: BorderSide(
                          color: colorScheme.primary.withValues(
                            alpha: isDarkMode ? 0.6 : 0.4,
                          ),
                          width: 0.9,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  );
                  actionButtons.add(
                    OutlinedButton.icon(
                      onPressed: () => _banWirelessClient(context, client),
                      icon: const Icon(
                        Icons.timer_outlined,
                        size: 14,
                        color: LuciStatusColors.warning,
                      ),
                      label: const Text(
                        'Edit Ban',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: LuciStatusColors.warning,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: BorderSide(
                          color: LuciStatusColors.warning.withValues(
                            alpha: isDarkMode ? 0.6 : 0.4,
                          ),
                          width: 0.9,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  );
                }

                // 1. Pause / Resume Internet Switch
                if (canPause && !isBanned) {
                  final pauseResumeColor = isPaused
                      ? LuciStatusColors.connected
                      : colorScheme.error;
                  actionButtons.add(
                    OutlinedButton.icon(
                      onPressed: () =>
                          _toggleInternetPause(context, client, !isPaused),
                      icon: Icon(
                        isPaused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        size: 15,
                        color: pauseResumeColor,
                      ),
                      label: Text(
                        isPaused ? 'Resume Access' : 'Pause Access',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: pauseResumeColor,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: BorderSide(
                          color: pauseResumeColor.withValues(
                            alpha: isDarkMode ? 0.6 : 0.4,
                          ),
                          width: 0.9,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  );
                }

                // 2. Ban Client (Available for all active & DHCP clients)
                if (!isBanned) {
                  actionButtons.add(
                    OutlinedButton.icon(
                      onPressed: () => _banWirelessClient(context, client),
                      icon: const Icon(
                        Icons.block_rounded,
                        size: 14,
                        color: LuciStatusColors.warning,
                      ),
                      label: const Text(
                        'Ban Client',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: LuciStatusColors.warning,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: BorderSide(
                          color: LuciStatusColors.warning.withValues(
                            alpha: isDarkMode ? 0.6 : 0.4,
                          ),
                          width: 0.9,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  );
                }

                // 3. Static Lease Controls (Add / Edit / Remove)
                final normMac =
                    client.macAddress.toUpperCase().replaceAll('-', ':');
                final isStatic =
                    client.isStatic ||
                    appState.configuredStaticLeaseMacs.contains(normMac);

                if (!isStatic && !_isIpv6Only(client)) {
                  actionButtons.add(
                    OutlinedButton.icon(
                      onPressed: () =>
                          _showAddStaticLeaseDialog(context, client),
                      icon: Icon(
                        Icons.push_pin_outlined,
                        size: 14,
                        color: colorScheme.primary,
                      ),
                      label: Text(
                        'Static Lease',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: BorderSide(
                          color: colorScheme.primary.withValues(
                            alpha: isDarkMode ? 0.6 : 0.4,
                          ),
                          width: 0.9,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  );
                }

                if (isStatic) {
                  actionButtons.add(
                    OutlinedButton.icon(
                      onPressed: () =>
                          _showAddStaticLeaseDialog(context, client),
                      icon: Icon(
                        Icons.edit_outlined,
                        size: 14,
                        color: colorScheme.primary,
                      ),
                      label: Text(
                        'Edit Static Lease',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: BorderSide(
                          color: colorScheme.primary.withValues(
                            alpha: isDarkMode ? 0.6 : 0.4,
                          ),
                          width: 0.9,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  );

                  actionButtons.add(
                    OutlinedButton.icon(
                      onPressed: () =>
                          _confirmRemoveStaticLease(context, client),
                      icon: Icon(
                        Icons.delete_outline,
                        size: 14,
                        color: colorScheme.error,
                      ),
                      label: Text(
                        'Remove Lease',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.error,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: BorderSide(
                          color: colorScheme.error.withValues(
                            alpha: isDarkMode ? 0.6 : 0.4,
                          ),
                          width: 0.9,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  );
                }

                return _buildJustifiedActionButtons(actionButtons);
              },
            ),
          ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }

  bool _isValidIPv4(String ip) {
    if (ip == 'N/A' || ip.trim().isEmpty) return false;
    final reg = RegExp(
      r'^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.){3}(25[0-5]|(2[0-4]|1\d|[1-9]|)\d)$',
    );
    return reg.hasMatch(ip.trim());
  }

  bool _isIpv6Only(Client client) {
    final hasV4 = _isValidIPv4(client.ipAddress);
    final hasV6 =
        client.ipv6Addresses != null && client.ipv6Addresses!.isNotEmpty;
    return !hasV4 && hasV6;
  }

  void _showAddStaticLeaseDialog(BuildContext context, Client client) {
    final appState = AppState.instance;
    final dhcpOverview = DhcpDnsOverview.fromDashboardData(
      appState.dashboardData,
      isReviewerMode: appState.reviewerModeEnabled,
    );
    DhcpStaticMapping? existingMapping;
    final normMac = client.macAddress.toUpperCase().replaceAll('-', ':');
    for (final s in dhcpOverview.staticMappings) {
      if (s.macAddress.toUpperCase().replaceAll('-', ':') == normMac) {
        existingMapping = s;
        break;
      }
    }

    showDialog(
      context: context,
      builder: (dialogCtx) => AddStaticLeaseDialog(
        client: client,
        allClients: widget.allClients,
        existingMapping: existingMapping,
        onSaved: widget.onRefreshNeeded,
      ),
    );
  }

  Future<void> _confirmRemoveStaticLease(
    BuildContext context,
    Client client,
  ) async {
    if (ActionRateLimiter.isRateLimited(
      'delete_static_lease_${client.macAddress}',
      cooldown: const Duration(milliseconds: 1200),
    )) {
      if (context.mounted) {
        context.showToastWarning(
          'Removal in progress. Please wait a moment...',
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_outline,
                color: Colors.redAccent,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Remove Static Lease',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to remove the static IP reservation for "${client.displayName}" (${client.macAddress})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Remove Reservation'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final actionKey = 'remove_lease_${client.macAddress}';
      context.showToastLoading(
        'Removing static lease for ${client.displayName}...',
        actionKey: actionKey,
      );

      final appState = AppState.instance;
      final success = await appState.deleteStaticLease(
        macAddress: client.macAddress,
        targetIp: client.ipAddress != 'N/A' ? client.ipAddress : null,
        hostname: client.staticLeaseName ??
            (client.hostname != 'Unknown' ? client.hostname : null),
        context: context,
      );

      if (!context.mounted) return;

      if (success) {
        appState.invalidateStaticLeasesCache();
        context.showToastSuccess(
          'Static lease removed for ${client.displayName}.',
          actionKey: actionKey,
        );
        widget.onRefreshNeeded();
      } else {
        context.showToastError(
          'Failed to remove static lease for ${client.displayName}.',
          actionKey: actionKey,
        );
      }
    }
  }

  Future<void> _toggleInternetPause(
    BuildContext context,
    Client client,
    bool pause,
  ) async {
    if (pause) {
      final safe = await SelfDeviceGuard.checkSelfActionGuardrail(
        context,
        actionName: 'Pause Internet Access',
        targetMac: client.macAddress,
        targetIp: client.ipAddress,
        targetHostname: client.displayName,
      );
      if (!safe) return;
      if (!context.mounted) return;
    }

    final actionKey = 'pause_internet_${client.macAddress}';
    if (ActionRateLimiter.isRateLimited(
      actionKey,
      cooldown: const Duration(seconds: 2),
    )) {
      final remaining = ActionRateLimiter.getRemainingCooldown(
        actionKey,
        cooldown: const Duration(seconds: 2),
      );
      context.showToastRateLimited(
        '${pause ? "Pause" : "Resume"} Internet (${client.displayName})',
        remaining,
      );
      return;
    }

    final appState = AppState.instance;
    context.showToastLoading(
      '${pause ? "Pausing" : "Resuming"} internet access...',
      subtitle: 'Target: ${client.displayName}',
      actionKey: actionKey,
    );

    final success = await appState.pauseClientInternet(
      client.macAddress,
      pause: pause,
      context: context,
    );

    if (success) {
      if (context.mounted) {
        LuciToastManager.safeShowSuccess(
          context,
          'Internet ${pause ? "Paused" : "Restored"}',
          subtitle: 'Target: ${client.displayName}',
          actionKey: actionKey,
        );
      }
    } else {
      if (context.mounted) {
        LuciToastManager.safeShowError(
          context,
          'Failed to ${pause ? "pause" : "resume"} internet',
          subtitle: 'Target: ${client.displayName}',
          actionKey: actionKey,
        );
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _banWirelessClient(BuildContext context, Client client) async {
    final isBanned = AppState.instance.isWirelessBanned(client.macAddress);

    await showDialog<void>(
      context: context,
      builder: (ctx) => BanWirelessClientDialog(
        macAddress: client.macAddress,
        displayName: client.displayName,
        ipAddress: client.ipAddress,
        ssid: client.ssid,
        iface: client.wirelessIface,
        isAlreadyBanned: isBanned,
        onUnbanConfirmed: () async {
          await _unbanWirelessClient(context, client);
        },
        onBanConfirmed: (int banTimeSeconds) async {
          final actionKey = 'ban_client_${client.macAddress}';
          if (ActionRateLimiter.isRateLimited(
            actionKey,
            cooldown: const Duration(seconds: 2),
          )) {
            final remaining = ActionRateLimiter.getRemainingCooldown(
              actionKey,
              cooldown: const Duration(seconds: 2),
            );
            if (context.mounted) {
              context.showToastRateLimited(
                'Ban Client (${client.displayName})',
                remaining,
              );
            }
            return;
          }

          if (context.mounted) {
            context.showToastLoading(
              'Banning ${client.displayName}...',
              subtitle:
                  'Setting hostapd ban for ${(banTimeSeconds / 60).round()} mins',
              actionKey: actionKey,
            );
          }

          final appState = AppState.instance;
          final success = await appState.banWirelessClient(
            client.macAddress,
            iface: client.wirelessIface,
            banTimeSeconds: banTimeSeconds,
            context: context.mounted ? context : null,
          );

          if (success) {
            if (context.mounted) {
              LuciToastManager.safeShowSuccess(
                context,
                'Banned ${client.displayName}',
                subtitle: 'Deauthenticated & blocked from Wi-Fi association',
                actionKey: actionKey,
              );
              widget.onRefreshNeeded();
            }
          } else {
            if (context.mounted) {
              LuciToastManager.safeShowError(
                context,
                'Failed to ban ${client.displayName}',
                subtitle: 'Target MAC: ${client.macAddress}',
                actionKey: actionKey,
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _unbanWirelessClient(BuildContext context, Client client) async {
    final actionKey = 'unban_client_${client.macAddress}';
    if (ActionRateLimiter.isRateLimited(
      actionKey,
      cooldown: const Duration(seconds: 2),
    )) {
      final remaining = ActionRateLimiter.getRemainingCooldown(
        actionKey,
        cooldown: const Duration(seconds: 2),
      );
      if (context.mounted) {
        context.showToastRateLimited(
          'Unban Client (${client.displayName})',
          remaining,
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                color: Colors.blue,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Unban Wireless Device?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to unban "${client.displayName}" (${client.macAddress})? This will restore Wi-Fi association and remove firewall blocking rules.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
            label: const Text('Unban Device'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final appState = AppState.instance;
    if (context.mounted) {
      LuciToastManager.safeShowLoading(
        context,
        'Unbanning ${client.displayName}...',
        actionKey: actionKey,
      );
    }

    final success = await appState.unbanWirelessClient(
      client.macAddress,
      context: context.mounted ? context : null,
    );

    if (success) {
      unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.medium));
      if (context.mounted) {
        LuciToastManager.safeShowSuccess(
          context,
          '${client.displayName} unbanned successfully.',
          actionKey: actionKey,
        );
        widget.onRefreshNeeded();
      }
    } else {
      unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));
      if (context.mounted) {
        LuciToastManager.safeShowError(
          context,
          'Failed to unban ${client.displayName}.',
          actionKey: actionKey,
        );
      }
    }
  }

  String _buildMinimalClientSubtitle(Client client) {
    final v4 = client.ipAddress;
    final v6s = client.ipv6Addresses ?? [];
    final v6 = v6s.isNotEmpty ? v6s.first : null;
    String? shown;
    int extra = 0;
    if (v4 != 'N/A') {
      shown = v4;
      if (v6 != null) extra++;
    } else if (v6 != null) {
      shown = v6;
    }
    if (shown == null) return '';
    if (extra > 0) {
      return '$shown  +$extra';
    } else {
      return shown;
    }
  }

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    context.showToastSuccess('$label copied', subtitle: 'Copied to clipboard.');
  }

  Widget _buildJustifiedActionButtons(List<Widget> buttons) {
    if (buttons.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth = constraints.maxWidth;

        if (availableWidth < 480) {
          final List<Widget> rows = [];
          for (int i = 0; i < buttons.length; i += 2) {
            if (i + 1 < buttons.length) {
              rows.add(
                Row(
                  children: [
                    Expanded(child: buttons[i]),
                    const SizedBox(width: 8),
                    Expanded(child: buttons[i + 1]),
                  ],
                ),
              );
            } else {
              rows.add(Row(children: [Expanded(child: buttons[i])]));
            }
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int r = 0; r < rows.length; r++) ...[
                if (r > 0) const SizedBox(height: 8),
                rows[r],
              ],
            ],
          );
        }

        return Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: buttons,
          ),
        );
      },
    );
  }
}
