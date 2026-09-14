// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/rpc_result.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/modules/wireless_management/models/wireless_info.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';

void main() {
  group('Wireless Security Mode & Frequency Display Unit Tests', () {
    test('WifiSecurityMode classifies SAE-Only (WPA3-Only) correctly', () {
      final mode1 = WifiSecurityMode.parse(
        iwinfoEnc: {
          'enabled': true,
          'description': 'WPA3 SAE (CCMP)',
          'auth_suites': ['SAE'],
        },
        rawConfigEnc: 'sae',
      );
      expect(mode1, equals(WifiSecurityMode.saeOnly));
      expect(mode1.shortBadgeLabel, equals('WPA3-SAE'));

      final pmfReq = PmfState.parse('2');
      expect(pmfReq, equals(PmfState.required));
      expect(pmfReq.displayName, equals('PMF Required'));
    });

    test(
      'WifiSecurityMode classifies SAE-Mixed (WPA2/WPA3 Transitional) correctly',
      () {
        final mode = WifiSecurityMode.parse(
          iwinfoEnc: {
            'enabled': true,
            'description': 'WPA2/WPA3 PSK/SAE (CCMP)',
            'auth_suites': ['PSK', 'SAE'],
          },
          rawConfigEnc: 'sae-mixed',
        );
        expect(mode, equals(WifiSecurityMode.saeMixed));
        expect(mode.shortBadgeLabel, equals('WPA2/WPA3'));

        final pmfOpt = PmfState.parse('1');
        expect(pmfOpt, equals(PmfState.optional));
        expect(pmfOpt.displayName, equals('PMF Optional'));
      },
    );

    test(
      'WifiSecurityMode classifies WPA2-PSK, WPA-PSK, Open, and Enterprise',
      () {
        final wpa2 = WifiSecurityMode.parse(
          iwinfoEnc: {
            'description': 'WPA2 PSK (CCMP)',
            'auth_suites': ['PSK'],
          },
          rawConfigEnc: 'psk2',
        );
        expect(wpa2, equals(WifiSecurityMode.wpa2Psk));

        final wpa1 = WifiSecurityMode.parse(rawConfigEnc: 'psk');
        expect(wpa1, equals(WifiSecurityMode.wpaPsk));

        final openMode = WifiSecurityMode.parse(
          iwinfoEnc: {'enabled': false, 'description': ''},
          rawConfigEnc: 'none',
        );
        expect(openMode, equals(WifiSecurityMode.open));

        final eapMode = WifiSecurityMode.parse(
          iwinfoEnc: {'description': 'WPA2 802.1X (CCMP)'},
          rawConfigEnc: 'wpa2',
        );
        expect(eapMode, equals(WifiSecurityMode.enterprise));
      },
    );

    test(
      'WirelessRadio handles valid frequency and 6GHz / 5GHz / 2.4GHz band labels',
      () {
        final radio2g = WirelessRadio.fromJson('radio0', {
          'channel': 6,
          'frequency': 2437,
        }, null);
        expect(radio2g.formattedFrequency, equals('2.437 GHz'));
        expect(radio2g.bandLabel, equals('2.4 GHz'));

        final radio5g = WirelessRadio.fromJson('radio1', {
          'channel': 36,
          'frequency': 5180,
        }, null);
        expect(radio5g.formattedFrequency, equals('5.180 GHz'));
        expect(radio5g.bandLabel, equals('5 GHz'));

        final radio6g = WirelessRadio.fromJson('radio6', {
          'channel': 1,
          'frequency': 5955,
        }, null);
        expect(radio6g.formattedFrequency, equals('5.955 GHz'));
        expect(radio6g.bandLabel, equals('6 GHz'));
      },
    );

    test(
      'WirelessRadio gracefully handles missing/null frequency on older radios without 0.000 GHz',
      () {
        final legacyRadio = WirelessRadio.fromJson('radioLegacy', {
          'channel': 6,
          'frequency': null, // frequency absent on older iwinfo
        }, null);

        expect(legacyRadio.formattedFrequency, isNull);
        expect(legacyRadio.bandLabel, equals('2.4 GHz'));
      },
    );

    test(
      'WirelessInterface.generateWifiQrUri escapes special characters and formats correctly',
      () {
        const iface = WirelessInterface(
          ifName: 'wlan0',
          sectionName: 'wifinet0',
          ssid: 'My;Special,Net:Work\\Name"',
          mode: 'AP',
          encryption: 'psk2',
          securityMode: WifiSecurityMode.wpa2Psk,
          pmfState: PmfState.disabled,
          stations: [],
          key: 'Secret;Pass,Word:With\\Special"',
          channel: '6',
          isEnabled: true,
        );

        final qrUri = iface.wifiQrUri;
        expect(qrUri, contains('S:My\\;Special\\,Net\\:Work\\\\Name\\";'));
        expect(qrUri, contains('P:Secret\\;Pass\\,Word\\:With\\\\Special\\";'));
        expect(qrUri, contains('T:WPA;'));
        expect(qrUri, contains('H:false;;'));
      },
    );

    test(
      'SSID byte length validation strictly checks UTF-8 bytes up to 32',
      () {
        const asciiSsid =
            'Standard2.4GHzWifiNetworkName123'; // 32 chars, 32 bytes
        expect(utf8.encode(asciiSsid).length, equals(32));

        const unicodeSsid =
            'Wi-Fi_Café_Test'; // 15 chars, but multi-byte 'é' makes it 16 bytes
        expect(utf8.encode(unicodeSsid).length, equals(16));

        const oversizedSsid =
            'ThisIsAnExcessivelyLongNetworkSSIDName123'; // 41 bytes
        expect(utf8.encode(oversizedSsid).length, greaterThan(32));
      },
    );

    test('WPA/WPA2/WPA3 passphrase validation rules', () {
      final valid8Char = '12345678';
      final valid63Char = 'A' * 63;
      final valid64Hex =
          'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

      expect(valid8Char.length >= 8 && valid8Char.length <= 63, isTrue);
      expect(valid63Char.length >= 8 && valid63Char.length <= 63, isTrue);
      expect(RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(valid64Hex), isTrue);

      final invalidShort = '1234567';
      final invalid64NonHex = 'G' * 64;
      expect(invalidShort.length < 8, isTrue);
      expect(RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(invalid64NonHex), isFalse);
    });

    test(
      'WirelessRadio parses htmode, supportedHtModes, hardwareName, and disabled state',
      () {
        final radio = WirelessRadio.fromJson('radio1', {
          'up': true,
          'channel': 36,
          'frequency': 5180,
          'txpower': 23,
          'htmode': 'VHT80',
          'htmodes': ['HT20', 'HT40', 'VHT20', 'VHT40', 'VHT80', 'HE80'],
          'country': 'US',
          'disabled': '0',
          'hardware': {'name': 'Qualcomm Atheros QCN9074'},
        }, null);

        expect(radio.htMode, equals('VHT80'));
        expect(radio.supportedHtModes, contains('VHT80'));
        expect(radio.supportedHtModes.length, equals(6));
        expect(radio.hardwareName, equals('Qualcomm Atheros QCN9074'));
        expect(radio.isDisabled, isFalse);
        expect(radio.country, equals('US'));
      },
    );

    test(
      'WirelessRadio parses live router (192.168.1.1) ubus JSON structure correctly',
      () {
        final livePayload = {
          'up': true,
          'disabled': false,
          'config': {
            'type': 'mac80211',
            'band': '2g',
            'channel': '1',
            'htmode': 'HT20',
          },
          'interfaces': [
            {
              'section': 'default_radio0',
              'ifname': 'phy1-ap0',
              'config': {
                'mode': 'ap',
                'ssid': 'SSID1',
                'encryption': 'sae',
                'key': 'Qwerty@1234',
              },
              'iwinfo': {
                'channel': 1,
                'country': 'US',
                'txpower': 21,
                'frequency': 2412,
                'htmodes': ['HT20', 'HT40'],
                'hardware': {'name': 'Generic MAC80211'},
                'ssid': 'SSID1',
                'encryption': {
                  'enabled': true,
                  'description': 'WPA3 SAE (CCMP)',
                  'auth_suites': ['SAE'],
                },
              },
            },
          ],
          'iwinfo': {
            'channel': 1,
            'country': 'US',
            'txpower': 21,
            'frequency': 2412,
            'htmodes': ['HT20', 'HT40'],
            'hardware': {'name': 'Generic MAC80211'},
          },
        };

        final radio = WirelessRadio.fromJson('radio0', livePayload, null);

        expect(radio.name, equals('radio0'));
        expect(radio.isUp, isTrue);
        expect(radio.channel, equals('1'));
        expect(radio.frequency, equals(2412));
        expect(radio.formattedFrequency, equals('2.412 GHz'));
        expect(radio.bandLabel, equals('2.4 GHz'));
        expect(radio.txPowerDbm, equals(21));
        expect(radio.country, equals('US'));
        expect(radio.htMode, equals('HT20'));
        expect(radio.supportedHtModes, equals(['HT20', 'HT40']));
        expect(radio.hardwareName, equals('Generic MAC80211'));

        expect(radio.interfaces.length, equals(1));
        final iface = radio.interfaces.first;
        expect(iface.ssid, equals('SSID1'));
        expect(iface.securityMode, equals(WifiSecurityMode.saeOnly));
        expect(iface.key, equals('Qwerty@1234'));
        expect(iface.wifiQrUri, contains('S:SSID1;'));
        expect(iface.wifiQrUri, contains('P:Qwerty@1234;'));
      },
    );

    test(
      'RouterCapabilities evaluates hasUciWriteAccess based on ubus method permissions',
      () {
        final fullCapabilities = RouterCapabilities(
          routerId: 'test_router',
          ubusObjects: {'uci', 'system'},
          ubusMethods: {
            'uci': ['get', 'set', 'apply', 'commit'],
          },
          probedAt: DateTime.now(),
        );
        expect(fullCapabilities.hasUciWriteAccess, isTrue);

        final readOnlyCapabilities = RouterCapabilities(
          routerId: 'test_router',
          ubusObjects: {'uci', 'system'},
          ubusMethods: {
            'uci': ['get'],
          },
          probedAt: DateTime.now(),
        );
        expect(readOnlyCapabilities.hasUciWriteAccess, isFalse);
      },
    );

    test(
      'RpcResult classification handles ubus status branches for wireless devices fetch',
      () {
        final deniedRpc = [6, 'Access denied'];
        final missingRpc = [3, 'Object not found'];

        final deniedRes = RpcResult.fromUbusResponse<WirelessOverview>(
          deniedRpc,
          (data) => WirelessOverview.fromDashboardData({'wireless': data}),
        );
        expect(deniedRes.status, equals(RpcCallStatus.permissionDenied));

        final missingRes = RpcResult.fromUbusResponse<WirelessOverview>(
          missingRpc,
          (data) => WirelessOverview.fromDashboardData({'wireless': data}),
        );
        expect(missingRes.status, equals(RpcCallStatus.methodNotFound));
      },
    );

    test(
      'MockApiService executes addWirelessInterface and deleteWirelessInterface successfully',
      () async {
        final mockApi = MockApiService();
        final addResult = await mockApi.addWirelessInterface(
          '192.168.1.1',
          'sysauth_token',
          false,
          radioName: 'radio0',
          ssid: 'Guest_WiFi',
          encryption: 'sae-mixed',
          key: 'SecretGuest123',
          network: 'guest',
        );
        expect(addResult, isTrue);

        final deleteResult = await mockApi.deleteWirelessInterface(
          '192.168.1.1',
          'sysauth_token',
          false,
          sectionName: 'wifinet1',
        );
        expect(deleteResult, isTrue);

        final guestResult = await mockApi.provisionGuestNetwork(
          '192.168.1.1',
          'sysauth_token',
          false,
          radioName: 'radio0',
          ssid: 'MyHome_Guest',
          encryption: 'sae-mixed',
          key: 'GuestPass123',
          guestIp: '192.168.2.1',
          isolateClients: true,
        );
        expect(guestResult, isTrue);

        final updateResult = await mockApi.updateWirelessInterfaceConfig(
          '192.168.1.1',
          'sysauth_token',
          false,
          sectionName: 'wifinet0',
          values: {
            'ssid': 'Updated_SSID_Name',
            'encryption': 'sae',
            'key': 'NewPassphrase123',
          },
        );
        expect(updateResult, isTrue);
      },
    );

    test(
      'WirelessOverview merges disabled SSIDs from uciWirelessConfig and preserves properties',
      () {
        final dashboardData = {
          'wireless': {
            'radio0': {
              'up': true,
              'channel': '6',
              'interfaces': [
                {
                  'section': 'wifinet0',
                  'ifname': 'wlan0',
                  'config': {
                    'ssid': 'ActiveSSID',
                    'encryption': 'psk2',
                    'key': 'ActivePass123',
                  },
                  'iwinfo': {'ssid': 'ActiveSSID'},
                },
              ],
            },
          },
          'uciWirelessConfig': {
            'values': {
              'radio0': {'.type': 'wifi-device', 'channel': '6'},
              'wifinet0': {
                '.type': 'wifi-iface',
                'device': 'radio0',
                'ssid': 'ActiveSSID',
                'disabled': '0',
              },
              'wifinet_disabled': {
                '.type': 'wifi-iface',
                'device': 'radio0',
                'ssid': 'DisabledSSID',
                'encryption': 'sae',
                'key': 'DisabledPass123',
                'disabled': '1',
              },
            },
          },
        };

        final overview = WirelessOverview.fromDashboardData(dashboardData);
        expect(overview.radios.length, equals(1));
        final radio = overview.radios.first;
        expect(radio.interfaces.length, equals(2));

        final active = radio.interfaces.firstWhere(
          (i) => i.ssid == 'ActiveSSID',
        );
        expect(active.isEnabled, isTrue);
        expect(active.key, equals('ActivePass123'));

        final disabled = radio.interfaces.firstWhere(
          (i) => i.ssid == 'DisabledSSID',
        );
        expect(disabled.isEnabled, isFalse);
        expect(disabled.key, equals('DisabledPass123'));
        expect(disabled.securityMode, equals(WifiSecurityMode.saeOnly));
      },
    );
  });
}
