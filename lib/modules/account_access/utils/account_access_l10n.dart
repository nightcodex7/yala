// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import '../models/account_access_models.dart';

/// Centralized localization resolver for dynamic Account & Access models and inspector probe telemetry.
class AccountAccessL10n {
  const AccountAccessL10n._();

  /// Resolves the localized identity source description for [account].
  static String getIdentitySource(
    BuildContext context,
    CurrentAccountInfo account,
  ) {
    final l10n = AppLocalizations.of(context);
    if (account.isUsernameConfirmedByRouter) {
      final user = account.authenticatedUsername ?? account.configuredUsername;
      return l10n?.accountIdentitySourceConfirmed(user) ??
          account.identitySource;
    } else {
      return l10n?.accountIdentitySourceUnconfirmed ?? account.identitySource;
    }
  }

  /// Resolves the localized authentication method name.
  static String getAuthMethod(BuildContext context, String authMethod) {
    final l10n = AppLocalizations.of(context);
    if (authMethod.contains('sysauth') || authMethod.contains('Token')) {
      return l10n?.accountAuthMethodLuciToken ?? authMethod;
    } else if (authMethod.contains('Basic')) {
      return l10n?.accountAuthMethodHttpBasic ?? authMethod;
    } else if (authMethod.contains('Reviewer')) {
      return l10n?.accountAuthMethodReviewer ?? authMethod;
    }
    return authMethod;
  }

  /// Resolves the localized connection transport mechanism.
  static String getConnectionTransport(
    BuildContext context,
    String connectionMethod,
  ) {
    final l10n = AppLocalizations.of(context);
    if (connectionMethod.contains('HTTPS') ||
        connectionMethod.contains('TLS')) {
      return l10n?.accountTransportHttps ?? connectionMethod;
    } else if (connectionMethod.contains('HTTP')) {
      return l10n?.accountTransportHttp ?? connectionMethod;
    } else if (connectionMethod.contains('Reviewer')) {
      return l10n?.accountTransportReviewer ?? connectionMethod;
    }
    return connectionMethod;
  }

  /// Resolves the localized session status badge or label.
  static String getSessionStatus(BuildContext context, String sessionStatus) {
    final l10n = AppLocalizations.of(context);
    if (sessionStatus.contains('Active') ||
        sessionStatus.contains('Authenticated')) {
      return l10n?.accountSessionStatusActive ?? sessionStatus;
    } else if (sessionStatus.contains('Unverified') ||
        sessionStatus.contains('Expired')) {
      return l10n?.accountSessionStatusUnverified ?? sessionStatus;
    } else if (sessionStatus.contains('Offline')) {
      return l10n?.accountSessionStatusOffline ?? sessionStatus;
    }
    return sessionStatus;
  }

  /// Resolves the localized session validity string.
  static String getSessionValidity(
    BuildContext context,
    String sessionValidity,
  ) {
    final l10n = AppLocalizations.of(context);
    if (sessionValidity.contains('system.board')) {
      return l10n?.accountSessionValidityVerified ?? sessionValidity;
    } else if (sessionValidity.contains('probe failed') ||
        sessionValidity.contains('network error')) {
      return l10n?.accountSessionValidityFailed ?? sessionValidity;
    } else if (sessionValidity.contains('expired') ||
        sessionValidity.contains('rejected')) {
      return l10n?.accountSessionValidityExpired ?? sessionValidity;
    } else if (sessionValidity.contains('Simulated')) {
      return l10n?.accountSessionValiditySimulated ?? sessionValidity;
    }
    return sessionValidity;
  }

  /// Resolves the localized connection method name.
  static String getMethodName(
    BuildContext context,
    ConnectionMethodInfo method,
  ) {
    final l10n = AppLocalizations.of(context);
    switch (method.id) {
      case 'luci_http':
        return l10n?.accountMethodLuciHttpName ?? method.name;
      case 'luci_rpc':
        return l10n?.accountMethodLuciRpcName ?? method.name;
      case 'ssh':
        return l10n?.accountMethodSshName ?? method.name;
      default:
        return method.name;
    }
  }

