// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';

/// Unify package manager enum across application
typedef PackageManagerType = PackageManagerEngine;

/// Unified software package model supporting OPKG (.ipk) and Alpine Package Keeper (.apk) formats.
class OpenWrtPackage {
  final String name;
  final String version;
  final String? architecture;
  final String description;
  final String? size;
  final bool isInstalled;
  final bool hasUpdate;
  final PackageManagerType managerType;

  const OpenWrtPackage({
    required this.name,
    required this.version,
    this.architecture,
    required this.description,
    this.size,
    required this.isInstalled,
    this.hasUpdate = false,
    this.managerType = PackageManagerType.opkg,
  });

  factory OpenWrtPackage.fromJson(
    Map<String, dynamic> json, {
    bool isInstalled = true,
    PackageManagerType managerType = PackageManagerType.opkg,
  }) {
    return OpenWrtPackage(
      name:
          json['name']?.toString() ??
          json['package']?.toString() ??
          json['pkg']?.toString() ??
          'unknown-package',
      version:
          json['version']?.toString() ?? json['ver']?.toString() ?? '1.0.0',
      architecture:
          json['architecture']?.toString() ?? json['arch']?.toString(),
      description:
          json['description']?.toString() ??
          json['desc']?.toString() ??
          'OpenWrt package',
      size: json['size']?.toString() ?? json['installed_size']?.toString(),
      isInstalled: isInstalled,
      hasUpdate: json['has_update'] == true || json['upgradable'] == true,
      managerType: managerType,
    );
  }

  String get fileExtension =>
      managerType == PackageManagerType.apk ? '.apk' : '.ipk';
}

/// Represents a LuCI application plugin (luci-app-*).
class LuciApp {
  final String id;
  final String name;
  final String packageName;
  final String description;
  final IconData icon;
  final bool isInstalled;
  final String? installedVersion;

  const LuciApp({
    required this.id,
    required this.name,
    required this.packageName,
    required this.description,
    required this.icon,
    required this.isInstalled,
    this.installedVersion,
  });
}

/// Complete overview container for package manager (OPKG/APK) and LuCI apps.
class PackageManagerOverview {
  final PackageManagerType activeManager;
  final List<OpenWrtPackage> installedPackages;
  final List<OpenWrtPackage> availablePackages;
  final List<LuciApp> discoveredLuciApps;

  const PackageManagerOverview({
    required this.activeManager,
    required this.installedPackages,
    required this.availablePackages,
    required this.discoveredLuciApps,
  });

