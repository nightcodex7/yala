// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

// Credentials via env: ROUTER_IP, ROUTER_USER, ROUTER_PASS, ROUTER_HTTPS (optional)

import 'dart:convert';
import 'dart:io';

class ProbeResult {
  final String name;
  final bool ok;
  final String detail;

  ProbeResult(this.name, this.ok, this.detail);
}

Future<String?> login(
  HttpClient client,
  Uri base,
  String user,
  String pass,
) async {
  final luciUri = base.replace(path: '/cgi-bin/luci/');
  final req = await client.postUrl(luciUri);
  req.headers.set('Content-Type', 'application/x-www-form-urlencoded');
  req.write(
    'luci_username=${Uri.encodeComponent(user)}&luci_password=${Uri.encodeComponent(pass)}',
  );
  final resp = await req.close();
  await resp.drain<void>();

  for (final raw in resp.cookies) {
    if (raw.name == 'sysauth' && raw.value.isNotEmpty) {
      return raw.value;
    }
  }

  // ubus fallback
  final ubusUri = base.replace(path: '/ubus');
  final ubusReq = await client.postUrl(ubusUri);
  ubusReq.headers.set('Content-Type', 'application/json');
  ubusReq.write(
    jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'call',
      'params': [
        '00000000000000000000000000000000',
        'session',
        'login',
        {'username': user, 'password': pass},
      ],
    }),
  );
  final ubusResp = await ubusReq.close();
  final ubusBody = await ubusResp.transform(utf8.decoder).join();
  try {
    final decoded = jsonDecode(ubusBody);
    if (decoded is Map &&
        decoded['result'] is List &&
        decoded['result'].length >= 2) {
      final status = decoded['result'][0];
      final data = decoded['result'][1];
      if (status == 0 && data is Map && data['ubus_rpc_session'] != null) {
        return data['ubus_rpc_session'] as String;
      }
    }
  } catch (_) {}

  if (resp.statusCode >= 200 && resp.statusCode < 400) {
    return null; // login page returned but no token
  }
  return null;
}

Future<dynamic> ubusCall(
  HttpClient client,
  Uri base,
  String token,
  String object,
  String method, [
  Map<String, dynamic>? params,
]) async {
  final paths = ['/ubus', '/cgi-bin/luci/admin/ubus'];
  Object? lastError;
  for (final path in paths) {
    try {
      final uri = base.replace(path: path);
      final req = await client.postUrl(uri);
      req.headers.set('Content-Type', 'application/json');
      req.cookies.add(Cookie('sysauth', token));
      req.write(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'call',
          'params': [token, object, method, params ?? {}],
        }),
      );
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['result'] is List) {
        return decoded['result'];
      }
    } catch (e) {
      lastError = e;
    }
  }
  throw lastError ?? Exception('ubus call failed');
}

bool rpcOk(dynamic result) {
  if (result is! List || result.isEmpty) return false;
  return result[0] == 0;
}

String rpcSummary(dynamic result) {
  if (result is! List) return 'invalid response';
  if (result.isEmpty) return 'empty';
  final status = result[0];
  if (status != 0) return 'status=$status';
  final data = result.length > 1 ? result[1] : null;
  if (data == null) return 'ok (no data)';
  if (data is Map) return 'ok (${data.length} keys)';
  if (data is List) return 'ok (${data.length} items)';
  return 'ok';
}

Future<ProbeResult> probe(
  HttpClient client,
  Uri base,
  String token,
  String name,
  String object,
  String method, [
  Map<String, dynamic>? params,
  bool optional = false,
]) async {
  try {
    final result = await ubusCall(client, base, token, object, method, params);
    final ok = rpcOk(result);
    return ProbeResult(name, ok || optional, rpcSummary(result));
  } catch (e) {
    return ProbeResult(name, optional, 'error: $e');
  }
}

