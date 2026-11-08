// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/modules/dhcp_dns/models/dhcp_dns_info.dart';
import 'package:yet_another_luci_app/modules/firewall_security/models/firewall_info.dart';
import 'package:yet_another_luci_app/modules/parental_controls/controllers/parental_controls_controller.dart';
import 'package:yet_another_luci_app/modules/services_system/models/ddns_info.dart';
import 'package:yet_another_luci_app/modules/ssh_console/services/saved_commands_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

/// Status of a single export category.
enum ExportCategoryStatus {
  /// Data retrieved successfully.
  success,

  /// Retrieval succeeded but the source is empty.
  empty,

  /// Retrieval was attempted but failed.
  failed,

  /// The current implementation does not support this category.
  unsupported,
}

/// Result of collecting data for one export category.
class ExportCategoryResult {
  final ExportCategoryStatus status;

  /// The exported data (List or Map), null when empty/failed/unsupported.
  final dynamic data;

  /// Number of top-level items in [data] (0 when no data).
  final int itemCount;

  /// Human-readable error message, populated only when [status] == [ExportCategoryStatus.failed].
  final String? errorMessage;

  const ExportCategoryResult._({
    required this.status,
    this.data,
    this.itemCount = 0,
    this.errorMessage,
  });

  factory ExportCategoryResult.success(dynamic data, int count) =>
      ExportCategoryResult._(
        status: ExportCategoryStatus.success,
        data: data,
        itemCount: count,
      );

  factory ExportCategoryResult.empty() =>
      const ExportCategoryResult._(status: ExportCategoryStatus.empty);

  factory ExportCategoryResult.failed(String error) => ExportCategoryResult._(
    status: ExportCategoryStatus.failed,
    errorMessage: error,
  );

  factory ExportCategoryResult.unsupported() =>
      const ExportCategoryResult._(status: ExportCategoryStatus.unsupported);

  bool get isSuccess => status == ExportCategoryStatus.success;
  bool get isEmpty => status == ExportCategoryStatus.empty;
  bool get isFailed => status == ExportCategoryStatus.failed;
  bool get isUnsupported => status == ExportCategoryStatus.unsupported;
}

/// Pure-Dart service that collects router configuration from [AppState] and
/// encodes it as a structured JSON document.
///
/// Security note: DDNS passwords are redacted – replaced with `"[REDACTED]"`.
/// SSH keys, session tokens and auth credentials are never included.
class ConfigExportService {
  ConfigExportService._();

  // ── Individual category exports ────────────────────────────────────────────

  /// Exports DDNS entries. DDNS passwords are [REDACTED].
  static ExportCategoryResult exportDdns(AppState appState) {
    try {
      final data = appState.dashboardData;
      if (data == null) return ExportCategoryResult.empty();

      final overview = DdnsOverview.fromDashboardData(
        data,
        isReviewerMode: appState.reviewerModeEnabled,
      );
      if (overview.instances.isEmpty) return ExportCategoryResult.empty();

      final list = overview.instances.map((inst) {
        return <String, dynamic>{
          'name': inst.name,
          'serviceName': inst.serviceName,
          'username': inst.username,
          'password': '[REDACTED]',
          'domain': inst.domain,
          'lookupHost': inst.lookupHost,
          'interface': inst.interface,
          'enabled': inst.enabled,
          'ipSource': inst.ipSource,
          'ipNetwork': inst.ipNetwork,
          'ipUrl': inst.ipUrl,
          if (inst.updateUrl.isNotEmpty) 'updateUrl': inst.updateUrl,
          if (inst.updateScript.isNotEmpty) 'updateScript': inst.updateScript,
          'useHttps': inst.useHttps,
          'checkInterval': inst.checkInterval,
          'checkUnit': inst.checkUnit,
          'forceInterval': inst.forceInterval,
          'forceUnit': inst.forceUnit,
        };
      }).toList();

      return ExportCategoryResult.success(list, list.length);
    } catch (e) {
      return ExportCategoryResult.failed('DDNS export error: $e');
    }
  }

  /// Exports static DHCP lease mappings (hostname → IP → MAC).
  static ExportCategoryResult exportStaticDhcpLeases(AppState appState) {
    try {
      final data = appState.dashboardData;
      if (data == null) return ExportCategoryResult.empty();

      final overview = DhcpDnsOverview.fromDashboardData(
        data,
        isReviewerMode: appState.reviewerModeEnabled,
      );
      final mappings = overview.staticMappings;
      if (mappings.isEmpty) return ExportCategoryResult.empty();

      final list = mappings
          .map(
            (m) => <String, dynamic>{
              'hostname': m.hostname,
              'ipAddress': m.ipAddress,
              'macAddress': m.macAddress,
              if (m.ip6Address.isNotEmpty) 'ip6Address': m.ip6Address,
              if (m.duid.isNotEmpty) 'duid': m.duid,
              if (m.leaseTime.isNotEmpty) 'leaseTime': m.leaseTime,
            },
          )
          .toList();

      return ExportCategoryResult.success(list, list.length);
    } catch (e) {
      return ExportCategoryResult.failed('Static DHCP export error: $e');
    }
  }

