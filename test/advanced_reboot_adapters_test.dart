// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/advanced_reboot/adapters/acpi_poweroff_adapter.dart';
import 'package:yet_another_luci_app/modules/advanced_reboot/adapters/boot_adapter_registry.dart';
import 'package:yet_another_luci_app/modules/advanced_reboot/adapters/standard_reboot_adapter.dart';
import 'package:yet_another_luci_app/modules/advanced_reboot/adapters/ubi_dual_boot_adapter.dart';
import 'package:yet_another_luci_app/modules/advanced_reboot/adapters/uboot_boot_part_adapter.dart';
import 'package:yet_another_luci_app/modules/advanced_reboot/adapters/uboot_boot_part_ready_adapter.dart';
import 'package:yet_another_luci_app/modules/advanced_reboot/adapters/uboot_dual_image_flag_adapter.dart';
import 'package:yet_another_luci_app/modules/advanced_reboot/models/reboot_capability.dart';

void main() {
  group('StandardRebootAdapter Tests', () {
    const adapter = StandardRebootAdapter();

    test('declares correct adapterId and operations', () {
      expect(adapter.adapterId, equals('standard_reboot'));
      expect(
        adapter.supportedOperations,
        contains(RebootOperationType.standardReboot),
      );
      expect(
        adapter.supportedOperations,
        isNot(contains(RebootOperationType.alternatePartitionBoot)),
      );
    });

    test('inspectCapabilities returns supported for standardReboot', () async {
      const env = DeviceBootEnvironment(
        boardName: 'generic,router',
        model: 'Generic Router',
        releaseVersion: '23.05.3',
      );
      final cap = await adapter.inspectCapabilities(
        environment: env,
        operation: RebootOperationType.standardReboot,
      );
      expect(cap.isSupported, isTrue);
      expect(cap.status, equals(CapabilityStatus.supported));
      expect(cap.riskLevel, equals(RiskLevel.low));
    });

    test(
      'inspectCapabilities returns unsupported for non-standardReboot',
      () async {
        const env = DeviceBootEnvironment(
          boardName: 'generic,router',
          model: 'Generic Router',
          releaseVersion: '23.05.3',
        );
        final cap = await adapter.inspectCapabilities(
          environment: env,
          operation: RebootOperationType.alternatePartitionBoot,
        );
        expect(cap.isUnsupported, isTrue);
      },
    );

    test('prepareOperation returns pre-approved reboot command', () {
      const env = DeviceBootEnvironment(
        boardName: 'generic,router',
        model: 'Generic Router',
        releaseVersion: '23.05.3',
      );
      final cmds = adapter.prepareOperation(
        environment: env,
        operation: RebootOperationType.standardReboot,
      );
      expect(
        cmds,
        equals([
          ['reboot'],
        ]),
      );
    });
  });

  group('UBootBootPartAdapter Tests', () {
    const adapter = UBootBootPartAdapter();

    test('evaluates single partition layout as unsupported', () async {
      const env = DeviceBootEnvironment(
        boardName: 'test,single',
        model: 'Single Boot Router',
        releaseVersion: '23.05.3',
        mtdPartitions: [
          MtdPartitionInfo(
            dev: 'mtd0',
            size: 0x10000,
            erasesize: 0x1000,
            name: 'kernel',
          ),
          MtdPartitionInfo(
            dev: 'mtd1',
            size: 0x20000,
            erasesize: 0x1000,
            name: 'rootfs',
          ),
        ],
      );
      final cap = await adapter.inspectCapabilities(
        environment: env,
        operation: RebootOperationType.alternatePartitionBoot,
      );
      expect(cap.isUnsupported, isTrue);
      expect(cap.reason, contains('single firmware layout'));
    });

    test('evaluates missing boot_part variable as unknown', () async {
      const env = DeviceBootEnvironment(
        boardName: 'test,dual',
        model: 'Dual Boot Router',
        releaseVersion: '23.05.3',
        mtdPartitions: [
          MtdPartitionInfo(
            dev: 'mtd0',
            size: 0x10000,
            erasesize: 0x1000,
            name: 'kernel',
          ),
          MtdPartitionInfo(
            dev: 'mtd1',
            size: 0x20000,
            erasesize: 0x1000,
            name: 'rootfs',
          ),
          MtdPartitionInfo(
            dev: 'mtd2',
            size: 0x10000,
            erasesize: 0x1000,
            name: 'alt_kernel',
          ),
          MtdPartitionInfo(
            dev: 'mtd3',
            size: 0x20000,
            erasesize: 0x1000,
            name: 'alt_rootfs',
          ),
        ],
        bootloaderEnv: {},
      );
      final cap = await adapter.inspectCapabilities(
        environment: env,
        operation: RebootOperationType.alternatePartitionBoot,
      );
      expect(cap.isUnknown, isTrue);
      expect(cap.reason, contains('boot_part'));
    });

    test('evaluates missing fw_setenv as unsupported', () async {
      const env = DeviceBootEnvironment(
        boardName: 'test,dual',
        model: 'Dual Boot Router',
        releaseVersion: '23.05.3',
        mtdPartitions: [
          MtdPartitionInfo(
            dev: 'mtd0',
            size: 0x10000,
            erasesize: 0x1000,
            name: 'kernel',
          ),
          MtdPartitionInfo(
            dev: 'mtd1',
            size: 0x20000,
            erasesize: 0x1000,
            name: 'rootfs',
          ),
          MtdPartitionInfo(
            dev: 'mtd2',
            size: 0x10000,
            erasesize: 0x1000,
            name: 'alt_kernel',
          ),
          MtdPartitionInfo(
            dev: 'mtd3',
            size: 0x20000,
            erasesize: 0x1000,
            name: 'alt_rootfs',
          ),
        ],
        bootloaderEnv: {'boot_part': '1'},
        hasFwPrintenv: true,
        hasFwSetenv: false,
      );
      final cap = await adapter.inspectCapabilities(
        environment: env,
        operation: RebootOperationType.alternatePartitionBoot,
      );
      expect(cap.isUnsupported, isTrue);
      expect(cap.missingOrConflictingEvidence, contains(contains('fw_setenv')));
    });

    test(
      'fully satisfied preconditions return supported with target slot',
      () async {
        const env = DeviceBootEnvironment(
          boardName: 'test,dual',
          model: 'Dual Boot Router',
          releaseVersion: '23.05.3',
          mtdPartitions: [
            MtdPartitionInfo(
              dev: 'mtd0',
              size: 0x10000,
              erasesize: 0x1000,
              name: 'kernel',
            ),
            MtdPartitionInfo(
              dev: 'mtd1',
              size: 0x20000,
              erasesize: 0x1000,
              name: 'rootfs',
            ),
            MtdPartitionInfo(
              dev: 'mtd2',
              size: 0x10000,
              erasesize: 0x1000,
              name: 'alt_kernel',
            ),
            MtdPartitionInfo(
              dev: 'mtd3',
              size: 0x20000,
              erasesize: 0x1000,
              name: 'alt_rootfs',
            ),
          ],
          bootloaderEnv: {'boot_part': '1'},
          hasFwPrintenv: true,
          hasFwSetenv: true,
        );
        final cap = await adapter.inspectCapabilities(
          environment: env,
          operation: RebootOperationType.alternatePartitionBoot,
        );
        expect(cap.isSupported, isTrue);
        expect(cap.targetIdentifier, equals('2'));
        expect(cap.mechanismId, equals('uboot_boot_part'));
      },
    );

    test('prepareOperation returns fixed pre-approved commands', () {
      const env = DeviceBootEnvironment(
        boardName: 'test,dual',
        model: 'Dual Boot Router',
        releaseVersion: '23.05.3',
      );
      final cmds = adapter.prepareOperation(
        environment: env,
        operation: RebootOperationType.alternatePartitionBoot,
        targetSlot: '2',
      );
      expect(
        cmds,
        equals([
          ['fw_setenv', 'boot_part', '2'],
          ['reboot'],
        ]),
      );
    });

    test('prepareOperation rejects invalid targetSlot', () {
      const env = DeviceBootEnvironment(
        boardName: 'test,dual',
        model: 'Dual Boot Router',
        releaseVersion: '23.05.3',
      );
      expect(
        () => adapter.prepareOperation(
          environment: env,
          operation: RebootOperationType.alternatePartitionBoot,
          targetSlot: '99',
        ),
        throwsArgumentError,
      );
    });
  });

  group('UBootBootPartReadyAdapter Tests', () {
    const adapter = UBootBootPartReadyAdapter();

    test(
      'returns unsupported when boot_part_ready variable is missing',
      () async {
        const env = DeviceBootEnvironment(
          boardName: 'test,dual',
          model: 'Dual Boot Router',
          releaseVersion: '23.05.3',
          mtdPartitions: [
            MtdPartitionInfo(
              dev: 'mtd0',
              size: 0x10000,
              erasesize: 0x1000,
              name: 'kernel',
            ),
            MtdPartitionInfo(
              dev: 'mtd1',
              size: 0x20000,
              erasesize: 0x1000,
              name: 'rootfs',
            ),
            MtdPartitionInfo(
              dev: 'mtd2',
              size: 0x10000,
              erasesize: 0x1000,
              name: 'alt_kernel',
            ),
            MtdPartitionInfo(
              dev: 'mtd3',
              size: 0x20000,
              erasesize: 0x1000,
              name: 'alt_rootfs',
            ),
          ],
          bootloaderEnv: {'boot_part': '1'},
          hasFwPrintenv: true,
          hasFwSetenv: true,
        );
        final cap = await adapter.inspectCapabilities(
          environment: env,
          operation: RebootOperationType.alternatePartitionBoot,
        );
        expect(cap.isUnsupported, isTrue);
      },
    );

    test(
      'returns supported when boot_part and boot_part_ready are present',
      () async {
        const env = DeviceBootEnvironment(
          boardName: 'linksys,ea8300',
          model: 'Linksys EA8300',
          releaseVersion: '23.05.3',
          mtdPartitions: [
            MtdPartitionInfo(
              dev: 'mtd0',
              size: 0x10000,
              erasesize: 0x1000,
              name: 'kernel',
            ),
            MtdPartitionInfo(
              dev: 'mtd1',
              size: 0x20000,
              erasesize: 0x1000,
              name: 'rootfs',
            ),
            MtdPartitionInfo(
              dev: 'mtd2',
              size: 0x10000,
              erasesize: 0x1000,
              name: 'alt_kernel',
            ),
            MtdPartitionInfo(
              dev: 'mtd3',
              size: 0x20000,
              erasesize: 0x1000,
              name: 'alt_rootfs',
            ),
          ],
          bootloaderEnv: {'boot_part': '2', 'boot_part_ready': '3'},
          hasFwPrintenv: true,
          hasFwSetenv: true,
        );
        final cap = await adapter.inspectCapabilities(
          environment: env,
          operation: RebootOperationType.alternatePartitionBoot,
        );
        expect(cap.isSupported, isTrue);
        expect(cap.targetIdentifier, equals('1'));
      },
    );

    test('prepareOperation sets both boot_part and boot_part_ready', () {
      const env = DeviceBootEnvironment(
        boardName: 'linksys,ea8300',
        model: 'Linksys EA8300',
        releaseVersion: '23.05.3',
      );
      final cmds = adapter.prepareOperation(
        environment: env,
        operation: RebootOperationType.alternatePartitionBoot,
        targetSlot: '1',
      );
      expect(
        cmds,
        equals([
          ['fw_setenv', 'boot_part', '1'],
          ['fw_setenv', 'boot_part_ready', '1'],
          ['reboot'],
        ]),
      );
    });
  });

  group('UBootDualImageFlagAdapter Tests', () {
    const adapter = UBootDualImageFlagAdapter();

    test('returns supported when DualImageFlag is 0', () async {
      const env = DeviceBootEnvironment(
        boardName: 'zyxel,dual-image',
        model: 'ZyXEL Router',
        releaseVersion: '23.05.3',
        mtdPartitions: [
          MtdPartitionInfo(
            dev: 'mtd0',
            size: 0x10000,
            erasesize: 0x1000,
            name: 'kernel',
          ),
          MtdPartitionInfo(
            dev: 'mtd1',
            size: 0x20000,
            erasesize: 0x1000,
            name: 'rootfs',
          ),
          MtdPartitionInfo(
            dev: 'mtd2',
            size: 0x10000,
            erasesize: 0x1000,
            name: 'kernel2',
          ),
          MtdPartitionInfo(
            dev: 'mtd3',
            size: 0x20000,
            erasesize: 0x1000,
            name: 'rootfs2',
          ),
        ],
        bootloaderEnv: {'DualImageFlag': '0'},
        hasFwPrintenv: true,
        hasFwSetenv: true,
      );
      final cap = await adapter.inspectCapabilities(
        environment: env,
        operation: RebootOperationType.alternatePartitionBoot,
      );
      expect(cap.isSupported, isTrue);
      expect(cap.targetIdentifier, equals('1'));
    });

    test('prepareOperation sets DualImageFlag and reboots', () {
      const env = DeviceBootEnvironment(
        boardName: 'zyxel,dual-image',
        model: 'ZyXEL Router',
        releaseVersion: '23.05.3',
      );
      final cmds = adapter.prepareOperation(
        environment: env,
        operation: RebootOperationType.alternatePartitionBoot,
        targetSlot: '1',
      );
      expect(
        cmds,
        equals([
          ['fw_setenv', 'DualImageFlag', '1'],
          ['reboot'],
        ]),
      );
    });
  });

  group('UbiDualBootAdapter Tests', () {
    const adapter = UbiDualBootAdapter();

    test('returns supported when UBI active variable is 0', () async {
      const env = DeviceBootEnvironment(
        boardName: 'avm,fritzbox-ubi',
        model: 'FRITZ!Box Router',
        releaseVersion: '23.05.3',
        mtdPartitions: [
          MtdPartitionInfo(
            dev: 'mtd0',
            size: 0x10000,
            erasesize: 0x1000,
            name: 'ubi',
          ),
        ],
        bootloaderEnv: {'active': '0'},
        hasFwPrintenv: true,
        hasFwSetenv: true,
      );
      final cap = await adapter.inspectCapabilities(
        environment: env,
        operation: RebootOperationType.alternatePartitionBoot,
      );
      expect(cap.isSupported, isTrue);
      expect(cap.targetIdentifier, equals('1'));
    });

    test('returns supported when UBI boot_bank variable is 1', () async {
      const env = DeviceBootEnvironment(
        boardName: 'glinet,ax1800',
        model: 'GL.iNet AX1800',
        releaseVersion: '23.05.3',
        mtdPartitions: [
          MtdPartitionInfo(
            dev: 'mtd0',
            size: 0x10000,
            erasesize: 0x1000,
            name: 'ubi',
          ),
        ],
        bootloaderEnv: {'boot_bank': '1'},
        hasFwPrintenv: true,
        hasFwSetenv: true,
      );
      final cap = await adapter.inspectCapabilities(
        environment: env,
        operation: RebootOperationType.alternatePartitionBoot,
      );
      expect(cap.isSupported, isTrue);
      expect(cap.targetIdentifier, equals('0'));
    });

    test('prepareOperation sets active variable and reboots', () {
      const env = DeviceBootEnvironment(
        boardName: 'avm,fritzbox-ubi',
        model: 'FRITZ!Box Router',
        releaseVersion: '23.05.3',
        bootloaderEnv: {'active': '0'},
      );
      final cmds = adapter.prepareOperation(
        environment: env,
        operation: RebootOperationType.alternatePartitionBoot,
        targetSlot: '1',
      );
      expect(
        cmds,
        equals([
          ['fw_setenv', 'active', '1'],
          ['reboot'],
        ]),
      );
    });
  });

  group('AcpiPowerOffAdapter Tests', () {
    const adapter = AcpiPowerOffAdapter();

    test('returns supported on x86_64 target architecture', () async {
      const env = DeviceBootEnvironment(
        boardName: 'x86/64',
        model: 'Generic x86/64 PC',
        releaseVersion: '23.05.3',
        targetArchitecture: 'x86/64',
      );
      final cap = await adapter.inspectCapabilities(
        environment: env,
        operation: RebootOperationType.powerOff,
      );
      expect(cap.isSupported, isTrue);
      expect(cap.riskLevel, equals(RiskLevel.medium));
      expect(cap.positiveEvidence, contains(contains('x86')));
    });

    test('returns unsupported on embedded ARM platform without PMIC', () async {
      const env = DeviceBootEnvironment(
        boardName: 'linksys,ea8300',
        model: 'Linksys EA8300',
        releaseVersion: '23.05.3',
        targetArchitecture: 'ipq40xx/generic',
      );
      final cap = await adapter.inspectCapabilities(
        environment: env,
        operation: RebootOperationType.powerOff,
      );
      expect(cap.isUnsupported, isTrue);
      expect(cap.reason, contains('Hardware DC power-down is not supported'));
    });

    test('prepareOperation returns pre-approved /sbin/poweroff command', () {
      const env = DeviceBootEnvironment(
        boardName: 'x86/64',
        model: 'Generic x86/64 PC',
        releaseVersion: '23.05.3',
      );
      final cmds = adapter.prepareOperation(
        environment: env,
        operation: RebootOperationType.powerOff,
      );
      expect(
        cmds,
        equals([
          ['/sbin/poweroff'],
        ]),
      );
    });
  });

  group('BootAdapterRegistry Tests', () {
    final registry = BootAdapterRegistry.instance;

    test('contains all 6 core adapters', () {
      expect(registry.allAdapters.length, equals(6));
      expect(registry.getAdapter('standard_reboot'), isNotNull);
      expect(registry.getAdapter('uboot_boot_part_ready'), isNotNull);
      expect(registry.getAdapter('uboot_boot_part'), isNotNull);
      expect(registry.getAdapter('uboot_dual_image_flag'), isNotNull);
      expect(registry.getAdapter('ubi_dual_boot'), isNotNull);
      expect(registry.getAdapter('acpi_poweroff'), isNotNull);
    });

    test('adaptersFor filters by operation type correctly', () {
      final rebootAdapters = registry.adaptersFor(
        RebootOperationType.standardReboot,
      );
      expect(rebootAdapters.length, equals(1));
      expect(rebootAdapters.first.adapterId, equals('standard_reboot'));

      final altBootAdapters = registry.adaptersFor(
        RebootOperationType.alternatePartitionBoot,
      );
      expect(altBootAdapters.length, equals(4));
      expect(
        altBootAdapters.map((a) => a.adapterId).toList(),
        equals([
          'uboot_boot_part_ready',
          'uboot_boot_part',
          'uboot_dual_image_flag',
          'ubi_dual_boot',
        ]),
      );

      final poweroffAdapters = registry.adaptersFor(
        RebootOperationType.powerOff,
      );
      expect(poweroffAdapters.length, equals(1));
      expect(poweroffAdapters.first.adapterId, equals('acpi_poweroff'));
    });
  });
}
