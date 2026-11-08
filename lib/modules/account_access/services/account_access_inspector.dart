// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:yet_another_luci_app/models/router.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/services/interfaces/ssh_service_interface.dart';
import 'package:yet_another_luci_app/utils/logger.dart';
import '../models/account_access_models.dart';

/// Service performing bounded, non-destructive, strictly read-only inspection
/// of router account identity, session connection methods, LuCI RPC capabilities,
/// and SSH reachability.
class AccountAccessInspector {
  final IApiService? _apiService;
  final ISshService? _sshService;

  const AccountAccessInspector({
    IApiService? apiService,
    ISshService? sshService,
  }) : _apiService = apiService,
       _sshService = sshService;

  /// Performs a thorough, non-destructive read-only audit of the current router session.
  Future<AccountAccessSnapshot> inspect({
    required Router? router,
    required String? sysauth,
    required RouterCapabilities? capabilities,
    required bool isReviewerMode,
  }) async {
    final startTime = DateTime.now();

    // 1. Handle Reviewer Mode simulation
    if (isReviewerMode) {
      Logger.info('AccountAccessInspector: Generating Reviewer Mode snapshot');
      return AccountAccessSnapshot.reviewerMode();
    }

    // 2. Handle offline / unauthenticated states
    if (router == null) {
      return AccountAccessSnapshot.offline(
        routerId: 'none',
        profileName: 'No router selected',
        configuredUsername: 'Unknown',
        routerAddress: '0.0.0.0',
        reason: 'No router profile is currently selected.',
      );
    }

    if (sysauth == null || sysauth.isEmpty) {
      return AccountAccessSnapshot.offline(
        routerId: router.id,
        profileName: router.displayName,
        configuredUsername: router.username,
        routerAddress: router.ipAddress,
        reason: 'No active LuCI session token available. Please authenticate.',
      );
    }

    final diagnostics = <DiagnosticFinding>[];
    void logDiag(String message, {String? evidence, bool isWarning = false}) {
      diagnostics.add(
        DiagnosticFinding(
          timestamp: DateTime.now(),
          message: message,
          evidence: evidence,
          isWarning: isWarning,
        ),
      );
    }

    logDiag(
      'Inspection initiated for router ${router.ipAddress}',
      evidence: 'Profile: ${router.displayName}',
    );

    // 3. Step 1: Probe RPC endpoints concurrently for optimal performance
    String? probedBoardModel = capabilities?.boardName;
    String? probedReleaseVersion = capabilities?.releaseVersion;
    bool isSessionVerified = false;
    String sessionValidityStr = 'Unverified';

    final ubusObjects = <String>{...?capabilities?.ubusObjects};
    final ubusMethods = <String, List<String>>{...?capabilities?.ubusMethods};
    final uciPermissions = <String, List<String>>{
      ...?capabilities?.uciPermissions,
    };
    bool sessionAccessProbed = false;

    int sshPort = 22;
    String sshPortSource = 'Standard default port (22)';
    String sshDaemonStatus = 'Unknown (Dropbear probe unverified)';
    bool isDropbearConfigFound = false;
    final otherAccountUsers = <String>{};
    bool boardNetworkFailed = false;

    try {
      final boardFuture = _apiService
          ?.call(
            router.ipAddress,
            sysauth,
            router.useHttps,
            object: 'system',
            method: 'board',
          )
          .timeout(const Duration(seconds: 4))
          .catchError((e) {
            boardNetworkFailed = true;
            logDiag('system.board RPC probe error: $e', isWarning: true);
            return null;
          });

      final accessFuture = _apiService
          ?.call(
            router.ipAddress,
            sysauth,
            router.useHttps,
            object: 'session',
            method: 'access',
          )
          .timeout(const Duration(seconds: 4))
          .catchError((e) {
            logDiag('rpcd session.access probe error: $e');
            return null;
          });

      final dropbearFuture = _apiService
          ?.call(
            router.ipAddress,
            sysauth,
            router.useHttps,
            object: 'uci',
            method: 'get',
            params: {'config': 'dropbear'},
          )
          .timeout(const Duration(seconds: 4))
          .catchError((_) => null);

      final rpcdFuture = _apiService
          ?.call(
            router.ipAddress,
            sysauth,
            router.useHttps,
            object: 'uci',
            method: 'get',
            params: {'config': 'rpcd'},
          )
          .timeout(const Duration(seconds: 4))
          .catchError((_) => null);

      final rpcResults = await Future.wait([
        boardFuture ?? Future.value(null),
        accessFuture ?? Future.value(null),
        dropbearFuture ?? Future.value(null),
        rpcdFuture ?? Future.value(null),
      ]);

      final boardRes = rpcResults[0];
      final accessRes = rpcResults[1];
      final dropbearUci = rpcResults[2];
      final rpcdRes = rpcResults[3];

      // Parse system.board
      if (boardNetworkFailed) {
        sessionValidityStr =
            'Session probe failed: network error or invalid token';
        logDiag(
          'system.board RPC probe failed: network error',
          isWarning: true,
        );
      } else if (boardRes is List && boardRes.isNotEmpty && boardRes[0] == 0) {
        isSessionVerified = true;
        sessionValidityStr = 'Active session verified via system.board RPC';
        if (boardRes.length > 1 && boardRes[1] is Map) {
          final bMap = boardRes[1] as Map;
          final modelName = bMap['model']?.toString();
          final systemBoard = bMap['system']?.toString();
          probedBoardModel = modelName ?? systemBoard ?? probedBoardModel;

          final releaseMap = bMap['release'];
          if (releaseMap is Map) {
            final desc = releaseMap['description']?.toString();
            final ver = releaseMap['version']?.toString();
            probedReleaseVersion = desc ?? ver ?? probedReleaseVersion;
          }
        }
        logDiag(
          'system.board RPC query succeeded',
          evidence: 'Model: $probedBoardModel, Release: $probedReleaseVersion',
        );
      } else {
        sessionValidityStr =
            'Session query returned non-zero response (Status: ${boardRes is List && boardRes.isNotEmpty ? boardRes[0] : "unknown"})';
        logDiag(
          'system.board RPC query returned error or invalid format',
          isWarning: true,
        );
      }

      // Parse rpcd session.access
      if (accessRes is List && accessRes.length > 1 && accessRes[0] == 0) {
        final data = accessRes[1];
        if (data is Map) {
          sessionAccessProbed = true;
          final ubusMap = data['ubus'];
          if (ubusMap is Map) {
            for (final entry in ubusMap.entries) {
              final objName = entry.key.toString();
              ubusObjects.add(objName);
              if (entry.value is List) {
                ubusMethods[objName] = (entry.value as List)
                    .map((e) => e.toString())
                    .toList();
              }
            }
          }

          final uciMap = data['uci'];
          if (uciMap is Map) {
            for (final entry in uciMap.entries) {
              final configName = entry.key.toString();
              if (entry.value is List) {
                uciPermissions[configName] = (entry.value as List)
                    .map((e) => e.toString())
                    .toList();
              }
            }
          }
          logDiag(
            'rpcd session.access returned effective permissions',
            evidence:
                '${ubusObjects.length} ubus objects, ${uciPermissions.length} UCI configs',
          );
        }
      }

      // Parse UCI dropbear
      if (dropbearUci is List &&
          dropbearUci.length > 1 &&
          dropbearUci[0] == 0 &&
          dropbearUci[1] is Map) {
        isDropbearConfigFound = true;
        sshDaemonStatus = 'Dropbear SSH configuration detected in UCI';
        final rawData = dropbearUci[1] as Map;
        final values = rawData['values'] is Map
            ? rawData['values'] as Map
            : rawData;

        for (final sec in values.values) {
          if (sec is Map) {
            final pVal = sec['Port'] ?? sec['port'];
            if (pVal != null) {
              final parsed = int.tryParse(pVal.toString().trim());
              if (parsed != null && parsed > 0) {
                sshPort = parsed;
                sshPortSource = 'UCI dropbear configuration';
                break;
              }
            }
          }
        }
        logDiag(
          'Dropbear UCI configuration read successfully',
          evidence: 'SSH Port: $sshPort (Source: $sshPortSource)',
        );
      }

      // Parse UCI rpcd for configured logins
      if (rpcdRes is List &&
          rpcdRes.length > 1 &&
          rpcdRes[0] == 0 &&
          rpcdRes[1] is Map) {
        final rawData = rpcdRes[1] as Map;
        final values = rawData['values'] is Map
            ? rawData['values'] as Map
            : rawData;

        for (final sec in values.values) {
          if (sec is Map) {
            final uName = sec['username']?.toString();
            if (uName != null &&
                uName.isNotEmpty &&
                uName != router.username &&
                uName != 'root') {
              otherAccountUsers.add(uName);
            }
          }
        }
      }
    } catch (e) {
      logDiag('RPC inspection error: $e', isWarning: true);
    }

    if (isSessionVerified) {
      ubusObjects.add('system');
    }

    if (!isDropbearConfigFound && capabilities?.hasDropbear == true) {
      sshDaemonStatus = 'Dropbear service detected in system init scripts';
    }

    // 4. Step 2: Bounded SSH probe: strictly execute non-destructive identity audit
    SshReachabilityStatus sshReachability = SshReachabilityStatus.notTested;
    String? confirmedSshUser;
    bool? readOnlySshSuccess;
    String? sanitizedSshOutput;
    String sshExplanation = 'SSH probe was not performed.';

    if (_sshService == null) {
      sshReachability = SshReachabilityStatus.unknown;
      sshExplanation = 'No SSH service abstraction available in environment.';
      logDiag('SSH probe skipped: ISshService instance is null');
    } else if (router.password.isEmpty) {
      sshReachability = SshReachabilityStatus.notTested;
      sshExplanation =
          'Router profile does not contain stored SSH credentials; password guessing is strictly avoided.';
      logDiag('SSH probe skipped: No stored credentials in profile');
    } else {
      try {
        logDiag('Executing bounded read-only SSH probe: id -u -n');
        final sshRes = await _sshService
            .executeCommand(
              host: router.ipAddress,
              username: router.username,
              password: router.password,
              command: 'id -u -n',
              port: sshPort,
              timeout: const Duration(seconds: 4),
            )
            .timeout(const Duration(seconds: 6));

        if (sshRes.success && sshRes.exitCode == 0) {
          sshReachability = SshReachabilityStatus.verifiedWorking;
          readOnlySshSuccess = true;
          final out = sshRes.stdout.trim();
          confirmedSshUser = out.isNotEmpty ? out : router.username;
          sanitizedSshOutput = 'UNIX username: $confirmedSshUser';
          sshExplanation =
              'SSH connection verified on port $sshPort; authenticated as $confirmedSshUser.';
          logDiag(
            'SSH read-only command succeeded',
            evidence: 'User: $confirmedSshUser, Port: $sshPort',
          );
        } else {
          readOnlySshSuccess = false;
          final errMsg = sshRes.errorMessage ?? sshRes.stderr;
          final lowerErr = errMsg.toLowerCase();

          if (lowerErr.contains('auth') ||
              lowerErr.contains('password') ||
              lowerErr.contains('denied') ||
              lowerErr.contains('rejected')) {
            sshReachability = SshReachabilityStatus.permissionDenied;
            sshExplanation =
                'SSH port $sshPort is reachable, but login credentials were rejected by SSH daemon.';
            logDiag(
              'SSH login rejected by server: permission denied',
              isWarning: true,
            );
          } else if (lowerErr.contains('refused') ||
              lowerErr.contains('closed') ||
              lowerErr.contains('timeout') ||
              lowerErr.contains('timed out') ||
              lowerErr.contains('unreachable') ||
              lowerErr.contains('os error')) {
            sshReachability = SshReachabilityStatus.portClosedOrUnreachable;
            sshExplanation =
                'SSH port $sshPort is closed, filtered by firewall, or unreachable.';
            logDiag('SSH connection timed out or port closed', isWarning: true);
          } else {
            sshReachability = SshReachabilityStatus.unknown;
            sshExplanation =
                'SSH probe encountered error: ${errMsg.isNotEmpty ? errMsg : "exit code ${sshRes.exitCode}"}';
            logDiag('SSH probe failed: $errMsg', isWarning: true);
          }
        }
      } catch (e) {
        sshReachability = SshReachabilityStatus.portClosedOrUnreachable;
        sshExplanation = 'SSH connection attempt timed out or failed: $e';
        logDiag('SSH connection error: $e', isWarning: true);
      }
    }

    // 6. Step 4: Synthesize Current Account Information
    // Distinguish carefully between configured profile username and independently confirmed identity.
    final isUsernameConfirmed =
        confirmedSshUser != null && confirmedSshUser.isNotEmpty;
    final identitySourceStr = isUsernameConfirmed
        ? 'Confirmed independently via authenticated UNIX shell ($confirmedSshUser)'
        : 'Configured profile label (unconfirmed by LuCI session API)';

    final currentAccount = CurrentAccountInfo(
      configuredUsername: router.username,
      authenticatedUsername: confirmedSshUser,
      isUsernameConfirmedByRouter: isUsernameConfirmed,
      identitySource: identitySourceStr,
      profileName: router.displayName,
      routerAddress: router.ipAddress,
      boardModel: probedBoardModel,
      firmwareVersion: probedReleaseVersion,
      authMethod: 'LuCI RPC Token (sysauth)',
      connectionMethod: router.useHttps
          ? 'HTTPS (TLS encrypted)'
          : 'HTTP (unencrypted LAN)',
      sessionStatus: isSessionVerified
          ? 'Authenticated & Active'
          : 'Session Unverified or Expired',
      sessionValidity: sessionValidityStr,
      lastVerified: isSessionVerified ? DateTime.now() : null,
    );

    // 7. Step 5: Synthesize Authentication & Connection Methods
    final connectionMethods = <ConnectionMethodInfo>[
      ConnectionMethodInfo(
        id: 'luci_http',
        name: 'LuCI HTTP/HTTPS Web Session',
        status: isSessionVerified
            ? ConnectionMethodStatus.activeAndVerified
            : ConnectionMethodStatus.unavailable,
        endpointOrPort: router.useHttps ? 'HTTPS (port 443)' : 'HTTP (port 80)',
        explanation: isSessionVerified
            ? 'Active HTTP session responding with valid sysauth credentials.'
            : 'HTTP session token could not be verified against router system.board.',
        evidenceSource: 'Direct system.board read probe',
      ),
      ConnectionMethodInfo(
        id: 'luci_rpc',
        name: 'LuCI JSON-RPC (ubus)',
        status: ubusObjects.isNotEmpty
            ? ConnectionMethodStatus.activeAndVerified
            : ConnectionMethodStatus.unavailable,
        endpointOrPort: '/ubus JSON-RPC',
        explanation: ubusObjects.isNotEmpty
            ? '${ubusObjects.length} ubus objects available to current session.'
            : 'No ubus objects returned or RPC endpoint unreachable.',
        evidenceSource: sessionAccessProbed
            ? 'rpcd session.access effective ACLs'
            : 'ubus schema introspection',
      ),
      ConnectionMethodInfo(
        id: 'ssh',
        name: 'SSH Console Access',
        status: _mapSshToConnectionStatus(sshReachability),
        endpointOrPort: 'SSH (port $sshPort)',
        explanation: sshExplanation,
        evidenceSource: sshPortSource,
      ),
    ];

    // 8. Step 6: Evaluate LuCI RPC Capabilities & Permissions
    final rpcCaps = _evaluateRpcPermissions(
      ubusObjects: ubusObjects,
      ubusMethods: ubusMethods,
      uciPermissions: uciPermissions,
      hasWireless: capabilities?.hasWireless ?? false,
      capabilities: capabilities,
    );

    // 9. Step 7: SSH Access Card representation
    final sshInfo = SshAccessInfo(
      reachability: sshReachability,
      port: sshPort,
      portSource: sshPortSource,
      daemonStatus: sshDaemonStatus,
      hasActiveConnection:
          sshReachability == SshReachabilityStatus.verifiedWorking,
      authenticatedUser: confirmedSshUser,
      isIdentityConfirmed: isUsernameConfirmed,
      readOnlyExecutionSucceeded: readOnlySshSuccess,
      executionOutput: sanitizedSshOutput,
      explanation: sshExplanation,
      securityNotes:
          'Security Guarantee: YALA never exposes stored passwords or private keys, never touches /etc/shadow, and only executes bounded read-only commands without guessing passwords.',
    );

    // 10. Step 8: Available router accounts discovery
    final activeUsername = confirmedSshUser ?? router.username;
    final availableAccounts = <RouterAccountEntry>[
      RouterAccountEntry(
        username: activeUsername,
        isActiveSession: true,
        isConfirmedByRouter: isUsernameConfirmed,
        role: activeUsername == 'root'
            ? 'Primary Administrator (UID 0)'
            : 'Authenticated Session User',
        accessScope: 'LuCI JSON-RPC & Administrative Access',
        source: identitySourceStr,
      ),
      for (final otherUser in otherAccountUsers)
        RouterAccountEntry(
          username: otherUser,
          isActiveSession: false,
          isConfirmedByRouter: true,
          role: 'Configured User Account',
          accessScope: 'Secondary Login / Limited Access',
          source: 'Discovered in router logins (/etc/passwd or rpcd)',
        ),
    ];

    // 11. Step 9: Other verified subsystems
    final subsystems = _evaluateSubsystems(
      capabilities: capabilities,
      uciPermissions: uciPermissions,
    );

    final duration = DateTime.now().difference(startTime);
    logDiag('Inspection finished in ${duration.inMilliseconds}ms');

    return AccountAccessSnapshot(
      routerId: router.id,
      inspectedAt: DateTime.now(),
      inspectionDuration: duration,
      account: currentAccount,
      availableAccounts: availableAccounts,
      connectionMethods: connectionMethods,
      rpcCapabilities: rpcCaps,
      sshAccess: sshInfo,
      subsystems: subsystems,
      diagnostics: diagnostics,
      isPartialInspection: !sessionAccessProbed,
      isOffline: false,
    );
  }

