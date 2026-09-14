// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:collection';
import 'dart:math';

class ThroughputService {
  final Queue<double> _rxHistory = Queue<double>();
  final Queue<double> _txHistory = Queue<double>();

  double _currentRxRate = 0;
  double _currentTxRate = 0;
  Map<String, dynamic>? _lastStats;
  DateTime? _lastTimestamp;

  // Per-interface tracking
  final Map<String, Queue<double>> _rxHistoryPerInterface = {};
  final Map<String, Queue<double>> _txHistoryPerInterface = {};
  final Map<String, double> _currentRxRatePerInterface = {};
  final Map<String, double> _currentTxRatePerInterface = {};
  final Map<String, Map<String, dynamic>?> _lastStatsPerInterface = {};
  final Map<String, DateTime?> _lastTimestampPerInterface = {};

  static const int _maxHistoryLength = 50;
  static const double _maxRate = 1000.0 * 1024.0 * 1024.0; // 1 GB/s
  static const double _minElapsedSeconds = 0.1;

  List<double> get rxHistory => _rxHistory.toList();
  List<double> get txHistory => _txHistory.toList();
  double get currentRxRate => _currentRxRate;
  double get currentTxRate => _currentTxRate;

  // Interface-specific getters
  List<double> getRxHistoryForInterface(String interface) {
    if (_rxHistoryPerInterface.containsKey(interface)) {
      return _rxHistoryPerInterface[interface]!.toList();
    }
    if (interface == 'lan' && _rxHistoryPerInterface.containsKey('br-lan')) {
      return _rxHistoryPerInterface['br-lan']!.toList();
    }
    if (interface == 'wan' && _rxHistoryPerInterface.containsKey('eth0')) {
      return _rxHistoryPerInterface['eth0']!.toList();
    }
    return [];
  }

  List<double> getTxHistoryForInterface(String interface) {
    if (_txHistoryPerInterface.containsKey(interface)) {
      return _txHistoryPerInterface[interface]!.toList();
    }
    if (interface == 'lan' && _txHistoryPerInterface.containsKey('br-lan')) {
      return _txHistoryPerInterface['br-lan']!.toList();
    }
    if (interface == 'wan' && _txHistoryPerInterface.containsKey('eth0')) {
      return _txHistoryPerInterface['eth0']!.toList();
    }
    return [];
  }

  double getCurrentRxRateForInterface(String interface) {
    if (_currentRxRatePerInterface.containsKey(interface)) {
      return _currentRxRatePerInterface[interface]!;
    }
    if (interface == 'lan' &&
        _currentRxRatePerInterface.containsKey('br-lan')) {
      return _currentRxRatePerInterface['br-lan']!;
    }
    if (interface == 'wan' && _currentRxRatePerInterface.containsKey('eth0')) {
      return _currentRxRatePerInterface['eth0']!;
    }
    return 0.0;
  }

  double getCurrentTxRateForInterface(String interface) {
    if (_currentTxRatePerInterface.containsKey(interface)) {
      return _currentTxRatePerInterface[interface]!;
    }
    if (interface == 'lan' &&
        _currentTxRatePerInterface.containsKey('br-lan')) {
      return _currentTxRatePerInterface['br-lan']!;
    }
    if (interface == 'wan' && _currentTxRatePerInterface.containsKey('eth0')) {
      return _currentTxRatePerInterface['eth0']!;
    }
    return 0.0;
  }