  /// Parses the firewall UCI config from dashboardData, returns the overview or null.
  static FirewallOverview? _firewallOverview(AppState appState) {
    final rawFirewall = appState.dashboardData?['uciFirewallConfig'];
    if (rawFirewall is! Map) return null;
    return FirewallOverview.fromUciData(
      Map<String, dynamic>.from(rawFirewall),
      backend: appState.capabilities?.firewallBackend ?? FirewallBackend.fw4,
      isReviewerMode: appState.reviewerModeEnabled,
    );
  }

  /// Exports custom firewall rules (non-system traffic rules).
  static ExportCategoryResult exportFirewallRules(AppState appState) {
    try {
      final overview = _firewallOverview(appState);
      if (overview == null) return ExportCategoryResult.empty();

      final rules = overview.customRules;
      if (rules.isEmpty) return ExportCategoryResult.empty();

      final list = rules.map((r) => r.toJson()).toList();
      return ExportCategoryResult.success(list, list.length);
    } catch (e) {
      return ExportCategoryResult.failed('Firewall rules export error: $e');
    }
  }

  /// Exports firewall zone forwarding entries.
  static ExportCategoryResult exportZoneForwarding(AppState appState) {
    try {
      final overview = _firewallOverview(appState);
      if (overview == null) return ExportCategoryResult.empty();

      final forwardings = overview.forwardings;
      if (forwardings.isEmpty) return ExportCategoryResult.empty();

      final list = forwardings
          .map(
            (f) => <String, dynamic>{
              'srcZone': f.srcZone,
              'destZone': f.destZone,
            },
          )
          .toList();

      return ExportCategoryResult.success(list, list.length);
    } catch (e) {
      return ExportCategoryResult.failed('Zone forwarding export error: $e');
    }
  }

  /// Exports port forwarding (redirect) rules.
  static ExportCategoryResult exportPortForwarding(AppState appState) {
    try {
      final overview = _firewallOverview(appState);
      if (overview == null) return ExportCategoryResult.empty();

      final portForwards = overview.portForwards;
      if (portForwards.isEmpty) return ExportCategoryResult.empty();

      final list = portForwards.map((p) => p.toJson()).toList();
      return ExportCategoryResult.success(list, list.length);
    } catch (e) {
      return ExportCategoryResult.failed('Port forwarding export error: $e');
    }
  }

  /// Exports parental control profiles (local/per-router store).
  static ExportCategoryResult exportParentalControls(AppState appState) {
    try {
      final profiles = ParentalControlsController.instance.store.profiles;
      if (profiles.isEmpty) return ExportCategoryResult.empty();

      final list = profiles.map((p) => p.toJson()).toList();
      return ExportCategoryResult.success(list, list.length);
    } catch (e) {
      return ExportCategoryResult.failed('Parental controls export error: $e');
    }
  }

  /// Exports installed packages. Makes a fresh network call via [AppState.fetchInstalledPackages].
  static Future<ExportCategoryResult> exportInstalledPackages(
    AppState appState,
  ) async {
    try {
      final result = await appState.fetchInstalledPackages();
      if (!result.isSuccess) {
        return ExportCategoryResult.failed(
          'Package fetch failed: ${result.errorMessage ?? result.status.name}',
        );
      }

      final packages = result.data ?? [];
      if (packages.isEmpty) return ExportCategoryResult.empty();

      final list = packages
          .map(
            (p) => <String, dynamic>{
              'name': p.name,
              'version': p.version,
              if (p.architecture != null) 'architecture': p.architecture,
              'description': p.description,
              if (p.size != null) 'size': p.size,
              if (p.license != null) 'license': p.license,
              if (p.section != null) 'section': p.section,
              'hasUpdate': p.hasUpdate,
              'managerType': p.managerType.name,
            },
          )
          .toList();

      return ExportCategoryResult.success(list, list.length);
    } catch (e) {
      return ExportCategoryResult.failed('Installed packages export error: $e');
    }
  }

  /// Exports cron jobs as a list of cron line strings.
  static ExportCategoryResult exportCronJobs(AppState appState) {
    try {
      final raw = appState.dashboardData?['cronJobs'];
      if (raw == null) return ExportCategoryResult.empty();

      final lines = <String>[];
      if (raw is List) {
        for (final item in raw) {
          final s = item?.toString() ?? '';
          if (s.trim().isNotEmpty) lines.add(s);
        }
      }

      if (lines.isEmpty) return ExportCategoryResult.empty();
      return ExportCategoryResult.success(lines, lines.length);
    } catch (e) {
      return ExportCategoryResult.failed('Cron jobs export error: $e');
    }
  }

  /// Exports init scripts status map from rc.list.
  static ExportCategoryResult exportInitScripts(AppState appState) {
    try {
      final raw = appState.dashboardData?['initScripts'];
      if (raw == null) return ExportCategoryResult.empty();

      if (raw is! Map || raw.isEmpty) return ExportCategoryResult.empty();

      final normalized = <String, dynamic>{};
      raw.forEach((key, value) {
        normalized[key.toString()] = value;
      });

      return ExportCategoryResult.success(normalized, normalized.length);
    } catch (e) {
      return ExportCategoryResult.failed('Init scripts export error: $e');
    }
  }