  /// Resolves the localized connection method explanation.
  static String getMethodExplanation(
    BuildContext context,
    ConnectionMethodInfo method,
  ) {
    final l10n = AppLocalizations.of(context);
    switch (method.id) {
      case 'luci_http':
        if (method.status == ConnectionMethodStatus.activeAndVerified) {
          return l10n?.accountMethodLuciHttpDesc ?? method.explanation;
        } else {
          return l10n?.accountMethodLuciHttpDescFailed ?? method.explanation;
        }
      case 'luci_rpc':
        final match = RegExp(r'(\d+)\s+ubus').firstMatch(method.explanation);
        if (match != null) {
          final count = int.tryParse(match.group(1)!) ?? 0;
          return l10n?.accountMethodLuciRpcDesc(count) ?? method.explanation;
        } else if (method.status == ConnectionMethodStatus.activeAndVerified) {
          return l10n?.accountMethodLuciRpcDesc(14) ?? method.explanation;
        } else {
          return l10n?.accountMethodLuciRpcDescFailed ?? method.explanation;
        }
      case 'ssh':
        final portMatch = RegExp(
          r'port\s+(\d+)',
        ).firstMatch(method.explanation);
        final userMatch = RegExp(
          r'authenticated as\s+([^\.]+)',
        ).firstMatch(method.explanation);
        if (portMatch != null && userMatch != null) {
          final port = int.tryParse(portMatch.group(1)!) ?? 22;
          final user = userMatch.group(1)!.trim();
          return l10n?.accountMethodSshDesc(port, user) ?? method.explanation;
        }
        return method.explanation;
      default:
        return method.explanation;
    }
  }

  /// Resolves localized evidence source description.
  static String getEvidence(BuildContext context, String evidenceSource) {
    final l10n = AppLocalizations.of(context);
    if (evidenceSource.contains('system.board')) {
      return l10n?.accountEvidenceSystemBoard ?? evidenceSource;
    } else if (evidenceSource.contains('session.access')) {
      return l10n?.accountEvidenceSessionAccess ?? evidenceSource;
    } else if (evidenceSource.contains('schema introspection')) {
      return l10n?.accountEvidenceUbusSchema ?? evidenceSource;
    } else if (evidenceSource.contains('dropbear')) {
      return l10n?.accountEvidenceDropbearUci ?? evidenceSource;
    } else if (evidenceSource.contains('Default port')) {
      return l10n?.accountEvidenceDefaultPort ?? evidenceSource;
    }
    return evidenceSource;
  }

  /// Resolves localized RPC capability title.
  static String getCapabilityTitle(
    BuildContext context,
    RpcCapabilityPermission cap,
  ) {
    final l10n = AppLocalizations.of(context);
    switch (cap.id) {
      case 'system_info':
        return l10n?.accountCapSystemInfo ?? cap.title;
      case 'network_interfaces':
        return l10n?.accountCapNetworkInterfaces ?? cap.title;
      case 'wireless_config':
        return l10n?.accountCapWireless ?? cap.title;
      case 'dhcp_leases':
        return l10n?.accountCapDhcp ?? cap.title;
      case 'firewall_rules':
        return l10n?.accountCapFirewall ?? cap.title;
      case 'system_logs':
        return l10n?.accountCapSystemLogs ?? cap.title;
      case 'package_manager':
        return l10n?.accountCapPackageManager ?? cap.title;
      case 'uci_read':
        return l10n?.accountCapUciReads ?? cap.title;
      case 'uci_write':
        return l10n?.accountCapUciWrites ?? cap.title;
      case 'service_control':
        return l10n?.accountCapServiceControl ?? cap.title;
      case 'router_reboot':
        return l10n?.accountCapRouterReboot ?? cap.title;
      case 'backup_restore':
        return l10n?.accountCapSystemUpgrade ?? cap.title;
      default:
        return cap.title;
    }
  }

