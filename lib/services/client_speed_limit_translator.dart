// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:yet_another_luci_app/models/client_speed_limit.dart';

/// Translates [ClientSpeedLimit] definitions into high-performance Linux kernel traffic shaping
/// (`tc` with HTB + fq_codel) for download limiting and `nftables netdev ingress` for upload limiting.
///
/// This architecture bypasses OpenWrt hardware/software flow offloading limitations by hooking
/// directly into the network device egress queue (`tc` on bridge devices like `br-lan` and `br-guest`)
/// and device ingress (`table netdev client_limits` at priority filter - 10).
class ClientSpeedLimitTranslator {
  static const String scriptPath = '/usr/sbin/yala-qos';
  static const String initServicePath = '/etc/init.d/yala-qos';
  static const String legacyNftablesPath = '/etc/nftables.d/10-yala-qos.nft';
  static const String legacyScriptPath = '/etc/firewall.yala_qos.sh';
  static const String nftablesSnippetPath = '/etc/nftables.d/10-yala-qos.nft';

  /// Generates the complete `/usr/sbin/yala-qos` shell script for the router.
  static String generateQosScript(List<ClientSpeedLimit> limits) {
    final activeLimits = limits
        .where((l) => l.isEffectivelyRestricted)
        .toList();

    final buffer = StringBuffer();
    buffer.writeln('#!/bin/sh');
    buffer.writeln('# YALA Client Bandwidth Throttling Manager');
    buffer.writeln(
      '# Linux tc (HTB + fq_codel) for download shaping and nftables netdev ingress for upload shaping',
    );
    buffer.writeln('# Automatically managed by YALA - do not edit manually');
    buffer.writeln('');
    buffer.writeln('# Detect all active bridge interfaces, fallback to br-lan');
    buffer.writeln(
      "BRIDGES=\$(ls -d /sys/class/net/*/bridge 2>/dev/null | awk -F'/' '{print \$(NF-1)}')",
    );
    buffer.writeln('[ -z "\$BRIDGES" ] && BRIDGES="br-lan"');
    buffer.writeln('');
    buffer.writeln('stop_qos() {');
    buffer.writeln('    for dev in \$BRIDGES; do');
    buffer.writeln(
      '        tc filter del dev "\$dev" parent 1:0 prio 1 2>/dev/null',
    );
    buffer.writeln('        for cid in \$(seq 100 150); do');
    buffer.writeln(
      '            tc class del dev "\$dev" classid 1:\$cid 2>/dev/null',
    );
    buffer.writeln('        done');
    buffer.writeln(
      '        if [ \$(tc class show dev "\$dev" 2>/dev/null | grep -c "class htb") -le 2 ]; then',
    );
    buffer.writeln('            tc qdisc del dev "\$dev" root 2>/dev/null');
    buffer.writeln('        fi');
    buffer.writeln('        tc qdisc del dev "\$dev" ingress 2>/dev/null');
    buffer.writeln('    done');
    buffer.writeln('    if which nft >/dev/null 2>&1; then');
    buffer.writeln('        nft delete table netdev yala_qos 2>/dev/null');
    buffer.writeln('    fi');
    buffer.writeln('    if which iptables >/dev/null 2>&1; then');
    buffer.writeln('        iptables -D FORWARD -j YALA_QOS_FWD 2>/dev/null');
    buffer.writeln('        iptables -F YALA_QOS_FWD 2>/dev/null');
    buffer.writeln('        iptables -X YALA_QOS_FWD 2>/dev/null');
    buffer.writeln('    fi');
    buffer.writeln('    if which ip6tables >/dev/null 2>&1; then');
    buffer.writeln('        ip6tables -D FORWARD -j YALA_QOS_FWD 2>/dev/null');
    buffer.writeln('        ip6tables -F YALA_QOS_FWD 2>/dev/null');
    buffer.writeln('        ip6tables -X YALA_QOS_FWD 2>/dev/null');
    buffer.writeln('    fi');
    buffer.writeln('    rm -f /etc/nftables.d/10-yala-qos.nft 2>/dev/null');
    buffer.writeln('}');
    buffer.writeln('');
    buffer.writeln('apply_qos() {');
    buffer.writeln('    stop_qos');
    buffer.writeln('');
    if (activeLimits.isEmpty) {
      buffer.writeln('    return 0');
      buffer.writeln('}');
    } else {
      buffer.writeln('    if ! which tc >/dev/null 2>&1; then');
      buffer.writeln(
        '        logger -t yala-qos "Warning: tc not found on system"',
      );
      buffer.writeln('    fi');
      buffer.writeln('    HAS_NFT=0');
      buffer.writeln('    if which nft >/dev/null 2>&1; then');
      buffer.writeln('        HAS_NFT=1');
      buffer.writeln('        nft add table netdev yala_qos 2>/dev/null');
      buffer.writeln('    fi');
      buffer.writeln('    for dev in \$BRIDGES; do');
      buffer.writeln('        [ ! -d "/sys/class/net/\$dev" ] && continue');
      buffer.writeln(
        '        if ! tc qdisc show dev "\$dev" 2>/dev/null | grep -q "htb 1:"; then',
      );
      buffer.writeln(
        '            tc qdisc add dev "\$dev" root handle 1: htb default 10 2>/dev/null',
      );
      buffer.writeln(
        '            tc class add dev "\$dev" parent 1: classid 1:1 htb rate 1000mbit 2>/dev/null',
      );
      buffer.writeln(
        '            tc class add dev "\$dev" parent 1:1 classid 1:10 htb rate 1000mbit ceil 1000mbit 2>/dev/null',
      );
      buffer.writeln('        fi');
      buffer.writeln('        if [ "\$HAS_NFT" -eq 1 ]; then');
      buffer.writeln(
        '            nft add chain netdev yala_qos "\${dev}_upload" \'{ type filter hook ingress device "\'\$dev\'" priority filter - 10; policy accept; }\' 2>/dev/null',
      );
      buffer.writeln(
        '            for port in \$(ls -1 "/sys/class/net/\$dev/brif" 2>/dev/null); do',
      );
      buffer.writeln(
        '                nft add chain netdev yala_qos "\${port}_upload" \'{ type filter hook ingress device "\'\$port\'" priority filter - 10; policy accept; }\' 2>/dev/null',
      );
      buffer.writeln('            done');
      buffer.writeln('        else');
      buffer.writeln(
        '            tc qdisc add dev "\$dev" ingress 2>/dev/null',
      );
      buffer.writeln('        fi');
      buffer.writeln('    done');
      buffer.writeln('');
      for (var i = 0; i < activeLimits.length; i++) {
        final limit = activeLimits[i];
        final classid = 100 + i;
        final name = limit.hostname ?? limit.targetMac;
        final mac = limit.targetMac.trim();
        final macLower = mac.toLowerCase();
        final ip = limit.ipAddress.trim();
        final dlKbps = (limit.downloadBitsPerSecond / 1000.0).round();
        final ulKbps = (limit.uploadBitsPerSecond / 1000.0).round();
        final ulKbytes = (limit.uploadBitsPerSecond / 8000.0).round();
        final staticV6List = limit.ipv6Addresses
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .join(' ');

        buffer.writeln('    # Target: $name ($mac)');
        buffer.writeln('    for dev in \$BRIDGES; do');
        buffer.writeln('        [ ! -d "/sys/class/net/\$dev" ] && continue');
        buffer.writeln(
          '        PORTS="\$dev \$(ls -1 "/sys/class/net/\$dev/brif" 2>/dev/null)"',
        );
        buffer.writeln(
          '        # Resolve all IPv6 addresses for $mac from neighbor cache and host hints',
        );
        buffer.writeln(
          '        ALL_V6="$staticV6List \$(ip -6 neigh show 2>/dev/null | grep -i "$macLower" | awk \'{print \$1}\') \$(ubus call luci-rpc getHostHints 2>/dev/null | grep -i -A 10 "$macLower" | grep -oE \'([0-9a-fA-F]{1,4}:){1,7}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|fe80:[0-9a-fA-F:]+\' 2>/dev/null)"',
        );
        buffer.writeln(
          '        ALL_V6=\$(echo "\$ALL_V6" | tr \' \' \'\\n\' | sort -u)',
        );

        if (dlKbps > 0) {
          buffer.writeln('        # Download: $dlKbps kbit/s');
          buffer.writeln(
            '        tc class add dev "\$dev" parent 1:1 classid 1:$classid htb rate ${dlKbps}kbit ceil ${dlKbps}kbit 2>/dev/null',
          );
          buffer.writeln(
            '        tc qdisc add dev "\$dev" parent 1:$classid handle $classid: fq_codel 2>/dev/null || tc qdisc add dev "\$dev" parent 1:$classid handle $classid: pfifo_fast 2>/dev/null',
          );
          if (ip.isNotEmpty && ip != 'N/A') {
            buffer.writeln(
              '        tc filter add dev "\$dev" parent 1:0 prio 1 protocol ip u32 match ip dst $ip flowid 1:$classid 2>/dev/null',
            );
          }
          buffer.writeln('        for v6 in \$ALL_V6; do');
          buffer.writeln('            [ -z "\$v6" ] && continue');
          buffer.writeln(
            '            tc filter add dev "\$dev" parent 1:0 prio 1 protocol ipv6 u32 match ip6 dst "\$v6" flowid 1:$classid 2>/dev/null',
          );
          buffer.writeln('        done');
        }

        if (ulKbytes > 0) {
          buffer.writeln('        # Upload: $ulKbytes kbytes/s');
          buffer.writeln('        if [ "\$HAS_NFT" -eq 1 ]; then');
          buffer.writeln('            for p in \$PORTS; do');
          buffer.writeln(
            '                # Match by MAC address (covers both IPv4 and IPv6 traffic)',
          );
          buffer.writeln(
            '                nft add rule netdev yala_qos "\${p}_upload" ether saddr $macLower limit rate over $ulKbytes kbytes/second drop 2>/dev/null',
          );
          if (ip.isNotEmpty && ip != 'N/A') {
            buffer.writeln(
              '                nft add rule netdev yala_qos "\${p}_upload" ip saddr $ip limit rate over $ulKbytes kbytes/second drop 2>/dev/null',
            );
          }
          buffer.writeln('                for v6 in \$ALL_V6; do');
          buffer.writeln('                    [ -z "\$v6" ] && continue');
          buffer.writeln(
            '                    nft add rule netdev yala_qos "\${p}_upload" ip6 saddr "\$v6" limit rate over $ulKbytes kbytes/second drop 2>/dev/null',
          );
          buffer.writeln('                done');
          buffer.writeln('            done');
          buffer.writeln('        else');
          if (ip.isNotEmpty && ip != 'N/A') {
            buffer.writeln(
              '            tc filter add dev "\$dev" parent ffff: protocol ip prio 1 u32 match ip src $ip police rate ${ulKbps}kbit burst 64k drop flowid :1 2>/dev/null',
            );
          }
          buffer.writeln('            for v6 in \$ALL_V6; do');
          buffer.writeln('                [ -z "\$v6" ] && continue');
          buffer.writeln(
            '                tc filter add dev "\$dev" parent ffff: protocol ipv6 prio 1 u32 match ip6 src "\$v6" police rate ${ulKbps}kbit burst 64k drop flowid :1 2>/dev/null',
          );
          buffer.writeln('            done');
          buffer.writeln('        fi');
        }

        buffer.writeln('    done');
      }
      buffer.writeln('}');
    }

    buffer.writeln('');
    buffer.writeln('case "\$1" in');
    buffer.writeln('    apply|start)');
    buffer.writeln('        apply_qos');
    buffer.writeln('        ;;');
    buffer.writeln('    stop)');
    buffer.writeln('        stop_qos');
    buffer.writeln('        ;;');
    buffer.writeln('    restart)');
    buffer.writeln('        stop_qos');
    buffer.writeln('        apply_qos');
    buffer.writeln('        ;;');
    buffer.writeln('    *)');
    buffer.writeln('        apply_qos');
    buffer.writeln('        ;;');
    buffer.writeln('esac');
    return buffer.toString();
  }

