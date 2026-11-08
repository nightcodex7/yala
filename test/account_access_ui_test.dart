// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart' hide Router;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/router.dart';
import 'package:yet_another_luci_app/modules/account_access/controllers/account_access_controller.dart';
import 'package:yet_another_luci_app/modules/account_access/models/account_access_models.dart';
import 'package:yet_another_luci_app/modules/account_access/screens/account_access_screen.dart';
import 'package:yet_another_luci_app/modules/account_access/screens/account_detail_screen.dart';
import 'package:yet_another_luci_app/modules/account_access/services/account_access_inspector.dart';
import 'package:yet_another_luci_app/screens/settings_screen.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

class MockAccountAccessController extends AccountAccessController {
  bool refreshCalled = false;

  MockAccountAccessController(AccountAccessState initialState)
    : super(ref: _DummyRef(), inspector: const AccountAccessInspector()) {
    state = initialState;
  }

  @override
  Future<void> inspect({bool force = false}) async {}

  @override
  Future<void> refresh() async {
    refreshCalled = true;
  }
}

class _DummyRef implements Ref {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

AccountAccessSnapshot createSampleSnapshot({
  bool confirmedByRouter = true,
  bool isPartial = false,
  List<RouterAccountEntry>? availableAccounts,
}) {
  final now = DateTime.now();
  return AccountAccessSnapshot(
    routerId: 'router-uuid-1',
    inspectedAt: now,
    inspectionDuration: const Duration(milliseconds: 85),
    isPartialInspection: isPartial,
    availableAccounts:
        availableAccounts ??
        [
          RouterAccountEntry(
            username: 'root',
            isActiveSession: true,
            isConfirmedByRouter: confirmedByRouter,
            role: 'Primary Administrator (UID 0)',
            accessScope: 'LuCI RPC & SSH Access',
            source: confirmedByRouter
                ? 'Confirmed via UNIX shell'
                : 'Profile label',
          ),
        ],
    account: CurrentAccountInfo(
      configuredUsername: 'root',
      authenticatedUsername: confirmedByRouter ? 'root' : null,
      isUsernameConfirmedByRouter: confirmedByRouter,
      identitySource: confirmedByRouter
          ? 'Confirmed independently via authenticated UNIX shell (UID 0)'
          : 'Configured profile label (unconfirmed by LuCI session API)',
      profileName: 'Main Laboratory Router',
      routerAddress: '192.168.1.1',
      boardModel: 'x86/64 TestPlatform',
      firmwareVersion: 'OpenWrt 23.05.3 r23809-234f1a2efa',
      authMethod: 'LuCI RPC sysauth token',
      connectionMethod: 'HTTPS (TLS encrypted)',
      sessionStatus: 'Authenticated & Active',
      sessionValidity: 'Active session verified via system.board RPC',
      lastVerified: now,
    ),
    connectionMethods: const [
      ConnectionMethodInfo(
        id: 'luci_http',
        name: 'LuCI HTTP/HTTPS Web Session',
        status: ConnectionMethodStatus.activeAndVerified,
        endpointOrPort: 'HTTPS (port 443)',
        explanation:
            'Active HTTP session responding with valid sysauth credentials.',
        evidenceSource: 'Direct system.board read probe',
      ),
      ConnectionMethodInfo(
        id: 'luci_rpc',
        name: 'LuCI JSON-RPC (ubus)',
        status: ConnectionMethodStatus.activeAndVerified,
        endpointOrPort: '/ubus JSON-RPC',
        explanation: '14 ubus objects available to current session.',
        evidenceSource: 'rpcd session.access effective ACLs',
      ),
      ConnectionMethodInfo(
        id: 'ssh',
        name: 'SSH Console Access',
        status: ConnectionMethodStatus.activeAndVerified,
        endpointOrPort: 'SSH (port 22)',
        explanation:
            'SSH connection verified on port 22; authenticated as root.',
        evidenceSource: 'UCI dropbear configuration',
      ),
    ],
    rpcCapabilities: const [
      RpcCapabilityPermission(
        id: 'system_info',
        title: 'System Information',
        category: 'Core System',
        readStatus: PermissionAccessStatus.verifiedReadAccess,
        writeStatus: PermissionAccessStatus.notApplicable,
        evidenceSource: 'ubus system object (info, board)',
        explanation: 'Read access verified via system.board RPC.',
      ),
      RpcCapabilityPermission(
        id: 'network_interfaces',
        title: 'Network Interfaces & Status',
        category: 'Network & Interfaces',
        readStatus: PermissionAccessStatus.verifiedReadAccess,
        writeStatus: PermissionAccessStatus.verifiedWriteAuthorization,
        evidenceSource: 'ubus network.interface & uci network ACL',
        explanation: 'Read status verified; write evaluated via UCI ACL.',
      ),
      RpcCapabilityPermission(
        id: 'firewall_rules',
        title: 'Firewall Rules & Security',
        category: 'Security & Firewall',
        readStatus: PermissionAccessStatus.verifiedReadAccess,
        writeStatus: PermissionAccessStatus.verifiedDenied,
        evidenceSource: 'ubus fw4 & uci firewall ACL',
        explanation: 'Firewall read verified; write denied by ACL.',
      ),
      RpcCapabilityPermission(
        id: 'service_control',
        title: 'Service Control & Init Scripts',
        category: 'Services & Management',
        readStatus: PermissionAccessStatus.verifiedReadAccess,
        writeStatus: PermissionAccessStatus.verifiedWriteAuthorization,
        evidenceSource: 'ubus service list',
        explanation: 'Init scripts control permissions confirmed.',
      ),
    ],
    sshAccess: const SshAccessInfo(
      reachability: SshReachabilityStatus.verifiedWorking,
      port: 22,
      portSource: 'UCI dropbear configuration',
      daemonStatus: 'Dropbear SSH configuration detected in UCI',
      hasActiveConnection: true,
      authenticatedUser: 'root',
      isIdentityConfirmed: true,
      readOnlyExecutionSucceeded: true,
      executionOutput: 'UNIX username: root',
      explanation: 'SSH connection verified on port 22; authenticated as root.',
      securityNotes:
          'Security Guarantee: YALA never exposes stored passwords or private keys, never touches /etc/shadow, and only executes bounded read-only commands without guessing passwords.',
    ),
    subsystems: const [
      SubsystemAccessInfo(
        id: 'uci',
        name: 'UCI Configuration System',
        status: '8 configs mapped',
        detail: 'system, network, wireless, firewall, dhcp, dropbear',
        isSupported: true,
      ),
      SubsystemAccessInfo(
        id: 'firewall',
        name: 'Firewall Engine Backend',
        status: 'FW4 (nftables)',
        detail: 'nftables firewall engine active.',
        isSupported: true,
      ),
    ],
    diagnostics: [
      DiagnosticFinding(
        timestamp: now,
        message: 'system.board RPC query succeeded',
        evidence: 'Model: x86/64 TestPlatform',
      ),
      DiagnosticFinding(
        timestamp: now,
        message: 'rpcd session.access returned effective permissions',
      ),
      DiagnosticFinding(
        timestamp: now,
        message: 'SSH read-only command succeeded',
        evidence: 'User: root, Port: 22',
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget createTestWidget({
    required Widget child,
    MockAccountAccessController? controller,
    ThemeMode themeMode = ThemeMode.light,
    Locale? locale,
  }) {
    final appState = AppState.instance;
    return ProviderScope(
      overrides: [
        appStateProvider.overrideWith((ref) => appState),
        if (controller != null)
          accountAccessControllerProvider.overrideWith((ref) => controller),
      ],
      child: MaterialApp(
        locale: locale,
        themeMode: themeMode,
        theme: ThemeData.light(useMaterial3: true),
        darkTheme: ThemeData.dark(useMaterial3: true),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }

  group('Settings Header Entry Point Tests', () {
    testWidgets(
      'Settings screen contains aligned Account & Access header icon and opens inspector screen',
      (tester) async {
        final appState = AppState.instance;
        appState.setSelectedRouterForTesting(
          Router(
            id: 'router-1',
            ipAddress: '192.168.1.1',
            username: 'root',
            password: 'pwd',
            useHttps: false,
            name: 'Test Router',
          ),
        );

        final controller = MockAccountAccessController(
          AccountAccessState(snapshot: createSampleSnapshot()),
        );

        await tester.pumpWidget(
          createTestWidget(
            child: const SettingsScreen(),
            controller: controller,
          ),
        );
        await tester.pumpAndSettle();

        // 1. Verify header icon button is present in Settings AppBar
        final accountIconFinder = find.byIcon(Icons.manage_accounts_outlined);
        expect(accountIconFinder, findsOneWidget);

        // 2. Verify tooltip / semantic label
        final iconButton = tester.widget<IconButton>(
          find.ancestor(
            of: accountIconFinder,
            matching: find.byType(IconButton),
          ),
        );
        expect(iconButton.tooltip, equals('Account & Access'));

        // 3. Verify existing Settings screen controls still exist
        expect(find.text('Settings'), findsOneWidget);
        expect(find.text('Appearance'), findsOneWidget);

        // 4. Tap the Account & Access icon button
        await tester.tap(accountIconFinder);
        await tester.pumpAndSettle();

        // 5. Verify AccountAccessScreen is opened with minimalist view
        expect(find.byType(AccountAccessScreen), findsOneWidget);
        expect(find.text('Router Accounts'), findsOneWidget);
        expect(find.text('root'), findsAtLeastNWidgets(1));
        expect(find.text('ACTIVE'), findsOneWidget);
        expect(find.text('No Other Accounts Configured'), findsOneWidget);

        // 6. Tap "View Access" on active account to reveal AccountDetailScreen
        await tester.tap(find.text('View Access'));
        await tester.pumpAndSettle();

        expect(find.byType(AccountDetailScreen), findsOneWidget);
        expect(find.text('Access & Permissions (root)'), findsOneWidget);
        expect(find.text('Current Account'), findsOneWidget);
        expect(
          find.text('Authentication & Connection Methods'),
          findsOneWidget,
        );
        expect(find.text('LuCI RPC Permissions'), findsOneWidget);
        expect(find.text('SSH Access'), findsOneWidget);
      },
    );
  });

  group('AccountAccessScreen UI Rendering Tests', () {
    testWidgets(
      'Renders minimalist available accounts and reveals detailed access upon tapping',
      (tester) async {
        final sample = createSampleSnapshot(confirmedByRouter: true);
        final controller = MockAccountAccessController(
          AccountAccessState(snapshot: sample),
        );

        await tester.pumpWidget(
          createTestWidget(
            child: const AccountAccessScreen(),
            controller: controller,
          ),
        );
        await tester.pumpAndSettle();

        // Top Read-Only Banner
        expect(
          find.textContaining('Read-Only Access Inspector'),
          findsOneWidget,
        );

        // Minimalist Available Accounts Section
        expect(find.text('Router Accounts'), findsOneWidget);
        expect(find.text('root'), findsAtLeastNWidgets(1));
        expect(find.text('ACTIVE'), findsOneWidget);
        expect(find.text('Primary Administrator (UID 0)'), findsOneWidget);
        expect(find.text('No Other Accounts Configured'), findsOneWidget);

        // Tap "View Access" on active account entry
        await tester.tap(find.text('View Access'));
        await tester.pumpAndSettle();

        // Reveals AccountDetailScreen with all 6 sections
        expect(find.byType(AccountDetailScreen), findsOneWidget);
        expect(find.text('Access & Permissions (root)'), findsOneWidget);
        expect(find.text('Current Account'), findsOneWidget);
        expect(find.text('Confirmed by Router'), findsOneWidget);
        expect(find.text('Authentication Method'), findsOneWidget);
        expect(find.text('LuCI RPC sysauth token'), findsOneWidget);

        expect(
          find.text('Authentication & Connection Methods'),
          findsOneWidget,
        );
        expect(find.text('LuCI HTTP/HTTPS Web Session'), findsOneWidget);
        expect(find.text('LuCI JSON-RPC (ubus)'), findsOneWidget);
        expect(find.text('SSH Console Access'), findsOneWidget);

        expect(find.text('LuCI RPC Permissions'), findsOneWidget);
        expect(find.text('System Information'), findsOneWidget);
        expect(find.text('Network Interfaces & Status'), findsOneWidget);
        expect(find.text('Firewall Rules & Security'), findsOneWidget);

        expect(find.text('SSH Access'), findsOneWidget);
        expect(
          find.text('Verified Working & Authenticated'),
          findsAtLeastNWidgets(1),
        );

        expect(find.text('Other Verified Access Capabilities'), findsOneWidget);
        expect(find.text('UCI Configuration System'), findsOneWidget);
        expect(find.text('Firewall Engine Backend'), findsOneWidget);

        expect(find.text('Detection Status & Diagnostics'), findsOneWidget);
        expect(
          find.text('0 writes performed (Strictly Read-Only)'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Renders other configured accounts when secondary accounts exist',
      (tester) async {
        final sample = createSampleSnapshot(
          availableAccounts: const [
            RouterAccountEntry(
              username: 'root',
              isActiveSession: true,
              isConfirmedByRouter: true,
              role: 'Primary Administrator (UID 0)',
              accessScope: 'LuCI RPC & SSH Access',
              source: 'Confirmed via UNIX shell',
            ),
            RouterAccountEntry(
              username: 'operator',
              isActiveSession: false,
              isConfirmedByRouter: true,
              role: 'Configured User Account',
              accessScope: 'Secondary Login',
              source: 'UCI rpcd login',
            ),
          ],
        );
        final controller = MockAccountAccessController(
          AccountAccessState(snapshot: sample),
        );

        await tester.pumpWidget(
          createTestWidget(
            child: const AccountAccessScreen(),
            controller: controller,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Router Accounts'), findsOneWidget);
        expect(find.text('root'), findsOneWidget);
        expect(find.text('Other Configured Accounts (1)'), findsOneWidget);
        expect(find.text('operator'), findsOneWidget);
        expect(find.text('No Other Accounts Configured'), findsNothing);
      },
    );

    testWidgets(
      'Renders unconfirmed profile label when username is not confirmed by router',
      (tester) async {
        final sample = createSampleSnapshot(confirmedByRouter: false);
        final controller = MockAccountAccessController(
          AccountAccessState(snapshot: sample),
        );

        await tester.pumpWidget(
          createTestWidget(
            child: const AccountAccessScreen(),
            controller: controller,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Profile Label Only'), findsOneWidget);
        expect(
          find.textContaining('unconfirmed by LuCI session API'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'STRICTLY READ-ONLY: Screen contains zero mutation or password changing inputs',
      (tester) async {
        final sample = createSampleSnapshot();
        final controller = MockAccountAccessController(
          AccountAccessState(snapshot: sample),
        );

        await tester.pumpWidget(
          createTestWidget(
            child: const AccountAccessScreen(),
            controller: controller,
          ),
        );
        await tester.pumpAndSettle();

        // Verify no password fields or text fields exist
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(TextFormField), findsNothing);

        // Verify no mutation action buttons exist
        expect(find.text('Save'), findsNothing);
        expect(find.text('Apply'), findsNothing);
        expect(find.text('Change Password'), findsNothing);
        expect(find.text('Reboot'), findsNothing);
        expect(find.text('Delete'), findsNothing);
        expect(find.text('Create User'), findsNothing);
        expect(find.text('Edit'), findsNothing);
      },
    );

    testWidgets('Renders properly in Dark Theme without errors or overflows', (
      tester,
    ) async {
      final sample = createSampleSnapshot();
      final controller = MockAccountAccessController(
        AccountAccessState(snapshot: sample),
      );

      await tester.pumpWidget(
        createTestWidget(
          child: const AccountAccessScreen(),
          controller: controller,
          themeMode: ThemeMode.dark,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AccountAccessScreen), findsOneWidget);
      expect(find.text('Router Accounts'), findsOneWidget);
      expect(find.text('root'), findsAtLeastNWidgets(1));
    });

    testWidgets('Renders initial loading view correctly', (tester) async {
      final controller = MockAccountAccessController(
        const AccountAccessState(isLoading: true, snapshot: null),
      );

      await tester.pumpWidget(
        createTestWidget(
          child: const AccountAccessScreen(),
          controller: controller,
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsAtLeastNWidgets(1));
      expect(
        find.text('Auditing account identity & effective permissions...'),
        findsOneWidget,
      );
    });

    testWidgets('Renders error view and retry button when inspection fails', (
      tester,
    ) async {
      final controller = MockAccountAccessController(
        const AccountAccessState(
          isLoading: false,
          snapshot: null,
          errorMessage: 'Connection timed out while querying router ubus',
        ),
      );

      await tester.pumpWidget(
        createTestWidget(
          child: const AccountAccessScreen(),
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Inspection Error'), findsOneWidget);
      expect(
        find.text('Connection timed out while querying router ubus'),
        findsOneWidget,
      );

      final retryButton = find.text('Retry Inspection');
      expect(retryButton, findsOneWidget);

      await tester.tap(retryButton);
      expect(controller.refreshCalled, isTrue);
    });

    testWidgets('Diagnostics accordion expands and collapses upon tap', (
      tester,
    ) async {
      final sample = createSampleSnapshot();
      final controller = MockAccountAccessController(
        AccountAccessState(snapshot: sample),
      );

      await tester.pumpWidget(
        createTestWidget(
          child: const AccountAccessScreen(),
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();

      // Ensure diagnostics section is visible
      await tester.ensureVisible(
        find.byKey(const ValueKey('diagnostics_accordion_toggle')),
      );
      await tester.pumpAndSettle();

      // Initially collapsed
      expect(find.text('Show'), findsOneWidget);
      expect(find.text('Model: x86/64 TestPlatform'), findsNothing);

      // Tap to expand
      await tester.tap(
        find.byKey(const ValueKey('diagnostics_accordion_toggle')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hide'), findsOneWidget);
      expect(find.text('Model: x86/64 TestPlatform'), findsOneWidget);
    });

    testWidgets(
      'Renders all areas and probe telemetry in Chinese locale (zh)',
      (tester) async {
        final sample = createSampleSnapshot();
        final controller = MockAccountAccessController(
          AccountAccessState(snapshot: sample),
        );

        await tester.pumpWidget(
          createTestWidget(
            child: const AccountAccessScreen(),
            controller: controller,
            locale: const Locale('zh'),
          ),
        );
        await tester.pumpAndSettle();

        // Master View checks in Chinese
        expect(find.text('路由器账户'), findsOneWidget);
        expect(find.text('活跃'), findsOneWidget);
        expect(find.text('主管理员 (UID 0)'), findsOneWidget);
        expect(find.text('未配置其他账户'), findsOneWidget);
        expect(find.text('查看权限'), findsOneWidget);

        // Open detail screen
        await tester.tap(find.text('查看权限'));
        await tester.pumpAndSettle();

        expect(find.byType(AccountDetailScreen), findsOneWidget);
        expect(find.text('访问与权限 (root)'), findsOneWidget);
        expect(find.text('当前账户'), findsOneWidget);
        expect(find.text('认证与连接方式'), findsOneWidget);
        expect(find.text('LuCI RPC 权限'), findsOneWidget);
        expect(find.text('SSH 访问'), findsOneWidget);
        expect(find.text('其他已验证的访问能力'), findsOneWidget);

        // Current Account Details in Chinese
        expect(find.text('路由器已确认'), findsOneWidget);
        expect(find.text('身份验证方式'), findsOneWidget);
        expect(find.text('LuCI RPC 令牌 (sysauth)'), findsOneWidget);
        expect(find.text('已认证且活跃'), findsOneWidget);
        expect(find.text('通过经过身份验证的 UNIX Shell 独立确认 (root)'), findsOneWidget);

        // Methods in Chinese
        expect(find.text('LuCI HTTP/HTTPS 网页会话'), findsOneWidget);
        expect(find.text('LuCI JSON-RPC (ubus)'), findsOneWidget);
        expect(find.text('SSH 控制台访问'), findsOneWidget);

        // Capabilities in Chinese
        expect(find.text('系统信息'), findsOneWidget);
        expect(find.text('网络接口与状态'), findsOneWidget);
        expect(find.text('防火墙规则与安全'), findsOneWidget);

        // Subsystems in Chinese
        expect(find.text('UCI 配置系统'), findsOneWidget);
        expect(find.text('防火墙引擎后端'), findsOneWidget);
      },
    );
  });
}
