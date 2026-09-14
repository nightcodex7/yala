// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

/// WireGuard Peer details.
class WireguardPeer {
  final String publicKey;
  final String? endpoint;
  final List<String> allowedIps;
  final num rxBytes;
  final num txBytes;
  final int? latestHandshakeTimestamp;

  const WireguardPeer({
    required this.publicKey,
    this.endpoint,
    required this.allowedIps,
    required this.rxBytes,
    required this.txBytes,
    this.latestHandshakeTimestamp,
  });

  factory WireguardPeer.fromJson(Map<String, dynamic> json) {
    final ips = <String>[];
    final allowed = json['allowed_ips'];
    if (allowed is List) {
      ips.addAll(allowed.map((e) => e.toString()));
    } else if (allowed is String) {
      ips.add(allowed);
    }

    return WireguardPeer(
      publicKey: json['public_key']?.toString() ?? 'Unknown Key',
      endpoint: json['endpoint']?.toString(),
      allowedIps: ips,
      rxBytes: (json['rx_bytes'] as num?) ?? 0,
      txBytes: (json['tx_bytes'] as num?) ?? 0,
      latestHandshakeTimestamp: (json['latest_handshake'] as num?)?.toInt(),
    );
  }

  String get formattedHandshake {
    if (latestHandshakeTimestamp == null || latestHandshakeTimestamp == 0) {
      return 'No handshake yet';
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final diff = now - latestHandshakeTimestamp!;
    if (diff < 60) return '$diff seconds ago';
    if (diff < 3600) return '${diff ~/ 60}m ${diff % 60}s ago';
    return '${diff ~/ 3600}h ago';
  }
}

/// WireGuard Interface definition.
class WireguardInterface {
  final String name;
  final String publicKey;
  final int listenPort;
  final bool isUp;
  final List<WireguardPeer> peers;

  const WireguardInterface({
    required this.name,
    required this.publicKey,
    required this.listenPort,
    required this.isUp,
    required this.peers,
  });

  factory WireguardInterface.fromJson(String name, Map<String, dynamic> json) {
    final peerList = <WireguardPeer>[];
    final rawPeers = json['peers'];
    if (rawPeers is List) {
      for (final p in rawPeers) {
        if (p is Map<String, dynamic>) {
          peerList.add(WireguardPeer.fromJson(p));
        }
      }
    } else if (rawPeers is Map) {
      rawPeers.forEach((_, p) {
        if (p is Map<String, dynamic>) {
          peerList.add(WireguardPeer.fromJson(p));
        }
      });
    }

    final upVal = json['up'] ?? json['is_up'] ?? json['status'];
    final isUp = upVal == true || upVal == 1 || upVal == '1' || upVal == 'up';

    return WireguardInterface(
      name: name,
      publicKey: json['public_key']?.toString() ?? 'WgPubKeyString...',
      listenPort: (json['listen_port'] as num?)?.toInt() ?? 51820,
      isUp: isUp,
      peers: peerList,
    );
  }
}

/// OpenVPN Instance definition.
class OpenVpnInstance {
  final String name;
  final bool isEnabled;
  final bool isRunning;
  final String port;
  final String proto;
  final String dev;

  const OpenVpnInstance({
    required this.name,
    required this.isEnabled,
    required this.isRunning,
    required this.port,
    required this.proto,
    required this.dev,
  });

  factory OpenVpnInstance.fromJson(String name, Map<String, dynamic> json) {
    final enabledVal = json['enabled'];
    final disabledVal = json['disabled'];
    final isEnabled =
        enabledVal != '0' &&
        enabledVal != false &&
        disabledVal != '1' &&
        disabledVal != true;

    final runningVal = json['running'] ?? json['is_running'] ?? json['up'];
    final isRunning =
        runningVal == true ||
        runningVal == 1 ||
        runningVal == '1' ||
        runningVal == 'up';

    return OpenVpnInstance(
      name: name,
      isEnabled: isEnabled,
      isRunning: isRunning,
      port: json['port']?.toString() ?? '1194',
      proto: json['proto']?.toString() ?? 'udp',
      dev: json['dev']?.toString() ?? 'tun',
    );
  }
}

/// Tailscale node status.
class TailscaleStatus {
  final bool isConfigured;
  final bool isRunning;
  final String nodeName;
  final String tailscaleIp;
  final String backendState;
  final String tailnet;
  final String magicDns;
  final int peersCount;
  final bool isExitNode;

