// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Class encapsulating real-time history series data.
class RealtimeMetricsData {
  final List<double> cpuHistory;
  final List<double> ramHistory;
  final List<double> rxHistory;
  final List<double> txHistory;
  final int pollingIntervalSeconds;
  final int timeWindowSeconds;

  const RealtimeMetricsData({
    required this.cpuHistory,
    required this.ramHistory,
    required this.rxHistory,
    required this.txHistory,
    required this.pollingIntervalSeconds,
    this.timeWindowSeconds = 60,
  });

  /// Maximum points in history buffer to cover timeWindowSeconds at pollingIntervalSeconds.
  int get maxPoints =>
      (timeWindowSeconds / pollingIntervalSeconds).round().clamp(6, 300);

  RealtimeMetricsData copyWith({
    List<double>? cpuHistory,
    List<double>? ramHistory,
    List<double>? rxHistory,
    List<double>? txHistory,
    int? pollingIntervalSeconds,
    int? timeWindowSeconds,
  }) {
    return RealtimeMetricsData(
      cpuHistory: cpuHistory ?? this.cpuHistory,
      ramHistory: ramHistory ?? this.ramHistory,
      rxHistory: rxHistory ?? this.rxHistory,
      txHistory: txHistory ?? this.txHistory,
      pollingIntervalSeconds:
          pollingIntervalSeconds ?? this.pollingIntervalSeconds,
      timeWindowSeconds: timeWindowSeconds ?? this.timeWindowSeconds,
    );
  }
}

/// Dynamic polling engine with decoupled rolling time window (e.g. 60s) and configurable polling interval (1s-10s).
class MetricsChartEngine extends StateNotifier<RealtimeMetricsData> {
  Timer? _timer;

  MetricsChartEngine({int timeWindowSeconds = 60, int intervalSeconds = 2})
    : super(
        RealtimeMetricsData(
          cpuHistory: [],
          ramHistory: [],
          rxHistory: [],
          txHistory: [],
          pollingIntervalSeconds: intervalSeconds.clamp(1, 10),
          timeWindowSeconds: timeWindowSeconds.clamp(15, 600),
        ),
      );

  int get maxPoints => state.maxPoints;

  void updatePollingInterval(int seconds) {
    final clamped = seconds.clamp(1, 10);
    if (state.pollingIntervalSeconds == clamped) return;

    final newState = state.copyWith(pollingIntervalSeconds: clamped);
    final limit = newState.maxPoints;

    state = newState.copyWith(
      cpuHistory: _trim(newState.cpuHistory, limit),
      ramHistory: _trim(newState.ramHistory, limit),
      rxHistory: _trim(newState.rxHistory, limit),
      txHistory: _trim(newState.txHistory, limit),
    );
  }

  void updateTimeWindow(int seconds) {
    final clamped = seconds.clamp(15, 600);
    if (state.timeWindowSeconds == clamped) return;

    final newState = state.copyWith(timeWindowSeconds: clamped);
    final limit = newState.maxPoints;

    state = newState.copyWith(
      cpuHistory: _trim(newState.cpuHistory, limit),
      ramHistory: _trim(newState.ramHistory, limit),
      rxHistory: _trim(newState.rxHistory, limit),
      txHistory: _trim(newState.txHistory, limit),
    );
  }

  List<double> _trim(List<double> list, int limit) {
    if (list.length <= limit) return list;
    return list.sublist(list.length - limit);
  }

  /// Appends a new metric sample point to history buffer, maintaining time window capacity.
  void addSample({
    required double cpuUsage,
    required double ramUsage,
    required double rxRate,
    required double txRate,
  }) {
    final limit = maxPoints;

    List<double> append(List<double> list, double value) {
      final updated = List<double>.from(list)..add(value);
      while (updated.length > limit) {
        updated.removeAt(0);
      }
      return updated;
    }

    state = state.copyWith(
      cpuHistory: append(state.cpuHistory, cpuUsage),
      ramHistory: append(state.ramHistory, ramUsage),
      rxHistory: append(state.rxHistory, rxRate),
      txHistory: append(state.txHistory, txRate),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final metricsChartEngineProvider =
    StateNotifierProvider<MetricsChartEngine, RealtimeMetricsData>((ref) {
      return MetricsChartEngine();
    });
