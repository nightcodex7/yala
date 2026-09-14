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
  int _throughputIntervalSeconds = 4;

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
  /// Returns true if the interval actually changed.
  bool setInterval(
    int seconds, {
    required bool isRebooting,
    required VoidCallback onTick,
  }) {
    final clamped = seconds.clamp(1, 10);
    if (_throughputIntervalSeconds == clamped) return false;
    _throughputIntervalSeconds = clamped;
    startTimer(isRebooting: isRebooting, onTick: onTick);
    return true;
  }

  /// Starts (or restarts) the periodic throughput poll timer.
  void startTimer({required bool isRebooting, required VoidCallback onTick}) {
    _throughputTimer?.cancel();
    if (isRebooting) return;
    _throughputTimer = Timer.periodic(
      Duration(seconds: _throughputIntervalSeconds),
      (_) => onTick(),
    );
  }

  /// Cancels the timer and clears accumulated history.
  void cancelAndClear() {
    _throughputTimer?.cancel();
    _throughputService.clear();
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

  /// Cleans up all resources. Must be called from AppState.dispose().
  void dispose() {
    _throughputTimer?.cancel();
  }
}
