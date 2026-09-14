// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';

import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/modules/parental_controls/models/parental_profile.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/services/interfaces/auth_service_interface.dart';
import 'package:yet_another_luci_app/services/router_service.dart';
import 'package:yet_another_luci_app/utils/logger.dart';

/// Lifecycle observer stub — auto-revert timer removed per developer requirement.
class AccessControlTimerLifecycleManager {
  AccessControlTimerLifecycleManager({
    required NetworkActionsController controller,
  }) : _controller = controller {
    _lifecycleListener = AppLifecycleListener(
      onPause: _onPause,
      onResume: _onResume,
      onDetach: _onDetach,
    );
  }

  final NetworkActionsController _controller;
  late final AppLifecycleListener _lifecycleListener;
  bool _wasPendingConfirmation = false;
  int _pausedCountdownSeconds = 0;

  void _onPause() {
    if (_controller._isAccessControlPendingConfirmation) {
      _wasPendingConfirmation = true;
      _pausedCountdownSeconds = _controller._accessControlCountdownSeconds;
      // Pause the countdown timer - don't let it tick down while backgrounded
      _controller._accessControlCountdownTimer?.cancel();
      _controller._accessControlCountdownTimer = null;
      // Note: We keep the revert timer running but don't want it to fire while app is backgrounded
      // The revert timer will be handled on resume
    }
  }

  void _onResume() {
    if (_wasPendingConfirmation) {
      _wasPendingConfirmation = false;
      // Restore the countdown with remaining seconds
      _controller.startAccessControlAutoRevertTimer(
        initialSeconds: _pausedCountdownSeconds,
        priorMaclist: _controller._priorMaclistSnapshot,
        priorMacfilter: _controller._priorMacfilterSnapshot,
      );
    }
  }

  void _onDetach() {
    _lifecycleListener.dispose();
  }

  void dispose() {
    _lifecycleListener.dispose();
  }
}

/// Encapsulates all network actions:
/// - VPN and secure tunnel toggles (OpenVPN, Tailscale, NextDNS, Cloudflared, WireGuard)
/// - Interface & service control (Wired/Wireless status, Firewall rules, init actions)
/// - Wi-Fi access control with safety revert timer management
/// - Client actions (disconnect, pause internet, static DHCP lease management, ban/unban)
///
/// Extracted from [AppState] to enforce single-responsibility.
class NetworkActionsController {
  NetworkActionsController({
    required IApiService? Function() apiServiceRef,
    required IAuthService? Function() authServiceRef,
    required RouterService? Function() routerServiceRef,
    required bool Function() reviewerModeRef,
    required Map<String, dynamic>? Function() dashboardDataRef,
    required Future<void> Function() refreshDashboard,
    required Future<void> Function() redetectCapabilities,
    required VoidCallback notifyListeners,
  }) : _apiServiceRef = apiServiceRef,
       _authServiceRef = authServiceRef,
       _routerServiceRef = routerServiceRef,
       _reviewerModeRef = reviewerModeRef,
       _dashboardDataRef = dashboardDataRef,
       _refreshDashboard = refreshDashboard,
       _redetectCapabilities = redetectCapabilities,
       _notifyListeners = notifyListeners;

  final IApiService? Function() _apiServiceRef;
  final IAuthService? Function() _authServiceRef;
  final RouterService? Function() _routerServiceRef;
  final bool Function() _reviewerModeRef;
  final Map<String, dynamic>? Function() _dashboardDataRef;
  final Future<void> Function() _refreshDashboard;
  final Future<void> Function() _redetectCapabilities;
  final VoidCallback _notifyListeners;

  // ── Access Control & Timer State ─────────────────────────────────
  Map<String, List<String>> _priorMaclistSnapshot = {};
  Map<String, String> _priorMacfilterSnapshot = {};
  bool _isAccessControlPendingConfirmation = false;
  int _accessControlCountdownSeconds = 25;

  String? _pendingSectionName;
  String? _pendingTargetType; // 'radio', 'ssid', or 'access_control'
  dynamic _pendingTargetRadio;
  dynamic _pendingTargetInterface;

  Timer? _accessControlRevertTimer;
  Timer? _accessControlCountdownTimer;
  Timer? _accessControlRevertRetryTimer;

  bool get isAccessControlPendingConfirmation =>
      _isAccessControlPendingConfirmation;
  int get accessControlCountdownSeconds => _accessControlCountdownSeconds;
  Map<String, List<String>> get priorMaclistSnapshot => _priorMaclistSnapshot;
  Map<String, String> get priorMacfilterSnapshot => _priorMacfilterSnapshot;
  String? get pendingSectionName => _pendingSectionName;
  String? get pendingTargetType => _pendingTargetType;
  dynamic get pendingTargetRadio => _pendingTargetRadio;
  dynamic get pendingTargetInterface => _pendingTargetInterface;

  // ── Paused Internet & Banned Wireless State ───────────────────────
  final Set<String> _pausedInternetMacs = {};
  final Set<String> _bannedWirelessMacs = {};

  Set<String> get pausedInternetMacs => _pausedInternetMacs;
  Set<String> get bannedWirelessMacs => _bannedWirelessMacs;

  bool isInternetPaused(String mac) =>
      _pausedInternetMacs.contains(mac.toUpperCase().replaceAll('-', ':'));

  bool isWirelessBanned(String mac) =>
      _bannedWirelessMacs.contains(mac.toUpperCase().replaceAll('-', ':'));

  bool isRestrictedOrBanned(String mac) =>
      isInternetPaused(mac) || isWirelessBanned(mac);

  void updatePausedInternetMacs(Set<String> macs) {
    _pausedInternetMacs.clear();
    _pausedInternetMacs.addAll(macs);
    _notifyListeners();
  }

  void updateBannedWirelessMacs(Set<String> macs) {
    _bannedWirelessMacs.clear();
    _bannedWirelessMacs.addAll(macs);
    _notifyListeners();
  }

  // ── Private Accessors ────────────────────────────────────────────
  String? get _ip => _routerServiceRef()?.selectedRouter?.ipAddress;
  String? get _sysauth => _authServiceRef()?.sysauth;
  bool get _useHttps => _routerServiceRef()?.selectedRouter?.useHttps ?? false;
  bool get _isReviewerMode => _reviewerModeRef();
  IApiService? get _apiService => _apiServiceRef();

  /// Dispose timers on controller teardown
  void dispose() {
    _accessControlRevertTimer?.cancel();
    _accessControlCountdownTimer?.cancel();
    _accessControlRevertRetryTimer?.cancel();
  }

  // ── VPN & Secure Toggles ─────────────────────────────────────────

