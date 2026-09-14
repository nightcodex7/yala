// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/modules/wireless_management/models/wireless_info.dart';
import 'package:yet_another_luci_app/modules/wireless_management/widgets/edit_ssid_dialog.dart';
import 'package:yet_another_luci_app/modules/wireless_management/widgets/add_ssid_dialog.dart';

Future<void> pumpFrames(
  WidgetTester tester, {
  int count = 10,
  Duration duration = const Duration(milliseconds: 50),
}) async {
  for (int i = 0; i < count; i++) {
    await tester.pump(duration);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  final mockRadio = WirelessRadio(
    name: 'radio0',
    isUp: true,
    channel: '6',
    country: 'US',
    interfaces: [
      const WirelessInterface(
        ifName: 'wlan0',
        sectionName: 'cfg0',
        ssid: 'Home_WiFi',
        mode: 'ap',
        encryption: 'psk2',
        securityMode: WifiSecurityMode.wpa2Psk,
        pmfState: PmfState.disabled,
        channel: '6',
        isEnabled: true,
        stations: [],
        key: 'MySecretPassword123',
      ),
    ],
  );

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          if (methodCall.method == 'readAll') {
            return <String, String>{'reviewer_mode_enabled': 'true'};
          }
          if (methodCall.method == 'read') {
            return methodCall.arguments['key'] == 'reviewer_mode_enabled'
                ? 'true'
                : null;
          }
          return null;
        });
  });

  setUp(() async {
    await AppState.instance.setReviewerMode(true);
  });

  group('EditSsidDialog Context Awareness Tests', () {
    testWidgets(
      'Save button is disabled initially and enables when SSID changes',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: EditSsidDialog(
                  radio: mockRadio,
                  interface: mockRadio.interfaces.first,
                ),
              ),
            ),
          ),
        );

        await pumpFrames(tester);

        final saveBtnFinder = find.widgetWithText(
          ElevatedButton,
          'Save & Apply',
        );
        expect(saveBtnFinder, findsOneWidget);

        final initialButton = tester.widget<ElevatedButton>(saveBtnFinder);
        expect(
          initialButton.onPressed,
          isNull,
          reason: 'Button should be disabled when baseline equals current form',
        );

        // Change SSID text
        final ssidFieldFinder = find.byType(TextFormField).first;
        await tester.enterText(ssidFieldFinder, 'Home_WiFi_Renamed');
        await pumpFrames(tester);

        final updatedButton = tester.widget<ElevatedButton>(saveBtnFinder);
        expect(
          updatedButton.onPressed,
          isNotNull,
          reason: 'Button should be enabled when SSID is modified',
        );

        // Revert SSID text back to initial baseline
        await tester.enterText(ssidFieldFinder, 'Home_WiFi');
        await pumpFrames(tester);

        final revertedButton = tester.widget<ElevatedButton>(saveBtnFinder);
        expect(
          revertedButton.onPressed,
          isNull,
          reason: 'Button should be disabled again when changes are reverted',
        );
      },
    );
  });

  group('AddSsidDialog Context Awareness Tests', () {
    testWidgets(
      'Create SSID button is disabled until required fields are filled',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: AddSsidDialog(
                  radios: [mockRadio],
                  targetRadio: mockRadio,
                ),
              ),
            ),
          ),
        );

        await pumpFrames(tester);

        final createBtnFinder = find.widgetWithText(
          ElevatedButton,
          'Create New SSID',
        );
        expect(createBtnFinder, findsOneWidget);

        // Initially empty SSID, button should be disabled
        final initialButton = tester.widget<ElevatedButton>(createBtnFinder);
        expect(
          initialButton.onPressed,
          isNull,
          reason: 'Button should be disabled when SSID is empty',
        );

        // Enter valid SSID and Passphrase
        final textFields = find.byType(TextFormField);
        final ssidField = textFields.at(0);
        final passField = textFields.at(1);

        await tester.enterText(ssidField, 'Guest_Network');
        await tester.enterText(passField, 'ValidPassphrase123');
        await pumpFrames(tester);

        final enabledButton = tester.widget<ElevatedButton>(createBtnFinder);
        expect(
          enabledButton.onPressed,
          isNotNull,
          reason: 'Button should be enabled when mandatory fields are valid',
        );
      },
    );
  });
}
