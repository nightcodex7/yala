// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/models/rpc_result.dart';
import 'package:yet_another_luci_app/modules/package_manager/models/package_info.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/services/interfaces/auth_service_interface.dart';
import 'package:yet_another_luci_app/services/router_service.dart';
import 'package:yet_another_luci_app/utils/logger.dart';

/// Encapsulates all package manager RPC operations — install, remove,
/// upgrade, list-installed, list-available, and list-upgradable.
///
/// Extracted from [AppState] to enforce single-responsibility.
/// [AppState] retains forwarding methods so every existing call-site
/// continues to work without modification.
class PackageController {
  PackageController({
    required IApiService? Function() apiServiceRef,
    required IAuthService? Function() authServiceRef,
    required RouterService? Function() routerServiceRef,
    required RouterCapabilities? Function() capabilitiesRef,
    required bool Function() reviewerModeRef,
    required Future<void> Function() refreshDashboard,
    required Future<void> Function() redetectCapabilities,
  }) : _apiServiceRef = apiServiceRef,
       _authServiceRef = authServiceRef,
       _routerServiceRef = routerServiceRef,
       _capabilitiesRef = capabilitiesRef,
       _reviewerModeRef = reviewerModeRef,
       _refreshDashboard = refreshDashboard,
       _redetectCapabilities = redetectCapabilities;

  // Accessor closures — avoid holding stale references after router switch
  final IApiService? Function() _apiServiceRef;
  final IAuthService? Function() _authServiceRef;
  final RouterService? Function() _routerServiceRef;
  final RouterCapabilities? Function() _capabilitiesRef;
  final bool Function() _reviewerModeRef;
  final Future<void> Function() _refreshDashboard;
  final Future<void> Function() _redetectCapabilities;

  // ── Convenience accessors ──────────────────────────────────────

  String? get _ip => _routerServiceRef()?.selectedRouter?.ipAddress;
  String? get _sysauth => _authServiceRef()?.sysauth;
  bool get _useHttps => _routerServiceRef()?.selectedRouter?.useHttps ?? false;
  bool get _isReviewerMode => _reviewerModeRef();
  PackageManagerEngine get _engine =>
      _capabilitiesRef()?.packageEngine ?? PackageManagerEngine.opkg;

  // ── Public API (same signatures as AppState) ───────────────────

  /// Lazy capability-aware fetch returning a list of installed OpenWrtPackage objects
  Future<RpcResult<List<OpenWrtPackage>>> fetchInstalledPackages() async {
    final result = await fetchPackagesDataResult();
    if (result.isSuccess && result.data != null) {
      final overview = PackageManagerOverview.fromDashboardData({
        'installedPackages': result.data,
        'packageManager': _capabilitiesRef()?.packageEngine.name ?? 'opkg',
      }, isReviewerMode: _isReviewerMode);
      return RpcResult.success(overview.installedPackages);
    }
    if (_isReviewerMode) {
      final overview = PackageManagerOverview.fromDashboardData(
        null,
        isReviewerMode: true,
      );
      return RpcResult.success(overview.installedPackages);
    }
    return RpcResult(
      status: result.status,
      errorMessage:
          result.errorMessage ??
          'Failed to read installed packages from router.',
      errorCode: result.errorCode,
    );
  }

