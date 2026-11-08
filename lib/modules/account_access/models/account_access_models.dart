// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';

/// Status of an authentication or transport connection method.
enum ConnectionMethodStatus {
  /// Active and verified working through current session communication.
  activeAndVerified,

  /// Supported or available on the device, but not actively verified in this session.
  availableUnverified,

  /// Confirmed unavailable or unreachable on the router.
  unavailable,

  /// The router explicitly rejected authorization for this connection method.
  permissionDenied,

  /// The status has not been tested or probed.
  notTested,

  /// The status cannot be definitively established from available evidence.
  unknown,

  /// This connection method is not applicable to the current router environment.
  notApplicable,
}

/// Evaluation status for LuCI RPC and subsystem access permissions.
enum PermissionAccessStatus {
  /// An appropriate read-only probe succeeded and confirmed access.
  verifiedReadAccess,

  /// Authoritative evidence (such as rpcd session ACLs) confirms write permission without mutation.
  verifiedWriteAuthorization,

  /// Explicit authorization response confirms that the tested operation is denied.
  verifiedDenied,

  /// No probe has been performed.
  notTested,

  /// Evidence is insufficient, ambiguous, or write permission cannot be tested without mutating.
  unknown,

  /// The router or firmware does not provide the relevant capability.
  notSupported,

  /// This access dimension (e.g. write on logs) is not applicable.
  notApplicable,
}

/// Reachability and operational status of the SSH service.
enum SshReachabilityStatus {
  /// Successfully connected and executed a non-destructive read-only probe.
  verifiedWorking,

  /// SSH port or daemon detected, but SSH connection is not actively tested or established.
  reachableUnverified,

  /// SSH port closed, connection refused, or network timed out.
  portClosedOrUnreachable,

  /// SSH daemon reachable, but credentials were rejected or permission denied.
  permissionDenied,

  /// SSH access has not been tested (e.g., credentials absent or test intentionally deferred).
  notTested,

  /// SSH state cannot be determined safely.
  unknown,

  /// SSH service (e.g. Dropbear) is not installed or explicitly disabled.
  notInstalledOrDisabled,
}

/// Representation of the currently authenticated router session and identity.
@immutable
class CurrentAccountInfo {
  /// The username configured in the local router profile (e.g. 'root').
  final String configuredUsername;

  /// The authenticated username confirmed independently by the router (e.g. via UNIX shell).
  final String? authenticatedUsername;

  /// Whether the username was confirmed by the router or is only a local profile label.
  final bool isUsernameConfirmedByRouter;

  /// Safe, human-readable source explanation of the username identity.
  final String identitySource;

  /// Locally stored router profile display name.
  final String profileName;

  /// Router network address (IP or hostname).
  final String routerAddress;

  /// Router hardware board / SoC model, if available through authorized read-only sources.
  final String? boardModel;

  /// OpenWrt / firmware release version, if available.
  final String? firmwareVersion;

  /// Authentication mechanism used for current session (e.g. 'LuCI Token (sysauth)').
  final String authMethod;

  /// Current session connection transport (e.g. 'HTTPS (TLS)' or 'HTTP (LAN plaintext)').
  final String connectionMethod;

  /// High-level session authentication status.
  final String sessionStatus;

  /// Detailed validity confirmation of the active session.
  final String sessionValidity;

  /// Last successful verification timestamp.
  final DateTime? lastVerified;

  const CurrentAccountInfo({
    required this.configuredUsername,
    this.authenticatedUsername,
    required this.isUsernameConfirmedByRouter,
    required this.identitySource,
    required this.profileName,
    required this.routerAddress,
    this.boardModel,
    this.firmwareVersion,
    required this.authMethod,
    required this.connectionMethod,
    required this.sessionStatus,
    required this.sessionValidity,
    this.lastVerified,
  });

  /// Returns the best available display username with appropriate qualification.
  String get displayUsername => authenticatedUsername ?? configuredUsername;
}

/// Information regarding a specific authentication or connection channel.
@immutable
class ConnectionMethodInfo {
  final String id;
  final String name;
  final ConnectionMethodStatus status;
  final String endpointOrPort;
  final String explanation;
  final String evidenceSource;
  final bool isDefinitive;

  const ConnectionMethodInfo({
    required this.id,
    required this.name,
    required this.status,
    required this.endpointOrPort,
    required this.explanation,
    required this.evidenceSource,
    this.isDefinitive = true,
  });
}