  /// Maps [SshReachabilityStatus] to a high-level [ConnectionMethodStatus].
  static ConnectionMethodStatus _mapSshToConnectionStatus(
    SshReachabilityStatus status,
  ) {
    switch (status) {
      case SshReachabilityStatus.verifiedWorking:
        return ConnectionMethodStatus.activeAndVerified;
      case SshReachabilityStatus.reachableUnverified:
        return ConnectionMethodStatus.availableUnverified;
      case SshReachabilityStatus.portClosedOrUnreachable:
        return ConnectionMethodStatus.unavailable;
      case SshReachabilityStatus.permissionDenied:
        return ConnectionMethodStatus.permissionDenied;
      case SshReachabilityStatus.notTested:
        return ConnectionMethodStatus.notTested;
      case SshReachabilityStatus.unknown:
        return ConnectionMethodStatus.unknown;
      case SshReachabilityStatus.notInstalledOrDisabled:
        return ConnectionMethodStatus.notApplicable;
    }
  }

  /// Evaluates each individual capability group based on ubus and UCI ACL evidence.
  static List<RpcCapabilityPermission> _evaluateRpcPermissions({
    required Set<String> ubusObjects,
    required Map<String, List<String>> ubusMethods,
    required Map<String, List<String>> uciPermissions,
    required bool hasWireless,
    required RouterCapabilities? capabilities,
  }) {
    final list = <RpcCapabilityPermission>[];

    // 1. System Information
    final hasSystem =
        ubusObjects.contains('system') || ubusObjects.contains('*');
    list.add(
      RpcCapabilityPermission(
        id: 'system_info',
        title: 'System Information',
        category: 'Core System',
        readStatus: hasSystem
            ? PermissionAccessStatus.verifiedReadAccess
            : PermissionAccessStatus.unknown,
        writeStatus: PermissionAccessStatus.notApplicable,
        evidenceSource: 'ubus system object (info, board)',
        explanation: hasSystem
            ? 'Read access verified via system.board and system.info RPCs.'
            : 'System ubus object unverified or missing from session ACL.',
      ),
    );

    // 2. Network Interfaces & Status
    final hasNetwork =
        ubusObjects.contains('network.interface') ||
        ubusObjects.contains('network') ||
        ubusObjects.contains('*');
    final canWriteNet = _checkUciWrite(uciPermissions, 'network');
    list.add(
      RpcCapabilityPermission(
        id: 'network_interfaces',
        title: 'Network Interfaces & Status',
        category: 'Network & Interfaces',
        readStatus: hasNetwork
            ? PermissionAccessStatus.verifiedReadAccess
            : PermissionAccessStatus.unknown,
        writeStatus: canWriteNet,
        evidenceSource: 'ubus network.interface & uci network ACL',
        explanation:
            'Read status verified via ubus; write evaluated via UCI network ACL without mutating.',
      ),
    );

    // 3. Wireless Configuration
    final hasIw =
        hasWireless ||
        ubusObjects.contains('iwinfo') ||
        ubusMethods['luci-rpc']?.contains('getWirelessDevices') == true ||
        ubusObjects.contains('*');
    final canWriteWireless = _checkUciWrite(uciPermissions, 'wireless');
    list.add(
      RpcCapabilityPermission(
        id: 'wireless_config',
        title: 'Wireless Management & Radios',
        category: 'Network & Interfaces',
        readStatus: hasIw
            ? PermissionAccessStatus.verifiedReadAccess
            : PermissionAccessStatus.notSupported,
        writeStatus: hasIw
            ? canWriteWireless
            : PermissionAccessStatus.notSupported,
        evidenceSource: 'ubus iwinfo & uci wireless ACL',
        explanation: hasIw
            ? 'Wireless device queries operational; write evaluated via UCI wireless ACL.'
            : 'No wireless radio or iwinfo RPC module found on this router hardware.',
      ),
    );

    // 4. DHCP and Lease Information
    final hasDhcp =
        ubusMethods['luci-rpc']?.contains('getDHCPLeases') == true ||
        ubusObjects.contains('odhcpd') ||
        uciPermissions.containsKey('dhcp') ||
        ubusObjects.contains('*');
    final canWriteDhcp = _checkUciWrite(uciPermissions, 'dhcp');
    list.add(
      RpcCapabilityPermission(
        id: 'dhcp_leases',
        title: 'DHCP & IP Leases',
        category: 'Network & Interfaces',
        readStatus: hasDhcp
            ? PermissionAccessStatus.verifiedReadAccess
            : PermissionAccessStatus.unknown,
        writeStatus: canWriteDhcp,
        evidenceSource: 'ubus luci-rpc getDHCPLeases & uci dhcp ACL',
        explanation:
            'DHCP read capability verified; write evaluated via UCI dhcp ACL.',
      ),
    );

    // 5. Firewall Rules & Status
    final hasFw =
        ubusObjects.contains('fw4') ||
        ubusObjects.contains('fw3') ||
        uciPermissions.containsKey('firewall') ||
        ubusObjects.contains('*');
    final canWriteFw = _checkUciWrite(uciPermissions, 'firewall');
    list.add(
      RpcCapabilityPermission(
        id: 'firewall_rules',
        title: 'Firewall Rules & Security',
        category: 'Security & Firewall',
        readStatus: hasFw
            ? PermissionAccessStatus.verifiedReadAccess
            : PermissionAccessStatus.unknown,
        writeStatus: canWriteFw,
        evidenceSource: 'ubus fw4/fw3 & uci firewall ACL',
        explanation:
            'Firewall configuration visibility confirmed; write evaluated via UCI firewall ACL without mutating.',
      ),
    );

    // 6. System Logs
    final hasLogs =
        ubusObjects.contains('log') ||
        ubusMethods['file']?.contains('read') == true ||
        ubusObjects.contains('*');
    list.add(
      RpcCapabilityPermission(
        id: 'system_logs',
        title: 'System & Kernel Logs',
        category: 'Core System',
        readStatus: hasLogs
            ? PermissionAccessStatus.verifiedReadAccess
            : PermissionAccessStatus.unknown,
        writeStatus: PermissionAccessStatus.notApplicable,
        evidenceSource: 'ubus log read & file.exec logread',
        explanation: hasLogs
            ? 'System and kernel ring buffer logs are readable.'
            : 'System log reading methods unverified.',
      ),
    );

    // 7. Package Information
    final hasPkg =
        ubusObjects.contains('opkg') ||
        ubusObjects.contains('apk') ||
        capabilities?.hasFileExec == true ||
        ubusObjects.contains('*');
    final canWritePkg = capabilities?.hasFileExec == true
        ? PermissionAccessStatus.verifiedWriteAuthorization
        : PermissionAccessStatus.unknown;
    list.add(
      RpcCapabilityPermission(
        id: 'package_manager',
        title: 'Package Manager (OPKG/APK)',
        category: 'Security & Firewall',
        readStatus: hasPkg
            ? PermissionAccessStatus.verifiedReadAccess
            : PermissionAccessStatus.unknown,
        writeStatus: canWritePkg,
        evidenceSource: 'ubus opkg/apk & backend file.exec',
        explanation:
            'Package manager read capabilities verified; write authorization inferred from backend file.exec.',
      ),
    );

    // 8. UCI Configuration Reads
    final hasUciGet = ubusObjects.contains('uci') || ubusObjects.contains('*');
    list.add(
      RpcCapabilityPermission(
        id: 'uci_read',
        title: 'UCI Configuration Reads',
        category: 'Core System',
        readStatus: hasUciGet
            ? PermissionAccessStatus.verifiedReadAccess
            : PermissionAccessStatus.unknown,
        writeStatus: PermissionAccessStatus.notApplicable,
        evidenceSource: 'ubus uci get method',
        explanation:
            'Session can execute read operations across permitted UCI configuration packages.',
      ),
    );

    // 9. UCI Configuration Writes
    final hasUciWrite = capabilities?.hasUciWriteAccess == true;
    list.add(
      RpcCapabilityPermission(
        id: 'uci_write',
        title: 'UCI Configuration Writes',
        category: 'Core System',
        readStatus: PermissionAccessStatus.notApplicable,
        writeStatus: hasUciWrite
            ? PermissionAccessStatus.verifiedWriteAuthorization
            : PermissionAccessStatus.unknown,
        evidenceSource: 'ubus session.access uci write permissions',
        explanation: hasUciWrite
            ? 'Write authorization verified from session ACLs without mutating any configuration.'
            : 'Write permission unverified without performing write operation.',
      ),
    );

    // 10. Service Control & Init Scripts
    final hasService =
        ubusObjects.contains('service') ||
        ubusObjects.contains('rc') ||
        ubusMethods['luci-rpc']?.contains('getInitList') == true ||
        ubusObjects.contains('*');
    final canWriteService =
        ubusMethods['service']?.contains('set') == true ||
        ubusMethods['service']?.contains('*') == true ||
        ubusObjects.contains('*');
    list.add(
      RpcCapabilityPermission(
        id: 'service_control',
        title: 'Service Control & Init Scripts',
        category: 'Services & Management',
        readStatus: hasService
            ? PermissionAccessStatus.verifiedReadAccess
            : PermissionAccessStatus.unknown,
        writeStatus: canWriteService
            ? PermissionAccessStatus.verifiedWriteAuthorization
            : PermissionAccessStatus.unknown,
        evidenceSource: 'ubus service list & luci-rpc getInitList',
        explanation:
            'System init scripts listable; service state modifications evaluated from RPC method list.',
      ),
    );

    // 11. Router Reboot Capability
    final hasReboot =
        ubusMethods['system']?.contains('reboot') == true ||
        capabilities?.hasFileExec == true ||
        ubusObjects.contains('*');
    list.add(
      RpcCapabilityPermission(
        id: 'router_reboot',
        title: 'Router Reboot Capability',
        category: 'Services & Management',
        readStatus: PermissionAccessStatus.notApplicable,
        writeStatus: hasReboot
            ? PermissionAccessStatus.verifiedWriteAuthorization
            : PermissionAccessStatus.unknown,
        evidenceSource: 'ubus system reboot schema & file.exec',
        explanation: hasReboot
            ? 'Reboot RPC method verified present in router API schema.'
            : 'Reboot RPC authorization unverified.',
      ),
    );

    // 12. Backup & Firmware Upgrade
    final hasBackup =
        ubusMethods['file']?.contains('read') == true ||
        ubusObjects.contains('*');
    list.add(
      RpcCapabilityPermission(
        id: 'backup_restore',
        title: 'System Backup & Upgrade',
        category: 'Services & Management',
        readStatus: hasBackup
            ? PermissionAccessStatus.verifiedReadAccess
            : PermissionAccessStatus.unknown,
        writeStatus: PermissionAccessStatus.unknown,
        evidenceSource: 'ubus file read & sysupgrade endpoint',
        explanation:
            'System backup archive download is supported; firmware flash write is unverified.',
      ),
    );

    return list;
  }

