// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:flutter/services.dart';
import 'package:yet_another_luci_app/models/interface.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/models/network_topology.dart';
import 'package:yet_another_luci_app/widgets/network_topology_card.dart';
import 'dart:math';
import 'package:yet_another_luci_app/widgets/luci_app_bar.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/widgets/luci_loading_states.dart';
import 'package:yet_another_luci_app/widgets/luci_refresh_components.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';

class InterfacesScreen extends ConsumerStatefulWidget {
  final String? scrollToInterface;
  final VoidCallback? onScrollComplete;
  final bool isTabActive;

  const InterfacesScreen({
    super.key,
    this.scrollToInterface,
    this.onScrollComplete,
    this.isTabActive = true,
  });

  @override
  ConsumerState<InterfacesScreen> createState() => _InterfacesScreenState();
}

class _InterfacesScreenState extends ConsumerState<InterfacesScreen> {
  final ScrollController _scrollController = ScrollController();
  String? _targetInterface;
  String? _expandedInterface;
  final Map<String, GlobalKey> _interfaceKeys = {};
  final Map<String, bool> _stagedWiredInterfaceStates = {};
  final Map<String, bool> _stagedWirelessInterfaceStates = {};
  bool _isSaving = false;
  Widget? _lastRenderedScaffold;
  String? _lastSelectedRouterId;

  dynamic _lastInterfaceDump;
  dynamic _lastNetworkDevices;
  String? _lastWiredRouterIp;
  int _lastStagedWiredHash = 0;
  List<NetworkInterface>? _cachedWiredList;

  dynamic _lastWirelessData;
  dynamic _lastUciWireless;
  String? _lastWirelessRouterIp;
  int _lastStagedWirelessHash = 0;
  List<Map<String, dynamic>>? _cachedWirelessList;

  bool _isWiredAccessInterface(NetworkInterface iface, String? routerIp) {
    if (routerIp == null || routerIp.isEmpty) return false;
    if (iface.ipAddress == routerIp) return true;
    final gate = iface.gateway;
    if (gate != null && gate == routerIp) return true;
    return false;
  }

  bool _isWirelessAccessInterface(
    Map<String, dynamic> iface,
    String? routerIp,
  ) {
    if (routerIp == null || routerIp.isEmpty) return false;
    final details = iface['details'] as Map<String, dynamic>?;
    if (details != null) {
      final ip = details['IP Address']?.toString();
      if (ip != null && ip == routerIp) return true;
    }
    return false;
  }