/// Inspection finding for a specific LuCI RPC or ubus capability group.
@immutable
class RpcCapabilityPermission {
  final String id;
  final String title;
  final String category;
  final PermissionAccessStatus readStatus;
  final PermissionAccessStatus writeStatus;
  final String evidenceSource;
  final String explanation;
  final bool isDefinitive;

  const RpcCapabilityPermission({
    required this.id,
    required this.title,
    required this.category,
    required this.readStatus,
    required this.writeStatus,
    required this.evidenceSource,
    required this.explanation,
    this.isDefinitive = true,
  });
}

/// Inspection results for SSH access and daemon status.
@immutable
class SshAccessInfo {
  final SshReachabilityStatus reachability;
  final int? port;
  final String portSource;
  final String daemonStatus;
  final bool hasActiveConnection;
  final String? authenticatedUser;
  final bool isIdentityConfirmed;
  final bool? readOnlyExecutionSucceeded;
  final String? executionOutput;
  final String explanation;
  final String securityNotes;

  const SshAccessInfo({
    required this.reachability,
    this.port,
    required this.portSource,
    required this.daemonStatus,
    required this.hasActiveConnection,
    this.authenticatedUser,
    required this.isIdentityConfirmed,
    this.readOnlyExecutionSucceeded,
    this.executionOutput,
    required this.explanation,
    required this.securityNotes,
  });
}

/// Inspection result for an underlying OpenWrt subsystem (UCI, packages, firewall, etc.).
@immutable
class SubsystemAccessInfo {
  final String id;
  final String name;
  final String status;
  final String detail;
  final bool isSupported;

  const SubsystemAccessInfo({
    required this.id,
    required this.name,
    required this.status,
    required this.detail,
    required this.isSupported,
  });
}

/// Represents an account entry identified on the router.
@immutable
class RouterAccountEntry {
  final String username;
  final bool isActiveSession;
  final bool isConfirmedByRouter;
  final String role;
  final String accessScope;
  final String source;
  final bool hasInteractiveShell;

  const RouterAccountEntry({
    required this.username,
    required this.isActiveSession,
    required this.isConfirmedByRouter,
    required this.role,
    required this.accessScope,
    required this.source,
    this.hasInteractiveShell = true,
  });
}

/// Sanitized audit log entry for inspector diagnostics.
@immutable
class DiagnosticFinding {
  final DateTime timestamp;
  final String message;
  final String? evidence;
  final bool isWarning;

  const DiagnosticFinding({
    required this.timestamp,
    required this.message,
    this.evidence,
    this.isWarning = false,
  });
}

/// Complete, immutable snapshot of the account access and capability audit.
@immutable
class AccountAccessSnapshot {
  final String routerId;
  final DateTime inspectedAt;
  final Duration inspectionDuration;
  final CurrentAccountInfo account;
  final List<RouterAccountEntry> availableAccounts;
  final List<ConnectionMethodInfo> connectionMethods;
  final List<RpcCapabilityPermission> rpcCapabilities;
  final SshAccessInfo sshAccess;
  final List<SubsystemAccessInfo> subsystems;
  final List<DiagnosticFinding> diagnostics;
  final bool isPartialInspection;
  final bool isOffline;
  final String? errorMessage;

  const AccountAccessSnapshot({
    required this.routerId,
    required this.inspectedAt,
    required this.inspectionDuration,
    required this.account,
    this.availableAccounts = const [],
    required this.connectionMethods,
    required this.rpcCapabilities,
    required this.sshAccess,
    required this.subsystems,
    required this.diagnostics,
    this.isPartialInspection = false,
    this.isOffline = false,
    this.errorMessage,
  });

  /// The active authenticated account entry on the router.
  RouterAccountEntry get activeAccount {
    return availableAccounts.firstWhere(
      (a) => a.isActiveSession,
      orElse: () => RouterAccountEntry(
        username: account.displayUsername,
        isActiveSession: true,
        isConfirmedByRouter: account.isUsernameConfirmedByRouter,
        role: account.displayUsername == 'root'
            ? 'Primary Administrator (UID 0)'
            : 'Authenticated User',
        accessScope: 'LuCI RPC & Administrative Access',
        source: account.identitySource,
      ),
    );
  }

  /// Other non-active accounts discovered on the router.
  List<RouterAccountEntry> get otherAccounts =>
      availableAccounts.where((a) => !a.isActiveSession).toList();

