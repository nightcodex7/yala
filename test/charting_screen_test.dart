// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/modules/charting/screens/charting_screen.dart';
import 'package:yet_another_luci_app/modules/charting/services/metrics_chart_engine.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  tearDown(() {
    AppState.instance.pauseThroughputTimer();
  });

  group('ChartingScreen Widget Tests', () {
    testWidgets('Acquires telemetry on mount and releases on dispose', (
      tester,
    ) async {
      final appState = AppState.instance;
      // Initially, dashboard tab is inactive (e.g. navigated from More tab)
      appState.setDashboardTabActive(false);
      expect(appState.isThroughputPollingActive, isFalse);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStateProvider.overrideWith((ref) => appState)],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ChartingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Upon mounting ChartingScreen, acquireRealtimeTelemetry must activate polling
      expect(appState.isThroughputPollingActive, isTrue);

      // Now unmount ChartingScreen (navigate back)
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStateProvider.overrideWith((ref) => appState)],
          child: const MaterialApp(home: Scaffold(body: Text('Back'))),
        ),
      );
      await tester.pumpAndSettle();

      // After unmounting, telemetry polling should be deactivated to preserve battery
      expect(appState.isThroughputPollingActive, isFalse);
    });

    testWidgets('Renders config card with slider and rolling window options', (
      tester,
    ) async {
      final appState = AppState.instance;
      appState.setDashboardTabActive(false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStateProvider.overrideWith((ref) => appState)],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ChartingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check slider and default interval '2s'
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('2s'), findsWidgets);

      // Check rolling window options: 30s, 1m, 2m, 5m
      expect(find.text('30s'), findsOneWidget);
      expect(find.text('1m'), findsOneWidget);
      expect(find.text('2m'), findsOneWidget);
      expect(find.text('5m'), findsOneWidget);
    });

    testWidgets('Tapping rolling window segment updates engine time window', (
      tester,
    ) async {
      final appState = AppState.instance;
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStateProvider.overrideWith((ref) => appState)],
          child: Consumer(
            builder: (context, ref, child) {
              container = ProviderScope.containerOf(context);
              return const MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: ChartingScreen(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial default window is 60s
      expect(container.read(metricsChartEngineProvider).timeWindowSeconds, 60);

      // Tap '2m' (120s)
      await tester.tap(find.text('2m'));
      await tester.pumpAndSettle();

      // Engine window must be updated to 120s
      expect(container.read(metricsChartEngineProvider).timeWindowSeconds, 120);
      expect(find.text('120s'), findsOneWidget);

      // Tap '5m' (300s)
      await tester.tap(find.text('5m'));
      await tester.pumpAndSettle();

      expect(container.read(metricsChartEngineProvider).timeWindowSeconds, 300);
      expect(find.text('300s'), findsOneWidget);
    });

    testWidgets(
      'Adjusting polling interval slider updates AppState and engine',
      (tester) async {
        final appState = AppState.instance;
        late ProviderContainer container;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [appStateProvider.overrideWith((ref) => appState)],
            child: Consumer(
              builder: (context, ref, child) {
                container = ProviderScope.containerOf(context);
                return const MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: ChartingScreen(),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Initial interval is 2s
        expect(appState.throughputIntervalSeconds, 2);
        expect(
          container.read(metricsChartEngineProvider).pollingIntervalSeconds,
          2,
        );

        // Programmatically invoke slider or appState interval update
        appState.setThroughputInterval(5);
        await tester.pumpAndSettle();

        expect(appState.throughputIntervalSeconds, 5);
        expect(
          container.read(metricsChartEngineProvider).pollingIntervalSeconds,
          5,
        );
        expect(find.text('5s'), findsWidgets);
      },
    );
  });
}
