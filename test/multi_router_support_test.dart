// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/modules/parental_controls/models/parental_controls_store.dart';
import 'package:yet_another_luci_app/modules/parental_controls/models/parental_profile.dart';
import 'package:yet_another_luci_app/services/router_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RouterService Multi-Router Support Tests', () {
    late RouterService routerService;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      routerService = RouterService();
    });

    test(
      'Adding multiple routers maintains full list without overwriting',
      () async {
        await routerService.loadRouters();
        expect(routerService.routers, isEmpty);
        expect(routerService.selectedRouter, isNull);

        final router1 = model.Router(
          id: RouterService.generateId('192.168.1.1', 'root', false),
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'Qwerty@1234',
          useHttps: false,
          name: 'Lab Router',
          lastKnownHostname: 'OpenWrt-Lab',
        );

        final router2 = model.Router(
          id: RouterService.generateId('10.0.0.1', 'root', false),
          ipAddress: '10.0.0.1',
          username: 'root',
          password: 'Tuhin@#2003',
          useHttps: false,
          name: 'ISP Gateway',
          lastKnownHostname: 'OpenWrt-Live',
        );

        // Add router 1
        await routerService.addRouter(router1);
        expect(routerService.routers.length, 1);
        expect(routerService.selectedRouter?.id, router1.id);
        expect(routerService.selectedRouter?.name, 'Lab Router');

        // Add router 2 (newly added router becomes selected)
        await routerService.addRouter(router2);
        expect(routerService.routers.length, 2);
        expect(routerService.selectedRouter?.id, router2.id);

        // Select router 1 back
        final selected = await routerService.selectRouter(router1.id);
        expect(selected, isNotNull);
        expect(routerService.selectedRouter?.id, router1.id);
        expect(routerService.selectedRouter?.ipAddress, '192.168.1.1');

        // Re-load from storage via a new RouterService instance to verify persistence
        final newService = RouterService();
        await newService.loadRouters();
        expect(newService.routers.length, 2);
        expect(newService.selectedRouter?.id, router1.id);
        expect(newService.routers.any((r) => r.id == router1.id), isTrue);
        expect(newService.routers.any((r) => r.id == router2.id), isTrue);
      },
    );

    test('Updating a router preserves other routers in the list', () async {
      final router1 = model.Router(
        id: RouterService.generateId('192.168.1.1', 'root', false),
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'password1',
        useHttps: false,
        lastKnownHostname: 'RouterA',
      );

      final router2 = model.Router(
        id: RouterService.generateId('192.168.2.1', 'admin', true),
        ipAddress: '192.168.2.1',
        username: 'admin',
        password: 'password2',
        useHttps: true,
        lastKnownHostname: 'RouterB',
      );

      await routerService.addRouter(router1);
      await routerService.addRouter(router2);
      expect(routerService.routers.length, 2);

      // Update router 1's hostname and custom name
      final updatedRouter1 = router1.copyWith(
        name: 'Home Office Router',
        lastKnownHostname: 'OpenWrt-Office',
      );
      await routerService.updateRouter(updatedRouter1);

      expect(routerService.routers.length, 2);
      final r1 = routerService.routers.firstWhere((r) => r.id == router1.id);
      final r2 = routerService.routers.firstWhere((r) => r.id == router2.id);

      expect(r1.name, 'Home Office Router');
      expect(r1.lastKnownHostname, 'OpenWrt-Office');
      expect(r2.name, isNull);
      expect(r2.lastKnownHostname, 'RouterB');
      expect(r2.username, 'admin');
    });

    test(
      'Removing a selected router falls back to another available router',
      () async {
        final router1 = model.Router(
          id: 'router1',
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'pw1',
          useHttps: false,
        );
        final router2 = model.Router(
          id: 'router2',
          ipAddress: '10.0.0.1',
          username: 'root',
          password: 'pw2',
          useHttps: false,
        );

        await routerService.addRouter(router1);
        await routerService.addRouter(router2);
        await routerService.selectRouter(router1.id);
        expect(routerService.selectedRouter?.id, 'router1');

        // Remove the currently selected router
        await routerService.removeRouter(router1.id);
        expect(routerService.routers.length, 1);
        expect(routerService.selectedRouter?.id, 'router2');

        // Remove the last remaining router
        await routerService.removeRouter(router2.id);
        expect(routerService.routers, isEmpty);
        expect(routerService.selectedRouter, isNull);
      },
    );

    test('Router displayName falls back correctly', () {
      final r1 = model.Router(
        id: '1',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: '',
        useHttps: false,
        name: 'Custom Name',
        lastKnownHostname: 'HostnameA',
      );
      expect(r1.displayName, 'Custom Name');

      final r2 = model.Router(
        id: '2',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: '',
        useHttps: false,
        name: '',
        lastKnownHostname: 'HostnameB',
      );
      expect(r2.displayName, 'HostnameB');

      final r3 = model.Router(
        id: '3',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: '',
        useHttps: false,
      );
      expect(r3.displayName, '192.168.1.1');
    });

    test('HTTPS and HTTP routers retain proper flags and IDs', () {
      final httpRouter = model.Router(
        id: RouterService.generateId('192.168.1.1', 'root', false),
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'pw',
        useHttps: false,
      );
      final httpsRouter = model.Router(
        id: RouterService.generateId('192.168.1.1', 'root', true),
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'pw',
        useHttps: true,
      );

      expect(httpRouter.id, 'http://192.168.1.1-root');
      expect(httpsRouter.id, 'https://192.168.1.1-root');
      expect(httpRouter.useHttps, isFalse);
      expect(httpsRouter.useHttps, isTrue);
    });

    test('updateRouterName sets, clears, and persists custom name', () async {
      final router = model.Router(
        id: RouterService.generateId('192.168.1.1', 'root', false),
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'pw',
        useHttps: false,
        lastKnownHostname: 'OpenWrt-Default',
      );
      await routerService.addRouter(router);
      expect(routerService.selectedRouter?.displayName, 'OpenWrt-Default');

      // Update custom name
      await routerService.updateRouterName(router.id, 'Living Room AP');
      expect(routerService.selectedRouter?.name, 'Living Room AP');
      expect(routerService.selectedRouter?.displayName, 'Living Room AP');

      // Verify persistence across service instances
      final newService = RouterService();
      await newService.loadRouters();
      expect(newService.selectedRouter?.name, 'Living Room AP');
      expect(newService.selectedRouter?.displayName, 'Living Room AP');

      // Clearing name with null restores fallback to hostname
      await routerService.updateRouterName(router.id, null);
      expect(routerService.selectedRouter?.name, isNull);
      expect(routerService.selectedRouter?.displayName, 'OpenWrt-Default');

      // Setting empty/whitespace name also treats it as null
      await routerService.updateRouterName(router.id, '   ');
      expect(routerService.selectedRouter?.name, isNull);
      expect(routerService.selectedRouter?.displayName, 'OpenWrt-Default');
    });

    test(
      'exportRoutersAsJson exports valid formatted JSON with all profiles',
      () async {
        final router1 = model.Router(
          id: RouterService.generateId('192.168.1.1', 'root', false),
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'password1',
          useHttps: false,
          name: 'Home Gateway',
          lastKnownHostname: 'OpenWrt-Main',
        );
        final router2 = model.Router(
          id: RouterService.generateId('10.0.0.1', 'admin', true),
          ipAddress: '10.0.0.1',
          username: 'admin',
          password: 'password2',
          useHttps: true,
          name: 'ISP Backup',
          lastKnownHostname: 'OpenWrt-ISP',
        );

        await routerService.addRouter(router1);
        await routerService.addRouter(router2);

        final jsonStr = routerService.exportRoutersAsJson();
        expect(jsonStr, isNotEmpty);

        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        expect(decoded['version'], 1);
        expect(decoded['app'], 'Yet Another LuCI App');
        expect(decoded['exportedAt'], isNotNull);

        final profiles = decoded['profiles'] as List<dynamic>;
        expect(profiles.length, 2);

        final p1 =
            profiles.firstWhere((p) => p['id'] == router1.id)
                as Map<String, dynamic>;
        expect(p1['ipAddress'], '192.168.1.1');
        expect(p1['username'], 'root');
        expect(p1['name'], 'Home Gateway');
        expect(p1['lastKnownHostname'], 'OpenWrt-Main');
        expect(p1['useHttps'], false);

        final p2 =
            profiles.firstWhere((p) => p['id'] == router2.id)
                as Map<String, dynamic>;
        expect(p2['ipAddress'], '10.0.0.1');
        expect(p2['username'], 'admin');
        expect(p2['name'], 'ISP Backup');
        expect(p2['lastKnownHostname'], 'OpenWrt-ISP');
        expect(p2['useHttps'], true);
      },
    );

    test(
      'createRouter preserves optional custom name and lastKnownHostname',
      () {
        final router = routerService.createRouter(
          '192.168.1.1',
          'root',
          'secret',
          false,
          name: 'Office AP',
          lastKnownHostname: 'OpenWrt-Office',
        );

        expect(router.name, 'Office AP');
        expect(router.lastKnownHostname, 'OpenWrt-Office');
        expect(router.displayName, 'Office AP');
      },
    );

    test(
      'importRoutersFromJson imports valid JSON envelope and persists profiles',
      () async {
        const jsonPayload = '''
      {
        "version": 1,
        "app": "Yet Another LuCI App",
        "exportedAt": "2026-09-08T18:00:00.000Z",
        "profiles": [
          {
            "ipAddress": "192.168.1.1",
            "username": "root",
            "password": "Qwerty@1234",
            "useHttps": false,
            "name": "Main Router",
            "lastKnownHostname": "OpenWrt-Main"
          },
          {
            "ipAddress": "10.0.0.1",
            "username": "root",
            "password": "Tuhin@#2003",
            "useHttps": false,
            "name": "ISP Router",
            "lastKnownHostname": "OpenWrt-Live"
          }
        ]
      }
      ''';

        final result = await routerService.importRoutersFromJson(jsonPayload);
        expect(result.success, isTrue);
        expect(result.importedCount, 2);
        expect(result.updatedCount, 0);
        expect(result.totalFound, 2);
        expect(routerService.routers.length, 2);
        expect(routerService.selectedRouter?.name, 'Main Router');

        // Verify persistence across service instances
        final newService = RouterService();
        await newService.loadRouters();
        expect(newService.routers.length, 2);
        expect(newService.routers.any((r) => r.name == 'Main Router'), isTrue);
        expect(newService.routers.any((r) => r.name == 'ISP Router'), isTrue);
      },
    );

    test(
      'importRoutersFromJson successfully parses payload with UTF-8 BOM prefix',
      () async {
        const jsonWithBom = '\uFEFF{"ipAddress":"192.168.1.1","username":"root","password":"pwd"}';
        final result = await routerService.importRoutersFromJson(jsonWithBom);
        expect(result.success, isTrue);
        expect(result.importedCount, 1);
        expect(routerService.routers.length, 1);
        expect(routerService.routers.first.ipAddress, '192.168.1.1');
      },
    );

    test(
      'importRoutersFromJson updates existing profiles without duplicating',
      () async {
        final initialRouter = model.Router(
          id: RouterService.generateId('192.168.1.1', 'root', false),
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'oldpassword',
          useHttps: false,
          name: 'Old Name',
        );
        await routerService.addRouter(initialRouter);
        expect(routerService.routers.length, 1);

        const jsonPayload = '''
      {
        "profiles": [
          {
            "ipAddress": "192.168.1.1",
            "username": "root",
            "password": "newpassword123",
            "useHttps": false,
            "name": "Updated Gateway"
          },
          {
            "ipAddress": "192.168.5.1",
            "username": "admin",
            "password": "secretpassword",
            "useHttps": true,
            "name": "New Secondary"
          }
        ]
      }
      ''';

        final result = await routerService.importRoutersFromJson(jsonPayload);
        expect(result.success, isTrue);
        expect(result.importedCount, 1);
        expect(result.updatedCount, 1);
        expect(result.totalFound, 2);
        expect(routerService.routers.length, 2);

        final updated = routerService.routers.firstWhere(
          (r) => r.id == initialRouter.id,
        );
        expect(updated.password, 'newpassword123');
        expect(updated.name, 'Updated Gateway');
      },
    );

    test(
      'importRoutersFromJson accepts raw array and single profile object',
      () async {
        // Test raw array
        const rawArrayPayload = '''
      [
        {
          "ipAddress": "192.168.10.1",
          "username": "root",
          "password": "pw1",
          "useHttps": false
        }
      ]
      ''';
        final arrayResult = await routerService.importRoutersFromJson(
          rawArrayPayload,
        );
        expect(arrayResult.success, isTrue);
        expect(arrayResult.importedCount, 1);
        expect(
          routerService.routers.any((r) => r.ipAddress == '192.168.10.1'),
          isTrue,
        );

        // Test single profile object
        const singleObjectPayload = '''
      {
        "ipAddress": "192.168.20.1",
        "username": "admin",
        "password": "pw2",
        "useHttps": true,
        "name": "Single Router"
      }
      ''';
        final singleResult = await routerService.importRoutersFromJson(
          singleObjectPayload,
        );
        expect(singleResult.success, isTrue);
        expect(singleResult.importedCount, 1);
        expect(
          routerService.routers.any((r) => r.ipAddress == '192.168.20.1'),
          isTrue,
        );
      },
    );

    test('importRoutersFromJson rejects malformed or invalid inputs', () async {
      // Empty input
      final emptyResult = await routerService.importRoutersFromJson('   ');
      expect(emptyResult.success, isFalse);
      expect(emptyResult.errorMessage, contains('empty'));

      // Malformed JSON syntax
      final malformedResult = await routerService.importRoutersFromJson(
        '{ not valid json }',
      );
      expect(malformedResult.success, isFalse);
      expect(malformedResult.errorMessage, contains('Invalid JSON syntax'));

      // Wrong root type (e.g. number or boolean)
      final primitiveResult = await routerService.importRoutersFromJson('42');
      expect(primitiveResult.success, isFalse);
      expect(
        primitiveResult.errorMessage,
        contains('Root element must be a JSON object or array'),
      );

      // Empty profiles list
      final emptyProfilesResult = await routerService.importRoutersFromJson(
        '{"profiles": []}',
      );
      expect(emptyProfilesResult.success, isFalse);
      expect(
        emptyProfilesResult.errorMessage,
        contains('No router profiles found'),
      );

      // Missing required ipAddress
      final missingIpResult = await routerService.importRoutersFromJson('''
      [
        {"username": "root", "password": "123"}
      ]
      ''');
      expect(missingIpResult.success, isFalse);
      expect(missingIpResult.errorMessage, contains('No valid profiles found'));

      // Missing required username
      final missingUserResult = await routerService.importRoutersFromJson('''
      [
        {"ipAddress": "192.168.1.1", "password": "123"}
      ]
      ''');
      expect(missingUserResult.success, isFalse);
      expect(
        missingUserResult.errorMessage,
        contains('No valid profiles found'),
      );

      // Invalid hostname with illegal characters/spaces
      final invalidHostResult = await routerService.importRoutersFromJson('''
      [
        {"ipAddress": "192.168. 1.1 with spaces", "username": "root"}
      ]
      ''');
      expect(invalidHostResult.success, isFalse);
      expect(
        invalidHostResult.errorMessage,
        contains('No valid profiles found'),
      );
    });
  });

  group('ParentalControls Router-Scoped Persistence and Isolation Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      ParentalControlsStore.instance.loadFromString(null);
    });

    test('Store reset clears all in-memory state on null input', () {
      final store = ParentalControlsStore.instance;
      store.addProfile(
        const ParentalProfile(
          id: 'p1',
          name: 'Kid Profile',
          icon: '👶',
          color: '#3B82F6',
          macAddresses: ['AA:BB:CC:DD:EE:FF'],
        ),
      );
      expect(store.profiles.length, 1);

      // Switching router with no stored state cleanly resets in-memory data
      store.loadFromString(null);
      expect(store.profiles, isEmpty);
      expect(store.activityLog, isEmpty);
      expect(store.dailyMinutesUsed, isEmpty);
    });

    test(
      'Profile store preserves separate profile states across router configurations',
      () {
        final store = ParentalControlsStore.instance;

        // Configure Router 1 profile
        store.addProfile(
          const ParentalProfile(
            id: 'profile_router1',
            name: 'Router 1 Kid Phone',
            icon: '📱',
            color: '#EF4444',
            macAddresses: ['11:22:33:44:55:66'],
          ),
        );
        final router1Serialized = store.toJsonString();
        expect(router1Serialized, contains('Router 1 Kid Phone'));

        // Switch router to Router 2 (empty state)
        store.loadFromString(null);
        expect(store.profiles, isEmpty);

        // Configure Router 2 profile
        store.addProfile(
          const ParentalProfile(
            id: 'profile_router2',
            name: 'Router 2 Tablet',
            icon: '💻',
            color: '#10B981',
            macAddresses: ['AA:BB:CC:DD:EE:00'],
          ),
        );
        final router2Serialized = store.toJsonString();
        expect(router2Serialized, contains('Router 2 Tablet'));
        expect(router2Serialized, isNot(contains('Router 1 Kid Phone')));

        // Switch back to Router 1
        store.loadFromString(router1Serialized);
        expect(store.profiles.length, 1);
        expect(store.profiles.first.id, 'profile_router1');
        expect(store.profiles.first.name, 'Router 1 Kid Phone');
      },
    );
  });
}