  factory PackageManagerOverview.fromDashboardData(
    Map<String, dynamic>? data, {
    bool isReviewerMode = false,
  }) {
    final installed = <OpenWrtPackage>[];
    final available = <OpenWrtPackage>[];
    PackageManagerType type = PackageManagerType.opkg;

    if (data != null) {
      // Check if OpenWrt 24.10+ APK manager is active
      final mgrStr =
          data['packageManager']?.toString() ?? data['pkg_mgr']?.toString();
      if (mgrStr == 'apk' || data.containsKey('apkPackages')) {
        type = PackageManagerType.apk;
      }

      dynamic installedRaw =
          data['installedPackages'] ??
          data['apkPackages'] ??
          data['opkgPackages'];
      if (installedRaw is Map) {
        if (installedRaw.containsKey('packages')) {
          installedRaw = installedRaw['packages'];
        } else if (installedRaw.containsKey('result')) {
          final res = installedRaw['result'];
          if (res is Map && res.containsKey('packages')) {
            installedRaw = res['packages'];
          } else if (res is Map || res is List) {
            installedRaw = res;
          }
        }
      }

      if (installedRaw is String) {
        if (installedRaw.contains('Package: ') &&
            (installedRaw.contains('Status: ') ||
                installedRaw.contains('Version: '))) {
          // OPKG status file format (/usr/lib/opkg/status or /var/lib/opkg/status)
          final blocks = installedRaw.split(RegExp(r'\n\s*\n'));
          for (final block in blocks) {
            if (block.contains('Status: ') && !block.contains('installed')) {
              continue;
            }
            String? pkgName;
            String? pkgVer;
            String pkgDesc = '';
            for (final line in block.split('\n')) {
              if (line.startsWith('Package: ')) {
                pkgName = line.substring(9).trim();
              } else if (line.startsWith('Version: ')) {
                pkgVer = line.substring(9).trim();
              } else if (line.startsWith('Description: ')) {
                pkgDesc = line.substring(13).trim();
              } else if (line.startsWith(' ') && pkgDesc.isNotEmpty) {
                pkgDesc += ' ${line.trim()}';
              }
            }
            if (pkgName != null && pkgName.isNotEmpty) {
              installed.add(
                OpenWrtPackage(
                  name: pkgName,
                  version: pkgVer ?? 'installed',
                  description: pkgDesc.isEmpty
                      ? 'OpenWrt package ($pkgName)'
                      : pkgDesc,
                  isInstalled: true,
                  managerType: type,
                ),
              );
            }
          }
        } else if (installedRaw.contains('P:') && installedRaw.contains('V:')) {
          // APK DB installed file format (/lib/apk/db/installed)
          final blocks = installedRaw.split(RegExp(r'\n\s*\n'));
          for (final block in blocks) {
            String? pkgName;
            String? pkgVer;
            String pkgDesc = '';
            for (final line in block.split('\n')) {
              if (line.startsWith('P:')) {
                pkgName = line.substring(2).trim();
              } else if (line.startsWith('V:')) {
                pkgVer = line.substring(2).trim();
              } else if (line.startsWith('T:')) {
                pkgDesc = line.substring(2).trim();
              }
            }
            if (pkgName != null && pkgName.isNotEmpty) {
              installed.add(
                OpenWrtPackage(
                  name: pkgName,
                  version: pkgVer ?? 'installed',
                  description: pkgDesc.isEmpty
                      ? 'APK package ($pkgName)'
                      : pkgDesc,
                  isInstalled: true,
                  managerType: PackageManagerType.apk,
                ),
              );
            }
          }
        } else {
          // Line based output (opkg list-installed / apk list --installed)
          final lines = installedRaw.split('\n');
          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.isEmpty ||
                trimmed.startsWith('#') ||
                trimmed.startsWith('WARNING')) {
              continue;
            }

            String pkgName;
            String pkgVer = 'installed';
            String pkgDesc = '';

            if (trimmed.contains(' - ')) {
              final parts = trimmed.split(' - ');
              pkgName = parts[0].trim();
              if (parts.length > 1) pkgVer = parts[1].trim();
              if (parts.length > 2) pkgDesc = parts[2].trim();
            } else if (trimmed.contains(' ')) {
              final parts = trimmed.split(RegExp(r'\s+'));
              pkgName = parts[0].trim();
              if (parts.length > 1) pkgVer = parts[1].trim();
              if (parts.length > 2) pkgDesc = parts.sublist(2).join(' ');
            } else {
              final match = RegExp(
                r'^([a-zA-Z0-9_\-]+?)-([0-9].*)$',
              ).firstMatch(trimmed);
              if (match != null) {
                pkgName = match.group(1)!;
                pkgVer = match.group(2)!;
              } else {
                pkgName = trimmed;
              }
            }

            if (pkgName.isNotEmpty &&
                pkgName != 'Package:' &&
                pkgName != 'Status:') {
              installed.add(
                OpenWrtPackage(
                  name: pkgName,
                  version: pkgVer,
                  description: pkgDesc.isEmpty
                      ? 'OpenWrt package ($pkgName)'
                      : pkgDesc,
                  isInstalled: true,
                  managerType: type,
                ),
              );
            }
          }
        }
      } else if (installedRaw is List) {
        for (final item in installedRaw) {
          if (item is Map<String, dynamic>) {
            installed.add(
              OpenWrtPackage.fromJson(
                item,
                isInstalled: true,
                managerType: type,
              ),
            );
          } else if (item is String && item.isNotEmpty) {
            installed.add(
              OpenWrtPackage(
                name: item,
                version: 'installed',
                description: 'OpenWrt package ($item)',
                isInstalled: true,
                managerType: type,
              ),
            );
          }
        }
      } else if (installedRaw is Map) {
        Map targetMap = installedRaw;
        if (targetMap['packages'] is Map) {
          targetMap = targetMap['packages'] as Map;
        } else if (targetMap['result'] is Map) {
          targetMap = targetMap['result'] as Map;
        }
        targetMap.forEach((pkgName, val) {
          final nameStr = pkgName.toString();
          if (nameStr == 'packages' || nameStr == 'result') return;
          if (val is Map) {
            installed.add(
              OpenWrtPackage.fromJson(
                Map<String, dynamic>.from(val),
                isInstalled: true,
                managerType: type,
              ),
            );
          } else {
            installed.add(
              OpenWrtPackage(
                name: nameStr,
                version: val?.toString() ?? 'installed',
                description: 'OpenWrt package ($nameStr)',
                isInstalled: true,
                managerType: type,
              ),
            );
          }
        });
      }