  /// Capability-aware fetch for installed packages returning RpcResult
  Future<RpcResult<dynamic>> fetchPackagesDataResult() async {
    if (_ip == null || _sysauth == null) {
      return RpcResult.networkError('No active router session');
    }

    final engine = _engine;
    if (engine == PackageManagerEngine.none) {
      return RpcResult.methodNotFound('No package manager detected on router');
    }

    // Dynamic UCI Configuration & System Package Discovery Engine.
    try {
      final discoveredPackages = <String>{};
      final api = _apiServiceRef()!;
      final ip = _ip!;
      final sysauth = _sysauth!;
      final useHttps = _useHttps;

      Map<String, dynamic>? unwrapUbusData(dynamic rpcData) {
        if (rpcData is List &&
            rpcData.length > 1 &&
            rpcData[0] == 0 &&
            rpcData[1] is Map) {
          return Map<String, dynamic>.from(rpcData[1] as Map);
        }
        if (rpcData is Map) {
          if (rpcData['values'] is Map || rpcData['configs'] is List) {
            return Map<String, dynamic>.from(rpcData);
          }
          if (rpcData['result'] is List &&
              (rpcData['result'] as List).length > 1 &&
              (rpcData['result'] as List)[1] is Map) {
            return Map<String, dynamic>.from(
              (rpcData['result'] as List)[1] as Map,
            );
          }
          if (rpcData['result'] is Map) {
            return Map<String, dynamic>.from(rpcData['result'] as Map);
          }
        }
        return null;
      }

      // 1. Dynamically query all installed UCI configs via uci.configs
      List<String> configsToQuery = [];
      try {
        final configsRpc = await api.call(
          ip,
          sysauth,
          useHttps,
          object: 'uci',
          method: 'configs',
          params: <String, dynamic>{},
        );
        final cfgMap = unwrapUbusData(configsRpc);
        if (cfgMap != null && cfgMap['configs'] is List) {
          configsToQuery = List<String>.from(cfgMap['configs']);
        }
      } catch (_) {}

      // Fallback config list if uci.configs is unavailable or blocked
      if (configsToQuery.isEmpty) {
        configsToQuery = [
          'ucitrack',
          'luci',
          'system',
          'network',
          'firewall',
          'dhcp',
          'wireless',
          'dropbear',
          'sqm',
          'ddns',
          'tailscale',
        ];
      }

      for (final cfg in configsToQuery) {
        try {
          final res = await api.call(
            ip,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'get',
            params: {'config': cfg},
          );
          final ubusMap = unwrapUbusData(res);
          if (ubusMap != null && ubusMap['values'] is Map) {
            discoveredPackages.add(cfg);
            if (!cfg.startsWith('luci')) {
              discoveredPackages.add('luci-app-$cfg');
            }

            final values = ubusMap['values'] as Map;
            for (final key in values.keys) {
              final sectionName = key.toString();
              if (sectionName.isNotEmpty && !sectionName.startsWith('@')) {
                discoveredPackages.add(sectionName);
              }
              final sectionVal = values[key];
              if (sectionVal is Map) {
                final typeStr = sectionVal['.type']?.toString();
                if (typeStr != null &&
                    typeStr.isNotEmpty &&
                    !typeStr.startsWith('@')) {
                  discoveredPackages.add(typeStr);
                }
              }
            }
          }
        } catch (_) {}
      }

      // 2. Query system board details dynamically for system base info
      try {
        final boardRpc = await api.call(
          ip,
          sysauth,
          useHttps,
          object: 'system',
          method: 'board',
          params: <String, dynamic>{},
        );
        final boardMap = unwrapUbusData(boardRpc);
        if (boardMap != null) {
          final release = boardMap['release'];
          if (release is Map) {
            final target = release['target']?.toString();
            if (target != null && target.isNotEmpty) {
              discoveredPackages.add('target-$target');
            }
          }
        }
      } catch (_) {}

      if (discoveredPackages.isNotEmpty) {
        final sortedList = discoveredPackages.toList()..sort();
        return RpcResult.success(sortedList);
      }
    } catch (_) {}

    return RpcResult.methodNotFound(
      'Could not read installed packages: no supported package query method responded on this router.',
    );
  }

