// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/vpn_connectivity/models/vpn_info.dart';
import 'package:yet_another_luci_app/state/controllers/dashboard_controller.dart';

void main() {
  group('VPN & Connectivity Unit Tests', () {
    test('Parses WireguardPeer and formats handshake correctly', () {
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final peerJson = {
        'public_key': 'P33r1PuB11cK3yStr1ngM0b1l3Ph0n3=',
        'endpoint': '198.51.100.42:51820',
        'allowed_ips': ['10.0.0.2/32', 'fd42:42:42::2/128'],
        'rx_bytes': 15420000,
        'tx_bytes': 4210000,
        'latest_handshake': nowSeconds - 45,
      };

      final peer = WireguardPeer.fromJson(peerJson);
      expect(peer.publicKey, equals('P33r1PuB11cK3yStr1ngM0b1l3Ph0n3='));
      expect(peer.endpoint, equals('198.51.100.42:51820'));
      expect(peer.allowedIps.length, equals(2));
      expect(peer.rxBytes, equals(15420000));
      expect(peer.txBytes, equals(4210000));
      expect(peer.formattedHandshake, contains('seconds ago'));
    });

    test('Parses WireguardInterface correctly', () {
      final wgJson = {
        'public_key': 'eX4mP1ePuB11cK3yF0rW1r3Gu4rdN3tw0rk=',
        'listen_port': 51820,
        'up': true,
        'peers': [
          {
            'public_key': 'PeerKey1',
            'allowed_ips': '10.0.0.2/32',
            'rx_bytes': 1000,
            'tx_bytes': 2000,
          },
        ],
      };

      final wg = WireguardInterface.fromJson('wg0', wgJson);
      expect(wg.name, equals('wg0'));
      expect(wg.publicKey, equals('eX4mP1ePuB11cK3yF0rW1r3Gu4rdN3tw0rk='));
      expect(wg.listenPort, equals(51820));
      expect(wg.isUp, isTrue);
      expect(wg.peers.length, equals(1));
      expect(wg.peers.first.publicKey, equals('PeerKey1'));
    });

    test('Parses OpenVpnInstance correctly', () {
      final ovpnJson = {
        'enabled': '1',
        'running': true,
        'port': '1194',
        'proto': 'udp',
        'dev': 'tun0',
      };

      final instance = OpenVpnInstance.fromJson('custom_client', ovpnJson);
      expect(instance.name, equals('custom_client'));
      expect(instance.isEnabled, isTrue);
      expect(instance.isRunning, isTrue);
      expect(instance.port, equals('1194'));
      expect(instance.proto, equals('udp'));
      expect(instance.dev, equals('tun0'));
    });

    test('Parses TailscaleStatus correctly', () {
      final tsJson = {
        'configured': true,
        'running': true,
        'hostname': 'Home-Router',
        'ip': '100.64.0.15',
        'state': 'Running',
      };

      final ts = TailscaleStatus.fromJson(tsJson);
      expect(ts.isConfigured, isTrue);
      expect(ts.isRunning, isTrue);
      expect(ts.nodeName, equals('Home-Router'));
      expect(ts.tailscaleIp, equals('100.64.0.15'));
      expect(ts.backendState, equals('Running'));
    });

    test('Parses NextDnsStatus correctly when active and stopped', () {
      final ndnsJsonActive = {
        'configured': true,
        'enabled': '1',
        'running': true,
        'profile': 'abcdef',
        'report_client_info': '1',
      };

      final ndnsActive = NextDnsStatus.fromJson(ndnsJsonActive);
      expect(ndnsActive.isConfigured, isTrue);
      expect(ndnsActive.isEnabled, isTrue);
      expect(ndnsActive.isRunning, isTrue);
      expect(ndnsActive.profileId, equals('abcdef'));
      expect(ndnsActive.reportClientInfo, isTrue);

      final ndnsJsonStopped = {
        'configured': true,
        'enabled': '1',
        'running': false,
        'profile': 'abcdef',
        'report_client_info': '1',
      };

      final ndnsStopped = NextDnsStatus.fromJson(ndnsJsonStopped);
      expect(ndnsStopped.isConfigured, isTrue);
      expect(ndnsStopped.isEnabled, isTrue);
      expect(ndnsStopped.isRunning, isFalse);
    });

    test('Parses CloudflaredStatus correctly', () {
      final cfJson = {
        'configured': true,
        'enabled': '1',
        'running': true,
        'tunnel_id': '8f92a10b-4c3d-2e1f-0a9b-8c7d6e5f4a3b',
        'tunnel_name': 'my-home-tunnel',
        'token': 'secret-jwt-token',
        'connections': 4,
      };

      final cf = CloudflaredStatus.fromJson(cfJson);
      expect(cf.isConfigured, isTrue);
      expect(cf.isEnabled, isTrue);
      expect(cf.isRunning, isTrue);
      expect(cf.tunnelId, equals('8f92a10b-4c3d-2e1f-0a9b-8c7d6e5f4a3b'));
      expect(cf.tunnelName, equals('my-home-tunnel'));
      expect(cf.connectionsCount, equals(4));
    });

    test(
      'CloudflaredStatus extracts tunnel ID from credentials_file path and section name',
      () {
        final jsonCredentials = {
          '.name': 'config',
          'enabled': '1',
          'credentials_file':
              '/etc/cloudflared/8f92a10b-4c3d-2e1f-0a9b-8c7d6e5f4a3b.json',
        };
        expect(
          CloudflaredStatus.extractTunnelId(jsonCredentials),
          equals('8f92a10b-4c3d-2e1f-0a9b-8c7d6e5f4a3b'),
        );

        final jsonSectionName = {
          '.name': '8f92a10b-4c3d-2e1f-0a9b-8c7d6e5f4a3b',
          'enabled': '1',
        };
        expect(
          CloudflaredStatus.extractTunnelId(jsonSectionName),
          equals('8f92a10b-4c3d-2e1f-0a9b-8c7d6e5f4a3b'),
        );
      },
    );

    test(
      'CloudflaredStatus extracts tunnel ID by decoding Base64 / JWT Cloudflare token',
      () {
        // Base64 of {"a":"account123","t":"11223344-5566-7788-9900-aabbccddeeff","s":"secret"}
        const token =
            'eyJhIjoiYWNjb3VudDEyMyIsInQiOiIxMTIyMzM0NC01NTY2LTc3ODgtOTkwMC1hYWJiY2NkZGVlZmYiLCJzIjoic2VjcmV0In0=';
        final jsonToken = {'enabled': '1', 'token': token};
        expect(
          CloudflaredStatus.extractTunnelId(jsonToken),
          equals('11223344-5566-7788-9900-aabbccddeeff'),
        );
      },
    );

    test(
      'VpnConnectivityOverview in Reviewer Mode provides complete mock structure',
      () {
        final overview = VpnConnectivityOverview.fromDashboardData(
          null,
          isReviewerMode: true,
        );

        expect(overview.wireguardInterfaces.length, equals(1));
        expect(overview.openvpnInstances.length, equals(1));
        expect(overview.tailscale.isConfigured, isTrue);
        expect(overview.nextdns.isConfigured, isTrue);
        expect(overview.cloudflared.isConfigured, isTrue);

        expect(overview.totalWgPeers, equals(2));
        expect(overview.activeServicesCount, equals(5));
        expect(overview.totalConfiguredServices, equals(5));
      },
    );

    test(
      'VpnConnectivityOverview in Real Mode handles empty/null dashboard data safely',
      () {
        final overview = VpnConnectivityOverview.fromDashboardData(
          null,
          isReviewerMode: false,
        );

        expect(overview.wireguardInterfaces, isEmpty);
        expect(overview.openvpnInstances, isEmpty);
        expect(overview.tailscale.isConfigured, isFalse);
        expect(overview.nextdns.isConfigured, isFalse);
        expect(overview.cloudflared.isConfigured, isFalse);

        expect(overview.totalWgPeers, equals(0));
        expect(overview.activeServicesCount, equals(0));
        expect(overview.totalConfiguredServices, equals(0));
      },
    );

    test(
      'Correctly identifies unconfigured services when partial data is provided',
      () {
        final partialData = {
          'wireguard': <String, dynamic>{}, // empty
          'openvpn': <String, dynamic>{}, // empty
          'tailscale': null,
          'nextdns': null,
          'cloudflared': null,
        };

        final overview = VpnConnectivityOverview.fromDashboardData(
          partialData,
          isReviewerMode: false,
        );

        expect(overview.wireguardInterfaces.isEmpty, isTrue);
        expect(overview.openvpnInstances.isEmpty, isTrue);
        expect(overview.tailscale.isConfigured, isFalse);
        expect(overview.nextdns.isConfigured, isFalse);
        expect(overview.cloudflared.isConfigured, isFalse);
      },
    );

    test(
      'VpnConnectivityOverview parses full real dashboard map correctly',
      () {
        final fullData = {
          'wireguard': {
            'wg0': {
              'public_key': 'WgKey123',
              'listen_port': 51820,
              'up': true,
              'peers': [
                {
                  'public_key': 'Peer1',
                  'allowed_ips': ['10.0.0.2/32'],
                  'rx_bytes': 500,
                  'tx_bytes': 300,
                },
              ],
            },
          },
          'openvpn': {
            'server1': {
              'enabled': '1',
              'running': true,
              'port': '1194',
              'proto': 'udp',
              'dev': 'tun0',
            },
          },
          'tailscale': {
            'configured': true,
            'enabled': true,
            'running': true,
            'node_name': 'MyNode',
            'ip': '100.64.0.1',
            'state': 'Running',
          },
          'nextdns': {
            'configured': true,
            'enabled': '1',
            'profile': 'xyz789',
            'report_client_info': '1',
          },
          'cloudflared': {
            'configured': true,
            'enabled': '1',
            'running': true,
            'tunnel_id': 'cf-tunnel-id-123',
            'tunnel_name': 'web-tunnel',
            'token': 'tok123',
            'connections': 4,
          },
        };

        final overview = VpnConnectivityOverview.fromDashboardData(
          fullData,
          isReviewerMode: false,
        );

        expect(overview.wireguardInterfaces.length, equals(1));
        expect(overview.openvpnInstances.length, equals(1));
        expect(overview.tailscale.isConfigured, isTrue);
        expect(overview.nextdns.isConfigured, isTrue);
        expect(overview.cloudflared.isConfigured, isTrue);

        expect(overview.totalWgPeers, equals(1));
        expect(overview.activeServicesCount, equals(5));
        expect(overview.totalConfiguredServices, equals(5));
      },
    );

    test(
      'DashboardController.synthesizeWireGuardData detects WireGuard interface without LuCI app',
      () {
        final interfaceDump = {
          'interface': [
            {
              'interface': 'vpn_server',
              'proto': 'wireguard',
              'up': true,
              'device': 'wg0',
              'l3_device': 'wg0',
            },
          ],
        };

        final uciNetworkConfig = {
          'values': {
            'vpn_server': {
              '.type': 'interface',
              'proto': 'wireguard',
              'listen_port': '51820',
            },
            'peer1': {
              '.type': 'wireguard_vpn_server',
              'public_key': 'ClientPubKey1234567890=',
              'endpoint_host': '198.51.100.5',
              'endpoint_port': '51820',
              'allowed_ips': ['10.0.0.2/32'],
            },
          },
        };

        // Simulating luci-app-wireguard absent: liveWireGuardData is null
        final synthesized = DashboardController.synthesizeWireGuardData(
          interfaceDump: interfaceDump,
          uciNetworkConfig: uciNetworkConfig,
          liveWireGuardData: null,
        );

        expect(synthesized.containsKey('vpn_server'), isTrue);
        final vpn = synthesized['vpn_server'] as Map<String, dynamic>;
        expect(vpn['interface'], equals('vpn_server'));
        expect(vpn['device'], equals('wg0'));
        expect(vpn['up'], isTrue);
        expect(vpn['listen_port'], equals(51820));

        final peers = vpn['peers'] as Map<String, dynamic>;
        expect(peers.containsKey('ClientPubKey1234567890='), isTrue);
        final peer = peers['ClientPubKey1234567890='] as Map<String, dynamic>;
        expect(peer['endpoint'], equals('198.51.100.5:51820'));
        expect(peer['allowed_ips'], contains('10.0.0.2/32'));
      },
    );

    test('WireGuard interface with 0 peers is retained and not dropped', () {
      final interfaceDump = {
        'interface': [
          {
            'interface': 'wg_empty',
            'proto': 'wireguard',
            'up': true,
            'device': 'wg1',
          },
        ],
      };

      final synthesized = DashboardController.synthesizeWireGuardData(
        interfaceDump: interfaceDump,
        uciNetworkConfig: null,
        liveWireGuardData: null,
      );

      expect(synthesized.containsKey('wg_empty'), isTrue);
      final wg = synthesized['wg_empty'] as Map<String, dynamic>;
      expect(wg['up'], isTrue);
      expect((wg['peers'] as Map).isEmpty, isTrue);

      // Verify VpnConnectivityOverview parses it correctly
      final overview = VpnConnectivityOverview.fromDashboardData({
        'wireguard': synthesized,
      }, isReviewerMode: false);

      expect(overview.wireguardInterfaces.length, equals(1));
      expect(overview.wireguardInterfaces.first.name, equals('wg_empty'));
      expect(overview.wireguardInterfaces.first.isUp, isTrue);
      expect(overview.wireguardInterfaces.first.peers, isEmpty);
    });

    test(
      'DashboardController.synthesizeOpenVpnData correctly computes running status and defaults to enabled',
      () {
        final uciOpenvpn = {
          'values': {
            'custom_server': {
              '.type': 'openvpn',
              'dev': 'tun0',
              'proto': 'udp',
              'port': '1194',
              // Note: 'enabled' option omitted, should default to enabled (1)
            },
            'disabled_client': {
              '.type': 'openvpn',
              'enabled': '0',
              'dev': 'tun1',
              'proto': 'tcp',
            },
          },
        };

        // Network devices showing tun0 is UP
        final networkDevices = {
          'eth0': {'up': true},
          'tun0': {
            'up': true,
            'flags': ['UP', 'POINTOPOINT', 'RUNNING'],
          },
        };

        final synthesized = DashboardController.synthesizeOpenVpnData(
          uciOpenvpnRaw: uciOpenvpn,
          interfaceDump: null,
          networkDevices: networkDevices,
          servicesData: null,
          initScriptsData: null,
        );

        expect(synthesized.containsKey('custom_server'), isTrue);
        final server = synthesized['custom_server'] as Map<String, dynamic>;
        expect(server['enabled'], equals('1'));
        expect(server['running'], isTrue);

        expect(synthesized.containsKey('disabled_client'), isTrue);
        final disabled = synthesized['disabled_client'] as Map<String, dynamic>;
        expect(disabled['enabled'], equals('0'));
        expect(disabled['running'], isFalse);

        // Verify OpenVpnInstance model parsing
        final instance = OpenVpnInstance.fromJson('custom_server', server);
        expect(instance.isEnabled, isTrue);
        expect(instance.isRunning, isTrue);
      },
    );

    test(
      'VpnConnectivityOverview detects fallback tunnels from interfaceDump when map is empty',
      () {
        final dashboardData = {
          'wireguard': <String, dynamic>{}, // empty map
          'openvpn': <String, dynamic>{}, // empty map
          'interfaceDump': {
            'interface': [
              {
                'interface': 'lan',
                'proto': 'static',
                'device': 'br-lan',
                'up': true,
              },
              {
                'interface': 'wg_tunnel',
                'proto': 'wireguard',
                'device': 'wg0',
                'up': true,
              },
              {
                'interface': 'ovpn_client',
                'proto': 'openvpn',
                'device': 'tun0',
                'up': true,
              },
            ],
          },
        };

        final overview = VpnConnectivityOverview.fromDashboardData(
          dashboardData,
          isReviewerMode: false,
        );

        expect(overview.wireguardInterfaces.length, equals(1));
        expect(overview.wireguardInterfaces.first.name, equals('wg_tunnel'));
        expect(overview.wireguardInterfaces.first.isUp, isTrue);

        expect(overview.openvpnInstances.length, equals(1));
        expect(overview.openvpnInstances.first.name, equals('ovpn_client'));
        expect(overview.openvpnInstances.first.isRunning, isTrue);
      },
    );
  });
}