Future<void> main() async {
  final ip = Platform.environment['ROUTER_IP'] ?? '192.168.1.1';
  final user = Platform.environment['ROUTER_USER'] ?? 'root';
  final pass = Platform.environment['ROUTER_PASS'] ?? '';
  final useHttps = (Platform.environment['ROUTER_HTTPS'] ?? 'false') == 'true';

  if (pass.isEmpty) {
    stderr.writeln('Set ROUTER_PASS environment variable');
    exit(2);
  }

  final scheme = useHttps ? 'https' : 'http';
  final base = Uri.parse('$scheme://$ip');

  final client = HttpClient()..badCertificateCallback = (_, _, _) => true;

  stdout.writeln('=== Router API Probe: $ip ($scheme) ===');

  final token = await login(client, base, user, pass);
  if (token == null) {
    stdout.writeln('LOGIN: FAIL');
    exit(1);
  }
  stdout.writeln('LOGIN: OK');

  // Print router identity (no secrets)
  try {
    final board = await ubusCall(client, base, token, 'system', 'board');
    if (board is List && board.length > 1 && board[0] == 0 && board[1] is Map) {
      final b = board[1] as Map;
      final rel = b['release'];
      final version = rel is Map ? rel['version'] : rel;
      stdout.writeln(
        'Router: ${b['model'] ?? b['hostname']} / OpenWrt $version',
      );
    }
  } catch (_) {}

  // Test wireless station detection paths
  try {
    final wireless = await ubusCall(
      client,
      base,
      token,
      'luci-rpc',
      'getWirelessDevices',
    );
    if (wireless is List &&
        wireless.length > 1 &&
        wireless[0] == 0 &&
        wireless[1] is Map) {
      final radios = wireless[1] as Map;
      stdout.writeln('');
      stdout.writeln('=== Wireless Interfaces ===');
      for (final radioEntry in radios.entries) {
        final radio = radioEntry.value;
        if (radio is! Map) continue;
        final ifaces = radio['interfaces'];
        final list = ifaces is List
            ? ifaces
            : (ifaces is Map ? ifaces.values.toList() : []);
        for (final iface in list) {
          if (iface is! Map) continue;
          final ifname = iface['ifname']?.toString() ?? '?';
          final ssid =
              (iface['config'] is Map ? iface['config']['ssid'] : null)
                  ?.toString() ??
              '?';
          stdout.writeln('  $ifname ($ssid)');

          // iwinfo assoclist
          try {
            final assoc = await ubusCall(
              client,
              base,
              token,
              'iwinfo',
              'assoclist',
              {'device': ifname},
            );
            if (assoc is List && assoc.length > 1 && assoc[0] == 0) {
              final results = (assoc[1] is Map ? assoc[1]['results'] : null);
              final count = results is List ? results.length : 0;
              stdout.writeln('    iwinfo.assoclist: $count stations');
            } else {
              stdout.writeln('    iwinfo.assoclist: ${rpcSummary(assoc)}');
            }
          } catch (e) {
            stdout.writeln('    iwinfo.assoclist: error');
          }

          // hostapd get_clients
          try {
            final hp = await ubusCall(
              client,
              base,
              token,
              'hostapd.$ifname',
              'get_clients',
            );
            if (hp is List && hp.length > 1 && hp[0] == 0 && hp[1] is Map) {
              final clients = hp[1]['clients'];
              final count = clients is Map ? clients.length : 0;
              stdout.writeln('    hostapd.get_clients: $count clients');
            }
          } catch (_) {
            stdout.writeln('    hostapd.get_clients: unavailable');
          }
        }
      }
    }
  } catch (_) {}

  // DHCP lease count
  try {
    final leases = await ubusCall(
      client,
      base,
      token,
      'luci-rpc',
      'getDHCPLeases',
    );
    if (leases is List &&
        leases.length > 1 &&
        leases[0] == 0 &&
        leases[1] is Map) {
      final d4 = (leases[1]['dhcp_leases'] as List?)?.length ?? 0;
      final d6 = (leases[1]['dhcp6_leases'] as List?)?.length ?? 0;
      stdout.writeln('');
      stdout.writeln('DHCP leases: $d4 IPv4, $d6 IPv6');
    }
  } catch (_) {}

  // LuCI features relevant to app
  try {
    final features = await ubusCall(client, base, token, 'luci', 'getFeatures');
    if (features is List &&
        features.length > 1 &&
        features[0] == 0 &&
        features[1] is Map) {
      final f = features[1] as Map;
      stdout.writeln('');
      stdout.writeln(
        'Features: opkg=${f['opkg']} apk=${f['apk']} firewall4=${f['firewall4']} wifi=${f['wifi']}',
      );
    }
  } catch (_) {}

  final probes = <Future<ProbeResult>>[
    probe(client, base, token, 'system.board', 'system', 'board'),
    probe(client, base, token, 'system.info', 'system', 'info'),
    probe(client, base, token, 'system.mounts', 'system', 'mounts', null, true),
    probe(
      client,
      base,
      token,
      'network.device.status',
      'network.device',
      'status',
      {},
      true,
    ),
    probe(
      client,
      base,
      token,
      'network.interface.dump',
      'network.interface',
      'dump',
    ),
    probe(
      client,
      base,
      token,
      'luci-rpc.getWirelessDevices',
      'luci-rpc',
      'getWirelessDevices',
      null,
      true,
    ),
    probe(
      client,
      base,
      token,
      'luci-rpc.getNetworkDevices',
      'luci-rpc',
      'getNetworkDevices',
    ),
    probe(
      client,
      base,
      token,
      'luci-rpc.getDHCPLeases',
      'luci-rpc',
      'getDHCPLeases',
      null,
      true,
    ),
    probe(
      client,
      base,
      token,
      'luci-rpc.getHostHints',
      'luci-rpc',
      'getHostHints',
      null,
      true,
    ),
    probe(
      client,
      base,
      token,
      'luci-rpc.getMountPoints',
      'luci-rpc',
      'getMountPoints',
      null,
      true,
    ),
    probe(
      client,
      base,
      token,
      'luci.getFeatures',
      'luci',
      'getFeatures',
      null,
      true,
    ),
    probe(
      client,
      base,
      token,
      'wireless.devices',
      'wireless',
      'devices',
      null,
      true,
    ),
    probe(client, base, token, 'service.list', 'service', 'list', null, true),
    probe(client, base, token, 'rc.list', 'rc', 'list', null, true),
    probe(client, base, token, 'rpc.list', 'rpc', 'list', null, true),
    probe(client, base, token, 'uci.network', 'uci', 'get', {
      'config': 'network',
    }),
    probe(client, base, token, 'uci.wireless', 'uci', 'get', {
      'config': 'wireless',
    }, true),
    probe(client, base, token, 'uci.firewall', 'uci', 'get', {
      'config': 'firewall',
    }, true),
    probe(client, base, token, 'uci.dhcp', 'uci', 'get', {
      'config': 'dhcp',
    }, true),
    // App uses {command, params} format for file.exec
    probe(client, base, token, 'file.exec.df', 'file', 'exec', {
      'command': 'df',
      'params': ['-k'],
    }, true),
    probe(client, base, token, 'file.exec.opkg', 'file', 'exec', {
      'command': 'opkg',
      'params': ['list-installed'],
    }, true),
    probe(client, base, token, 'file.read.opkg-status', 'file', 'read', {
      'path': '/usr/lib/opkg/status',
    }, true),
    probe(client, base, token, 'file.read.proc-mounts', 'file', 'read', {
      'path': '/proc/mounts',
    }, true),
    probe(client, base, token, 'file.read.dhcp-leases', 'file', 'read', {
      'path': '/tmp/dhcp.leases',
    }, true),
    probe(client, base, token, 'file.read.cron', 'file', 'read', {
      'path': '/etc/crontabs/root',
    }, true),
    probe(
      client,
      base,
      token,
      'luci.wireguard',
      'luci.wireguard',
      'getWgInstances',
      null,
      true,
    ),
  ];

  final results = await Future.wait(probes);
  var passed = 0;
  var failed = 0;

  for (final r in results) {
    final tag = r.ok ? 'PASS' : 'FAIL';
    stdout.writeln('  [$tag] ${r.name}: ${r.detail}');
    if (r.ok) {
      passed++;
    } else {
      failed++;
    }
  }

  stdout.writeln('');
  stdout.writeln(
    'Summary: $passed passed, $failed failed (${results.length} total)',
  );
  client.close(force: true);
  exit(failed > 3 ? 1 : 0);
}