  /// Capability-aware fetch for available packages returning RpcResult
  Future<RpcResult<dynamic>> fetchAvailablePackagesDataResult() async {
    if (_ip == null || _sysauth == null) {
      return RpcResult.networkError('No active router session');
    }

    final engine = _engine;
    if (engine == PackageManagerEngine.none) {
      return RpcResult.methodNotFound('No package manager detected on router');
    }

    final api = _apiServiceRef()!;
    final ip = _ip!;
    final sysauth = _sysauth!;
    final useHttps = _useHttps;
    final isApk = engine == PackageManagerEngine.apk;
    final cmd = isApk ? 'apk' : 'opkg';

    try {
      final helperRpc = await api.call(
        ip,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': '/usr/libexec/package-manager-call',
          'params': ['list-available'],
        },
      );

      final helperResult = RpcResult.classifyExecResult<dynamic>(helperRpc, (
        data,
      ) {
        if (data is Map &&
            data['stdout'] != null &&
            (data['stdout'] as String).trim().isNotEmpty) {
          return data['stdout'];
        }
        return null;
      });

      if (helperResult.isSuccess && helperResult.data != null) {
        return helperResult;
      }

      final rawRpc = await api.call(
        ip,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': cmd,
          'params': ['list'],
        },
      );

      final execResult = RpcResult.classifyExecResult<dynamic>(rawRpc, (data) {
        if (data is Map &&
            data['stdout'] != null &&
            (data['stdout'] as String).trim().isNotEmpty) {
          return data['stdout'];
        }
        return null;
      });

      if (execResult.status == RpcCallStatus.methodNotFound) {
        unawaited(_redetectCapabilities());
      }

