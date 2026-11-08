// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/modules/json_export/json_export_screen.dart';
import 'package:yet_another_luci_app/modules/json_export/json_export_service.dart';
import 'package:yet_another_luci_app/modules/ssh_console/models/saved_ssh_command.dart';
import 'package:yet_another_luci_app/modules/ssh_console/services/saved_commands_service.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    final appState = AppState.instance;
    appState.setApiServiceForTesting(MockApiService());
    appState.setDashboardTabActive(false);
    appState.cancelThroughputTimer();
  });

  tearDown(() {
    AppState.instance.cancelThroughputTimer();
  });

  group('SavedCommandsService Import Tests', () {
    const testRouterId = 'test-router-1';
    late SavedCommandsService service;

    setUp(() {
      service = SavedCommandsService();
    });

    test('imports commands from raw JSON array', () async {
      final jsonArray = jsonEncode([
        {'name': 'Check IP', 'command': 'ip addr show'},
        {'name': 'Show Disk', 'command': 'df -h'},
      ]);

      final count = await service.importFromJson(testRouterId, jsonArray);
      expect(count, equals(2));

      final saved = await service.getAll(testRouterId);
      expect(saved.length, equals(2));
      expect(saved[0].name, equals('Check IP'));
      expect(saved[0].command, equals('ip addr show'));
      expect(saved[1].name, equals('Show Disk'));
      expect(saved[1].command, equals('df -h'));
    });

    test('imports commands from single category export JSON', () async {
      final categoryJson = jsonEncode({
        'category': 'sshSavedCommands',
        'exportedAt': DateTime.now().toIso8601String(),
        'data': [
          {'name': 'Uptime', 'command': 'uptime'},
          {'name': 'Free RAM', 'command': 'free -m'},
        ],
      });

      final count = await service.importFromJson(testRouterId, categoryJson);
      expect(count, equals(2));

      final saved = await service.getAll(testRouterId);
      expect(saved.length, equals(2));
      expect(saved.any((c) => c.name == 'Uptime'), isTrue);
    });

    test('imports commands from full config export JSON manifest', () async {
      final fullConfigJson = jsonEncode({
        'manifestVersion': 1,
        'categories': {
          'sshSavedCommands': {
            'data': [
              {'name': 'Logread', 'command': 'logread -f'},
            ],
          },
          'firewall': {'data': []},
        },
      });

      final count = await service.importFromJson(testRouterId, fullConfigJson);
      expect(count, equals(1));

      final saved = await service.getAll(testRouterId);
      expect(saved.length, equals(1));
      expect(saved.first.name, equals('Logread'));
      expect(saved.first.command, equals('logread -f'));
    });

    test('handles invalid JSON and empty strings gracefully', () async {
      expect(await service.importFromJson(testRouterId, ''), equals(0));
      expect(
        await service.importFromJson(testRouterId, 'not a json'),
        equals(0),
      );
      expect(await service.importFromJson(testRouterId, '{}'), equals(0));
      expect(
        await service.importFromJson(testRouterId, '{"data": []}'),
        equals(0),
      );
    });

    test('deduplicates existing commands by name and command text', () async {
      final firstBatch = jsonEncode([
        {'name': 'Reboot', 'command': 'reboot'},
      ]);
      await service.importFromJson(testRouterId, firstBatch);

      final secondBatch = jsonEncode([
        {'name': 'Reboot', 'command': 'reboot'},
        {'name': 'New Cmd', 'command': 'ls -l'},
      ]);
      final count = await service.importFromJson(testRouterId, secondBatch);
      expect(count, equals(1));

      final saved = await service.getAll(testRouterId);
      expect(saved.length, equals(2));
    });

    test('caps total commands at 50', () async {
      final fiftyCommands = List.generate(
        55,
        (i) => {'name': 'Cmd $i', 'command': 'echo $i'},
      );
      final count = await service.importFromJson(
        testRouterId,
        jsonEncode(fiftyCommands),
      );
      expect(count, equals(50));

      final saved = await service.getAll(testRouterId);
      expect(saved.length, equals(50));
    });
  });

  group('ConfigExportService SSH Commands Export Tests', () {
    test(
      'exportSshSavedCommands creates valid JSON with saved commands',
      () async {
        final appState = AppState.instance;
        const routerId = 'export-router-1';
        final testRouter = model.Router(
          id: routerId,
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'password',
          useHttps: false,
          name: 'OpenWrt Router',
        );
        await appState.addRouter(testRouter);
        await appState.selectRouter(routerId);

        final service = SavedCommandsService();
        await service.save(
          routerId,
          SavedSshCommand(
            id: 'test-cmd-1',
            routerId: routerId,
            name: 'Export Test Cmd',
            command: 'cat /etc/openwrt_release',
            createdAt: DateTime.now(),
          ),
        );

        final exportResult = await ConfigExportService.exportSshSavedCommands(
          appState,
        );
        expect(exportResult.isSuccess, isTrue);
        expect(exportResult.itemCount, equals(1));

        final encodedBytes = ConfigExportService.encodeCategoryToJson(
          'sshSavedCommands',
          exportResult,
          appState,
        );
        final decoded =
            jsonDecode(utf8.decode(encodedBytes)) as Map<String, dynamic>;

        expect(decoded['exportMeta']['category'], equals('sshSavedCommands'));
        expect(decoded['status'], equals('success'));
        expect(decoded['data'], isA<List>());
        final dataList = decoded['data'] as List;
        expect(dataList.length, equals(1));
        expect(dataList[0]['name'], equals('Export Test Cmd'));
        expect(dataList[0]['command'], equals('cat /etc/openwrt_release'));
      },
    );
  });

  group('JsonExportScreen Category UI Tests', () {
    testWidgets('Displays SSH Saved Commands category card in list', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final appState = AppState.instance;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStateProvider.overrideWith((ref) => appState)],
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('en'),
            home: JsonExportScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('SSH Saved Commands'), findsOneWidget);
      expect(
        find.text('Saved SSH console commands and shortcuts'),
        findsOneWidget,
      );
    });
  });
}