  void updateThroughput(
    Map<String, dynamic>? networkData,
    Set<String> wanDeviceNames, {
    String? specificInterface,
  }) {
    final now = DateTime.now();

    // Always update per-interface throughput for all interfaces
    if (networkData != null) {
      networkData.forEach((devName, devData) {
        _updateInterfaceThroughput(devName, devData, now);
      });
    }

    // Update overall throughput
    if (specificInterface != null && specificInterface.isNotEmpty) {
      String? matchedKey;
      if (networkData != null) {
        if (networkData.containsKey(specificInterface)) {
          matchedKey = specificInterface;
        } else {
          // Fallback matching: map logical interface names (e.g. lan -> br-lan, wan -> eth0)
          for (final entry in networkData.entries) {
            final devName = entry.key;
            if (devName == specificInterface ||
                (specificInterface == 'lan' && devName == 'br-lan') ||
                (specificInterface == 'wan' && devName == 'eth0')) {
              matchedKey = devName;
              break;
            }
            final devData = entry.value;
            if (devData is Map<String, dynamic>) {
              if (devData['device'] == specificInterface ||
                  devData['l3_device'] == specificInterface) {
                matchedKey = devName;
                break;
              }
            }
          }
        }
      }

      if (matchedKey != null) {
        _updateSpecificInterfaceThroughput(
          matchedKey,
          networkData![matchedKey],
          now,
        );
      } else {
        // Interface not found in data, clear current rates
        _currentRxRate = 0;
        _currentTxRate = 0;
      }
    } else {
      // Update combined throughput as before
      if (_lastStats == null || _lastTimestamp == null) {
        _lastStats = networkData;
        _lastTimestamp = now;
        // Add an initial zero-rate data point so the UI has something to display
        _addToHistory(0.0, 0.0);
        return;
      }

      final elapsedSeconds =
          now.difference(_lastTimestamp!).inMilliseconds / 1000.0;

      // Only calculate throughput if we have a reasonable time difference
      if (elapsedSeconds >= _minElapsedSeconds) {
        final lastRx = _calculateTotalBytes(
          _lastStats,
          'rx_bytes',
          wanDeviceNames: wanDeviceNames,
        );
        final lastTx = _calculateTotalBytes(
          _lastStats,
          'tx_bytes',
          wanDeviceNames: wanDeviceNames,
        );
        final currentRx = _calculateTotalBytes(
          networkData,
          'rx_bytes',
          wanDeviceNames: wanDeviceNames,
        );
        final currentTx = _calculateTotalBytes(
          networkData,
          'tx_bytes',
          wanDeviceNames: wanDeviceNames,
        );

        // Calculate rates with a reasonable maximum to prevent spikes
        final rxRate = max(0, (currentRx - lastRx) / elapsedSeconds);
        final txRate = max(0, (currentTx - lastTx) / elapsedSeconds);

        // Cap the rates to prevent unrealistic spikes
        _currentRxRate = min(rxRate.toDouble(), _maxRate);
        _currentTxRate = min(txRate.toDouble(), _maxRate);

        _addToHistory(_currentRxRate, _currentTxRate);
      }

      _lastStats = networkData;
      _lastTimestamp = now;
    }
  }

  void _updateInterfaceThroughput(
    String interface,
    dynamic devData,
    DateTime now,
  ) {
    if (devData == null || devData is! Map<String, dynamic>) return;

    final lastStats = _lastStatsPerInterface[interface];
    final lastTimestamp = _lastTimestampPerInterface[interface];

    if (lastStats == null || lastTimestamp == null) {
      _lastStatsPerInterface[interface] = devData;
      _lastTimestampPerInterface[interface] = now;

      // Initialize history for this interface
      _rxHistoryPerInterface.putIfAbsent(interface, () => Queue<double>());
      _txHistoryPerInterface.putIfAbsent(interface, () => Queue<double>());
      _rxHistoryPerInterface[interface]!.add(0.0);
      _txHistoryPerInterface[interface]!.add(0.0);
      return;
    }

    final elapsedSeconds =
        now.difference(lastTimestamp).inMilliseconds / 1000.0;

    if (elapsedSeconds >= _minElapsedSeconds) {
      // Handle both formats: stats.rx_bytes and direct rx_bytes
      final lastRx =
          (lastStats['stats']?['rx_bytes'] ?? lastStats['rx_bytes'] ?? 0)
              as num;
      final lastTx =
          (lastStats['stats']?['tx_bytes'] ?? lastStats['tx_bytes'] ?? 0)
              as num;
      final currentRx =
          (devData['stats']?['rx_bytes'] ?? devData['rx_bytes'] ?? 0) as num;
      final currentTx =
          (devData['stats']?['tx_bytes'] ?? devData['tx_bytes'] ?? 0) as num;

      final rxRate = max(0, (currentRx - lastRx) / elapsedSeconds);
      final txRate = max(0, (currentTx - lastTx) / elapsedSeconds);

      _currentRxRatePerInterface[interface] = min(rxRate.toDouble(), _maxRate);
      _currentTxRatePerInterface[interface] = min(txRate.toDouble(), _maxRate);

      _addToInterfaceHistory(
        interface,
        _currentRxRatePerInterface[interface]!,
        _currentTxRatePerInterface[interface]!,
      );
    }

    _lastStatsPerInterface[interface] = devData;
    _lastTimestampPerInterface[interface] = now;
  }