  const TailscaleStatus({
    required this.isConfigured,
    required this.isRunning,
    required this.nodeName,
    required this.tailscaleIp,
    required this.backendState,
    this.tailnet = '',
    this.magicDns = '',
    this.peersCount = 0,
    this.isExitNode = false,
  });

  factory TailscaleStatus.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const TailscaleStatus(
        isConfigured: false,
        isRunning: false,
        nodeName: '',
        tailscaleIp: '',
        backendState: 'Disabled',
      );
    }
    final nodeName =
        json['node_name']?.toString() ?? json['hostname']?.toString() ?? '';
    final ip = json['ip']?.toString() ?? json['tailscale_ip']?.toString() ?? '';
    final state = json['state']?.toString() ?? 'Disabled';
    final isConfig =
        json['configured'] == true || nodeName.isNotEmpty || ip.isNotEmpty;
    return TailscaleStatus(
      isConfigured: isConfig,
      isRunning: json['running'] == true || state == 'Running',
      nodeName: nodeName.isNotEmpty ? nodeName : 'OpenWrt-Node',
      tailscaleIp: ip,
      backendState: state,
      tailnet: json['tailnet']?.toString() ?? '',
      magicDns: json['magic_dns']?.toString() ?? '',
      peersCount: (json['peers_count'] as num?)?.toInt() ?? 0,
      isExitNode: json['is_exit_node'] == true || json['is_exit_node'] == '1',
    );
  }
}

/// NextDNS / Encrypted DNS status.
class NextDnsStatus {
  final bool isConfigured;
  final bool isEnabled;
  final bool isRunning;
  final String profileId;
  final bool reportClientInfo;

  const NextDnsStatus({
    required this.isConfigured,
    required this.isEnabled,
    required this.isRunning,
    required this.profileId,
    required this.reportClientInfo,
  });

  factory NextDnsStatus.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const NextDnsStatus(
        isConfigured: false,
        isEnabled: false,
        isRunning: false,
        profileId: '',
        reportClientInfo: false,
      );
    }
    final profile = json['profile']?.toString() ?? '';
    final isConfig = json['configured'] == true || profile.isNotEmpty;
    final isEnabled = json['enabled'] == '1' || json['enabled'] == true;
    final isRunning =
        json['running'] == true ||
        json['running'] == 1 ||
        (json.containsKey('running') ? json['running'] == true : isEnabled);
    return NextDnsStatus(
      isConfigured: isConfig,
      isEnabled: isEnabled,
      isRunning: isRunning,
      profileId: profile,
      reportClientInfo:
          json['report_client_info'] == '1' ||
          json['report_client_info'] == true,
    );
  }
}

/// Cloudflared / Cloudflare Tunnel status.
class CloudflaredStatus {
  final bool isConfigured;
  final bool isEnabled;
  final bool isRunning;
  final String tunnelId;
  final String tunnelName;
  final String token;
  final int connectionsCount;

  const CloudflaredStatus({
    required this.isConfigured,
    required this.isEnabled,
    required this.isRunning,
    required this.tunnelId,
    required this.tunnelName,
    required this.token,
    required this.connectionsCount,
  });

