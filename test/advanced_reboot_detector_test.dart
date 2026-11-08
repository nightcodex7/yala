// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/src/widgets/framework.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/advanced_reboot/models/reboot_capability.dart';
import 'package:yet_another_luci_app/modules/advanced_reboot/services/advanced_reboot_detector.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/services/mock_ssh_service.dart';

class ConfigurableRebootApiService extends MockApiService {
  Map<String, dynamic> boardResponse;
  String procMtdContent;
  String bootPartContent;
  String bootPartReadyContent;
  bool hasFwSetenvUtil;
  bool shouldThrowOnCall;
  String? osReleaseContent;
  String? alternateOsContent;
  List<String> recordedCalls = [];

  ConfigurableRebootApiService({
    this.boardResponse = const {
      'board_name': 'linksys,ea8300',
      'model': 'Linksys EA8300',
      'release': {'target': 'ipq40xx/generic', 'version': '23.05.3'},
    },
    this.procMtdContent = '''
dev:    size   erasesize  name
mtd0: 00080000 00020000 "sbl1"
mtd1: 00080000 00020000 "mibib"
mtd2: 00080000 00020000 "qseecom"
mtd3: 00080000 00020000 "u-boot"
mtd4: 00080000 00020000 "u-boot-env"
mtd5: 00600000 00020000 "kernel"
mtd6: 02800000 00020000 "rootfs"
mtd7: 00600000 00020000 "alt_kernel"
mtd8: 02800000 00020000 "alt_rootfs"
''',
    this.bootPartContent = '1',
    this.bootPartReadyContent = '3',
    this.hasFwSetenvUtil = true,
    this.shouldThrowOnCall = false,
    this.osReleaseContent,
    this.alternateOsContent,
    this.luciAdvancedRebootResponse,
  });

  final Map<String, dynamic>? luciAdvancedRebootResponse;

  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  }) async {
    recordedCalls.add('$object.$method(${params ?? ""})');

    if (shouldThrowOnCall) {
      throw Exception('Network connection timed out');
    }

    if (object == 'luci.advanced-reboot' && method == 'obtain_device_info') {
      if (luciAdvancedRebootResponse != null) {
        return [0, luciAdvancedRebootResponse];
      }
      return [6];
    }

    if (object == 'system' && method == 'board') {
      return boardResponse;
    }

    if (object == 'file' && method == 'read') {
      final path = params?['path'];
      if (path == '/proc/mtd') {
        return {'data': procMtdContent};
      }
      if (path == '/tmp/sysinfo/board_name') {
        return {'data': boardResponse['board_name'] ?? ''};
      }
      if (path == '/tmp/sysinfo/model') {
        return {'data': boardResponse['model'] ?? ''};
      }
      if (path == '/etc/os-release') {
        return {
          'data':
              osReleaseContent ??
              'PRETTY_NAME="OpenWrt 23.05.3"\nNAME="OpenWrt"\nVERSION="23.05.3"\n',
        };
      }
      if (path != null &&
          (path.startsWith('/alt') || path.startsWith('/rom_alt'))) {
        return {'error': 'No such file or directory'};
      }
    }

    if (object == 'file' && method == 'exec') {
      final cmd = params?['command']?.toString() ?? '';
      final args =
          (params?['args'] as List?)?.map((e) => e.toString()).toList() ?? [];

      // Alternate OS read-only probe
      if ((cmd == 'sh' || cmd == '/bin/sh') && args.contains('-c')) {
        return {
          'stdout':
              alternateOsContent ??
              'PRETTY_NAME="OpenWrt 22.03.5"\nNAME="OpenWrt"\nVERSION="22.03.5"\n',
          'code': 0,
        };
      }

      // NEVER allow fw_setenv during detection
      if (cmd.contains('fw_setenv') && !cmd.contains('which')) {
        throw StateError(
          'fw_setenv was invoked during read-only capability detection!',
        );
      }

      if (cmd.contains('fw_printenv')) {
        if (args.contains('boot_part')) {
          return {'stdout': bootPartContent, 'code': 0};
        }
        if (args.contains('boot_part_ready')) {
          return {'stdout': bootPartReadyContent, 'code': 0};
        }
      }

      if (cmd == 'which') {
        if (args.contains('fw_setenv')) {
          return hasFwSetenvUtil
              ? {'stdout': '/usr/sbin/fw_setenv\n', 'code': 0}
              : {'stdout': '', 'code': 1};
        }
      }
    }

    return super.call(
      ipAddress,
      sysauth,
      useHttps,
      object: object,
      method: method,
      params: params,
      context: context,
    );
  }
}