  /// Generates the standard OpenWrt `/etc/init.d/yala-qos` service script for boot persistence.
  static String generateInitServiceScript() {
    final buffer = StringBuffer();
    buffer.writeln('#!/bin/sh /etc/rc.common');
    buffer.writeln('# YALA Client Bandwidth Throttling Service');
    buffer.writeln('START=99');
    buffer.writeln('USE_PROCD=0');
    buffer.writeln('');
    buffer.writeln('start() {');
    buffer.writeln('    [ -x /usr/sbin/yala-qos ] && /usr/sbin/yala-qos apply');
    buffer.writeln('}');
    buffer.writeln('');
    buffer.writeln('stop() {');
    buffer.writeln('    [ -x /usr/sbin/yala-qos ] && /usr/sbin/yala-qos stop');
    buffer.writeln('}');
    buffer.writeln('');
    buffer.writeln('restart() {');
    buffer.writeln('    stop');
    buffer.writeln('    start');
    buffer.writeln('}');
    return buffer.toString();
  }

  /// Generates backward-compatible nftables snippet (used for fw4 fallback/tests).
  static String generateNftablesSnippet(List<ClientSpeedLimit> limits) {
    final activeLimits = limits
        .where((l) => l.isEffectivelyRestricted)
        .toList();

    final buffer = StringBuffer();
    buffer.writeln('# YALA Client Bandwidth Throttling Configuration');
    buffer.writeln('# Automatically managed - do not edit manually');
    buffer.writeln('chain yala_qos_forward {');
    buffer.writeln('    type filter hook forward priority -1; policy accept;');

    if (activeLimits.isEmpty) {
      buffer.writeln('    # No clients currently restricted');
      buffer.writeln('}');
      return buffer.toString();
    }

    for (final limit in activeLimits) {
      final name = limit.hostname ?? limit.targetMac;
      final ip = limit.ipAddress.trim();
      final dlBytes = limit.downloadBytesPerSecondInt;
      final ulBytes = limit.uploadBytesPerSecondInt;
      final dlBurst = limit.downloadBurstBytes;
      final ulBurst = limit.uploadBurstBytes;

      buffer.writeln('');
      buffer.writeln('    # Target: $name (${limit.targetMac})');

      if (ip.isNotEmpty && ip != 'N/A') {
        if (dlBytes > 0) {
          buffer.writeln(
            '    ip daddr $ip limit rate over $dlBytes bytes/second burst $dlBurst bytes drop',
          );
        }
        if (ulBytes > 0) {
          buffer.writeln(
            '    ip saddr $ip oifname != "br-lan" limit rate over $ulBytes bytes/second burst $ulBurst bytes drop',
          );
        }
      }

      for (final v6 in limit.ipv6Addresses) {
        final cleanV6 = v6.trim();
        if (cleanV6.isEmpty || cleanV6.startsWith('fe80:')) continue;
        if (dlBytes > 0) {
          buffer.writeln(
            '    ip6 daddr $cleanV6 limit rate over $dlBytes bytes/second burst $dlBurst bytes drop',
          );
        }
        if (ulBytes > 0) {
          buffer.writeln(
            '    ip6 saddr $cleanV6 oifname != "br-lan" limit rate over $ulBytes bytes/second burst $ulBurst bytes drop',
          );
        }
      }
    }

    buffer.writeln('}');
    return buffer.toString();
  }

