// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/models/dashboard_preferences.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/services/interfaces/auth_service_interface.dart';
import 'package:yet_another_luci_app/services/router_service.dart';
import 'package:yet_another_luci_app/services/secure_storage_service.dart';
import 'package:yet_another_luci_app/services/throughput_service.dart';
import 'package:yet_another_luci_app/state/controllers/client_controller.dart';
import 'package:yet_another_luci_app/state/controllers/dashboard_controller.dart';
import 'package:yet_another_luci_app/state/controllers/session_controller.dart';
import 'package:yet_another_luci_app/state/controllers/throughput_controller.dart';
import 'package:yet_another_luci_app/utils/http_client_manager.dart';

class MockAuthService implements IAuthService {
  String? _sysauth = 'initial_sysauth';
  bool _isAuthenticated = true;
  bool _useHttps = false;
  int logoutCount = 0;
  int loginCount = 0;
  int tryAutoLoginCount = 0;

  @override
  String? get sysauth => _sysauth;

  @override
  bool get isAuthenticated => _isAuthenticated;

  @override
  bool get useHttps => _useHttps;

  @override
  Future<void> login(
    String ip,
    String username,
    String password,
    bool useHttps, {
    dynamic context,
  }) async {
    loginCount++;
    _sysauth = 'token_for_$ip';
    _isAuthenticated = true;
    _useHttps = useHttps;
  }

  @override
  Future<void> logout() async {
    logoutCount++;
    _sysauth = null;
    _isAuthenticated = false;
  }