void main() {
  group('AdvancedRebootDetector Tests', () {
    test(
      'Known supported device with complete evidence (Linksys EA8300)',
      () async {
        final api = ConfigurableRebootApiService();
        final detector = AdvancedRebootDetector(apiService: api);

        final caps = await detector.detect(
          routerId: 'router_ea8300',
          ipAddress: '192.168.1.1',
          sysauth: 'mock_token',
          useHttps: false,
        );

        // Verify Standard Reboot is supported
        expect(caps.standardReboot.isSupported, isTrue);

        // Verify Alternate Partition Boot is supported
        expect(caps.alternatePartitionBoot.isSupported, isTrue);
        expect(
          caps.alternatePartitionBoot.status,
          equals(CapabilityStatus.supported),
        );
        expect(caps.alternatePartitionBoot.targetIdentifier, equals('2'));
        expect(caps.environment.activeSlot, equals('1'));
        expect(caps.environment.alternateSlot, equals('2'));
        expect(caps.matchedProfileId, equals('linksys_ea8300'));

        // Verify Poweroff is unsupported on EA8300 (no ACPI hardware cut-off)
        expect(caps.powerOff.isUnsupported, isTrue);

        // Verify read-only guarantee: fw_setenv was NEVER called
        final setenvCalls = api.recordedCalls.where(
          (c) => c.contains('fw_setenv') && !c.contains('which'),
        );
        expect(setenvCalls, isEmpty);
      },
    );

    test(
      'Single-partition device evaluates alternate boot as unsupported',
      () async {
        final api = ConfigurableRebootApiService(
          boardResponse: {
            'board_name': 'tp-link,archer-c7-v2',
            'model': 'TP-Link Archer C7 v2',
            'release': {'target': 'ath79/generic', 'version': '23.05.3'},
          },
          procMtdContent: '''
dev:    size   erasesize  name
mtd0: 00020000 00010000 "u-boot"
mtd1: 00140000 00010000 "kernel"
mtd2: 00e80000 00010000 "rootfs"
mtd3: 00020000 00010000 "art"
''',
          bootPartContent: '',
          hasFwSetenvUtil: false,
        );
        final detector = AdvancedRebootDetector(apiService: api);

        final caps = await detector.detect(
          routerId: 'router_archer_c7',
          ipAddress: '192.168.1.1',
          sysauth: 'mock_token',
          useHttps: false,
        );

        expect(caps.standardReboot.isSupported, isTrue);
        expect(caps.alternatePartitionBoot.isUnsupported, isTrue);
        expect(
          caps.alternatePartitionBoot.status,
          equals(CapabilityStatus.unsupported),
        );
        expect(
          caps.alternatePartitionBoot.reason,
          contains('Single firmware partition layout'),
        );
      },
    );

    test(
      'Uncurated device with dual partitions and valid U-Boot boot_part is supported via generic adapter',
      () async {
        final api = ConfigurableRebootApiService(
          boardResponse: {
            'board_name': 'acme,experimental-dual-boot',
            'model': 'ACME DualBoot Router',
            'release': {'target': 'ramips/mt7621', 'version': '23.05.3'},
          },
          procMtdContent: '''
dev:    size   erasesize  name
mtd0: 00040000 00010000 "boot"
mtd1: 00400000 00010000 "kernel1"
mtd2: 01000000 00010000 "rootfs1"
mtd3: 00400000 00010000 "kernel2"
mtd4: 01000000 00010000 "rootfs2"
''',
          bootPartContent: '1',
          bootPartReadyContent: '',
          hasFwSetenvUtil: true,
        );
        final detector = AdvancedRebootDetector(apiService: api);

        final caps = await detector.detect(
          routerId: 'router_acme',
          ipAddress: '192.168.1.1',
          sysauth: 'mock_token',
          useHttps: false,
        );

        // Standard reboot is available
        expect(caps.standardReboot.isSupported, isTrue);

        // Universally supported via generic U-Boot adapter even without a curated profile!
        expect(caps.alternatePartitionBoot.isSupported, isTrue);
        expect(
          caps.alternatePartitionBoot.status,
          equals(CapabilityStatus.supported),
        );
        expect(
          caps.alternatePartitionBoot.mechanismId,
          equals('uboot_boot_part'),
        );
        expect(caps.matchedProfileId, isNull);
        expect(caps.matchedAdapterId, equals('uboot_boot_part'));
        expect(caps.alternatePartitionBoot.targetIdentifier, equals('2'));
      },
    );

    test(
      'Uncurated device with dual partitions but unknown/unreadable boot variables evaluates as unknown',
      () async {
        final api = ConfigurableRebootApiService(
          boardResponse: {
            'board_name': 'acme,unknown-boot-router',
            'model': 'ACME Unknown Boot Router',
            'release': {'target': 'ramips/mt7621', 'version': '23.05.3'},
          },
          procMtdContent: '''
dev:    size   erasesize  name
mtd0: 00040000 00010000 "boot"
mtd1: 00400000 00010000 "kernel1"
mtd2: 01000000 00010000 "rootfs1"
mtd3: 00400000 00010000 "kernel2"
mtd4: 01000000 00010000 "rootfs2"
''',
          bootPartContent: '',
          hasFwSetenvUtil: true,
        );
        final detector = AdvancedRebootDetector(apiService: api);

        final caps = await detector.detect(
          routerId: 'router_acme_unknown',
          ipAddress: '192.168.1.1',
          sysauth: 'mock_token',
          useHttps: false,
        );

        // Standard reboot is available
        expect(caps.standardReboot.isSupported, isTrue);

        // Alternate partition boot MUST be unknown because boot mechanism is unverified
        expect(caps.alternatePartitionBoot.isUnknown, isTrue);
        expect(
          caps.alternatePartitionBoot.status,
          equals(CapabilityStatus.unknown),
        );
        expect(caps.alternatePartitionBoot.isSupported, isFalse);
      },
    );

    test(
      'Supported model with missing fw_setenv evaluates as unsupported',
      () async {
        final api = ConfigurableRebootApiService(hasFwSetenvUtil: false);
        final detector = AdvancedRebootDetector(apiService: api);

        final caps = await detector.detect(
          routerId: 'router_no_setenv',
          ipAddress: '192.168.1.1',
          sysauth: 'mock_token',
          useHttps: false,
        );

        expect(caps.alternatePartitionBoot.isUnsupported, isTrue);
        expect(
          caps.alternatePartitionBoot.reason,
          contains('Bootloader control utilities are missing'),
        );
        expect(
          caps.alternatePartitionBoot.missingOrConflictingEvidence,
          contains(contains('fw_setenv')),
        );
      },
    );

    test(
      'Supported model with unreadable active boot slot evaluates as unknown',
      () async {
        final api = ConfigurableRebootApiService(
          bootPartContent: '', // fw_printenv returned empty/unreadable
        );
        final detector = AdvancedRebootDetector(apiService: api);

        final caps = await detector.detect(
          routerId: 'router_no_slot',
          ipAddress: '192.168.1.1',
          sysauth: 'mock_token',
          useHttps: false,
        );

        expect(caps.alternatePartitionBoot.isUnknown, isTrue);
        expect(
          caps.alternatePartitionBoot.reason,
          contains('Current active firmware partition could not be determined'),
        );
      },
    );

    test('x86_64 platform evaluates poweroff as supported', () async {
      final api = ConfigurableRebootApiService(
        boardResponse: {
          'board_name': 'x86/64',
          'model': 'Generic x86/64',
          'release': {'target': 'x86/64', 'version': '23.05.3'},
        },
        procMtdContent: '',
      );
      final detector = AdvancedRebootDetector(apiService: api);

      final caps = await detector.detect(
        routerId: 'router_x86',
        ipAddress: '192.168.1.1',
        sysauth: 'mock_token',
        useHttps: false,
      );

      expect(caps.standardReboot.isSupported, isTrue);
      expect(caps.powerOff.isSupported, isTrue);
      expect(caps.powerOff.status, equals(CapabilityStatus.supported));
      expect(caps.alternatePartitionBoot.isUnsupported, isTrue);
    });

    test('RPC exception produces safe error state without throwing', () async {
      final api = ConfigurableRebootApiService(shouldThrowOnCall: true);
      final detector = AdvancedRebootDetector(apiService: api);

      final caps = await detector.detect(
        routerId: 'router_error',
        ipAddress: '192.168.1.1',
        sysauth: 'mock_token',
        useHttps: false,
      );

      expect(caps.standardReboot.isError, isTrue);
      expect(caps.alternatePartitionBoot.isError, isTrue);
      expect(caps.powerOff.isError, isTrue);
      expect(caps.detectionError, isNotNull);
    });

    test('SSH fallback query works when RPC file.read fails', () async {
      final api = ConfigurableRebootApiService(procMtdContent: '');
      final ssh = MockSshService(
        shouldSucceed: true,
        mockStdout:
            'mtd0: 00600000 00020000 "kernel"\nmtd1: 00600000 00020000 "alt_kernel"',
      );
      final detector = AdvancedRebootDetector(apiService: api, sshService: ssh);

      final caps = await detector.detect(
        routerId: 'router_ssh_test',
        ipAddress: '192.168.1.1',
        sysauth: 'mock_token',
        useHttps: false,
        sshUsername: 'root',
        sshPassword: 'password',
      );

      expect(caps.environment.mtdPartitions.length, equals(2));
      expect(
        caps.environment.mtdPartitions.any((p) => p.name == 'alt_kernel'),
        isTrue,
      );
    });

    test('Sanitized diagnostic string excludes secrets', () async {
      final api = ConfigurableRebootApiService();
      final detector = AdvancedRebootDetector(apiService: api);

      final caps = await detector.detect(
        routerId: 'router_secret_test',
        ipAddress: '192.168.1.1',
        sysauth: 'super_secret_sysauth_token_9999',
        sshPassword: 'super_secret_router_pass_8888',
        useHttps: false,
      );

      final diag = caps.toSanitizedDiagnosticString();
      expect(diag, contains('linksys,ea8300'));
      expect(diag, contains('Linksys EA8300'));
      expect(diag, isNot(contains('super_secret_sysauth_token_9999')));
      expect(diag, isNot(contains('super_secret_router_pass_8888')));
    });

    test('Detects active OS and alternate OS accurately', () async {
      final api = ConfigurableRebootApiService(
        osReleaseContent: 'PRETTY_NAME="OpenWrt 25.12.6"\n',
        alternateOsContent: 'PRETTY_NAME="OpenWrt 23.05.3"\n',
      );
      final detector = AdvancedRebootDetector(apiService: api);

      final caps = await detector.detect(
        routerId: 'router_os_test',
        ipAddress: '192.168.1.1',
        sysauth: 'mock_token',
        useHttps: false,
      );

      expect(caps.environment.activeOs, equals('OpenWrt 25.12.6'));
      expect(caps.environment.alternateOs, equals('OpenWrt 23.05.3'));
      expect(
        caps.environment.discoveredMechanismName,
        equals('U-Boot (boot_part + ready)'),
      );
    });

    test('Detects OEM stock firmware on alternate slot', () async {
      final api = ConfigurableRebootApiService(
        osReleaseContent: 'PRETTY_NAME="OpenWrt 25.12.6"\n',
        alternateOsContent: '1.1.4.195026\n',
      );
      final detector = AdvancedRebootDetector(apiService: api);

      final caps = await detector.detect(
        routerId: 'router_stock_test',
        ipAddress: '192.168.1.1',
        sysauth: 'mock_token',
        useHttps: false,
      );

      expect(caps.environment.activeOs, equals('OpenWrt 25.12.6'));
      expect(
        caps.environment.alternateOs,
        equals('Stock Firmware v1.1.4.195026'),
      );
    });

    test(
      'Opportunistically utilizes luci-app-advanced-reboot info when installed',
      () async {
        final api = ConfigurableRebootApiService(
          bootPartContent: '2',
          luciAdvancedRebootResponse: {
            'device': {
              'vendor': 'Linksys',
              'model': 'EA8300',
              'board': 'linksys,ea8300',
              'partition_active': '2',
            },
            'partitions': [
              {
                'number': '1',
                'label': 'OpenWrt 25.12.5 r33051-f5dae5ece4',
                'os': '6.12.94',
                'mtd': 'mtd10',
              },
              {
                'number': '2',
                'label': 'OpenWrt 25.12.6 r33311-981c978eff',
                'os': '6.12.112',
                'mtd': 'mtd12',
              },
            ],
          },
        );
        final detector = AdvancedRebootDetector(apiService: api);

        final caps = await detector.detect(
          routerId: 'router_luci_adv_test',
          ipAddress: '192.168.1.1',
          sysauth: 'mock_token',
          useHttps: false,
        );

        expect(caps.environment.activeSlot, equals('2'));
        expect(caps.environment.alternateSlot, equals('1'));
        expect(caps.environment.activeOs, equals('OpenWrt 25.12.6'));
        expect(caps.environment.alternateOs, equals('OpenWrt 25.12.5'));
      },
    );

    test('Parses raw alternate OS string without KEY=VALUE pairs', () async {
      final api = ConfigurableRebootApiService(
        osReleaseContent: 'PRETTY_NAME="OpenWrt 25.12.6"\n',
        alternateOsContent: 'OpenWrt 25.12.5 r33051-f5dae5ece4\n',
      );
      final detector = AdvancedRebootDetector(apiService: api);

      final caps = await detector.detect(
        routerId: 'router_raw_os_test',
        ipAddress: '192.168.1.1',
        sysauth: 'mock_token',
        useHttps: false,
      );

      expect(caps.environment.activeOs, equals('OpenWrt 25.12.6'));
      expect(caps.environment.alternateOs, equals('OpenWrt 25.12.5'));
    });
  });
}
