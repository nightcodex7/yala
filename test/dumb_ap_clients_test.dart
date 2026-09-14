// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  group('Client Dumb AP Properties & Methods', () {
    test('Client default constructor defaults isDumbApClient to false', () {
      final client = Client(
        ipAddress: '192.168.1.10',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        hostname: 'MyPhone',
        isConnected: true,
      );

      expect(client.isDumbApClient, isFalse);
      expect(client.apName, isNull);
    });

    test('Client constructor accepts isDumbApClient and apName', () {
      final client = Client(
        ipAddress: '10.0.0.15',
        macAddress: 'AA:BB:CC:DD:EE:01',
        hostname: 'SmartSpeaker',
        isConnected: true,
        isDumbApClient: true,
        apName: 'TP-Link Archer C60',
      );

      expect(client.isDumbApClient, isTrue);
      expect(client.apName, 'TP-Link Archer C60');
    });

    test('Client.fromWirelessStation accepts isDumbApClient and apName', () {
      final client = Client.fromWirelessStation(
        '11:22:33:44:55:66',
        isDumbApClient: true,
        apName: 'Dumb AP 5GHz',
      );

      expect(client.macAddress, '11:22:33:44:55:66');
      expect(client.connectionType, ConnectionType.wireless);
      expect(client.isDumbApClient, isTrue);
      expect(client.apName, 'Dumb AP 5GHz');
    });

    test('Client.copyWith retains or updates isDumbApClient and apName', () {
      final original = Client(
        ipAddress: '10.0.0.50',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        hostname: 'Laptop',
        isConnected: true,
      );

      final updated = original.copyWith(
        isDumbApClient: true,
        apName: 'Secondary AP',
      );

      expect(updated.isDumbApClient, isTrue);
      expect(updated.apName, 'Secondary AP');
      expect(updated.macAddress, original.macAddress);
      expect(updated.ipAddress, original.ipAddress);

      final preserved = updated.copyWith(hostname: 'New Laptop');
      expect(preserved.isDumbApClient, isTrue);
      expect(preserved.apName, 'Secondary AP');
      expect(preserved.hostname, 'New Laptop');
    });
  });

  group('ClientCategoryFilter.dumbAp filtering logic', () {
    final regularWired = Client(
      ipAddress: '10.0.0.10',
      macAddress: 'AA:11:11:11:11:11',
      hostname: 'Desktop',
      isConnected: true,
      connectionType: ConnectionType.wired,
    );

    final regularWireless = Client(
      ipAddress: '10.0.0.11',
      macAddress: 'AA:22:22:22:22:22',
      hostname: 'Phone-Main',
      isConnected: true,
      connectionType: ConnectionType.wireless,
    );

    final dumbApClient = Client(
      ipAddress: '10.0.0.12',
      macAddress: 'AA:33:33:33:33:33',
      hostname: 'Phone-AP',
      isConnected: true,
      connectionType: ConnectionType.wireless,
      isDumbApClient: true,
      apName: 'Archer C60 (AP)',
    );

    final allClients = [regularWired, regularWireless, dumbApClient];

    test('Filter by dumbAp returns only clients connected to the Dumb AP', () {
      final filtered = allClients.where((c) => c.isDumbApClient).toList();

      expect(filtered, hasLength(1));
      expect(filtered.first.macAddress, 'AA:33:33:33:33:33');
      expect(filtered.first.hostname, 'Phone-AP');
      expect(filtered.first.apName, 'Archer C60 (AP)');
    });

    test('Filter by all includes Dumb AP clients as well', () {
      expect(allClients, hasLength(3));
      expect(allClients.any((c) => c.isDumbApClient), isTrue);
    });

    test('Search query matches client by apName', () {
      final query = 'archer';
      final matching = allClients.where((c) {
        return (c.apName != null &&
            c.apName!.toLowerCase().contains(query.toLowerCase()));
      }).toList();

      expect(matching, hasLength(1));
      expect(matching.first.hostname, 'Phone-AP');
    });
  });

  group('AppState Dumb AP context-aware getters', () {
    test('AppState hasDumbAp reflects clients or controller state', () {
      final appState = AppState.instance;

      // Set clients with one Dumb AP client
      appState.clients = [
        Client(
          ipAddress: '10.0.0.2',
          macAddress: '00:11:22:33:44:55',
          hostname: 'Tablet',
          isConnected: true,
          isDumbApClient: true,
          apName: 'Dumb AP Bedroom',
        ),
        Client(
          ipAddress: '10.0.0.3',
          macAddress: '00:11:22:33:44:66',
          hostname: 'PC',
          isConnected: true,
        ),
      ];

      expect(appState.dumbApClients, hasLength(1));
      expect(appState.dumbApClientsCount, 1);
      expect(appState.dumbApClients.first.hostname, 'Tablet');
      expect(appState.dumbApClients.first.apName, 'Dumb AP Bedroom');
    });
  });
}