  Future<bool> _showCriticalLockoutWarningDialog(String interfaceName) async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          actionsOverflowButtonSpacing: 8,
          actionsOverflowDirection: VerticalDirection.down,
          icon: Icon(
            Icons.gpp_maybe_rounded,
            color: theme.colorScheme.error,
            size: 36,
          ),
          title: Text(
            l10n?.lockoutWarningTitle ?? 'CRITICAL LOCKOUT WARNING',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n?.lockoutWarningBody(interfaceName) ??
                      'Disabling active access interface "$interfaceName" will lock you out of this router!\n',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  l10n?.lockoutWarningDesc ??
                      'This is your ACTIVE ACCESS INTERFACE hosting your management session. Disabling it will immediately break communication between the app and the router.',
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withValues(
                      alpha: 0.3,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.colorScheme.error.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.report_problem,
                        size: 18,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n?.lockoutWarningSure ??
                              'Are you absolutely sure you want to proceed?',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.w600,
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
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n?.actionCancel ?? 'Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n?.btnDisableInterface ?? 'Disable Interface'),
            ),
          ],
        );
      },
    );
    return confirm ?? false;
  }

  Future<bool> _showRestartAccessWarningDialog(String interfaceName) async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final warnColor = LuciStatusColors.warningColor(ctx);
        return AlertDialog(
          actionsOverflowButtonSpacing: 8,
          actionsOverflowDirection: VerticalDirection.down,
          icon: Icon(Icons.warning_amber_rounded, color: warnColor, size: 36),
          title: Text(
            l10n?.activeAccessRestartTitle ?? 'ACTIVE ACCESS RESTART',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n?.activeAccessRestartBody(interfaceName) ??
                      'Restarting active access interface "$interfaceName" will temporarily sever your app connection!\n',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  l10n?.activeAccessRestartDesc ??
                      'This is your ACTIVE ACCESS INTERFACE hosting your management session. Restarting it will temporarily break communication until the interface re-establishes network binding.',
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: LuciStatusColors.warningBg(ctx),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: LuciStatusColors.warningBorder(ctx),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.sync_problem, size: 18, color: warnColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n?.activeAccessRestartNotice ??
                              'Temporary Disconnection: Please allow a few seconds for the router to complete interface re-binding.',
                          style: TextStyle(
                            fontSize: 11,
                            color: LuciStatusColors.warningText(ctx),
                            fontWeight: FontWeight.w600,
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
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n?.actionCancel ?? 'Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: warnColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                l10n?.btnRestartTempDisconnect ??
                    'Restart (Temporary Disconnect)',
              ),
            ),
          ],
        );
      },
    );
    return confirm ?? false;
  }

  Future<bool> _showRestartWanWarningDialog(String interfaceName) async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          actionsOverflowButtonSpacing: 8,
          actionsOverflowDirection: VerticalDirection.down,
          icon: Icon(
            Icons.public_off_outlined,
            color: theme.colorScheme.primary,
            size: 36,
          ),
          title: Text(
            l10n?.restartWanTitle ?? 'RESTART WAN INTERFACE',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n?.restartWanBody(interfaceName) ??
                      'Restarting WAN interface "$interfaceName" will renew its internet lease and drop active WAN connections.\n',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  l10n?.restartWanDesc ??
                      'All devices connected to this router will temporarily lose external internet access until the WAN link re-connects.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n?.actionCancel ?? 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                l10n?.btnRestartWanInterface ?? 'Restart WAN Interface',
              ),
            ),
          ],
        );
      },
    );
    return confirm ?? false;
  }

  Future<bool> _showRestartGeneralConfirmDialog(String interfaceName) async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        title: Text(
          l10n?.restartInterfaceConfirmTitle(interfaceName) ??
              'Restart Interface "$interfaceName"?',
        ),
        content: SingleChildScrollView(
          child: Text(
            l10n?.restartInterfaceConfirmMessage(interfaceName) ??
                'Are you sure you want to restart network interface "$interfaceName"?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n?.actionCancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n?.btnRestartInterface ?? 'Restart Interface'),
          ),
        ],
      ),
    );
    return confirm ?? false;
  }

  Future<void> _restartWiredInterface(
    NetworkInterface iface,
    String? routerIp,
  ) async {
    final isAccess = _isWiredAccessInterface(iface, routerIp);
    final isWan =
        iface.name.toLowerCase().contains('wan') || iface.gateway != null;

    bool confirm = false;
    if (isAccess) {
      confirm = await _showRestartAccessWarningDialog(iface.name);
    } else if (isWan) {
      confirm = await _showRestartWanWarningDialog(iface.name);
    } else {
      confirm = await _showRestartGeneralConfirmDialog(iface.name);
    }

    if (!confirm) return;

    if (!mounted) return;

    final actionKey = 'restart_iface_${iface.name}';
    if (ActionRateLimiter.isRateLimited(
      actionKey,
      cooldown: const Duration(seconds: 2),
    )) {
      return;
    }
    context.showToastLoading(
      'Restarting Interface',
      subtitle: 'Restarting interface "${iface.name}"...',
      actionKey: actionKey,
    );

    final appState = ref.read(appStateProvider);
    final success = await appState.restartWiredInterface(
      iface.name,
      context: context,
    );

    if (!mounted) return;

    if (success) {
      appState.invalidateInFlightDashboardFetches();
      context.showToastSuccess(
        'Interface Restarted',
        subtitle: 'Interface "${iface.name}" restarted successfully.',
        actionKey: actionKey,
      );
      await appState.fetchDashboardData();
    } else {
      context.showToastError(
        'Restart Failed',
        subtitle: 'Failed to restart interface "${iface.name}".',
        actionKey: actionKey,
      );
    }
  }

  Future<void> _restartWirelessInterface(
    String sectionKey,
    String displayName,
    bool isAccess,
    bool isWan, {
    String? radioName,
  }) async {
    bool confirm = false;
    if (isAccess) {
      confirm = await _showRestartAccessWarningDialog(displayName);
    } else if (isWan) {
      confirm = await _showRestartWanWarningDialog(displayName);
    } else {
      confirm = await _showRestartGeneralConfirmDialog(displayName);
    }

    if (!confirm) return;

    if (!mounted) return;

    final actionKey = 'restart_wifi_$sectionKey';
    if (ActionRateLimiter.isRateLimited(
      actionKey,
      cooldown: const Duration(seconds: 2),
    )) {
      return;
    }
    context.showToastLoading(
      'Restarting Wireless',
      subtitle: 'Restarting wireless interface "$displayName"...',
      actionKey: actionKey,
    );

    final appState = ref.read(appStateProvider);
    final success = await appState.restartWirelessInterface(
      sectionKey,
      radioName: radioName,
      context: context,
    );

    if (!mounted) return;

    if (success) {
      appState.invalidateInFlightDashboardFetches();
      context.showToastSuccess(
        'Wireless Restarted',
        subtitle: 'Wireless interface "$displayName" restarted successfully.',
        actionKey: actionKey,
      );
      await appState.fetchDashboardData();
    } else {
      context.showToastError(
        'Restart Failed',
        subtitle: 'Failed to restart wireless interface "$displayName".',
        actionKey: actionKey,
      );
    }
  }

  Future<void> _toggleWiredInterface(
    NetworkInterface iface,
    bool newValue,
    String? routerIp,
  ) async {
    final isAccess = _isWiredAccessInterface(iface, routerIp);
    if (!newValue && isAccess) {
      final confirm = await _showCriticalLockoutWarningDialog(iface.name);
      if (!confirm) return;
    }

    setState(() {
      if (newValue == iface.isUp) {
        _stagedWiredInterfaceStates.remove(iface.name);
      } else {
        _stagedWiredInterfaceStates[iface.name] = newValue;
      }
    });
  }

  Future<void> _toggleWirelessInterface(
    String sectionKey,
    String displayName,
    bool originalEnabled,
    bool isAccess,
    bool newValue,
  ) async {
    if (!newValue && isAccess) {
      final confirm = await _showCriticalLockoutWarningDialog(displayName);
      if (!confirm) return;
    }

    setState(() {
      if (newValue == originalEnabled) {
        _stagedWirelessInterfaceStates.remove(sectionKey);
      } else {
        _stagedWirelessInterfaceStates[sectionKey] = newValue;
      }
    });
  }

  Future<void> _saveChanges() async {
    if (_stagedWiredInterfaceStates.isEmpty &&
        _stagedWirelessInterfaceStates.isEmpty) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final appState = ref.read(appStateProvider);
    bool overallSuccess = true;
    bool caughtError = false;

    try {
      for (final entry in _stagedWiredInterfaceStates.entries) {
        if (!mounted) return;
        final success = await appState.updateWiredInterfaceStatus(
          entry.key,
          entry.value,
          context: mounted ? context : null,
        );
        if (!success) overallSuccess = false;
      }

      for (final entry in _stagedWirelessInterfaceStates.entries) {
        if (!mounted) return;
        final success = await appState.updateWirelessInterfaceStatus(
          entry.key,
          entry.value,
          context: mounted ? context : null,
        );
        if (!success) overallSuccess = false;
      }
    } catch (e) {
      overallSuccess = false;
      caughtError = true;
      if (mounted) {
        context.showToastError(
          'Apply Failed',
          subtitle: LuciToastManager.parseErrorReason(e),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          if (overallSuccess) {
            _stagedWiredInterfaceStates.clear();
            _stagedWirelessInterfaceStates.clear();
          }
        });
      }
    }

    if (!mounted) return;

    if (overallSuccess) {
      context.showToastSuccess(
        'Changes Applied',
        subtitle: 'Interface state changes applied successfully.',
      );
      appState.invalidateInFlightDashboardFetches();
      unawaited(appState.fetchDashboardData());
    } else if (!caughtError) {
      context.showToastError(
        'Apply Failed',
        subtitle: 'Some interface state changes failed to apply.',
      );
    }
  }

  Future<void> _confirmAndDiscardChanges() async {
    setState(() {
      _stagedWiredInterfaceStates.clear();
      _stagedWirelessInterfaceStates.clear();
    });
  }

  Widget _buildUnsavedChangesBottomBar(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final count =
        _stagedWiredInterfaceStates.length +
        _stagedWirelessInterfaceStates.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Icon(Icons.edit_note, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n?.interfacesModifiedCount(count) ??
                    '$count interface(s) modified',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            OutlinedButton(
              onPressed: _isSaving ? null : _confirmAndDiscardChanges,
              child: Text(l10n?.actionDiscard ?? 'Discard'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _isSaving ? null : () => _saveChanges(),
              icon: _isSaving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check, size: 18),
              label: Text(l10n?.actionSave ?? 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  /// Safely extract a String from a UCI config value that may be a List or String.
  static String _uciString(dynamic value, [String fallback = '']) {
    if (value is String) return value;
    if (value is List) {
      return value.isNotEmpty ? value.first.toString() : fallback;
    }
    return value?.toString() ?? fallback;
  }

  // Unified key generator for all interfaces
  String _interfaceKey({String? name, String? ssid, String? deviceName}) {
    if (ssid != null && ssid.trim().isNotEmpty) {
      return ssid.trim(); // SSID is case sensitive
    } else if (deviceName != null && deviceName.trim().isNotEmpty) {
      return deviceName.trim().toLowerCase();
    } else if (name != null && name.trim().isNotEmpty) {
      return name.trim().toLowerCase();
    }
    return '';
  }

  // Unified key generator and matcher for all interfaces
  String _normalizeInterfaceKey(String? value) {
    return (value ?? '').trim().toLowerCase();
  }

  String _interfaceKeyForWireless({
    String? ssid,
    String? radioName,
    String? deviceName,
    String? name,
  }) {
    final radio = (radioName ?? '').trim();
    final ssidTrimmed = (ssid ?? '').trim();

    // If SSID is empty, we need to ensure uniqueness even with same radio
    if (ssidTrimmed.isEmpty) {
      // Use device name as fallback for uniqueness
      final device = (deviceName ?? '').trim();
      if (device.isNotEmpty && device != radio) {
        return '${ssidTrimmed.toLowerCase()}__${device.toLowerCase()}';
      }
      // Use interface name as fallback
      final interfaceName = (name ?? '').trim();
      if (interfaceName.isNotEmpty && interfaceName != radio) {
        return '${ssidTrimmed.toLowerCase()}__${interfaceName.toLowerCase()}';
      }
      // If all names are the same, use deterministic radio fallback
      return '${ssidTrimmed.toLowerCase()}__${radio.toLowerCase()}_fallback';
    }

    // If SSID is not empty, use SSID + radio
    return '${ssidTrimmed.toLowerCase()}__${radio.toLowerCase()}';
  }

  @override
  void initState() {
    super.initState();
    _targetInterface = widget.scrollToInterface;
    if (_targetInterface != null) {
      // Delay scrolling to allow the widget to build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToInterface(_targetInterface!);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lastRenderedScaffold = null;
  }

  @override
  void didUpdateWidget(InterfacesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isTabActive != widget.isTabActive && widget.isTabActive) {
      _lastRenderedScaffold = null;
    }

    // Handle parameter changes
    if (widget.scrollToInterface != oldWidget.scrollToInterface) {
      _targetInterface = widget.scrollToInterface;
      if (_targetInterface != null) {
        // Delay scrolling to allow the widget to build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToInterface(_targetInterface!);
        });
      } else {
        // Clear target interface if no new target is provided
        setState(() {
          _targetInterface = null;
        });
      }
    }
  }

  @override
  void dispose() {
    // Clear target interface when widget is disposed
    _targetInterface = null;
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToInterface(String interfaceName) {
    if (!_scrollController.hasClients) return;

    // Find the target interface and calculate its position
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        // Get the app state to access interface data
        final appState = ref.read(appStateProvider);
        final dashboardData = appState.dashboardData;

        if (dashboardData != null) {
          // Check wired interfaces first
          final rawWired = dashboardData['interfaceDump']?['interface'];
          final wiredInterfaces = rawWired is List
              ? rawWired
              : (rawWired is Map ? rawWired.values.toList() : null);
          if (wiredInterfaces != null) {
            for (int i = 0; i < wiredInterfaces.length; i++) {
              final iface = wiredInterfaces[i] as Map<String, dynamic>;
              final name = iface['interface'] as String? ?? '';
              final keyStr = _interfaceKey(name: name);
              // Use exact matching only
              if (keyStr == interfaceName.toLowerCase()) {
                _scrollToExpandedCard(keyStr);
                return;
              }
            }
          }

          // If not found in wired, check wireless interfaces
          final wirelessData =
              dashboardData['wireless'] as Map<String, dynamic>?;
          if (wirelessData != null) {
            final normalizedTarget = _normalizeInterfaceKey(interfaceName);
            wirelessData.forEach((radioName, radioData) {
              final rawIfaces = radioData['interfaces'];
              final interfaces = rawIfaces is List
                  ? rawIfaces
                  : (rawIfaces is Map ? rawIfaces.values.toList() : null);
              if (interfaces != null) {
                for (var i = 0; i < interfaces.length; i++) {
                  final interface = interfaces[i];
                  final config = interface['config'] ?? {};
                  final iwinfo = interface['iwinfo'] ?? {};
                  final deviceName = _uciString(config['device'], radioName);
                  final ssid = _uciString(iwinfo['ssid']).isNotEmpty
                      ? _uciString(iwinfo['ssid'])
                      : _uciString(config['ssid']);
                  final name = interface['name'] ?? '';
                  final keyStr = _interfaceKeyForWireless(
                    ssid: ssid,
                    radioName: radioName,
                    deviceName: deviceName,
                    name: name,
                  );
                  // Generate all possible normalized keys for matching
                  final ssidKey = _normalizeInterfaceKey(ssid);
                  final deviceKey = _normalizeInterfaceKey(deviceName);
                  final nameKey = _normalizeInterfaceKey(name);
                  // Match against all possible keys
                  if (normalizedTarget == ssidKey ||
                      normalizedTarget == deviceKey ||
                      normalizedTarget == nameKey) {
                    _scrollToExpandedCard(keyStr);
                    return;
                  }
                }
              }
            });
          }
        }

        // If not found, use section-based scrolling
        if (interfaceName.toLowerCase().contains('wifi') ||
            interfaceName.toLowerCase().contains('wireless') ||
            interfaceName.toLowerCase().contains('radio')) {
          _scrollToSection(200); // Wireless section
        } else {
          _scrollToSection(80); // Wired section
        }
      }
    });
  }

  double _headerOffset(BuildContext context) {
    // App bar (56) + section header (60)
    return 116.0;
  }

  void _scrollToExpandedCard(String keyStr, {int retry = 0}) {
    if (!mounted) return;

    // Set the expanded interface
    if (_expandedInterface != keyStr) {
      setState(() {
        _expandedInterface = keyStr;
      });

      // Wait for the expansion animation to complete (400ms) before calculating scroll
      Future.delayed(const Duration(milliseconds: 450), () {
        if (mounted) _performScrollToCard(keyStr, retry: retry);
      });
    } else {
      // Already expanded, perform scroll immediately
      _performScrollToCard(keyStr, retry: retry);
    }
  }

  void _performScrollToCard(String keyStr, {int retry = 0}) {
    if (!mounted) return;

    final key = _interfaceKeys[keyStr];
    final currentContext = context; // Store context

    final ctx = key?.currentContext;
    if (ctx == null) {
      if (retry < 5) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _performScrollToCard(keyStr, retry: retry + 1);
        });
      }
      return;
    }

    final headerOffset = _headerOffset(currentContext);
    final renderBox = ctx.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      if (retry < 5) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _performScrollToCard(keyStr, retry: retry + 1);
        });
      }
      return;
    }

    final cardOffset = renderBox.localToGlobal(Offset.zero).dy;
    final cardHeight = renderBox.size.height;
    final scrollableBox = _scrollController.position.hasContentDimensions
        ? _scrollController.position.context.storageContext.findRenderObject()
              as RenderBox?
        : null;
    final scrollableTop = scrollableBox?.localToGlobal(Offset.zero).dy ?? 0.0;
    final visibleTop = scrollableTop + headerOffset;
    final visibleBottom = MediaQuery.of(currentContext).size.height;
    final cardBottom = cardOffset + cardHeight;

    // Calculate how much of the card is visible
    final visibleCardTop = max(cardOffset, visibleTop);
    final visibleCardBottom = min(cardBottom, visibleBottom);
    final visibleCardHeight = max(0.0, visibleCardBottom - visibleCardTop);
    final cardVisibilityRatio = cardHeight > 0
        ? visibleCardHeight / cardHeight
        : 0.0;

    // Only scroll if less than 90% of the card is visible
    final needsScroll = cardVisibilityRatio < 0.9;

    if (needsScroll) {
      // Calculate optimal scroll position to center the card
      final screenHeight = MediaQuery.of(currentContext).size.height;
      final availableHeight = screenHeight - headerOffset;
      final targetPosition =
          cardOffset - headerOffset - (availableHeight - cardHeight) / 2;
      final clampedPosition = targetPosition.clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );

      _scrollController
          .animateTo(
            clampedPosition,
            duration: const Duration(milliseconds: 500),
            curve: Curves.fastOutSlowIn,
          )
          .then((_) {
            if (mounted) {
              setState(() {
                _targetInterface = null;
              });
              widget.onScrollComplete?.call();
            }
          });
    } else {
      if (mounted) {
        setState(() {
          _targetInterface = null;
        });
        widget.onScrollComplete?.call();
      }
    }
  }

  void _scrollToSection(double targetPosition) {
    if (!_scrollController.hasClients ||
        !_scrollController.position.hasContentDimensions) {
      return;
    }

    final maxScroll = _scrollController.position.maxScrollExtent;
    final clampedPosition = targetPosition.clamp(0.0, maxScroll);

    _scrollController
        .animateTo(
          clampedPosition,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        )
        .then((_) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              setState(() {
                _targetInterface = null;
              });
              widget.onScrollComplete?.call();
            }
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.read(appStateProvider);
    final currentRouterId = appState.selectedRouter?.id;
    if (currentRouterId != _lastSelectedRouterId) {
      _lastSelectedRouterId = currentRouterId;
      _lastRenderedScaffold = null;
      _stagedWiredInterfaceStates.clear();
      _stagedWirelessInterfaceStates.clear();
    }

    if (!widget.isTabActive && _lastRenderedScaffold != null) {
      return _lastRenderedScaffold!;
    }

    final hasStagedChanges =
        _stagedWiredInterfaceStates.isNotEmpty ||
        _stagedWirelessInterfaceStates.isNotEmpty;

    final l10n = AppLocalizations.of(context);
    final scaffold = Scaffold(
      appBar: LuciAppBar(title: l10n?.navInterfaces ?? 'Interfaces'),
      bottomNavigationBar: hasStagedChanges
          ? _buildUnsavedChangesBottomBar(context)
          : null,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Stack(
          children: [
            LuciPullToRefresh(
              onRefresh: () => appState.fetchDashboardData(),
              child: Builder(
                builder: (context) {
                  final watchedAppState = ref.watch(appStateProvider);
                  final isLoading = watchedAppState.isDashboardLoading;
                  final dashboardError = watchedAppState.dashboardError;
                  final dashboardData = watchedAppState.dashboardData;

                  if (isLoading && dashboardData == null) {
                    return _buildSkeletonInterfaces(context, appState);
                  }

                  if (dashboardError != null && dashboardData == null) {
                    return LuciErrorDisplay(
                      title:
                          l10n?.interfacesFailedToLoad ??
                          'Failed to Load Interfaces',
                      message:
                          l10n?.interfacesFailedToLoadMessage ??
                          'Could not connect to the router. Please check your network connection and router settings.',
                      actionLabel: l10n?.actionRetry ?? 'Retry',
                      onAction: () => appState.fetchDashboardData(),
                      icon: Icons.wifi_off_rounded,
                    );
                  }

                  if (dashboardData == null) {
                    return LuciEmptyState(
                      title: l10n?.interfacesNoData ?? 'No Interface Data',
                      message:
                          l10n?.interfacesNoDataMessage ??
                          'Unable to fetch interface information. Pull down to refresh or tap the button below.',
                      icon: Icons.device_hub_outlined,
                      actionLabel: l10n?.interfacesFetchData ?? 'Fetch Data',
                      onAction: () => appState.fetchDashboardData(),
                    );
                  }

                  final wiredList = _getWiredInterfacesList(appState);
                  final wirelessList = _getWirelessInterfacesList(appState);
                  final topology = _getNetworkTopology(appState);

                  final isWiredAvailable = wiredList.isNotEmpty;
                  final isWirelessAvailable = wirelessList.isNotEmpty;
                  final isTopologyAvailable =
                      topology != null &&
                      topology.isAvailable &&
                      (!topology.isZeroVlans || topology.ports.isNotEmpty);

                  final routerIp = appState.currentRouterIp;

                  final sections = <_SectionSpec>[
                    _SectionSpec(
                      defaultOrder: 0,
                      isAvailable: isWiredAvailable,
                      header: LuciSectionHeader(
                        l10n?.headerWiredInterfaces ?? 'Wired',
                        icon: Icons.settings_ethernet,
                      ),
                      sliverOrWidget: isWiredAvailable
                          ? _buildWiredSliverList(wiredList, routerIp)
                          : _buildCompactUnavailableCard(
                              icon: Icons.lan_outlined,
                              title:
                                  l10n?.wiredInterfacesUnavailable ??
                                  'Wired Interfaces Unavailable',
                              subtitle:
                                  l10n?.noWiredInterfacesDetected ??
                                  'No active or configured ethernet network interfaces detected.',
                            ),
                      isSliver: isWiredAvailable,
                    ),
                    _SectionSpec(
                      defaultOrder: 1,
                      isAvailable: isTopologyAvailable,
                      header: LuciSectionHeader(
                        l10n?.headerSwitchTopology ?? 'Switch Topology & VLANs',
                        icon: Icons.hub_outlined,
                      ),
                      sliverOrWidget: NetworkTopologyCard(
                        topology: topology,
                        onRetry: () => appState.redetectCapabilities(),
                      ),
                      isSliver: false,
                    ),
                    _SectionSpec(
                      defaultOrder: 2,
                      isAvailable: isWirelessAvailable,
                      header: LuciSectionHeader(
                        l10n?.headerWirelessInterfaces ?? 'Wireless',
                        icon: Icons.wifi,
                      ),
                      sliverOrWidget: isWirelessAvailable
                          ? _buildWirelessSliverList(wirelessList, routerIp)
                          : _buildCompactUnavailableCard(
                              icon: Icons.wifi_off_rounded,
                              title:
                                  l10n?.wirelessInterfacesUnavailable ??
                                  'Wireless Interfaces Unavailable',
                              subtitle:
                                  l10n?.noWirelessInterfacesDetected ??
                                  'No wireless physical radios or SSIDs configured on this router.',
                            ),
                      isSliver: isWirelessAvailable,
                    ),
                  ];

                  sections.sort((a, b) {
                    if (a.isAvailable != b.isAvailable) {
                      return a.isAvailable ? -1 : 1;
                    }
                    return a.defaultOrder.compareTo(b.defaultOrder);
                  });

                  final slivers = <Widget>[];
                  for (final sec in sections) {
                    slivers.add(SliverToBoxAdapter(child: sec.header));
                    if (sec.isSliver) {
                      slivers.add(sec.sliverOrWidget);
                    } else {
                      slivers.add(
                        SliverToBoxAdapter(child: sec.sliverOrWidget),
                      );
                    }
                  }
                  slivers.add(
                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  );

                  return CustomScrollView(
                    controller: _scrollController,
                    slivers: slivers,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    _lastRenderedScaffold = scaffold;
    return scaffold;
  }

  Widget _buildCompactUnavailableCard({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onRetry,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      shape: RoundedRectangleBorder(
        borderRadius: LuciCardStyles.standardRadius,
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: colorScheme.onSurfaceVariant, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                tooltip: 'Retry',
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                color: colorScheme.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }

  NetworkTopology? _getNetworkTopology(AppState appState) {
    final capabilities = appState.capabilities;
    final model = capabilities?.networkModel ?? NetworkModel.unknown;

    if (model == NetworkModel.unknown) {
      return NetworkTopology.unavailable(
        NetworkModel.unknown,
        'Conservative fallback active — network model could not be verified automatically.',
      );
    }

    final uciNetwork = appState.dashboardData?['uciNetworkConfig'];
    Map<String, dynamic> uciMap = {};
    if (uciNetwork is Map) {
      uciMap = Map<String, dynamic>.from(uciNetwork);
    }

    if (model == NetworkModel.dsa) {
      return DsaTopologyParser.parse(
        uciMap,
        appState.dashboardData?['networkDevices'] as Map<String, dynamic>?,
      );
    } else {
      return SwconfigTopologyParser.parse(
        uciMap,
        appState.dashboardData?['networkDevices'] as Map<String, dynamic>?,
        boardJson:
            appState.dashboardData?['boardJson'] as Map<String, dynamic>? ??
            appState.capabilities?.boardJson,
      );
    }
  }

  List<NetworkInterface> _getWiredInterfacesList(AppState appState) {
    final dynamic detailedData = appState.dashboardData?['interfaceDump'];
    final dynamic statsDataSource = appState.dashboardData?['networkDevices'];
    final routerIp = appState.currentRouterIp;
    final stagedHash = Object.hashAllUnordered(
      _stagedWiredInterfaceStates.entries.map(
        (e) => Object.hash(e.key, e.value),
      ),
    );

    if (_cachedWiredList != null &&
        identical(_lastInterfaceDump, detailedData) &&
        identical(_lastNetworkDevices, statsDataSource) &&
        _lastWiredRouterIp == routerIp &&
        _lastStagedWiredHash == stagedHash) {
      return _cachedWiredList!;
    }

    var interfacesList = <NetworkInterface>[];

    if (detailedData is Map &&
        detailedData.containsKey('interface') &&
        detailedData['interface'] is List) {
      final List<dynamic> interfaceDataList = detailedData['interface'];
      final Map<String, dynamic> networkStatsMap = statsDataSource is Map
          ? Map<String, dynamic>.from(statsDataSource)
          : <String, dynamic>{};

      interfacesList = interfaceDataList.whereType<Map<String, dynamic>>().map((
        detailedInterfaceMap,
      ) {
        final stats = detailedInterfaceMap['stats'];
        if (stats == null || (stats is Map && stats.isEmpty)) {
          final String? deviceName =
              detailedInterfaceMap['l3_device'] ??
              detailedInterfaceMap['device'];
          if (deviceName != null) {
            final statsContainer = networkStatsMap[deviceName];
            if (statsContainer is Map && statsContainer['stats'] is Map) {
              detailedInterfaceMap['stats'] = statsContainer['stats'];
            }
          }
        }
        return NetworkInterface.fromJson(detailedInterfaceMap);
      }).toList();
    }

    interfacesList.sort((a, b) {
      final aUp = _stagedWiredInterfaceStates[a.name] ?? a.isUp;
      final bUp = _stagedWiredInterfaceStates[b.name] ?? b.isUp;
      if (aUp != bUp) {
        return aUp ? -1 : 1;
      }
      final aAccess = _isWiredAccessInterface(a, routerIp);
      final bAccess = _isWiredAccessInterface(b, routerIp);
      if (aAccess != bAccess) {
        return aAccess ? -1 : 1;
      }
      return a.name.compareTo(b.name);
    });

    _lastInterfaceDump = detailedData;
    _lastNetworkDevices = statsDataSource;
    _lastWiredRouterIp = routerIp;
    _lastStagedWiredHash = stagedHash;
    _cachedWiredList = interfacesList;

    return interfacesList;
  }

  Widget _buildWiredSliverList(
    List<NetworkInterface> interfaces,
    String? routerIp,
  ) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final iface = interfaces[index];
        final isTargetInterface =
            _targetInterface != null &&
            iface.name.toLowerCase() == _targetInterface!.toLowerCase();

        final keyStr = _interfaceKey(name: iface.name);
        final key = _interfaceKeys.putIfAbsent(keyStr, () => GlobalKey());

        final isStaged = _stagedWiredInterfaceStates.containsKey(iface.name);
        final currentEnabled =
            _stagedWiredInterfaceStates[iface.name] ?? iface.isUp;
        final isAccess = _isWiredAccessInterface(iface, routerIp);
        final isWan =
            iface.name.toLowerCase().contains('wan') || iface.gateway != null;

        return RepaintBoundary(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: _UnifiedNetworkCard(
              key: key,
              name: iface.name.toUpperCase(),
              subtitle: _buildMinimalInterfaceSubtitle(iface),
              isUp: currentEnabled,
              icon: _getInterfaceIcon(iface.protocol),
              details: _buildWiredDetails(context, iface),
              initiallyExpanded:
                  isTargetInterface || _expandedInterface == keyStr,
              isAccessInterface: isAccess,
              isWanInterface: isWan,
              isStaged: isStaged,
              currentEnabled: currentEnabled,
              onToggle: (val) => _toggleWiredInterface(iface, val, routerIp),
              onRestart: () => _restartWiredInterface(iface, routerIp),
              isSaving: _isSaving,
            ),
          ),
        );
      }, childCount: interfaces.length),
    );
  }

  List<Map<String, dynamic>> _getWirelessInterfacesList(AppState appState) {
    final dashboardData = appState.dashboardData;
    final wirelessData = dashboardData?['wireless'] as Map<String, dynamic>?;
    final uciWirelessConfig = dashboardData?['uciWirelessConfig'];
    final routerIp = appState.currentRouterIp;
    final stagedHash = Object.hashAllUnordered(
      _stagedWirelessInterfaceStates.entries.map(
        (e) => Object.hash(e.key, e.value),
      ),
    );

    if (_cachedWirelessList != null &&
        identical(_lastWirelessData, wirelessData) &&
        identical(_lastUciWireless, uciWirelessConfig) &&
        _lastWirelessRouterIp == routerIp &&
        _lastStagedWirelessHash == stagedHash) {
      return _cachedWirelessList!;
    }

    final interfacesList = <Map<String, dynamic>>[];

    final uciRadios = <String, Map>{};
    final uciInterfaces = <String, Map>{};

    final uciValues = uciWirelessConfig?['values'] as Map?;
    if (uciValues != null) {
      uciValues.forEach((key, value) {
        final typedValue = value as Map?;
        if (typedValue?['.type'] == 'wifi-device') {
          uciRadios[key] = typedValue!;
        } else if (typedValue?['.type'] == 'wifi-iface') {
          uciInterfaces[key] = typedValue!;
        }
      });
    }

    final runtimeInterfaces = <String>{};
    if (wirelessData != null) {
      wirelessData.forEach((radioName, radioData) {
        final rawIfaces = radioData['interfaces'];
        final interfaces = rawIfaces is List
            ? rawIfaces
            : (rawIfaces is Map ? rawIfaces.values.toList() : null);
        if (interfaces != null) {
          for (final iface in interfaces) {
            final config = iface['config'] ?? {};
            final iwinfo = iface['iwinfo'] ?? {};
            final uciName = iface['section'] as String?;
            if (uciName != null) {
              runtimeInterfaces.add(uciName);
            }

            final isRadioEnabled = uciRadios[radioName]?['disabled'] != '1';
            final isIfaceEnabled = config['disabled'] != '1';
            final isEnabled = isRadioEnabled && isIfaceEnabled;

            final name = iface['name'] ?? '';
            final ssid = _uciString(iwinfo['ssid']).isNotEmpty
                ? _uciString(iwinfo['ssid'])
                : _uciString(config['ssid']);
            final deviceName = _uciString(config['device'], radioName);
            final mode = _uciString(config['mode']).toUpperCase().isNotEmpty
                ? _uciString(config['mode']).toUpperCase()
                : (iwinfo['mode']?.toString().toUpperCase() ?? 'N/A');
            interfacesList.add({
              'section':
                  uciName ??
                  (iface['section'] as String? ?? '$radioName-$ssid'),
              'name': _uciString(config['ssid']).isNotEmpty
                  ? _uciString(config['ssid'])
                  : (iwinfo['ssid']?.toString() ?? 'Unnamed'),
              'subtitle':
                  '$mode • Ch. ${iwinfo['channel']?.toString() ?? _uciString(config['channel'], 'N/A')}',
              'isEnabled': isEnabled,
              'deviceName': deviceName,
              'radioName': radioName,
              'ssid': ssid,
              'interfaceName': name,
              'details': {
                'Device': _uciString(config['device'], radioName),
                'Mode': _uciString(config['mode']).isNotEmpty
                    ? _uciString(config['mode'])
                    : (iwinfo['mode']?.toString() ?? 'N/A'),
                'Channel':
                    iwinfo['channel']?.toString() ??
                    _uciString(config['channel'], 'N/A'),
                'Signal': '${iwinfo['signal']?.toString() ?? '--'} dBm',
                'Network': (config['network'] is List)
                    ? (config['network'] as List).join(', ')
                    : _uciString(config['network'], 'N/A'),
              },
            });
          }
        }
      });
    }

    uciInterfaces.forEach((uciName, config) {
      if (!runtimeInterfaces.contains(uciName)) {
        final radioName = _uciString(config['device']);
        final isRadioEnabled = uciRadios[radioName]?['disabled'] != '1';
        final isIfaceEnabled = _uciString(config['disabled']) != '1';
        final isEnabled = isRadioEnabled && isIfaceEnabled;

        final name = _uciString(config['ssid'], 'Unnamed');
        interfacesList.add({
          'section': uciName,
          'name': name,
          'subtitle':
              '${_uciString(config['mode'], 'N/A').toUpperCase()} • Disabled',
          'isEnabled': isEnabled,
          'deviceName': radioName,
          'radioName': radioName,
          'ssid': _uciString(config['ssid']),
          'interfaceName': 'N/A',
          'details': {
            'Device': _uciString(config['device'], radioName),
            'Mode': _uciString(config['mode'], 'N/A'),
            'Channel': _uciString(config['channel'], 'N/A'),
            'Signal': '-- dBm',
            'Network': (config['network'] is List)
                ? (config['network'] as List).join(', ')
                : _uciString(config['network'], 'N/A'),
          },
        });
      }
    });

    interfacesList.sort((a, b) {
      final sectionA = a['section'] as String?;
      final sectionB = b['section'] as String?;
      final aEnabled =
          (sectionA != null &&
              _stagedWirelessInterfaceStates.containsKey(sectionA))
          ? _stagedWirelessInterfaceStates[sectionA]!
          : (a['isEnabled'] == true);
      final bEnabled =
          (sectionB != null &&
              _stagedWirelessInterfaceStates.containsKey(sectionB))
          ? _stagedWirelessInterfaceStates[sectionB]!
          : (b['isEnabled'] == true);
      if (aEnabled != bEnabled) {
        return aEnabled ? -1 : 1;
      }
      return (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? '');
    });

    _lastWirelessData = wirelessData;
    _lastUciWireless = uciWirelessConfig;
    _lastWirelessRouterIp = routerIp;
    _lastStagedWirelessHash = stagedHash;
    _cachedWirelessList = interfacesList;

    return interfacesList;
  }

  Widget _buildWirelessSliverList(
    List<Map<String, dynamic>> interfaces,
    String? routerIp,
  ) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final iface = interfaces[index];
        final deviceName = iface['deviceName'] ?? '';
        final radioName = iface['radioName'] ?? '';
        final ssid = iface['ssid'] ?? '';
        final name = iface['interfaceName'] ?? '';
        final keyStr = _interfaceKeyForWireless(
          ssid: ssid,
          radioName: radioName,
          deviceName: deviceName,
          name: name,
        );
        final key = _interfaceKeys.putIfAbsent(keyStr, () => GlobalKey());
        final displayName = ssid.toString().isNotEmpty
            ? ssid.toString()
            : deviceName.toString();

        final isTargetInterface =
            _targetInterface != null &&
            (_normalizeInterfaceKey(ssid) ==
                    _normalizeInterfaceKey(_targetInterface!) ||
                _normalizeInterfaceKey(deviceName) ==
                    _normalizeInterfaceKey(_targetInterface!) ||
                _normalizeInterfaceKey(name) ==
                    _normalizeInterfaceKey(_targetInterface!));

        final shouldExpand = isTargetInterface || _expandedInterface == keyStr;

        final sectionKey =
            iface['section']?.toString() ??
            (radioName.toString().isNotEmpty
                ? radioName.toString()
                : displayName);
        final isStaged = _stagedWirelessInterfaceStates.containsKey(sectionKey);
        final originalEnabled = iface['isEnabled'] as bool? ?? false;
        final currentEnabled =
            _stagedWirelessInterfaceStates[sectionKey] ?? originalEnabled;
        final isAccess = _isWirelessAccessInterface(iface, routerIp);
        final isWan =
            iface['details']?['Network']?.toString().toLowerCase().contains(
                  'wan',
                ) ==
                true ||
            displayName.toLowerCase().contains('wan');

        return RepaintBoundary(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: _UnifiedNetworkCard(
              key: key,
              name: displayName,
              subtitle: iface['subtitle'],
              isUp: currentEnabled,
              icon: Icons.wifi,
              details: _buildGenericDetails(context, iface['details']),
              initiallyExpanded: shouldExpand,
              isAccessInterface: isAccess,
              isWanInterface: isWan,
              isStaged: isStaged,
              currentEnabled: currentEnabled,
              onToggle: (val) => _toggleWirelessInterface(
                sectionKey,
                displayName,
                originalEnabled,
                isAccess,
                val,
              ),
              onRestart: () => _restartWirelessInterface(
                sectionKey,
                displayName,
                isAccess,
                isWan,
                radioName: radioName.toString(),
              ),
              isSaving: _isSaving,
            ),
          ),
        );
      }, childCount: interfaces.length),
    );
  }

  Widget _buildWiredDetails(BuildContext context, NetworkInterface interface) {
    final l10n = AppLocalizations.of(context);
    final parsedProto = WanProtocol.parse(interface.protocol);
    return Column(
      children: [
        if (parsedProto == WanProtocol.unknown)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.shade900.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.amber.shade700.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.amber.shade700,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Unrecognized proto (${interface.protocol}) — showing raw fields',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        _buildDetailRow(
          context,
          l10n?.labelDevice ?? 'Device',
          interface.device,
        ),
        _buildDetailRow(
          context,
          l10n?.systemUptime ?? 'Uptime',
          interface.formattedUptime,
        ),
        if (interface.ipAddress != null)
          _buildDetailRow(
            context,
            _isPublicIp(interface.ipAddress!)
                ? (l10n?.labelPublicIpAddress ?? 'Public IP Address')
                : (interface.name.toLowerCase().contains('wan')
                      ? (l10n?.labelIpAddressWan ?? 'IP Address (WAN)')
                      : (l10n?.labelIpAddress ?? 'IP Address')),
            interface.ipAddress!,
            onTap: () => _copyToClipboard(
              context,
              interface.ipAddress!,
              l10n?.labelIpAddress ?? 'IP Address',
            ),
          ),
        if (interface.ipv6Addresses != null &&
            interface.ipv6Addresses!.isNotEmpty)
          ...interface.ipv6Addresses!.map(
            (ipv6) => _buildDetailRow(
              context,
              _isPublicIp(ipv6)
                  ? (l10n?.labelPublicIpv6Address ?? 'Public IPv6 Address')
                  : (l10n?.labelIpv6Address ?? 'IPv6 Address'),
              ipv6,
              onTap: () => _copyToClipboard(
                context,
                ipv6,
                l10n?.labelIpv6Address ?? 'IPv6 Address',
              ),
            ),
          ),
        if (interface.gateway != null)
          _buildDetailRow(
            context,
            l10n?.interfaceGateway ?? 'Gateway',
            interface.gateway!,
            onTap: () => _copyToClipboard(
              context,
              interface.gateway!,
              l10n?.interfaceGateway ?? 'Gateway IP',
            ),
          ),
        if (interface.dnsServers.isNotEmpty)
          _buildDetailRow(
            context,
            l10n?.interfaceDns ?? 'DNS',
            interface.dnsServers.join(', '),
            onTap: () => _copyToClipboard(
              context,
              interface.dnsServers.join(', '),
              l10n?.interfaceDns ?? 'DNS Servers',
            ),
          ),
        // Add WireGuard peer information if this is a WireGuard interface
        if (interface.protocol.toLowerCase() == 'wireguard') ...[
          Builder(
            builder: (context) {
              return _buildWireGuardPeersSection(context, interface.name);
            },
          ),
        ],
        const Divider(height: 1, indent: 16, endIndent: 16),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: _buildStatsRow(context, interface.stats),
        ),
      ],
    );
  }

  Widget _buildWireGuardPeersSection(
    BuildContext context,
    String interfaceName,
  ) {
    final appState = ref.watch(appStateProvider);
    final wireguardData =
        appState.dashboardData?['wireguard'] as Map<String, dynamic>?;
    final peerData = wireguardData?[interfaceName];
    if (peerData == null) {
      return const SizedBox.shrink();
    }
    final peers = peerData['peers'] as Map<String, dynamic>?;
    if (peers == null || peers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Divider(height: 24, thickness: 1, indent: 0, endIndent: 0),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1, thickness: 1, indent: 0, endIndent: 0),
          const SizedBox(height: 8),
          ...peers.values.map(
            (peer) =>
                _buildCohesivePeerRow(context, peer as Map<String, dynamic>),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCohesivePeerRow(
    BuildContext context,
    Map<String, dynamic> peer,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final publicKey = peer['public_key'] as String? ?? 'Unknown';
    final endpoint = peer['endpoint'] as String? ?? 'N/A';
    final peerName = peer['name'] as String?;
    int lastHandshake = 0;
    final rawHandshake = peer['last_handshake'] ?? peer['latest_handshake'];
    if (rawHandshake != null) {
      if (rawHandshake is int) {
        lastHandshake = rawHandshake;
      } else if (rawHandshake is String) {
        lastHandshake = int.tryParse(rawHandshake) ?? 0;
      }
    }
    final displayKey = publicKey.length > 16
        ? '${publicKey.substring(0, 8)}...${publicKey.substring(publicKey.length - 8)}'
        : publicKey;
    String formatHandshakeTime(int timestamp) {
      if (timestamp == 0) return 'Never';
      final now = DateTime.now();
      final handshakeTime = DateTime.fromMillisecondsSinceEpoch(
        timestamp * 1000,
      );
      final difference = now.difference(handshakeTime);
      if (difference.inSeconds < 0) return 'Never';
      if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return '${difference.inSeconds}s ago';
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.vpn_key, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  displayKey,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (peerName != null && peerName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                peerName,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      l10n?.labelLastHandshake ?? 'Last Handshake',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatHandshakeTime(lastHandshake),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        color: colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      l10n?.labelEndpoint ?? 'Endpoint',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      endpoint,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        color: colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGenericDetails(
    BuildContext context,
    Map<String, dynamic> details,
  ) {
    return Column(
      children: details.entries.map((entry) {
        return _buildDetailRow(context, entry.key, entry.value.toString());
      }).toList(),
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    String title,
    String value, {
    VoidCallback? onTap,
    bool isLoading = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 3.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 115,
              child: Text(
                title,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12.0,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 2.0),
                      child: LuciSkeleton(
                        width: 80,
                        height: 12,
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                      ),
                    )
                  else
                    Expanded(
                      child: Text(
                        value,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                          fontSize: 12.5,
                        ),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  if (!isLoading && onTap != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 6.0),
                      child: Icon(
                        Icons.copy_all_outlined,
                        size: 14,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.6,
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

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    context.showToastSuccess('$label copied', subtitle: 'Copied to clipboard.');
  }

  bool _isPublicIp(String ipText) {
    if (ipText.isEmpty ||
        ipText == 'No IPv4' ||
        ipText == 'No IPv6' ||
        ipText == 'N/A') {
      return false;
    }
    final raw = ipText.split('/')[0].trim();
    if (raw.contains('.')) {
      final parts = raw.split('.');
      if (parts.length != 4) return false;
      final octet1 = int.tryParse(parts[0]);
      final octet2 = int.tryParse(parts[1]);
      if (octet1 == null || octet2 == null) return false;
      if (octet1 == 10) return false;
      if (octet1 == 172 && octet2 >= 16 && octet2 <= 31) return false;
      if (octet1 == 192 && octet2 == 168) return false;
      if (octet1 == 127) return false;
      if (octet1 == 169 && octet2 == 254) return false;
      return true;
    } else if (raw.contains(':')) {
      final lower = raw.toLowerCase();
      if (lower == '::1') return false;
      if (lower.startsWith('fe80:') ||
          lower.startsWith('fe8') ||
          lower.startsWith('fe9') ||
          lower.startsWith('fea') ||
          lower.startsWith('feb')) {
        return false;
      }
      if (lower.startsWith('fc') || lower.startsWith('fd')) {
        return false;
      }
      return true;
    }
    return false;
  }

  Widget _buildStatsRow(
    BuildContext context,
    Map<String, dynamic> stats, {
    bool isLoading = false,
  }) {
    String formatBytes(int bytes) {
      if (bytes <= 0) return '0 B';
      const suffixes = ["B", "KB", "MB", "GB", "TB"];
      final i = (log(bytes) / log(1024)).floor();
      return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
    }

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final rxStr = formatBytes(stats['rx_bytes'] ?? 0);
    final txStr = formatBytes(stats['tx_bytes'] ?? 0);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.arrow_downward_rounded,
                  size: 14,
                  color: Colors.green,
                ),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n?.metricReceived ?? 'Received',
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 2.0),
                        child: LuciSkeleton(
                          width: 44,
                          height: 12,
                          borderRadius: BorderRadius.all(Radius.circular(4)),
                        ),
                      )
                    else
                      Text(
                        rxStr,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            height: 22,
            width: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.arrow_upward_rounded,
                  size: 14,
                  color: Colors.orange,
                ),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n?.metricTransmitted ?? 'Transmitted',
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 2.0),
                        child: LuciSkeleton(
                          width: 44,
                          height: 12,
                          borderRadius: BorderRadius.all(Radius.circular(4)),
                        ),
                      )
                    else
                      Text(
                        txStr,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWiredDetailsSkeleton(
    BuildContext context, {
    bool isWan = false,
  }) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        _buildDetailRow(
          context,
          l10n?.labelDevice ?? 'Device',
          '',
          isLoading: true,
        ),
        _buildDetailRow(
          context,
          l10n?.systemUptime ?? 'Uptime',
          '',
          isLoading: true,
        ),
        _buildDetailRow(
          context,
          isWan
              ? (l10n?.labelIpAddressWan ?? 'IP Address (WAN)')
              : (l10n?.labelIpAddress ?? 'IP Address'),
          '',
          isLoading: true,
        ),
        _buildDetailRow(
          context,
          l10n?.interfaceGateway ?? 'Gateway',
          '',
          isLoading: true,
        ),
        _buildDetailRow(
          context,
          l10n?.interfaceDns ?? 'DNS',
          '',
          isLoading: true,
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: _buildStatsRow(context, const {}, isLoading: true),
        ),
      ],
    );
  }

  Widget _buildWirelessDetailsSkeleton(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        _buildDetailRow(
          context,
          l10n?.labelDevice ?? 'Device',
          '',
          isLoading: true,
        ),
        _buildDetailRow(context, 'Mode', '', isLoading: true),
        _buildDetailRow(context, 'Channel', '', isLoading: true),
        _buildDetailRow(context, 'Signal', '', isLoading: true),
        _buildDetailRow(context, 'Network', '', isLoading: true),
      ],
    );
  }

  Widget _buildSkeletonInterfaces(BuildContext context, AppState appState) {
    final l10n = AppLocalizations.of(context);
    final sections = <_SectionSpec>[
      _SectionSpec(
        defaultOrder: 0,
        isAvailable: true,
        header: LuciSectionHeader(
          l10n?.headerWiredInterfaces ?? 'Wired',
          icon: Icons.settings_ethernet,
        ),
        sliverOrWidget: SliverList(
          delegate: SliverChildListDelegate([
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: _UnifiedNetworkCard(
                name: 'LAN',
                subtitle: '',
                isUp: true,
                isLoading: true,
                icon: Icons.settings_ethernet,
                details: _buildWiredDetailsSkeleton(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: _UnifiedNetworkCard(
                name: 'WAN',
                subtitle: '',
                isUp: true,
                isWanInterface: true,
                isLoading: true,
                icon: Icons.public,
                details: _buildWiredDetailsSkeleton(context, isWan: true),
              ),
            ),
          ]),
        ),
        isSliver: true,
      ),
      _SectionSpec(
        defaultOrder: 1,
        isAvailable: true,
        header: LuciSectionHeader(
          l10n?.headerSwitchTopology ?? 'Switch Topology & VLANs',
          icon: Icons.hub_outlined,
        ),
        sliverOrWidget: const NetworkTopologyCard(
          topology: null,
          isLoading: true,
        ),
        isSliver: false,
      ),
      _SectionSpec(
        defaultOrder: 2,
        isAvailable: true,
        header: LuciSectionHeader(
          l10n?.headerWirelessInterfaces ?? 'Wireless',
          icon: Icons.wifi,
        ),
        sliverOrWidget: SliverList(
          delegate: SliverChildListDelegate([
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: _UnifiedNetworkCard(
                name: 'Wireless',
                subtitle: '',
                isUp: true,
                isLoading: true,
                icon: Icons.wifi,
                details: _buildWirelessDetailsSkeleton(context),
              ),
            ),
          ]),
        ),
        isSliver: true,
      ),
    ];

    final slivers = <Widget>[];
    for (final sec in sections) {
      slivers.add(SliverToBoxAdapter(child: sec.header));
      if (sec.isSliver) {
        slivers.add(sec.sliverOrWidget);
      } else {
        slivers.add(SliverToBoxAdapter(child: sec.sliverOrWidget));
      }
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 100)));

    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: slivers,
    );
  }

  IconData _getInterfaceIcon(String protocol) {
    switch (protocol.toLowerCase()) {
      case 'wireguard':
        return Icons.shield_outlined;
      case 'static':
        return Icons.settings_ethernet;
      case 'dhcp':
        return Icons.dns_outlined;
      default:
        return Icons.device_hub_outlined;
    }
  }

  String _buildMinimalInterfaceSubtitle(NetworkInterface iface) {
    final v4 = iface.ipAddress;
    final v6s = iface.ipv6Addresses ?? [];
    final v6 = v6s.isNotEmpty ? v6s.first : null;
    String? shown;
    int extra = 0;
    if (v4 != null) {
      shown = v4;
      if (v6 != null) extra++;
    } else if (v6 != null) {
      shown = v6;
    }
    if (shown == null) return iface.protocol;
    if (extra > 0) {
      return '${iface.protocol} • $shown  +$extra';
    } else {
      return '${iface.protocol} • $shown';
    }
  }
}

