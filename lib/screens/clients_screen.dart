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
import 'package:yet_another_luci_app/utils/os_platform_integration.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/widgets/add_static_lease_dialog.dart';
import 'package:yet_another_luci_app/widgets/ban_wireless_client_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/modules/dhcp_dns/models/dhcp_dns_info.dart';
import 'package:yet_another_luci_app/modules/wireless_management/models/wireless_info.dart';
import 'package:yet_another_luci_app/widgets/rpc_permissions_dialog.dart';
import 'package:yet_another_luci_app/widgets/device_network_access_card.dart';
import 'package:yet_another_luci_app/widgets/client_speed_limit_dialog.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';

class ClientsScreen extends ConsumerStatefulWidget {
  final bool isTabActive;

  const ClientsScreen({super.key, this.isTabActive = true});

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
  int _clientFetchEpoch = 0;
  String? _lastSelectedRouterId;
  String? _cachedClientsRouterId;
  dynamic _lastDashboardUpdated;
  DateTime? _lastFetchTime;
  bool _showOnlyActiveConnected = false;
  bool _showDumbApClients = true;
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
    _cachedClientsRouterId = _lastSelectedRouterId;
    _lastDashboardUpdated = initState.dashboardData?['_lastUpdated'];
    // Pre-populate cached clients so tab switching displays existing data instantly (0ms delay)
    if (initState.clients.isNotEmpty) {
      _cachedClients = List<Client>.from(initState.clients);
    }
    _computeClientsFuture(forRouterId: _lastSelectedRouterId);
    if (widget.isTabActive) {
      _startAutoRefreshTimer();
    }
    unawaited(initState.checkExpiredDevicePolicies());
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

  Future<List<Client>> _computeClientsFuture({String? forRouterId}) {
    _lastFetchTime = DateTime.now();
    final appState = ref.read(appStateProvider);
    final targetRouterId = forRouterId ?? appState.selectedRouter?.id;
    final currentEpoch = ++_clientFetchEpoch;

    // Stage 1: Priority to current logged-in router session data.
    // Fetch and display the active router's clients first so the screen resolves immediately.
    final future = appState
        .fetchClientsForSelectedRouter()
        .then((currentClients) {
          if (mounted && currentEpoch == _clientFetchEpoch) {
            final currentRouterId = ref
                .read(appStateProvider)
                .selectedRouter
                ?.id;
            if (targetRouterId == null || currentRouterId == targetRouterId) {
              setState(() {
                _cachedClientsRouterId = currentRouterId;
                if (currentClients.isNotEmpty || _cachedClients.isEmpty) {
                  _cachedClients = currentClients;
                }
              });
            }
          }

          // Stage 2: After current router data is loaded, check for other secondary or Dumb AP clients.
          if (_aggregateAllRouters &&
              (appState.hasDumbAp || appState.routers.length > 1)) {
            unawaited(
              appState
                  .fetchAggregatedClients(
                    onIncrementalUpdate: (incrementalList) {
                      if (!mounted || currentEpoch != _clientFetchEpoch) return;
                      final activeId = ref
                          .read(appStateProvider)
                          .selectedRouter
                          ?.id;
                      if (targetRouterId != null && activeId != targetRouterId)
                        return;

                      setState(() {
                        _cachedClientsRouterId = activeId;
                        if (incrementalList.isNotEmpty ||
                            _cachedClients.isEmpty) {
                          _cachedClients = incrementalList;
                        }
                      });
                    },
                  )
                  .then((aggregatedList) {
                    if (!mounted || currentEpoch != _clientFetchEpoch) return;
                    final activeId = ref
                        .read(appStateProvider)
                        .selectedRouter
                        ?.id;
                    if (targetRouterId != null && activeId != targetRouterId)
                      return;

                    setState(() {
                      _cachedClientsRouterId = activeId;
                      if (aggregatedList.isNotEmpty || _cachedClients.isEmpty) {
                        _cachedClients = aggregatedList;
                      }
                    });
                  })
                  .catchError((_) {
                    // Retain active router clients if secondary AP query fails or times out
                  }),
            );
          }

          return currentClients;
        })
        .catchError((error) {
          if (mounted && currentEpoch == _clientFetchEpoch) {
            setState(() {});
          }
          return appState.clients;
        });

    _clientsFuture = future;
    return future;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lastRenderedScaffold = null;
  }

