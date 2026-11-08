// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/parental_controls/models/parental_profile.dart';
import 'package:yet_another_luci_app/modules/system_monitoring/models/system_metrics.dart';
import 'package:yet_another_luci_app/state/controllers/dashboard_controller.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/state/controllers/session_controller.dart';
import 'package:yet_another_luci_app/services/router_service.dart';
import 'package:yet_another_luci_app/services/interfaces/auth_service_interface.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/models/dashboard_preferences.dart';
import 'package:yet_another_luci_app/services/secure_storage_service.dart';
import 'package:yet_another_luci_app/utils/http_client_manager.dart';

class FakeRouterService implements RouterService {
  final List<model.Router> _routers = [];
  model.Router? _selectedRouter;

  FakeRouterService({List<model.Router>? initialRouters}) {
    if (initialRouters != null) {
      _routers.addAll(initialRouters);
      if (_routers.isNotEmpty) {
        _selectedRouter = _routers.first;
      }
    }
  }

  @override
  List<model.Router> get routers => List.unmodifiable(_routers);

  @override
  model.Router? get selectedRouter => _selectedRouter;

  @override
  Future<void> loadRouters() async {}

  @override
  Future<model.Router?> selectRouter(String id) async {
    final match = _routers.where((r) => r.id == id).firstOrNull;
    if (match != null) {
      _selectedRouter = match;
    }
    return match;
  }

  @override
  Future<void> addRouter(model.Router router) async {
    _routers.add(router);
  }

