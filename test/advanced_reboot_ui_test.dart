// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/modules/advanced_reboot/controllers/advanced_reboot_controller.dart';
import 'package:yet_another_luci_app/modules/advanced_reboot/models/reboot_capability.dart';
import 'package:yet_another_luci_app/modules/advanced_reboot/models/reboot_state.dart';
import 'package:yet_another_luci_app/modules/advanced_reboot/screens/advanced_reboot_screen.dart';
import 'package:yet_another_luci_app/modules/advanced_reboot/services/advanced_reboot_coordinator.dart';
import 'package:yet_another_luci_app/modules/advanced_reboot/services/advanced_reboot_detector.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/screens/more_screen.dart';
import 'package:yet_another_luci_app/modules/built_in_modules.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockAdvancedRebootController extends AdvancedRebootController {
  bool detectCalled = false;
  RebootOperationType? executedOp;
  String? executedTargetSlot;

  MockAdvancedRebootController(AdvancedRebootState initialState)
    : super(
        ref: _DummyRef(),
        detector: AdvancedRebootDetector(apiService: MockApiService()),
        coordinator: AdvancedRebootCoordinator(apiService: MockApiService()),
      ) {
    state = initialState;
  }

  @override
  Future<void> detectCapabilities() async {
    detectCalled = true;
  }

  @override
  Future<void> executeOperation(
    RebootOperationType operation, {
    String? targetSlot,
  }) async {
    executedOp = operation;
    executedTargetSlot = targetSlot;
  }
}

class _DummyRef implements Ref {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  Widget buildTestApp({
    required MockAdvancedRebootController controller,
    ThemeMode themeMode = ThemeMode.light,
    Locale locale = const Locale('en'),
  }) {
    return ProviderScope(
      overrides: [
        advancedRebootControllerProvider.overrideWith((ref) => controller),
      ],
      child: MaterialApp(
        locale: locale,
        themeMode: themeMode,
        theme: ThemeData.light(useMaterial3: true),
        darkTheme: ThemeData.dark(useMaterial3: true),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AdvancedRebootScreen(),
      ),
    );
  }