      return execResult;
    } catch (e) {
      return RpcResult.networkError(
        'Network error fetching available packages: $e',
      );
    }
  }

  /// Manage software packages on OpenWrt (OPKG / APK) returning classified RpcResult
  Future<RpcResult<String>> managePackageResult({
    required String packageName,
    required String action,
  }) async {
    if (_ip == null || _sysauth == null) {
      return RpcResult.networkError('No active router session');
    }

    final engine = _engine;
    if (engine == PackageManagerEngine.none) {
      return RpcResult.methodNotFound(
        'No package manager detected on this router',
      );
    }

    final api = _apiServiceRef()!;
    final ip = _ip!;
    final sysauth = _sysauth!;
    final useHttps = _useHttps;
    final isApk = engine == PackageManagerEngine.apk;
    final cmd = isApk ? 'apk' : 'opkg';
    List<String> args = [];

    if (action == 'install') {
      args = isApk ? ['add', packageName] : ['install', packageName];
    } else if (action == 'remove') {
      args = isApk ? ['del', packageName] : ['remove', packageName];
    } else if (action == 'update') {
      args = ['update'];
    } else if (action == 'upgrade') {
      args = ['upgrade'];
    }

    try {
      final helperArgs =
          action == 'install' || action == 'remove' || action == 'upgrade'
          ? (packageName.trim().isEmpty ? [action] : [action, packageName])
          : [action];

      final helperRpc = await api.call(
        ip,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': '/usr/libexec/package-manager-call',
          'params': helperArgs,
        },
      );

      final helperResult = RpcResult.classifyExecResult<String>(helperRpc, (
        data,
      ) {
        if (data is Map && data['stdout'] != null) {
          return data['stdout'].toString();
        }
        return 'Action completed successfully';
      });

      if (helperResult.isSuccess) {
        await _refreshDashboard();
        return helperResult;
      }

      final rawRpc = await api.call(
        ip,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {'command': cmd, 'params': args},
      );

      final result = RpcResult.classifyExecResult<String>(rawRpc, (data) {
        if (data is Map && data['stdout'] != null) {
          return data['stdout'].toString();
        }
        return 'Action completed successfully';
      });

      // Trigger background re-probe on capability mismatch
      if (result.status == RpcCallStatus.methodNotFound) {
        Logger.warning(
          'Package action returned methodNotFound. Triggering background capability re-probe.',
        );
        unawaited(_redetectCapabilities());
      }

      if (result.isSuccess) {
        await _refreshDashboard();
      }

      return result;
    } catch (e) {
      Logger.error('Failed package action $action for $packageName: $e');
      return RpcResult.networkError(
        'Network error executing package action: $e',
      );
    }
  }

  /// Backward compatible wrapper for managePackage
  Future<bool> managePackage({
    required String packageName,
    required String action,
  }) async {
    final res = await managePackageResult(
      packageName: packageName,
      action: action,
    );
    return res.isSuccess;
  }

  /// Check and fetch upgradable packages returning classified RpcResult
  Future<RpcResult<List<OpenWrtPackage>>>
  fetchUpgradablePackagesResult() async {
    if (_isReviewerMode) {
      return RpcResult.success([
        OpenWrtPackage(
          name: 'luci-app-firewall',
          version: 'git-23.332 ➔ git-24.010',
          description: 'Firewall management interface upgrade',
          isInstalled: true,
          managerType: PackageManagerEngine.opkg,
        ),
        OpenWrtPackage(
          name: 'dnsmasq',
          version: '2.89-1 ➔ 2.90-1',
          description: 'DHCP and DNS server security update',
          isInstalled: true,
          managerType: PackageManagerEngine.opkg,
        ),
      ]);
    }

    final engine = _engine;
    if (engine == PackageManagerEngine.none) {
      return RpcResult.methodNotFound(
        'No package manager detected on this router',
      );
    }

    if (_ip == null || _sysauth == null) {
      return RpcResult.networkError('No active router session');
    }

    final api = _apiServiceRef()!;
    final ip = _ip!;
    final sysauth = _sysauth!;
    final useHttps = _useHttps;
    final isApk = engine == PackageManagerEngine.apk;
    final cmd = isApk ? 'apk' : 'opkg';
    final listArgs = isApk ? ['list', '--upgradable'] : ['list-upgradable'];

    try {
      await api.call(
        ip,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': '/usr/libexec/package-manager-call',
          'params': ['update'],
        },
      );

      final rawRpc = await api.call(
        ip,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {'command': cmd, 'params': listArgs},
      );

      final result = RpcResult.classifyExecResult<List<OpenWrtPackage>>(
        rawRpc,
        (data) {
          final output = data is Map ? (data['stdout']?.toString() ?? '') : '';
          if (output.trim().isEmpty) return <OpenWrtPackage>[];

          final upgradable = <OpenWrtPackage>[];
          for (final line in output.split('\n')) {
            final trimmed = line.trim();
            if (trimmed.isEmpty ||
                trimmed.startsWith('WARNING') ||
                trimmed.startsWith('#')) {
              continue;
            }

            if (trimmed.contains(' - ')) {
              final parts = trimmed.split(' - ');
              final name = parts[0].trim();
              final oldVer = parts.length > 1 ? parts[1].trim() : '';
              final newVer = parts.length > 2 ? parts[2].trim() : '';
              upgradable.add(
                OpenWrtPackage(
                  name: name,
                  version: oldVer.isNotEmpty && newVer.isNotEmpty
                      ? '$oldVer ➔ $newVer'
                      : (newVer.isNotEmpty ? newVer : oldVer),
                  description: 'Upgradable package ($name)',
                  isInstalled: true,
                  managerType: engine,
                ),
              );
            } else {
              final parts = trimmed.split(RegExp(r'\s+'));
              if (parts.isNotEmpty) {
                final name = parts[0].trim();
                upgradable.add(
                  OpenWrtPackage(
                    name: name,
                    version: parts.length > 1 ? parts[1] : 'update available',
                    description: 'Upgradable package ($name)',
                    isInstalled: true,
                    managerType: engine,
                  ),
                );
              }
            }
          }
          return upgradable;
        },
      );

      if (result.status == RpcCallStatus.methodNotFound) {
        Logger.warning(
          'Upgradable query returned methodNotFound. Triggering background capability re-probe.',
        );
        unawaited(_redetectCapabilities());
      }

      return result;
    } catch (e) {
      Logger.error('Failed to fetch upgradable packages: $e');
      return RpcResult.networkError(
        'Network error checking package upgrades: $e',
      );
    }
  }

  /// Backward compatible wrapper for fetchUpgradablePackages
  Future<List<OpenWrtPackage>> fetchUpgradablePackages() async {
    final res = await fetchUpgradablePackagesResult();
    return res.data ?? [];
  }
}
