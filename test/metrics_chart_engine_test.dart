// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/charting/services/metrics_chart_engine.dart';

void main() {
  group('MetricsChartEngine Tests', () {
    test('Decouples time window from polling interval correctly', () {
      final engine = MetricsChartEngine(
        timeWindowSeconds: 60,
        intervalSeconds: 2,
      );

      // Default: 60s window @ 2s poll rate = 30 max points
      expect(engine.state.timeWindowSeconds, 60);
      expect(engine.state.pollingIntervalSeconds, 2);
      expect(engine.state.maxPoints, 30);

      // Change poll rate to 1s -> 60s / 1s = 60 max points
      engine.updatePollingInterval(1);
      expect(engine.state.pollingIntervalSeconds, 1);
      expect(engine.state.maxPoints, 60);

      // Change time window to 120s @ 1s poll rate = 120 max points
      engine.updateTimeWindow(120);
      expect(engine.state.timeWindowSeconds, 120);
      expect(engine.state.maxPoints, 120);
    });

    test('Buffers and trims samples maintaining calculated maxPoints', () {
      final engine = MetricsChartEngine(
        timeWindowSeconds: 30,
        intervalSeconds: 5,
      );
      // 30s / 5s = 6 max points
      expect(engine.state.maxPoints, 6);

      for (int i = 1; i <= 10; i++) {
        engine.addSample(
          cpuUsage: i.toDouble(),
          ramUsage: i * 2.0,
          rxRate: 1000.0,
          txRate: 500.0,
        );
      }

      expect(engine.state.cpuHistory.length, 6);
      expect(engine.state.cpuHistory.first, 5.0);
      expect(engine.state.cpuHistory.last, 10.0);
    });

    test(
      'Rolling window expansion preserves historical buffer and reveals earlier points',
      () {
        final engine = MetricsChartEngine(
          timeWindowSeconds: 30,
          intervalSeconds: 2,
        );
        // 30s @ 2s = 15 max points
        expect(engine.state.maxPoints, 15);

        // Add 30 samples (e.g. 1.0 to 30.0)
        for (int i = 1; i <= 30; i++) {
          engine.addSample(
            cpuUsage: i.toDouble(),
            ramUsage: i * 1.5,
            rxRate: i * 100.0,
            txRate: i * 50.0,
          );
        }

        // Sliced view for 30s window must show only the latest 15 points (16.0 to 30.0)
        expect(engine.state.cpuHistory.length, 15);
        expect(engine.state.cpuHistory.first, 16.0);
        expect(engine.state.cpuHistory.last, 30.0);

        // Expand window to 60s @ 2s = 30 max points
        engine.updateTimeWindow(60);
        expect(engine.state.maxPoints, 30);
        // History should NOT have been destroyed! Earlier points are revealed:
        expect(engine.state.cpuHistory.length, 30);
        expect(engine.state.cpuHistory.first, 1.0);
        expect(engine.state.cpuHistory.last, 30.0);

        // Expand window further to 120s @ 2s = 60 max points
        engine.updateTimeWindow(120);
        expect(engine.state.maxPoints, 60);
        // Still contains all 30 points collected
        expect(engine.state.cpuHistory.length, 30);
        expect(engine.state.cpuHistory.first, 1.0);

        // Contract window back to 30s
        engine.updateTimeWindow(30);
        expect(engine.state.maxPoints, 15);
        expect(engine.state.cpuHistory.length, 15);
        expect(engine.state.cpuHistory.first, 16.0);
      },
    );

    test(
      'seedHistory populates empty buffer and ignores subsequent seed calls',
      () {
        final engine = MetricsChartEngine();
        expect(engine.state.cpuBuffer, isEmpty);

        engine.seedHistory(
          rxHistory: [100.0, 200.0, 300.0],
          txHistory: [50.0, 60.0, 70.0],
          cpuUsage: 25.0,
          ramUsage: 45.0,
        );

        expect(engine.state.cpuBuffer.length, 3);
        expect(engine.state.cpuBuffer, [25.0, 25.0, 25.0]);
        expect(engine.state.rxBuffer, [100.0, 200.0, 300.0]);

        // Second call must be a no-op to avoid resetting ongoing data
        engine.seedHistory(
          rxHistory: [999.0],
          txHistory: [999.0],
          cpuUsage: 99.0,
          ramUsage: 99.0,
        );

        expect(engine.state.cpuBuffer.length, 3);
        expect(engine.state.cpuBuffer.first, 25.0);
      },
    );

    test('Buffer caps at maxCapacity (300) without memory leak', () {
      final engine = MetricsChartEngine();
      for (int i = 1; i <= 350; i++) {
        engine.addSample(
          cpuUsage: i.toDouble(),
          ramUsage: 50.0,
          rxRate: 100.0,
          txRate: 100.0,
        );
      }

      expect(engine.state.cpuBuffer.length, MetricsChartEngine.maxCapacity);
      // Earliest 50 were trimmed in FIFO order
      expect(engine.state.cpuBuffer.first, 51.0);
      expect(engine.state.cpuBuffer.last, 350.0);
    });
  });
}
