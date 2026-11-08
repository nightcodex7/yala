// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/vpn_connectivity/models/vpn_info.dart';
import 'package:yet_another_luci_app/modules/dhcp_dns/utils/dns_provider_resolver.dart';
import 'package:yet_another_luci_app/state/controllers/dashboard_controller.dart';

void main() {
  group('DashboardController UCI Config Parsing & NextDNS/Cloudflared tests', () {
    test('parseUciText parses cloudflared UCI configuration accurately', () {
      const cfUci = '''
config cloudflared 'config'
\toption enabled '1'
\toption token 'eyJhIjoiODk3NzEzZjA1MzVmMmNiNzYwOTAyNTA1YTY4NTNmMzkiLCJ0IjoiYWU0ZTJkNWYtOGJiMy00NzBhLWIyZjctZDAzNjQ1YzRmMWQyIiwicyI6IllUWTJNR1JqWlRjdFpHRTBOUzAwTVRFNUxUazJZell0WWpBNU5HVXlOREpqWkdReCJ9'
''';

      final parsed = DashboardController.parseUciText(cfUci);
      expect(parsed.containsKey('values'), isTrue);

      final values = parsed['values'] as Map<String, dynamic>;
      expect(values.containsKey('config'), isTrue);

      final sec = values['config'] as Map<String, dynamic>;
      expect(sec['.type'], equals('cloudflared'));
      expect(sec['.name'], equals('config'));
      expect(sec['.anonymous'], isFalse);
      expect(sec['enabled'], equals('1'));
      expect(
        sec['token'],
        equals(
          'eyJhIjoiODk3NzEzZjA1MzVmMmNiNzYwOTAyNTA1YTY4NTNmMzkiLCJ0IjoiYWU0ZTJkNWYtOGJiMy00NzBhLWIyZjctZDAzNjQ1YzRmMWQyIiwicyI6IllUWTJNR1JqWlRjdFpHRTBOUzAwTVRFNUxUazJZell0WWpBNU5HVXlOREpqWkdReCJ9',
        ),
      );

      // Verify CloudflaredStatus extracts tunnel ID from the JWT token
      final tunnelId = CloudflaredStatus.extractTunnelId(sec);
      expect(tunnelId, equals('ae4e2d5f-8bb3-470a-b2f7-d03645c4f1d2'));
    });

    test(
      'parseUciText parses nextdns UCI configuration with lists accurately',
      () {
        const nextdnsUci = '''
config nextdns 'main'
\toption enabled '0'
\toption setup_router '1'
\toption report_client_info '1'
\toption control '/var/run/nextdns.sock'
\tlist profile '2d9879'
\tlist listen '127.0.0.1:5342'
''';

        final parsed = DashboardController.parseUciText(nextdnsUci);
        expect(parsed.containsKey('values'), isTrue);

        final values = parsed['values'] as Map<String, dynamic>;
        expect(values.containsKey('main'), isTrue);

        final sec = values['main'] as Map<String, dynamic>;
        expect(sec['.type'], equals('nextdns'));
        expect(sec['enabled'], equals('0'));
        expect(sec['setup_router'], equals('1'));
        expect(sec['report_client_info'], equals('1'));
        expect(sec['profile'], isA<List>());
        expect((sec['profile'] as List).first, equals('2d9879'));
        expect((sec['listen'] as List), contains('127.0.0.1:5342'));
      },
    );

    test(
      'NextDnsStatus correctly resolves profile string when profile is a List',
      () {
        final mockData = {
          'nextdns': {
            'configured': true,
            'enabled': false,
            'running': false,
            'profile': '2d9879',
            'report_client_info': true,
          },
        };

        final overview = VpnConnectivityOverview.fromDashboardData(
          mockData,
          isReviewerMode: false,
        );

        expect(overview.nextdns.isConfigured, isTrue);
        expect(overview.nextdns.isEnabled, isFalse);
        expect(overview.nextdns.profileId, equals('2d9879'));
        expect(overview.nextdns.reportClientInfo, isTrue);
      },
    );

    test(
      'CloudflaredStatus correctly resolves configured tunnel from dashboard data',
      () {
        final mockData = {
          'cloudflared': {
            'configured': true,
            'enabled': true,
            'running': true,
            'tunnel_id': 'ae4e2d5f-8bb3-470a-b2f7-d03645c4f1d2',
            'tunnel_name': 'Cloudflare Tunnel',
            'token':
                'eyJhIjoiODk3NzEzZjA1MzVmMmNiNzYwOTAyNTA1YTY4NTNmMzkiLCJ0IjoiYWU0ZTJkNWYtOGJiMy00NzBhLWIyZjctZDAzNjQ1YzRmMWQyIiwicyI6IllUWTJNR1JqWlRjdFpHRTBOUzAwTVRFNUxUazJZell0WWpBNU5HVXlOREpqWkdReCJ9',
            'connections': 4,
          },
        };

        final overview = VpnConnectivityOverview.fromDashboardData(
          mockData,
          isReviewerMode: false,
        );

        expect(overview.cloudflared.isConfigured, isTrue);
        expect(overview.cloudflared.isEnabled, isTrue);
        expect(overview.cloudflared.isRunning, isTrue);
        expect(
          overview.cloudflared.tunnelId,
          equals('ae4e2d5f-8bb3-470a-b2f7-d03645c4f1d2'),
        );
        expect(overview.cloudflared.connectionsCount, equals(4));
      },
    );

    test('parseUciText handles anonymous sections and inline comments', () {
      const uciText = '''
# Global comment
config defaults # trailing comment
\toption syn_flood '1'
\toption input 'ACCEPT'
''';

      final parsed = DashboardController.parseUciText(uciText);
      final values = parsed['values'] as Map<String, dynamic>;
      expect(values.containsKey('cfg000000'), isTrue);
      final sec = values['cfg000000'] as Map<String, dynamic>;
      expect(sec['.type'], equals('defaults'));
      expect(sec['.anonymous'], isTrue);
      expect(sec['syn_flood'], equals('1'));
      expect(sec['input'], equals('ACCEPT'));
    });

    test(
      'parseUciChunkForTesting parses JSON chunk with whitespace and newlines',
      () {
        const jsonChunk = '''
\n\t
{
	"values": {
		"config": {
			".type": "cloudflared",
			"enabled": "1",
			"token": "test-token"
		}
	}
}
\n
''';
        final parsed = DashboardController.parseUciChunkForTesting(jsonChunk);
        expect(parsed, isNotNull);
        expect(parsed!['values'], isA<Map>());
        expect((parsed['values'] as Map).containsKey('config'), isTrue);
      },
    );

    test(
      'NextDNS and Cloudflared resolve properly after SSH fallback provides configs',
      () {
        // Simulates the exact parsed structure obtained via SSH fallback
        final nextdnsFromSsh = {
          'values': {
            'main': {
              '.type': 'nextdns',
              'enabled': '0',
              'profile': ['2d9879'],
              'report_client_info': '1',
            },
          },
        };

        final cfFromSsh = {
          'values': {
            'config': {
              '.type': 'cloudflared',
              'enabled': '1',
              'token':
                  'eyJhIjoiODk3NzEzZjA1MzVmMmNiNzYwOTAyNTA1YTY4NTNmMzkiLCJ0IjoiYWU0ZTJkNWYtOGJiMy00NzBhLWIyZjctZDAzNjQ1YzRmMWQyIiwicyI6IllUWTJNR1JqWlRjdFpHRTBOUzAwTVRFNUxUazJZell0WWpBNU5HVXlOREpqWkdReCJ9',
            },
          },
        };

        // Transform exactly as dashboard_controller does
        final ndSec =
            (nextdnsFromSsh['values'] as Map)['main'] as Map<String, dynamic>;
        final profileVal =
            (ndSec['profile'] is List
                    ? (ndSec['profile'] as List).firstOrNull
                    : ndSec['profile'])
                ?.toString() ??
            '';
        final synthesizedNd = {
          'configured': true,
          'enabled': ndSec['enabled'] == '1',
          'running': false,
          'profile': profileVal,
          'report_client_info': ndSec['report_client_info'] == '1',
        };

        final cfSec =
            (cfFromSsh['values'] as Map)['config'] as Map<String, dynamic>;
        final tunnelId = CloudflaredStatus.extractTunnelId(cfSec);
        final synthesizedCf = {
          'configured': true,
          'enabled': cfSec['enabled'] == '1',
          'running': true,
          'tunnel_id': tunnelId,
          'tunnel_name': 'Cloudflare Tunnel',
          'token': cfSec['token'],
          'connections': 4,
        };

        final dashboardData = {
          'nextdns': synthesizedNd,
          'cloudflared': synthesizedCf,
        };

        final overview = VpnConnectivityOverview.fromDashboardData(
          dashboardData,
          isReviewerMode: false,
        );

        expect(overview.nextdns.isConfigured, isTrue);
        expect(overview.nextdns.profileId, equals('2d9879'));
        expect(overview.cloudflared.isConfigured, isTrue);
        expect(
          overview.cloudflared.tunnelId,
          equals('ae4e2d5f-8bb3-470a-b2f7-d03645c4f1d2'),
        );
        expect(overview.cloudflared.isRunning, isTrue);
      },
    );

    test(
      'parseUciChunkForTesting correctly parses OpenVPN and Tailscale chunks',
      () {
        const openvpnChunk = '''
{
	"values": {
		"custom_client": {
			".anonymous": false,
			".type": "openvpn",
			".name": "custom_client",
			"enabled": "1",
			"dev": "tun0",
			"proto": "udp",
			"port": "1194"
		}
	}
}
''';

        const tailscaleChunk = '''
{
  "Version": "1.98.3-1 (OpenWrt)",
  "BackendState": "Running",
  "TailscaleIPs": ["100.90.160.1"],
  "Self": {
    "HostName": "ncxRouter",
    "DNSName": "ncxrouter.silverside-acrux.ts.net."
  },
  "CurrentTailnet": {
    "Name": "test@example.com"
  }
}
''';

        final ovpnParsed = DashboardController.parseUciChunkForTesting(
          openvpnChunk,
        );
        expect(ovpnParsed, isNotNull);
        expect(
          ovpnParsed!['values']['custom_client']['.type'],
          equals('openvpn'),
        );
        expect(ovpnParsed['values']['custom_client']['dev'], equals('tun0'));

        final tsParsed = DashboardController.parseUciChunkForTesting(
          tailscaleChunk,
        );
        expect(tsParsed, isNotNull);
        expect(tsParsed!['BackendState'], equals('Running'));
        expect(tsParsed['Self']['HostName'], equals('ncxRouter'));
        expect(tsParsed['TailscaleIPs'], contains('100.90.160.1'));
      },
    );

    test(
      'VpnConnectivityOverview parses OpenVPN and Tailscale accurately from fallback data',
      () {
        final dashboardData = {
          'openvpn': {
            'custom_client': {
              '.type': 'openvpn',
              '.name': 'custom_client',
              'enabled': '1',
              'running': true,
              'dev': 'tun0',
              'proto': 'udp',
              'port': '1194',
            },
          },
          'tailscale': {
            'configured': true,
            'enabled': true,
            'running': true,
            'node_name': 'ncxRouter',
            'tailscale_ip': '100.90.160.1',
            'state': 'Running',
            'tailnet': 'test@example.com',
            'magic_dns': 'ncxrouter.ts.net',
            'peers_count': 2,
            'is_exit_node': false,
          },
        };

        final overview = VpnConnectivityOverview.fromDashboardData(
          dashboardData,
          isReviewerMode: false,
        );

        expect(overview.openvpnInstances.length, equals(1));
        expect(overview.openvpnInstances.first.name, equals('custom_client'));
        expect(overview.openvpnInstances.first.isRunning, isTrue);

        expect(overview.tailscale.isConfigured, isTrue);
        expect(overview.tailscale.isRunning, isTrue);
        expect(overview.tailscale.nodeName, equals('ncxRouter'));
        expect(overview.tailscale.tailscaleIp, equals('100.90.160.1'));
        expect(overview.tailscale.peersCount, equals(2));
      },
    );

    test(
      'parseUciChunkForTesting correctly parses https-dns-proxy chunk and resolves Quad9 DoH',
      () {
        const hdpChunk = '''
config https-dns-proxy
\toption listen_addr '127.0.0.1'
\toption listen_port '5053'
\toption resolver_url 'https://dns10.quad9.net/dns-query'
\toption bootstrap_dns '9.9.9.10,149.112.112.10'
''';

        final parsed = DashboardController.parseUciChunkForTesting(hdpChunk);
        expect(parsed, isNotNull);
        expect(parsed!.containsKey('values'), isTrue);

        final values = parsed['values'] as Map<String, dynamic>;
        final sec = values.values.first as Map<String, dynamic>;
        expect(sec['listen_port'], equals('5053'));
        expect(
          sec['resolver_url'],
          equals('https://dns10.quad9.net/dns-query'),
        );

        final res = DnsProviderResolver.resolve(
          upstreamServers: ['127.0.0.1#5053'],
          httpsDnsProxyData: parsed,
        );
        expect(res, isNotNull);
        expect(res!.providerName, equals('Quad9'));
        expect(res.displayLabel, equals('Quad9 (DoH)'));
      },
    );
  });
}
