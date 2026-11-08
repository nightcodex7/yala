// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/models/dashboard_preferences.dart';
import 'package:yet_another_luci_app/services/throughput_service.dart';

/// Encapsulates throughput polling, timer lifecycle, and interface-specific
/// rate history. Extracted from AppState to enforce single-responsibility
/// and proper timer lifecycle management.
///
/// [AppState] retains forwarding getters so every existing call-site
/// (`appState.rxHistory`, `appState.currentTxRate`, etc.) continues
/// to work without modification.
class ThroughputController {
  ThroughputController({required ThroughputService throughputService})
    : _throughputService = throughputService;

  final ThroughputService _throughputService;

  Timer? _throughputTimer;
  int _throughputIntervalSeconds = 2;

  int get throughputIntervalSeconds => _throughputIntervalSeconds;

  // ── Proxy getters ──────────────────────────────────────────────

  List<double> get rxHistory => _throughputService.rxHistory;
  List<double> get txHistory => _throughputService.txHistory;
  double get currentRxRate => _throughputService.currentRxRate;
  double get currentTxRate => _throughputService.currentTxRate;

  List<double> getRxHistoryForInterface(String interface) =>
      _throughputService.getRxHistoryForInterface(interface);

  List<double> getTxHistoryForInterface(String interface) =>
      _throughputService.getTxHistoryForInterface(interface);

  double getCurrentRxRateForInterface(String interface) =>
      _throughputService.getCurrentRxRateForInterface(interface);

  double getCurrentTxRateForInterface(String interface) =>
      _throughputService.getCurrentTxRateForInterface(interface);

  // ── Timer lifecycle ────────────────────────────────────────────

  /// Updates the polling interval (clamped 1–10s) and restarts the timer.
  /// Returns true if the interval actually changed or if the timer was restarted.
  bool setInterval(
    int seconds, {
    required bool isRebooting,
    required VoidCallback onTick,
    bool immediateTick = true,
  }) {
    final clamped = seconds.clamp(1, 10);
    final changed = _throughputIntervalSeconds != clamped;
    final wasRunning = isTimerRunning;
    _throughputIntervalSeconds = clamped;
    startTimer(isRebooting: isRebooting, onTick: onTick);
    if (immediateTick && !isRebooting) {
      Future.microtask(onTick);
    }
    return changed || !wasRunning;
  }

  bool _isPaused = false;

  /// Whether the throughput polling timer is currently active.
  bool get isTimerRunning =>
      _throughputTimer != null && _throughputTimer!.isActive;

  /// Whether the throughput timer was active before being paused.
  bool get isPaused => _isPaused;

  /// Starts (or restarts) the periodic throughput poll timer.
  void startTimer({required bool isRebooting, required VoidCallback onTick}) {
    _isPaused = false;
    _throughputTimer?.cancel();
    if (isRebooting) return;
    _throughputTimer = Timer.periodic(
      Duration(seconds: _throughputIntervalSeconds),
      (_) => onTick(),
    );
  }

  /// Cancels the timer and clears accumulated history.
  void cancelAndClear() {
    _isPaused = false;
    _throughputTimer?.cancel();
    _throughputTimer = null;
    _throughputService.clear();
  }

  /// Pauses the polling timer without clearing rate history.
  void pauseTimer() {
    if (isTimerRunning) {
      _isPaused = true;
      _throughputTimer?.cancel();
      _throughputTimer = null;
    }
  }

  /// Resumes the timer if paused or restarts if not currently running.
  void resumeTimer({
    required bool isRebooting,
    required VoidCallback onTick,
    bool immediateTick = false,
  }) {
    if (_isPaused) {
      _isPaused = false;
      _throughputService.resetBaseline();
      startTimer(isRebooting: isRebooting, onTick: onTick);
      if (immediateTick && !isRebooting) {
        Future.microtask(onTick);
      }
    }
  }

  /// Resets the baseline timestamp and stats without clearing historical rate queues.
  void resetBaseline() {
    _throughputService.resetBaseline();
  }

  /// Feeds network data into the underlying ThroughputService.
  void updateThroughput(
    Map<String, dynamic>? networkData,
    Set<String> wanDeviceNames, {
    String? specificInterface,
  }) {
    _throughputService.updateThroughput(
      networkData,
      wanDeviceNames,
      specificInterface: specificInterface,
    );
  }

  /// Extracts the specific-interface device name from dashboard preferences,
  /// handling the "SSID (deviceName)" and bare-deviceName formats.
  static String? resolveSpecificInterface(
    DashboardPreferences prefs, {
    String? Function(String)? deviceNameResolver,
  }) {
    if (prefs.showAllThroughput || prefs.primaryThroughputInterface == null) {
      return null;
    }
    final interfaceId = prefs.primaryThroughputInterface!;
    if (interfaceId.contains('(')) {
      final match = RegExp(r'\(([^)]+)\)').firstMatch(interfaceId);
      return match?.group(1);
    }
    if (deviceNameResolver != null) {
      final resolved = deviceNameResolver(interfaceId);
      if (resolved != null && resolved.isNotEmpty) {
        return resolved;
      }
    }
    return interfaceId;
  }

  /// Resolves the set of network device names to monitor for overall throughput.
  ///
  /// For standard gateway routers with a WAN interface (DHCP, PPPoE, static WAN, etc.),
  /// this returns only the external WAN layer-3 device(s), preventing double-counting
  /// with LAN bridges or local Wi-Fi traffic.
  ///
  /// For routers in Dumb AP or bridge-only mode (where no WAN interface exists),
  /// this falls back exclusively to the primary LAN bridge device (e.g. `br-lan`),
  /// avoiding duplication across physical member switch ports and wireless radios.
  static Set<String> resolveThroughputDeviceNames(
    Map<String, dynamic>? interfaceDump,
  ) {
    if (interfaceDump == null || interfaceDump['interface'] is! List) {
      return const <String>{};
    }

    final wanDevices = <String>{};
    final lanDevices = <String>{};

    for (final interface in interfaceDump['interface']) {
      if (interface is! Map<String, dynamic>) continue;
      final ifname = (interface['interface'] as String?)?.toLowerCase();
      if (ifname == null || ifname == 'loopback' || ifname == 'lo') continue;

      final proto = (interface['proto'] as String?)?.toLowerCase();
      // Prefer l3_device (the layer-3 routed interface, e.g. pppoe-wan or eth1)
      // over device (the underlying carrier) to prevent double counting.
      final device = interface['device'] as String?;
      final l3Device = interface['l3_device'] as String?;
      final targetDev = (l3Device != null && l3Device.isNotEmpty)
          ? l3Device
          : device;

      if (targetDev == null || targetDev == 'lo' || targetDev.isEmpty) continue;

      final isWan =
          ifname.startsWith('wan') ||
          proto == 'pppoe' ||
          interface['is_wan'] == true;

      if (isWan) {
        wanDevices.add(targetDev);
      } else if (ifname == 'lan') {
        lanDevices.add(targetDev);
      } else if (ifname.startsWith('lan') && lanDevices.isEmpty) {
        lanDevices.add(targetDev);
      }
    }

    if (wanDevices.isNotEmpty) {
      return wanDevices;
    }

    if (lanDevices.isNotEmpty) {
      return lanDevices;
    }

    return const <String>{};
  }

  /// Cleans up all resources. Must be called from AppState.dispose().
  void dispose() {
    _throughputTimer?.cancel();
  }
}