      // Do not inject placeholder packages in production — empty means RPC unavailable.

      final availableRaw = data['availablePackages'];
      if (availableRaw is String) {
        final lines = availableRaw.split('\n');
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          if (trimmed.contains(' - ')) {
            final parts = trimmed.split(' - ');
            final pkgName = parts[0].trim();
            final pkgVer = parts.length > 1 ? parts[1].trim() : 'available';
            final pkgDesc = parts.length > 2
                ? parts[2].trim()
                : 'OpenWrt repository package';
            if (!installed.any((p) => p.name == pkgName)) {
              available.add(
                OpenWrtPackage(
                  name: pkgName,
                  version: pkgVer,
                  description: pkgDesc,
                  isInstalled: false,
                  managerType: type,
                ),
              );
            }
          } else {
            final parts = trimmed.split(RegExp(r'\s+'));
            final pkgName = parts[0];
            final pkgVer = parts.length > 1 ? parts[1] : 'available';
            final pkgDesc = parts.length > 2
                ? parts.sublist(2).join(' ')
                : 'OpenWrt repository package';
            if (!installed.any((p) => p.name == pkgName)) {
              available.add(
                OpenWrtPackage(
                  name: pkgName,
                  version: pkgVer,
                  description: pkgDesc,
                  isInstalled: false,
                  managerType: type,
                ),
              );
            }
          }
        }
      } else if (availableRaw is List) {
        for (final item in availableRaw) {
          if (item is Map<String, dynamic>) {
            available.add(
              OpenWrtPackage.fromJson(
                item,
                isInstalled: false,
                managerType: type,
              ),
            );
          }
        }
      } else if (availableRaw is Map) {
        availableRaw.forEach((_, item) {
          if (item is Map<String, dynamic>) {
            available.add(
              OpenWrtPackage.fromJson(
                item,
                isInstalled: false,
                managerType: type,
              ),
            );
          }
        });
      }
    }

    // Default mock package list only if in Reviewer Mode
    if (isReviewerMode) {
      if (installed.isEmpty) {
        installed.addAll([
          OpenWrtPackage(
            name: 'luci-base',
            version: 'git-23.330.60124',
            description: 'LuCI core JavaScript and MVC framework',
            isInstalled: true,
            managerType: type,
          ),
          OpenWrtPackage(
            name: 'luci-mod-admin-full',
            version: 'git-23.330.60124',
            description: 'LuCI Administration User Interface',
            isInstalled: true,
            managerType: type,
          ),
          OpenWrtPackage(
            name: 'dnsmasq-full',
            version: '2.89-1',
            description: 'DNS forwarder and DHCP server with DNSSEC support',
            isInstalled: true,
            managerType: type,
          ),
          OpenWrtPackage(
            name: 'wireguard-tools',
            version: '1.0.20210914-1',
            description: 'WireGuard control utilities',
            isInstalled: true,
            managerType: type,
          ),
          OpenWrtPackage(
            name: 'firewall4',
            version: '2023-09-12',
            description: 'OpenWrt nftables-based firewall manager',
            isInstalled: true,
            managerType: type,
          ),
          OpenWrtPackage(
            name: 'dropbear',
            version: '2022.82-2',
            description: 'Small SSH daemon',
            isInstalled: true,
            managerType: type,
          ),
        ]);
      }

      if (available.isEmpty) {
        available.addAll([
          OpenWrtPackage(
            name: 'luci-app-adguardhome',
            version: '1.8.2-1',
            description:
                'AdGuard Home network-wide ad blocker LuCI integration',
            isInstalled: false,
            managerType: type,
          ),
          OpenWrtPackage(
            name: 'luci-app-sqm',
            version: '1.5.0-1',
            description:
                'Smart Queue Management (Bufferbloat control) interface',
            isInstalled: false,
            managerType: type,
          ),
          OpenWrtPackage(
            name: 'luci-app-ttyd',
            version: '1.7.3-1',
            description: 'Web-based terminal command line interface',
            isInstalled: false,
            managerType: type,
          ),
          OpenWrtPackage(
            name: 'luci-app-aria2',
            version: '1.0.3-2',
            description: 'Lightweight multi-protocol download manager LuCI app',
            isInstalled: false,
            managerType: type,
          ),
          OpenWrtPackage(
            name: 'luci-app-samba4',
            version: '4.18.5-1',
            description: 'Samba4 Windows network file sharing server interface',
            isInstalled: false,
            managerType: type,
          ),
        ]);
      }
    }

    // Helper to check if a package is installed
    bool isPkgInstalled(String targetPkgName) {
      final cleanTarget = targetPkgName.toLowerCase().trim();
      final coreName = cleanTarget.replaceFirst('luci-app-', '');
      return installed.any((p) {
        final pName = p.name.toLowerCase().trim();
        return pName == cleanTarget ||
            pName == 'luci-app-$coreName' ||
            (coreName.length > 3 && pName == coreName);
      });
    }

    String? getPkgVersion(String targetPkgName) {
      final cleanTarget = targetPkgName.toLowerCase().trim();
      final coreName = cleanTarget.replaceFirst('luci-app-', '');
      for (final p in installed) {
        final pName = p.name.toLowerCase().trim();
        if (pName == cleanTarget ||
            pName == 'luci-app-$coreName' ||
            (coreName.length > 3 && pName == coreName)) {
          return p.version;
        }
      }
      return null;
    }

    // Known LuCI applications catalog
    final knownApps = <LuciApp>[
      LuciApp(
        id: 'adguardhome',
        name: 'AdGuard Home',
        packageName: 'luci-app-adguardhome',
        description: 'Network-wide advertisement and tracker blocking server',
        icon: Icons.shield,
        isInstalled: isPkgInstalled('luci-app-adguardhome'),
        installedVersion: getPkgVersion('luci-app-adguardhome'),
      ),
      LuciApp(
        id: 'wireguard',
        name: 'WireGuard VPN',
        packageName: 'luci-app-wireguard',
        description: 'Extremely simple yet fast modern VPN manager',
        icon: Icons.vpn_lock,
        isInstalled: isPkgInstalled('luci-app-wireguard'),
        installedVersion: getPkgVersion('luci-app-wireguard'),
      ),
      LuciApp(
        id: 'sqm',
        name: 'SQM QoS',
        packageName: 'luci-app-sqm',
        description:
            'Smart Queue Management to eliminate latency & bufferbloat',
        icon: Icons.speed,
        isInstalled: isPkgInstalled('luci-app-sqm'),
        installedVersion: getPkgVersion('luci-app-sqm'),
      ),
      LuciApp(
        id: 'ttyd',
        name: 'Terminal (ttyd)',
        packageName: 'luci-app-ttyd',
        description: 'Web-based terminal shell execution command line',
        icon: Icons.terminal,
        isInstalled: isPkgInstalled('luci-app-ttyd'),
        installedVersion: getPkgVersion('luci-app-ttyd'),
      ),
      LuciApp(
        id: 'aria2',
        name: 'Aria2 Downloader',
        packageName: 'luci-app-aria2',
        description: 'Multi-protocol download utility (HTTP/FTP/BitTorrent)',
        icon: Icons.downloading,
        isInstalled: isPkgInstalled('luci-app-aria2'),
        installedVersion: getPkgVersion('luci-app-aria2'),
      ),
      LuciApp(
        id: 'samba4',
        name: 'Samba Network Share',
        packageName: 'luci-app-samba4',
        description: 'SMB/CIFS local file server for USB storage sharing',
        icon: Icons.folder_shared,
        isInstalled: isPkgInstalled('luci-app-samba4'),
        installedVersion: getPkgVersion('luci-app-samba4'),
      ),
    ];

    // Automatically discover any other installed luci-app-* packages from router
    for (final pkg in installed) {
      if (pkg.name.startsWith('luci-app-')) {
        final alreadyInCatalog = knownApps.any(
          (app) => app.packageName == pkg.name,
        );
        if (!alreadyInCatalog) {
          final rawName = pkg.name.replaceFirst('luci-app-', '');
          final formattedTitle = rawName
              .split('-')
              .map(
                (w) => w.isNotEmpty
                    ? '${w[0].toUpperCase()}${w.substring(1)}'
                    : '',
              )
              .join(' ');

          knownApps.add(
            LuciApp(
              id: rawName,
              name: formattedTitle,
              packageName: pkg.name,
              description: 'OpenWrt LuCI module integration ($rawName)',
              icon: Icons.widgets_outlined,
              isInstalled: true,
              installedVersion: pkg.version,
            ),
          );
        }
      }
    }

    return PackageManagerOverview(
      activeManager: type,
      installedPackages: installed,
      availablePackages: available,
      discoveredLuciApps: knownApps,
    );
  }

  int get upgradableCount => installedPackages.where((p) => p.hasUpdate).length;

  String get managerTitle => 'OPKG/APK Package Manager';
}

