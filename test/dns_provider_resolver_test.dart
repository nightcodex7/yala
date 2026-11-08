// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/models/dashboard_preferences.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/modules/dhcp_dns/models/dhcp_dns_info.dart';
import 'package:yet_another_luci_app/modules/dhcp_dns/screens/dhcp_dns_screen.dart';
import 'package:yet_another_luci_app/modules/dhcp_dns/utils/dns_provider_resolver.dart';
import 'package:yet_another_luci_app/modules/dhcp_dns/widgets/dhcp_dns_card.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState appState;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'hint_dismissed_rpc_missing_warning': true,
    });

    appState = AppState.instance;
    final testRouter = model.Router(
      id: 'test_router_dns_resolution',
      ipAddress: '192.168.1.1',
      username: 'root',
      password: 'password',
      useHttps: false,
    );
    await appState.routerService?.addRouter(testRouter);
    await appState.routerService?.selectRouter(testRouter.id);
  });

  group('DnsProviderResolver Unit Tests', () {
    test('Resolves Quad9 DoH from https-dns-proxy on loopback port 5053', () {
      final httpsDnsProxyConfig = {
        'values': {
          'cfg02f37c': {
            '.name': 'cfg02f37c',
            '.type': 'https-dns-proxy',
            'listen_addr': '127.0.0.1',
            'listen_port': 5053,
            'resolver_url': 'https://dns10.quad9.net/dns-query',
            'bootstrap_dns': '9.9.9.10,149.112.112.10',
          },
        },
      };

      final result = DnsProviderResolver.resolve(
        upstreamServers: ['127.0.0.1#5053'],
        httpsDnsProxyData: httpsDnsProxyConfig,
      );

      expect(result, isNotNull);
      expect(result!.providerName, equals('Quad9'));
      expect(result.displayLabel, equals('Quad9 (DoH)'));
      expect(result.protocol, equals('DoH'));
      expect(result.endpoint, equals('https://dns10.quad9.net/dns-query'));
      expect(result.bootstrapDns, equals('9.9.9.10,149.112.112.10'));
      expect(result.socketAddress, equals('127.0.0.1#5053'));
      expect(result.summary, equals('Quad9 (DoH) via 127.0.0.1#5053'));
    });

    test('Resolves Cloudflare DoH from https-dns-proxy', () {
      final httpsDnsProxyConfig = {
        'values': {
          'cf': {
            '.name': 'cf',
            '.type': 'https-dns-proxy',
            'listen_addr': '127.0.0.1',
            'listen_port': 5053,
            'resolver_url': 'https://cloudflare-dns.com/dns-query',
            'bootstrap_dns': '1.1.1.1,1.0.0.1',
          },
        },
      };

      final result = DnsProviderResolver.resolve(
        upstreamServers: ['127.0.0.1#5053'],
        httpsDnsProxyData: httpsDnsProxyConfig,
      );

      expect(result, isNotNull);
      expect(result!.providerName, equals('Cloudflare'));
      expect(result.displayLabel, equals('Cloudflare (DoH)'));
      expect(result.endpoint, equals('https://cloudflare-dns.com/dns-query'));
    });

    test('Resolves Google DNS DoH from https-dns-proxy', () {
      final httpsDnsProxyConfig = {
        'values': {
          'google': {
            'listen_port': 5053,
            'resolver_url': 'https://dns.google/dns-query',
          },
        },
      };

      final result = DnsProviderResolver.resolve(
        upstreamServers: ['127.0.0.1#5053'],
        httpsDnsProxyData: httpsDnsProxyConfig,
      );

      expect(result, isNotNull);
      expect(result!.providerName, equals('Google DNS'));
      expect(result.displayLabel, equals('Google DNS (DoH)'));
    });

    test('Resolves Stubby DoT upstream configuration', () {
      final stubbyConfig = {
        'values': {
          'stubby': {
            '.type': 'stubby',
            'tls_auth_name': 'dns.quad9.net',
            'address_data': '9.9.9.9',
          },
        },
      };

      final result = DnsProviderResolver.resolve(
        upstreamServers: ['127.0.0.1#5453'],
        stubbyData: stubbyConfig,
      );

      expect(result, isNotNull);
      expect(result!.providerName, equals('Quad9'));
      expect(result.displayLabel, equals('Quad9 (DoT)'));
      expect(result.protocol, equals('DoT'));
      expect(result.summary, equals('Quad9 (DoT) via 127.0.0.1#5453'));
    });

    test('Resolves NextDNS active local proxy', () {
      final nextdnsConfig = {
        'values': {
          'main': {'enabled': '1', 'profile': 'abc123'},
        },
      };

      final result = DnsProviderResolver.resolve(
        upstreamServers: ['127.0.0.1#5342'],
        nextdnsData: nextdnsConfig,
      );

      expect(result, isNotNull);
      expect(result!.providerName, equals('NextDNS'));
      expect(result.displayLabel, equals('NextDNS'));
    });

    test('Resolves Cloudflared DoH proxy tunnel', () {
      final cloudflaredConfig = {
        'values': {
          'config': {
            'enabled': '1',
            'tunnel_id': 'ae4e2d5f-8bb3-470a-b2f7-d03645c4f1d2',
          },
        },
      };

      final result = DnsProviderResolver.resolve(
        upstreamServers: ['127.0.0.1#5054'],
        cloudflaredData: cloudflaredConfig,
      );

      expect(result, isNotNull);
      expect(result!.providerName, equals('Cloudflare'));
      expect(result.displayLabel, equals('Cloudflare (DoH)'));
    });

    test('Resolves SmartDNS with upstream DoH servers', () {
      final smartdnsConfig = {
        'values': {
          'smartdns': {'server-https': 'https://dns.quad9.net/dns-query'},
        },
      };

      final result = DnsProviderResolver.resolve(
        upstreamServers: ['127.0.0.1#6053'],
        smartdnsData: smartdnsConfig,
      );

      expect(result, isNotNull);
      expect(result!.providerName, equals('Quad9'));
      expect(result.displayLabel, equals('Quad9 (DoH)'));
    });

    test(
      'Resolves WAN interface upstream DNS when no custom DNS configured',
      () {
        final ifaceDump = {
          'interface': [
            {
              'interface': 'wan',
              'dns-server': ['9.9.9.9', '149.112.112.112'],
            },
          ],
        };

        final result = DnsProviderResolver.resolve(
          upstreamServers: ['ISP Default'],
          interfaceDump: ifaceDump,
        );

        expect(result, isNotNull);
        expect(result!.providerName, equals('Quad9'));
        expect(result.displayLabel, equals('Quad9 (WAN)'));
      },
    );
  });

  group('DhcpDnsOverview.fromDashboardData integration', () {
    test('Correctly populates resolved DNS fields for Quad9 DoH', () {
      final dashboardData = {
        'uciDhcpConfig': {
          'values': {
            'cfg01': {
              '.type': 'dnsmasq',
              'domain': 'lan',
              'rebind_protection': '1',
              'server': ['127.0.0.1#5053'],
            },
          },
        },
        'https-dns-proxy': {
          'values': {
            'cfg02f37c': {
              '.type': 'https-dns-proxy',
              'listen_addr': '127.0.0.1',
              'listen_port': 5053,
              'resolver_url': 'https://dns10.quad9.net/dns-query',
              'bootstrap_dns': '9.9.9.10,149.112.112.10',
            },
          },
        },
      };

      final overview = DhcpDnsOverview.fromDashboardData(dashboardData);

      expect(overview.resolvedDnsProvider, equals('Quad9 (DoH)'));
      expect(
        overview.resolvedDnsSummary,
        equals('Quad9 (DoH) via 127.0.0.1#5053'),
      );
      expect(
        overview.realDnsEndpoint,
        equals('https://dns10.quad9.net/dns-query'),
      );
      expect(overview.realDnsBootstrap, equals('9.9.9.10,149.112.112.10'));
    });
  });

  group('DhcpDnsCard Dashboard Display Widget Tests', () {
    Widget buildCardWidget() {
      return const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(child: SizedBox(width: 360, child: DhcpDnsCard())),
          ),
        ),
      );
    }

    testWidgets(
      'DhcpDnsCard displays "Quad9 (DoH)" on Dashboard when loopback 127.0.0.1#5053 is used',
      (tester) async {
        appState.setDashboardPreferencesForTesting(DashboardPreferences());
        appState.setDashboardDataForTesting({
          'dhcp': {
            'values': {
              'cfg01': {
                '.type': 'dnsmasq',
                'domain': 'lan',
                'rebind_protection': '1',
                'server': ['127.0.0.1#5053'],
              },
            },
          },
          'https-dns-proxy': {
            'values': {
              'cfg02f37c': {
                '.type': 'https-dns-proxy',
                'listen_addr': '127.0.0.1',
                'listen_port': 5053,
                'resolver_url': 'https://dns10.quad9.net/dns-query',
                'bootstrap_dns': '9.9.9.10,149.112.112.10',
              },
            },
          },
        });

        await tester.pumpWidget(buildCardWidget());
        await tester.pumpAndSettle();

        // Card title & domain badge
        expect(find.text('DHCP & DNS Management'), findsOneWidget);
        expect(find.text('.lan'), findsOneWidget);

        // Verify the tile displays real upstream DNS "Quad9 (DoH)" instead of raw loopback "127.0.0.1#5053"
        expect(find.text('Quad9 (DoH)'), findsOneWidget);
        expect(find.text('127.0.0.1#5053'), findsNothing);
      },
    );

    testWidgets(
      'DhcpDnsCard displays "Quad9 (DoH) (+1)" when loopback has secondary forwarder',
      (tester) async {
        appState.setDashboardPreferencesForTesting(DashboardPreferences());
        appState.setDashboardDataForTesting({
          'dhcp': {
            'values': {
              'cfg01': {
                '.type': 'dnsmasq',
                'domain': 'lan',
                'rebind_protection': '1',
                'server': ['127.0.0.1#5053', '1.1.1.1'],
              },
            },
          },
          'https-dns-proxy': {
            'values': {
              'cfg02f37c': {
                '.type': 'https-dns-proxy',
                'listen_addr': '127.0.0.1',
                'listen_port': 5053,
                'resolver_url': 'https://dns10.quad9.net/dns-query',
                'bootstrap_dns': '9.9.9.10,149.112.112.10',
              },
            },
          },
        });

        await tester.pumpWidget(buildCardWidget());
        await tester.pumpAndSettle();

        expect(find.text('Quad9 (DoH) (+1)'), findsOneWidget);
      },
    );
  });

  group('DhcpDnsScreen Details Widget Tests', () {
    Widget buildScreenWidget() {
      return const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DhcpDnsScreen(),
        ),
      );
    }

    testWidgets(
      'DhcpDnsScreen displays complete DoH upstream summary, endpoint URL, and bootstrap IPs',
      (tester) async {
        appState.setDashboardDataForTesting({
          'dhcp': {
            'values': {
              'cfg01': {
                '.type': 'dnsmasq',
                'domain': 'lan',
                'rebind_protection': '1',
                'server': ['127.0.0.1#5053'],
              },
            },
          },
          'https-dns-proxy': {
            'values': {
              'cfg02f37c': {
                '.type': 'https-dns-proxy',
                'listen_addr': '127.0.0.1',
                'listen_port': 5053,
                'resolver_url': 'https://dns10.quad9.net/dns-query',
                'bootstrap_dns': '9.9.9.10,149.112.112.10',
              },
            },
          },
        });

        await tester.pumpWidget(buildScreenWidget());
        await tester.pumpAndSettle();

        // Check section header
        expect(find.text('DNS Forwarders & Dnsmasq Config'), findsOneWidget);

        // Check Upstream DNS Forwarders row
        expect(find.text('Quad9 (DoH) via 127.0.0.1#5053'), findsOneWidget);

        // Check Encrypted DNS Endpoint row
        expect(find.text('Encrypted DNS Endpoint'), findsOneWidget);
        expect(find.text('https://dns10.quad9.net/dns-query'), findsOneWidget);

        // Check Bootstrap DNS Servers row
        expect(find.text('Bootstrap DNS Servers'), findsOneWidget);
        expect(find.text('9.9.9.10,149.112.112.10'), findsOneWidget);
      },
    );
  });
}