  /// Resolves localized RPC capability explanation.
  static String getCapabilityExplanation(
    BuildContext context,
    RpcCapabilityPermission cap,
  ) {
    final l10n = AppLocalizations.of(context);
    switch (cap.id) {
      case 'system_info':
        return l10n?.accountCapSystemInfoDesc ?? cap.explanation;
      case 'network_interfaces':
        return l10n?.accountCapNetworkInterfacesDesc ?? cap.explanation;
      case 'wireless_config':
        return cap.readStatus == PermissionAccessStatus.notSupported
            ? (l10n?.accountCapWirelessUnsupported ?? cap.explanation)
            : (l10n?.accountCapWirelessDesc ?? cap.explanation);
      case 'dhcp_leases':
        return l10n?.accountCapDhcpDesc ?? cap.explanation;
      case 'firewall_rules':
        return l10n?.accountCapFirewallDesc ?? cap.explanation;
      case 'system_logs':
        return l10n?.accountCapSystemLogsDesc ?? cap.explanation;
      case 'package_manager':
        return l10n?.accountCapPackageManagerDesc ?? cap.explanation;
      case 'uci_read':
        return l10n?.accountCapUciReadsDesc ?? cap.explanation;
      case 'uci_write':
        return l10n?.accountCapUciWritesDesc ?? cap.explanation;
      case 'service_control':
        return l10n?.accountCapServiceControlDesc ?? cap.explanation;
      case 'router_reboot':
        return l10n?.accountCapRouterRebootDesc ?? cap.explanation;
      case 'backup_restore':
        return l10n?.accountCapSystemUpgradeDesc ?? cap.explanation;
      default:
        return cap.explanation;
    }
  }

  /// Resolves localized RPC category chip label.
  static String getCategoryLabel(BuildContext context, String category) {
    final l10n = AppLocalizations.of(context);
    switch (category) {
      case 'Core System':
        return l10n?.accountRpcCatCoreSystem ?? category;
      case 'Network & Interfaces':
        return l10n?.accountRpcCatNetwork ?? category;
      case 'Security & Firewall':
        return l10n?.accountRpcCatSecurity ?? category;
      case 'Services & Management':
        return l10n?.accountRpcCatServices ?? category;
      case 'all':
      case 'All':
        return l10n?.accountRpcCatAll ?? category;
      default:
        return category;
    }
  }

  /// Resolves localized SSH daemon service status.
  static String getSshDaemonStatus(BuildContext context, String status) {
    final l10n = AppLocalizations.of(context);
    if (status.contains('detected in UCI')) {
      return l10n?.accountSshDaemonDropbearUci ?? status;
    } else if (status.contains('init scripts')) {
      return l10n?.accountSshDaemonDropbearInit ?? status;
    } else if (status.contains('active in UCI')) {
      return l10n?.accountSshDaemonNone ?? status;
    } else if (status.contains('inaccessible via LuCI')) {
      return l10n?.accountSshDaemonInaccessible ?? status;
    }
    return status;
  }

  /// Resolves localized SSH port source description.
  static String getSshPortSource(BuildContext context, String portSource) {
    final l10n = AppLocalizations.of(context);
    if (portSource.contains('dropbear')) {
      return l10n?.accountEvidenceDropbearUci ?? portSource;
    } else if (portSource.contains('Default')) {
      return l10n?.accountEvidenceDefaultPort ?? portSource;
    }
    return portSource;
  }

  /// Resolves localized SSH explanation.
  static String getSshExplanation(BuildContext context, SshAccessInfo ssh) {
    final l10n = AppLocalizations.of(context);
    if (ssh.explanation.contains('verified on port')) {
      final port = ssh.port ?? 22;
      final user = ssh.authenticatedUser ?? 'root';
      return l10n?.accountSshExplanationVerified(port, user) ?? ssh.explanation;
    } else if (ssh.explanation.contains('authentication failed') ||
        ssh.explanation.contains('bad password')) {
      return l10n?.accountSshExplanationAuthFailed ?? ssh.explanation;
    } else if (ssh.explanation.contains('closed or host unreachable')) {
      return l10n?.accountSshExplanationClosed ?? ssh.explanation;
    } else if (ssh.explanation.contains(
      'does not contain stored SSH credentials',
    )) {
      return l10n?.accountSshExplanationNoCreds ?? ssh.explanation;
    } else if (ssh.explanation.contains('No SSH service abstraction')) {
      return l10n?.accountSshExplanationNoService ?? ssh.explanation;
    } else if (ssh.explanation.contains('was not performed')) {
      return l10n?.accountSshExplanationNotPerformed ?? ssh.explanation;
    }
    return ssh.explanation;
  }

  /// Resolves localized command probe output.
  static String getSshOutput(BuildContext context, String output) {
    final l10n = AppLocalizations.of(context);
    if (output.startsWith('UNIX username:')) {
      final user = output.replaceFirst('UNIX username:', '').trim();
      return l10n?.accountSshOutputUsername(user) ?? output;
    }
    return output;
  }

