// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/screens/dashboard_screen.dart';
import 'package:yet_another_luci_app/screens/clients_screen.dart';
import 'package:yet_another_luci_app/screens/interfaces_screen.dart';
import 'package:yet_another_luci_app/screens/more_screen.dart';
import 'package:yet_another_luci_app/modules/wireless_management/screens/wireless_management_screen.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/widgets/scroll_jitter_guard.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/utils/gateway_utils.dart';
import 'package:yet_another_luci_app/services/secure_storage_service.dart';
import 'package:yet_another_luci_app/screens/login_screen.dart';
import 'package:yet_another_luci_app/utils/os_platform_integration.dart';

class MainScreen extends ConsumerStatefulWidget {
  final int? initialTab;
  final String? interfaceToScroll;

  const MainScreen({super.key, this.initialTab, this.interfaceToScroll});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  String? _currentInterfaceToScroll;
  final Set<int> _activatedTabs = {0};
  final List<int> _tabHistory = [0];
  bool _isRedirectingToLogin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialTab != null) {
      _selectedIndex = widget.initialTab!.clamp(0, 4);
    }
    _activatedTabs.add(_selectedIndex);
    _tabHistory.clear();
    _tabHistory.add(_selectedIndex);
    _currentInterfaceToScroll = widget.interfaceToScroll;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final appState = ref.read(appStateProvider);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      appState.cancelThroughputTimer();
    } else if (state == AppLifecycleState.resumed) {
      appState.handleAppResume();
    }
  }

  @override
  void didUpdateWidget(MainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.interfaceToScroll != oldWidget.interfaceToScroll) {
      _currentInterfaceToScroll = widget.interfaceToScroll;
    }

    if (widget.initialTab != oldWidget.initialTab &&
        widget.initialTab != null) {
      _selectedIndex = widget.initialTab!.clamp(0, 4);
      _activatedTabs.add(_selectedIndex);
      _tabHistory.remove(_selectedIndex);
      _tabHistory.add(_selectedIndex);
    }
  }

  void _clearInterfaceToScroll() {
    if (_currentInterfaceToScroll != null) {
      setState(() {
        _currentInterfaceToScroll = null;
      });
    }
  }

  void _onItemTapped(int index) {
    FocusScope.of(context).unfocus();
    final safeIndex = index.clamp(0, 4);
    if (_selectedIndex == safeIndex) return;
    setState(() {
      _selectedIndex = safeIndex;
      _activatedTabs.add(safeIndex);
      _tabHistory.remove(safeIndex);
      _tabHistory.add(safeIndex);
    });

    if (_selectedIndex != 1 && _currentInterfaceToScroll != null) {
      _clearInterfaceToScroll();
    }
  }

  Future<bool?> _showExitConfirmationDialog(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.exit_to_app_rounded,
                color: colorScheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Exit Yala?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to exit the application?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);

    // Guardrail: If session is completely unauthenticated and not in reviewer mode,
    // redirect smoothly to LoginScreen instead of leaving the app on a blank main screen.
    if (appState.hasActiveSession) {
      _isRedirectingToLogin = false;
    } else if (!appState.isLoading && !_isRedirectingToLogin) {
      _isRedirectingToLogin = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted &&
            !ref.read(appStateProvider).hasActiveSession &&
            !ref.read(appStateProvider).isLoading) {
          final creds = await SecureStorageService().getCredentials();
          final detectedGateway = await GatewayUtils.detectGatewayIp();

          if (!mounted) return;
          final currentState = ref.read(appStateProvider);
          if (currentState.hasActiveSession || currentState.isLoading) {
            _isRedirectingToLogin = false;
            return;
          }

          final effectiveIp =
              (creds['ipAddress'] != null && creds['ipAddress']!.isNotEmpty)
              ? creds['ipAddress']
              : detectedGateway;

          if (!mounted || !context.mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => LoginScreen(
                initialIp: effectiveIp,
                initialUsername: creds['username'],
                initialPassword: creds['password'],
              ),
            ),
            (route) => false,
          );
        } else {
          _isRedirectingToLogin = false;
        }
      });
    }

    if (appState.requestedTab != null &&
        appState.requestedTab != _selectedIndex) {
      final safeRequestedTab = appState.requestedTab!.clamp(0, 4);
      final requestedInterface = appState.requestedInterfaceToScroll;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        FocusScope.of(context).unfocus();
        setState(() {
          _selectedIndex = safeRequestedTab;
          _activatedTabs.add(safeRequestedTab);
          _tabHistory.remove(safeRequestedTab);
          _tabHistory.add(safeRequestedTab);
          if (requestedInterface != null) {
            _currentInterfaceToScroll = requestedInterface;
          }
        });
        appState.requestedTab = null;
        appState.requestedInterfaceToScroll = null;
      });
    }

    if (appState.reviewerModeEnabled &&
        !appState.hasShownReviewerNotice &&
        !appState.isDashboardLoading &&
        appState.dashboardData != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndShowReviewerNotice();
      });
    }

    final isRebooting = appState.isRebooting;
    final colorScheme = Theme.of(context).colorScheme;
    final isTablet = LuciBreakpoints.isTablet(context);

    // Build the shared IndexedStack content used in both phone and tablet layouts
    final body = ScrollJitterGuard(
      child: IndexedStack(
        index: _selectedIndex,
        children: [
          _activatedTabs.contains(0)
              ? DashboardScreen(isTabActive: _selectedIndex == 0)
              : const SizedBox.shrink(),
          _activatedTabs.contains(1)
              ? InterfacesScreen(
                  scrollToInterface: _currentInterfaceToScroll,
                  onScrollComplete: _clearInterfaceToScroll,
                  isTabActive: _selectedIndex == 1,
                )
              : const SizedBox.shrink(),
          _activatedTabs.contains(2)
              ? ClientsScreen(isTabActive: _selectedIndex == 2)
              : const SizedBox.shrink(),
          _activatedTabs.contains(3)
              ? WirelessManagementScreen(isTabActive: _selectedIndex == 3)
              : const SizedBox.shrink(),
          _activatedTabs.contains(4)
              ? const MoreScreen()
              : const SizedBox.shrink(),
        ],
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        // 1. If currently on a secondary tab, navigate back to previous tab or Dashboard
        if (_tabHistory.length > 1) {
          setState(() {
            _tabHistory.removeLast();
            final previousTab = _tabHistory.last;
            _selectedIndex = previousTab;
            if (_selectedIndex != 1 && _currentInterfaceToScroll != null) {
              _clearInterfaceToScroll();
            }
          });
          return;
        } else if (_selectedIndex != 0) {
          setState(() {
            _selectedIndex = 0;
            _tabHistory.clear();
            _tabHistory.add(0);
            if (_currentInterfaceToScroll != null) {
              _clearInterfaceToScroll();
            }
          });
          return;
        }

        // 2. Already on Dashboard (root) — prompt user with exit confirmation dialog
        final shouldExit = await _showExitConfirmationDialog(context);
        if (shouldExit == true && context.mounted) {
          await OsPlatformIntegration.exitApp(context: context);
        }
      },
      // ── Tablet / Chromebook / DeX layout: NavigationRail on the left ─────────
      child: isTablet
          ? Scaffold(
              body: Row(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: NavigationRail(
                            selectedIndex: _selectedIndex,
                            onDestinationSelected:
                                isRebooting ? null : _onItemTapped,
                            labelType: NavigationRailLabelType.all,
                            useIndicator: true,
                            indicatorColor: colorScheme.primaryContainer,
                            selectedIconTheme: IconThemeData(
                              color: colorScheme.onPrimaryContainer,
                            ),
                            unselectedIconTheme: IconThemeData(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            selectedLabelTextStyle: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                            unselectedLabelTextStyle: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            backgroundColor: colorScheme.surfaceContainer,
                            destinations: [
                              NavigationRailDestination(
                                icon: const Icon(Icons.dashboard_outlined),
                                selectedIcon: const Icon(Icons.dashboard_rounded),
                                label: const Text('Dashboard'),
                              ),
                              NavigationRailDestination(
                                icon: const Icon(Icons.lan_outlined),
                                selectedIcon: const Icon(Icons.lan),
                                label: const Text('Interfaces'),
                              ),
                              NavigationRailDestination(
                                icon: Builder(
                                  builder: (context) {
                                    final connectedCount = appState.clients
                                        .where((c) => c.isConnected)
                                        .length;
                                    return Badge(
                                      isLabelVisible: connectedCount > 0,
                                      label: Text(
                                        connectedCount > 99
                                            ? '99+'
                                            : '$connectedCount',
                                      ),
                                      child: const Icon(Icons.people_outline),
                                    );
                                  },
                                ),
                                selectedIcon: const Icon(Icons.people),
                                label: const Text('Clients'),
                              ),
                              NavigationRailDestination(
                                icon: const Icon(Icons.wifi_outlined),
                                selectedIcon: const Icon(Icons.wifi),
                                label: const Text('Wireless'),
                              ),
                              NavigationRailDestination(
                                icon: const Icon(Icons.more_horiz_outlined),
                                selectedIcon: const Icon(Icons.more_horiz),
                                label: const Text('More'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const VerticalDivider(thickness: 1, width: 1),
                  Expanded(child: body),
                ],
              ),
            )
          // ── Phone layout: Custom bottom navigation bar ─────────────────────
          : Scaffold(
              body: body,
              bottomNavigationBar: SafeArea(
                child: SizedBox(
                  height: 72,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.bottomCenter,
                    children: [
                      // Flat Matt Bottom Bar Container
                      Container(
                        height: 60,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainer,
                          border: Border(
                            top: BorderSide(
                              color: colorScheme.outlineVariant.withValues(
                                alpha: 0.2,
                              ),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Left Wing (Interfaces & Clients)
                            Expanded(
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildNavItem(
                                    index: 1,
                                    label: 'Interfaces',
                                    icon: Icons.lan_outlined,
                                    selectedIcon: Icons.lan,
                                    isRebooting: isRebooting,
                                  ),
                                  _buildNavItem(
                                    index: 2,
                                    label: 'Clients',
                                    icon: Icons.people_outline,
                                    selectedIcon: Icons.people,
                                    isRebooting: isRebooting,
                                    badgeCount: appState.clients
                                        .where((c) => c.isConnected)
                                        .length,
                                  ),
                                ],
                              ),
                            ),
                            // Center Clearance Spacer for Elevated Dashboard Badge
                            const SizedBox(width: 64),
                            // Right Wing (Wireless & More)
                            Expanded(
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildNavItem(
                                    index: 3,
                                    label: 'Wireless',
                                    icon: Icons.wifi_outlined,
                                    selectedIcon: Icons.wifi,
                                    isRebooting: isRebooting,
                                  ),
                                  _buildNavItem(
                                    index: 4,
                                    label: 'More',
                                    icon: Icons.more_horiz_outlined,
                                    selectedIcon: Icons.more_horiz,
                                    isRebooting: false,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Solid Flat Matt Circular Center Dashboard Badge Button (Index 0)
                      Align(
                        alignment: Alignment.topCenter,
                        child: Transform.translate(
                          offset: const Offset(0, -12),
                          child: GestureDetector(
                            onTap: () {
                              if (isRebooting) return;
                              _onItemTapped(0);
                            },
                            behavior: HitTestBehavior.opaque,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _selectedIndex == 0
                                        ? colorScheme.primary
                                        : colorScheme.surfaceContainerHigh,
                                    border: Border.all(
                                      color: colorScheme.surface,
                                      width: 3,
                                    ),
                                  ),
                                  child: Icon(
                                    _selectedIndex == 0
                                        ? Icons.dashboard_rounded
                                        : Icons.dashboard_outlined,
                                    color: _selectedIndex == 0
                                        ? colorScheme.onPrimary
                                        : colorScheme.onSurfaceVariant,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Dashboard',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: _selectedIndex == 0
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: _selectedIndex == 0
                                        ? colorScheme.primary
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
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

  Widget _buildNavItem({
    required int index,
    required String label,
    required IconData icon,
    required IconData selectedIcon,
    required bool isRebooting,
    int? badgeCount,
  }) {
    final isSelected = _selectedIndex == index;
    final colorScheme = Theme.of(context).colorScheme;
    final color = isRebooting
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : (isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant);

    final semanticText =
        '$label, tab ${index + 1} of 5. ${isSelected ? "Currently active tab." : "Double tap to switch to $label."}';

    return Semantics(
      selected: isSelected,
      button: true,
      label: semanticText,
      child: InkWell(
        onTap: isRebooting ? null : () => _onItemTapped(index),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    isSelected ? selectedIcon : icon,
                    color: color,
                    size: 24,
                  ),
                  if (badgeCount != null && badgeCount > 0)
                    Align(
                      alignment: Alignment.topRight,
                      child: Transform.translate(
                        offset: const Offset(8, -4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.secondary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 14,
                            minHeight: 14,
                          ),
                          child: Text(
                            badgeCount > 99 ? '99+' : '$badgeCount',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onPrimary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _checkAndShowReviewerNotice() {
    if (!mounted) return;
    final appState = ref.read(appStateProvider);
    if (appState.reviewerModeEnabled &&
        !appState.hasShownReviewerNotice &&
        !appState.isDashboardLoading &&
        appState.dashboardData != null) {
      appState.markReviewerNoticeShown();
      _showReviewerInfoDialog(context);
    }
  }

  void _showReviewerInfoDialog(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.rate_review_outlined,
                color: colorScheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reviewer Mode Active',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    'Simulated Router Session',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You are exploring Yet Another LuCI App in Reviewer Mode.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'This session provides pre-loaded mock datasets, simulating live OpenWrt router interfaces, connected clients, and performance metrics without needing an active router connection.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'To manage a physical OpenWrt router, toggle off Reviewer Mode in More > Connection Settings.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'GOT IT',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
