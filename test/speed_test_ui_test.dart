// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/modules/diagnostics/controllers/speed_test_controller.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/speed_test_models.dart';
import 'package:yet_another_luci_app/modules/diagnostics/screens/diagnostics_screen.dart';
import 'package:yet_another_luci_app/modules/diagnostics/services/speed_test_service.dart';
import 'package:yet_another_luci_app/modules/diagnostics/widgets/speed_test_view.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

class _MockSpeedTestService implements ISpeedTestService {
  final StreamController<SpeedTestProgress> _controller =
      StreamController<SpeedTestProgress>.broadcast();
  bool isCancelled = false;
  bool shouldFailWithAcl = false;

  @override
  Stream<SpeedTestProgress> get progressStream => _controller.stream;

  @override
  void cancel() {
    isCancelled = true;
    _controller.add(
      const SpeedTestProgress(
        stage: SpeedTestStage.cancelled,
        statusMessage: 'Cancelled',
      ),
    );
  }

  @override
  Future<String> detectTransportType() async => 'Router WAN';

  @override
  Future<SpeedTestResult> runTest({
    int downloadByteTarget = 15000000,
    int uploadByteTarget = 4000000,
    int latencyProbes = 5,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    if (shouldFailWithAcl) {
      _controller.add(
        const SpeedTestProgress(
          stage: SpeedTestStage.failed,
          statusMessage:
              'Router WAN speed test requires RPC execution permissions. Run RPC Setup in Settings',
        ),
      );
      return SpeedTestResult(
        stage: SpeedTestStage.failed,
        errorMessage:
            'Router WAN speed test requires RPC execution permissions. Run RPC Setup in Settings',
        isPermissionDenied: true,
        idleLatencyMs: 9.1,
        jitterMs: 1.8,
        loadedLatencyMs: 8.3,
        timestamp: DateTime.now(),
      );
    }

    _controller.add(
      const SpeedTestProgress(
        stage: SpeedTestStage.measuringDownload,
        currentSpeedMbps: 92.4,
        progressPercent: 0.5,
        statusMessage: 'Downloading...',
      ),
    );

    return SpeedTestResult(
      downloadSpeedMbps: 92.4,
      uploadSpeedMbps: 45.1,
      idleLatencyMs: 14.2,
      jitterMs: 1.5,
      loadedLatencyMs: 20.8,
      connectionType: 'Router WAN (wan)',
      vantagePoint: 'Router Internet Speed Test (WAN)',
      serverName: 'Cloudflare Anycast (speed.cloudflare.com)',
      timestamp: DateTime.now(),
      downloadBytes: downloadByteTarget,
      uploadBytes: uploadByteTarget,
      downloadDurationMs: 1300,
      uploadDurationMs: 710,
      stage: SpeedTestStage.completed,
    );
  }

  @override
  Future<SpeedTestResult> runRouterSpeedTest({
    required IApiService api,
    required String routerIp,
    required String sysauth,
    bool useHttps = false,
    String? wanInterface,
    Duration timeout = const Duration(seconds: 30),
    RouterCapabilities? capabilities,
  }) async {
    return runTest();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestWidget({
    required Widget child,
    ISpeedTestService? service,
    Locale locale = const Locale('en'),
  }) {
    final appState = AppState.instance;
    appState.setApiServiceForTesting(MockApiService());

    return ProviderScope(
      overrides: [
        appStateProvider.overrideWith((ref) => appState),
        if (service != null)
          speedTestServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: Scaffold(body: child),
      ),
    );
  }

  group('SpeedTestView Widget Tests', () {
    testWidgets('Renders idle state without displaying false zero speed', (
      tester,
    ) async {
      final mockService = _MockSpeedTestService();
      await tester.pumpWidget(
        buildTestWidget(child: const SpeedTestView(), service: mockService),
      );
      await tester.pumpAndSettle();

      expect(find.text('Router Internet Speed Test (WAN)'), findsOneWidget);
      expect(
        find.textContaining(
          'Vantage Point: Direct OpenWrt router WAN interface',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Endpoint: Cloudflare Anycast edge'),
        findsOneWidget,
      );
      expect(find.text('DOWNLOAD'), findsOneWidget);
      expect(find.text('UPLOAD'), findsOneWidget);
      expect(find.text('Start Router Speed Test'), findsOneWidget);

      // Verify that idle state shows '--' instead of misleading 0.0 Mbps
      expect(
        find.text('--'),
        findsNWidgets(4),
      ); // Download, Upload, Idle Ping, Jitter
      expect(find.text('0.0'), findsNothing);
    });

    testWidgets(
      'Tapping Start Router Speed Test executes and displays measured results',
      (tester) async {
        final mockService = _MockSpeedTestService();
        await tester.pumpWidget(
          buildTestWidget(child: const SpeedTestView(), service: mockService),
        );
        await tester.pumpAndSettle();

        // Tap Start Router Speed Test
        await tester.tap(find.text('Start Router Speed Test'));
        await tester.pump();
        await tester.pumpAndSettle();

        // Verify results display
        expect(find.text('92.4'), findsOneWidget);
        expect(find.text('45.1'), findsOneWidget);
        expect(find.text('14.2 ms'), findsOneWidget);
        expect(find.text('1.5 ms'), findsOneWidget);
        expect(find.text('Run Router Speed Test Again'), findsOneWidget);
      },
    );

    testWidgets('Integrated in DiagnosticsScreen TabBar and can be selected', (
      tester,
    ) async {
      final mockService = _MockSpeedTestService();
      await tester.pumpWidget(
        buildTestWidget(child: const DiagnosticsScreen(), service: mockService),
      );
      await tester.pumpAndSettle();

      // Tab 'Speed Test' exists
      final speedTab = find.text('Speed Test');
      expect(speedTab, findsOneWidget);

      // Tap 'Speed Test' Tab
      await tester.tap(speedTab);
      await tester.pumpAndSettle();

      // Verify SpeedTestView is active
      expect(find.byType(SpeedTestView), findsOneWidget);
      expect(find.text('Router Internet Speed Test (WAN)'), findsOneWidget);
    });

    testWidgets(
      'Displays actionable Open RPC Setup button when test fails due to rpcd ACL permission denied',
      (tester) async {
        final mockService = _MockSpeedTestService()..shouldFailWithAcl = true;

        await tester.pumpWidget(
          buildTestWidget(child: const SpeedTestView(), service: mockService),
        );
        await tester.pumpAndSettle();

        // Tap Start Router Speed Test
        await tester.tap(find.text('Start Router Speed Test'));
        await tester.pump();
        await tester.pumpAndSettle();

        // Verify actionable banner message and Open RPC Setup button
        expect(
          find.text(
            'Router WAN speed test requires RPC execution permissions. Run RPC Setup in Settings',
          ),
          findsNWidgets(2),
        );
        expect(find.text('Open RPC Setup'), findsOneWidget);
        expect(
          find.byIcon(Icons.admin_panel_settings_outlined),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.build_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'Displays localized speed test permission error message and Open RPC Setup button in German',
      (tester) async {
        final mockService = _MockSpeedTestService()..shouldFailWithAcl = true;

        await tester.pumpWidget(
          buildTestWidget(
            child: const SpeedTestView(),
            service: mockService,
            locale: const Locale('de'),
          ),
        );
        await tester.pumpAndSettle();

        // Tap Start Router Speed Test button (in German)
        await tester.tap(find.text('Router-Geschwindigkeitstest starten'));
        await tester.pump();
        await tester.pumpAndSettle();

        // Verify localized message and button
        expect(
          find.text(
            'Router-WAN-Geschwindigkeitstest erfordert RPC-Ausführungsberechtigungen. Führen Sie RPC-Setup in den Einstellungen aus',
          ),
          findsOneWidget,
        );
        expect(find.text('RPC-Setup öffnen'), findsOneWidget);
      },
    );

    testWidgets(
      'Renders correct router name in vantage banner when switching router profiles',
      (tester) async {
        final mockService = _MockSpeedTestService();
        final appState = AppState.instance;

        // 1. Initial router profile: ncxRouter
        final routerA = model.Router(
          id: 'router-prod-1',
          ipAddress: '10.0.0.1',
          username: 'root',
          password: 'pw',
          useHttps: false,
          name: 'ncxRouter',
        );
        appState.setSelectedRouterForTesting(routerA);

        await tester.pumpWidget(
          buildTestWidget(child: const SpeedTestView(), service: mockService),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining(
            'Vantage Point: Direct OpenWrt router WAN interface (Router WAN (ncxRouter))',
          ),
          findsOneWidget,
        );

        // Tap Start Router Speed Test on routerA
        await tester.tap(find.text('Start Router Speed Test'));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('92.4'), findsOneWidget);
        expect(find.text('45.1'), findsOneWidget);

        // 2. Switch to test router profile: ncxTest
        final routerB = model.Router(
          id: 'router-test-2',
          ipAddress: '10.0.0.125',
          username: 'root',
          password: 'pw',
          useHttps: false,
          name: 'ncxTest',
        );
        appState.setSelectedRouterForTesting(routerB);
        await tester.pump();
        await tester.pumpAndSettle();

        // Must display ncxTest in banner and NOT display routerA's speed results
        expect(
          find.textContaining(
            'Vantage Point: Direct OpenWrt router WAN interface (Router WAN (ncxTest))',
          ),
          findsOneWidget,
        );
        expect(find.text('92.4'), findsNothing);
        expect(find.text('45.1'), findsNothing);
        expect(find.text('--'), findsNWidgets(4));
      },
    );
  });
}