  /// Exports dashboard UI preferences (tile visibility, ordering, etc.).
  static ExportCategoryResult exportDashboardSettings(AppState appState) {
    try {
      final prefs = appState.dashboardPreferences;
      final json = prefs.toJson();
      return ExportCategoryResult.success(json, json.length);
    } catch (e) {
      return ExportCategoryResult.failed('Dashboard settings export error: $e');
    }
  }

  /// Exports saved SSH console commands for the current router.
  static Future<ExportCategoryResult> exportSshSavedCommands(
    AppState appState,
  ) async {
    try {
      final routerId = appState.selectedRouter?.id;
      if (routerId == null) return ExportCategoryResult.empty();

      final commands = await SavedCommandsService().getAll(routerId);
      if (commands.isEmpty) return ExportCategoryResult.empty();

      final list = commands.map((c) => c.toJson()).toList();
      return ExportCategoryResult.success(list, list.length);
    } catch (e) {
      return ExportCategoryResult.failed('SSH saved commands export error: $e');
    }
  }

  // ── All-in-one export ──────────────────────────────────────────────────────

  /// Collects data for all categories and returns a structured export document.
  static Future<Map<String, dynamic>> buildAllCategoriesExport(
    AppState appState,
  ) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final now = DateTime.now().toUtc();

    final ddnsResult = exportDdns(appState);
    final dhcpResult = exportStaticDhcpLeases(appState);
    final firewallResult = exportFirewallRules(appState);
    final zoneResult = exportZoneForwarding(appState);
    final portResult = exportPortForwarding(appState);
    final parentalResult = exportParentalControls(appState);
    final packagesResult = await exportInstalledPackages(appState);
    final cronResult = exportCronJobs(appState);
    final initResult = exportInitScripts(appState);
    final dashboardResult = exportDashboardSettings(appState);
    final sshSavedCommandsResult = await exportSshSavedCommands(appState);

    Map<String, dynamic> categoryEntry(ExportCategoryResult r, String label) {
      return {
        'status': r.status.name,
        'itemCount': r.itemCount,
        if (r.data != null) 'data': r.data,
        if (r.errorMessage != null) 'error': r.errorMessage,
      };
    }

    return {
      'exportMeta': {
        'exportedAt': now.toIso8601String(),
        'appVersion': packageInfo.version,
        'appBuildNumber': packageInfo.buildNumber,
        'routerIp': appState.selectedRouter?.ipAddress ?? 'unknown',
        'routerLabel': appState.selectedRouter?.displayName ?? 'unknown',
        'exportFormat': 'yala-config-export-v1',
        'securityNote':
            'Sensitive fields (passwords, tokens, keys) have been redacted.',
      },
      'categories': {
        'ddns': categoryEntry(ddnsResult, 'DDNS'),
        'staticDhcpLeases': categoryEntry(dhcpResult, 'Static DHCP Leases'),
        'firewallRules': categoryEntry(firewallResult, 'Firewall Rules'),
        'zoneForwarding': categoryEntry(zoneResult, 'Zone Forwarding'),
        'portForwarding': categoryEntry(portResult, 'Port Forwarding'),
        'parentalControls': categoryEntry(parentalResult, 'Parental Controls'),
        'installedPackages': categoryEntry(
          packagesResult,
          'Installed Packages',
        ),
        'cronJobs': categoryEntry(cronResult, 'Cron Jobs'),
        'initScripts': categoryEntry(initResult, 'Init Scripts'),
        'dashboardSettings': categoryEntry(
          dashboardResult,
          'Dashboard Settings',
        ),
        'sshSavedCommands': categoryEntry(
          sshSavedCommandsResult,
          'SSH Saved Commands',
        ),
      },
    };
  }

  // ── Encoding ───────────────────────────────────────────────────────────────

  /// Encodes [data] to indented JSON bytes (UTF-8).
  static Uint8List encodeToJson(Map<String, dynamic> data) {
    const encoder = JsonEncoder.withIndent('  ');
    return Uint8List.fromList(utf8.encode(encoder.convert(data)));
  }

  /// Builds a single-category export document and encodes it.
  static Uint8List encodeCategoryToJson(
    String categoryKey,
    ExportCategoryResult result,
    AppState appState,
  ) {
    final now = DateTime.now().toUtc();

    final doc = <String, dynamic>{
      'exportMeta': {
        'exportedAt': now.toIso8601String(),
        'category': categoryKey,
        'routerIp': appState.selectedRouter?.ipAddress ?? 'unknown',
        'routerLabel': appState.selectedRouter?.displayName ?? 'unknown',
        'exportFormat': 'yala-config-export-v1',
      },
      'status': result.status.name,
      'itemCount': result.itemCount,
      if (result.data != null) 'data': result.data,
      if (result.errorMessage != null) 'error': result.errorMessage,
    };

    return encodeToJson(doc);
  }
}