  group('AdvancedRebootScreen UI Tests', () {
    testWidgets('Displays loading indicator while detecting initially', (
      tester,
    ) async {
      final controller = MockAdvancedRebootController(
        const AdvancedRebootState(isDetecting: true, capabilities: null),
      );

      await tester.pumpWidget(buildTestApp(controller: controller));
      expect(find.text('Analyzing Boot Environment'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
    });

    testWidgets('Renders verified dual-partition router with Slot 2 button', (
      tester,
    ) async {
      final supportedCaps = AdvancedRebootCapabilities(
        routerId: 'router_ea8300',
        detectedAt: DateTime.now(),
        environment: const DeviceBootEnvironment(
          boardName: 'linksys,ea8300',
          model: 'Linksys EA8300',
          releaseVersion: '23.05.3',
          targetArchitecture: 'ipq40xx/generic',
          activeSlot: '1',
          alternateSlot: '2',
        ),
        matchedProfileId: 'linksys_ea8300',
        capabilities: {
          RebootOperationType.standardReboot: const OperationCapability(
            operation: RebootOperationType.standardReboot,
            status: CapabilityStatus.supported,
            reason: 'Standard reboot supported',
          ),
          RebootOperationType.alternatePartitionBoot: const OperationCapability(
            operation: RebootOperationType.alternatePartitionBoot,
            status: CapabilityStatus.supported,
            reason: 'Verified dual-boot profile Linksys EA8300.',
            targetIdentifier: '2',
            riskLevel: RiskLevel.high,
          ),
          RebootOperationType.powerOff: const OperationCapability(
            operation: RebootOperationType.powerOff,
            status: CapabilityStatus.unsupported,
            reason: 'Hardware DC power-down is not supported on this platform.',
          ),
        },
      );

      final controller = MockAdvancedRebootController(
        AdvancedRebootState(capabilities: supportedCaps),
      );

      await tester.pumpWidget(buildTestApp(controller: controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Environment Card
      expect(find.text('Linksys EA8300'), findsWidgets);
      expect(find.text('Native Dual-Boot'), findsOneWidget);
      expect(find.text('Slot 1'), findsOneWidget);
      expect(find.text('Slot 2'), findsOneWidget);

      // Operations
      expect(find.text('Standard System Reboot'), findsOneWidget);
      expect(find.text('Alternate Firmware Partition'), findsOneWidget);
      expect(find.text('Reboot to Slot 2'), findsOneWidget);
      expect(find.text('Power Off Router'), findsOneWidget);
    });

    testWidgets('Tapping Standard Reboot button opens confirmation dialog', (
      tester,
    ) async {
      final supportedCaps = AdvancedRebootCapabilities(
        routerId: 'router_ea8300',
        detectedAt: DateTime.now(),
        environment: const DeviceBootEnvironment(
          boardName: 'linksys,ea8300',
          model: 'Linksys EA8300',
          releaseVersion: '23.05.3',
        ),
        capabilities: {
          RebootOperationType.standardReboot: const OperationCapability(
            operation: RebootOperationType.standardReboot,
            status: CapabilityStatus.supported,
            reason: 'Standard reboot supported',
          ),
        },
      );

      final controller = MockAdvancedRebootController(
        AdvancedRebootState(capabilities: supportedCaps),
      );

      await tester.pumpWidget(buildTestApp(controller: controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final rebootBtn = find.text('Reboot Router');
      expect(rebootBtn, findsOneWidget);

      await tester.tap(rebootBtn);
      await tester.pumpAndSettle();

      // Verify dialog is presented
      expect(find.text('Reboot Router?'), findsOneWidget);
      expect(find.text('Reboot'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Confirm
      await tester.tap(find.text('Reboot'));
      await tester.pumpAndSettle();

      expect(controller.executedOp, equals(RebootOperationType.standardReboot));
    });

    testWidgets(
      'Tapping Alternate Partition button opens confirmation dialog with Slot 2',
      (tester) async {
        final supportedCaps = AdvancedRebootCapabilities(
          routerId: 'router_ea8300',
          detectedAt: DateTime.now(),
          environment: const DeviceBootEnvironment(
            boardName: 'linksys,ea8300',
            model: 'Linksys EA8300',
            releaseVersion: '23.05.3',
            activeSlot: '1',
            alternateSlot: '2',
          ),
          matchedProfileId: 'linksys_ea8300',
          capabilities: {
            RebootOperationType.alternatePartitionBoot:
                const OperationCapability(
                  operation: RebootOperationType.alternatePartitionBoot,
                  status: CapabilityStatus.supported,
                  reason: 'Verified dual-boot profile Linksys EA8300.',
                  targetIdentifier: '2',
                  riskLevel: RiskLevel.high,
                ),
          },
        );

        final controller = MockAdvancedRebootController(
          AdvancedRebootState(capabilities: supportedCaps),
        );

        await tester.pumpWidget(buildTestApp(controller: controller));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final switchBtn = find.text('Reboot to Slot 2');
        expect(switchBtn, findsOneWidget);

        await tester.tap(switchBtn);
        await tester.pumpAndSettle();

        // Verify confirmation dialog
        expect(find.text('Reboot into Partition Slot 2?'), findsOneWidget);
        expect(find.text('Switch to Slot 2 & Reboot'), findsOneWidget);

        // Confirm
        await tester.tap(find.text('Switch to Slot 2 & Reboot'));
        await tester.pumpAndSettle();

        expect(
          controller.executedOp,
          equals(RebootOperationType.alternatePartitionBoot),
        );
        expect(controller.executedTargetSlot, equals('2'));
      },
    );

    testWidgets(
      'Tapping diagnostics button opens sanitized diagnostics bottom sheet',
      (tester) async {
        final supportedCaps = AdvancedRebootCapabilities(
          routerId: 'router_ea8300',
          detectedAt: DateTime.now(),
          environment: const DeviceBootEnvironment(
            boardName: 'linksys,ea8300',
            model: 'Linksys EA8300',
            releaseVersion: '23.05.3',
          ),
          capabilities: {
            RebootOperationType.standardReboot: const OperationCapability(
              operation: RebootOperationType.standardReboot,
              status: CapabilityStatus.supported,
              reason: 'Standard reboot supported',
            ),
          },
        );

        final controller = MockAdvancedRebootController(
          AdvancedRebootState(capabilities: supportedCaps),
        );

        await tester.pumpWidget(buildTestApp(controller: controller));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final diagIcon = find.byIcon(Icons.description_outlined);
        expect(diagIcon, findsOneWidget);

        await tester.tap(diagIcon);
        await tester.pumpAndSettle();

        // Bottom sheet open
        expect(find.text('Boot Diagnostics'), findsOneWidget);
        expect(
          find.textContaining('YALA Advanced Reboot Diagnostics'),
          findsOneWidget,
        );

        // Verify scrollable behavior: can drag/scroll down smoothly
        await tester.drag(
          find.textContaining('YALA Advanced Reboot Diagnostics'),
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();
      },
    );

    testWidgets('Renders execution card during reconnecting state', (
      tester,
    ) async {
      final controller = MockAdvancedRebootController(
        const AdvancedRebootState(
          progress: RebootExecutionProgress(
            state: RebootExecutionState.reconnecting,
            operation: RebootOperationType.alternatePartitionBoot,
            message: 'Waiting for router to reboot...',
            pollAttempt: 3,
            maxPollAttempts: 30,
          ),
        ),
      );

      await tester.pumpWidget(buildTestApp(controller: controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Reconnecting to Router'), findsOneWidget);
      expect(find.text('Waiting for router to reboot...'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('Renders cleanly in dark theme mode without overflow', (
      tester,
    ) async {
      final supportedCaps = AdvancedRebootCapabilities(
        routerId: 'router_ea8300',
        detectedAt: DateTime.now(),
        environment: const DeviceBootEnvironment(
          boardName: 'linksys,ea8300',
          model: 'Linksys EA8300',
          releaseVersion: '23.05.3',
          activeSlot: '1',
          alternateSlot: '2',
        ),
        capabilities: {
          RebootOperationType.standardReboot: const OperationCapability(
            operation: RebootOperationType.standardReboot,
            status: CapabilityStatus.supported,
            reason: 'Standard reboot supported',
          ),
        },
      );

      final controller = MockAdvancedRebootController(
        AdvancedRebootState(capabilities: supportedCaps),
      );

      await tester.pumpWidget(
        buildTestApp(controller: controller, themeMode: ThemeMode.dark),
      );
      await tester.pumpAndSettle();

      expect(find.text('Advanced Reboot'), findsOneWidget);
      expect(find.text('Standard System Reboot'), findsOneWidget);
    });

    testWidgets('Renders active OS and alternate OS names in UI and dialog', (
      tester,
    ) async {
      final supportedCaps = AdvancedRebootCapabilities(
        routerId: 'router_ea8300',
        detectedAt: DateTime.now(),
        environment: const DeviceBootEnvironment(
          boardName: 'linksys,ea8300',
          model: 'Linksys EA8300',
          releaseVersion: 'OpenWrt 25.12.6',
          targetArchitecture: 'ipq40xx/generic',
          activeSlot: '2',
          alternateSlot: '1',
          activeOs: 'OpenWrt 25.12.6',
          alternateOs: 'Stock Firmware v1.1.4.195026',
          discoveredMechanismName: 'U-Boot (boot_part + ready)',
        ),
        capabilities: {
          RebootOperationType.standardReboot: const OperationCapability(
            operation: RebootOperationType.standardReboot,
            status: CapabilityStatus.supported,
            reason: 'Standard reboot supported',
          ),
          RebootOperationType.alternatePartitionBoot: const OperationCapability(
            operation: RebootOperationType.alternatePartitionBoot,
            status: CapabilityStatus.supported,
            reason: 'Verified dual-boot U-Boot mechanism.',
            targetIdentifier: '1',
            riskLevel: RiskLevel.high,
          ),
          RebootOperationType.powerOff: const OperationCapability(
            operation: RebootOperationType.powerOff,
            status: CapabilityStatus.unsupported,
            reason: 'Hardware DC power-down is not supported on this platform.',
          ),
        },
      );

      final controller = MockAdvancedRebootController(
        AdvancedRebootState(capabilities: supportedCaps),
      );

      await tester.pumpWidget(buildTestApp(controller: controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Mechanism badge
      expect(find.text('U-Boot (boot_part + ready)'), findsOneWidget);

      // Slot labels with OS
      expect(find.text('Slot 2 (OpenWrt 25.12.6)'), findsOneWidget);
      expect(
        find.text('Slot 1 (Stock Firmware v1.1.4.195026)'),
        findsOneWidget,
      );

      // Button with alternate OS
      expect(
        find.text('Reboot to Slot 1 (Stock Firmware v1.1.4.195026)'),
        findsOneWidget,
      );

      // Tap button and verify confirmation dialog displays alternate OS
      await tester.tap(
        find.text('Reboot to Slot 1 (Stock Firmware v1.1.4.195026)'),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Reboot into Partition Slot 1 (Stock Firmware v1.1.4.195026)?',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Stock Firmware v1.1.4.195026 on Slot 1'),
        findsOneWidget,
      );
    });

    testWidgets(
      'Renders localized strings when locale is German, Spanish, French, and Chinese',
      (tester) async {
        final supportedCaps = AdvancedRebootCapabilities(
          routerId: 'router_ea8300',
          detectedAt: DateTime.now(),
          environment: const DeviceBootEnvironment(
            boardName: 'linksys,ea8300',
            model: 'Linksys EA8300',
            releaseVersion: '23.05.3',
            activeSlot: '1',
            alternateSlot: '2',
          ),
          capabilities: {
            RebootOperationType.standardReboot: const OperationCapability(
              operation: RebootOperationType.standardReboot,
              status: CapabilityStatus.supported,
              reason: 'Standard reboot supported',
            ),
            RebootOperationType
                .alternatePartitionBoot: const OperationCapability(
              operation: RebootOperationType.alternatePartitionBoot,
              status: CapabilityStatus.supported,
              reason: 'Alternate partition ready',
              targetIdentifier: '2',
              warningMessage:
                  'You are about to switch the active boot partition to Slot 2 via U-Boot boot_part and boot_part_ready.',
            ),
            RebootOperationType.powerOff: const OperationCapability(
              operation: RebootOperationType.powerOff,
              status: CapabilityStatus.unsupported,
              reason:
                  'Hardware DC power-down is not supported on linksys,ea8300.',
            ),
          },
        );

        final controller = MockAdvancedRebootController(
          AdvancedRebootState(capabilities: supportedCaps),
        );

        // 1. German
        await tester.pumpWidget(
          buildTestApp(controller: controller, locale: const Locale('de')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Erweiterter Neustart'), findsOneWidget);
        expect(find.text('Standard-Systemneustart'), findsOneWidget);
        expect(find.text('Alternative Firmware-Partition'), findsOneWidget);
        expect(find.text('Router neu starten'), findsOneWidget);
        expect(
          find.textContaining('Dual-Partition-Boot-Mechanismus bestätigt.'),
          findsOneWidget,
        );

        // 2. Spanish
        await tester.pumpWidget(
          buildTestApp(controller: controller, locale: const Locale('es')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Reinicio avanzado'), findsOneWidget);
        expect(find.text('Reinicio estándar del sistema'), findsOneWidget);
        expect(find.text('Partición de firmware alternativa'), findsOneWidget);
        expect(find.text('Reiniciar router'), findsOneWidget);
        expect(
          find.textContaining(
            'Mecanismo de arranque de partición dual verificado.',
          ),
          findsOneWidget,
        );

        // 3. French
        await tester.pumpWidget(
          buildTestApp(controller: controller, locale: const Locale('fr')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Redémarrage avancé'), findsOneWidget);
        expect(find.text('Redémarrage système standard'), findsOneWidget);
        expect(
          find.text('Partition de micrologiciel alternative'),
          findsOneWidget,
        );
        expect(find.text('Redémarrer le routeur'), findsOneWidget);
        expect(
          find.textContaining('Mécanisme de double amorçage vérifié.'),
          findsOneWidget,
        );

        // 4. Chinese
        await tester.pumpWidget(
          buildTestApp(controller: controller, locale: const Locale('zh')),
        );
        await tester.pumpAndSettle();

        expect(find.text('高级重启'), findsOneWidget);
        expect(find.text('标准系统重启'), findsOneWidget);
        expect(find.text('备用固件分区'), findsOneWidget);
        expect(find.text('重启路由器'), findsOneWidget);
        expect(
          find.text('执行标准的 OpenWrt 操作系统重启。在所有可连接的路由器上均完全可用。'),
          findsOneWidget,
        );
        expect(
          find.text('双分区启动机制已验证。当前从槽位 1 启动，准备就绪可重启至槽位 2。'),
          findsOneWidget,
        );
        expect(find.textContaining('您即将把活动启动分区切换至槽位 2。'), findsOneWidget);
        expect(
          find.textContaining('此平台（linksys,ea8300）不支持硬件直流断电。'),
          findsOneWidget,
        );
      },
    );
  });

  group('MoreScreen Device Management & Reboot Revamp Tests', () {
    setUpAll(() {
      registerBuiltInModules();
    });

    testWidgets(
      'Device Management displays Reboot Router with compact Advanced button and no duplicate under Management Modules',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        FlutterSecureStorage.setMockInitialValues({});
        SharedPreferences.setMockInitialValues({});

        final appState = AppState.instance;
        appState.setCapabilitiesForTesting(
          RouterCapabilities(
            routerId: 'test-router',
            probedAt: DateTime.now(),
            ubusObjects: const {'system', 'uci', 'luci-rpc', 'file'},
            ubusMethods: const {
              'system': ['reboot'],
              'file': ['exec'],
              'luci-rpc': ['getWirelessDevices'],
            },
          ),
        );

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: MoreScreen())),
        );
        await tester.pumpAndSettle();

        // 1. Device Management section contains "Reboot Router" and "Advanced" button
        expect(find.text('DEVICE MANAGEMENT'), findsOneWidget);
        expect(find.text('Reboot Router'), findsOneWidget);
        expect(find.text('Advanced'), findsOneWidget);

        // 2. "Advanced Reboot" is NOT duplicated as a tile under Management Modules
        expect(find.text('Advanced Reboot'), findsNothing);

        // 3. Tapping the "Reboot Router" tile opens the simple reboot dialog (original simple prompt)
        await tester.tap(find.text('Reboot Router'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Reboot Router?'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Reboot'), findsOneWidget);
        expect(find.text('Advanced Options'), findsNothing);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      },
    );

    testWidgets(
      'Tapping the compact Advanced button on MoreScreen directly opens AdvancedRebootScreen',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        FlutterSecureStorage.setMockInitialValues({});
        SharedPreferences.setMockInitialValues({});

        final appState = AppState.instance;
        appState.setCapabilitiesForTesting(
          RouterCapabilities(
            routerId: 'test-router',
            probedAt: DateTime.now(),
            ubusObjects: const {'system', 'uci', 'luci-rpc', 'file'},
            ubusMethods: const {
              'system': ['reboot'],
              'file': ['exec'],
              'luci-rpc': ['getWirelessDevices'],
            },
          ),
        );

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: MoreScreen())),
        );
        await tester.pumpAndSettle();

        // Tap the "Advanced" tonal pill button directly
        await tester.tap(find.text('Advanced'));
        await tester.pumpAndSettle();

        expect(find.byType(AdvancedRebootScreen), findsOneWidget);
      },
    );
  });
}