/// Package feed/repository definition supporting OPKG and APK feed parsing.
class OpenWrtPackageRepository {
  final String name;
  final String url;
  final bool isEnabled;
  final PackageManagerEngine engine;

  const OpenWrtPackageRepository({
    required this.name,
    required this.url,
    this.isEnabled = true,
    required this.engine,
  });

  /// Parse OPKG config line: e.g. "src/gz openwrt_core https://downloads.openwrt.org/..."
  static OpenWrtPackageRepository? parseOpkgLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return null;
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length >= 3 &&
        (parts[0].startsWith('src') || parts[0] == 'dest')) {
      return OpenWrtPackageRepository(
        name: parts[1],
        url: parts[2],
        engine: PackageManagerEngine.opkg,
      );
    }
    return null;
  }

  /// Parse APK repositories line: e.g. "https://downloads.openwrt.org/snapshots/packages/x86_64/base"
  static OpenWrtPackageRepository? parseApkLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return null;
    String name = 'repository';
    String url = trimmed;
    if (trimmed.startsWith('@')) {
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        name = parts[0].substring(1);
        url = parts[1];
      }
    } else {
      final uri = Uri.tryParse(trimmed);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        name = uri.pathSegments.lastWhere(
          (s) => s.isNotEmpty,
          orElse: () => 'repo',
        );
      }
    }
    return OpenWrtPackageRepository(
      name: name,
      url: url,
      engine: PackageManagerEngine.apk,
    );
  }
}
