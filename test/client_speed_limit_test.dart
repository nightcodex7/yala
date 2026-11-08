// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/client_speed_limit.dart';
import 'package:yet_another_luci_app/services/client_speed_limit_translator.dart';

void main() {
  group('ClientSpeedLimit conversion and formatting tests', () {
    test('10 Mbps download and 2 Mbps upload conversion accuracy', () {
      final limit = ClientSpeedLimit(
        targetMac: 'AA:BB:CC:DD:EE:FF',
        ipAddress: '192.168.1.150',
        downloadValue: 10,
        downloadUnit: 'Mbps',
        uploadValue: 2,
        uploadUnit: 'Mbps',
        enabled: true,
        updatedAt: DateTime(2026, 11, 3),
      );

      // Bits per second
      expect(limit.downloadBitsPerSecond, 10000000.0);
      expect(limit.uploadBitsPerSecond, 2000000.0);

      // Bytes per second (netfilter tokens)
      expect(limit.downloadBytesPerSecond, 1250000.0);
      expect(limit.uploadBytesPerSecond, 250000.0);
      expect(limit.downloadBytesPerSecondInt, 1250000);
      expect(limit.uploadBytesPerSecondInt, 250000);

      // Formatted speeds
      expect(limit.formattedDownloadSpeed, contains('10'));
      expect(limit.formattedDownloadSpeed, contains('Mbps'));
      expect(limit.formattedUploadSpeed, contains('2'));
      expect(limit.formattedUploadSpeed, contains('Mbps'));
      expect(limit.isEffectivelyRestricted, isTrue);
    });

    test('512 Kbps upload conversion accuracy', () {
      final limit = ClientSpeedLimit(
        targetMac: 'AA:BB:CC:DD:EE:FF',
        ipAddress: '192.168.1.150',
        downloadValue: 1,
        downloadUnit: 'Mbps',
        uploadValue: 512,
        uploadUnit: 'Kbps',
        enabled: true,
        updatedAt: DateTime(2026, 11, 3),
      );

      // 512 Kbps = 512,000 bits/sec
      expect(limit.uploadBitsPerSecond, 512000.0);
      // 512,000 / 8 = 64,000 bytes/sec
      expect(limit.uploadBytesPerSecond, 64000.0);
      expect(limit.uploadBytesPerSecondInt, 64000);
      expect(limit.formattedUploadSpeed, contains('512'));
      expect(limit.formattedUploadSpeed, contains('Kbps'));
    });

    test('Disabled or zero rate limit is not effectively restricted', () {
      final limit = ClientSpeedLimit.unrestricted(
        targetMac: 'AA:BB:CC:DD:EE:FF',
        ipAddress: '192.168.1.150',
      );
      expect(limit.isEffectivelyRestricted, isFalse);
      expect(limit.compactSummary, 'Unrestricted');
      expect(limit.formattedDownloadSpeed, 'Unlimited');
      expect(limit.formattedUploadSpeed, 'Unlimited');
    });

    test('JSON serialization round-trip', () {
      final original = ClientSpeedLimit(
        targetMac: 'AA:BB:CC:DD:EE:FF',
        ipAddress: '192.168.1.150',
        ipv6Addresses: const ['2400:1234::1'],
        downloadValue: 15,
        downloadUnit: 'Mbps',
        uploadValue: 5,
        uploadUnit: 'Mbps',
        enabled: true,
        hostname: 'Work-MacBook',
        updatedAt: DateTime(2026, 11, 3, 12, 0, 0),
      );

      final json = original.toJson();
      final reconstituted = ClientSpeedLimit.fromJson(json);

      expect(reconstituted, equals(original));
      expect(reconstituted.hostname, 'Work-MacBook');
      expect(reconstituted.ipv6Addresses, const ['2400:1234::1']);
    });
  });

  group('ClientSpeedLimitTranslator tests', () {
    test('generateQosScript creates valid tc HTB and nftables netdev rules', () {
      final limits = [
        ClientSpeedLimit(
          targetMac: 'AA:BB:CC:DD:EE:FF',
          ipAddress: '192.168.1.150',
          ipv6Addresses: const ['2400:abcd::50'],
          downloadValue: 10,
          downloadUnit: 'Mbps',
          uploadValue: 2,
          uploadUnit: 'Mbps',
          enabled: true,
          hostname: 'GuestPhone',
          updatedAt: DateTime(2026, 11, 3),
        ),
      ];

      final script = ClientSpeedLimitTranslator.generateQosScript(limits);

      expect(script, contains('#!/bin/sh'));
      expect(script, contains('stop_qos() {'));
      expect(script, contains('apply_qos() {'));
      expect(script, contains('BRIDGES='));
      expect(
        script,
        contains('tc qdisc add dev "\$dev" root handle 1: htb default 10'),
      );
      expect(
        script,
        contains(
          'tc class add dev "\$dev" parent 1: classid 1:1 htb rate 1000mbit',
        ),
      );
      expect(
        script,
        contains(
          'tc class add dev "\$dev" parent 1:1 classid 1:10 htb rate 1000mbit ceil 1000mbit',
        ),
      );
      // 10 Mbps = 10000 kbit
      expect(
        script,
        contains(
          'tc class add dev "\$dev" parent 1:1 classid 1:100 htb rate 10000kbit ceil 10000kbit',
        ),
      );
      expect(script, contains('fq_codel'));
      expect(
        script,
        contains(
          'tc filter add dev "\$dev" parent 1:0 prio 1 protocol ip u32 match ip dst 192.168.1.150 flowid 1:100',
        ),
      );
      // 2 Mbps = 250 kbytes/s (2,000,000 / 8,000)
      expect(script, contains('nft add table netdev yala_qos'));
      expect(script, contains('priority filter - 10'));
      expect(
        script,
        contains(
          'nft add rule netdev yala_qos "\${p}_upload" ether saddr aa:bb:cc:dd:ee:ff limit rate over 250 kbytes/second drop',
        ),
      );
      expect(
        script,
        contains(
          'nft add rule netdev yala_qos "\${p}_upload" ip saddr 192.168.1.150 limit rate over 250 kbytes/second drop',
        ),
      );
      // IPv6 rules
      expect(
        script,
        contains(
          'tc filter add dev "\$dev" parent 1:0 prio 1 protocol ipv6 u32 match ip6 dst "\$v6" flowid 1:100',
        ),
      );
      expect(
        script,
        contains(
          'nft add rule netdev yala_qos "\${p}_upload" ip6 saddr "\$v6" limit rate over 250 kbytes/second drop',
        ),
      );
      // tc policer fallback for non-nft systems
      expect(script, contains('police rate 2000kbit burst 64k drop'));
    });

    test('generateQosScript handles empty limits safely', () {
      final script = ClientSpeedLimitTranslator.generateQosScript([]);
      expect(script, contains('apply_qos() {'));
      expect(script, contains('stop_qos'));
      expect(script, contains('return 0'));
      expect(script, isNot(contains('htb rate 1000mbit')));
    });

    test(
      'generateInitServiceScript creates valid OpenWrt rc.common init script',
      () {
        final initScript =
            ClientSpeedLimitTranslator.generateInitServiceScript();
        expect(initScript, contains('#!/bin/sh /etc/rc.common'));
        expect(initScript, contains('START=99'));
        expect(initScript, contains('USE_PROCD=0'));
        expect(initScript, contains('/usr/sbin/yala-qos apply'));
        expect(initScript, contains('/usr/sbin/yala-qos stop'));
      },
    );

    test('generateNftablesSnippet creates valid forward chain with drop rules', () {
      final limits = [
        ClientSpeedLimit(
          targetMac: 'AA:BB:CC:DD:EE:FF',
          ipAddress: '192.168.1.150',
          ipv6Addresses: const ['2400:abcd::50'],
          downloadValue: 10,
          downloadUnit: 'Mbps',
          uploadValue: 2,
          uploadUnit: 'Mbps',
          enabled: true,
          hostname: 'GuestPhone',
          updatedAt: DateTime(2026, 11, 3),
        ),
      ];

      final snippet = ClientSpeedLimitTranslator.generateNftablesSnippet(
        limits,
      );

      expect(snippet, contains('chain yala_qos_forward {'));
      expect(
        snippet,
        contains('type filter hook forward priority -1; policy accept;'),
      );
      // 10 Mbps = 1,250,000 bytes/second
      expect(
        snippet,
        contains('ip daddr 192.168.1.150 limit rate over 1250000 bytes/second'),
      );
      // 2 Mbps = 250,000 bytes/second
      expect(
        snippet,
        contains(
          'ip saddr 192.168.1.150 oifname != "br-lan" limit rate over 250000 bytes/second',
        ),
      );
      // IPv6 drop rules
      expect(
        snippet,
        contains(
          'ip6 daddr 2400:abcd::50 limit rate over 1250000 bytes/second',
        ),
      );
      expect(
        snippet,
        contains(
          'ip6 saddr 2400:abcd::50 oifname != "br-lan" limit rate over 250000 bytes/second',
        ),
      );
    });

    test('generateNftablesSnippet handles empty or disabled limits safely', () {
      final snippet = ClientSpeedLimitTranslator.generateNftablesSnippet([]);
      expect(snippet, contains('chain yala_qos_forward {'));
      expect(snippet, contains('policy accept;'));
      expect(snippet, contains('# No clients currently restricted'));
      expect(snippet, isNot(contains('drop')));
    });

    test('generateIptablesScript creates valid hashlimit rules for fw3', () {
      final limits = [
        ClientSpeedLimit(
          targetMac: 'AA:BB:CC:DD:EE:FF',
          ipAddress: '192.168.1.150',
          downloadValue: 10,
          downloadUnit: 'Mbps',
          uploadValue: 1,
          uploadUnit: 'Mbps',
          enabled: true,
          updatedAt: DateTime(2026, 11, 3),
        ),
      ];

      final script = ClientSpeedLimitTranslator.generateIptablesScript(limits);
      expect(script, contains('iptables -N YALA_QOS_FWD'));
      expect(script, contains('--hashlimit-above 10000kb/s'));
      expect(script, contains('--hashlimit-above 1000kb/s'));
      expect(script, contains('-o ! br-lan'));
    });
  });
}
