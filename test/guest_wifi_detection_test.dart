// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/wireless_management/models/wireless_info.dart';

void main() {
  group('Guest Wi-Fi Auto-Detection Heuristics & Exclusions', () {
    test('Auto-detects custom SSID with TitanicGst as Guest network', () {
      const iface = WirelessInterface(
        ifName: 'wlan0-1',
        sectionName: 'wifinet1',
        ssid: 'TitanicGst',
        mode: 'AP',
        encryption: 'sae-mixed',
        securityMode: WifiSecurityMode.saeMixed,
        pmfState: PmfState.optional,
        channel: '36',
        isEnabled: true,
        networkBridge: 'br-custom',
        stations: [],
      );

      expect(iface.isGuest, isTrue);
    });

    test('Auto-detects network attached to guest bridge', () {
      const iface = WirelessInterface(
        ifName: 'wlan1',
        sectionName: 'wifinet0',
        ssid: 'MyHome',
        mode: 'AP',
        encryption: 'psk2',
        securityMode: WifiSecurityMode.wpa2Psk,
        pmfState: PmfState.disabled,
        channel: '6',
        isEnabled: true,
        networkBridge: 'guest',
        stations: [],
      );

      expect(iface.isGuest, isTrue);
    });

    test('Auto-detects client isolated non-LAN interface as Guest network', () {
      const iface = WirelessInterface(
        ifName: 'wlan0-2',
        sectionName: 'wifinet2',
        ssid: 'IsolatedAccess',
        mode: 'AP',
        encryption: 'psk2',
        securityMode: WifiSecurityMode.wpa2Psk,
        pmfState: PmfState.disabled,
        channel: '11',
        isEnabled: true,
        isolateClients: true,
        networkBridge: 'opt_net',
        stations: [],
      );

      expect(iface.isGuest, isTrue);
    });

    test('Identifies standard LAN AP as non-guest network', () {
      const iface = WirelessInterface(
        ifName: 'wlan0',
        sectionName: 'wifinet0',
        ssid: 'HomeNetwork',
        mode: 'AP',
        encryption: 'psk2',
        securityMode: WifiSecurityMode.wpa2Psk,
        pmfState: PmfState.disabled,
        channel: '6',
        isEnabled: true,
        networkBridge: 'lan',
        stations: [],
      );

      expect(iface.isGuest, isFalse);
    });

    test('Manual guest section override flags interface as Guest network', () {
      const iface = WirelessInterface(
        ifName: 'wlan0-3',
        sectionName: 'custom_section_abc',
        ssid: 'PrivateOffice',
        mode: 'AP',
        encryption: 'psk2',
        securityMode: WifiSecurityMode.wpa2Psk,
        pmfState: PmfState.disabled,
        channel: '6',
        isEnabled: true,
        networkBridge: 'lan',
        stations: [],
      );

      expect(iface.isGuest, isFalse);
      expect(iface.isGuestInterface({'custom_section_abc'}), isTrue);
    });

    test(
      'Excluding a falsely-detected guest SSID overrides heuristics and forces standard network',
      () {
        const iface = WirelessInterface(
          ifName: 'wlan0-1',
          sectionName: 'wifinet1',
          ssid: 'VisitorCenter_Staff',
          mode: 'AP',
          encryption: 'psk2',
          securityMode: WifiSecurityMode.wpa2Psk,
          pmfState: PmfState.optional,
          channel: '36',
          isEnabled: true,
          networkBridge: 'br-custom',
          stations: [],
        );

        // Heuristic auto-detects 'visit' in SSID as Guest
        expect(iface.isGuest, isTrue);

        // User explicit exclusion overrides heuristic
        expect(iface.isGuestInterface(null, {'wifinet1'}), isFalse);
      },
    );
  });
}
