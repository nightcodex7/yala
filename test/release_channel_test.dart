// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/utils/release_utils.dart';

void main() {
  group('Release channel detection', () {
    test('detects SNAPSHOT version', () {
      final release = {
        'distribution': 'OpenWrt',
        'version': 'SNAPSHOT',
        'revision': 'r28597-d3e1c1fba8',
        'description': 'OpenWrt SNAPSHOT r28597-d3e1c1fba8',
      };
      expect(deriveReleaseChannel(release), 'snapshot');
    });

    test('detects 24.10-SNAPSHOT version', () {
      final release = {
        'distribution': 'OpenWrt',
        'version': '24.10-SNAPSHOT',
        'revision': 'r28500-abc123',
        'description': 'OpenWrt 24.10-SNAPSHOT r28500-abc123',
      };
      expect(deriveReleaseChannel(release), 'snapshot');
    });

    test('detects snapshot in description only', () {
      final release = {
        'distribution': 'OpenWrt',
        'version': '24.10.0',
        'description': 'OpenWrt 24.10.0-SNAPSHOT r28500',
      };
      expect(deriveReleaseChannel(release), 'snapshot');
    });

    test('stable release returns stable', () {
      final release = {
        'distribution': 'OpenWrt',
        'version': '23.05.0',
        'revision': 'r23497-6637af95aa',
        'description': 'OpenWrt 23.05.0 r23497-6637af95aa',
      };
      expect(deriveReleaseChannel(release), 'stable');
    });

    test('detects beta channel', () {
      final release = {
        'distribution': 'OpenWrt',
        'version': '24.10.0-beta1',
        'description': 'OpenWrt 24.10.0-beta1',
      };
      expect(deriveReleaseChannel(release), 'beta');
    });

    test('detects rc channel for lower and uppercase formats', () {
      expect(
        deriveReleaseChannel({
          'distribution': 'OpenWrt',
          'version': '24.10.0-rc1',
        }),
        'rc',
      );
      expect(
        deriveReleaseChannel({
          'distribution': 'OpenWrt',
          'version': '23.05.0-RC3',
        }),
        'rc',
      );
      expect(
        deriveReleaseChannel({
          'distribution': 'OpenWrt',
          'version': '24.10-rc.2',
        }),
        'rc',
      );
    });

    test('detects release channel directly from string version input', () {
      expect(deriveReleaseChannel('24.10.0-rc1'), 'rc');
      expect(deriveReleaseChannel('23.05.0-RC2'), 'rc');
      expect(deriveReleaseChannel('24.10-SNAPSHOT'), 'snapshot');
      expect(deriveReleaseChannel('23.05.3'), 'stable');
      expect(deriveReleaseChannel('24.10.0-beta2'), 'beta');
    });

    test('rc check does not false-positive on common words', () {
      final release = {
        'distribution': 'OpenWrt',
        'version': '23.05.0',
        'description': 'OpenWrt from source build',
      };
      expect(deriveReleaseChannel(release), 'stable');
    });

    test('null release returns stable', () {
      expect(deriveReleaseChannel(null), 'stable');
    });

    test('empty release returns stable', () {
      expect(deriveReleaseChannel({}), 'stable');
    });

    test('checks all fields including non-standard ones', () {
      final release = {
        'distribution': 'OpenWrt',
        'version': '24.10.0',
        'custom_field': 'snapshot-build',
      };
      expect(deriveReleaseChannel(release), 'snapshot');
    });
  });

  group('Distribution detection & parsing', () {
    test('detects ImmortalWrt distribution', () {
      final info = deriveDistributionInfo({
        'distribution': 'ImmortalWrt',
        'version': '23.05.3',
        'description': 'ImmortalWrt 23.05.3 r23801-23c6637af9',
      });
      expect(info.distribution, RouterDistribution.immortalWrt);
      expect(info.distributionName, 'ImmortalWrt');
      expect(info.displayName, 'ImmortalWrt 23.05.3');
      expect(info.channel, 'stable');
    });

    test('detects GL.iNet distribution and extracts base OpenWrt version', () {
      final info = deriveDistributionInfo({
        'distribution': 'GL.iNet',
        'version': '4.6.2',
        'description': 'GL.iNet v4.6.2 (OpenWrt 23.05.3)',
      }, model: 'GL-MT6000');
      expect(info.distribution, RouterDistribution.glInet);
      expect(info.distributionName, 'GL.iNet');
      expect(info.displayName, 'GL.iNet 4.6.2');
      expect(info.baseOpenWrtVersion, 'OpenWrt 23.05.3');
    });

    test('detects iStoreOS distribution', () {
      final info = deriveDistributionInfo({
        'distribution': 'iStoreOS',
        'version': '22.03.7',
        'description': 'iStoreOS 22.03.7 2024051010',
      });
      expect(info.distribution, RouterDistribution.iStoreOS);
      expect(info.distributionName, 'iStoreOS');
      expect(info.displayName, 'iStoreOS 22.03.7');
    });

    test('detects X-WRT, DD-WRT, FreshTomato distributions', () {
      expect(
        deriveDistributionInfo({
          'distribution': 'X-WRT',
          'version': '24.01',
        }).distribution,
        RouterDistribution.xWrt,
      );
      expect(
        deriveDistributionInfo({
          'distribution': 'DD-WRT',
          'version': 'v3.0',
        }).distribution,
        RouterDistribution.ddWrt,
      );
      expect(
        deriveDistributionInfo({
          'distribution': 'FreshTomato',
          'version': '2024.1',
        }).distribution,
        RouterDistribution.tomato,
      );
    });
  });
}