  /// Generates backward-compatible shell script for fw3/iptables.
  static String generateIptablesScript(List<ClientSpeedLimit> limits) {
    final activeLimits = limits
        .where((l) => l.isEffectivelyRestricted)
        .toList();

    final buffer = StringBuffer();
    buffer.writeln('#!/bin/sh');
    buffer.writeln('# YALA Client Bandwidth Throttling for fw3 (iptables)');
    buffer.writeln('');
    buffer.writeln('iptables -N YALA_QOS_FWD 2>/dev/null');
    buffer.writeln('iptables -F YALA_QOS_FWD');
    buffer.writeln(
      'iptables -C FORWARD -j YALA_QOS_FWD 2>/dev/null || iptables -I FORWARD 1 -j YALA_QOS_FWD',
    );
    buffer.writeln('ip6tables -N YALA_QOS_FWD 2>/dev/null');
    buffer.writeln('ip6tables -F YALA_QOS_FWD');
    buffer.writeln(
      'ip6tables -C FORWARD -j YALA_QOS_FWD 2>/dev/null || ip6tables -I FORWARD 1 -j YALA_QOS_FWD',
    );

    for (var i = 0; i < activeLimits.length; i++) {
      final limit = activeLimits[i];
      final ip = limit.ipAddress.trim();
      final dlKbps = (limit.downloadBitsPerSecond / 1000.0).round();
      final ulKbps = (limit.uploadBitsPerSecond / 1000.0).round();
      final tag = 'yala_$i';

      if (ip.isNotEmpty && ip != 'N/A') {
        if (dlKbps > 0) {
          buffer.writeln(
            'iptables -A YALA_QOS_FWD -d $ip -m hashlimit --hashlimit-above ${dlKbps}kb/s --hashlimit-mode dstip --hashlimit-name ${tag}_dl -j DROP',
          );
        }
        if (ulKbps > 0) {
          buffer.writeln(
            'iptables -A YALA_QOS_FWD -s $ip -o ! br-lan -m hashlimit --hashlimit-above ${ulKbps}kb/s --hashlimit-mode srcip --hashlimit-name ${tag}_ul -j DROP',
          );
        }
      }

      for (final v6 in limit.ipv6Addresses) {
        final cleanV6 = v6.trim();
        if (cleanV6.isEmpty || cleanV6.startsWith('fe80:')) continue;
        if (dlKbps > 0) {
          buffer.writeln(
            'ip6tables -A YALA_QOS_FWD -d $cleanV6 -m hashlimit --hashlimit-above ${dlKbps}kb/s --hashlimit-mode dstip --hashlimit-name ${tag}_dl6 -j DROP',
          );
        }
        if (ulKbps > 0) {
          buffer.writeln(
            'ip6tables -A YALA_QOS_FWD -s $cleanV6 -o ! br-lan -m hashlimit --hashlimit-above ${ulKbps}kb/s --hashlimit-mode srcip --hashlimit-name ${tag}_ul6 -j DROP',
          );
        }
      }
    }

    return buffer.toString();
  }
}