  /// Resolves localized SSH security guarantee notes.
  static String getSshSecurityNotes(BuildContext context, String notes) {
    final l10n = AppLocalizations.of(context);
    return l10n?.accountSshSecurityNotes ?? notes;
  }

  /// Resolves localized subsystem name.
  static String getSubsystemName(
    BuildContext context,
    SubsystemAccessInfo sub,
  ) {
    final l10n = AppLocalizations.of(context);
    switch (sub.id) {
      case 'uci':
        return l10n?.accountSubsystemUci ?? sub.name;
      case 'pkg':
        return l10n?.accountSubsystemPkg ?? sub.name;
      case 'firewall':
        return l10n?.accountSubsystemFirewall ?? sub.name;
      case 'adguard':
        return l10n?.accountSubsystemAdGuard ?? sub.name;
      case 'odhcpd':
        return l10n?.accountSubsystemOdhcpd ?? sub.name;
      case 'cron':
        return l10n?.accountSubsystemCron ?? sub.name;
      default:
        return sub.name;
    }
  }

  /// Resolves localized subsystem status badge.
  static String getSubsystemStatus(
    BuildContext context,
    SubsystemAccessInfo sub,
  ) {
    final l10n = AppLocalizations.of(context);
    if (sub.id == 'uci') {
      final match = RegExp(
        r'(\d+)\s+configurations mapped',
      ).firstMatch(sub.status);
      if (match != null) {
        final count = int.tryParse(match.group(1)!) ?? 0;
        return l10n?.accountSubsystemUciStatus(count) ?? sub.status;
      } else if (sub.status.contains('Active')) {
        return l10n?.accountSubsystemUciStatusActive ?? sub.status;
      }
    } else if (sub.status == 'Active') {
      return l10n?.accountSubsystemStatusActive ?? sub.status;
    }
    return sub.status;
  }

  /// Resolves localized subsystem detail text.
  static String getSubsystemDetail(
    BuildContext context,
    SubsystemAccessInfo sub,
  ) {
    final l10n = AppLocalizations.of(context);
    switch (sub.id) {
      case 'uci':
        if (sub.detail.startsWith('Configs:')) {
          final configs = sub.detail.replaceFirst('Configs:', '').trim();
          return l10n?.accountSubsystemUciDetail(configs) ?? sub.detail;
        }
        return l10n?.accountSubsystemUciDetailStandard ?? sub.detail;
      case 'pkg':
        if (sub.detail.contains('APK')) {
          return l10n?.accountSubsystemPkgApkDesc ?? sub.detail;
        }
        return l10n?.accountSubsystemPkgOpkgDesc ?? sub.detail;
      case 'firewall':
        if (sub.detail.contains('fw4')) {
          return l10n?.accountSubsystemFw4Desc ?? sub.detail;
        }
        return l10n?.accountSubsystemFw3Desc ?? sub.detail;
      case 'adguard':
        return l10n?.accountSubsystemAdGuardDesc ?? sub.detail;
      case 'odhcpd':
        return l10n?.accountSubsystemOdhcpdDesc ?? sub.detail;
      case 'cron':
        return l10n?.accountSubsystemCronDesc ?? sub.detail;
      default:
        return sub.detail;
    }
  }

  /// Resolves localized account role.
  static String getAccountRole(BuildContext context, String role) {
    final l10n = AppLocalizations.of(context);
    if (role.contains('Primary Administrator')) {
      return l10n?.accountRoleAdmin ?? role;
    } else if (role.contains('Authenticated Session User')) {
      return l10n?.accountRoleSessionUser ?? role;
    } else if (role.contains('Configured User Account')) {
      return l10n?.accountRoleConfiguredUser ?? role;
    } else if (role.contains('Secondary Operator')) {
      return l10n?.accountRoleSecondaryOperator ?? role;
    }
    return role;
  }

  /// Resolves localized account source.
  static String getAccountSource(BuildContext context, String source) {
    final l10n = AppLocalizations.of(context);
    if (source.contains('Discovered in router logins')) {
      return l10n?.accountSourceDiscoveredLogins ?? source;
    } else if (source.contains('Confirmed via UNIX shell')) {
      return l10n?.accountSourceConfirmedShell ?? source;
    } else if (source.contains('Profile label')) {
      return l10n?.accountSourceProfileLabel ?? source;
    } else if (source.contains('UCI rpcd login')) {
      return l10n?.accountSourceUciLogin ?? source;
    }
    return source;
  }
}