class _SectionSpec {
  final int defaultOrder;
  final bool isAvailable;
  final Widget header;
  final Widget sliverOrWidget;
  final bool isSliver;

  _SectionSpec({
    required this.defaultOrder,
    required this.isAvailable,
    required this.header,
    required this.sliverOrWidget,
    required this.isSliver,
  });
}

class LuciSectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;
  const LuciSectionHeader(this.title, {this.icon, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
          ],
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

typedef _UnifiedNetworkCard = UnifiedNetworkCard;

class UnifiedNetworkCard extends StatefulWidget {
  final String name;
  final String subtitle;
  final bool isUp;
  final IconData icon;
  final Widget details;
  final bool initiallyExpanded;
  final bool isLoading;

  final bool isAccessInterface;
  final bool isWanInterface;
  final bool isStaged;
  final bool? currentEnabled;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onRestart;
  final bool isSaving;

  const UnifiedNetworkCard({
    required this.name,
    required this.subtitle,
    required this.isUp,
    required this.icon,
    required this.details,
    this.initiallyExpanded = false,
    this.isLoading = false,
    this.isAccessInterface = false,
    this.isWanInterface = false,
    this.isStaged = false,
    this.currentEnabled,
    this.onToggle,
    this.onRestart,
    this.isSaving = false,
    super.key,
  });

  @override
  State<UnifiedNetworkCard> createState() => _UnifiedNetworkCardState();
}

class _UnifiedNetworkCardState extends State<UnifiedNetworkCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    if (widget.initiallyExpanded) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _UnifiedNetworkCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initiallyExpanded != oldWidget.initiallyExpanded) {
      setState(() {
        _isExpanded = widget.initiallyExpanded;
        if (_isExpanded) {
          _controller.forward();
        } else {
          _controller.reverse();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final effectiveEnabled = widget.currentEnabled ?? widget.isUp;

    final card = Card(
      elevation: _isExpanded ? 6 : 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: LuciCardStyles.standardRadius,
        side: BorderSide(
          color: widget.initiallyExpanded && _isExpanded
              ? colorScheme.primary.withValues(alpha: 0.3)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.10),
          width: widget.initiallyExpanded && _isExpanded ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedScale(
        scale: widget.initiallyExpanded && _isExpanded ? 1.01 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: Column(
          children: [
            InkWell(
              onTap: _toggleExpand,
              borderRadius: LuciCardStyles.standardRadius,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14.0,
                  vertical: 8.0,
                ),
                child: Row(
                  children: [
                    Stack(
                      alignment: Alignment.topRight,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7.0),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(
                              alpha: 0.13,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: AnimatedScale(
                            scale: widget.initiallyExpanded && _isExpanded
                                ? 1.05
                                : 1.0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            child: Icon(
                              widget.icon,
                              color: effectiveEnabled
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                              size: 20,
                              semanticLabel: 'Interface icon',
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.topRight,
                          child: Tooltip(
                            message: effectiveEnabled
                                ? (l10n?.tooltipInterfaceUp ??
                                      'Interface is up')
                                : (l10n?.tooltipInterfaceDown ??
                                      'Interface is down'),
                            child: LuciStatusIndicators.statusDot(
                              context,
                              effectiveEnabled,
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
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  widget.name,
                                  style: LuciTextStyles.cardTitle(context)
                                      .copyWith(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  semanticsLabel:
                                      'Interface name: ${widget.name}',
                                ),
                              ),
                            ],
                          ),
                          if (widget.isAccessInterface ||
                              widget.isWanInterface ||
                              widget.isStaged) ...[
                            const SizedBox(height: 3),
                            Wrap(
                              spacing: 4,
                              runSpacing: 3,
                              children: [
                                if (widget.isAccessInterface)
                                  Tooltip(
                                    message:
                                        l10n?.tooltipActiveAccess ??
                                        'Active management access interface',
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withValues(
                                          alpha: 0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: Colors.red.shade400,
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.lock,
                                            size: 9,
                                            color: Colors.red,
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            l10n?.chipActiveAccess ??
                                                'ACTIVE ACCESS',
                                            style: const TextStyle(
                                              color: Colors.red,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (widget.isWanInterface)
                                  Tooltip(
                                    message:
                                        l10n?.tooltipWanGateway ??
                                        'WAN / Gateway Interface',
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.indigo.shade800
                                            .withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: Colors.indigo.shade400,
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.public,
                                            size: 9,
                                            color: Colors.indigo.shade300,
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            l10n?.chipWanGateway ??
                                                'WAN / GATEWAY',
                                            style: TextStyle(
                                              color: Colors.indigo.shade200,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (widget.isStaged)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(
                                        alpha: 0.2,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: Colors.amber.shade700,
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Text(
                                      l10n?.chipStaged ?? 'STAGED',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.amber.shade900,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 2),
                          if (widget.isLoading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 2.0),
                              child: LuciSkeleton(
                                width: 120,
                                height: 12,
                                borderRadius: BorderRadius.all(
                                  Radius.circular(4),
                                ),
                              ),
                            )
                          else
                            Text(
                              widget.isStaged
                                  ? '${widget.subtitle} • Original: ${widget.isUp ? "UP" : "DOWN"}'
                                  : widget.subtitle,
                              style: LuciTextStyles.cardSubtitle(
                                context,
                              ).copyWith(fontSize: 12.0),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              semanticsLabel:
                                  'Interface details: ${widget.subtitle}',
                            ),
                        ],
                      ),
                    ),
                    if (widget.onRestart != null) ...[
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 19),
                        color: colorScheme.primary,
                        tooltip:
                            l10n?.tooltipRestartInterface ??
                            'Restart Interface',
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        onPressed: widget.isSaving ? null : widget.onRestart,
                      ),
                      const SizedBox(width: 4),
                    ],
                    if (widget.onToggle != null) ...[
                      if (widget.isSaving)
                        Padding(
                          padding: const EdgeInsets.only(right: 6.0),
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: widget.isSaving ? 0.55 : 1.0,
                        child: Transform.scale(
                          scale: 0.82,
                          child: Switch(
                            value: effectiveEnabled,
                            onChanged: widget.isSaving ? null : widget.onToggle,
                          ),
                        ),
                      ),
                    ],
                    Icon(
                      _isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: colorScheme.onSurfaceVariant,
                      size: 22,
                      semanticLabel: _isExpanded
                          ? 'Collapse details'
                          : 'Expand details',
                    ),
                  ],
                ),
              ),
            ),
            if (_isExpanded)
              Column(
                children: [
                  const Divider(height: 1, indent: 14, endIndent: 14),
                  widget.details,
                  const SizedBox(height: 6),
                ],
              ),
          ],
        ),
      ),
    );

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: (!effectiveEnabled && !widget.isStaged) ? 0.55 : 1.0,
      child: card,
    );
  }
}
