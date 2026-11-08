// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/advanced_reboot/models/reboot_capability.dart';
import 'package:yet_another_luci_app/modules/advanced_reboot/profiles/device_profile.dart';
import 'package:yet_another_luci_app/modules/advanced_reboot/profiles/device_profile_registry.dart';

void main() {
  group('DeviceProfile Tests', () {
    const ea8300 = DeviceProfile(
      profileId: 'linksys_ea8300',
      displayName: 'Linksys EA8300',
      compatibleBoardIds: {'linksys,ea8300', 'linksys_ea8300'},
      compatibleModels: {'Linksys EA8300'},
      targetArchitecture: 'ipq40xx/generic',
      supportedOperations: {
        RebootOperationType.standardReboot,
        RebootOperationType.alternatePartitionBoot,
      },
      partitionMechanism: PartitionMechanism.uBootEnvBootPartReady,
      requiredMtdPartitionNames: {'alt_kernel', 'alt_rootfs'},
      requiredUtilities: {'fw_printenv', 'fw_setenv'},
      validPartitionSlots: ['1', '2'],
      poweroffSupported: false,
      documentationUrl: 'https://openwrt.org/toh/linksys/ea8300',
      notes: 'Test profile',
      lastReviewed: '2026-10-25',
    );

    test('Exact board ID matches correctly', () {
      expect(ea8300.matches(boardName: 'linksys,ea8300'), isTrue);
      expect(ea8300.matches(boardName: 'linksys_ea8300'), isTrue);
      expect(ea8300.matches(boardName: 'LINKSYS,EA8300'), isTrue);
    });

    test('Unrelated board ID does not match', () {
      expect(ea8300.matches(boardName: 'tp-link,archer-c7-v2'), isFalse);
      expect(ea8300.matches(boardName: 'xiaomi,ax3600'), isFalse);
      expect(ea8300.matches(boardName: ''), isFalse);
    });

    test('Model name alone does not match if board name differs', () {
      expect(
        ea8300.matches(boardName: 'random_board_id', model: 'Linksys EA8300'),
        isFalse,
      );
    });

    test('Calculates alternate slot correctly', () {
      expect(ea8300.getAlternateSlot('1'), equals('2'));
      expect(ea8300.getAlternateSlot('2'), equals('1'));
      expect(ea8300.getAlternateSlot('invalid'), isNull);
    });

    test('Generates fixed, pre-approved switch commands for target slot', () {
      final cmds = ea8300.getSwitchPartitionCommands('2');
      expect(cmds.length, equals(2));
      expect(cmds[0], equals(['fw_setenv', 'boot_part', '2']));
      expect(cmds[1], equals(['fw_setenv', 'boot_part_ready', '2']));
    });

    test('Rejects invalid target slot with ArgumentError', () {
      expect(() => ea8300.getSwitchPartitionCommands('3'), throwsArgumentError);
      expect(
        () => ea8300.getSwitchPartitionCommands('slot_invalid; rm -rf /'),
        throwsArgumentError,
      );
    });
  });

  group('DeviceProfileRegistry Tests', () {
    final registry = DeviceProfileRegistry.instance;

    test('Registry contains curated Linksys EA8300 profile', () {
      final res = registry.findMatchingProfile(
        boardName: 'linksys,ea8300',
        model: 'Linksys EA8300',
      );
      expect(res.hasMatch, isTrue);
      expect(res.profile?.profileId, equals('linksys_ea8300'));
      expect(res.isAmbiguous, isFalse);
    });

    test('Registry contains curated Linksys WRT3200ACM profile', () {
      final res = registry.findMatchingProfile(
        boardName: 'linksys,wrt3200acm',
        model: 'Linksys WRT3200ACM',
      );
      expect(res.hasMatch, isTrue);
      expect(res.profile?.profileId, equals('linksys_wrt3200acm'));
    });

    test('Registry returns noMatch for uncurated device', () {
      final res = registry.findMatchingProfile(
        boardName: 'gl-inet,gl-mt3000',
        model: 'GL.iNet GL-MT3000',
      );
      expect(res.hasMatch, isFalse);
      expect(res.profile, isNull);
      expect(res.isAmbiguous, isFalse);
      expect(res.message, contains('No verified device profile matches'));
    });

    test('Registry returns noMatch for empty board identifier', () {
      final res = registry.findMatchingProfile(boardName: '');
      expect(res.hasMatch, isFalse);
      expect(res.profile, isNull);
    });
  });
}
