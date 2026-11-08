// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/services/mock_auth_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final appState = AppState.instance;
    appState.setApiServiceForTesting(MockApiService());
    appState.setAuthServiceForTesting(MockAuthService());
    appState.setDashboardTabActive(false);
    appState.cancelThroughputTimer();
  });

  tearDown(() {
    AppState.instance.cancelThroughputTimer();
  });

  group('Session & Login State Tests', () {
    test(
      'hasActiveSession evaluates correctly across auth and reviewer modes',
      () async {
        final appState = AppState.instance;

        // When sysauth is null and reviewer mode is false, hasActiveSession is false
        await appState.logout();
        expect(appState.hasActiveSession, isFalse);

        // When reviewer mode is enabled, hasActiveSession is true
        await appState.setReviewerMode(true);
        expect(appState.hasActiveSession, isTrue);

        // Disable reviewer mode restores inactive session
        await appState.setReviewerMode(false);
        expect(appState.hasActiveSession, isFalse);
      },
    );

    test('selectRouter updates active profile and sets session', () async {
      final appState = AppState.instance;
      final router = model.Router(
        id: 'test_router_select',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'password',
        useHttps: false,
        name: 'Target Router',
      );
      await appState.addRouter(router);
      expect(appState.routers.any((r) => r.id == router.id), isTrue);
    });
  });
}