  factory CloudflaredStatus.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const CloudflaredStatus(
        isConfigured: false,
        isEnabled: false,
        isRunning: false,
        tunnelId: '',
        tunnelName: '',
        token: '',
        connectionsCount: 0,
      );
    }
    final tunnelId = extractTunnelId(json);
    final tunnelName =
        json['tunnel_name']?.toString() ?? json['name']?.toString() ?? '';
    final token =
        json['token']?.toString() ?? json['tunnel_token']?.toString() ?? '';
    final isConfigured =
        json['configured'] == true ||
        (tunnelId.isNotEmpty && tunnelId != 'N/A') ||
        token.isNotEmpty ||
        tunnelName.isNotEmpty;
    final isEnabled =
        json['enabled'] == '1' ||
        json['enabled'] == true ||
        json['enable'] == '1' ||
        json['enable'] == true;
    final isRunning =
        json['running'] == true ||
        json['running'] == 1 ||
        (isEnabled && isConfigured);
    final connCount =
        (json['connections'] as num?)?.toInt() ??
        (json['connections_count'] as num?)?.toInt() ??
        (isRunning ? 4 : 0);

    return CloudflaredStatus(
      isConfigured: isConfigured,
      isEnabled: isEnabled,
      isRunning: isRunning,
      tunnelId: tunnelId.isNotEmpty ? tunnelId : 'N/A',
      tunnelName: tunnelName.isNotEmpty
          ? tunnelName
          : ((tunnelId.isNotEmpty && tunnelId != 'N/A')
                ? 'Cloudflare Tunnel'
                : ''),
      token: token,
      connectionsCount: connCount,
    );
  }

  static String extractTunnelId(Map<String, dynamic> json) {
    // 1. Check explicit keys
    final explicitKeys = [
      'tunnel_id',
      'tunnelid',
      'tunnel_uuid',
      'uuid',
      'id',
      'tunnel',
    ];
    for (final k in explicitKeys) {
      final val = json[k]?.toString().trim();
      if (val != null && val.isNotEmpty) {
        if (val != 'config' &&
            val != 'main' &&
            val != 'global' &&
            val != 'true' &&
            val != 'false') {
          return val;
        }
      }
    }

    // 2. Check section name or .name for UUID
    final nameKey = json['.name']?.toString() ?? json['name']?.toString() ?? '';
    final uuidRegex = RegExp(
      r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
    );
    final nameMatch = uuidRegex.firstMatch(nameKey);
    if (nameMatch != null) {
      return nameMatch.group(0)!;
    }

    // 3. Check credentials_file, origincert, config_file, or config paths for UUID
    final pathKeys = [
      'credentials_file',
      'credentials',
      'origincert',
      'config_file',
      'config',
    ];
    for (final k in pathKeys) {
      final pathVal = json[k]?.toString();
      if (pathVal != null && pathVal.isNotEmpty) {
        final match = uuidRegex.firstMatch(pathVal);
        if (match != null) {
          return match.group(0)!;
        }
      }
    }

    // 4. Try decoding token (Base64 / JWT Cloudflare Tunnel Token)
    final tokenVal =
        json['token']?.toString() ??
        json['tunnel_token']?.toString() ??
        json['secret']?.toString() ??
        '';
    if (tokenVal.isNotEmpty) {
      final decodedId = _extractTunnelIdFromToken(tokenVal);
      if (decodedId.isNotEmpty) {
        return decodedId;
      }
    }

    // 5. Fallback: check any string value in the json map for UUID regex match
    for (final val in json.values) {
      if (val is String && val.isNotEmpty) {
        final match = uuidRegex.firstMatch(val);
        if (match != null) {
          return match.group(0)!;
        }
      }
    }

    return '';
  }

  static String _extractTunnelIdFromToken(String token) {
    try {
      String cleanToken = token.trim();
      if (cleanToken.contains('.')) {
        final parts = cleanToken.split('.');
        if (parts.length >= 2) {
          cleanToken = parts[1];
        }
      }

      final normalized = base64.normalize(cleanToken);
      final decodedBytes = base64.decode(normalized);
      final decodedStr = utf8.decode(decodedBytes, allowMalformed: true);

      final uuidRegex = RegExp(
        r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
      );
      final match = uuidRegex.firstMatch(decodedStr);
      if (match != null) {
        return match.group(0)!;
      }

      if (decodedStr.contains('{')) {
        final parsed = jsonDecode(decodedStr);
        if (parsed is Map) {
          final tVal =
              parsed['t']?.toString() ??
              parsed['tunnel_id']?.toString() ??
              parsed['tunnelId']?.toString();
          if (tVal != null && tVal.isNotEmpty) {
            return tVal;
          }
        }
      }
    } catch (_) {}
    return '';
  }
}

