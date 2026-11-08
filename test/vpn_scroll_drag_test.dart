// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/design/luci_theme.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/modules/vpn_connectivity/screens/vpn_connectivity_screen.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppState appState;
  final List<String> clipboardHistory = [];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    appState = AppState.instance;
    appState.setApiServiceForTesting(MockApiService());

    // Mock clipboard channel to capture copied values
    clipboardHistory.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            final text = methodCall.arguments['text'] as String?;
            if (text != null) clipboardHistory.add(text);
            return null;
          }
          return null;
        });

    appState.setDashboardDataForTesting({
      'wireguard': {
        'wg0': {
          'public_key': 'eX4mP1ePuB11cK3yF0rW1r3Gu4rdN3tw0rk=',
          'listen_port': 51820,
          'up': true,
          'peers': [
            {
              'public_key': 'PeerKey1',
              'endpoint': '198.51.100.42:51820',
              'allowed_ips': ['10.0.0.2/32'],
              'rx_bytes': 1048576,
              'tx_bytes': 2097152,
            },
          ],
        },
      },
      'tailscale': {
        'configured': true,
        'running': true,
        'hostname': 'Home-Router-Mesh',
        'ip': '100.64.0.15',
        'state': 'Running',
        'tailnet': 'mesh-network@tailscale.com',
        'magic_dns': 'router.tailnet.ts.net',
        'peers_count': 4,
        'is_exit_node': true,
      },
      'openvpn': <String, dynamic>{},
      'nextdns': {
        'configured': true,
        'enabled': '1',
        'running': true,
        'profile': 'abc123profile',
        'report_client_info': '1',
      },
      'cloudflared': {
        'configured': true,
        'running': true,
        'tunnel_id': 'f839a-1122-3344-5566-778899aabbcc',
        'connections_count': 4,
        'origin_url': 'http://192.168.1.1:80',
      },
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget createHarness() {
    return ProviderScope(
      overrides: [appStateProvider.overrideWith((ref) => appState)],
      child: MaterialApp(
        theme: LuciTheme.buildLightTheme(palette: AppThemePalette.dynamicTheme),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: VpnConnectivityScreen()),
      ),
    );
  }

  group('VPN Screen Fluid Scrolling & Tap-to-Copy Tests', () {
    testWidgets(
      'Dragging directly on Tailscale IP smoothly scrolls the view without gesture blocking',
      (tester) async {
        tester.view.physicalSize = const Size(360, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(createHarness());
        await tester.pumpAndSettle();

        // Verify Tailscale IP text is present on screen
        final ipFinder = find.text('100.64.0.15');
        expect(ipFinder, findsOneWidget);

        // Find scrollable
        final scrollableFinder = find.byType(Scrollable);
        expect(scrollableFinder, findsOneWidget);
        final scrollableState = tester.state<ScrollableState>(scrollableFinder);
        final initialOffset = scrollableState.position.pixels;
        expect(initialOffset, equals(0.0));

        // Drag vertically starting directly on the Tailscale IP text widget
        await tester.drag(ipFinder, const Offset(0, -300));
        await tester.pumpAndSettle();

        // Verify the view scrolled smoothly down
        final scrolledOffset = scrollableState.position.pixels;
        expect(
          scrolledOffset,
          greaterThan(100.0),
          reason: 'View must scroll down when dragged starting on Tailscale IP',
        );

        // Drag back up starting on Cloudflare Tunnel ID or whatever is now visible
        await tester.drag(scrollableFinder, const Offset(0, 300));
        await tester.pumpAndSettle();
        expect(scrollableState.position.pixels, lessThan(scrolledOffset));
      },
    );

    testWidgets(
      'Tapping Tailscale IP row copies the IP directly to clipboard with user feedback',
      (tester) async {
        await tester.pumpWidget(createHarness());
        await tester.pumpAndSettle();

        final ipFinder = find.text('100.64.0.15');
        expect(ipFinder, findsOneWidget);

        // Tap the Tailscale IP row
        await tester.tap(ipFinder);
        await tester.pumpAndSettle();

        // Verify clipboard received the IP address
        expect(clipboardHistory, contains('100.64.0.15'));
      },
    );

    testWidgets(
      'Tapping WireGuard Public Key copies key directly to clipboard',
      (tester) async {
        await tester.pumpWidget(createHarness());
        await tester.pumpAndSettle();

        final keyFinder = find.text('eX4mP1ePuB11cK3yF0rW1r3Gu4rdN3tw0rk=');
        expect(keyFinder, findsOneWidget);

        await tester.tap(keyFinder);
        await tester.pumpAndSettle();

        expect(
          clipboardHistory,
          contains('eX4mP1ePuB11cK3yF0rW1r3Gu4rdN3tw0rk='),
        );
      },
    );

    testWidgets(
      'Tailscale card displays Running status only once as header badge with no duplicate row',
      (tester) async {
        await tester.pumpWidget(createHarness());
        await tester.pumpAndSettle();

        // RUNNING badge in card header
        expect(find.text('RUNNING'), findsOneWidget);

        // Redundant "Backend Daemon State" row must not be present
        expect(find.text('Backend Daemon State'), findsNothing);
      },
    );
  });
}
