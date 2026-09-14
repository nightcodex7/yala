// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/storage_monitoring/models/storage_info.dart';

void main() {
  group('Storage Monitoring Tests', () {
    test('Parses standard df -k output correctly', () {
      const dfOutput = '''
Filesystem           1K-blocks      Used Available Use% Mounted on
/dev/root                15360     15360         0 100% /rom
tmpfs                   124808       988    123820   1% /tmp
/dev/ubi0_1              28468      5124     21876  19% /overlay
overlayfs:/overlay       28468      5124     21876  19% /
tmpfs                      512         0       512   0% /dev
''';

      final overview = StorageOverview.fromRpcData(dfOutput);
      expect(overview.mountPoints.length, equals(5));

      final root = overview.rootFs;
      expect(root, isNotNull);
      expect(root!.mountPath, equals('/'));

      final overlay = overview.overlayFs;
      expect(overlay, isNotNull);
      expect(overlay!.mountPath, equals('/overlay'));
      expect(overlay.sizeBytes, equals(28468 * 1024));
      expect(overlay.usedBytes, equals(5124 * 1024));
    });

    test(
      'Parses df output with split device names and spaces in mount target',
      () {
        const dfOutput = '''
Filesystem           1K-blocks      Used Available Use% Mounted on
/dev/mapper/vg-root
                      10485760   5242880   5242880  50% /
/dev/sda1
                       1000000    100000    900000  10% /mnt/USB Drive
''';

        final overview = StorageOverview.fromRpcData(dfOutput);
        expect(overview.mountPoints.length, equals(2));
        expect(overview.mountPoints[0].mountPath, equals('/'));
        expect(overview.mountPoints[1].mountPath, equals('/mnt/USB Drive'));
        expect(overview.mountPoints[1].sizeBytes, equals(1000000 * 1024));
      },
    );

    test('Parses /proc/mounts text fallback correctly', () {
      const procMounts = '''
/dev/root /rom squashfs ro,relatime 0 0
tmpfs /tmp tmpfs rw,nosuid,nodev,noatime,size=124808k 0 0
/dev/ubi0_1 /overlay ubifs rw,noatime,ubi=0,vol=1 0 0
overlayfs:/overlay / overlay rw,noatime 0 0
''';

      final overview = StorageOverview.fromRpcData(procMounts);
      expect(overview.mountPoints.length, equals(4));
      expect(overview.rootFs, isNotNull);
      expect(overview.overlayFs, isNotNull);
      expect(overview.overlayFs!.filesystemType, equals('ubifs'));
    });

    test('Parses JSON RPC mount points with explicit byte keys correctly', () {
      final jsonRpcData = [
        {
          'mount': '/',
          'device': '/dev/root',
          'fs': 'squashfs',
          'sizeBytes': 134217728, // Bytes (128MB)
          'usedBytes': 47185920,
          'availableBytes': 87031808,
        },
        {
          'mount': '/overlay',
          'device': '/dev/mtdblock6',
          'fs': 'ext4',
          'sizeBytes': 67108864, // Bytes (64MB)
          'usedBytes': 16777216,
          'availableBytes': 50331648,
        },
      ];

      final overview = StorageOverview.fromRpcData(jsonRpcData);
      expect(overview.mountPoints.length, equals(2));
      expect(overview.rootFs!.sizeBytes, equals(134217728));
      expect(overview.overlayFs!.sizeBytes, equals(67108864));
      expect(
        StorageOverview.formatBytes(overview.rootFs!.sizeBytes),
        equals('128.0 MB'),
      );
      expect(
        StorageOverview.formatBytes(overview.overlayFs!.sizeBytes),
        equals('64.0 MB'),
      );
    });

    test(
      'Parses df -h human-readable format correctly without double conversion',
      () {
        const dfHumanOutput = '''
Filesystem           Size  Used Avail Use% Mounted on
/dev/root            128M  128M     0 100% /rom
tmpfs                123M  2.0M  121M   2% /tmp
/dev/mtdblock6        53M  5.0M   48M  10% /overlay
''';

        final overview = StorageOverview.fromRpcData(dfHumanOutput);
        expect(overview.mountPoints.length, equals(3));
        expect(
          StorageOverview.formatBytes(overview.mountPoints[1].sizeBytes),
          equals('123.0 MB'),
        );
        expect(
          StorageOverview.formatBytes(overview.overlayFs!.sizeBytes),
          equals('53.0 MB'),
        );
      },
    );

    test(
      'Parses dynamic map representations without strict String generics',
      () {
        final dynamicMap = {
          'mountPoints': <dynamic, dynamic>{
            '0': <dynamic, dynamic>{
              'mount': '/',
              'device': '/dev/root',
              'sizeBytes': 134217728, // Explicit bytes
              'usedBytes': 47185920,
              'availableBytes': 87031808,
            },
          },
        };

        final overview = StorageOverview.fromRpcData(dynamicMap);
        expect(overview.mountPoints.length, equals(1));
        expect(overview.mountPoints[0].sizeBytes, equals(134217728));
        expect(
          StorageOverview.formatBytes(overview.mountPoints[0].sizeBytes),
          equals('128.0 MB'),
        );
      },
    );

    test('Format bytes function returns human readable strings', () {
      expect(StorageOverview.formatBytes(512), equals('512 B'));
      expect(StorageOverview.formatBytes(512000), equals('500.0 KB'));
      expect(StorageOverview.formatBytes(134217728), equals('128.0 MB'));
      expect(StorageOverview.formatBytes(2684354560), equals('2.50 GB'));
    });

    test('Reviewer mode fallback provides complete mock storage structure', () {
      final overview = StorageOverview.fromRpcData(null, isReviewerMode: true);
      expect(overview.mountPoints.length, equals(3));
      expect(overview.rootFs, isNotNull);
      expect(overview.overlayFs, isNotNull);
      expect(overview.totalSizeBytes, greaterThan(0));
    });

    test(
      'priorityDisplayMounts selects Overlay 1st, TempFS 2nd, and fallback partitions when missing',
      () {
        // 1. Standard case: Overlay and /tmp present
        const dfOutput = '''
Filesystem           1K-blocks      Used Available Use% Mounted on
/dev/root                15360     15360         0 100% /rom
tmpfs                   124808       988    123820   1% /tmp
/dev/ubi0_1              28468      5124     21876  19% /overlay
overlayfs:/overlay       28468      5124     21876  19% /
''';
        final overview = StorageOverview.fromRpcData(dfOutput);
        final priority = overview.priorityDisplayMounts;
        expect(priority.length, equals(2));
        expect(priority[0].mountPath, equals('/overlay'));
        expect(priority[1].mountPath, equals('/tmp'));

        // 2. Missing /tmp case: Overlay present, Root present
        const dfOutputNoTmp = '''
Filesystem           1K-blocks      Used Available Use% Mounted on
/dev/ubi0_1              28468      5124     21876  19% /overlay
overlayfs:/overlay       28468      5124     21876  19% /
''';
        final overviewNoTmp = StorageOverview.fromRpcData(dfOutputNoTmp);
        final priorityNoTmp = overviewNoTmp.priorityDisplayMounts;
        expect(priorityNoTmp.length, equals(2));
        expect(priorityNoTmp[0].mountPath, equals('/overlay'));
        expect(priorityNoTmp[1].mountPath, equals('/'));

        // 3. Missing Overlay case: only /tmp and /mnt/usb
        const dfOutputNoOverlay = '''
Filesystem           1K-blocks      Used Available Use% Mounted on
tmpfs                   124808       988    123820   1% /tmp
/dev/sda1              1000000    100000    900000  10% /mnt/usb
''';
        final overviewNoOverlay = StorageOverview.fromRpcData(
          dfOutputNoOverlay,
        );
        final priorityNoOverlay = overviewNoOverlay.priorityDisplayMounts;
        expect(priorityNoOverlay.length, equals(2));
        expect(priorityNoOverlay[0].mountPath, equals('/tmp'));
        expect(priorityNoOverlay[1].mountPath, equals('/mnt/usb'));
      },
    );

    test(
      'Scales 1K-blocks from OpenWrt RPC getMountPoints correctly for 384 MB router',
      () {
        final rpcData = [
          {
            'mount': '/',
            'device': 'overlayfs:/overlay',
            'fs': 'overlay',
            'size': 393216, // 393216 KB = 384 MB
            'used': 196608, // 196608 KB = 192 MB
            'avail': 196608,
          },
        ];

        final overview = StorageOverview.fromRpcData(rpcData);
        expect(overview.rootFs, isNotNull);
        expect(
          StorageOverview.formatBytes(overview.rootFs!.sizeBytes),
          equals('384.0 MB'),
        );
        expect(
          StorageOverview.formatBytes(overview.rootFs!.usedBytes),
          equals('192.0 MB'),
        );
      },
    );

    test(
      'Parses RPC mount points with size ALREADY in Bytes (e.g. 10.0.0.0 router) correctly',
      () {
        final rpcDataBytes = [
          {
            'mount': '/',
            'device': '/dev/root',
            'fs': 'squashfs',
            'size': 402653184, // 384 MB in Bytes
            'used': 201326592, // 192 MB in Bytes
            'avail': 201326592,
          },
        ];

        final overview = StorageOverview.fromRpcData(rpcDataBytes);
        expect(overview.rootFs, isNotNull);
        expect(
          StorageOverview.formatBytes(overview.rootFs!.sizeBytes),
          equals('384.0 MB'),
        );
        expect(
          StorageOverview.formatBytes(overview.rootFs!.usedBytes),
          equals('192.0 MB'),
        );
      },
    );

    test(
      'Parses RPC mount points with 1K-blocks (e.g. 192.168.1.1 router) correctly',
      () {
        final rpcDataKb = [
          {
            'mount': '/',
            'device': 'overlayfs:/overlay',
            'fs': 'overlay',
            'size': 131072, // 128 MB in 1K-blocks
            'used': 65536, // 64 MB in 1K-blocks
            'avail': 65536,
          },
        ];

        final overview = StorageOverview.fromRpcData(rpcDataKb);
        expect(overview.rootFs, isNotNull);
        expect(
          StorageOverview.formatBytes(overview.rootFs!.sizeBytes),
          equals('128.0 MB'),
        );
        expect(
          StorageOverview.formatBytes(overview.rootFs!.usedBytes),
          equals('64.0 MB'),
        );
      },
    );

    test('Parses RPC mount points with size in Megabytes correctly', () {
      final rpcDataMb = [
        {
          'mount': '/',
          'device': '/dev/root',
          'fs': 'squashfs',
          'size': 384, // in Megabytes
          'used': 192,
          'avail': 192,
        },
      ];

      final overview = StorageOverview.fromRpcData(rpcDataMb);
      expect(overview.rootFs, isNotNull);
      expect(
        StorageOverview.formatBytes(overview.rootFs!.sizeBytes),
        equals('384.0 MB'),
      );
      expect(
        StorageOverview.formatBytes(overview.rootFs!.usedBytes),
        equals('192.0 MB'),
      );
    });

    test('Parses ubus system mounts with explicit block_size correctly', () {
      final ubusData = [
        {
          'mount': '/overlay',
          'device': '/dev/ubi0_1',
          'fs': 'ubifs',
          'size': 98304,
          'used': 49152,
          'avail': 49152,
          'bsize': 4096, // 98304 * 4096 = 402,653,184 Bytes (384 MB)
        },
      ];

      final overview = StorageOverview.fromRpcData(ubusData);
      expect(overview.overlayFs, isNotNull);
      expect(
        StorageOverview.formatBytes(overview.overlayFs!.sizeBytes),
        equals('384.0 MB'),
      );
      expect(
        StorageOverview.formatBytes(overview.overlayFs!.usedBytes),
        equals('192.0 MB'),
      );
    });

    test(
      'Parses /rom squashfs mount with non-exact MB multiple byte size correctly',
      () {
        final romRpcData = [
          {
            'mount': '/rom',
            'device': '/dev/root',
            'fs': 'squashfs',
            'size': 15400960, // 14.68 MB in Bytes (not an exact 1MB multiple)
            'used': 15400960,
            'avail': 0,
          },
        ];

        final overview = StorageOverview.fromRpcData(romRpcData);
        expect(overview.mountPoints.length, equals(1));
        final rom = overview.mountPoints.first;
        expect(rom.mountPath, equals('/rom'));
        expect(rom.sizeBytes, equals(15400960));
        expect(rom.usedBytes, equals(15400960));
        expect(rom.availableBytes, equals(0));
        expect(rom.usedPercent, equals(100.0));
        expect(StorageOverview.formatBytes(rom.sizeBytes), equals('14.7 MB'));
        expect(StorageOverview.formatBytes(rom.usedBytes), equals('14.7 MB'));
        expect(StorageOverview.formatBytes(rom.availableBytes), equals('0 MB'));
      },
    );
  });
}