  @override
  Future<bool> tryAutoLogin(
    String? ip,
    String? username,
    String? password,
    bool? useHttps, {
    bool force = false,
    dynamic context,
  }) async {
    tryAutoLoginCount++;
    _sysauth = 'reconnected_token';
    _isAuthenticated = true;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockApiService implements IApiService {
  int callCount = 0;
  Map<String, dynamic> customResponses = {};

  @override
  Future<dynamic> call(
    String ip,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    dynamic context,
  }) async {
    callCount++;
    final key = '$object.$method';
    if (customResponses.containsKey(key)) {
      final val = customResponses[key];
      if (val is Exception) throw val;
      if (val is Error) throw val;
      return val;
    }

    if (object == 'system' && method == 'board') {
      return [
        0,
        {
          'model': 'TestRouter-$ip',
          'board_name': 'test-board',
          'release': {'version': '24.10.0'},
        },
      ];
    }
    if (object == 'system' && method == 'info') {
      return [
        0,
        {
          'memory': {'total': 1000, 'free': 500},
        },
      ];
    }
    return [0, <String, dynamic>{}];
  }

  @override
  Future<dynamic> callSimple(
    String object,
    String method,
    Map<String, dynamic> params,
  ) async {
    return [0, <String, dynamic>{}];
  }

  @override
  Future<bool> ensureSilentPermissions(
    String ip,
    String sysauth,
    bool useHttps,
  ) async => true;

  @override
  Future<Map<String, Set<String>>> fetchAssociatedStations() async => {};

  @override
  Future<Map<String, dynamic>?> fetchWireGuardPeers({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interface,
    dynamic context,
  }) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Router Profile Switching & Deadlock Prevention Tests', () {
    late RouterService routerService;
    late MockAuthService authService;
    late MockApiService apiService;
    late SecureStorageService secureStorageService;
    late ThroughputController throughputController;
    late DashboardController dashboardController;
    late SessionController sessionController;
    late ClientController clientController;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      routerService = RouterService();
      authService = MockAuthService();
      apiService = MockApiService();
      secureStorageService = SecureStorageService();
      throughputController = ThroughputController(
        throughputService: ThroughputService(),
      );

      dashboardController = DashboardController(
        apiServiceRef: () => apiService,
        authServiceRef: () => authService,
        routerServiceRef: () => routerService,
        secureStorageServiceRef: () => secureStorageService,
        throughputControllerRef: () => throughputController,
        dashboardPreferencesRef: () => DashboardPreferences(),
        reviewerModeRef: () => false,
        tryAutoLogin: ({bool force = false, bool fetchDashboard = true}) async {
          return await sessionController.tryAutoLogin(
            force: force,
            fetchDashboard: fetchDashboard,
          );
        },
        fetchPublicIps: () async {},
        setPublicIps: (v4, v6) {},
        setConnectionStatus: (status) {},
        startThroughputTimer: () {},
        updateThroughputOnly: () {},
        processDhcpLeases: (raw) => raw,
        notifyListeners: () {},
      );

      sessionController = SessionController(
        initialReviewerMode: false,
        apiServiceRef: () => apiService,
        authServiceRef: () => authService,
        routerServiceRef: () => routerService,
        secureStorageServiceRef: () => secureStorageService,
        httpClientManagerRef: () => HttpClientManager(),
        dashboardControllerRef: () => dashboardController,
        cancelThroughputTimer: () {},
        startThroughputTimer: () {},
        fetchDashboardData: ({bool force = false}) =>
            dashboardController.fetchDashboardData(force: force),
        initializeServices: () {},
        setLoadingState: (_) {},
        setErrorState: (_) {},
        notifyListeners: () {},
      );

      clientController = ClientController(
        apiServiceRef: () => apiService,
        authServiceRef: () => authService,
        routerServiceRef: () => routerService,
        reviewerModeRef: () => false,
        dashboardDataRef: () => dashboardController.dashboardData,
        executeRouterCommandOutput: (cmd, args) async => '',
        processDhcpLeases: (raw) => raw,
      );
    });

    test(
      'updateSysInfo does NOT create dummy dashboardData when boardInfo is missing',
      () {
        dashboardController.resetState();
        expect(dashboardController.dashboardData, isNull);

        // Throughput tick updates sysInfo
        dashboardController.updateSysInfo({'memory': {'total': 100}});

        // dashboardData must STILL be null to avoid bypassing loading skeleton with N/A model
        expect(dashboardController.dashboardData, isNull);
      },
    );

    test(
      'Optional RPC Access Denied does NOT abort dashboard fetch or trigger deadlock',
      () async {
        final router = model.Router(
          id: 'test_router_1',
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'password',
          useHttps: false,
        );
        await routerService.addRouter(router);
        await routerService.selectRouter(router.id);

        // Simulate luci-rpc.getMountPoints returning access denied (code -32002)
        apiService.customResponses['luci-rpc.getMountPoints'] = Exception(
          'RPC luci-rpc.getMountPoints failed: Access denied (-32002)',
        );

        // Fetch dashboard data
        await dashboardController.fetchDashboardData(force: true);

        // Should successfully complete with boardInfo populated
        expect(dashboardController.dashboardData, isNotNull);
        expect(
          dashboardController.dashboardData?['boardInfo']?['model'],
          'TestRouter-192.168.1.1',
        );
        expect(dashboardController.dashboardError, isNull);
      },
    );

    test(
      'Switching router profile cleanly logs out, clears old state, and loads new details',
      () async {
        final router1 = model.Router(
          id: 'router_1',
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'pass1',
          useHttps: false,
          name: 'Router 1',
        );
        final router2 = model.Router(
          id: 'router_2',
          ipAddress: '10.0.0.1',
          username: 'root',
          password: 'pass2',
          useHttps: false,
          name: 'Router 2',
        );

        await routerService.addRouter(router1);
        await routerService.addRouter(router2);

        // Select Router 1 and fetch data
        await sessionController.selectRouter(router1.id);
        expect(routerService.selectedRouter?.id, router1.id);
        expect(
          dashboardController.dashboardData?['boardInfo']?['model'],
          'TestRouter-192.168.1.1',
        );

        // Switch to Router 2
        await sessionController.selectRouter(router2.id);

        // Verify router 2 is selected and loaded
        expect(routerService.selectedRouter?.id, router2.id);
        expect(authService.logoutCount, greaterThanOrEqualTo(2));
        expect(authService.sysauth, 'token_for_10.0.0.1');
        expect(
          dashboardController.dashboardData?['boardInfo']?['model'],
          'TestRouter-10.0.0.1',
        );
      },
    );

    test('ClientController resetState clears client cache', () {
      clientController.lastFetchedClients = [
        Client(
          ipAddress: '192.168.1.100',
          macAddress: 'AA:BB:CC:DD:EE:FF',
          hostname: 'Test Device',
        ),
      ];
      expect(clientController.lastFetchedClients, isNotEmpty);

      clientController.resetState();
      expect(clientController.lastFetchedClients, isNull);
    });
  });
}
