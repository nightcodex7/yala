// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yet_another_luci_app/screens/dashboard_screen.dart';
import 'package:yet_another_luci_app/screens/clients_screen.dart';
import 'package:yet_another_luci_app/screens/interfaces_screen.dart';
import 'package:yet_another_luci_app/screens/more_screen.dart';
import 'package:yet_another_luci_app/modules/wireless_management/screens/wireless_management_screen.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/widgets/scroll_jitter_guard.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/utils/gateway_utils.dart';
import 'package:yet_another_luci_app/services/secure_storage_service.dart';
import 'package:yet_another_luci_app/screens/login_screen.dart';
import 'package:yet_another_luci_app/utils/os_platform_integration.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';

class MainScreen extends ConsumerStatefulWidget {
  final int? initialTab;
  final String? interfaceToScroll;

  const MainScreen({super.key, this.initialTab, this.interfaceToScroll});

  /// Exposes multi-line nav measurement for adaptive layout testing and inspection.
  static bool shouldUseMultiLineNav({
    required BuildContext context,
    required double slotWidth,
    required List<String> labels,
    required TextScaler textScaler,
  }) => _MainScreenState.shouldUseMultiLineNav(
    context: context,
    slotWidth: slotWidth,
    labels: labels,
    textScaler: textScaler,
  );

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
    if (_selectedIndex != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(appStateProvider).setDashboardTabActive(false);
        }
      });
    }
  }

  AppState? _appState;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newAppState = ref.read(appStateProvider);
    if (_appState != newAppState) {
      _appState?.removeRouterBackOnlineListener(_handleRouterBackOnline);
      _appState = newAppState;
      _appState?.addRouterBackOnlineListener(_handleRouterBackOnline);
    }
  }

  @override
  void dispose() {
    _appState?.removeRouterBackOnlineListener(_handleRouterBackOnline);
    WidgetsBinding.instance.removeObserver(this);
    _appState?.pauseThroughputTimer();
    super.dispose();
  }

  void _handleRouterBackOnline(bool success) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    if (success) {
      context.showToastSuccess(
        l10n?.moreRouterOnline ?? 'Router Online',
        subtitle:
            l10n?.moreRouterOnlineSubtitle ??
            'Router is back online, reconnecting…',
        actionKey: 'router_reboot',
      );
    } else {
      context.showToastError(
        'Reboot Timeout',
        subtitle:
            'Router did not respond in time. Please check your connection.',
        actionKey: 'router_reboot',
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final appState = ref.read(appStateProvider);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      appState.pauseThroughputTimer();
    } else if (state == AppLifecycleState.resumed) {
      appState.handleAppResume();
      if (_selectedIndex == 0) {
        appState.resumeThroughputTimer(immediateTick: true);
      } else {
        appState.setDashboardTabActive(false);
      }
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
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _selectedIndex = safeIndex;
      _activatedTabs.add(safeIndex);
      _tabHistory.remove(safeIndex);
      _tabHistory.add(safeIndex);
    });

    ref.read(appStateProvider).setDashboardTabActive(safeIndex == 0);

    if (_selectedIndex != 1 && _currentInterfaceToScroll != null) {
      _clearInterfaceToScroll();
    }
  }

  Future<bool?> _showExitConfirmationDialog(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        icon: Icon(
          Icons.exit_to_app_rounded,
          color: colorScheme.primary,
          size: 28,
        ),
        title: Text(
          l10n?.exitDialogTitle ?? 'Exit Yala?',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Text(
            l10n?.exitDialogMessage ??
                'Are you sure you want to exit the application?',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n?.actionCancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n?.actionExit ?? 'Exit'),
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
        ref.read(appStateProvider).setDashboardTabActive(safeRequestedTab == 0);
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
    final connectionStatus = appState.connectionStatus;
    final colorScheme = Theme.of(context).colorScheme;
    final isTablet = LuciBreakpoints.isTablet(context);
    final l10n = AppLocalizations.of(context);

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

    final showConnectivityBanner =
        connectionStatus != RouterConnectionStatus.connected && !isRebooting;

    final topOffset = MediaQuery.paddingOf(context).top + kToolbarHeight;

    final contentWithBanner = Stack(
      children: [
        Positioned.fill(child: body),
        Positioned(
          top: topOffset,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: !showConnectivityBanner,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              offset: showConnectivityBanner
                  ? Offset.zero
                  : const Offset(0, -0.6),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                opacity: showConnectivityBanner ? 1.0 : 0.0,
                child: showConnectivityBanner
                    ? _buildConnectivityBanner(
                        context,
                        connectionStatus,
                        isDynamic: appState.useDynamicTheme,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ],
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
          ref.read(appStateProvider).setDashboardTabActive(_selectedIndex == 0);
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
          ref.read(appStateProvider).setDashboardTabActive(true);
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
                            onDestinationSelected: isRebooting
                                ? null
                                : _onItemTapped,
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
                                selectedIcon: const Icon(
                                  Icons.dashboard_rounded,
                                ),
                                label: Text(l10n?.navDashboard ?? 'Dashboard'),
                              ),
                              NavigationRailDestination(
                                icon: const Icon(Icons.lan_outlined),
                                selectedIcon: const Icon(Icons.lan),
                                label: Text(
                                  l10n?.navInterfaces ?? 'Interfaces',
                                ),
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
                                label: Text(l10n?.navClients ?? 'Clients'),
                              ),
                              NavigationRailDestination(
                                icon: const Icon(Icons.wifi_outlined),
                                selectedIcon: const Icon(Icons.wifi),
                                label: Text(l10n?.navWireless ?? 'Wireless'),
                              ),
                              NavigationRailDestination(
                                icon: const Icon(Icons.more_horiz_outlined),
                                selectedIcon: const Icon(Icons.more_horiz),
                                label: Text(l10n?.navMore ?? 'More'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const VerticalDivider(thickness: 1, width: 1),
                  Expanded(child: contentWithBanner),
                ],
              ),
            )
          // ── Phone layout: Custom bottom navigation bar ─────────────────────
          : Scaffold(
              body: contentWithBanner,
              bottomNavigationBar: Container(
                color: colorScheme.surfaceContainer,
                child: SafeArea(
                  top: false,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final textScaler = MediaQuery.textScalerOf(context);
                      final textScale = textScaler.scale(1.0);
                      final slotWidth = constraints.maxWidth / 5.0;

                      final labels = [
                        l10n?.navInterfaces ?? 'Interfaces',
                        l10n?.navClients ?? 'Clients',
                        l10n?.navDashboard ?? 'Dashboard',
                        l10n?.navWireless ?? 'Wireless',
                        l10n?.navMore ?? 'More',
                      ];

                      // Adaptive navigation layout:
                      // If any label wraps beyond 1 line (due to translation or accessibility text scaling),
                      // adapt bar height and items to multi-line mode (68px base, up to 2 lines).
                      // Otherwise, maintain compact single-line mode (54px base).
                      final isMultiLine = shouldUseMultiLineNav(
                        context: context,
                        slotWidth: slotWidth,
                        labels: labels,
                        textScaler: textScaler,
                      );

                      final barHeight = isMultiLine
                          ? (68.0 * textScale).clamp(66.0, 88.0)
                          : (54.0 * textScale).clamp(52.0, 64.0);
                      final centerCircleSize = isMultiLine ? 34.0 : 32.0;
                      const centerIconSize = 20.0;
                      const sideIconSize = 22.0;

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        height: barHeight,
                        color: colorScheme.surfaceContainer,
                        child: Row(
                          children: [
                            // 1. Interfaces
                            Expanded(
                              child: _buildNavItem(
                                index: 1,
                                label: labels[0],
                                icon: Icons.lan_outlined,
                                selectedIcon: Icons.lan,
                                isRebooting: isRebooting,
                                isMultiLine: isMultiLine,
                                iconSize: sideIconSize,
                              ),
                            ),
                            // 2. Clients
                            Expanded(
                              child: _buildNavItem(
                                index: 2,
                                label: labels[1],
                                icon: Icons.people_outline,
                                selectedIcon: Icons.people,
                                isRebooting: isRebooting,
                                isMultiLine: isMultiLine,
                                iconSize: sideIconSize,
                                badgeCount: appState.clients
                                    .where((c) => c.isConnected)
                                    .length,
                              ),
                            ),
                            // 3. Centered Distinct Dashboard Button (Index 0)
                            Expanded(
                              child: _buildDashboardNavItem(
                                label: labels[2],
                                isRebooting: isRebooting,
                                isMultiLine: isMultiLine,
                                circleSize: centerCircleSize,
                                iconSize: centerIconSize,
                              ),
                            ),
                            // 4. Wireless
                            Expanded(
                              child: _buildNavItem(
                                index: 3,
                                label: labels[3],
                                icon: Icons.wifi_outlined,
                                selectedIcon: Icons.wifi,
                                isRebooting: isRebooting,
                                isMultiLine: isMultiLine,
                                iconSize: sideIconSize,
                              ),
                            ),
                            // 5. More
                            Expanded(
                              child: _buildNavItem(
                                index: 4,
                                label: labels[4],
                                icon: Icons.more_horiz_outlined,
                                selectedIcon: Icons.more_horiz,
                                isRebooting: false,
                                isMultiLine: isMultiLine,
                                iconSize: sideIconSize,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildDashboardNavItem({
    required String label,
    required bool isRebooting,
    required bool isMultiLine,
    required double circleSize,
    required double iconSize,
  }) {
    final isSelected = _selectedIndex == 0;
    final colorScheme = Theme.of(context).colorScheme;
    final semanticText =
        '$label, tab 3 of 5. ${isSelected ? "Currently active tab." : "Double tap to switch to $label."}';

    final iconColor = isRebooting
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : (isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant);
    final labelColor = isRebooting
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : (isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant);

    return Semantics(
      selected: isSelected,
      button: true,
      label: semanticText,
      child: InkWell(
        onTap: isRebooting ? null : () => _onItemTapped(0),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 2.0,
            vertical: isMultiLine ? 4.0 : 2.0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                width: circleSize,
                height: circleSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.surfaceContainerHigh,
                ),
                child: Center(
                  child: Icon(
                    isSelected
                        ? Icons.dashboard_rounded
                        : Icons.dashboard_outlined,
                    color: iconColor,
                    size: iconSize,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: isMultiLine ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: labelColor,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Determines whether bottom navigation bar needs multi-line height based on label widths.
  static bool shouldUseMultiLineNav({
    required BuildContext context,
    required double slotWidth,
    required List<String> labels,
    required TextScaler textScaler,
  }) {
    if (slotWidth <= 0) return false;
    final availableWidth = (slotWidth - 6.0).clamp(10.0, double.infinity);
    final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
    const style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.normal,
      height: 1.15,
    );

    for (final label in labels) {
      if (label.isEmpty) continue;
      final textPainter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: textDirection,
        textScaler: textScaler,
        maxLines: 2,
      )..layout(maxWidth: availableWidth);

      if (textPainter.computeLineMetrics().length > 1) {
        return true;
      }
    }
    return false;
  }

  Widget _buildNavItem({
    required int index,
    required String label,
    required IconData icon,
    required IconData selectedIcon,
    required bool isRebooting,
    required bool isMultiLine,
    required double iconSize,
    int? badgeCount,
  }) {
    final isSelected = _selectedIndex == index;
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = isRebooting
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : (isSelected
              ? colorScheme.onSecondaryContainer
              : colorScheme.onSurfaceVariant);
    final labelColor = isRebooting
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : (isSelected ? colorScheme.onSurface : colorScheme.onSurfaceVariant);

    final semanticText =
        '$label, tab ${index + 1} of 5. ${isSelected ? "Currently active tab." : "Double tap to switch to $label."}';

    final hasBadge = badgeCount != null && badgeCount > 0;
    final badgeLabel = hasBadge
        ? (badgeCount > 99 ? '99+' : '$badgeCount')
        : '';

    return Semantics(
      selected: isSelected,
      button: true,
      label: semanticText,
      child: InkWell(
        onTap: isRebooting ? null : () => _onItemTapped(index),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 2.0,
            vertical: isMultiLine ? 4.0 : 2.0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // M3 Active Indicator Pill container
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                width: isSelected ? 48 : 32,
                height: 28,
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.secondaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Badge(
                    isLabelVisible: hasBadge,
                    label: Text(
                      badgeLabel,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onError,
                      ),
                    ),
                    backgroundColor: colorScheme.error,
                    child: Icon(
                      isSelected ? selectedIcon : icon,
                      color: iconColor,
                      size: iconSize,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: isMultiLine ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: labelColor,
                  height: 1.15,
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
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
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

  Widget _buildConnectivityBanner(
    BuildContext context,
    RouterConnectionStatus status, {
    bool isDynamic = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isReconnecting = status == RouterConnectionStatus.reconnecting;

    final Color bgColor;
    final Color borderColor;
    final Color textColor;
    final Color accentColor;

    if (isReconnecting) {
      if (isDynamic) {
        // Dynamic Theme: follow dynamic primary branding (e.g. Material You Blue)
        bgColor = colorScheme.primaryContainer.withValues(
          alpha: isDark ? 0.90 : 0.95,
        );
        borderColor = colorScheme.primary.withValues(alpha: 0.35);
        textColor = colorScheme.onPrimaryContainer;
        accentColor = colorScheme.primary;
      } else {
        // Amber Theme: follow signature warm amber tertiary branding
        bgColor = colorScheme.tertiaryContainer.withValues(
          alpha: isDark ? 0.90 : 0.95,
        );
        borderColor = colorScheme.tertiary.withValues(alpha: 0.35);
        textColor = colorScheme.onTertiaryContainer;
        accentColor = colorScheme.tertiary;
      }
    } else {
      // Disconnected: Error state
      bgColor = isDark && isDynamic
          ? Color.alphaBlend(
              colorScheme.error.withValues(alpha: 0.20),
              colorScheme.surfaceContainerHigh,
            ).withValues(alpha: 0.95)
          : colorScheme.errorContainer.withValues(alpha: isDark ? 0.90 : 0.95);
      borderColor = colorScheme.error.withValues(alpha: 0.35);
      textColor = colorScheme.onErrorContainer;
      accentColor = colorScheme.error;
    }

    final label = isReconnecting
        ? 'Reconnecting to router...'
        : 'Router disconnected';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20.0),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 460),
              padding: const EdgeInsets.symmetric(
                horizontal: 14.0,
                vertical: 7.0,
              ),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(20.0),
                border: Border.all(color: borderColor, width: 1.0),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(alpha: 0.10),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isReconnecting
                        ? Icons.sync_rounded
                        : Icons.wifi_off_rounded,
                    size: 16,
                    color: accentColor,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!isReconnecting) ...[
                    const SizedBox(width: 10),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          if (ActionRateLimiter.isRateLimited(
                            'retry_connection',
                            cooldown: const Duration(seconds: 1),
                          )) {
                            return;
                          }
                          ref
                              .read(appStateProvider)
                              .fetchDashboardData(force: true);
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9.0,
                            vertical: 3.5,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surface.withValues(
                              alpha: isDark ? 0.35 : 0.85,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: colorScheme.outline.withValues(
                                alpha: 0.30,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.refresh_rounded,
                                size: 13,
                                color: textColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Retry',
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
