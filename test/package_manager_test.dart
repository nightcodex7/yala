// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/models/rpc_result.dart';
import 'package:yet_another_luci_app/modules/package_manager/models/package_info.dart';
import 'package:yet_another_luci_app/services/api_service.dart';

void main() {
  group('Package Manager Engine Wiring Tests', () {
    test('PackageManagerType is unified with PackageManagerEngine', () {
      expect(PackageManagerType.opkg, equals(PackageManagerEngine.opkg));
      expect(PackageManagerType.apk, equals(PackageManagerEngine.apk));
      expect(PackageManagerType.none, equals(PackageManagerEngine.none));
    });

    test('classifyExecResult maps exit code 127 to methodNotFound', () {
      final execPayload = [
        0,
        {'code': 127, 'stdout': '', 'stderr': 'opkg: command not found'},
      ];

      final result = RpcResult.classifyExecResult<String>(
        execPayload,
        (data) => data['stdout'],
      );
      expect(result.status, equals(RpcCallStatus.methodNotFound));
      expect(result.isMethodNotFound, isTrue);
    });

    test(
      'classifyExecResult maps exit code 126 and permission denied stderr to permissionDenied',
      () {
        final execPayload = [
          0,
          {
            'code': 126,
            'stdout': '',
            'stderr': 'Permission denied executing command',
          },
        ];

        final result = RpcResult.classifyExecResult<String>(
          execPayload,
          (data) => data['stdout'],
        );
        expect(result.status, equals(RpcCallStatus.permissionDenied));
        expect(result.isPermissionDenied, isTrue);
      },
    );

    test(
      'classifyExecResult maps non-zero exit code to failed with raw stderr detail',
      () {
        final execPayload = [
          0,
          {
            'code': 1,
            'stdout': '',
            'stderr':
                'opkg_install_cmd: Cannot install package luci-app-test: No space left on device',
          },
        ];

        final result = RpcResult.classifyExecResult<String>(
          execPayload,
          (data) => data['stdout'],
        );
        expect(result.status, equals(RpcCallStatus.failed));
        expect(result.errorMessage, contains('No space left on device'));
      },
    );

    test('classifyExecResult maps exit code 0 to success', () {
      final execPayload = [
        0,
        {'code': 0, 'stdout': 'base-files - 1570-r23805\n', 'stderr': ''},
      ];

      final result = RpcResult.classifyExecResult<String>(
        execPayload,
        (data) => data['stdout'],
      );
      expect(result.status, equals(RpcCallStatus.success));
      expect(result.isSuccess, isTrue);
      expect(result.data, equals('base-files - 1570-r23805\n'));
    });

    test(
      'fromDashboardData parses package-manager-call OPKG status output on APK routers',
      () {
        const sampleOutput = '''
Package: apk-mbedtls
Version: 3.0.5-r2
Depends: libc, libmbedtls21
Status: install ok installed
Description: apk package manager (mbedtls)

Package: base-files
Version: 1696~b21cfa8f8c
Status: install ok installed
Description: OpenWrt base files
''';
        final overview = PackageManagerOverview.fromDashboardData({
          'packageManager': 'apk',
          'installedPackages': sampleOutput,
        });
        expect(overview.installedPackages.length, 2);
        expect(overview.installedPackages[0].name, 'apk-mbedtls');
        expect(overview.installedPackages[0].version, '3.0.5-r2');
        expect(overview.installedPackages[1].name, 'base-files');
      },
    );

    test(
      'fromDashboardData returns empty installed list when RPC data is missing',
      () {
        final overview = PackageManagerOverview.fromDashboardData({
          'packageManager': 'apk',
          'installedPackages': null,
        });
        expect(overview.installedPackages, isEmpty);
        expect(overview.availablePackages, isEmpty);
      },
    );

    test('OpenWrtPackageRepository correctly parses OPKG feeds', () {
      const line =
          'src/gz openwrt_core https://downloads.openwrt.org/snapshots/packages/x86_64/base';
      final repo = OpenWrtPackageRepository.parseOpkgLine(line);

      expect(repo, isNotNull);
      expect(repo!.name, equals('openwrt_core'));
      expect(
        repo.url,
        equals('https://downloads.openwrt.org/snapshots/packages/x86_64/base'),
      );
      expect(repo.engine, equals(PackageManagerEngine.opkg));
    });

    test('OpenWrtPackageRepository correctly parses APK repositories', () {
      const line =
          'https://downloads.openwrt.org/snapshots/packages/x86_64/base';
      final repo = OpenWrtPackageRepository.parseApkLine(line);

      expect(repo, isNotNull);
      expect(
        repo!.url,
        equals('https://downloads.openwrt.org/snapshots/packages/x86_64/base'),
      );
      expect(repo.engine, equals(PackageManagerEngine.apk));
    });

    test(
      'PackageManagerOverview parses OPKG status file blocks (/usr/lib/opkg/status)',
      () {
        const opkgStatus = '''
Package: base-files
Version: 1570-r23805
Status: install ok installed
Architecture: x86_64
Description: OpenWrt core base files

Package: luci-app-firewall
Version: 1.0.0-1
Status: install ok installed
Description: Firewall configuration user interface
''';
        final overview = PackageManagerOverview.fromDashboardData({
          'packageManager': 'opkg',
          'installedPackages': opkgStatus,
        });

        expect(overview.installedPackages.length, equals(2));
        expect(overview.installedPackages[0].name, equals('base-files'));
        expect(overview.installedPackages[0].version, equals('1570-r23805'));
        expect(overview.installedPackages[1].name, equals('luci-app-firewall'));
      },
    );

    test(
      'PackageManagerOverview parses APK database blocks (/lib/apk/db/installed)',
      () {
        const apkDb = '''
C:Q1abc123
P:zlib
V:1.2.13-r1
T:Compression library

C:Q1def456
P:busybox
V:1.36.1-r2
T:Essential command line utilities
''';
        final overview = PackageManagerOverview.fromDashboardData({
          'packageManager': 'apk',
          'installedPackages': apkDb,
        });

        expect(overview.installedPackages.length, equals(2));
        expect(overview.installedPackages[0].name, equals('zlib'));
        expect(overview.installedPackages[0].version, equals('1.2.13-r1'));
        expect(overview.installedPackages[1].name, equals('busybox'));
      },
    );

    test(
      'PackageManagerOverview parses apk info -v single-word output lines',
      () {
        const apkInfo = '''
zlib-1.2.13-r1
busybox-1.36.1-r2
luci-mod-status-24.10.0-r1
''';
        final overview = PackageManagerOverview.fromDashboardData({
          'packageManager': 'apk',
          'installedPackages': apkInfo,
        });

        expect(overview.installedPackages.length, equals(3));
        expect(overview.installedPackages[0].name, equals('zlib'));
        expect(overview.installedPackages[0].version, equals('1.2.13-r1'));
        expect(overview.installedPackages[1].name, equals('busybox'));
        expect(overview.installedPackages[1].version, equals('1.36.1-r2'));
      },
    );

    test(
      'fileExecParams and fileExecArgs preserve RPC compatibility for file.exec',
      () {
        final params = RealApiService.fileExecParams(
          '/usr/libexec/package-manager-call',
          ['list-installed'],
        );
        expect(
          params,
          containsPair('command', '/usr/libexec/package-manager-call'),
        );
        expect(params, contains('params'));
        expect(params, isNot(contains('args')));

        final args = RealApiService.fileExecArgs(
          '/usr/libexec/package-manager-call',
          ['list-installed'],
        );
        expect(
          args,
          containsPair('command', '/usr/libexec/package-manager-call'),
        );
        expect(args, contains('args'));
        expect(args, isNot(contains('params')));
      },
    );

    test(
      'RpcResult correctly identifies permissionDenied status (ubus code 6)',
      () {
        final ubusPermError = [6, 'Access denied'];
        final res = RpcResult.fromUbusResponse<String>(
          ubusPermError,
          (d) => d.toString(),
        );
        expect(res.isPermissionDenied, isTrue);
        expect(res.status, equals(RpcCallStatus.permissionDenied));
      },
    );
  });
}
