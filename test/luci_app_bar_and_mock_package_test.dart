// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/luci_theme.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/widgets/luci_app_bar.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/modules/system_backup_upgrade/models/router_upgrade_scan.dart';
import 'package:yet_another_luci_app/modules/system_backup_upgrade/services/router_upgrade_scan_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LuciAppBar Back Button Tests', () {
    testWidgets(
      'LuciAppBar shows back button when screen is pushed onto Navigator stack',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const Scaffold(
                            appBar: LuciAppBar(title: 'Sub Screen'),
                            body: SizedBox(),
                          ),
                        ),
                      );
                    },
                    child: const Text('Push'),
                  ),
                ),
              ),
            ),
          ),
        );

        // Initially on root: no back button
        expect(find.byType(IconButton), findsNothing);

        // Tap push
        await tester.tap(find.text('Push'));
        await tester.pumpAndSettle();

        // On pushed screen: back button exists automatically
        expect(find.byType(IconButton), findsOneWidget);
        expect(find.text('Sub Screen'), findsOneWidget);

        // Tap back button
        await tester.tap(find.byType(IconButton));
        await tester.pumpAndSettle();

        // Popped back to root
        expect(find.text('Push'), findsOneWidget);
        expect(find.byType(IconButton), findsNothing);
      },
    );

    testWidgets('LuciAppBar respects explicit showBack: true even on root', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            appBar: LuciAppBar(title: 'Root With Back', showBack: true),
            body: SizedBox(),
          ),
        ),
      );

      expect(find.byType(IconButton), findsOneWidget);
    });

    testWidgets(
      'LuciAppBar respects explicit showBack: false on pushed screen',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const Scaffold(
                            appBar: LuciAppBar(
                              title: 'Sub Screen',
                              showBack: false,
                            ),
                            body: SizedBox(),
                          ),
                        ),
                      );
                    },
                    child: const Text('Push'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Push'));
        await tester.pumpAndSettle();

        expect(find.text('Sub Screen'), findsOneWidget);
        expect(find.byType(IconButton), findsNothing);
      },
    );

    testWidgets(
      'LuciAppBar defaults to centerTitle: true on Android platform',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
            home: const Scaffold(
              appBar: LuciAppBar(title: 'Android Header'),
              body: SizedBox(),
            ),
          ),
        );

        final appBar = tester.widget<AppBar>(find.byType(AppBar));
        expect(appBar.centerTitle, isTrue);
      },
    );

    testWidgets('LuciAppBar respects explicit centerTitle: false', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: const Scaffold(
            appBar: LuciAppBar(
              title: 'Left Aligned Header',
              centerTitle: false,
            ),
            body: SizedBox(),
          ),
        ),
      );

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.centerTitle, isFalse);
    });

    test(
      'LuciTheme defaults centerTitle to true in light and dark appBarTheme',
      () {
        final lightTheme = LuciTheme.buildLightTheme();
        final darkTheme = LuciTheme.buildDarkTheme();

        expect(lightTheme.appBarTheme.centerTitle, isTrue);
        expect(darkTheme.appBarTheme.centerTitle, isTrue);
      },
    );
  });

  group('MockApiService & RouterUpgradeScanService Package Engine Tests', () {
    test(
      'MockApiService reports APK engine and RouterUpgradeScanService detects only APK',
      () async {
        final mockApi = MockApiService();
        MockApiService.mockPackageEngine = PackageManagerEngine.apk;
        addTearDown(() {
          MockApiService.mockPackageEngine = PackageManagerEngine.opkg;
        });
        final scanService = RouterUpgradeScanService(
          apiService: mockApi,
          ipAddress: '192.168.1.1',
          sysauth: 'mock_token',
          useHttps: false,
        );

        final scan = await scanService.scan();

        // Package manager MUST be APK, NOT mixed ("OPKG + APK") or opkg
        expect(scan.packageManager.isKnown, isTrue);
        expect(scan.packageManager.value, equals(RouterPackageManager.apk));
        expect(
          scan.packageManager.value,
          isNot(equals(RouterPackageManager.mixed)),
        );
        expect(
          scan.packageManager.value,
          isNot(equals(RouterPackageManager.opkg)),
        );
      },
    );
  });
}
