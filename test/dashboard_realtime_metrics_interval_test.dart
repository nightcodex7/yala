// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/services/mock_auth_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Dashboard Real-Time Network Metric Chart Interval Tests', () {
    late AppState appState;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      appState = AppState.instance;
      appState.setApiServiceForTesting(MockApiService());
      appState.setAuthServiceForTesting(MockAuthService());
      appState.setSelectedRouterForTesting(
        model.Router(
          id: 'test-router-metrics',
          ipAddress: '192.168.1.1',
          name: 'Test Router',
          username: 'root',
          password: 'password',
          useHttps: false,
        ),
      );
    });

    test('Dashboard throughput polling interval defaults to 2 seconds', () {
      expect(appState.throughputIntervalSeconds, equals(2));
    });

    test(
      'setDashboardTabActive enforces 2-second interval for dashboard real-time chart',
      () {
        // Simulate interval change while away from dashboard
        appState.setThroughputInterval(5);
        expect(appState.throughputIntervalSeconds, equals(5));

        // Activating dashboard tab restores interval to 2 seconds
        appState.setDashboardTabActive(false);
        appState.setDashboardTabActive(true);
        expect(appState.throughputIntervalSeconds, equals(2));
      },
    );

    test(
      'Releasing external telemetry consumers restores dashboard 2-second interval',
      () {
        appState.setDashboardTabActive(true);
        expect(appState.throughputIntervalSeconds, equals(2));

        // Real Time Metrics (ChartingScreen) acquires telemetry and sets custom interval
        appState.acquireRealtimeTelemetry();
        appState.setThroughputInterval(6);
        expect(appState.throughputIntervalSeconds, equals(6));

        // When ChartingScreen disposes and releases telemetry, dashboard restores 2s
        appState.releaseRealtimeTelemetry();
        expect(appState.throughputIntervalSeconds, equals(2));
      },
    );

    test('resumeThroughputTimer on Dashboard preserves 2-second interval', () {
      appState.setDashboardTabActive(true);
      appState.pauseThroughputTimer();
      appState.resumeThroughputTimer();
      expect(appState.throughputIntervalSeconds, equals(2));
    });
  });
}
