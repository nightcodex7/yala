// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/network_topology.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/models/rpc_result.dart';

void main() {
  group('Network Topology & Interfaces Unit Tests', () {
    test('DsaTopologyParser correctly parses bridge-vlan sections', () {
      final mockUciNetwork = {
        'values': {
          'br0': {'.type': 'device', 'name': 'br-lan', 'type': 'bridge'},
          'vlan10': {
            '.type': 'bridge-vlan',
            'device': 'br-lan',
            'vlan': '10',
            'ports': ['lan1:u', 'lan2:u', 'lan3:t'],
          },
        },
      };

      final topology = DsaTopologyParser.parse(mockUciNetwork, null);
      expect(topology.isAvailable, isTrue);
      expect(topology.isZeroVlans, isFalse);
      expect(topology.modelType, equals(NetworkModel.dsa));
      expect(topology.vlans.length, equals(1));
      expect(topology.vlans.first.vid, equals(10));
      expect(topology.vlans.first.ports.length, equals(3));
      expect(topology.vlans.first.ports.first.name, equals('lan1'));
      expect(topology.vlans.first.ports.last.isTagged, isTrue);
    });

    test('SwconfigTopologyParser correctly parses switch_vlan sections', () {
      final mockUciNetwork = {
        'values': {
          'sw0': {'.type': 'switch', 'name': 'switch0'},
          'vlan1': {
            '.type': 'switch_vlan',
            'device': 'switch0',
            'vlan': '1',
            'ports': '1 2 3 5t',
          },
        },
      };

      final topology = SwconfigTopologyParser.parse(mockUciNetwork, null);
      expect(topology.isAvailable, isTrue);
      expect(topology.isZeroVlans, isFalse);
      expect(topology.modelType, equals(NetworkModel.swconfig));
      expect(topology.vlans.length, equals(1));
      expect(topology.vlans.first.vid, equals(1));
      expect(topology.vlans.first.ports.length, equals(4));
      expect(topology.vlans.first.ports.last.isTagged, isTrue);
    });

    test('Parser produces distinct empty states: zeroVlans vs unavailable', () {
      final validFlatNetworkUci = {
        'values': {
          'lan': {'.type': 'interface', 'device': 'br-lan'},
        },
      };
      final emptyPayloadUci = {'values': {}};

      // 1. Genuine Zero VLANs (Flat Network) state on valid config
      final zeroDsa = DsaTopologyParser.parse(validFlatNetworkUci, null);
      expect(zeroDsa.isAvailable, isTrue);
      expect(zeroDsa.isZeroVlans, isTrue);
      expect(zeroDsa.vlans, isEmpty);

      // 2. Empty payload is treated as unavailable, NOT zeroVlans
      final emptyParse = DsaTopologyParser.parse(emptyPayloadUci, null);
      expect(emptyParse.isAvailable, isFalse);
      expect(emptyParse.isZeroVlans, isFalse);

      // 3. Capability unavailable state (e.g. unknown network model / conservative fallback)
      final unavailable = NetworkTopology.unavailable(
        NetworkModel.unknown,
        'Conservative mode',
      );
      expect(unavailable.isAvailable, isFalse);
      expect(unavailable.isZeroVlans, isFalse);
      expect(unavailable.errorMessage, contains('Conservative mode'));
    });

    test(
      'WanProtocol correctly parses standard and unrecognized protocols',
      () {
        expect(WanProtocol.parse('dhcp'), equals(WanProtocol.dhcp));
        expect(WanProtocol.parse('static'), equals(WanProtocol.static));
        expect(WanProtocol.parse('pppoe'), equals(WanProtocol.pppoe));
        expect(WanProtocol.parse('map'), equals(WanProtocol.map));
        expect(WanProtocol.parse('dslite'), equals(WanProtocol.dslite));
        expect(WanProtocol.parse('6in4'), equals(WanProtocol.sixInFour));
        expect(WanProtocol.parse('wireguard'), equals(WanProtocol.wireguard));
        expect(WanProtocol.parse('openvpn'), equals(WanProtocol.openvpn));
        expect(WanProtocol.parse('ovpn'), equals(WanProtocol.openvpn));
        expect(WanProtocol.openvpn.displayName, equals('OpenVPN Tunnel'));

        // Unrecognized proto fallback test
        final unknown = WanProtocol.parse('custom_proto_xyz');
        expect(unknown, equals(WanProtocol.unknown));
        expect(unknown.displayName, equals('Unrecognized Protocol'));
      },
    );

    test(
      'RpcResult classification handles transport and ubus status branches',
      () {
        final successRpc = [
          0,
          {'code': 0, 'stdout': 'lan1 lan2'},
        ];
        final resSuccess = RpcResult.classifyExecResult(successRpc, (d) => d);
        expect(resSuccess.isSuccess, isTrue);

        final notFoundRpc = [3, 'Object not found'];
        final resNotFound = RpcResult.fromUbusResponse(notFoundRpc, (d) => d);
        expect(resNotFound.isMethodNotFound, isTrue);

        final permDeniedRpc = [6, 'Permission denied'];
        final resPermDenied = RpcResult.fromUbusResponse(
          permDeniedRpc,
          (d) => d,
        );
        expect(resPermDenied.isPermissionDenied, isTrue);
      },
    );
  });
}
