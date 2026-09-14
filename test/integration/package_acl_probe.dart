// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

Future<String?> login() async {
  final ip = Platform.environment['ROUTER_IP'] ?? '192.168.1.1';
  final user = Platform.environment['ROUTER_USER'] ?? 'root';
  final pass = Platform.environment['ROUTER_PASS'] ?? '';
  final base = Uri.parse('http://$ip');
  final c = HttpClient()..badCertificateCallback = (_, _, _) => true;

  final req = await c.postUrl(base.replace(path: '/cgi-bin/luci/'));
  req.headers.set('Content-Type', 'application/x-www-form-urlencoded');
  req.write(
    'luci_username=${Uri.encodeComponent(user)}&luci_password=${Uri.encodeComponent(pass)}',
  );
  final resp = await req.close();
  await resp.drain<void>();
  for (final cookie in resp.cookies) {
    if (cookie.name == 'sysauth' && cookie.value.isNotEmpty) {
      return cookie.value;
    }
  }

  // ubus session.login fallback (OpenWrt 24.10+)
  final ubusReq = await c.postUrl(base.replace(path: '/ubus'));
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
  final body = await ubusResp.transform(utf8.decoder).join();
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map &&
        decoded['result'] is List &&
        decoded['result'].length >= 2) {
      final data = decoded['result'][1];
      if (decoded['result'][0] == 0 &&
          data is Map &&
          data['ubus_rpc_session'] != null) {
        return data['ubus_rpc_session'] as String;
      }
    }
  } catch (_) {}

  c.close(force: true);
  return null;
}

Future<void> ubusCall(
  String token,
  String object,
  String method,
  Map params,
  String label,
) async {
  final c = HttpClient()..badCertificateCallback = (_, _, _) => true;
  final req = await c.postUrl(
    Uri.parse(
      'http://${Platform.environment['ROUTER_IP'] ?? '192.168.1.1'}/ubus',
    ),
  );
  req.headers.set('Content-Type', 'application/json');
  req.cookies.add(Cookie('sysauth', token));
  req.write(
    jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'call',
      'params': [token, object, method, params],
    }),
  );
  final resp = await req.close();
  final body = await resp.transform(utf8.decoder).join();
  try {
    final decoded = jsonDecode(body);
    final result = decoded['result'];
    if (result is List) {
      final status = result[0];
      var detail = 'status=$status';
      if (result.length > 1 && result[1] is Map) {
        final m = result[1] as Map;
        final stdout = m['stdout']?.toString() ?? m['data']?.toString() ?? '';
        detail += ' stdout_len=${stdout.length} code=${m['code']}';
        if (stdout.length > 40) {
          detail += ' head=${stdout.substring(0, 40).replaceAll('\n', ' ')}';
        }
      }
      stdout.writeln('$label: $detail');
    } else {
      stdout.writeln('$label: $body');
    }
  } catch (_) {
    stdout.writeln('$label: parse error');
  }
  c.close(force: true);
}

void main() async {
  final token = await login();
  if (token == null) {
    stdout.writeln('LOGIN FAIL');
    exit(1);
  }
  stdout.writeln('LOGIN OK');

  await ubusCall(token, 'session', 'get', {
    'ubus_rpc_session': token,
  }, 'session.get');
  await ubusCall(token, 'file', 'exec', {
    'command': '/usr/libexec/package-manager-call',
    'params': ['list-installed'],
    'args': ['list-installed'],
  }, 'pm-call split');
  await ubusCall(token, 'file', 'exec', {
    'command': '/usr/libexec/package-manager-call list-installed',
  }, 'pm-call full cmd');
  await ubusCall(token, 'file', 'read', {
    'path': '/etc/apk/world',
  }, 'read apk world');
  await ubusCall(token, 'file', 'read', {
    'path': '/lib/apk/db/installed',
  }, 'read apk db');
  await ubusCall(token, 'file', 'exec', {
    'command': 'sh',
    'params': ['-c', 'cat /etc/apk/world'],
  }, 'sh cat world');
}