  /// Whether secondary or non-active accounts were discovered on the router.
  bool get hasOtherAccounts => otherAccounts.isNotEmpty;

  /// Factory creating an unauthenticated or offline inspection snapshot.
  factory AccountAccessSnapshot.offline({
    required String routerId,
    required String profileName,
    required String configuredUsername,
    required String routerAddress,
    String? reason,
  }) {
    final now = DateTime.now();
    return AccountAccessSnapshot(
      routerId: routerId,
      inspectedAt: now,
      inspectionDuration: Duration.zero,
      isOffline: true,
      errorMessage: reason ?? 'Router session is offline or unreachable.',
      availableAccounts: [
        RouterAccountEntry(
          username: configuredUsername,
          isActiveSession: false,
          isConfirmedByRouter: false,
          role: configuredUsername == 'root'
              ? 'Primary Administrator (Offline)'
              : 'Configured Profile User',
          accessScope: 'Session Offline',
          source: 'Local profile configuration',
        ),
      ],
      account: CurrentAccountInfo(
        configuredUsername: configuredUsername,
        authenticatedUsername: null,
        isUsernameConfirmedByRouter: false,
        identitySource: 'Locally stored profile label (unverified by router)',
        profileName: profileName,
        routerAddress: routerAddress,
        boardModel: null,
        firmwareVersion: null,
        authMethod: 'None / Inactive Session',
        connectionMethod: 'Offline',
        sessionStatus: 'Offline / Disconnected',
        sessionValidity: reason ?? 'No active session token available.',
        lastVerified: null,
      ),
      connectionMethods: const [
        ConnectionMethodInfo(
          id: 'luci_http',
          name: 'LuCI HTTP/HTTPS Session',
          status: ConnectionMethodStatus.unavailable,
          endpointOrPort: 'HTTP / HTTPS',
          explanation: 'No active session or router unreachable.',
          evidenceSource: 'Local session state',
        ),
        ConnectionMethodInfo(
          id: 'luci_rpc',
          name: 'LuCI JSON-RPC (ubus)',
          status: ConnectionMethodStatus.unavailable,
          endpointOrPort: '/ubus',
          explanation:
              'RPC endpoint unreachable without an authenticated session.',
          evidenceSource: 'Local session state',
        ),
        ConnectionMethodInfo(
          id: 'ssh',
          name: 'SSH Console Access',
          status: ConnectionMethodStatus.notTested,
          endpointOrPort: 'Port 22 (Standard)',
          explanation: 'SSH probe skipped because router session is offline.',
          evidenceSource: 'Offline safety policy',
        ),
      ],
      rpcCapabilities: const [],
      sshAccess: const SshAccessInfo(
        reachability: SshReachabilityStatus.notTested,
        port: 22,
        portSource: 'Default configuration standard',
        daemonStatus: 'Unknown (Router offline)',
        hasActiveConnection: false,
        authenticatedUser: null,
        isIdentityConfirmed: false,
        readOnlyExecutionSucceeded: null,
        explanation: 'SSH access was not probed because router is offline.',
        securityNotes:
            'YALA strictly enforces read-only access and never attempts credential guessing.',
      ),
      subsystems: const [],
      diagnostics: [
        DiagnosticFinding(
          timestamp: now,
          message: 'Inspection skipped: $reason',
          isWarning: true,
        ),
      ],
    );
  }