  @override
  Future<void> updateRouter(model.Router router, {String? oldId}) async {
    final targetId = oldId ?? router.id;
    final index = _routers.indexWhere((r) => r.id == targetId);
    if (index != -1) {
      _routers[index] = router;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthService implements IAuthService {
  String? lastPassedIp;
  String? lastPassedUser;
  String? lastPassedPass;
  bool? lastPassedHttps;
  bool isAuthed = false;
  String? token;

  @override
  bool get isAuthenticated => isAuthed;

  @override
  String? get sysauth => token;

  @override
  Future<bool> tryAutoLogin(
    String? ipAddress,
    String? username,
    String? password,
    bool? useHttps, {
    bool force = false,
    dynamic context,
  }) async {
    lastPassedIp = ipAddress;
    lastPassedUser = username;
    lastPassedPass = password;
    lastPassedHttps = useHttps;
    isAuthed = ipAddress != null && username != null && password != null;
    if (isAuthed) {
      token = 'token_for_$ipAddress';
    }
    return isAuthed;
  }

  @override
  Future<void> login(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    dynamic context,
  }) async {
    lastPassedIp = ipAddress;
    lastPassedUser = username;
    lastPassedPass = password;
    lastPassedHttps = useHttps;
    isAuthed = true;
    token = 'token_for_$ipAddress';
  }

  @override
  Future<void> logout() async {
    isAuthed = false;
    token = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeApiService implements IApiService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Repo-Wide Audit Fixes Regression Suite', () {
    group('1. Parental Controls Schedule Window Calculations', () {
      const scheduleFridayOnly = TimeSchedule(
        activeDays: {ScheduleDay.friday},
        blockHour: 22,
        blockMinute: 0,
        resumeHour: 7,
        resumeMinute: 0,
        enabled: true,
      );

      test('Friday evening inside block window (22:30)', () {
        final dt = DateTime(2026, 11, 13, 22, 30); // Friday
        expect(dt.weekday, equals(DateTime.friday));
        expect(scheduleFridayOnly.isTimeInBlockWindow(dt), isTrue);
      });

      test('Friday night before block window (21:45)', () {
        final dt = DateTime(2026, 11, 13, 21, 45); // Friday
        expect(scheduleFridayOnly.isTimeInBlockWindow(dt), isFalse);
      });

      test(
        'Friday morning outside block window when Thursday was inactive (05:15)',
        () {
          final dt = DateTime(2026, 11, 13, 5, 15); // Friday
          expect(scheduleFridayOnly.isTimeInBlockWindow(dt), isFalse);
        },
      );

      test('Friday afternoon outside block window (12:00)', () {
        final dt = DateTime(2026, 11, 13, 12, 0); // Friday
        expect(scheduleFridayOnly.isTimeInBlockWindow(dt), isFalse);
      });

      test('Saturday morning inside Friday overnight block window (05:15)', () {
        final satMorning = DateTime(2026, 11, 14, 5, 15); // Saturday
        final satNight = DateTime(2026, 11, 14, 22, 30); // Saturday
        expect(scheduleFridayOnly.isTimeInBlockWindow(satMorning), isTrue);
        expect(scheduleFridayOnly.isTimeInBlockWindow(satNight), isFalse);
      });

      test('Daytime schedule window (14:00 to 17:00)', () {
        const daytimeSchedule = TimeSchedule(
          activeDays: {ScheduleDay.wednesday},
          blockHour: 14,
          blockMinute: 0,
          resumeHour: 17,
          resumeMinute: 0,
          enabled: true,
        );

        final wedInside = DateTime(2026, 11, 11, 15, 30); // Wednesday
        final wedOutside = DateTime(2026, 11, 11, 18, 00); // Wednesday
        final thuInside = DateTime(
          2026,
          11,
          12,
          15,
          30,
        ); // Thursday (not active)
        expect(daytimeSchedule.isTimeInBlockWindow(wedInside), isTrue);
        expect(daytimeSchedule.isTimeInBlockWindow(wedOutside), isFalse);
        expect(daytimeSchedule.isTimeInBlockWindow(thuInside), isFalse);
      });

      test('24-hour block schedule (equal block and resume time)', () {
        const fullDaySchedule = TimeSchedule(
          activeDays: {ScheduleDay.sunday},
          blockHour: 0,
          blockMinute: 0,
          resumeHour: 0,
          resumeMinute: 0,
          enabled: true,
        );

        final sunNoon = DateTime(2026, 11, 15, 12, 0); // Sunday
        final monNoon = DateTime(2026, 11, 16, 12, 0); // Monday
        expect(fullDaySchedule.isTimeInBlockWindow(sunNoon), isTrue);
        expect(fullDaySchedule.isTimeInBlockWindow(monNoon), isFalse);
      });
    });

    group('2. System Metrics Load Average Parsing', () {
      test('Parses Linux kernel 16-bit fixed point load averages', () {
        final sysInfo = {
          'uptime': 123456,
          'memory': {'total': 128000000, 'free': 64000000},
          'load': [34688, 33600, 33120],
        };

        final metrics = SystemMetrics.fromSysInfo(sysInfo);
        // 34688 / 65536.0 ~= 0.5293
        expect(metrics.load1m, closeTo(0.529, 0.005));
        // 33600 / 65536.0 ~= 0.5127
        expect(metrics.load5m, closeTo(0.512, 0.005));
        // 33120 / 65536.0 ~= 0.5053
        expect(metrics.load15m, closeTo(0.505, 0.005));
      });

      test('Does NOT erroneously downscale real high float loads (>10.0)', () {
        final sysInfo = {
          'uptime': 50000,
          'memory': {'total': 1000000, 'free': 500000},
          'load': [12.5, 10.2, 8.4],
        };

        final metrics = SystemMetrics.fromSysInfo(sysInfo);
        expect(metrics.load1m, equals(12.5));
        expect(metrics.load5m, equals(10.2));
        expect(metrics.load15m, equals(8.4));
      });

      test('Parses string decimal load averages accurately', () {
        final sysInfo = {
          'uptime': 50000,
          'memory': {'total': 1000000, 'free': 500000},
          'load': ['0.45', '0.35', '0.25'],
        };

        final metrics = SystemMetrics.fromSysInfo(sysInfo);
        expect(metrics.load1m, closeTo(0.45, 0.001));
        expect(metrics.load5m, closeTo(0.35, 0.001));
        expect(metrics.load15m, closeTo(0.25, 0.001));
      });
    });

    group('3. Dashboard Controller Interface Device Resolution', () {
      test('Resolves interface names safely from dynamic Map interfaceDump', () {
        final controller = DashboardController(
          apiServiceRef: () => null,
          authServiceRef: () => null,
          routerServiceRef: () => null,
          secureStorageServiceRef: () => SecureStorageService(),
          throughputControllerRef: () => null,
          dashboardPreferencesRef: () => DashboardPreferences(),
          reviewerModeRef: () => false,
          tryAutoLogin:
              ({bool force = false, bool fetchDashboard = true}) async => false,
          fetchPublicIps: () async {},
          setPublicIps: (v4, v6) {},
          setConnectionStatus: (status) {},
          startThroughputTimer: () {},
          processDhcpLeases: (raw) => raw,
          notifyListeners: () {},
        );

        // Dynamic map with dynamic keys/values (not strictly Map<String, dynamic>)
        final dynamic dynamicDump = <dynamic, dynamic>{
          'interface': <dynamic>[
            <dynamic, dynamic>{
              'interface': 'lan',
              'l3_device': 'br-lan',
              'device': 'eth1',
            },
            <dynamic, dynamic>{
              'interface': 'wan',
              'l3_device': 'eth0',
              'device': 'eth0',
            },
            <dynamic, dynamic>{'interface': 'guest', 'device': 'wlan0-1'},
          ],
        };

        controller.setDashboardDataForTesting({'interfaceDump': dynamicDump});

        expect(controller.getDeviceNameForInterface('lan'), equals('br-lan'));
        expect(controller.getDeviceNameForInterface('wan'), equals('eth0'));
        expect(
          controller.getDeviceNameForInterface('guest'),
          equals('wlan0-1'),
        );
      });
    });

    group('4. Multi-Router Credential Isolation in Session Controller', () {
      test(
        'tryAutoLogin uses selected router credentials instead of empty values',
        () async {
          final router1 = model.Router(
            id: 'r1',
            ipAddress: '192.168.1.1',
            username: 'root',
            password: 'Password1',
            useHttps: false,
          );
          final router2 = model.Router(
            id: 'r2',
            ipAddress: '10.0.0.1',
            username: 'admin',
            password: 'Password2',
            useHttps: true,
          );

          final fakeRouterService = FakeRouterService(
            initialRouters: [router1, router2],
          );
          final fakeAuthService = FakeAuthService();
          final fakeApiService = FakeApiService();

          final sessionController = SessionController(
            initialReviewerMode: false,
            apiServiceRef: () => fakeApiService,
            authServiceRef: () => fakeAuthService,
            routerServiceRef: () => fakeRouterService,
            secureStorageServiceRef: () => SecureStorageService(),
            httpClientManagerRef: () => HttpClientManager(),
            dashboardControllerRef: () => null,
            cancelThroughputTimer: () {},
            startThroughputTimer: () {},
            fetchDashboardData: ({bool force = false}) async {},
            initializeServices: () {},
            setLoadingState: (_) {},
            setErrorState: (_) {},
            notifyListeners: () {},
          );

          // Router 1 selected initially
          await sessionController.tryAutoLogin();
          expect(fakeAuthService.lastPassedIp, equals('192.168.1.1'));
          expect(fakeAuthService.lastPassedUser, equals('root'));
          expect(fakeAuthService.lastPassedPass, equals('Password1'));
          expect(fakeAuthService.lastPassedHttps, isFalse);

          // Now select Router 2
          await fakeRouterService.selectRouter('r2');
          await sessionController.tryAutoLogin(force: true);

          // Credential bleed prevented: Router 2's specific credentials used
          expect(fakeAuthService.lastPassedIp, equals('10.0.0.1'));
          expect(fakeAuthService.lastPassedUser, equals('admin'));
          expect(fakeAuthService.lastPassedPass, equals('Password2'));
          expect(fakeAuthService.lastPassedHttps, isTrue);
        },
      );
    });
  });
}