  /// Toggle an OpenVPN instance enabled state and manage service action
  Future<bool> toggleOpenVpnInstance(String name, bool enable) async {
    if (_isReviewerMode) return true;
    final ip = _ip;
    final sysauth = _sysauth;
    if (ip == null || sysauth == null || _apiService == null) return false;

    try {
      final setRes = await _apiService!.uciSet(
        ip,
        sysauth,
        _useHttps,
        config: 'openvpn',
        section: name,
        values: {'enabled': enable ? '1' : '0'},
      );
      if (setRes is List && setRes.isNotEmpty && setRes[0] != 0) return false;
      final commitRes = await _apiService!.uciCommit(
        ip,
        sysauth,
        _useHttps,
        config: 'openvpn',
      );
      if (commitRes is List && commitRes.isNotEmpty && commitRes[0] != 0) {
        return false;
      }

      await _apiService!.manageServiceAction(
        ip,
        sysauth,
        _useHttps,
        serviceName: 'openvpn',
        action: enable ? 'start' : 'stop',
      );
      await _refreshDashboard();
      return true;
    } catch (e, stack) {
      Logger.exception('Failed to toggle OpenVPN instance $name', e, stack);
      return false;
    }
  }

  /// Toggle Tailscale mesh daemon enabled state
  Future<bool> toggleTailscale(bool enable) async {
    if (_isReviewerMode) return true;
    final ip = _ip;
    final sysauth = _sysauth;
    if (ip == null || sysauth == null || _apiService == null) return false;

    try {
      try {
        await _apiService!.uciSet(
          ip,
          sysauth,
          _useHttps,
          config: 'tailscale',
          section: 'settings',
          values: {'enabled': enable ? '1' : '0'},
        );
        await _apiService!.uciCommit(
          ip,
          sysauth,
          _useHttps,
          config: 'tailscale',
        );
      } catch (_) {}

      await _apiService!.manageServiceAction(
        ip,
        sysauth,
        _useHttps,
        serviceName: 'tailscale',
        action: enable ? 'start' : 'stop',
      );

      try {
        await _apiService!.call(
          ip,
          sysauth,
          _useHttps,
          object: 'file',
          method: 'exec',
          params: {
            'command': 'tailscale',
            'params': [enable ? 'up' : 'down'],
          },
        );
      } catch (_) {}

      await _refreshDashboard();
      return true;
    } catch (e, stack) {
      Logger.exception('Failed to toggle Tailscale', e, stack);
      return false;
    }
  }