  @override
  void didUpdateWidget(ClientsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isTabActive != oldWidget.isTabActive) {
      if (widget.isTabActive) {
        _lastRenderedScaffold = null;
        final currentRouterId = ref.read(appStateProvider).selectedRouter?.id;
        if (currentRouterId != _cachedClientsRouterId) {
          _cachedClients = [];
          _cachedClientsRouterId = currentRouterId;
        }
        final now = DateTime.now();
        final shouldFetch =
            _lastFetchTime == null ||
            now.difference(_lastFetchTime!) > const Duration(seconds: 15) ||
            _cachedClients.isEmpty;
        if (shouldFetch) {
          setState(() {
            _computeClientsFuture(forRouterId: currentRouterId);
          });
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
      unawaited(AppState.instance.checkExpiredDevicePolicies());
      _lastRenderedScaffold = null;
      if (widget.isTabActive) {
        _startAutoRefreshTimer();
        setState(() {
          _computeClientsFuture();
        });
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _autoRefreshTimer?.cancel();
    }
  }

  void _onClientStaticLeaseRemoved(String macAddress) {
    final norm = normalizeMac(macAddress);
    setState(() {
      _cachedClients = _cachedClients
          .map((c) {
            if (normalizeMac(c.macAddress) == norm) {
              return c.copyWith(
                isStaticLease: false,
                staticLeaseName: '',
                staticLeaseTime: '',
              );
            }
            return c;
          })
          .where((c) {
            if (normalizeMac(c.macAddress) == norm &&
                !c.isConnected &&
                (c.leaseTime == 0 || c.leaseTime == null)) {
              return false;
            }
            return true;
          })
          .toList();
    });
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
            if (reqFilter == ClientCategoryFilter.dumbAp) {
              _categoryFilter = ClientCategoryFilter.all;
              _showDumbApClients = true;
            } else {
              _categoryFilter = reqFilter;
            }
          });
        }
        watchedAppState.requestedClientCategoryFilter = null;
      });
    }
    // Recompute future when selected router changes or (if active) dashboard data timestamp changes
    final currentId = watchedAppState.selectedRouter?.id;
    final lastUpdated = watchedAppState.dashboardData?['_lastUpdated'];
    final routerChanged = currentId != _lastSelectedRouterId;

    if (routerChanged) {
      _lastSelectedRouterId = currentId;
      _lastDashboardUpdated = lastUpdated;
      _lastRenderedScaffold = null;
      _cachedClientsRouterId = currentId;
      _cachedClients = [];
      _expandedClientMacs.clear();
      _expandedIpv6Macs.clear();
      _computeClientsFuture(forRouterId: currentId);
    } else if (widget.isTabActive && lastUpdated != _lastDashboardUpdated) {
      _lastDashboardUpdated = lastUpdated;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.isTabActive) {
          setState(() {
            _computeClientsFuture(forRouterId: currentId);
          });
        }
      });
    }

    if (!widget.isTabActive && _lastRenderedScaffold != null) {
      return _lastRenderedScaffold!;
    }

    final Future<List<Client>>? future = _clientsFuture;
    final scaffold = FutureBuilder<List<Client>>(
      key: ValueKey('clients_${currentId ?? 'none'}'),
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          if (snapshot.data!.isNotEmpty || _cachedClients.isEmpty) {
            _cachedClients = snapshot.data!;
          }
          _cachedClientsRouterId = currentId;
        }
        final isMatchingRouter = _cachedClientsRouterId == currentId;
        final aggregatedClients =
            (snapshot.hasData &&
                snapshot.data != null &&
                (snapshot.data!.isNotEmpty || _cachedClients.isEmpty))
            ? snapshot.data!
            : (isMatchingRouter ? _cachedClients : <Client>[]);
        final l10n = AppLocalizations.of(context);
        return Scaffold(
          appBar: LuciAppBar(title: l10n?.navClients ?? 'Clients'),
          body: Stack(
            children: [
              LuciPullToRefresh(
                onRefresh: () async {
                  // Trigger a refresh by re-fetching dashboard data for selected router
                  await ref.read(appStateProvider).fetchDashboardData();
                  if (mounted) {
                    setState(() {
                      _computeClientsFuture(forRouterId: currentId);
                    });
                  }
                },
                child: Builder(
                  builder: (context) {
                    final appState = ref.watch(appStateProvider);
                    final l10n = AppLocalizations.of(context);
                    final isWaitingData =
                        snapshot.connectionState == ConnectionState.waiting ||
                        appState.isLoading ||
                        appState.isDashboardLoading ||
                        appState.isClientsLoading;
                    final isLoading =
                        isWaitingData && (aggregatedClients.isEmpty);
                    final dashboardError = appState.dashboardError;

                    if (isLoading) {
                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 6.0,
                            ),
                            child: SizedBox(
                              height: 40,
                              child: TextField(
                                enabled: false,
                                autofocus: false,
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12.0,
                                    vertical: 0.0,
                                  ),
                                  hintText:
                                      l10n?.searchClientsPlaceholder ??
                                      'Search by name, IP, MAC, vendor...',
                                  prefixIcon: Icon(
                                    Icons.search,
                                    size: 19,
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.7),
                                  ),
                                  prefixIconConstraints: const BoxConstraints(
                                    minWidth: 38,
                                    minHeight: 38,
                                  ),
                                  filled: true,
                                  fillColor: colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.45),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14.0),
                                    borderSide: BorderSide.none,
                                  ),
                                  hintStyle: TextStyle(
                                    fontSize: 13,
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.6),
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
                                Expanded(
                                  child: _buildFilterChip(
                                    icon: Icons.devices_other,
                                    label:
                                        l10n?.filterActiveConnectedOnly ??
                                        'Active Connected Only',
                                    isSelected: false,
                                    onTap: () {},
                                    colorScheme: colorScheme,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildFilterChip(
                                    icon: Icons.settings_input_antenna_rounded,
                                    label:
                                        l10n?.filterShowDumbApClients ??
                                        'Show Dumb AP Clients',
                                    isSelected: false,
                                    onTap: () {},
                                    colorScheme: colorScheme,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildClientSummaryRow(
                            [],
                            colorScheme,
                            theme.textTheme,
                            isLoading: true,
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.only(bottom: 100),
                              itemCount: 6,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 4),
                              itemBuilder: (context, index) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                  vertical: 8.0,
                                ),
                                child: Card(
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18.0),
                                    side: BorderSide(
                                      color: colorScheme.surfaceContainerHighest
                                          .withValues(alpha: 0.10),
                                      width: 1,
                                    ),
                                  ),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 4.0,
                                      vertical: 2.0,
                                    ),
                                    child: LuciListItemSkeleton(
                                      showLeading: true,
                                      showTrailing: true,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }

                    final hasError =
                        dashboardError != null || snapshot.hasError;
                    if (hasError && aggregatedClients.isEmpty) {
                      return LuciErrorDisplay(
                        title:
                            l10n?.clientsFailedToLoad ??
                            'Failed to Load Clients',
                        message:
                            l10n?.clientsFailedToLoadMessage ??
                            'Could not connect to the router. Please check your network connection and the router\'s IP address.',
                        actionLabel: l10n?.actionRetry ?? 'Retry',
                        onAction: () async {
                          await ref.read(appStateProvider).fetchDashboardData();
                          if (mounted) {
                            setState(() {
                              _computeClientsFuture(forRouterId: currentId);
                            });
                          }
                        },
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
                      final isBannedOrPaused =
                          hasBannedOrPaused &&
                          allBannedMacs.contains(client.normalizedMac);

                      if (_categoryFilter == ClientCategoryFilter.banned) {
                        if (!isBannedOrPaused) return false;
                      } else {
                        // Exclude banned/paused clients from Total, Wired, Wireless options
                        if (isBannedOrPaused) return false;

                        if (_showOnlyActiveConnected && !client.isConnected) {
                          return false;
                        }
                        if (!_showDumbApClients && client.isDumbApClient) {
                          return false;
                        }
                        if (_categoryFilter == ClientCategoryFilter.wired) {
                          if (!clientHasActiveWiredBadge(client)) {
                            return false;
                          }
                        }
                        if (_categoryFilter == ClientCategoryFilter.wireless &&
                            client.connectionType != ConnectionType.wireless) {
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

                    final dumbApCount = clients.where((c) {
                      final isBannedOrPaused =
                          hasBannedOrPaused &&
                          allBannedMacs.contains(c.normalizedMac);
                      if (isBannedOrPaused) return false;
                      if (_showOnlyActiveConnected && !c.isConnected) {
                        return false;
                      }
                      return c.isDumbApClient;
                    }).length;

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
                                        l10n?.bannedClientsHubTitle ??
                                            'Banned Clients Hub',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12.5,
                                          color: colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        l10n?.bannedClientsHubMessage ??
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
                                  tooltip: l10n?.dismissHint ?? 'Dismiss hint',
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
                                hintText:
                                    l10n?.searchClientsPlaceholder ??
                                    'Search by name, IP, MAC, vendor...',
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
                                        tooltip:
                                            l10n?.clearSearchTooltip ??
                                            'Clear search',
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
                              Expanded(
                                child: _buildFilterChip(
                                  icon: _showOnlyActiveConnected
                                      ? Icons.wifi_tethering
                                      : Icons.devices_other,
                                  label:
                                      l10n?.filterActiveConnectedOnly ??
                                      'Active Connected Only',
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
                                  label:
                                      l10n?.filterShowDumbApClients ??
                                      'Show Dumb AP Clients',
                                  isSelected: _showDumbApClients,
                                  countBadge: dumbApCount,
                                  onTap: () {
                                    setState(() {
                                      _showDumbApClients = !_showDumbApClients;
                                    });
                                  },
                                  colorScheme: colorScheme,
                                ),
                              ),
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
                                      ? (l10n?.noBannedClientsTitle ??
                                            'No Banned Clients')
                                      : (_categoryFilter ==
                                                ClientCategoryFilter.dumbAp
                                            ? (l10n?.noDumbApClientsTitle ??
                                                  'No Dumb AP Clients')
                                            : (_searchQuery.isEmpty
                                                  ? (l10n?.noActiveClientsFound ??
                                                        'No Active Clients Found')
                                                  : (l10n?.noMatchingClients ??
                                                        'No Matching Clients'))),
                                  message:
                                      _categoryFilter ==
                                          ClientCategoryFilter.banned
                                      ? (l10n?.noBannedClientsMessage ??
                                            'No clients are currently banned from Wi-Fi or internet access.')
                                      : (_categoryFilter ==
                                                ClientCategoryFilter.dumbAp
                                            ? (l10n?.noDumbApClientsMessage ??
                                                  'No clients are currently associated with the secondary Access Point.')
                                            : (_searchQuery.isEmpty
                                                  ? (l10n?.noClientsConnectedMessage ??
                                                        'No clients are currently connected to the router. Pull down to refresh the list.')
                                                  : (l10n?.noClientsMatchingMessage ??
                                                        'No clients match your search criteria. Try a different search term.'))),
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
                                  padding: const EdgeInsets.only(bottom: 100),
                                  // ignore: deprecated_member_use
                                  cacheExtent: 500.0,
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.onDrag,
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
                                      key: ValueKey<String>(client.macAddress),
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
                                          onLeaseRemoved:
                                              _onClientStaticLeaseRemoved,
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
    int? countBadge,
  }) {
    final activeColor = isSelected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    final bgColor = isSelected
        ? colorScheme.primary.withValues(alpha: 0.14)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.45);
    final borderColor = isSelected
        ? colorScheme.primary.withValues(alpha: 0.4)
        : colorScheme.outlineVariant.withValues(alpha: 0.25);
    final hasBadge = countBadge != null && countBadge > 0;

    return Semantics(
      button: true,
      toggled: isSelected,
      label: hasBadge ? '$label ($countBadge)' : label,
      child: Material(
        color: bgColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: borderColor, width: 1),
        ),
        child: InkWell(
          onTap: () {
            unawaited(HapticFeedback.selectionClick());
            onTap();
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 32,
            padding: EdgeInsets.symmetric(horizontal: hasBadge ? 8.0 : 10.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: activeColor),
                const SizedBox(width: 5),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: activeColor,
                      ),
                    ),
                  ),
                ),
                if (hasBadge) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4.5,
                      vertical: 1.0,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.secondary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 15,
                      minHeight: 14,
                    ),
                    child: Text(
                      countBadge > 99 ? '99+' : '$countBadge',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? colorScheme.onPrimary
                            : colorScheme.onSecondary,
                        height: 1.1,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
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
    TextTheme textTheme, {
    bool isLoading = false,
  }) {
    final appState = ref.watch(appStateProvider);
    final l10n = AppLocalizations.of(context);

    int totalCount = 0;
    int wiredCount = 0;
    int wirelessCount = 0;

    final allBannedMacs = <String>{
      ...appState.pausedInternetMacs.map(normalizeMac),
      ...appState.bannedWirelessMacs.map(normalizeMac),
    };

    for (final c in clients) {
      final normMac = normalizeMac(c.macAddress);
      if (allBannedMacs.contains(normMac)) {
        continue;
      }

      if (_showOnlyActiveConnected && !c.isConnected) {
        continue;
      }

      if (!_showDumbApClients && c.isDumbApClient) {
        continue;
      }

      totalCount++;

      if (clientHasActiveWiredBadge(c)) {
        wiredCount++;
      } else if (c.connectionType == ConnectionType.wireless) {
        wirelessCount++;
      }
    }

    final bannedCount = allBannedMacs.length;

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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 640;

            final totalItem = _buildSummaryItem(
              icon: Icons.devices_rounded,
              label: l10n?.summaryTotal ?? 'Total',
              count: totalCount,
              color: colorScheme.primary,
              category: ClientCategoryFilter.all,
              isSelected: _categoryFilter == ClientCategoryFilter.all,
              onTap: () {
                setState(() {
                  _categoryFilter = ClientCategoryFilter.all;
                });
              },
              colorScheme: colorScheme,
              isLoading: isLoading,
            );
            final wiredItem = _buildSummaryItem(
              icon: Icons.lan_outlined,
              label: l10n?.summaryWired ?? 'Wired',
              count: wiredCount,
              color: colorScheme.secondary,
              category: ClientCategoryFilter.wired,
              isSelected: _categoryFilter == ClientCategoryFilter.wired,
              onTap: () {
                setState(() {
                  _categoryFilter = ClientCategoryFilter.wired;
                });
              },
              colorScheme: colorScheme,
              isLoading: isLoading,
            );
            final wirelessItem = _buildSummaryItem(
              icon: Icons.wifi_rounded,
              label: l10n?.summaryWireless ?? 'Wireless',
              count: wirelessCount,
              color: colorScheme.tertiary,
              category: ClientCategoryFilter.wireless,
              isSelected: _categoryFilter == ClientCategoryFilter.wireless,
              onTap: () {
                setState(() {
                  _categoryFilter = ClientCategoryFilter.wireless;
                });
              },
              colorScheme: colorScheme,
              isLoading: isLoading,
            );
            final bannedItem = _buildSummaryItem(
              icon: Icons.block_rounded,
              label: l10n?.summaryBanned ?? 'Banned',
              count: bannedCount,
              color: bannedCount > 0
                  ? Colors.red
                  : colorScheme.onSurfaceVariant,
              category: ClientCategoryFilter.banned,
              isSelected: _categoryFilter == ClientCategoryFilter.banned,
              onTap: () {
                setState(() {
                  _categoryFilter = ClientCategoryFilter.banned;
                });
              },
              colorScheme: colorScheme,
              isLoading: isLoading,
            );

            Widget divider() => Container(
              width: 1,
              height: 20,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            );

            if (isNarrow) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    totalItem,
                    divider(),
                    wiredItem,
                    divider(),
                    wirelessItem,
                    divider(),
                    bannedItem,
                  ],
                ),
              );
            }

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(child: totalItem),
                divider(),
                Expanded(child: wiredItem),
                divider(),
                Expanded(child: wirelessItem),
                divider(),
                Expanded(child: bannedItem),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSummaryItem({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
    required ClientCategoryFilter category,
    required bool isSelected,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
    bool isLoading = false,
  }) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final (Color bg, Color fg, Color border) = switch (category) {
      ClientCategoryFilter.all => (
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
        colorScheme.primary.withValues(alpha: 0.35),
      ),
      ClientCategoryFilter.wired => (
        colorScheme.secondaryContainer,
        colorScheme.onSecondaryContainer,
        colorScheme.secondary.withValues(alpha: 0.35),
      ),
      ClientCategoryFilter.wireless => (
        colorScheme.tertiaryContainer,
        colorScheme.onTertiaryContainer,
        colorScheme.tertiary.withValues(alpha: 0.35),
      ),
      ClientCategoryFilter.dumbAp => (
        Colors.indigo.withValues(alpha: isDark ? 0.3 : 0.12),
        isDark ? Colors.indigo.shade200 : Colors.indigo.shade900,
        Colors.indigo.withValues(alpha: 0.4),
      ),
      ClientCategoryFilter.banned => (
        Colors.red.withValues(alpha: isDark ? 0.3 : 0.12),
        isDark ? Colors.red.shade200 : Colors.red.shade900,
        Colors.red.withValues(alpha: 0.4),
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
                isLoading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 2.0),
                        child: LuciSkeleton(
                          width: 14,
                          height: 12,
                          borderRadius: BorderRadius.all(Radius.circular(3)),
                        ),
                      )
                    : Text(
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

/// Returns whether a client displays the active "Wired" badge.
/// Dumb AP clients that are stale or failed do not display the active Wired badge.
bool clientHasActiveWiredBadge(Client client) {
  final isStaleDumbApWired =
      client.isDumbApClient &&
      (client.neighState == NeighborReachability.stale ||
          client.neighState == NeighborReachability.failed);
  return client.isConnected &&
      client.connectionType == ConnectionType.wired &&
      !isStaleDumbApWired;
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
  final void Function(String macAddress)? onLeaseRemoved;

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
    this.onLeaseRemoved,
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
    if (!client.isConnected) {
      return Theme.of(context).colorScheme.outlineVariant;
    }
    switch (client.neighState) {
      case NeighborReachability.reachable:
        return LuciStatusColors.connectedColor(context);
      case NeighborReachability.stale:
        return LuciStatusColors.warningColor(context);
      case NeighborReachability.failed:
        return Theme.of(context).colorScheme.outlineVariant;
      case NeighborReachability.unknown:
        return client.isConnected
            ? LuciStatusColors.connectedColor(context)
            : Theme.of(context).colorScheme.outlineVariant;
    }
  }

  /// Tooltip describing the connectivity state in plain language.
  String _statusTooltip(Client client, AppLocalizations? l10n) {
    if (!client.isConnected) {
      return l10n?.clientOfflineTooltip ?? 'Client is offline (Lease active)';
    }
    switch (client.neighState) {
      case NeighborReachability.reachable:
        return l10n?.clientOnlineTooltip ?? 'Client is online';
      case NeighborReachability.stale:
        return l10n?.clientIdleTooltip ?? 'Client is idle (no recent traffic)';
      case NeighborReachability.failed:
        return l10n?.clientOfflineTooltip ?? 'Client is offline (Lease active)';
      case NeighborReachability.unknown:
        return client.isConnected
            ? (l10n?.clientOnlineTooltip ?? 'Client is online')
            : (l10n?.clientOfflineTooltip ??
                  'Client is offline (Lease active)');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

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
                                      color: colorScheme.primary.withValues(
                                        alpha: 0.25,
                                      ),
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
                                    : colorScheme.onSurfaceVariant.withValues(
                                        alpha: 0.7,
                                      ),
                                size: 20,
                                semanticLabel: 'Client icon',
                              ),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Tooltip(
                              message: _statusTooltip(widget.client, l10n),
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
                              maxLines: 2,
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
    final l10n = AppLocalizations.of(context);
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
      final signalText = client.signalDbm != null
          ? ' • ${client.signalDbm} dBm'
          : '';
      final labelText = (client.ssid != null && client.ssid!.isNotEmpty)
          ? 'Wi-Fi • ${client.ssid}$signalText'
          : 'Wi-Fi$signalText';
      pills.add(
        buildPill(
          label: labelText,
          icon: Icons.wifi_rounded,
          bg: colorScheme.primaryContainer,
          border: colorScheme.primary.withValues(alpha: 0.3),
          fg: colorScheme.onPrimaryContainer,
        ),
      );
    } else if (clientHasActiveWiredBadge(client)) {
      pills.add(
        buildPill(
          label: l10n?.clientMediumWired ?? (l10n?.summaryWired ?? 'Wired'),
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
          label: l10n?.pillStatic ?? 'STATIC',
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
          ? '${l10n?.summaryDumbAp ?? "Dumb AP"} • ${client.apName}'
          : (l10n?.summaryDumbAp ?? 'Dumb AP');
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
          label: l10n?.pillGuest ?? 'Isolated Guest',
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
          label: l10n?.pillBanned ?? 'Wi-Fi Banned',
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
          label: l10n?.pillPaused ?? 'PAUSED',
          icon: Icons.pause_circle_filled_rounded,
          bg: Colors.orange.shade700.withValues(alpha: 0.15),
          border: Colors.orange.shade700.withValues(alpha: 0.4),
          fg: theme.brightness == Brightness.dark
              ? Colors.orange.shade300
              : Colors.orange.shade900,
        ),
      );
    }

    // 5. Bandwidth Throttled Pill
    final speedLimit = appState.getClientSpeedLimit(
      client.macAddress,
      routerId: appState.selectedRouter?.id,
    );
    if (speedLimit != null && speedLimit.isEffectivelyRestricted) {
      pills.add(
        buildPill(
          label: speedLimit.compactSummary,
          icon: Icons.traffic_rounded,
          bg: Colors.blue.shade700.withValues(alpha: 0.15),
          border: Colors.blue.shade700.withValues(alpha: 0.4),
          fg: theme.brightness == Brightness.dark
              ? Colors.blue.shade300
              : Colors.blue.shade900,
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
  static String _classifyIPv6(String ipv6, AppLocalizations? l10n) {
    final lower = ipv6.toLowerCase().split('/').first.split('%').first;
    if (lower.startsWith('fe80')) {
      return l10n?.ipv6LinkLocal ?? 'Link-Local IPv6';
    }
    if (lower.startsWith('fd') || lower.startsWith('fc')) {
      return l10n?.ipv6Private ?? 'Private IPv6 (ULA)';
    }
    return l10n?.ipv6Public ?? 'Public IPv6';
  }

  /// Sort priority for IPv6 types: public first, private second, link-local last.
  static int _ipv6SortPriority(String label, AppLocalizations? l10n) {
    final publicPrefix = l10n?.ipv6Public ?? 'Public IPv6';
    final privatePrefix = l10n?.ipv6Private ?? 'Private IPv6 (ULA)';
    if (label == publicPrefix || label.startsWith('Public')) return 0;
    if (label == privatePrefix || label.startsWith('Private')) return 1;
    return 2;
  }

  Widget _buildClientDetails(BuildContext context, Client client) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

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
        final label = _classifyIPv6(ipv6, l10n);
        return (label: label, address: ipv6);
      }).toList();
      classified.sort(
        (a, b) => _ipv6SortPriority(
          a.label,
          l10n,
        ).compareTo(_ipv6SortPriority(b.label, l10n)),
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
                          ? (l10n?.collapseIpv6Addresses ??
                                'Collapse IPv6 addresses')
                          : (l10n?.showMoreIpv6Addresses(remainingCount) ??
                                'Show $remainingCount more IPv6 addresses'),
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
            l10n?.labelIpAddress ?? 'IP Address',
            client.ipAddress,
            onTap: () => _copyToClipboard(
              context,
              client.ipAddress,
              l10n?.labelIpAddress ?? 'IP Address',
            ),
            semanticsLabel:
                '${l10n?.labelIpAddress ?? "IP Address"}: ${client.ipAddress}',
          ),
          ...ipv6Rows,
          detailRow(
            l10n?.labelMacAddress ?? 'MAC Address',
            client.macAddress,
            onTap: () => _copyToClipboard(
              context,
              client.macAddress,
              l10n?.labelMacAddress ?? 'MAC Address',
            ),
            semanticsLabel:
                '${l10n?.labelMacAddress ?? "MAC Address"}: ${client.macAddress}',
          ),
          if (client.vendor != null && client.vendor!.isNotEmpty)
            detailRow(
              l10n?.labelVendor ?? 'Vendor',
              client.vendor!,
              semanticsLabel:
                  '${l10n?.labelVendor ?? "Vendor"}: ${client.vendor}',
            ),
          if (client.dnsName != null && client.dnsName!.isNotEmpty)
            detailRow(
              l10n?.labelDnsName ?? 'DNS Name',
              client.dnsName!,
              onTap: () => _copyToClipboard(
                context,
                client.dnsName!,
                l10n?.labelDnsName ?? 'DNS Name',
              ),
              semanticsLabel:
                  '${l10n?.labelDnsName ?? "DNS Name"}: ${client.dnsName}',
            ),
          const SizedBox(height: 2),
          const Divider(height: 1, indent: 14, endIndent: 14),
          const SizedBox(height: 2),
          detailRow(
            l10n?.labelLeaseTimeRemaining ?? 'Lease Time Remaining',
            client.formattedLeaseTime == 'Expired'
                ? (l10n?.leaseExpired ?? 'Expired')
                : (client.formattedLeaseTime == 'No active lease'
                      ? (l10n?.leaseNoActiveLease ?? 'No active lease')
                      : client.formattedLeaseTime),
            valueColor: client.formattedLeaseTime == 'Expired'
                ? theme.colorScheme.error
                : (client.formattedLeaseTime == 'No active lease'
                      ? theme.colorScheme.onSurfaceVariant
                      : null),
            semanticsLabel:
                '${l10n?.labelLeaseTimeRemaining ?? "Lease Time Remaining"}: ${client.formattedLeaseTime}',
          ),
          if (client.hasTrafficData || client.signalDbm != null) ...[
            const SizedBox(height: 2),
            const Divider(height: 1, indent: 14, endIndent: 14),
            const SizedBox(height: 2),
            if (client.formattedSignalWithQuality != null)
              detailRow(
                l10n?.clientSignal ?? 'Signal',
                client.formattedSignalWithQuality!,
                semanticsLabel:
                    '${l10n?.clientSignal ?? "Signal"}: ${client.formattedSignalWithQuality}',
              ),
            if (client.formattedPhyRate != null)
              detailRow(
                l10n?.clientPhyRate ?? 'Link Rate (PHY)',
                client.formattedPhyRate!,
                semanticsLabel:
                    '${l10n?.clientPhyRate ?? "Link Rate (PHY)"}: ${client.formattedPhyRate}',
              ),

            if (client.formattedTotalDownloaded != null ||
                client.formattedTotalUploaded != null ||
                (client.isConnected &&
                    client.connectionType == ConnectionType.wireless))
              detailRow(
                l10n?.clientTotalTransfer ?? 'Session Transfer',
                '↓ ${client.formattedTotalDownloaded ?? "0 B"}  ↑ ${client.formattedTotalUploaded ?? "0 B"}',
                semanticsLabel:
                    '${l10n?.clientTotalTransfer ?? "Session Transfer"}: ↓ ${client.formattedTotalDownloaded ?? "0 B"} ↑ ${client.formattedTotalUploaded ?? "0 B"}',
              ),
            if (client.formattedConnectedTime != null)
              detailRow(
                l10n?.clientConnectedDuration ?? 'Connection Time',
                client.formattedConnectedTime!,
                semanticsLabel:
                    '${l10n?.clientConnectedDuration ?? "Connection Time"}: ${client.formattedConnectedTime}',
              ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 14.0,
              vertical: 6.0,
            ),
            child: ListenableBuilder(
              listenable: AppState.instance,
              builder: (ctx, _) {
                final appState = AppState.instance;
                final isRpcMissing = appState.isMissingRpcPackages;
                final isDarkMode = theme.brightness == Brightness.dark;
                final colorScheme = theme.colorScheme;
                final policy = appState.getDeviceNetworkAccessPolicy(
                  client.macAddress,
                );
                final isBanned = appState.isWirelessBanned(client.macAddress);
                final canPause = client.isConnected || policy.hasAnyRestriction;

                final actionButtons = <Widget>[];

                // 0. Unban & Edit Ban Controls (if currently banned)
                if (isBanned && !client.isDumbApClient) {
                  actionButtons.add(
                    _buildRestrictedClientActionButton(
                      context: context,
                      isRestricted: isRpcMissing,
                      actionName: l10n?.btnUnbanClient ?? 'Unban Client',
                      child: OutlinedButton.icon(
                        onPressed: () => _unbanWirelessClient(context, client),
                        icon: Icon(
                          Icons.check_circle_outline_rounded,
                          size: 14,
                          color: colorScheme.primary,
                        ),
                        label: Text(
                          l10n?.btnUnbanClient ?? 'Unban Client',
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
                    ),
                  );
                  actionButtons.add(
                    _buildRestrictedClientActionButton(
                      context: context,
                      isRestricted: isRpcMissing,
                      actionName: l10n?.btnEditBan ?? 'Edit Ban',
                      child: OutlinedButton.icon(
                        onPressed: () => _banWirelessClient(context, client),
                        icon: Icon(
                          Icons.timer_outlined,
                          size: 14,
                          color: LuciStatusColors.warningColor(context),
                        ),
                        label: Text(
                          l10n?.btnEditBan ?? 'Edit Ban',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: LuciStatusColors.warningColor(context),
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
                            color: LuciStatusColors.warningColor(
                              context,
                            ).withValues(alpha: isDarkMode ? 0.6 : 0.4),
                            width: 0.9,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  );
                }

                // 1. Pause / Resume / Manage Internet Access
                if (canPause && !isBanned) {
                  final Color buttonColor;
                  final IconData buttonIcon;
                  final String buttonLabel;
                  String? badgeText;

                  if (policy.isEffectivelyBlocked) {
                    buttonColor = LuciStatusColors.connectedColor(context);
                    buttonIcon = Icons.play_arrow_rounded;
                    buttonLabel = l10n?.btnResumeAccess ?? 'Resume Access';
                  } else if (policy.hasAnyRestriction) {
                    buttonColor = LuciStatusColors.warningColor(context);
                    buttonIcon = Icons.shield_outlined;
                    buttonLabel = 'Manage Access';
                    if (policy.isIpv4OnlyBlocked) {
                      badgeText = 'IPv4';
                    } else if (policy.isIpv6OnlyBlocked) {
                      badgeText = 'IPv6';
                    }
                  } else {
                    buttonColor = colorScheme.error;
                    buttonIcon = Icons.pause_rounded;
                    buttonLabel = l10n?.btnPauseAccess ?? 'Pause Access';
                  }

                  actionButtons.add(
                    _buildRestrictedClientActionButton(
                      context: context,
                      isRestricted: isRpcMissing,
                      actionName: buttonLabel,
                      child: OutlinedButton(
                        onPressed: () =>
                            _showAccessControlSheet(context, client),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          side: BorderSide(
                            color: buttonColor.withValues(
                              alpha: isDarkMode ? 0.6 : 0.4,
                            ),
                            width: 0.9,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(buttonIcon, size: 15, color: buttonColor),
                            const SizedBox(width: 4),
                            Text(
                              buttonLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: buttonColor,
                              ),
                            ),
                            if (badgeText != null) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: buttonColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: buttonColor.withValues(alpha: 0.5),
                                    width: 0.6,
                                  ),
                                ),
                                child: Text(
                                  badgeText,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: buttonColor,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                }

                // 2. Ban Client (Available for all active & DHCP clients)
                if (!isBanned && !client.isDumbApClient) {
                  actionButtons.add(
                    _buildRestrictedClientActionButton(
                      context: context,
                      isRestricted: isRpcMissing,
                      actionName: l10n?.btnBanClient ?? 'Ban Client',
                      child: OutlinedButton.icon(
                        onPressed: () => _banWirelessClient(context, client),
                        icon: Icon(
                          Icons.block_rounded,
                          size: 14,
                          color: LuciStatusColors.warningColor(context),
                        ),
                        label: Text(
                          l10n?.btnBanClient ?? 'Ban Client',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: LuciStatusColors.warningColor(context),
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
                            color: LuciStatusColors.warningColor(
                              context,
                            ).withValues(alpha: isDarkMode ? 0.6 : 0.4),
                            width: 0.9,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  );
                }

                // 3. Static Lease Controls (Add / Edit / Remove)
                if (!client.isDumbApClient) {
                  final normMac = client.macAddress.toUpperCase().replaceAll(
                    '-',
                    ':',
                  );
                  final isStatic =
                      client.isStatic ||
                      appState.configuredStaticLeaseMacs.contains(normMac);

                  if (!isStatic && !_isIpv6Only(client)) {
                    actionButtons.add(
                      _buildRestrictedClientActionButton(
                        context: context,
                        isRestricted: isRpcMissing,
                        actionName: l10n?.btnStaticLease ?? 'Static Lease',
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _showAddStaticLeaseDialog(context, client),
                          icon: Icon(
                            Icons.push_pin_outlined,
                            size: 14,
                            color: colorScheme.primary,
                          ),
                          label: Text(
                            l10n?.btnStaticLease ?? 'Static Lease',
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
                      ),
                    );
                  }

                  if (isStatic) {
                    actionButtons.add(
                      _buildRestrictedClientActionButton(
                        context: context,
                        isRestricted: isRpcMissing,
                        actionName:
                            l10n?.btnEditStaticLease ?? 'Edit Static Lease',
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _showAddStaticLeaseDialog(context, client),
                          icon: Icon(
                            Icons.edit_outlined,
                            size: 14,
                            color: colorScheme.primary,
                          ),
                          label: Text(
                            l10n?.btnEditStaticLease ?? 'Edit Static Lease',
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
                      ),
                    );

                    actionButtons.add(
                      _buildRestrictedClientActionButton(
                        context: context,
                        isRestricted: isRpcMissing,
                        actionName: l10n?.btnRemoveLease ?? 'Remove Lease',
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _confirmRemoveStaticLease(context, client),
                          icon: Icon(
                            Icons.delete_outline,
                            size: 14,
                            color: colorScheme.error,
                          ),
                          label: Text(
                            l10n?.btnRemoveLease ?? 'Remove Lease',
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
                      ),
                    );
                  }
                }

                // 4. Bandwidth Speed Limit
                if (!client.isDumbApClient) {
                  final activeLimit = appState.getClientSpeedLimit(
                    client.macAddress,
                    routerId: appState.selectedRouter?.id,
                  );
                  final isRestricted =
                      activeLimit != null &&
                      activeLimit.isEffectivelyRestricted;

                  final Color speedBtnColor = isRestricted
                      ? (isDarkMode
                            ? Colors.amberAccent
                            : Colors.orange.shade800)
                      : colorScheme.primary;
                  final String speedLabel = isRestricted
                      ? (l10n?.speedLimitClientActionWithLimit(
                              activeLimit.compactSummary,
                            ) ??
                            'Limit: ${activeLimit.compactSummary}')
                      : (l10n?.speedLimitClientAction ?? 'Speed Limit');

                  actionButtons.add(
                    _buildRestrictedClientActionButton(
                      context: context,
                      isRestricted: isRpcMissing,
                      actionName: speedLabel,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final changed = await ClientSpeedLimitDialog.show(
                            context,
                            client: client,
                            initialLimit: activeLimit,
                            routerId: appState.selectedRouter?.id,
                          );
                          if (changed == true && mounted) {
                            setState(() {});
                          }
                        },
                        icon: Icon(
                          Icons.traffic_rounded,
                          size: 14,
                          color: speedBtnColor,
                        ),
                        label: Text(
                          speedLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: speedBtnColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          side: BorderSide(
                            color: speedBtnColor.withValues(
                              alpha: isDarkMode ? 0.6 : 0.4,
                            ),
                            width: 0.9,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
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

    final parentContext = Navigator.of(context).context;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          actionsOverflowButtonSpacing: 8,
          actionsOverflowDirection: VerticalDirection.down,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.error,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n?.dialogRemoveStaticLeaseTitle ?? 'Remove Static Lease',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              l10n?.dialogRemoveStaticLeaseMessage(
                    client.displayName,
                    client.macAddress,
                  ) ??
                  'Are you sure you want to remove the static IP reservation for "${client.displayName}" (${client.macAddress})?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n?.actionCancel ?? 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              child: Text(l10n?.btnRemoveReservation ?? 'Remove Reservation'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      final actionKey = 'remove_lease_${client.macAddress}';
      if (parentContext.mounted) {
        parentContext.showToastLoading(
          'Removing static lease for ${client.displayName}...',
          actionKey: actionKey,
        );
      }

      final appState = AppState.instance;

      // Find the static mapping record to get exact IP, DUID, and hostname configured on the router
      final normMac = client.macAddress.toUpperCase().replaceAll('-', ':');
      DhcpStaticMapping? existingMapping = appState.findStaticLeaseByMac(
        client.macAddress,
      );
      if (existingMapping == null && appState.dashboardData != null) {
        final dhcpOverview = DhcpDnsOverview.fromDashboardData(
          appState.dashboardData,
          isReviewerMode: appState.reviewerModeEnabled,
        );
        for (final s in dhcpOverview.staticMappings) {
          if (s.macAddress.toUpperCase().replaceAll('-', ':') == normMac) {
            existingMapping = s;
            break;
          }
        }
      }

      final targetIp =
          (existingMapping != null &&
              existingMapping.ipAddress.isNotEmpty &&
              existingMapping.ipAddress != 'N/A')
          ? existingMapping.ipAddress
          : (client.ipAddress != 'N/A' && client.ipAddress.isNotEmpty
                ? client.ipAddress
                : null);

      final hostname =
          (existingMapping != null &&
              existingMapping.hostname.isNotEmpty &&
              existingMapping.hostname != 'Unnamed Host')
          ? existingMapping.hostname
          : (client.staticLeaseName ??
                (client.hostname != 'Unknown' ? client.hostname : null));

      final duid =
          (existingMapping != null &&
              existingMapping.duid.isNotEmpty &&
              existingMapping.duid != 'N/A')
          ? existingMapping.duid
          : null;

      final success = await appState.deleteStaticLease(
        macAddress: client.macAddress,
        targetIp: targetIp,
        hostname: hostname,
        duid: duid,
        context: parentContext.mounted ? parentContext : null,
      );

      if (success) {
        appState.invalidateStaticLeasesCache();
        widget.onLeaseRemoved?.call(client.macAddress);
        if (mounted) setState(() {});
        if (parentContext.mounted) {
          parentContext.showToastSuccess(
            'Static lease removed for ${client.displayName}.',
            actionKey: actionKey,
          );
        }
        widget.onRefreshNeeded();
      } else {
        if (parentContext.mounted) {
          parentContext.showToastError(
            'Failed to remove static lease for ${client.displayName}.',
            subtitle:
                l10n?.toastErrorCheckPermissionsOrDhcp ??
                'Check router permissions or UCI DHCP configuration.',
            actionKey: actionKey,
          );
        }
      }
    }
  }

  Future<void> _showAccessControlSheet(
    BuildContext context,
    Client client,
  ) async {
    await DeviceNetworkAccessCard.showAsBottomSheet(context, client: client);
    if (mounted) setState(() {});
  }

  Future<void> _banWirelessClient(BuildContext context, Client client) async {
    final l10n = AppLocalizations.of(context);
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
                subtitle:
                    '${l10n?.toastErrorCheckPermissionsOrWireless ?? "Check router permissions or hostapd configuration"} (${client.macAddress}).',
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

    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          actionsOverflowButtonSpacing: 8,
          actionsOverflowDirection: VerticalDirection.down,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle_outline_rounded,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n?.dialogUnbanDeviceTitle ?? 'Unban Wireless Device?',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              l10n?.dialogUnbanDeviceMessage(
                    client.displayName,
                    client.macAddress,
                  ) ??
                  'Are you sure you want to unban "${client.displayName}" (${client.macAddress})? This will restore Wi-Fi association and remove firewall blocking rules.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n?.actionCancel ?? 'Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
              label: Text(l10n?.btnUnbanDevice ?? 'Unban Device'),
            ),
          ],
        );
      },
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
          subtitle:
              '${l10n?.toastErrorCheckPermissionsOrFirewall ?? "Check router permissions or firewall configuration"} (${client.macAddress}).',
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
    final l10n = AppLocalizations.of(context);
    context.showToastSuccess(
      l10n?.toastItemCopied(label) ?? '$label copied',
      subtitle: l10n?.toastCopiedToClipboard ?? 'Copied to clipboard.',
    );
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

  Widget _buildRestrictedClientActionButton({
    required BuildContext context,
    required Widget child,
    required bool isRestricted,
    required String actionName,
  }) {
    if (!isRestricted) return child;
    return Tooltip(
      message: 'Requires router RPC permissions',
      child: Opacity(
        opacity: 0.55,
        child: InkWell(
          onTap: () =>
              RpcPermissionsDialog.show(context, actionName: actionName),
          borderRadius: BorderRadius.circular(8),
          child: IgnorePointer(child: child),
        ),
      ),
    );
  }
}