  /// Factory creating an inspector snapshot for Reviewer Mode.
  factory AccountAccessSnapshot.reviewerMode() {
    final now = DateTime.now();
    return AccountAccessSnapshot(
      routerId: 'mock_router_reviewer_mode',
      inspectedAt: now,
      inspectionDuration: const Duration(milliseconds: 45),
      isOffline: false,
      availableAccounts: const [
        RouterAccountEntry(
          username: 'root',
          isActiveSession: true,
          isConfirmedByRouter: true,
          role: 'Primary Administrator (UID 0)',
          accessScope: 'Full Administrative & Shell Access (Simulation)',
          source: 'Reviewer Mode Mock Provider',
        ),
      ],
      account: CurrentAccountInfo(
        configuredUsername: 'root',
        authenticatedUsername: 'root (Simulated)',
        isUsernameConfirmedByRouter: true,
        identitySource: 'Simulated Reviewer Mode session (UID 0)',
        profileName: 'OpenWrt Mock Reviewer',
        routerAddress: '192.168.1.1 (Virtual)',
        boardModel: 'x86/64 (QEMU KVM Virtual Machine)',
        firmwareVersion: 'OpenWrt 23.05.3 r23809-234f1a2efa',
        authMethod: 'Reviewer Mode Mock Authentication',
        connectionMethod: 'Internal Mock Transport (In-Memory)',
        sessionStatus: 'Active & Verified (Simulation)',
        sessionValidity: 'In-memory simulated session active',
        lastVerified: now,
      ),
      connectionMethods: const [
        ConnectionMethodInfo(
          id: 'luci_http',
          name: 'LuCI HTTP/HTTPS Session',
          status: ConnectionMethodStatus.activeAndVerified,
          endpointOrPort: 'HTTPS port 443 (Virtual)',
          explanation: 'Simulated TLS session verified via mock adapter.',
          evidenceSource: 'Reviewer Mode Service Provider',
        ),
        ConnectionMethodInfo(
          id: 'luci_rpc',
          name: 'LuCI JSON-RPC (ubus)',
          status: ConnectionMethodStatus.activeAndVerified,
          endpointOrPort: '/ubus JSON-RPC (Virtual)',
          explanation: '14 virtual ubus objects exposed and verified.',
          evidenceSource: 'Reviewer Mode Service Provider',
        ),
        ConnectionMethodInfo(
          id: 'ssh',
          name: 'SSH Console Access',
          status: ConnectionMethodStatus.activeAndVerified,
          endpointOrPort: 'Port 22 (Virtual)',
          explanation:
              'Mock SSH client executed simulated read-only command successfully.',
          evidenceSource: 'MockSshService adapter',
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
          explanation: 'Read access verified via system.board mock response.',
        ),
        RpcCapabilityPermission(
          id: 'network_interfaces',
          title: 'Network Interfaces & Status',
          category: 'Network & Interfaces',
          readStatus: PermissionAccessStatus.verifiedReadAccess,
          writeStatus: PermissionAccessStatus.verifiedWriteAuthorization,
          evidenceSource: 'ubus network.interface & uci network ACL',
          explanation:
              'Full read status and declared UCI network write authorization.',
        ),
        RpcCapabilityPermission(
          id: 'wireless_config',
          title: 'Wireless Management & Radios',
          category: 'Network & Interfaces',
          readStatus: PermissionAccessStatus.verifiedReadAccess,
          writeStatus: PermissionAccessStatus.verifiedWriteAuthorization,
          evidenceSource: 'ubus iwinfo & luci-rpc getWirelessDevices',
          explanation:
              'Read verified via iwinfo mock; write authorized via UCI wireless ACL.',
        ),
        RpcCapabilityPermission(
          id: 'dhcp_leases',
          title: 'DHCP & IP Leases',
          category: 'Network & Interfaces',
          readStatus: PermissionAccessStatus.verifiedReadAccess,
          writeStatus: PermissionAccessStatus.verifiedWriteAuthorization,
          evidenceSource: 'ubus luci-rpc getDHCPLeases & uci dhcp',
          explanation:
              'DHCP lease visibility confirmed; write authorized in UCI.',
        ),
        RpcCapabilityPermission(
          id: 'firewall_rules',
          title: 'Firewall Rules & Security',
          category: 'Security & Firewall',
          readStatus: PermissionAccessStatus.verifiedReadAccess,
          writeStatus: PermissionAccessStatus.verifiedWriteAuthorization,
          evidenceSource: 'ubus fw4 & uci firewall ACL',
          explanation:
              'Firewall overview read and write authorization verified without mutation.',
        ),
        RpcCapabilityPermission(
          id: 'system_logs',
          title: 'System & Kernel Logs',
          category: 'Core System',
          readStatus: PermissionAccessStatus.verifiedReadAccess,
          writeStatus: PermissionAccessStatus.notApplicable,
          evidenceSource: 'ubus log read & file.exec logread',
          explanation:
              'System log inspection confirmed. Write operations not applicable to logs.',
        ),
        RpcCapabilityPermission(
          id: 'package_manager',
          title: 'Package Manager (OPKG/APK)',
          category: 'Security & Firewall',
          readStatus: PermissionAccessStatus.verifiedReadAccess,
          writeStatus: PermissionAccessStatus.verifiedWriteAuthorization,
          evidenceSource: 'ubus opkg & backend file.exec',
          explanation:
              'Package manager read queries and execution permissions verified.',
        ),
        RpcCapabilityPermission(
          id: 'uci_read',
          title: 'UCI Configuration Reads',
          category: 'Core System',
          readStatus: PermissionAccessStatus.verifiedReadAccess,
          writeStatus: PermissionAccessStatus.notApplicable,
          evidenceSource: 'ubus uci get method',
          explanation:
              'Direct UCI read queries operational across all configuration packages.',
        ),
        RpcCapabilityPermission(
          id: 'uci_write',
          title: 'UCI Configuration Writes',
          category: 'Core System',
          readStatus: PermissionAccessStatus.notApplicable,
          writeStatus: PermissionAccessStatus.verifiedWriteAuthorization,
          evidenceSource: 'ubus session.access uci write permissions',
          explanation:
              'Write authorization verified via rpcd session ACL without performing writes.',
        ),
        RpcCapabilityPermission(
          id: 'service_control',
          title: 'Service Control & Init Scripts',
          category: 'Services & Management',
          readStatus: PermissionAccessStatus.verifiedReadAccess,
          writeStatus: PermissionAccessStatus.verifiedWriteAuthorization,
          evidenceSource: 'ubus service list & luci-rpc getInitList',
          explanation:
              'Init scripts enumeration and control permissions confirmed.',
        ),
        RpcCapabilityPermission(
          id: 'router_reboot',
          title: 'Router Reboot Capability',
          category: 'Services & Management',
          readStatus: PermissionAccessStatus.notApplicable,
          writeStatus: PermissionAccessStatus.verifiedWriteAuthorization,
          evidenceSource: 'ubus system reboot & file.exec /sbin/reboot',
          explanation: 'Reboot RPC method verified present in ubus schema.',
        ),
        RpcCapabilityPermission(
          id: 'backup_restore',
          title: 'System Backup & Upgrade',
          category: 'Services & Management',
          readStatus: PermissionAccessStatus.verifiedReadAccess,
          writeStatus: PermissionAccessStatus.unknown,
          evidenceSource: 'ubus file read & sysupgrade endpoint',
          explanation:
              'Backup download capability verified. Firmware flash write unverified.',
        ),
      ],
      sshAccess: const SshAccessInfo(
        reachability: SshReachabilityStatus.verifiedWorking,
        port: 22,
        portSource: 'UCI dropbear configuration (Simulated)',
        daemonStatus: 'Dropbear SSH daemon active (Simulated)',
        hasActiveConnection: true,
        authenticatedUser: 'root',
        isIdentityConfirmed: true,
        readOnlyExecutionSucceeded: true,
        executionOutput: 'uid=0(root) gid=0(root) groups=0(root)',
        explanation:
            'Simulated SSH probe returned UID 0 root account successfully.',
        securityNotes:
            'YALA strictly enforces read-only access and never attempts credential guessing.',
      ),
      subsystems: const [
        SubsystemAccessInfo(
          id: 'uci',
          name: 'UCI Configuration Engine',
          status: 'Full Read/Write Authorization',
          detail:
              'Declared permissions cover system, network, wireless, firewall, and dhcp.',
          isSupported: true,
        ),
        SubsystemAccessInfo(
          id: 'packages',
          name: 'Package Manager Engine',
          status: 'OPKG (ipk)',
          detail:
              'Standard OpenWrt opkg package manager detected and supported.',
          isSupported: true,
        ),
        SubsystemAccessInfo(
          id: 'firewall',
          name: 'Firewall Engine Backend',
          status: 'fw4 (nftables)',
          detail: 'Modern nftables-based firewall backend detected.',
          isSupported: true,
        ),
        SubsystemAccessInfo(
          id: 'adguard',
          name: 'AdGuard Home Integration',
          status: 'Detected & Active',
          detail: 'Local DNS filtering service operational on port 3000.',
          isSupported: true,
        ),
        SubsystemAccessInfo(
          id: 'sqm',
          name: 'Smart Queue Management (SQM)',
          status: 'Installed & Configured',
          detail: 'Bufferbloat mitigation queues active on WAN interface.',
          isSupported: true,
        ),
      ],
      diagnostics: [
        DiagnosticFinding(
          timestamp: now,
          message: 'Reviewer Mode simulated audit completed.',
          evidence: 'Mock session provider',
        ),
        DiagnosticFinding(
          timestamp: now,
          message: 'Zero configuration changes performed (Strictly read-only).',
        ),
      ],
    );
  }
}