  void _updateSpecificInterfaceThroughput(
    String interface,
    dynamic devData,
    DateTime now,
  ) {
    if (devData == null || devData is! Map<String, dynamic>) return;

    final rxRate = _currentRxRatePerInterface[interface] ?? 0.0;
    final txRate = _currentTxRatePerInterface[interface] ?? 0.0;

    _currentRxRate = rxRate;
    _currentTxRate = txRate;

    // Use the interface's history for the main display
    final rxHist = _rxHistoryPerInterface[interface];
    final txHist = _txHistoryPerInterface[interface];

    if (rxHist != null && txHist != null) {
      _rxHistory.clear();
      _txHistory.clear();
      _rxHistory.addAll(rxHist);
      _txHistory.addAll(txHist);
    }
  }

  void _addToInterfaceHistory(String interface, double rxRate, double txRate) {
    final rxHist = _rxHistoryPerInterface.putIfAbsent(
      interface,
      () => Queue<double>(),
    );
    final txHist = _txHistoryPerInterface.putIfAbsent(
      interface,
      () => Queue<double>(),
    );

    rxHist.add(rxRate);
    txHist.add(txRate);

    // Maintain fixed queue size
    if (rxHist.length > _maxHistoryLength) {
      rxHist.removeFirst();
    }
    if (txHist.length > _maxHistoryLength) {
      txHist.removeFirst();
    }
  }

  void _addToHistory(double rxRate, double txRate) {
    _rxHistory.add(rxRate);
    _txHistory.add(txRate);

    // Maintain fixed queue size for O(1) performance
    if (_rxHistory.length > _maxHistoryLength) {
      _rxHistory.removeFirst();
    }
    if (_txHistory.length > _maxHistoryLength) {
      _txHistory.removeFirst();
    }
  }

  num _calculateTotalBytes(
    Map<String, dynamic>? networkData,
    String key, {
    Set<String>? wanDeviceNames,
  }) {
    if (networkData == null) return 0;
    num total = 0;
    networkData.forEach((devName, devData) {
      // If wanDeviceNames is null, count all devices (old behavior).
      // Otherwise, only count devices in the set.
      if (wanDeviceNames == null || wanDeviceNames.contains(devName)) {
        if (devData is Map<String, dynamic>) {
          // Handle both formats: stats.rx_bytes and direct rx_bytes
          if (devData['stats'] is Map<String, dynamic> &&
              devData['stats'][key] != null) {
            total += devData['stats'][key];
          } else if (devData[key] != null) {
            total += devData[key];
          }
        }
      }
    });
    return total;
  }

  void clear() {
    _rxHistory.clear();
    _txHistory.clear();
    _currentRxRate = 0;
    _currentTxRate = 0;
    _lastStats = null;
    _lastTimestamp = null;

    // Clear per-interface data
    _rxHistoryPerInterface.clear();
    _txHistoryPerInterface.clear();
    _currentRxRatePerInterface.clear();
    _currentTxRatePerInterface.clear();
    _lastStatsPerInterface.clear();
    _lastTimestampPerInterface.clear();
  }
}