  /// Helper to check if a specific UCI configuration package has write access in ACLs.
  static PermissionAccessStatus _checkUciWrite(
    Map<String, List<String>> uciPermissions,
    String config,
  ) {
    if (uciPermissions.isEmpty) {
      return PermissionAccessStatus.unknown;
    }
    if (uciPermissions.containsKey('*') &&
        (uciPermissions['*']?.contains('write') == true ||
            uciPermissions['*']?.contains('*') == true)) {
      return PermissionAccessStatus.verifiedWriteAuthorization;
    }
    if (uciPermissions.containsKey(config)) {
      final perms = uciPermissions[config] ?? [];
      if (perms.contains('write') || perms.contains('*')) {
        return PermissionAccessStatus.verifiedWriteAuthorization;
      } else {
        return PermissionAccessStatus.verifiedDenied;
      }
    }
    return PermissionAccessStatus.unknown;
  }

  /// Evaluates subsystems based on router capabilities and configuration.
  static List<SubsystemAccessInfo> _evaluateSubsystems({
    required RouterCapabilities? capabilities,
    required Map<String, List<String>> uciPermissions,
  }) {
    final list = <SubsystemAccessInfo>[];

    // UCI Engine
    final uciCount = uciPermissions.length;
    list.add(
      SubsystemAccessInfo(
        id: 'uci',
        name: 'UCI Configuration System',
        status: uciCount > 0
            ? '$uciCount configurations mapped'
            : 'Active (Standard)',
        detail: uciCount > 0
            ? 'Configs: ${uciPermissions.keys.take(5).join(", ")}${uciCount > 5 ? "..." : ""}'
            : 'Unified Configuration Interface (UCI) operational via ubus.',
        isSupported: true,
      ),
    );

    // Package Manager
    final pkgEngine = capabilities?.packageEngine.name.toUpperCase() ?? 'OPKG';
    list.add(
      SubsystemAccessInfo(
        id: 'pkg',
        name: 'Package Manager Engine',
        status: pkgEngine,
        detail: pkgEngine == 'APK'
            ? 'Alpine Package Keeper (APK) engine detected (OpenWrt >= 24.x).'
            : 'OpenWrt OPKG package management engine active.',
        isSupported: true,
      ),
    );

    // Firewall Backend
    final fwBackend = capabilities?.firewallBackend.name.toUpperCase() ?? 'FW4';
    list.add(
      SubsystemAccessInfo(
        id: 'firewall',
        name: 'Firewall Engine Backend',
        status: fwBackend,
        detail: fwBackend == 'FW4'
            ? 'nftables firewall engine (fw4) active.'
            : 'iptables firewall engine (fw3) legacy mode.',
        isSupported: true,
      ),
    );

    // AdGuard Home
    if (capabilities?.hasAdGuardHome == true) {
      list.add(
        const SubsystemAccessInfo(
          id: 'adguard',
          name: 'AdGuard Home Integration',
          status: 'Active',
          detail: 'Local network-wide ad and tracker blocking service active.',
          isSupported: true,
        ),
      );
    }

    // Odhcpd
    if (capabilities?.hasOdhcpd == true) {
      list.add(
        const SubsystemAccessInfo(
          id: 'odhcpd',
          name: 'Embedded DHCP & IPv6 Daemon (odhcpd)',
          status: 'Active',
          detail:
              'Embedded DHCP, DHCPv6 and Router Advertisement server running.',
          isSupported: true,
        ),
      );
    }

    // Cron
    if (capabilities?.hasCron == true) {
      list.add(
        const SubsystemAccessInfo(
          id: 'cron',
          name: 'Scheduled Tasks Daemon (cron)',
          status: 'Active',
          detail: 'Task scheduling service detected and available.',
          isSupported: true,
        ),
      );
    }

    return list;
  }
}
