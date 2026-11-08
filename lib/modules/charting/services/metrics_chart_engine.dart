// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Class encapsulating real-time history series data.
class RealtimeMetricsData {
  final List<double> _cpuBuffer;
  final List<double> _ramBuffer;
  final List<double> _rxBuffer;
  final List<double> _txBuffer;
  final int pollingIntervalSeconds;
  final int timeWindowSeconds;

  RealtimeMetricsData({
    List<double>? cpuHistory,
    List<double>? ramHistory,
    List<double>? rxHistory,
    List<double>? txHistory,
    List<double>? cpuBuffer,
    List<double>? ramBuffer,
    List<double>? rxBuffer,
    List<double>? txBuffer,
    required this.pollingIntervalSeconds,
    this.timeWindowSeconds = 60,
  }) : _cpuBuffer = cpuBuffer ?? cpuHistory ?? const [],
       _ramBuffer = ramBuffer ?? ramHistory ?? const [],
       _rxBuffer = rxBuffer ?? rxHistory ?? const [],
       _txBuffer = txBuffer ?? txHistory ?? const [];

  /// Maximum points in history buffer to cover timeWindowSeconds at pollingIntervalSeconds.
  int get maxPoints =>
      (timeWindowSeconds / pollingIntervalSeconds).round().clamp(6, 300);

  /// Slices buffer to the active time window capacity.
  List<double> get cpuHistory => _slice(_cpuBuffer);
  List<double> get ramHistory => _slice(_ramBuffer);
  List<double> get rxHistory => _slice(_rxBuffer);
  List<double> get txHistory => _slice(_txBuffer);

  /// Full master buffers preserving history across rolling window changes.
  List<double> get cpuBuffer => _cpuBuffer;
  List<double> get ramBuffer => _ramBuffer;
  List<double> get rxBuffer => _rxBuffer;
  List<double> get txBuffer => _txBuffer;

  List<double> _slice(List<double> list) {
    final limit = maxPoints;
    if (list.length <= limit) return list;
    return list.sublist(list.length - limit);
  }

  RealtimeMetricsData copyWith({
    List<double>? cpuBuffer,
    List<double>? ramBuffer,
    List<double>? rxBuffer,
    List<double>? txBuffer,
    List<double>? cpuHistory,
    List<double>? ramHistory,
    List<double>? rxHistory,
    List<double>? txHistory,
    int? pollingIntervalSeconds,
    int? timeWindowSeconds,
  }) {
    return RealtimeMetricsData(
      cpuBuffer: cpuBuffer ?? cpuHistory ?? _cpuBuffer,
      ramBuffer: ramBuffer ?? ramHistory ?? _ramBuffer,
      rxBuffer: rxBuffer ?? rxHistory ?? _rxBuffer,
      txBuffer: txBuffer ?? txHistory ?? _txBuffer,
      pollingIntervalSeconds:
          pollingIntervalSeconds ?? this.pollingIntervalSeconds,
      timeWindowSeconds: timeWindowSeconds ?? this.timeWindowSeconds,
    );
  }
}

/// Dynamic polling engine with decoupled rolling time window (e.g. 60s) and configurable polling interval (1s-10s).
class MetricsChartEngine extends StateNotifier<RealtimeMetricsData> {
  static const int maxCapacity = 300;

  MetricsChartEngine({int timeWindowSeconds = 60, int intervalSeconds = 2})
    : super(
        RealtimeMetricsData(
          cpuBuffer: [],
          ramBuffer: [],
          rxBuffer: [],
          txBuffer: [],
          pollingIntervalSeconds: intervalSeconds.clamp(1, 10),
          timeWindowSeconds: timeWindowSeconds.clamp(15, 600),
        ),
      );

  int get maxPoints => state.maxPoints;

  void updatePollingInterval(int seconds) {
    final clamped = seconds.clamp(1, 10);
    if (state.pollingIntervalSeconds == clamped) return;
    state = state.copyWith(pollingIntervalSeconds: clamped);
  }

  void updateTimeWindow(int seconds) {
    final clamped = seconds.clamp(15, 600);
    if (state.timeWindowSeconds == clamped) return;
    state = state.copyWith(timeWindowSeconds: clamped);
  }

  /// Seeds buffer with available history or initial baseline metrics.
  void seedHistory({
    required List<double> rxHistory,
    required List<double> txHistory,
    required double cpuUsage,
    required double ramUsage,
  }) {
    if (state.cpuBuffer.isNotEmpty) return;
    final int count = math.max(rxHistory.length, txHistory.length);
    if (count == 0) {
      addSample(cpuUsage: cpuUsage, ramUsage: ramUsage, rxRate: 0, txRate: 0);
      return;
    }
    final cpuList = List<double>.filled(count, cpuUsage);
    final ramList = List<double>.filled(count, ramUsage);
    final rxList = List<double>.from(rxHistory);
    final txList = List<double>.from(txHistory);
    state = state.copyWith(
      cpuBuffer: cpuList,
      ramBuffer: ramList,
      rxBuffer: rxList,
      txBuffer: txList,
    );
  }

  /// Appends a new metric sample point to history buffer, maintaining full historical capacity.
  void addSample({
    required double cpuUsage,
    required double ramUsage,
    required double rxRate,
    required double txRate,
  }) {
    List<double> append(List<double> list, double value) {
      final updated = List<double>.from(list)..add(value);
      while (updated.length > maxCapacity) {
        updated.removeAt(0);
      }
      return updated;
    }

    state = state.copyWith(
      cpuBuffer: append(state.cpuBuffer, cpuUsage),
      ramBuffer: append(state.ramBuffer, ramUsage),
      rxBuffer: append(state.rxBuffer, rxRate),
      txBuffer: append(state.txBuffer, txRate),
    );
  }
}

final metricsChartEngineProvider =
    StateNotifierProvider<MetricsChartEngine, RealtimeMetricsData>((ref) {
      return MetricsChartEngine();
    });