/// Complete VPN & Connectivity overview container.
class VpnConnectivityOverview {
  final List<WireguardInterface> wireguardInterfaces;
  final List<OpenVpnInstance> openvpnInstances;
  final TailscaleStatus tailscale;
  final NextDnsStatus nextdns;
  final CloudflaredStatus cloudflared;

  const VpnConnectivityOverview({
    required this.wireguardInterfaces,
    required this.openvpnInstances,
    required this.tailscale,
    required this.nextdns,
    required this.cloudflared,
  });

  factory VpnConnectivityOverview.fromDashboardData(
    Map<String, dynamic>? data, {
    bool isReviewerMode = false,
  }) {
    final wgList = <WireguardInterface>[];
    final ovpnList = <OpenVpnInstance>[];
    Map<String, dynamic>? tsRaw;
    Map<String, dynamic>? ndnsRaw;
    Map<String, dynamic>? cfRaw;

    if (data != null) {
      final wgMap = data['wireguard'] as Map<String, dynamic>?;
      if (wgMap != null) {
        wgMap.forEach((name, val) {
          if (val is Map<String, dynamic>) {
            wgList.add(WireguardInterface.fromJson(name, val));
          }
        });
      }

      final ovpnMap = data['openvpn'] as Map<String, dynamic>?;
      if (ovpnMap != null) {
        ovpnMap.forEach((name, val) {
          if (val is Map<String, dynamic>) {
            ovpnList.add(OpenVpnInstance.fromJson(name, val));
          }
        });
      }

      final rawDump = data['interfaceDump'];
      List<dynamic>? interfaces;
      if (rawDump is List) {
        interfaces = rawDump;
      } else if (rawDump is Map) {
        final list = rawDump['interface'];
        if (list is List) interfaces = list;
      }
      if (interfaces != null) {
        for (final item in interfaces) {
          if (item is Map<String, dynamic>) {
            final ifname = item['interface']?.toString() ?? '';
            final proto = item['proto']?.toString().toLowerCase() ?? '';
            final dev =
                (item['device'] ?? item['l3_device'])
                    ?.toString()
                    .toLowerCase() ??
                '';
            final isUp =
                item['up'] == true || item['up'] == 1 || item['up'] == '1';

            if (ifname.isNotEmpty) {
              if (proto == 'wireguard' ||
                  (dev.isNotEmpty && dev.startsWith('wg'))) {
                if (!wgList.any(
                  (w) => w.name == ifname || (dev.isNotEmpty && w.name == dev),
                )) {
                  wgList.add(
                    WireguardInterface(
                      name: ifname,
                      publicKey: '',
                      listenPort: 51820,
                      isUp: isUp,
                      peers: const [],
                    ),
                  );
                }
              } else if (proto == 'openvpn' ||
                  (dev.isNotEmpty &&
                      (dev.startsWith('tun') || dev.startsWith('tap'))) ||
                  ifname.toLowerCase().contains('openvpn') ||
                  ifname.toLowerCase().contains('ovpn')) {
                if (!ovpnList.any(
                  (o) =>
                      o.name == ifname ||
                      (dev.isNotEmpty && (o.name == dev || o.dev == dev)),
                )) {
                  ovpnList.add(
                    OpenVpnInstance(
                      name: ifname,
                      isEnabled: true,
                      isRunning: isUp,
                      port: '1194',
                      proto: 'udp',
                      dev: dev.isNotEmpty ? dev : 'tun',
                    ),
                  );
                }
              }
            }
          }
        }
      }

      tsRaw = data['tailscale'] as Map<String, dynamic>?;
      ndnsRaw = data['nextdns'] as Map<String, dynamic>?;
      cfRaw = data['cloudflared'] as Map<String, dynamic>?;
    }

    // Default mock data only if in Reviewer Mode
    if (isReviewerMode) {
      if (wgList.isEmpty) {
        wgList.add(
          WireguardInterface(
            name: 'wg0',
            publicKey: 'eX4mP1ePuB11cK3yF0rW1r3Gu4rdN3tw0rk=',
            listenPort: 51820,
            isUp: true,
            peers: [
              WireguardPeer(
                publicKey: 'P33r1PuB11cK3yStr1ngM0b1l3Ph0n3=',
                endpoint: '198.51.100.42:51820',
                allowedIps: ['10.0.0.2/32', 'fd42:42:42::2/128'],
                rxBytes: 15420000,
                txBytes: 4210000,
                latestHandshakeTimestamp:
                    DateTime.now().millisecondsSinceEpoch ~/ 1000 - 45,
              ),
              WireguardPeer(
                publicKey: 'P33r2PuB11cK3yStr1ngL4pt0pD3v1c3=',
                endpoint: '203.0.113.88:51820',
                allowedIps: ['10.0.0.3/32'],
                rxBytes: 850000,
                txBytes: 210000,
                latestHandshakeTimestamp:
                    DateTime.now().millisecondsSinceEpoch ~/ 1000 - 120,
              ),
            ],
          ),
        );
      }

      if (ovpnList.isEmpty) {
        ovpnList.add(
          const OpenVpnInstance(
            name: 'custom_client',
            isEnabled: true,
            isRunning: true,
            port: '1194',
            proto: 'udp',
            dev: 'tun0',
          ),
        );
      }
    }

    return VpnConnectivityOverview(
      wireguardInterfaces: wgList,
      openvpnInstances: ovpnList,
      tailscale: isReviewerMode
          ? (tsRaw != null
                ? TailscaleStatus.fromJson(tsRaw)
                : const TailscaleStatus(
                    isConfigured: true,
                    isRunning: true,
                    nodeName: 'OpenWrt-Router',
                    tailscaleIp: '100.64.0.15',
                    backendState: 'Running',
                  ))
          : TailscaleStatus.fromJson(tsRaw),
      nextdns: isReviewerMode
          ? (ndnsRaw != null
                ? NextDnsStatus.fromJson(ndnsRaw)
                : const NextDnsStatus(
                    isConfigured: true,
                    isEnabled: true,
                    isRunning: true,
                    profileId: 'abcdef',
                    reportClientInfo: true,
                  ))
          : NextDnsStatus.fromJson(ndnsRaw),
      cloudflared: isReviewerMode
          ? (cfRaw != null
                ? CloudflaredStatus.fromJson(cfRaw)
                : const CloudflaredStatus(
                    isConfigured: true,
                    isEnabled: true,
                    isRunning: true,
                    tunnelId: '8f92a10b-4c3d-2e1f-0a9b-8c7d6e5f4a3b',
                    tunnelName: 'home-router-tunnel',
                    token: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
                    connectionsCount: 4,
                  ))
          : CloudflaredStatus.fromJson(cfRaw),
    );
  }

  int get totalWgPeers =>
      wireguardInterfaces.fold(0, (sum, i) => sum + i.peers.length);

  int get activeServicesCount {
    int count = 0;
    if (wireguardInterfaces.any((w) => w.isUp)) count++;
    if (openvpnInstances.any((o) => o.isRunning)) count++;
    if (tailscale.isRunning) count++;
    if (nextdns.isEnabled) count++;
    if (cloudflared.isRunning) count++;
    return count;
  }

  int get totalConfiguredServices {
    int count = 0;
    if (wireguardInterfaces.isNotEmpty) count++;
    if (openvpnInstances.isNotEmpty) count++;
    if (tailscale.isConfigured) count++;
    if (nextdns.isConfigured) count++;
    if (cloudflared.isConfigured) count++;
    return count;
  }
}