  /// Toggle NextDNS encrypted DNS daemon state with multi-daemon (dnsmasq, unbound, kresd, smartdns, odhcpd) self-healing guardrails
  Future<bool> toggleNextDns(bool enable) async {
    if (_isReviewerMode) return true;
    final ip = _ip;
    final sysauth = _sysauth;
    if (ip == null || sysauth == null || _apiService == null) return false;

    // Multi-daemon DNS restorer helper function for OpenWrt
    const restartDnsHelper = '''
restart_dns() {
  if [ -x /etc/init.d/dnsmasq ] && /etc/init.d/dnsmasq enabled 2>/dev/null; then
    uci commit dhcp 2>/dev/null || true
    /etc/init.d/dnsmasq restart 2>/dev/null || true
  elif [ -x /etc/init.d/unbound ] && /etc/init.d/unbound enabled 2>/dev/null; then
    /etc/init.d/unbound restart 2>/dev/null || true
  elif [ -x /etc/init.d/kresd ] && /etc/init.d/kresd enabled 2>/dev/null; then
    /etc/init.d/kresd restart 2>/dev/null || true
  elif [ -x /etc/init.d/smartdns ] && /etc/init.d/smartdns enabled 2>/dev/null; then
    /etc/init.d/smartdns restart 2>/dev/null || true
  elif [ -x /etc/init.d/odhcpd ] && /etc/init.d/odhcpd enabled 2>/dev/null; then
    /etc/init.d/odhcpd restart 2>/dev/null || true
  else
    ubus call network reload 2>/dev/null || /etc/init.d/network reload 2>/dev/null || true
  fi
}
''';

    const healDnsHelper = '''
heal_dns() {
  if [ -x /etc/init.d/dnsmasq ] && /etc/init.d/dnsmasq enabled 2>/dev/null; then
    pgrep dnsmasq >/dev/null || /etc/init.d/dnsmasq restart 2>/dev/null || true
  elif [ -x /etc/init.d/unbound ] && /etc/init.d/unbound enabled 2>/dev/null; then
    pgrep unbound >/dev/null || /etc/init.d/unbound restart 2>/dev/null || true
  elif [ -x /etc/init.d/kresd ] && /etc/init.d/kresd enabled 2>/dev/null; then
    pgrep kresd >/dev/null || /etc/init.d/kresd restart 2>/dev/null || true
  elif [ -x /etc/init.d/smartdns ] && /etc/init.d/smartdns enabled 2>/dev/null; then
    pgrep smartdns >/dev/null || /etc/init.d/smartdns restart 2>/dev/null || true
  elif [ -x /etc/init.d/odhcpd ] && /etc/init.d/odhcpd enabled 2>/dev/null; then
    pgrep odhcpd >/dev/null || /etc/init.d/odhcpd restart 2>/dev/null || true
  fi
}
''';

    try {
      if (enable) {
        // 1. Configure NextDNS listening port to 5342 to prevent port 53 collision
        await _apiService!.uciSet(
          ip,
          sysauth,
          _useHttps,
          config: 'nextdns',
          section: 'main',
          values: {
            'enabled': '1',
            'setup_router': '1',
            'listen': '127.0.0.1:5342',
          },
        );
        await _apiService!.uciCommit(ip, sysauth, _useHttps, config: 'nextdns');

        // 2. Start nextdns service
        await _apiService!.manageServiceAction(
          ip,
          sysauth,
          _useHttps,
          serviceName: 'nextdns',
          action: 'start',
        );

        // 3. Activate NextDNS, ensure process is running on port 5342 & restart active DNS daemon
        final activateCmd =
            '$restartDnsHelper\n'
            '(nextdns activate || /etc/init.d/nextdns activate 2>/dev/null || true) && '
            '(pgrep nextdns >/dev/null || nextdns run -config-file /etc/config/nextdns -listen 127.0.0.1:5342 &) && '
            'restart_dns';
        await _apiService!.call(
          ip,
          sysauth,
          _useHttps,
          object: 'file',
          method: 'exec',
          params: {
            'command': '/bin/sh',
            'params': ['-c', activateCmd],
          },
        );
      } else {
        // 1. Deactivate NextDNS
        const deactivateCmd =
            '(nextdns deactivate || /etc/init.d/nextdns deactivate 2>/dev/null || true)';
        await _apiService!.call(
          ip,
          sysauth,
          _useHttps,
          object: 'file',
          method: 'exec',
          params: {
            'command': '/bin/sh',
            'params': ['-c', deactivateCmd],
          },
        );

        // 2. Stop nextdns service & kill process if needed
        await _apiService!.manageServiceAction(
          ip,
          sysauth,
          _useHttps,
          serviceName: 'nextdns',
          action: 'stop',
        );
        const killCmd = 'killall nextdns 2>/dev/null || true';
        await _apiService!.call(
          ip,
          sysauth,
          _useHttps,
          object: 'file',
          method: 'exec',
          params: {
            'command': '/bin/sh',
            'params': ['-c', killCmd],
          },
        );

        // 3. Disable nextdns in UCI
        await _apiService!.uciSet(
          ip,
          sysauth,
          _useHttps,
          config: 'nextdns',
          section: 'main',
          values: {'enabled': '0'},
        );
        await _apiService!.uciCommit(ip, sysauth, _useHttps, config: 'nextdns');

        // 4. Purge orphaned drop-in configs and restore active DNS daemon
        final purgeCmd =
            '$restartDnsHelper\n'
            'rm -f /tmp/dnsmasq.d/nextdns.conf /var/etc/dnsmasq.d/nextdns.conf 2>/dev/null && '
            'uci del dhcp.@dnsmasq[0].noresolv 2>/dev/null || true && '
            'restart_dns';
        await _apiService!.call(
          ip,
          sysauth,
          _useHttps,
          object: 'file',
          method: 'exec',
          params: {
            'command': '/bin/sh',
            'params': ['-c', purgeCmd],
          },
        );
      }

      // 5. DHCP & DNS Self-Healing Guardrail: ensure active DNS daemon is running
      final healCmd =
          '$healDnsHelper\n'
          'sleep 1 && heal_dns';
      await _apiService!.call(
        ip,
        sysauth,
        _useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': '/bin/sh',
          'params': ['-c', healCmd],
        },
      );

      await _refreshDashboard();
      return true;
    } catch (e, stack) {
      Logger.exception('Failed to toggle NextDNS', e, stack);
      try {
        final emergencyCmd =
            '$restartDnsHelper\n'
            'rm -f /tmp/dnsmasq.d/nextdns.conf 2>/dev/null && '
            'uci del dhcp.@dnsmasq[0].noresolv 2>/dev/null || true && '
            'restart_dns';
        await _apiService!.call(
          ip,
          sysauth,
          _useHttps,
          object: 'file',
          method: 'exec',
          params: {
            'command': '/bin/sh',
            'params': ['-c', emergencyCmd],
          },
        );
      } catch (_) {
        // Pure ubus RPC fallback if file.exec is unavailable
        await _apiService!.manageServiceAction(
          ip,
          sysauth,
          _useHttps,
          serviceName: 'nextdns',
          action: enable ? 'start' : 'stop',
        );
        await _apiService!.manageServiceAction(
          ip,
          sysauth,
          _useHttps,
          serviceName: 'dnsmasq',
          action: 'restart',
        );
      }
      return false;
    }
  }

  /// Toggle Cloudflared tunnel daemon enabled state
  Future<bool> toggleCloudflared(bool enable) async {
    if (_isReviewerMode) return true;
    final ip = _ip;
    final sysauth = _sysauth;
    if (ip == null || sysauth == null || _apiService == null) return false;

    try {
      final setRes = await _apiService!.uciSet(
        ip,
        sysauth,
        _useHttps,
        config: 'cloudflared',
        section: 'main',
        values: {'enabled': enable ? '1' : '0'},
      );
      if (setRes is List && setRes.isNotEmpty && setRes[0] != 0) return false;
      final commitRes = await _apiService!.uciCommit(
        ip,
        sysauth,
        _useHttps,
        config: 'cloudflared',
      );
      if (commitRes is List && commitRes.isNotEmpty && commitRes[0] != 0) {
        return false;
      }

      await _apiService!.manageServiceAction(
        ip,
        sysauth,
        _useHttps,
        serviceName: 'cloudflared',
        action: enable ? 'start' : 'stop',
      );
      await _refreshDashboard();
      return true;
    } catch (e, stack) {
      Logger.exception('Failed to toggle Cloudflared', e, stack);
      return false;
    }
  }

  /// Bring WireGuard interface up or down
  Future<bool> toggleWireguardInterface(String ifaceName, bool bringUp) async {
    if (_isReviewerMode) return true;
    final ip = _ip;
    final sysauth = _sysauth;
    if (ip == null || sysauth == null || _apiService == null) return false;

    try {
      final cmd = bringUp ? '/sbin/ifup' : '/sbin/ifdown';
      await _apiService!.systemExec(
        ip,
        sysauth,
        _useHttps,
        command: '$cmd $ifaceName',
      );
      await _refreshDashboard();
      return true;
    } catch (e, stack) {
      Logger.exception(
        'Failed to toggle WireGuard interface $ifaceName',
        e,
        stack,
      );
      return false;
    }
  }

  /// Restart a VPN service daemon by service name
  Future<bool> restartVpnService(String serviceName) async {
    if (_isReviewerMode) return true;
    final ip = _ip;
    final sysauth = _sysauth;
    if (ip == null || sysauth == null || _apiService == null) return false;

    try {
      await _apiService!.manageServiceAction(
        ip,
        sysauth,
        _useHttps,
        serviceName: serviceName,
        action: 'restart',
      );
      await _refreshDashboard();
      return true;
    } catch (e, stack) {
      Logger.exception('Failed to restart VPN service $serviceName', e, stack);
      return false;
    }
  }

  // ── Services & Interface Controls ─────────────────────────────────

  Future<bool> manageServiceAction(
    String serviceName,
    String action, {
    BuildContext? context,
  }) async {
    if (_isReviewerMode) return true;
    final ip = _ip;
    final sysauth = _sysauth;
    if (ip == null || sysauth == null || _apiService == null) return false;

    final success = await _apiService!.manageServiceAction(
      ip,
      sysauth,
      _useHttps,
      serviceName: serviceName,
      action: action,
      context: context,
    );
    if (success) {
      await _refreshDashboard();
    }
    return success;
  }

  Future<bool> updateFirewallCustomRuleStatus(
    String sectionKey,
    bool enabled, {
    BuildContext? context,
  }) async {
    if (_isReviewerMode) {
      await Future.delayed(const Duration(milliseconds: 300));
      return true;
    }
    final ip = _ip;
    final sysauth = _sysauth;
    if (ip == null || sysauth == null || _apiService == null) return false;

    try {
      final setRes = await _apiService!.uciSet(
        ip,
        sysauth,
        _useHttps,
        config: 'firewall',
        section: sectionKey,
        values: {'enabled': enabled ? '1' : '0'},
        context: context,
      );
      if (setRes is List && setRes.isNotEmpty && setRes[0] != 0) return false;

      final commitRes = await _apiService!.uciCommit(
        ip,
        sysauth,
        _useHttps,
        config: 'firewall',
        context: (context != null && context.mounted) ? context : null,
      );
      if (commitRes is List && commitRes.isNotEmpty && commitRes[0] != 0) {
        return false;
      }

      await _apiService!.manageServiceAction(
        ip,
        sysauth,
        _useHttps,
        serviceName: 'firewall',
        action: 'reload',
        context: (context != null && context.mounted) ? context : null,
      );
      return true;
    } catch (e, stack) {
      Logger.exception(
        'updateFirewallCustomRuleStatus failed for $sectionKey',
        e,
        stack,
      );
      return false;
    }
  }

  Future<bool> updateWiredInterfaceStatus(
    String interfaceName,
    bool enabled, {
    BuildContext? context,
  }) async {
    if (_isReviewerMode) {
      await Future.delayed(const Duration(milliseconds: 300));
      return true;
    }
    final ip = _ip;
    final sysauth = _sysauth;
    if (ip == null || sysauth == null || _apiService == null) return false;

    try {
      final setRes = await _apiService!.uciSet(
        ip,
        sysauth,
        _useHttps,
        config: 'network',
        section: interfaceName,
        values: {'disabled': enabled ? '0' : '1'},
        context: context,
      );
      if (setRes is List && setRes.isNotEmpty && setRes[0] != 0) return false;

      final commitRes = await _apiService!.uciCommit(
        ip,
        sysauth,
        _useHttps,
        config: 'network',
        context: (context != null && context.mounted) ? context : null,
      );
      if (commitRes is List && commitRes.isNotEmpty && commitRes[0] != 0) {
        return false;
      }

      await _apiService!.manageServiceAction(
        ip,
        sysauth,
        _useHttps,
        serviceName: 'network',
        action: 'reload',
        context: (context != null && context.mounted) ? context : null,
      );
      return true;
    } catch (e, stack) {
      Logger.exception(
        'updateWiredInterfaceStatus failed for $interfaceName',
        e,
        stack,
      );
      return false;
    }
  }

  Future<bool> updateWirelessInterfaceStatus(
    String sectionKey,
    bool enabled, {
    BuildContext? context,
  }) async {
    if (_isReviewerMode) {
      await Future.delayed(const Duration(milliseconds: 300));
      return true;
    }
    final ip = _ip;
    final sysauth = _sysauth;
    if (ip == null || sysauth == null || _apiService == null) return false;

    try {
      final setRes = await _apiService!.uciSet(
        ip,
        sysauth,
        _useHttps,
        config: 'wireless',
        section: sectionKey,
        values: {'disabled': enabled ? '0' : '1'},
        context: context,
      );
      if (setRes is List && setRes.isNotEmpty && setRes[0] != 0) return false;

      final commitRes = await _apiService!.uciCommit(
        ip,
        sysauth,
        _useHttps,
        config: 'wireless',
        context: (context != null && context.mounted) ? context : null,
      );
      if (commitRes is List && commitRes.isNotEmpty && commitRes[0] != 0) {
        return false;
      }

      await _apiService!.systemExec(
        ip,
        sysauth,
        _useHttps,
        command: 'wifi reload',
        context: (context != null && context.mounted) ? context : null,
      );
      return true;
    } catch (e, stack) {
      Logger.exception(
        'updateWirelessInterfaceStatus failed for $sectionKey',
        e,
        stack,
      );
      return false;
    }
  }

  // ── Wi-Fi Access Control & Auto-Revert Safety ───────────────────────

  Map<String, String> _priorValuesSnapshot = {};

  Future<bool> applyWirelessInterfaceConfig({
    required String sectionName,
    required Map<String, String> newValues,
    required Map<String, String> priorValuesSnapshot,
    dynamic targetRadio,
    dynamic targetInterface,
    BuildContext? context,
  }) async {
    _pendingSectionName = sectionName;
    _pendingTargetType = 'ssid';
    _pendingTargetRadio = targetRadio;
    _pendingTargetInterface = targetInterface;
    _priorValuesSnapshot = priorValuesSnapshot;

    bool success = true;
    if (!_isReviewerMode) {
      final ip = _ip;
      final sysauth = _sysauth;
      if (ip == null || sysauth == null || _apiService == null) return false;

      success = await _apiService!.updateWirelessInterfaceConfig(
        ip,
        sysauth,
        _useHttps,
        sectionName: sectionName,
        values: newValues,
        context: (context != null && context.mounted) ? context : null,
      );
    }

    if (success) {
      startAccessControlAutoRevertTimer(initialSeconds: 25);
    }
    await _refreshDashboard();
    return success;
  }

  Future<bool> applyWirelessRadioConfig({
    required String sectionName,
    required Map<String, String> newValues,
    required Map<String, String> priorValuesSnapshot,
    dynamic targetRadio,
    BuildContext? context,
  }) async {
    _pendingSectionName = sectionName;
    _pendingTargetType = 'radio';
    _pendingTargetRadio = targetRadio;
    _pendingTargetInterface = null;
    _priorValuesSnapshot = priorValuesSnapshot;

    bool success = true;
    if (!_isReviewerMode) {
      final ip = _ip;
      final sysauth = _sysauth;
      if (ip == null || sysauth == null || _apiService == null) return false;

      success = await _apiService!.updateWirelessRadioConfig(
        ip,
        sysauth,
        _useHttps,
        sectionName: sectionName,
        values: newValues,
        context: (context != null && context.mounted) ? context : null,
      );
    }

    if (success) {
      startAccessControlAutoRevertTimer(initialSeconds: 25);
    }
    await _refreshDashboard();
    return success;
  }

  Future<bool> addWirelessInterface({
    required String radioName,
    required String ssid,
    required String encryption,
    required String key,
    required String network,
    BuildContext? context,
  }) async {
    bool success = true;
    if (!_isReviewerMode) {
      final ip = _ip;
      final sysauth = _sysauth;
      if (ip == null || sysauth == null || _apiService == null) return false;

      success = await _apiService!.addWirelessInterface(
        ip,
        sysauth,
        _useHttps,
        radioName: radioName,
        ssid: ssid,
        encryption: encryption,
        key: key,
        network: network,
        context: (context != null && context.mounted) ? context : null,
      );
    }

    if (success) {
      startAccessControlAutoRevertTimer(initialSeconds: 25);
    }
    await _refreshDashboard();
    return success;
  }

  Future<bool> deleteWirelessInterface({
    required String sectionName,
    BuildContext? context,
  }) async {
    bool success = true;
    if (!_isReviewerMode) {
      final ip = _ip;
      final sysauth = _sysauth;
      if (ip == null || sysauth == null || _apiService == null) return false;

      success = await _apiService!.deleteWirelessInterface(
        ip,
        sysauth,
        _useHttps,
        sectionName: sectionName,
        context: (context != null && context.mounted) ? context : null,
      );
    }

    if (success) {
      startAccessControlAutoRevertTimer(initialSeconds: 25);
    }
    await _refreshDashboard();
    return success;
  }

  Future<bool> provisionGuestNetwork({
    required String radioName,
    required String ssid,
    required String encryption,
    required String key,
    String guestIp = '192.168.2.1',
    bool isolateClients = true,
    String network = 'guest',
    // Advanced radio settings
    String? country,
    String? channel,
    String? htMode,
    String? txPower,
    // Fast roaming (802.11r/k/v)
    bool ieee80211r = false,
    bool ftOverDs = false,
    bool ftPskGenerateLocal = false,
    String? mobilityDomain,
    // Wireless advanced settings
    bool wmm = true,
    bool hidden = false,
    int? dtimPeriod,
    int? gtkRekey,
    int? inactivityLimit,
    int? maxListenInterval,
    bool disassocLowAck = true,
    bool multicastToUnicast = false,
    bool wds = false,
    // MAC filtering
    String? macfilter,
    List<String>? maclist,
    BuildContext? context,
  }) async {
    bool success = true;
    if (!_isReviewerMode) {
      final ip = _ip;
      final sysauth = _sysauth;
      if (ip == null || sysauth == null || _apiService == null) return false;

      success = await _apiService!.provisionGuestNetwork(
        ip,
        sysauth,
        _useHttps,
        radioName: radioName,
        ssid: ssid,
        encryption: encryption,
        key: key,
        guestIp: guestIp,
        isolateClients: isolateClients,
        network: network,
        country: country,
        channel: channel,
        htMode: htMode,
        txPower: txPower,
        ieee80211r: ieee80211r,
        ftOverDs: ftOverDs,
        ftPskGenerateLocal: ftPskGenerateLocal,
        mobilityDomain: mobilityDomain,
        wmm: wmm,
        hidden: hidden,
        dtimPeriod: dtimPeriod,
        gtkRekey: gtkRekey,
        inactivityLimit: inactivityLimit,
        maxListenInterval: maxListenInterval,
        disassocLowAck: disassocLowAck,
        multicastToUnicast: multicastToUnicast,
        wds: wds,
        macfilter: macfilter,
        maclist: maclist,
        context: (context != null && context.mounted) ? context : null,
      );
    }

    if (success) {
      startAccessControlAutoRevertTimer(initialSeconds: 25);
    }
    await _refreshDashboard();
    return success;
  }

  Future<List<String>> fetchNetworkInterfaces({BuildContext? context}) async {
    if (!_isReviewerMode) {
      final ip = _ip;
      final sysauth = _sysauth;
      if (ip == null || sysauth == null || _apiService == null) {
        return ['lan', 'wan', 'guest'];
      }

      return await _apiService!.fetchNetworkInterfaces(
        ipAddress: ip,
        sysauth: sysauth,
        useHttps: _useHttps,
        context: (context != null && context.mounted) ? context : null,
      );
    }
    return ['lan', 'wan', 'guest'];
  }

  Future<bool> applyWifiAccessControl({
    required Map<String, List<String>> newMaclistByIface,
    required Map<String, String> newMacfilterByIface,
    required Map<String, List<String>> priorMaclistSnapshot,
    required Map<String, String> priorMacfilterSnapshot,
    BuildContext? context,
  }) async {
    _priorMaclistSnapshot = priorMaclistSnapshot;
    _priorMacfilterSnapshot = priorMacfilterSnapshot;

    bool success = true;
    if (!_isReviewerMode) {
      final ip = _ip;
      final sysauth = _sysauth;
      if (ip == null || sysauth == null || _apiService == null) return false;

      success = await _apiService!.setWifiAccessControl(
        ip,
        sysauth,
        _useHttps,
        maclistByIface: newMaclistByIface,
        macfilterByIface: newMacfilterByIface,
        context: (context != null && context.mounted) ? context : null,
      );
    }

    if (success) {
      startAccessControlAutoRevertTimer(initialSeconds: 25);
    }
    await _refreshDashboard();
    return success;
  }

  void startAccessControlAutoRevertTimer({
    int initialSeconds = 25,
    Map<String, List<String>>? priorMaclist,
    Map<String, String>? priorMacfilter,
  }) {
    // Auto-revert timer removed per developer requirement. Changes require explicit user confirmation.
    _accessControlRevertTimer?.cancel();
    _accessControlCountdownTimer?.cancel();
    _isAccessControlPendingConfirmation = false;
    _accessControlCountdownSeconds = 0;
    _notifyListeners();
  }

  Future<bool> confirmWifiAccessControlChanges() async {
    _accessControlRevertTimer?.cancel();
    _accessControlCountdownTimer?.cancel();
    _isAccessControlPendingConfirmation = false;

    bool success = true;
    if (!_isReviewerMode) {
      final ip = _ip;
      final sysauth = _sysauth;
      if (ip != null && sysauth != null && _apiService != null) {
        success = await _apiService!.confirmWifiAccessControl(
          ip,
          sysauth,
          _useHttps,
        );
      }
    }

    _priorMaclistSnapshot = {};
    _priorMacfilterSnapshot = {};
    _pendingSectionName = null;
    _priorValuesSnapshot = {};
    _notifyListeners();
    return success;
  }

  Future<bool> revertWifiAccessControlChanges({BuildContext? context}) async {
    _accessControlRevertTimer?.cancel();
    _accessControlCountdownTimer?.cancel();
    _isAccessControlPendingConfirmation = false;
    _notifyListeners();

    if (_priorMaclistSnapshot.isEmpty &&
        _priorMacfilterSnapshot.isEmpty &&
        _pendingSectionName == null) {
      return true;
    }

    bool success = true;
    if (!_isReviewerMode) {
      final ip = _ip;
      final sysauth = _sysauth;
      if (ip != null && sysauth != null && _apiService != null) {
        if (_pendingSectionName != null) {
          success = await _apiService!.revertWirelessInterfaceConfig(
            ip,
            sysauth,
            _useHttps,
            sectionName: _pendingSectionName!,
            priorValues: _priorValuesSnapshot,
            context: (context != null && context.mounted) ? context : null,
          );
        } else {
          success = await _apiService!.revertWifiAccessControl(
            ip,
            sysauth,
            _useHttps,
            maclistByIface: _priorMaclistSnapshot,
            macfilterByIface: _priorMacfilterSnapshot,
            context: (context != null && context.mounted) ? context : null,
          );
        }

        if (!success) {
          int retries = 0;
          _accessControlRevertRetryTimer?.cancel();
          _accessControlRevertRetryTimer = Timer.periodic(
            const Duration(seconds: 3),
            (retryTimer) async {
              retries++;
              if (retries > 10) {
                retryTimer.cancel();
                _accessControlRevertRetryTimer = null;
                return;
              }
              final retried = _pendingSectionName != null
                  ? await _apiService!.revertWirelessInterfaceConfig(
                      ip,
                      sysauth,
                      _useHttps,
                      sectionName: _pendingSectionName!,
                      priorValues: _priorValuesSnapshot,
                    )
                  : await _apiService!.revertWifiAccessControl(
                      ip,
                      sysauth,
                      _useHttps,
                      maclistByIface: _priorMaclistSnapshot,
                      macfilterByIface: _priorMacfilterSnapshot,
                    );
              if (retried) {
                retryTimer.cancel();
                _accessControlRevertRetryTimer = null;
                await _refreshDashboard();
              }
            },
          );
        }
      }
    }

    _priorMaclistSnapshot = {};
    _priorMacfilterSnapshot = {};
    _pendingSectionName = null;
    _priorValuesSnapshot = {};
    await _refreshDashboard();
    _notifyListeners();
    return success;
  }

  Future<bool> autoFixPermissions({BuildContext? context}) async {
    if (_isReviewerMode) {
      await _redetectCapabilities();
      return true;
    }
    final ip = _ip;
    final sysauth = _sysauth;
    if (ip == null || sysauth == null || _apiService == null) return false;

    final res = await _apiService!.autoFixPermissions(
      ip,
      sysauth,
      _useHttps,
      context: context,
    );
    if (res) {
      await _redetectCapabilities();
    }
    return res;
  }

  // ── Client Actions ────────────────────────────────────────────────

  Future<bool> disconnectWirelessClient(
    String macAddress, {
    String? iface,
    int banTimeSeconds = 300,
    BuildContext? context,
  }) async {
    final macUpper = macAddress.toUpperCase().replaceAll('-', ':');
    if (_isReviewerMode) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (banTimeSeconds > 0) _bannedWirelessMacs.add(macUpper);
      _notifyListeners();
      unawaited(_refreshDashboard());
      return true;
    }
    final ip = _ip;
    final sysauth = _sysauth;
    if (ip == null || sysauth == null || _apiService == null) return false;

    final res = await _apiService!.disconnectWirelessClient(
      ip,
      sysauth,
      _useHttps,
      macAddress: macAddress,
      iface: iface,
      banTimeSeconds: banTimeSeconds,
      context: context,
    );
    if (res) {
      if (banTimeSeconds > 0) {
        _bannedWirelessMacs.add(macUpper);
      }
      _notifyListeners();
      unawaited(_refreshDashboard());
    }
    return res;
  }

  Future<bool> pauseClientInternet(
    String macAddress, {
    required bool pause,
    BuildContext? context,
  }) async {
    final macUpper = macAddress.toUpperCase().replaceAll('-', ':');
    if (_isReviewerMode) {
      if (pause) {
        _pausedInternetMacs.add(macUpper);
      } else {
        _pausedInternetMacs.remove(macUpper);
      }
      _notifyListeners();
      return true;
    }
    final ip = _ip;
    final sysauth = _sysauth;
    if (ip == null || sysauth == null || _apiService == null) return false;

    final res = await _apiService!.pauseClientInternet(
      ip,
      sysauth,
      _useHttps,
      macAddress: macAddress,
      pause: pause,
      context: context,
    );
    if (res) {
      if (pause) {
        _pausedInternetMacs.add(macUpper);
      } else {
        _pausedInternetMacs.remove(macUpper);
      }
      _notifyListeners();
    }
    return res;
  }

  Future<bool> applyParentalProfileDns({
    required String profileId,
    required List<String> macAddresses,
    required List<String>? dnsServers,
    BuildContext? context,
  }) async {
    if (_isReviewerMode) {
      await Future.delayed(const Duration(milliseconds: 300));
      return true;
    }
    final ip = _ip;
    final sysauth = _sysauth;
    if (ip == null || sysauth == null || _apiService == null) return false;

    final res = await _apiService!.applyParentalProfileDns(
      ip,
      sysauth,
      _useHttps,
      profileId: profileId,
      macAddresses: macAddresses,
      dnsServers: dnsServers,
      context: context,
    );
    if (res) {
      _notifyListeners();
    }
    return res;
  }

  Future<List<ParentalProfile>?> fetchParentalProfiles({
    BuildContext? context,
  }) async {
    final ip = _ip;
    final sysauth = _sysauth;
    if (ip == null || sysauth == null || _apiService == null) return [];

    return await _apiService!.fetchParentalProfiles(
      ip,
      sysauth,
      _useHttps,
      context: context,
    );
  }

  Future<bool> saveParentalProfile({
    required ParentalProfile profile,
    BuildContext? context,
  }) async {
    final ip = _ip;
    final sysauth = _sysauth;
    if (ip == null || sysauth == null || _apiService == null) return false;

    return await _apiService!.saveParentalProfile(
      ip,
      sysauth,
      _useHttps,
      profile: profile,
      context: context,
    );
  }

  Future<bool> deleteParentalProfile({
    required String profileId,
    BuildContext? context,
  }) async {
    final ip = _ip;
    final sysauth = _sysauth;
    if (ip == null || sysauth == null || _apiService == null) return false;

    return await _apiService!.deleteParentalProfile(
      ip,
      sysauth,
      _useHttps,
      profileId: profileId,
      context: context,
    );
  }

  Future<bool> addStaticLease({
    required String macAddress,
    required String targetIp,
    required String hostname,
    String? targetIp6,
    String? duid,
    String? leaseTime,
    BuildContext? context,
  }) async {
    final macUpper = macAddress.toUpperCase().replaceAll('-', ':');
    if (_isReviewerMode) {
      final dashboardData = _dashboardDataRef();
      if (dashboardData != null) {
        final hints = dashboardData['hostHints'] as Map<String, dynamic>? ?? {};
        hints[macUpper] = {
          'name': hostname,
          'staticLeaseName': hostname,
          'ipaddrs': [if (targetIp.isNotEmpty) targetIp],
          'staticLeaseIp': targetIp,
          'isStaticLease': true,
          if (targetIp6 != null && targetIp6.isNotEmpty) 'ip6addr': targetIp6,
          if (duid != null && duid.isNotEmpty) 'duid': duid,
          if (leaseTime != null && leaseTime.isNotEmpty) 'leasetime': leaseTime,
        };

        final rawUciDhcp =
            dashboardData['uciDhcpConfig'] ?? dashboardData['dhcp'];
        if (rawUciDhcp is Map) {
          final values = rawUciDhcp['values'] ?? rawUciDhcp;
          if (values is Map) {
            bool updated = false;
            values.forEach((k, v) {
              if (v is Map && v['.type'] == 'host') {
                final mac = v['mac']?.toString().toUpperCase().replaceAll(
                  '-',
                  ':',
                );
                if (mac == macUpper) {
                  v['name'] = hostname;
                  v['ip'] = targetIp;
                  if (targetIp6 != null && targetIp6.isNotEmpty) {
                    v['ip6addr'] = targetIp6;
                  }
                  if (duid != null && duid.isNotEmpty) {
                    v['duid'] = duid;
                  }
                  if (leaseTime != null && leaseTime.isNotEmpty) {
                    v['leasetime'] = leaseTime;
                  } else {
                    v.remove('leasetime');
                  }
                  updated = true;
                }
              }
            });
            if (!updated) {
              final newSecKey = 'host_${macUpper.replaceAll(':', '')}';
              final newSec = <String, dynamic>{
                '.type': 'host',
                '.name': newSecKey,
                'name': hostname,
                'mac': macUpper,
                'ip': targetIp,
                if (targetIp6 != null && targetIp6.isNotEmpty)
                  'ip6addr': targetIp6,
                if (duid != null && duid.isNotEmpty) 'duid': duid,
              };
              if (leaseTime != null && leaseTime.isNotEmpty) {
                newSec['leasetime'] = leaseTime;
              }
              values[newSecKey] = newSec;
            }
          }
        }
      }
      _notifyListeners();
      await _refreshDashboard();
      return true;
    }
    final ip = _ip;
    final sysauth = _sysauth;
    if (ip == null || sysauth == null || _apiService == null) return false;

    final res = await _apiService!.addStaticLease(
      ip,
      sysauth,
      _useHttps,
      macAddress: macAddress,
      targetIp: targetIp,
      hostname: hostname,
      targetIp6: targetIp6,
      duid: duid,
      leaseTime: leaseTime,
      context: context,
    );
    if (res) {
      final dashboardData = _dashboardDataRef();
      if (dashboardData != null) {
        if (dashboardData['hostHints'] is Map) {
          final hints = dashboardData['hostHints'] as Map;
          hints[macUpper] = {
            'name': hostname,
            'staticLeaseName': hostname,
            'ipaddrs': [if (targetIp.isNotEmpty) targetIp],
            'staticLeaseIp': targetIp,
            'isStaticLease': true,
            if (targetIp6 != null && targetIp6.isNotEmpty) 'ip6addr': targetIp6,
            if (duid != null && duid.isNotEmpty) 'duid': duid,
            if (leaseTime != null && leaseTime.isNotEmpty)
              'leasetime': leaseTime,
          };
        }
        final rawUciDhcp =
            dashboardData['uciDhcpConfig'] ?? dashboardData['dhcp'];
        if (rawUciDhcp is Map) {
          final values = rawUciDhcp['values'] ?? rawUciDhcp;
          if (values is Map) {
            bool updated = false;
            values.forEach((k, v) {
              if (v is Map && v['.type'] == 'host') {
                final rawMac = v['mac'];
                final macList = <String>[];
                if (rawMac is List) {
                  macList.addAll(
                    rawMac.map(
                      (e) => e.toString().toUpperCase().replaceAll('-', ':'),
                    ),
                  );
                } else if (rawMac != null) {
                  macList.addAll(
                    rawMac
                        .toString()
                        .split(RegExp(r'\s+'))
                        .map((e) => e.toUpperCase().replaceAll('-', ':')),
                  );
                }
                if (macList.contains(macUpper)) {
                  v['name'] = hostname;
                  v['ip'] = targetIp;
                  if (targetIp6 != null && targetIp6.isNotEmpty) {
                    v['ip6addr'] = targetIp6;
                  }
                  if (duid != null && duid.isNotEmpty) {
                    v['duid'] = duid;
                  }
                  if (leaseTime != null && leaseTime.isNotEmpty) {
                    v['leasetime'] = leaseTime;
                  } else {
                    v.remove('leasetime');
                  }
                  updated = true;
                }
              }
            });
            if (!updated) {
              final newSecKey = 'sec_${macUpper.replaceAll(":", "")}';
              values[newSecKey] = {
                '.type': 'host',
                '.name': newSecKey,
                'name': hostname,
                'mac': macUpper,
                'ip': targetIp,
                if (targetIp6 != null && targetIp6.isNotEmpty)
                  'ip6addr': targetIp6,
                if (duid != null && duid.isNotEmpty) 'duid': duid,
                if (leaseTime != null && leaseTime.isNotEmpty)
                  'leasetime': leaseTime,
              };
            }
          }
        }
      }
      await _refreshDashboard();
      _notifyListeners();
    }
    return res;
  }

  Future<bool> deleteStaticLease({
    required String macAddress,
    String? targetIp,
    String? hostname,
    String? duid,
    BuildContext? context,
  }) async {
    final macUpper = macAddress.toUpperCase().replaceAll('-', ':');
    if (_isReviewerMode) {
      final dashboardData = _dashboardDataRef();
      if (dashboardData != null) {
        final hints = dashboardData['hostHints'];
        if (hints is Map) {
          for (final entry in hints.entries) {
            final normKey = entry.key.toString().toUpperCase().replaceAll('-', ':');
            final val = entry.value;
            bool matches = normKey == macUpper;
            if (!matches && targetIp != null && val is Map) {
              final ips = val['ipaddrs'];
              if (ips is List && ips.contains(targetIp)) matches = true;
            }
            if (matches && val is Map) {
              val['isStaticLease'] = false;
              val.remove('staticLeaseName');
              val.remove('staticLeaseIp');
              val.remove('staticLeaseTime');
              val.remove('leasetime');
            }
          }
        }

        final rawUciDhcp =
            dashboardData['uciDhcpConfig'] ?? dashboardData['dhcp'];
        if (rawUciDhcp is Map) {
          final values = rawUciDhcp['values'] ?? rawUciDhcp;
          if (values is Map) {
            values.removeWhere((k, v) {
              if (v is Map && v['.type'] == 'host') {
                final mac = v['mac'];
                if (mac is List) {
                  if (mac
                      .map(
                        (e) => e.toString().toUpperCase().replaceAll('-', ':'),
                      )
                      .contains(macUpper)) {
                    return true;
                  }
                } else if (mac?.toString().toUpperCase().replaceAll('-', ':') ==
                    macUpper) {
                  return true;
                }
                if (targetIp != null &&
                    targetIp.isNotEmpty &&
                    targetIp != 'N/A' &&
                    v['ip']?.toString().trim() == targetIp.trim()) {
                  return true;
                }
                if (duid != null &&
                    duid.isNotEmpty &&
                    duid != 'N/A' &&
                    v['duid']?.toString().trim().toUpperCase() ==
                        duid.trim().toUpperCase()) {
                  return true;
                }
                if (hostname != null &&
                    hostname.isNotEmpty &&
                    hostname != 'Unknown' &&
                    hostname != '*' &&
                    hostname != 'Unnamed Host' &&
                    v['name']?.toString().trim().toLowerCase() ==
                        hostname.trim().toLowerCase()) {
                  return true;
                }
              }
              return false;
            });
          }
        }
      }
      _notifyListeners();
      await _refreshDashboard();
      return true;
    }
    final ip = _ip;
    final sysauth = _sysauth;
    if (ip == null || sysauth == null || _apiService == null) return false;

    final res = await _apiService!.deleteStaticLease(
      ip,
      sysauth,
      _useHttps,
      macAddress: macAddress,
      targetIp: targetIp,
      hostname: hostname,
      duid: duid,
      context: context,
    );
    if (res) {
      final dashboardData = _dashboardDataRef();
      if (dashboardData != null) {
        if (dashboardData['hostHints'] is Map) {
          final hints = dashboardData['hostHints'] as Map;
          for (final entry in hints.entries) {
            final normKey = entry.key.toString().toUpperCase().replaceAll('-', ':');
            final val = entry.value;
            bool matches = normKey == macUpper;
            if (!matches && targetIp != null && val is Map) {
              final ips = val['ipaddrs'];
              if (ips is List && ips.contains(targetIp)) matches = true;
            }
            if (matches && val is Map) {
              val['isStaticLease'] = false;
              val.remove('staticLeaseName');
              val.remove('staticLeaseIp');
              val.remove('staticLeaseTime');
              val.remove('leasetime');
            }
          }
        }
        final rawUciDhcp =
            dashboardData['uciDhcpConfig'] ?? dashboardData['dhcp'];
        if (rawUciDhcp is Map) {
          final values = rawUciDhcp['values'] ?? rawUciDhcp;
          if (values is Map) {
            values.removeWhere((k, v) {
              if (v is Map && v['.type'] == 'host') {
                final mac = v['mac'];
                if (mac is List) {
                  if (mac
                      .map(
                        (e) => e.toString().toUpperCase().replaceAll('-', ':'),
                      )
                      .contains(macUpper)) {
                    return true;
                  }
                } else if (mac?.toString().toUpperCase().replaceAll('-', ':') ==
                    macUpper) {
                  return true;
                }
                if (targetIp != null &&
                    targetIp.isNotEmpty &&
                    targetIp != 'N/A' &&
                    v['ip']?.toString().trim() == targetIp.trim()) {
                  return true;
                }
                if (duid != null &&
                    duid.isNotEmpty &&
                    duid != 'N/A' &&
                    v['duid']?.toString().trim().toUpperCase() ==
                        duid.trim().toUpperCase()) {
                  return true;
                }
                if (hostname != null &&
                    hostname.isNotEmpty &&
                    hostname != 'Unknown' &&
                    hostname != '*' &&
                    hostname != 'Unnamed Host' &&
                    v['name']?.toString().trim().toLowerCase() ==
                        hostname.trim().toLowerCase()) {
                  return true;
                }
              }
              return false;
            });
          }
        }
      }
      // Fire refresh in background — do NOT await; the caller (app_state)
      // already fires its own unawaited fetches after this returns.
      unawaited(_refreshDashboard());
      _notifyListeners();
    }
    return res;
  }

  Future<bool> refreshClientConnection({
    required String macAddress,
    BuildContext? context,
  }) async {
    final macUpper = macAddress.toUpperCase().replaceAll('-', ':');
    if (_isReviewerMode) {
      await _refreshDashboard();
      _notifyListeners();
      return true;
    }
    final ip = _ip;
    final sysauth = _sysauth;
    if (ip == null || sysauth == null || _apiService == null) return false;

    final res = await _apiService!.refreshClientConnection(
      ip,
      sysauth,
      _useHttps,
      macAddress: macUpper,
      context: context,
    );
    if (res) {
      await _refreshDashboard();
      _notifyListeners();
    }
    return res;
  }

  Future<int> flushUnusedDhcpLeases({
    List<Client>? clients,
    List<String>? macsToFlush,
    BuildContext? context,
  }) async {
    final List<String> targetMacs =
        macsToFlush ??
        (clients ?? [])
            .where((c) => !c.isConnected && !c.isStatic)
            .map((c) => c.macAddress.toUpperCase().replaceAll('-', ':'))
            .toList();

    if (targetMacs.isEmpty) return 0;

    if (_isReviewerMode) {
      final dashData = _dashboardDataRef();
      if (dashData != null) {
        final targetUpper = targetMacs
            .map((m) => m.toUpperCase().replaceAll('-', ':'))
            .toSet();

        String extractMac(dynamic item) {
          if (item is Map) {
            return (item['macaddr'] ?? item['mac'] ?? item['macAddress'] ?? '')
                .toString()
                .toUpperCase()
                .replaceAll('-', ':');
          }
          try {
            final dynamic m = (item as dynamic).macAddress;
            if (m != null) {
              return m.toString().toUpperCase().replaceAll('-', ':');
            }
          } catch (_) {}
          return '';
        }

        bool shouldKeep(dynamic item) {
          final mac = extractMac(item);
          if (mac.isEmpty) return true;
          return !targetUpper.contains(mac);
        }

        final dhcpLeases = dashData['dhcpLeases'];
        if (dhcpLeases is List) {
          dashData['dhcpLeases'] = dhcpLeases.where(shouldKeep).toList();
        } else if (dhcpLeases is Map) {
          final innerList = dhcpLeases['dhcpLeases'] ?? dhcpLeases['leases'];
          if (innerList is List) {
            dhcpLeases['dhcpLeases'] = innerList.where(shouldKeep).toList();
          }
        }

        final dhcp6Leases = dashData['dhcp6Leases'] ?? dashData['dhcp6_leases'];
        if (dhcp6Leases is List) {
          dashData['dhcp6Leases'] = dhcp6Leases.where(shouldKeep).toList();
        } else if (dhcp6Leases is Map) {
          final inner6List =
              dhcp6Leases['dhcp6Leases'] ?? dhcp6Leases['leases'];
          if (inner6List is List) {
            dhcp6Leases['dhcp6Leases'] = inner6List.where(shouldKeep).toList();
          }
        }
      }
      await _refreshDashboard();
      _notifyListeners();
      return targetMacs.length;
    }

    final ip = _ip;
    final sysauth = _sysauth;
    if (ip == null || sysauth == null || _apiService == null) return 0;

    final count = await _apiService!.deleteUnusedDhcpLeases(
      ip,
      sysauth,
      _useHttps,
      macsToFlush: targetMacs,
      context: context,
    );
    if (count > 0) {
      await _refreshDashboard();
      _notifyListeners();
    }
    return count;
  }

  Future<bool> banWirelessClient(
    String macAddress, {
    String? iface,
    int banTimeSeconds = 300,
    BuildContext? context,
  }) async {
    final macUpper = macAddress.toUpperCase().replaceAll('-', ':');
    if (_isReviewerMode) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (banTimeSeconds > 0) _bannedWirelessMacs.add(macUpper);
      _notifyListeners();
      unawaited(_refreshDashboard());
      return true;
    }
    final ip = _ip;
    final sysauth = _sysauth;
    if (ip == null || sysauth == null || _apiService == null) return false;

    final res = await _apiService!.banWirelessClient(
      ip,
      sysauth,
      _useHttps,
      macAddress: macAddress,
      iface: iface,
      banTimeSeconds: banTimeSeconds,
      context: context,
    );
    if (res) {
      if (banTimeSeconds > 0) {
        _bannedWirelessMacs.add(macUpper);
      }
      _notifyListeners();
      unawaited(_refreshDashboard());
    }
    return res;
  }

  Future<bool> unbanWirelessClient(
    String macAddress, {
    BuildContext? context,
  }) async {
    final macUpper = macAddress.toUpperCase().replaceAll('-', ':');
    if (_isReviewerMode) {
      await Future.delayed(const Duration(milliseconds: 300));
      _bannedWirelessMacs.remove(macUpper);
      _pausedInternetMacs.remove(macUpper);
      _notifyListeners();
      unawaited(_refreshDashboard());
      return true;
    }
    final ip = _ip;
    final sysauth = _sysauth;
    if (ip == null || sysauth == null || _apiService == null) return false;

    final res = await _apiService!.unbanWirelessClient(
      ip,
      sysauth,
      _useHttps,
      macAddress: macAddress,
      context: context,
    );
    if (res) {
      _bannedWirelessMacs.remove(macUpper);
      _pausedInternetMacs.remove(macUpper);
      _notifyListeners();
      unawaited(_refreshDashboard());
    }
    return res;
  }

  Future<bool> forceRefreshDhcpLeases({BuildContext? context}) async {
    if (_isReviewerMode) {
      await Future.delayed(const Duration(milliseconds: 300));
      await _refreshDashboard();
      _notifyListeners();
      return true;
    }
    final ip = _ip;
    final sysauth = _sysauth;
    if (ip == null || sysauth == null || _apiService == null) return false;

    final res = await _apiService!.forceRefreshDhcpLeases(
      ip,
      sysauth,
      _useHttps,
      context: context,
    );
    if (res) {
      await _refreshDashboard();
      _notifyListeners();
    }
    return res;
  }
}
