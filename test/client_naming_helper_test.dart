// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';

void main() {
  group('ClientNamingHelper Unit Tests', () {
    test('normalizes MAC address format correctly', () {
      expect(
        ClientNamingHelper.normalizeMac('d4-98-b9-1f-9f-8c'),
        equals('D4:98:B9:1F:9F:8C'),
      );
      expect(
        ClientNamingHelper.normalizeMac('D4:98:B9:1F:9F:8C'),
        equals('D4:98:B9:1F:9F:8C'),
      );
    });

    test('prioritizes static lease name over hostname and MAC address', () {
      final client = Client(
        ipAddress: '192.168.1.100',
        macAddress: 'D4:98:B9:1F:9F:8C',
        hostname: 'Galaxy-S21',
        staticLeaseName: 'John-Personal-Phone',
        isStaticLease: true,
      );

      final resolvedName = ClientNamingHelper.getDisplayName(
        client.macAddress,
        client: client,
      );

      expect(resolvedName, equals('John-Personal-Phone'));
    });

    test('falls back to hostname when static lease name is absent', () {
      final client = Client(
        ipAddress: '192.168.1.101',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        hostname: 'Work-Laptop',
      );

      final resolvedName = ClientNamingHelper.getDisplayName(
        client.macAddress,
        client: client,
      );

      expect(resolvedName, equals('Work-Laptop'));
    });

    test(
      'falls back to MAC address when hostname and static lease name are Unknown or missing',
      () {
        final client = Client(
          ipAddress: '192.168.1.102',
          macAddress: '11:22:33:44:55:66',
          hostname: 'Unknown',
        );

        final resolvedName = ClientNamingHelper.getDisplayName(
          client.macAddress,
          client: client,
        );

        expect(resolvedName, equals('11:22:33:44:55:66'));
      },
    );

    test(
      'resolves accurate device icons based on hostname and vendor hints',
      () {
        final tvClient = Client(
          ipAddress: '10.0.0.61',
          macAddress: 'AC:5D:5C:B3:ED:7C',
          hostname: 'MITV',
        );
        expect(
          ClientNamingHelper.getDeviceIcon(tvClient),
          equals(Icons.tv_rounded),
        );

        final actvClient = Client(
          ipAddress: '10.0.0.63',
          macAddress: 'AC:5D:5C:B3:ED:7D',
          hostname: 'ncxACTv',
        );
        expect(
          ClientNamingHelper.getDeviceIcon(actvClient),
          equals(Icons.tv_rounded),
        );

        final mobileClient = Client(
          ipAddress: '10.0.0.53',
          macAddress: 'AA:BB:CC:DD:EE:11',
          hostname: 'mummyMobile',
        );
        expect(
          ClientNamingHelper.getDeviceIcon(mobileClient),
          equals(Icons.phone_android_rounded),
        );

        final socketClient = Client(
          ipAddress: '10.0.0.99',
          macAddress: 'AA:BB:CC:DD:EE:22',
          hostname: 'QuboSmartSocket-HomeGuest',
        );
        expect(
          ClientNamingHelper.getDeviceIcon(socketClient),
          equals(Icons.power_rounded),
        );

        final laptopClient = Client(
          ipAddress: '10.0.0.10',
          macAddress: 'AA:BB:CC:DD:EE:33',
          hostname: 'ncxLaptop-Eth',
        );
        expect(
          ClientNamingHelper.getDeviceIcon(laptopClient),
          equals(Icons.laptop_mac_rounded),
        );

        final routerClient = Client(
          ipAddress: '10.0.0.1',
          macAddress: 'AA:BB:CC:DD:EE:44',
          hostname: 'OpenWrt-Router',
        );
        expect(
          ClientNamingHelper.getDeviceIcon(routerClient),
          equals(Icons.router_rounded),
        );

        final watchClient = Client(
          ipAddress: '10.0.0.12',
          macAddress: 'AA:BB:CC:DD:EE:55',
          hostname: 'AppleWatch-Series9',
        );
        expect(
          ClientNamingHelper.getDeviceIcon(watchClient),
          equals(Icons.watch_rounded),
        );

        final glassesClient = Client(
          ipAddress: '10.0.0.15',
          macAddress: 'AA:BB:CC:DD:EE:66',
          hostname: 'RayBan-MetaSmartGlasses',
        );
        expect(
          ClientNamingHelper.getDeviceIcon(glassesClient),
          equals(Icons.view_in_ar_rounded),
        );

        final devBoardClient = Client(
          ipAddress: '10.0.0.88',
          macAddress: 'AA:BB:CC:DD:EE:77',
          hostname: 'ESP32-WROOM-DevKit',
        );
        expect(
          ClientNamingHelper.getDeviceIcon(devBoardClient),
          equals(Icons.developer_board_rounded),
        );

        final nasClient = Client(
          ipAddress: '10.0.0.200',
          macAddress: 'AA:BB:CC:DD:EE:88',
          hostname: 'Synology-DS920Plus',
        );
        expect(
          ClientNamingHelper.getDeviceIcon(nasClient),
          equals(Icons.dns_rounded),
        );

        final doorbellClient = Client(
          ipAddress: '10.0.0.91',
          macAddress: 'AA:BB:CC:DD:EE:99',
          hostname: 'Ring-VideoDoorbell-Pro',
        );
        expect(
          ClientNamingHelper.getDeviceIcon(doorbellClient),
          equals(Icons.doorbell_rounded),
        );

        final lockClient = Client(
          ipAddress: '10.0.0.92',
          macAddress: 'AA:BB:CC:DD:EE:9A',
          hostname: 'Yale-SmartDoorLock',
        );
        expect(
          ClientNamingHelper.getDeviceIcon(lockClient),
          equals(Icons.lock_rounded),
        );

        final cameraClient = Client(
          ipAddress: '10.0.0.93',
          macAddress: 'AA:BB:CC:DD:EE:9B',
          hostname: 'Reolink-CCTV-Cam',
        );
        expect(
          ClientNamingHelper.getDeviceIcon(cameraClient),
          equals(Icons.videocam_rounded),
        );

        final sensorClient = Client(
          ipAddress: '10.0.0.94',
          macAddress: 'AA:BB:CC:DD:EE:9C',
          hostname: 'Aqara-MotionSensor',
        );
        expect(
          ClientNamingHelper.getDeviceIcon(sensorClient),
          equals(Icons.sensors_rounded),
        );
      },
    );
  });
}
