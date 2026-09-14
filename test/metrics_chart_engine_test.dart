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
  });
}
