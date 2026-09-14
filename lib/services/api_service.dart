// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:yet_another_luci_app/modules/parental_controls/models/parental_profile.dart';
import 'package:yet_another_luci_app/modules/services_system/models/ddns_info.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import '../utils/http_client_manager.dart';
import '../utils/logger.dart';

class LoginResult {
  final String? token;
  final bool actualUseHttps;

  LoginResult({required this.token, required this.actualUseHttps});
}

Uri _buildUrl(String ipAddress, bool useHttps, String path) {
  final scheme = useHttps ? 'https' : 'http';
  // Handle cases where ipAddress might already include a port
  String host = ipAddress;
  // Don't add scheme if the address already has one (shouldn't happen with our parser)
  if (host.startsWith('http://') || host.startsWith('https://')) {
    return Uri.parse('$host$path');
  }
  return Uri.parse('$scheme://$host$path');
}

class RealApiService implements IApiService {
  final HttpClientManager _httpClientManager = HttpClientManager();

  /// OpenWrt rpcd `file.exec` accepts `params` on newer builds and `args` on older ones.
  ///
  /// Some router images only support one form, so callers should try both when
  /// running package manager helper commands to remain compatible.
  static Map<String, dynamic> fileExecParams(
    String command,
    List<String> arguments,
  ) => {'command': command, 'params': arguments};

  static Map<String, dynamic> fileExecArgs(
    String command,
    List<String> arguments,
  ) => {'command': command, 'args': arguments};

  Dio _createHttpClient(
    bool useHttps,
    String hostWithPort, {
    BuildContext? context,
  }) {
    return _httpClientManager.getClient(
      hostWithPort,
      useHttps,
      context: context,
    );
  }

  @override
  Future<AuthResult> authenticate(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
  }) async {
    final client = _createHttpClient(useHttps, ipAddress, context: context);
    bool redirectDetected = false;
    bool targetIsHttps = false;
    bool invalidCredentialsDetected = false;

    // Helper to verify candidate token against router system.board
    Future<bool> verifyToken(String candidateToken, bool protocolHttps) async {
      try {
        final res = await callWithContext(
          ipAddress,
          candidateToken,
          protocolHttps,
          object: 'system',
          method: 'board',
          context: context,
        );
        return res != null;
      } catch (e) {
        return false;
      }
    }

    // Step 1: ubus JSON-RPC session.login (/ubus & /cgi-bin/luci/admin/ubus)
    final ubusEndpoints = ['/ubus', '/cgi-bin/luci/admin/ubus'];
    for (final endpoint in ubusEndpoints) {
      try {
        final ubusUrl = _buildUrl(ipAddress, useHttps, endpoint);
        final ubusPayload = {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'call',
          'params': [
            '00000000000000000000000000000000',
            'session',
            'login',
            {'username': username, 'password': password},
          ],
        };
        final response = await client.post(
          ubusUrl.toString(),
          data: jsonEncode(ubusPayload),
          options: Options(
            headers: {'Content-Type': 'application/json'},
            followRedirects: false,
            validateStatus: (code) => code != null && code < 500,
          ),
        );

        final location = response.headers.value('location') ?? '';
        if (response.statusCode == 302 ||
            response.statusCode == 301 ||
            location.isNotEmpty) {
          redirectDetected = true;
          if (location.startsWith('https://') ||
              response.realUri.scheme == 'https') {
            targetIsHttps = true;
          }
        }

        final token = _extractAuthToken(response);
        if (token != null) {
          final isVerified = await verifyToken(token, useHttps);
          if (isVerified) {
            Logger.info(
              'Step 1 (ubus JSON-RPC $endpoint) succeeded and verified',
            );
            return AuthResult.success(token, actualUseHttps: useHttps);
          }
        }

        if (response.data is Map && response.data['error'] != null) {
          final err = response.data['error'];
          if (err is Map &&
              (err['code'] == 6 || err['message'] == 'Access denied')) {
            invalidCredentialsDetected = true;
          }
        }
      } on DioException catch (e) {
        Logger.info(
          'Step 1 (ubus JSON-RPC $endpoint) failed [${e.type}]: ${e.message}',
        );
      } catch (e) {
        Logger.info('Step 1 (ubus JSON-RPC $endpoint) unexpected error: $e');
      }
    }

    // Step 2: CGI Form Login (/cgi-bin/luci/ & candidate paths)
    final cgiPaths = [
      '/cgi-bin/luci/',
      '/cgi-bin/luci',
      '/cgi-bin/luci/admin/',
    ];
    for (final path in cgiPaths) {
      try {
        final cgiUrl = _buildUrl(ipAddress, useHttps, path);
        final formParams =
            'luci_username=${Uri.encodeComponent(username)}&luci_password=${Uri.encodeComponent(password)}&username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}';
        final response = await client.post(
          cgiUrl.toString(),
          data: formParams,
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            followRedirects: true,
            validateStatus: (code) => code != null && code < 500,
          ),
        );

        final location = response.headers.value('location') ?? '';
        if (response.statusCode == 302 ||
            response.statusCode == 301 ||
            location.isNotEmpty) {
          redirectDetected = true;
          if (location.startsWith('https://') ||
              response.realUri.scheme == 'https') {
            targetIsHttps = true;
          }
        }

        final token = _extractAuthToken(response);
        if (token != null) {
          final isVerified = await verifyToken(token, useHttps);
          if (isVerified) {
            Logger.info('Step 2 (CGI form login $path) succeeded and verified');
            return AuthResult.success(token, actualUseHttps: useHttps);
          }
        }

        if (response.statusCode == 401 || response.statusCode == 403) {
          invalidCredentialsDetected = true;
        }
      } on DioException catch (e) {
        Logger.info(
          'Step 2 (CGI form login $path) failed [${e.type}]: ${e.message}',
        );
      } catch (e) {
        Logger.info('Step 2 (CGI form login $path) unexpected error: $e');
      }
    }

    // Step 3: LuCI RPC auth (/cgi-bin/luci/rpc/auth)
    try {
      final rpcUrl = _buildUrl(ipAddress, useHttps, '/cgi-bin/luci/rpc/auth');
      final rpcPayload = {
        'method': 'login',
        'params': [username, password],
        'id': 1,
      };
      final response = await client.post(
        rpcUrl.toString(),
        data: jsonEncode(rpcPayload),
        options: Options(
          headers: {'Content-Type': 'application/json'},
          followRedirects: false,
          validateStatus: (code) => code != null && code < 500,
        ),
      );

      final token = _extractAuthToken(response);
      if (token != null) {
        final isVerified = await verifyToken(token, useHttps);
        if (isVerified) {
          Logger.info('Step 3 (LuCI RPC auth) succeeded and verified');
          return AuthResult.success(token, actualUseHttps: useHttps);
        }
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        invalidCredentialsDetected = true;
      }
    } on DioException catch (e) {
      Logger.info('Step 3 (LuCI RPC auth) failed [${e.type}]: ${e.message}');
    } catch (e) {
      Logger.info('Step 3 (LuCI RPC auth) unexpected error: $e');
    }

    // Step 4: Protocol Fallback Replay (HTTP <-> HTTPS switch)
    if (redirectDetected || !useHttps) {
      try {
        final replayUseHttps = targetIsHttps || !useHttps;
        final replayClient = _createHttpClient(
          replayUseHttps,
          ipAddress,
          context: context,
        );

        final replayUrl = _buildUrl(ipAddress, replayUseHttps, '/ubus');
        final ubusPayload = {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'call',
          'params': [
            '00000000000000000000000000000000',
            'session',
            'login',
            {'username': username, 'password': password},
          ],
        };
        final response = await replayClient.post(
          replayUrl.toString(),
          data: jsonEncode(ubusPayload),
          options: Options(
            headers: {'Content-Type': 'application/json'},
            followRedirects: false,
            validateStatus: (code) => code != null && code < 500,
          ),
        );

        final token = _extractAuthToken(response);
        if (token != null) {
          final isVerified = await verifyToken(token, replayUseHttps);
          if (isVerified) {
            Logger.info(
              'Step 4 (Protocol fallback replay) succeeded and verified',
            );
            return AuthResult.success(token, actualUseHttps: replayUseHttps);
          }
        }
      } on DioException catch (e) {
        Logger.info(
          'Step 4 (Protocol fallback replay) failed [${e.type}]: ${e.message}',
        );
      } catch (e) {
        Logger.info('Step 4 (Protocol fallback replay) unexpected error: $e');
      }
    }

    if (invalidCredentialsDetected) {
      return AuthResult.invalidCredentials();
    }

    return AuthResult.unreachable();
  }

  @override
  Future<String> login(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
  }) async {
    final result = await authenticate(
      ipAddress,
      username,
      password,
      useHttps,
      context: context,
    );
    if (!result.isSuccess || result.token == null) {
      throw Exception(result.errorMessage ?? 'Login failed');
    }
    return result.token!;
  }

  static String? _extractAuthToken(Response response) {
    // 1. Set-Cookie header with exact match 'sysauth', 'sysauth_http', or 'sysauth_https'
    final setCookies = response.headers.map['set-cookie'];
    if (setCookies != null && setCookies.isNotEmpty) {
      for (final rawHeader in setCookies) {
        final parts = rawHeader.split(';');
        for (final part in parts) {
          final trimmed = part.trim();
          final eqIdx = trimmed.indexOf('=');
          if (eqIdx != -1) {
            final key = trimmed.substring(0, eqIdx).trim().toLowerCase();
            var val = trimmed.substring(eqIdx + 1).trim();

            if (val.startsWith('"') && val.endsWith('"') && val.length >= 2) {
              val = val.substring(1, val.length - 1).trim();
            }

            if ((key == 'sysauth' ||
                    key == 'sysauth_http' ||
                    key == 'sysauth_https') &&
                val.isNotEmpty &&
                val != 'deleted' &&
                val != 'expired' &&
                val != 'null') {
              return val;
            }
          }
        }
      }
    }

    // 2. Location header (or realUri) containing stok=<value> via strict regex
    final location = response.headers.value('location');
    if (location != null) {
      final match = RegExp(r'stok=([a-zA-Z0-9_-]+)').firstMatch(location);
      if (match != null && match.group(1) != null) {
        final stokVal = match.group(1)!;
        if (stokVal.isNotEmpty && stokVal.length >= 16) {
          return stokVal;
        }
      }
    }

    final realUriStr = response.realUri.toString();
    final uriMatch = RegExp(r'stok=([a-zA-Z0-9_-]+)').firstMatch(realUriStr);
    if (uriMatch != null && uriMatch.group(1) != null) {
      final stokVal = uriMatch.group(1)!;
      if (stokVal.isNotEmpty && stokVal.length >= 16) {
        return stokVal;
      }
    }

    // 3. Response body field stok / result / ubus_rpc_session
    if (response.data != null) {
      final dynamic data = response.data is String
          ? (response.data as String).startsWith('{')
                ? jsonDecode(response.data as String)
                : null
          : response.data;
      if (data is Map) {
        if (data['stok'] != null && data['stok'].toString().isNotEmpty) {
          return data['stok'].toString();
        }
        if (data['result'] is String && (data['result'] as String).isNotEmpty) {
          return data['result'] as String;
        }
        if (data['result'] is List && (data['result'] as List).length > 1) {
          final resData = data['result'][1];
          if (resData is Map && resData['ubus_rpc_session'] != null) {
            return resData['ubus_rpc_session'].toString();
          }
        }
      }
    }

    return null;
  }

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
    return await callWithContext(
      ipAddress,
      sysauth,
      useHttps,
      object: object,
      method: method,
      params: params,
      context: context,
    );
  }

  // Simplified call method for reviewer mode
  @override
  Future<dynamic> callSimple(
    String object,
    String method,
    Map<String, dynamic> params,
  ) async {
    // Use default values for ipAddress, sysauth, and useHttps
    // This is primarily for mock/testing scenarios
    return await call(
      'localhost', // Default IP address
      '', // Default sysauth (empty for mock scenarios)
      false, // Default to HTTP
      object: object,
      method: method,
      params: params,
    );
  }

  Future<dynamic> callWithContext(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  }) async {
    final client = _createHttpClient(useHttps, ipAddress, context: context);
    final rpcPayload = {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'call',
      'params': [sysauth, object, method, params ?? {}],
    };

    final endpoints = ['/ubus', '/cgi-bin/luci/admin/ubus'];

    for (int i = 0; i < endpoints.length; i++) {
      final endpointPath = endpoints[i];
      final url = _buildUrl(ipAddress, useHttps, endpointPath);

      try {
        final response = await client.post(
          url.toString(),
          data: jsonEncode(rpcPayload),
          options: Options(
            headers: {
              'Content-Type': 'application/json',
              if (sysauth.isNotEmpty)
                'Cookie':
                    'sysauth=$sysauth; sysauth_http=$sysauth; sysauth_https=$sysauth',
            },
            responseDecoder: (responseBytes, options, responseBody) {
              return utf8.decode(responseBytes, allowMalformed: true);
            },
            validateStatus: (status) => status != null && status < 500,
          ),
        );

        if (response.statusCode == 200) {
          final decoded = response.data is String
              ? jsonDecode(response.data as String)
              : response.data;
          if (decoded['error'] != null) {
            throw Exception('RPC error: ${decoded['error']['message']}');
          }
          // Return in LuCI RPC format: [status, data]
          final result = decoded['result'];
          if (result is List && result.isNotEmpty) {
            return result;
          } else {
            return [0, result];
          }
        } else if (response.statusCode == 404 && i < endpoints.length - 1) {
          // Fallback to next endpoint
          continue;
        } else {
          throw Exception('Failed to call RPC: HTTP ${response.statusCode}');
        }
      } on DioException catch (e, stack) {
        if (i < endpoints.length - 1) {
          continue;
        }
        Logger.exception('API call failed', e, stack);
        rethrow;
      }
    }

    throw Exception('Failed to reach RPC endpoint');
  }

  @override
  Future<bool> reboot(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    return await rebootWithContext(
      ipAddress,
      sysauth,
      useHttps,
      context: context,
    );
  }

  Future<bool> rebootWithContext(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    try {
      final result = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'system',
        method: 'reboot',
        context: context,
      );
      // Handle LuCI RPC format: [status, data] - successful reboot returns [0, ...]
      if (result is List && result.isNotEmpty && result[0] == 0) {
        Logger.info('Router reboot initiated successfully');
        return true;
      }
      Logger.warning('Router reboot call returned unexpected result: $result');
      return false;
    } catch (e, stack) {
      Logger.exception('Router reboot failed', e, stack);
      return false;
    }
  }

  @override
  Future<Map<String, Set<String>>> fetchAssociatedStations() async {
    // This method is mainly used by the mock service
    // For real implementation, individual interface queries via fetchAssociatedStationsWithContext should be used
    // The app_state.dart should call fetchAllAssociatedWirelessMacsWithContext instead
    throw UnimplementedError(
      'Use fetchAllAssociatedWirelessMacsWithContext for real implementation',
    );
  }

  /// Fetches all associated wireless MAC addresses from all wireless interfaces for real API
  @override
  Future<Map<String, Set<String>>> fetchAllAssociatedWirelessMacsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async {
    final result = <String, Set<String>>{};
    final discoveredIfaces = <String, String>{}; // ifname -> ssid/label

    try {
      // 1. Try getWirelessDevices via luci-rpc
      final wirelessResult = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'luci-rpc',
        method: 'getWirelessDevices',
        context: context,
      );

      if (wirelessResult is List &&
          wirelessResult.length > 1 &&
          wirelessResult[0] == 0) {
        final wirelessData = wirelessResult[1] as Map<String, dynamic>?;
        if (wirelessData != null) {
          for (final entry in wirelessData.entries) {
            final radioData = entry.value as Map<String, dynamic>?;
            if (radioData == null || radioData['interfaces'] == null) continue;

            final rawIfaces = radioData['interfaces'];
            final interfaces = rawIfaces is List
                ? rawIfaces
                : (rawIfaces is Map ? rawIfaces.values.toList() : null);
            if (interfaces == null) continue;

            for (final iface in interfaces) {
              if (iface is Map<String, dynamic>) {
                final ifname = iface['ifname']?.toString();
                final ssid =
                    iface['config']?['ssid']?.toString() ??
                    iface['iwinfo']?['ssid']?.toString() ??
                    iface['ssid']?.toString() ??
                    ifname;
                if (ifname != null && ifname.isNotEmpty) {
                  discoveredIfaces[ifname] = ssid ?? ifname;
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    // 2. Query UCI wireless configuration directly for VAP interface names & maclists
    try {
      final uciRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': 'wireless'},
        context: context?.mounted == true ? context : null,
      );
      if (uciRes is List && uciRes.length > 1 && uciRes[0] == 0) {
        final values =
            (uciRes[1] as Map<String, dynamic>?)?['values']
                as Map<String, dynamic>?;
        if (values != null) {
          for (final section in values.values) {
            if (section is Map<String, dynamic> &&
                section['.type'] == 'wifi-iface') {
              final ifname = section['ifname']?.toString();
              final ssid = section['ssid']?.toString() ?? ifname;
              if (ifname != null && ifname.isNotEmpty && ssid != null) {
                discoveredIfaces[ifname] = ssid;
              }
            }
          }
        }
      }
    } catch (_) {}

    // 3. Command/ubus fallback to find interface names if none found
    if (discoveredIfaces.isEmpty) {
      try {
        final resIwDev = await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'file',
          method: 'exec',
          params: fileExecParams('iw', ['dev']),
          context: context?.mounted == true ? context : null,
        );
        if (resIwDev is List && resIwDev.length > 1 && resIwDev[0] == 0) {
          final data = resIwDev[1] as Map<String, dynamic>?;
          final stdout = data?['stdout']?.toString() ?? '';
          String? currentIface;
          for (final line in stdout.split('\n')) {
            final trimmed = line.trim();
            if (trimmed.startsWith('Interface ')) {
              currentIface = trimmed.substring(10).trim();
              discoveredIfaces[currentIface] = currentIface;
            } else if (trimmed.startsWith('ssid ') && currentIface != null) {
              final ssid = trimmed.substring(5).trim();
              discoveredIfaces[currentIface] = ssid;
            }
          }
        }
      } catch (_) {}
    }

    // 3. For every discovered interface, fetch associated stations
    for (final entry in discoveredIfaces.entries) {
      final ifname = entry.key;
      final label = entry.value;

      final stations = await fetchAssociatedStationsWithContext(
        ipAddress: ipAddress,
        sysauth: sysauth,
        useHttps: useHttps,
        interface: ifname,
        context: context?.mounted == true ? context : null,
      );

      if (stations.isNotEmpty) {
        final mapKey = '$ifname|$label';
        result[mapKey] = (result[mapKey] ?? {})..addAll(stations);
      }
    }

    return result;
  }

  /// Fetches associated stations (wireless clients) for a given wireless interface (e.g., wlan0)
  /// Fetches associated stations (wireless clients) for a given wireless interface (e.g., phy0-ap0, wlan0)
  @override
  Future<List<String>> fetchAssociatedStationsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interface,
    BuildContext? context,
  }) async {
    final stations = <String>{};

    try {
      // 1. Try iwinfo assoclist
      final resultIw = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'iwinfo',
        method: 'assoclist',
        params: {'device': interface},
        context: context?.mounted == true ? context : null,
      );
      if (resultIw is List && resultIw.length > 1 && resultIw[0] == 0) {
        final data = resultIw[1];
        if (data is Map && data['results'] is List) {
          for (final entry in (data['results'] as List)) {
            final mac = (entry as Map<String, dynamic>)['mac']?.toString();
            if (mac != null && mac.isNotEmpty) {
              stations.add(mac.toUpperCase().replaceAll('-', ':'));
            }
          }
        }
      }
    } catch (_) {}

    try {
      // 2. Try hostapd.<interface> get_clients
      final resultHostapd = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'hostapd.$interface',
        method: 'get_clients',
        params: {},
        context: context?.mounted == true ? context : null,
      );
      if (resultHostapd is List &&
          resultHostapd.length > 1 &&
          resultHostapd[0] == 0) {
        final data = resultHostapd[1];
        if (data is Map && data['clients'] is Map) {
          final clientsMap = data['clients'] as Map<String, dynamic>;
          for (final mac in clientsMap.keys) {
            stations.add(mac.toUpperCase().replaceAll('-', ':'));
          }
        }
      }
    } catch (_) {}

    if (stations.isEmpty) {
      try {
        // 3. Command execution fallback (iwinfo <iface> assoclist or iw dev <iface> station dump)
        final resExec1 = await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'file',
          method: 'exec',
          params: fileExecParams('iwinfo', [interface, 'assoclist']),
          context: context?.mounted == true ? context : null,
        );
        if (resExec1 is List && resExec1.length > 1 && resExec1[0] == 0) {
          final data = resExec1[1] as Map<String, dynamic>?;
          final stdout = data?['stdout']?.toString() ?? '';
          final macRegex = RegExp(r'([0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5})');
          for (final m in macRegex.allMatches(stdout)) {
            final macStr = m.group(0);
            if (macStr != null) {
              stations.add(macStr.toUpperCase().replaceAll('-', ':'));
            }
          }
        }

        if (stations.isEmpty) {
          final resExec2 = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'file',
            method: 'exec',
            params: fileExecParams('iw', ['dev', interface, 'station', 'dump']),
            context: context?.mounted == true ? context : null,
          );
          if (resExec2 is List && resExec2.length > 1 && resExec2[0] == 0) {
            final data = resExec2[1] as Map<String, dynamic>?;
            final stdout = data?['stdout']?.toString() ?? '';
            final macRegex = RegExp(r'([0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5})');
            for (final m in macRegex.allMatches(stdout)) {
              final macStr = m.group(0);
              if (macStr != null) {
                stations.add(macStr.toUpperCase().replaceAll('-', ':'));
              }
            }
          }
        }
      } catch (_) {}
    }

    return stations.toList();
  }

  /// Fetches Host Hints dictionary from luci-rpc and UCI dhcp static host leases
  @override
  Future<Map<String, Map<String, dynamic>>> fetchHostHintsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async {
    final hints = <String, Map<String, dynamic>>{};

    // 1. Fetch static DHCP host leases directly from UCI (dhcp)
    try {
      final uciRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': 'dhcp', 'type': 'host'},
        context: context?.mounted == true ? context : null,
      );
      if (uciRes is List && uciRes.length > 1 && uciRes[0] == 0) {
        final rawData = uciRes[1];
        Map<String, dynamic>? values;
        if (rawData is Map<String, dynamic>) {
          if (rawData['values'] is Map<String, dynamic>) {
            values = rawData['values'] as Map<String, dynamic>;
          } else {
            values = rawData;
          }
        }
        if (values != null) {
          values.forEach((_, sec) {
            if (sec is Map<String, dynamic>) {
              final rawName =
                  sec['name']?.toString() ??
                  sec['hostname']?.toString() ??
                  sec['comment']?.toString() ??
                  sec['description']?.toString();
              final rawMac = sec['mac'];
              if (rawName != null && rawName.isNotEmpty && rawMac != null) {
                final macList = <String>[];
                if (rawMac is List) {
                  macList.addAll(rawMac.map((e) => e.toString()));
                } else if (rawMac is String) {
                  macList.addAll(rawMac.split(RegExp(r'\s+')));
                }
                for (final mac in macList) {
                  final normMac = mac
                      .toUpperCase()
                      .replaceAll('-', ':')
                      .split(':')
                      .map((b) => b.length == 1 ? '0$b' : b)
                      .join(':');
                  if (normMac.isNotEmpty) {
                    hints[normMac] = {
                      'name': rawName,
                      'staticLeaseName': rawName,
                      'ipaddrs': sec['ip'] != null
                          ? [sec['ip'].toString()]
                          : [],
                      'staticLeaseIp': sec['ip']?.toString(),
                      'isStaticLease': true,
                    };
                  }
                }
              }
            }
          });
        }
      }
    } catch (_) {}

    // 2. Fetch getHostHints from luci-rpc (merges /etc/hosts, ethers, and active leases)
    try {
      final res = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'luci-rpc',
        method: 'getHostHints',
        params: {},
        context: context?.mounted == true ? context : null,
      );
      if (res is List && res.length > 1 && res[0] == 0) {
        final data = res[1];
        if (data is Map<String, dynamic>) {
          data.forEach((mac, info) {
            if (info is Map<String, dynamic>) {
              final normMac = mac
                  .trim()
                  .toUpperCase()
                  .replaceAll('-', ':')
                  .split(':')
                  .map((b) => b.length == 1 ? '0$b' : b)
                  .join(':');
              var name = info['name']?.toString();
              if (name != null && name.isNotEmpty && name != '*') {
                if (name.endsWith('.lan')) {
                  name = name.substring(0, name.length - 4);
                } else if (name.endsWith('.local')) {
                  name = name.substring(0, name.length - 6);
                }
              }
              final existing = hints[normMac];
              final newIps = info['ipaddrs'] as List?;
              final newV6Ips = info['ip6addrs'] as List?;
              if (existing == null) {
                hints[normMac] = {
                  'name': name ?? '',
                  'ipaddrs': newIps ?? [],
                  'ip6addrs': newV6Ips ?? [],
                  'isStaticLease': false,
                };
              } else {
                // Keep static lease info if set from UCI in step 1, otherwise update missing dynamic fields
                if (existing['name'] == null ||
                    existing['name'].toString().isEmpty) {
                  existing['name'] = name ?? '';
                }
                if (newIps != null && newIps.isNotEmpty) {
                  existing['ipaddrs'] = newIps;
                }
                if (newV6Ips != null && newV6Ips.isNotEmpty) {
                  existing['ip6addrs'] = newV6Ips;
                }
              }
            }
          });
        }
      }
    } catch (_) {}
    return hints;
  }

  @override
  Future<Map<String, dynamic>?> fetchWireGuardPeers({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interface,
    BuildContext? context,
  }) async {
    return await fetchWireGuardPeersWithContext(
      ipAddress: ipAddress,
      sysauth: sysauth,
      useHttps: useHttps,
      interface: interface,
      context: context,
    );
  }

  /// Fetches WireGuard peer information for a given interface
  /// If interface is empty, returns data for all WireGuard interfaces
  Future<Map<String, dynamic>?> fetchWireGuardPeersWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interface,
    BuildContext? context,
  }) async {
    try {
      // Use the correct luci.wireguard.getWgInstances method
      final result = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'luci.wireguard',
        method: 'getWgInstances',
        params: {},
        context: context,
      );

      // Handle LuCI RPC format: [status, data]
      if (result is List && result.length > 1 && result[0] == 0) {
        final data = result[1] as Map<String, dynamic>?;
        if (data != null) {
          return _parseWireGuardFromInstances(data, interface);
        }
      }

      return null;
    } catch (e, stack) {
      Logger.exception('Failed to fetch WireGuard peers', e, stack);
      return null;
    }
  }

  Map<String, dynamic>? _parseWireGuardFromInstances(
    Map<String, dynamic> data,
    String targetInterface,
  ) {
    final wireguardData = <String, dynamic>{};

    data.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        // Look for peers in the interface data
        final peers = <String, dynamic>{};

        // The structure might have peers in different formats
        final rawPeers = value['peers'];
        if (rawPeers is List) {
          for (final peer in rawPeers) {
            if (peer is Map<String, dynamic>) {
              final publicKey = peer['public_key'] as String?;
              if (publicKey != null) {
                peers[publicKey] = {
                  'public_key': publicKey,
                  'endpoint': peer['endpoint'] ?? 'N/A',
                  'last_handshake':
                      int.tryParse(
                        peer['latest_handshake']?.toString() ?? '0',
                      ) ??
                      0,
                  'rx_bytes': peer['rx_bytes'] ?? 0,
                  'tx_bytes': peer['tx_bytes'] ?? 0,
                  'allowed_ips': peer['allowed_ips'] ?? [],
                };
              }
            }
          }
        } else if (rawPeers is Map) {
          rawPeers.forEach((k, peer) {
            if (peer is Map<String, dynamic>) {
              final publicKey = peer['public_key'] as String? ?? k.toString();
              final allowed = peer['allowed_ips'];
              final ips = <String>[];
              if (allowed is List) {
                ips.addAll(allowed.map((e) => e.toString()));
              } else if (allowed != null) {
                ips.add(allowed.toString());
              }
              peers[publicKey] = {
                'public_key': publicKey,
                'endpoint': peer['endpoint'] ?? 'N/A',
                'last_handshake':
                    int.tryParse(peer['latest_handshake']?.toString() ?? '0') ??
                    0,
                'rx_bytes': peer['rx_bytes'] ?? 0,
                'tx_bytes': peer['tx_bytes'] ?? 0,
                'allowed_ips': ips,
              };
            }
          });
        }

        wireguardData[key] = {
          'interface': key,
          'device': value['device'] ?? key,
          'public_key': value['public_key']?.toString(),
          'listen_port': value['listen_port'],
          'up': value['up'] ?? value['is_up'],
          'peers': peers,
        };
      }
    });

    if (targetInterface.isEmpty) {
      return wireguardData;
    } else {
      if (wireguardData.containsKey(targetInterface)) {
        return wireguardData[targetInterface];
      }
      for (final entry in wireguardData.values) {
        if (entry is Map &&
            (entry['device'] == targetInterface ||
                entry['interface'] == targetInterface)) {
          return entry as Map<String, dynamic>;
        }
      }
      return null;
    }
  }

  @override
  Future<dynamic> uciSet(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    required String section,
    required Map<String, String> values,
    BuildContext? context,
  }) async {
    return await callWithContext(
      ipAddress,
      sysauth,
      useHttps,
      object: 'uci',
      method: 'set',
      params: {'config': config, 'section': section, 'values': values},
      context: context,
    );
  }

  @override
  Future<dynamic> uciCommit(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  }) async {
    return await callWithContext(
      ipAddress,
      sysauth,
      useHttps,
      object: 'uci',
      method: 'commit',
      params: {'config': config},
      context: context,
    );
  }

  @override
  Future<dynamic> uciRevert(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  }) async {
    return await callWithContext(
      ipAddress,
      sysauth,
      useHttps,
      object: 'uci',
      method: 'revert',
      params: {'config': config},
      context: context,
    );
  }

  @override
  Future<List<String>> fetchNetworkInterfaces({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async {
    try {
      final mCtx = mountedContext(context);
      final res = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': 'network'},
        context: mCtx,
      );
      if (res is List && res.length > 1 && res[0] == 0) {
        final uciData = res[1];
        final valuesMap = (uciData is Map && uciData['values'] is Map)
            ? uciData['values'] as Map
            : (uciData is Map ? uciData : {});
        final interfaces = <String>[];
        valuesMap.forEach((key, val) {
          if (val is Map && val['.type'] == 'interface') {
            interfaces.add(key);
          }
        });
        return interfaces;
      }
    } catch (_) {}
    return ['lan', 'wan', 'guest'];
  }

  @override
  Future<dynamic> systemExec(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String command,
    BuildContext? context,
  }) async {
    return await callWithContext(
      ipAddress,
      sysauth,
      useHttps,
      object: 'file',
      method: 'exec',
      params: fileExecParams('/bin/sh', ['-c', command]),
      context: context,
    );
  }

  /// Helper to safely obtain mounted BuildContext across async gaps.
  BuildContext? mountedContext(BuildContext? ctx) =>
      (ctx != null && ctx.mounted) ? ctx : null;

  @override
  bool execSucceeded(dynamic res) {
    if (res == null) return false;
    if (res is List && res.isNotEmpty) {
      if (res.length > 1 && res[1] is Map) {
        final map = res[1] as Map;
        if (map['code'] is int) return map['code'] == 0;
        return res[0] == 0;
      }
      return res[0] == 0;
    }
    if (res is Map) {
      if (res['code'] is int) return res['code'] == 0;
      if (res['rc'] is int) return res['rc'] == 0;
      return false;
    }
    return res == 0;
  }

  bool _execSucceeded(dynamic res) => execSucceeded(res);

  @override
  Future<bool> setSsidEnabled(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String ifaceSection,
    required bool enabled,
    BuildContext? context,
  }) async {
    try {
      final mCtx = mountedContext(context);
      final setRes = await uciSet(
        ipAddress,
        sysauth,
        useHttps,
        config: 'wireless',
        section: ifaceSection,
        values: {'disabled': enabled ? '0' : '1'},
        context: mCtx,
      );
      if (setRes is List && setRes.isNotEmpty && setRes[0] != 0) {
        await uciRevert(
          ipAddress,
          sysauth,
          useHttps,
          config: 'wireless',
          context: mCtx,
        );
        return false;
      }

      final commitRes = await uciCommit(
        ipAddress,
        sysauth,
        useHttps,
        config: 'wireless',
        context: mCtx,
      );
      if (commitRes is List && commitRes.isNotEmpty && commitRes[0] != 0) {
        await uciRevert(
          ipAddress,
          sysauth,
          useHttps,
          config: 'wireless',
          context: mCtx,
        );
        return false;
      }

      // Reload wifi configuration
      final reloadRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': '/sbin/wifi',
          'params': ['reload'],
        },
        context: mCtx,
      );
      return _execSucceeded(reloadRes);
    } catch (e, stack) {
      Logger.exception('setSsidEnabled failed for $ifaceSection', e, stack);
      await uciRevert(
        ipAddress,
        sysauth,
        useHttps,
        config: 'wireless',
        context: mountedContext(context),
      );
      return false;
    }
  }

  @override
  Future<bool> updateWirelessInterfaceConfig(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionName,
    required Map<String, String> values,
    BuildContext? context,
  }) async {
    final mCtx = mountedContext(context);
    try {
      final setRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'set',
        params: {
          'config': 'wireless',
          'section': sectionName,
          'values': values,
        },
        context: mCtx,
      );
      if (setRes is List && setRes.isNotEmpty && setRes[0] != 0) {
        await uciRevert(
          ipAddress,
          sysauth,
          useHttps,
          config: 'wireless',
          context: mCtx,
        );
        return false;
      }

      final applyRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'apply',
        params: {'rollback': false},
        context: mCtx,
      );
      if (applyRes is List && applyRes.isNotEmpty && applyRes[0] == 0) {
        await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'uci',
          method: 'confirm',
          context: mCtx,
        );
        return true;
      }

      // Atomic Rollback on Apply Failure
      await uciRevert(
        ipAddress,
        sysauth,
        useHttps,
        config: 'wireless',
        context: mCtx,
      );
      return false;
    } catch (e, stack) {
      Logger.exception(
        'updateWirelessInterfaceConfig failed for $sectionName',
        e,
        stack,
      );
      await uciRevert(
        ipAddress,
        sysauth,
        useHttps,
        config: 'wireless',
        context: mCtx,
      );
      return false;
    }
  }

  @override
  Future<bool> revertWirelessInterfaceConfig(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionName,
    required Map<String, String> priorValues,
    BuildContext? context,
  }) async {
    try {
      final res = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'revert',
        params: {'config': 'wireless'},
        context: mountedContext(context),
      );

      if (priorValues.isNotEmpty) {
        await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'uci',
          method: 'set',
          params: {
            'config': 'wireless',
            'section': sectionName,
            'values': priorValues,
          },
          context: mountedContext(context),
        );
        await uciCommit(
          ipAddress,
          sysauth,
          useHttps,
          config: 'wireless',
          context: mountedContext(context),
        );
      }

      final reloadRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': '/sbin/wifi',
          'params': ['reload'],
        },
        context: mountedContext(context),
      );

      return res is List &&
          res.isNotEmpty &&
          res[0] == 0 &&
          _execSucceeded(reloadRes);
    } catch (e, stack) {
      Logger.exception(
        'revertWirelessInterfaceConfig failed for $sectionName',
        e,
        stack,
      );
      return false;
    }
  }

  @override
  Future<bool> updateWirelessRadioConfig(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionName,
    required Map<String, String> values,
    BuildContext? context,
  }) async {
    final mCtx = mountedContext(context);
    try {
      final setRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'set',
        params: {
          'config': 'wireless',
          'section': sectionName,
          'values': values,
        },
        context: mCtx,
      );
      if (setRes is List && setRes.isNotEmpty && setRes[0] != 0) {
        await uciRevert(
          ipAddress,
          sysauth,
          useHttps,
          config: 'wireless',
          context: mCtx,
        );
        return false;
      }

      final applyRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'apply',
        params: {'rollback': false},
        context: mCtx,
      );
      if (applyRes is List && applyRes.isNotEmpty && applyRes[0] == 0) {
        await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'uci',
          method: 'confirm',
          context: mCtx,
        );
        return true;
      }

      // Atomic Rollback on Apply Failure
      await uciRevert(
        ipAddress,
        sysauth,
        useHttps,
        config: 'wireless',
        context: mCtx,
      );
      return false;
    } catch (e, stack) {
      Logger.exception(
        'updateWirelessRadioConfig failed for $sectionName',
        e,
        stack,
      );
      await uciRevert(
        ipAddress,
        sysauth,
        useHttps,
        config: 'wireless',
        context: mCtx,
      );
      return false;
    }
  }

  @override
  Future<bool> revertWirelessRadioConfig(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionName,
    required Map<String, String> priorValues,
    BuildContext? context,
  }) async {
    try {
      final res = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'revert',
        params: {'config': 'wireless'},
        context: mountedContext(context),
      );

      if (priorValues.isNotEmpty) {
        await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'uci',
          method: 'set',
          params: {
            'config': 'wireless',
            'section': sectionName,
            'values': priorValues,
          },
          context: mountedContext(context),
        );
        await uciCommit(
          ipAddress,
          sysauth,
          useHttps,
          config: 'wireless',
          context: mountedContext(context),
        );
      }

      final reloadRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': '/sbin/wifi',
          'params': ['reload'],
        },
        context: mountedContext(context),
      );

      return res is List &&
          res.isNotEmpty &&
          res[0] == 0 &&
          _execSucceeded(reloadRes);
    } catch (e, stack) {
      Logger.exception(
        'revertWirelessRadioConfig failed for $sectionName',
        e,
        stack,
      );
      return false;
    }
  }

  // ─── Anonymous Section Migration Helpers ─────────────────────────────────

  /// Returns the next available wifinet# name that is not already used in the
  /// current wireless config, by reading all named wifi-iface section names.
  Future<String> _nextWifinetName(
    String ipAddress,
    String sysauth,
    bool useHttps,
    BuildContext? context,
  ) async {
    try {
      final res = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': 'wireless'},
        context: context,
      );
      final usedIndices = <int>{};
      if (res is List && res.length > 1 && res[0] == 0) {
        final values =
            (res[1] as Map<String, dynamic>?)?['values']
                as Map<String, dynamic>?;
        if (values != null) {
          for (final key in values.keys) {
            final match = RegExp(r'^wifinet(\d+)$').firstMatch(key.toString());
            if (match != null) {
              final idx = int.tryParse(match.group(1)!);
              if (idx != null) usedIndices.add(idx);
            }
          }
        }
      }
      // Also consider staging/uci changes that might have already been renamed
      int next = 0;
      while (usedIndices.contains(next)) {
        next++;
      }
      return 'wifinet$next';
    } catch (_) {
      return 'wifinet0';
    }
  }

  /// Renames an anonymous section (e.g. cfg033579) to the provided named
  /// identifier via `uci rename`. Returns true if the rename succeeded.
  Future<bool> _renameUciSection(
    String ipAddress,
    String sysauth,
    bool useHttps,
    String config,
    String anonymousSection,
    String namedSection,
    BuildContext? context,
  ) async {
    try {
      final res = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'rename',
        params: {
          'config': config,
          'section': anonymousSection,
          'name': namedSection,
        },
        context: context,
      );
      return res is List && res.isNotEmpty && res[0] == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<int> migrateAnonymousWirelessSections(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    try {
      final res = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': 'wireless'},
        context: context,
      );

      if (res is! List || res.length < 2 || res[0] != 0) return 0;
      final values =
          (res[1] as Map<String, dynamic>?)?['values'] as Map<String, dynamic>?;
      if (values == null) return 0;

      // Collect existing wifinet indices to avoid collisions when renaming
      final usedIndices = <int>{};
      final anonymousSections = <String>[];
      for (final entry in values.entries) {
        final key = entry.key.toString();
        final sectionMap = entry.value;
        if (sectionMap is Map) {
          final type = sectionMap['.type']?.toString();
          final isAnon =
              sectionMap['.anonymous'] == true ||
              sectionMap['.anonymous'].toString() == 'true';
          if (type == 'wifi-iface' && isAnon) {
            anonymousSections.add(key);
          } else if (type == 'wifi-iface') {
            final match = RegExp(r'^wifinet(\d+)$').firstMatch(key);
            if (match != null) {
              final idx = int.tryParse(match.group(1)!);
              if (idx != null) usedIndices.add(idx);
            }
          }
        }
      }

      if (anonymousSections.isEmpty) return 0;

      int migratedCount = 0;
      for (final anonSection in anonymousSections) {
        // Find next unused wifinet# index
        int idx = 0;
        while (usedIndices.contains(idx)) {
          idx++;
        }
        final namedSection = 'wifinet$idx';
        usedIndices.add(idx);

        final renamed = await _renameUciSection(
          ipAddress,
          sysauth,
          useHttps,
          'wireless',
          anonSection,
          namedSection,
          context,
        );
        if (renamed) migratedCount++;
      }

      // Commit all renames atomically if any succeeded
      if (migratedCount > 0) {
        await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'uci',
          method: 'commit',
          params: {'config': 'wireless'},
          context: context,
        );
      }

      return migratedCount;
    } catch (e, stack) {
      Logger.exception('migrateAnonymousWirelessSections failed', e, stack);
      return 0;
    }
  }

  @override
  Future<bool> applyParentalProfileDns(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String profileId,
    required List<String> macAddresses,
    required List<String>? dnsServers,
    BuildContext? context,
  }) async {
    try {
      final safeId = profileId.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
      final tag = 'p_tag_$safeId';
      final dnsStr = dnsServers?.join(',') ?? '';

      final script =
          '''
T="$tag"
DNS="$dnsStr"
if [ "\$DNS" = "" ]; then
  uci delete dhcp.\$T 2>/dev/null
  for sec in \$(uci show dhcp 2>/dev/null | grep -i '@host' | grep "\\.mac=" | cut -d. -f2 | sort -u); do
    cur_tag=\$(uci get dhcp.\$sec.tag 2>/dev/null)
    if [ "\$cur_tag" = "\$T" ]; then
      uci delete dhcp.\$sec.tag
    fi
  done
else
  uci set dhcp.\$T=tag
  uci set dhcp.\$T.dhcp_option="6,\$DNS"
  MACS="${macAddresses.map((m) => m.toLowerCase()).join(' ')}"
  for m in \$MACS; do
    sec=\$(uci show dhcp 2>/dev/null | grep -i "@host.*\\.mac=.*\$m" | cut -d. -f2 | head -n1)
    if [ -z "\$sec" ]; then
      sec=\$(uci add dhcp host)
      uci set dhcp.\$sec.mac="\$m"
      name=\$(echo "\$m" | tr ':' '-')
      uci set dhcp.\$sec.name="p_\$name"
    fi
    uci set dhcp.\$sec.tag="\$T"
  done
fi
uci commit dhcp
/etc/init.d/dnsmasq restart 2>/dev/null || true
''';

      return await systemExec(
            ipAddress,
            sysauth,
            useHttps,
            command: script,
            context: context,
          ) !=
          null;
    } catch (e, stack) {
      Logger.exception('applyParentalProfileDns failed', e, stack);
      return false;
    }
  }

  @override
  Future<List<ParentalProfile>?> fetchParentalProfiles(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    try {
      final mCtx = mountedContext(context);
      final res = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': 'parental'},
        context: mCtx,
      );
      if (res is List && res.length > 1) {
        if (res[0] != 0) {
          // If ubus returned error (e.g. config file does not exist yet), return empty list
          return [];
        }
        final uciData = res[1];
        final valuesMap = (uciData is Map && uciData['values'] is Map)
            ? uciData['values'] as Map
            : (uciData is Map ? uciData : {});
        final profiles = <ParentalProfile>[];
        valuesMap.forEach((key, val) {
          if (val is Map && val['.type'] == 'profile') {
            profiles.add(
              ParentalProfile.fromJson(
                Map<String, dynamic>.from(val),
                key.toString(),
              ),
            );
          }
        });
        return profiles;
      }
    } catch (e, stack) {
      Logger.exception('fetchParentalProfiles failed', e, stack);
    }
    return null;
  }

  @override
  Future<bool> saveParentalProfile(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required ParentalProfile profile,
    BuildContext? context,
  }) async {
    try {
      final sec = profile.id.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
      final safeName = profile.name.replaceAll("'", "'\\''");
      final safeIcon = profile.icon.replaceAll("'", "'\\''");
      final safeColor = profile.color.replaceAll("'", "'\\''");
      final macsStr = profile.macAddresses
          .map((m) => m.toLowerCase())
          .join(' ');
      final dnsStr = profile.customDnsServers.join(' ');

      final script =
          '''
touch /etc/config/parental 2>/dev/null || true
SEC="$sec"
uci set parental.\$SEC=profile
uci set parental.\$SEC.name='$safeName'
uci set parental.\$SEC.icon='$safeIcon'
uci set parental.\$SEC.color='$safeColor'
uci set parental.\$SEC.is_paused="${profile.isPaused ? '1' : '0'}"
uci set parental.\$SEC.is_enabled="${profile.isEnabled ? '1' : '0'}"
uci set parental.\$SEC.content_filter="${profile.contentFilter.toStorageString()}"
uci delete parental.\$SEC.mac 2>/dev/null || true
for m in $macsStr; do uci add_list parental.\$SEC.mac="\$m"; done
uci delete parental.\$SEC.custom_dns 2>/dev/null || true
for d in $dnsStr; do uci add_list parental.\$SEC.custom_dns="\$d"; done
uci commit parental
''';

      return await systemExec(
            ipAddress,
            sysauth,
            useHttps,
            command: script,
            context: context,
          ) !=
          null;
    } catch (e, stack) {
      Logger.exception('saveParentalProfile failed', e, stack);
      return false;
    }
  }

  @override
  Future<bool> deleteParentalProfile(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String profileId,
    BuildContext? context,
  }) async {
    try {
      final sec = profileId.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
      final script =
          '''
SEC="$sec"
uci delete parental.\$SEC 2>/dev/null || true
uci commit parental
''';

      return await systemExec(
            ipAddress,
            sysauth,
            useHttps,
            command: script,
            context: context,
          ) !=
          null;
    } catch (e, stack) {
      Logger.exception('deleteParentalProfile failed', e, stack);
      return false;
    }
  }

  @override
  Future<Map<String, List<Map<String, String>>>>
  fetchWirelessHardwareCapabilities({
    required String sectionName,
    String? radioName,
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async {
    try {
      final targetDevice = sectionName.isNotEmpty
          ? sectionName
          : (radioName ?? 'wlan0');
      final mCtx = mountedContext(context);

      final encResult = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'iwinfo',
        method: 'encryption',
        params: {'device': targetDevice},
        context: mCtx,
      );

      final cipherResult = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'iwinfo',
        method: 'ciphers',
        params: {'device': targetDevice},
        context: mCtx,
      );

      final encList = <Map<String, String>>[];
      final cipherList = <Map<String, String>>[];

      if (encResult is List && encResult.length > 1 && encResult[0] == 0) {
        final data = encResult[1];
        if (data is Map<String, dynamic>) {
          final encs = data['encryption'] ?? data['encryptions'];
          if (encs is List) {
            for (final item in encs) {
              final val = item.toString().toLowerCase();
              encList.add({'value': val, 'label': _formatEncLabel(val)});
            }
          }
        }
      }

      if (cipherResult is List &&
          cipherResult.length > 1 &&
          cipherResult[0] == 0) {
        final data = cipherResult[1];
        if (data is Map<String, dynamic>) {
          final ciphers = data['ciphers'];
          if (ciphers is List) {
            for (final item in ciphers) {
              final val = item.toString().toLowerCase();
              cipherList.add({'value': val, 'label': _formatCipherLabel(val)});
            }
          }
        }
      }

      if (encList.isNotEmpty || cipherList.isNotEmpty) {
        return {
          'encryptions': encList.isNotEmpty ? encList : _fallbackEncryptions(),
          'ciphers': cipherList.isNotEmpty ? cipherList : _fallbackCiphers(),
        };
      }
    } catch (e) {
      Logger.debug(
        'fetchWirelessHardwareCapabilities failed for $sectionName: $e',
      );
    }
    return {
      'encryptions': _fallbackEncryptions(),
      'ciphers': _fallbackCiphers(),
    };
  }

  @override
  Future<Map<String, dynamic>> fetchWirelessRadioCapabilities({
    required String radioName,
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async {
    final result = <String, dynamic>{
      'countryCodes': <Map<String, String>>[],
      'channels': <String>[],
      'htModes': <String>[],
      'txPowers': <String>[],
    };
    try {
      final targetDevice = radioName.isNotEmpty ? radioName : 'wlan0';
      final mCtx = mountedContext(context);

      final responses = await Future.wait([
        callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'iwinfo',
          method: 'countrylist',
          params: {'device': targetDevice},
          context: mCtx,
        ),
        callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'iwinfo',
          method: 'freqlist',
          params: {'device': targetDevice},
          context: mCtx,
        ),
        callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'iwinfo',
          method: 'htmodelist',
          params: {'device': targetDevice},
          context: mCtx,
        ),
        callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'iwinfo',
          method: 'txpowerlist',
          params: {'device': targetDevice},
          context: mCtx,
        ),
      ]);

      final countryRes = responses[0];
      final freqRes = responses[1];
      final htRes = responses[2];
      final txRes = responses[3];

      // Parse countrylist
      final countries = <Map<String, String>>[];
      dynamic countryData;
      if (countryRes is List && countryRes.length > 1 && countryRes[0] == 0) {
        countryData = countryRes[1];
      }
      if (countryData is Map) {
        countryData = countryData['results'] ?? countryData['countrylist'];
      }
      if (countryData is List) {
        for (final item in countryData) {
          if (item is Map) {
            final code = (item['code'] ?? item['iso'] ?? item['country'])
                ?.toString()
                .toUpperCase();
            final name = (item['name'] ?? item['country'] ?? code)?.toString();
            if (code != null && code.isNotEmpty) {
              countries.add({
                'code': code,
                'label': name != null && name != code
                    ? '$code — $name'
                    : '$code — Country Code',
              });
            }
          } else if (item is String && item.isNotEmpty) {
            final code = item.toUpperCase();
            countries.add({'code': code, 'label': '$code — Country Code'});
          }
        }
      }
      if (countries.isNotEmpty) {
        result['countryCodes'] = countries;
      }

      // Parse freqlist / channellist
      final channels = <String>['auto'];
      dynamic freqData;
      if (freqRes is List && freqRes.length > 1 && freqRes[0] == 0) {
        freqData = freqRes[1];
      }
      if (freqData is Map) {
        freqData =
            freqData['results'] ??
            freqData['freqlist'] ??
            freqData['channellist'];
      }
      if (freqData is List) {
        for (final item in freqData) {
          if (item is Map && item['channel'] != null) {
            final ch = item['channel'].toString();
            if (!channels.contains(ch)) channels.add(ch);
          } else if (item != null) {
            final ch = item.toString();
            if (!channels.contains(ch)) channels.add(ch);
          }
        }
      }
      if (channels.length > 1) {
        result['channels'] = channels;
      }

      // Parse htmodelist
      final htModes = <String>[];
      dynamic htData;
      if (htRes is List && htRes.length > 1 && htRes[0] == 0) {
        htData = htRes[1];
      }
      if (htData is Map) {
        final resObj = htData['results'] ?? htData['htmodelist'];
        if (resObj is Map) {
          resObj.forEach((k, v) {
            if (v == true || v == 1 || v == '1') htModes.add(k.toString());
          });
        } else if (resObj is List) {
          htData = resObj;
        }
      }
      if (htData is List) {
        for (final item in htData) {
          if (item != null && item.toString().isNotEmpty) {
            htModes.add(item.toString());
          }
        }
      }
      if (htModes.isEmpty) {
        try {
          final infoRes = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'iwinfo',
            method: 'info',
            params: {'device': targetDevice},
            context: mCtx,
          );
          if (infoRes is List &&
              infoRes.length > 1 &&
              infoRes[0] == 0 &&
              infoRes[1] is Map) {
            final infoMap = infoRes[1] as Map;
            final modesList = infoMap['htmodes'];
            if (modesList is List) {
              for (final item in modesList) {
                if (item != null && item.toString().isNotEmpty) {
                  htModes.add(item.toString());
                }
              }
            }
          }
        } catch (_) {}
      }

      if (htModes.isNotEmpty) {
        result['htModes'] = htModes;
      }

      // Parse txpowerlist
      final txPowers = <String>['auto'];
      dynamic txData;
      if (txRes is List && txRes.length > 1 && txRes[0] == 0) {
        txData = txRes[1];
      }
      if (txData is Map) {
        txData = txData['results'] ?? txData['txpowerlist'];
      }
      if (txData is List) {
        for (final item in txData) {
          if (item is Map && item['dbm'] != null) {
            final dbm = item['dbm'].toString();
            if (!txPowers.contains(dbm)) txPowers.add(dbm);
          } else if (item != null) {
            final pwr = item.toString();
            if (!txPowers.contains(pwr)) txPowers.add(pwr);
          }
        }
      }
      if (txPowers.length > 1) {
        result['txPowers'] = txPowers;
      }
    } catch (e) {
      Logger.debug('fetchWirelessRadioCapabilities failed for $radioName: $e');
    }
    return result;
  }

  List<Map<String, String>> _fallbackEncryptions() => [
    {'value': 'sae', 'label': 'WPA3-SAE (Personal / Strict)'},
    {'value': 'sae-mixed', 'label': 'WPA2/WPA3 Mixed (Transitional)'},
    {'value': 'psk2', 'label': 'WPA2-PSK (CCMP / AES)'},
    {'value': 'psk', 'label': 'WPA-PSK (Legacy / WPA1)'},
    {'value': 'owe', 'label': 'Enhanced Open (OWE)'},
    {'value': 'none', 'label': 'Open / No Encryption'},
  ];

  List<Map<String, String>> _fallbackCiphers() => [
    {'value': 'auto', 'label': 'Auto (Hardware Default)'},
    {'value': 'ccmp', 'label': 'CCMP (AES)'},
    {'value': 'gcmp256', 'label': 'GCMP-256 (High Security)'},
    {'value': 'gcmp128', 'label': 'GCMP-128'},
    {'value': 'tkip', 'label': 'TKIP (Legacy)'},
  ];

  String _formatEncLabel(String raw) {
    switch (raw) {
      case 'sae':
        return 'WPA3-SAE (Personal / Strict)';
      case 'psk2+ccmp':
      case 'psk2':
        return 'WPA2-PSK (CCMP / AES)';
      case 'psk+ccmp':
      case 'psk':
        return 'WPA-PSK (Legacy / WPA1)';
      case 'owe':
        return 'Enhanced Open (OWE)';
      case 'none':
        return 'Open / No Encryption';
      case 'sae-mixed':
      case 'psk2+sae':
        return 'WPA2/WPA3 Mixed (Transitional)';
      default:
        return raw.toUpperCase();
    }
  }

  String _formatCipherLabel(String raw) {
    switch (raw) {
      case 'auto':
        return 'Auto (Hardware Default)';
      case 'ccmp':
        return 'CCMP (AES)';
      case 'gcmp-256':
      case 'gcmp256':
        return 'GCMP-256 (High Security)';
      case 'gcmp-128':
      case 'gcmp128':
        return 'GCMP-128';
      case 'tkip':
        return 'TKIP (Legacy)';
      default:
        return raw.toUpperCase();
    }
  }

  @override
  Future<bool> addWirelessInterface(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String radioName,
    required String ssid,
    required String encryption,
    required String key,
    required String network,
    BuildContext? context,
  }) async {
    try {
      final addRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'add',
        params: {'config': 'wireless', 'type': 'wifi-iface'},
        context: mountedContext(context),
      );

      String? sectionName;
      if (addRes is List &&
          addRes.isNotEmpty &&
          addRes[0] == 0 &&
          addRes.length > 1) {
        final data = addRes[1];
        if (data is Map && data['section'] != null) {
          sectionName = data['section'].toString();
        } else if (data is String) {
          sectionName = data;
        }
      }

      if (sectionName == null || sectionName.isEmpty) {
        return false;
      }

      // Immediately rename anonymous cfg###### section to wifinet# to prevent
      // LuCI "Wireless configuration migration" dialog on next UI visit.
      final namedSection = await _nextWifinetName(
        ipAddress,
        sysauth,
        useHttps,
        mountedContext(context),
      );
      final renamed = await _renameUciSection(
        ipAddress,
        sysauth,
        useHttps,
        'wireless',
        sectionName,
        namedSection,
        mountedContext(context),
      );
      if (renamed) sectionName = namedSection;

      final values = <String, String>{
        'device': radioName,
        'mode': 'ap',
        'network': network,
        'ssid': ssid,
        'encryption': encryption,
        'disabled': '0',
      };
      if (encryption != 'none' && key.isNotEmpty) {
        values['key'] = key;
      }
      if (encryption == 'sae' || encryption == 'sae-mixed') {
        values['ieee80211w'] = encryption == 'sae' ? '2' : '1';
      }

      final setRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'set',
        params: {
          'config': 'wireless',
          'section': sectionName,
          'values': values,
        },
        context: mountedContext(context),
      );

      if (setRes is List && setRes.isNotEmpty && setRes[0] != 0) {
        await uciRevert(
          ipAddress,
          sysauth,
          useHttps,
          config: 'wireless',
          context: mountedContext(context),
        );
        return false;
      }

      final applyRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'apply',
        params: {'rollback': false},
        context: mountedContext(context),
      );
      if (applyRes is List && applyRes.isNotEmpty && applyRes[0] == 0) {
        await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'uci',
          method: 'confirm',
          context: mountedContext(context),
        );
        return true;
      }
      await uciRevert(
        ipAddress,
        sysauth,
        useHttps,
        config: 'wireless',
        context: mountedContext(context),
      );
      return false;
    } catch (e, stack) {
      Logger.exception(
        'addWirelessInterface failed for radio $radioName',
        e,
        stack,
      );
      await uciRevert(
        ipAddress,
        sysauth,
        useHttps,
        config: 'wireless',
        context: mountedContext(context),
      );
      return false;
    }
  }

  @override
  Future<bool> deleteWirelessInterface(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionName,
    BuildContext? context,
  }) async {
    try {
      final delRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'delete',
        params: {'config': 'wireless', 'section': sectionName},
        context: mountedContext(context),
      );

      if (delRes is List && delRes.isNotEmpty && delRes[0] != 0) {
        await uciRevert(
          ipAddress,
          sysauth,
          useHttps,
          config: 'wireless',
          context: mountedContext(context),
        );
        return false;
      }

      final applyRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'apply',
        params: {'rollback': false},
        context: mountedContext(context),
      );
      if (applyRes is List && applyRes.isNotEmpty && applyRes[0] == 0) {
        await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'uci',
          method: 'confirm',
          context: mountedContext(context),
        );
        return true;
      }
      await uciRevert(
        ipAddress,
        sysauth,
        useHttps,
        config: 'wireless',
        context: mountedContext(context),
      );
      return false;
    } catch (e, stack) {
      Logger.exception(
        'deleteWirelessInterface failed for $sectionName',
        e,
        stack,
      );
      await uciRevert(
        ipAddress,
        sysauth,
        useHttps,
        config: 'wireless',
        context: mountedContext(context),
      );
      return false;
    }
  }

  Future<bool> _ensureUciSection(
    String ipAddress,
    String sysauth,
    bool useHttps,
    String config,
    String section,
    String type,
    Map<String, dynamic> values, {
    BuildContext? context,
  }) async {
    try {
      final setRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'set',
        params: {'config': config, 'section': section, 'values': values},
        context: context,
      );
      if (setRes is List && setRes.isNotEmpty && setRes[0] == 0) {
        return true;
      }
      final addRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'add',
        params: {
          'config': config,
          'type': type,
          'name': section,
          'values': values,
        },
        context: context,
      );
      return addRes is List && addRes.isNotEmpty && addRes[0] == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> provisionGuestNetwork(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String radioName,
    required String ssid,
    required String encryption,
    required String key,
    String guestIp = '192.168.2.1',
    bool isolateClients = true,
    String network = 'guest',
    // Advanced radio settings
    String? country,
    String? channel,
    String? htMode,
    String? txPower,
    // Fast roaming (802.11r/k/v)
    bool ieee80211r = false,
    bool ftOverDs = false,
    bool ftPskGenerateLocal = false,
    String? mobilityDomain,
    // Wireless advanced settings
    bool wmm = true,
    bool hidden = false,
    int? dtimPeriod,
    int? gtkRekey,
    int? inactivityLimit,
    int? maxListenInterval,
    bool disassocLowAck = true,
    bool multicastToUnicast = false,
    bool wds = false,
    // MAC filtering
    String? macfilter,
    List<String>? maclist,
    BuildContext? context,
  }) async {
    try {
      final mCtx = mountedContext(context);

      // Step 1 & 2: Configure network and DHCP only if creating the default 'guest' network
      // If using a different network, assume it already exists with proper DHCP/firewall config
      if (network == 'guest') {
        // Configure /etc/config/network interface 'guest'
        await _ensureUciSection(
          ipAddress,
          sysauth,
          useHttps,
          'network',
          'guest',
          'interface',
          {'proto': 'static', 'ipaddr': guestIp, 'netmask': '255.255.255.0'},
          context: mCtx,
        );

        // Configure /etc/config/dhcp section 'guest'
        await _ensureUciSection(
          ipAddress,
          sysauth,
          useHttps,
          'dhcp',
          'guest',
          'dhcp',
          {
            'interface': 'guest',
            'start': '100',
            'limit': '150',
            'leasetime': '12h',
          },
          context: mCtx,
        );

        // Step 3: Configure /etc/config/firewall zone and forwarding for guest
        // Use REJECT for input to prevent guests from accessing router gateway / LuCI / SSH
        await _ensureUciSection(
          ipAddress,
          sysauth,
          useHttps,
          'firewall',
          'zone_guest',
          'zone',
          {
            'name': 'guest',
            'network': ['guest'],
            'input': 'REJECT',
            'output': 'ACCEPT',
            'forward': 'REJECT',
          },
          context: mCtx,
        );

        // Allow essential DHCP (UDP 67) for guest devices
        await _ensureUciSection(
          ipAddress,
          sysauth,
          useHttps,
          'firewall',
          'rule_guest_dhcp',
          'rule',
          {
            'name': 'Allow-Guest-DHCP',
            'src': 'guest',
            'proto': 'udp',
            'dest_port': '67',
            'target': 'ACCEPT',
          },
          context: mCtx,
        );

        // Allow essential DNS (UDP/TCP 53) for guest devices
        await _ensureUciSection(
          ipAddress,
          sysauth,
          useHttps,
          'firewall',
          'rule_guest_dns',
          'rule',
          {
            'name': 'Allow-Guest-DNS',
            'src': 'guest',
            'proto': 'tcpudp',
            'dest_port': '53',
            'target': 'ACCEPT',
          },
          context: mCtx,
        );

        // Forward guest traffic to WAN for internet access
        await _ensureUciSection(
          ipAddress,
          sysauth,
          useHttps,
          'firewall',
          'fwd_guest_wan',
          'forwarding',
          {'src': 'guest', 'dest': 'wan'},
          context: mCtx,
        );
      }

      // Step 4: Add wireless interface for guest SSID
      final addWifiRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'add',
        params: {'config': 'wireless', 'type': 'wifi-iface'},
        context: mCtx,
      );

      String? sectionName;
      if (addWifiRes is List &&
          addWifiRes.isNotEmpty &&
          addWifiRes[0] == 0 &&
          addWifiRes.length > 1) {
        final data = addWifiRes[1];
        if (data is Map && data['section'] != null) {
          sectionName = data['section'].toString();
        } else if (data is String) {
          sectionName = data;
        }
      }

      if (sectionName == null || sectionName.isEmpty) {
        return false;
      }

      // Immediately rename anonymous cfg###### section to wifinet# to prevent
      // LuCI "Wireless configuration migration" dialog on next UI visit.
      final namedGuestSection = await _nextWifinetName(
        ipAddress,
        sysauth,
        useHttps,
        mCtx,
      );
      final guestRenamed = await _renameUciSection(
        ipAddress,
        sysauth,
        useHttps,
        'wireless',
        sectionName,
        namedGuestSection,
        mCtx,
      );
      if (guestRenamed) sectionName = namedGuestSection;

      final wifiValues = <String, String>{
        'device': radioName,
        'mode': 'ap',
        'network': network,
        'ssid': ssid,
        'encryption': encryption,
        'isolate': isolateClients ? '1' : '0',
        'disabled': '0',
      };

      // Add advanced radio settings
      if (country != null && country.isNotEmpty) {
        wifiValues['country'] = country;
      }
      if (channel != null && channel.isNotEmpty) {
        wifiValues['channel'] = channel;
      }
      if (htMode != null && htMode.isNotEmpty) {
        wifiValues['htmode'] = htMode;
      }
      if (txPower != null && txPower.isNotEmpty && txPower != 'auto') {
        wifiValues['txpower'] = txPower;
      }

      // Add encryption and key
      if (encryption != 'none' && key.isNotEmpty) {
        wifiValues['key'] = key;
      }

      // Handle PMF (ieee80211w) for SAE/SAE-mixed and 802.11r
      if (encryption == 'sae' || encryption == 'sae-mixed' || ieee80211r) {
        if (encryption == 'sae') {
          wifiValues['ieee80211w'] = '2'; // Required for WPA3-SAE
        } else if (encryption == 'sae-mixed' || ieee80211r) {
          wifiValues['ieee80211w'] =
              '1'; // Optional for transitional or 802.11r
        }
      }

      // Fast roaming (802.11r/k/v)
      if (ieee80211r) {
        wifiValues['ieee80211r'] = '1';
        if (ftOverDs) wifiValues['ft_over_ds'] = '1';
        if (ftPskGenerateLocal) wifiValues['ft_psk_generate_local'] = '1';
        if (mobilityDomain != null && mobilityDomain.isNotEmpty) {
          wifiValues['mobility_domain'] = mobilityDomain;
        }
      }

      // Wireless advanced settings
      wifiValues['wmm'] = wmm ? '1' : '0';
      wifiValues['hidden'] = hidden ? '1' : '0';

      if (dtimPeriod != null) {
        wifiValues['dtim_period'] = dtimPeriod.toString();
      }
      if (gtkRekey != null) {
        wifiValues['gtk_rekey'] = gtkRekey.toString();
      }
      if (inactivityLimit != null) {
        wifiValues['inactivity_limit'] = inactivityLimit.toString();
      }
      if (maxListenInterval != null) {
        wifiValues['max_listen_interval'] = maxListenInterval.toString();
      }
      wifiValues['disassoc_low_ack'] = disassocLowAck ? '1' : '0';
      wifiValues['multicast_to_unicast'] = multicastToUnicast ? '1' : '0';
      wifiValues['wds'] = wds ? '1' : '0';

      // MAC filtering
      if (macfilter != null && macfilter.isNotEmpty && macfilter != 'disable') {
        wifiValues['macfilter'] = macfilter;
        if (maclist != null && maclist.isNotEmpty) {
          wifiValues['maclist'] = maclist.join(' ');
        }
      }

      await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'set',
        params: {
          'config': 'wireless',
          'section': sectionName,
          'values': wifiValues,
        },
        context: mCtx,
      );

      // Step 5: Execute cross-config atomic apply and immediately confirm to persist changes
      final applyRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'apply',
        params: {'rollback': false},
        context: mCtx,
      );
      if (applyRes is List && applyRes.isNotEmpty && applyRes[0] == 0) {
        await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'uci',
          method: 'confirm',
          context: mCtx,
        );
        return true;
      }

      // Revert staged changes across modified configs on failure
      for (final cfg in ['wireless', 'firewall', 'dhcp', 'network']) {
        await uciRevert(
          ipAddress,
          sysauth,
          useHttps,
          config: cfg,
          context: mCtx,
        );
      }
      return false;
    } catch (e, stack) {
      Logger.exception(
        'provisionGuestNetwork failed for radio $radioName',
        e,
        stack,
      );
      for (final cfg in ['wireless', 'firewall', 'dhcp', 'network']) {
        await uciRevert(
          ipAddress,
          sysauth,
          useHttps,
          config: cfg,
          context: mountedContext(context),
        );
      }
      return false;
    }
  }

  @override
  Future<bool> setWifiAccessControl(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required Map<String, List<String>> maclistByIface,
    required Map<String, String> macfilterByIface,
    BuildContext? context,
  }) async {
    final mCtx = mountedContext(context);
    try {
      final allSections = {...maclistByIface.keys, ...macfilterByIface.keys};
      for (final section in allSections) {
        final values = <String, dynamic>{};
        if (macfilterByIface.containsKey(section)) {
          values['macfilter'] = macfilterByIface[section]!;
        }
        if (maclistByIface.containsKey(section)) {
          values['maclist'] = maclistByIface[section]!;
        }

        final res = await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'uci',
          method: 'set',
          params: {'config': 'wireless', 'section': section, 'values': values},
          context: mCtx,
        );
        if (res is List && res.isNotEmpty && res[0] != 0) {
          await uciRevert(
            ipAddress,
            sysauth,
            useHttps,
            config: 'wireless',
            context: mCtx,
          );
          return false;
        }
      }

      final applyRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'apply',
        params: {'rollback': false},
        context: mCtx,
      );
      if (applyRes is List && applyRes.isNotEmpty && applyRes[0] == 0) {
        return true;
      }
      await uciRevert(
        ipAddress,
        sysauth,
        useHttps,
        config: 'wireless',
        context: mCtx,
      );
      return false;
    } catch (e, stack) {
      Logger.exception('setWifiAccessControl failed', e, stack);
      await uciRevert(
        ipAddress,
        sysauth,
        useHttps,
        config: 'wireless',
        context: mCtx,
      );
      return false;
    }
  }

  @override
  Future<bool> confirmWifiAccessControl(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    try {
      final res = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'confirm',
        params: {},
        context: mountedContext(context),
      );
      return res is List && res.isNotEmpty && res[0] == 0;
    } catch (e, stack) {
      Logger.exception('confirmWifiAccessControl failed', e, stack);
      return false;
    }
  }

  @override
  Future<bool> revertWifiAccessControl(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required Map<String, List<String>> maclistByIface,
    required Map<String, String> macfilterByIface,
    BuildContext? context,
  }) async {
    try {
      final res = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'revert',
        params: {'config': 'wireless'},
        context: mountedContext(context),
      );

      // Fallback: If uci revert didn't clean everything, explicitly re-apply prior state
      final allSections = {...maclistByIface.keys, ...macfilterByIface.keys};
      for (final section in allSections) {
        final values = <String, dynamic>{};
        if (macfilterByIface.containsKey(section)) {
          values['macfilter'] = macfilterByIface[section]!;
        }
        if (maclistByIface.containsKey(section)) {
          values['maclist'] = maclistByIface[section]!;
        }
        await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'uci',
          method: 'set',
          params: {'config': 'wireless', 'section': section, 'values': values},
          context: mountedContext(context),
        );
      }
      await uciCommit(
        ipAddress,
        sysauth,
        useHttps,
        config: 'wireless',
        context: mountedContext(context),
      );
      final reloadRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': '/sbin/wifi',
          'params': ['reload'],
        },
        context: mountedContext(context),
      );

      return res is List &&
          res.isNotEmpty &&
          res[0] == 0 &&
          _execSucceeded(reloadRes);
    } catch (e, stack) {
      Logger.exception('revertWifiAccessControl failed', e, stack);
      return false;
    }
  }

  @override
  Future<bool> autoFixPermissions(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    try {
      final res = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': '/bin/sh',
          'params': [
            '-c',
            'mkdir -p /usr/share/rpcd/acl.d/ && '
                'printf \'{\\n  "luci-app-tailscale": {\\n    "description": "Tailscale VPN ACL Permissions",\\n    "read": {\\n      "file": {\\n        "/usr/sbin/tailscale": [ "exec" ],\\n        "/usr/bin/tailscale": [ "exec" ],\\n        "/usr/bin/nextdns": [ "exec" ],\\n        "/usr/bin/cloudflared": [ "exec" ]\\n      }\\n    },\\n    "write": {\\n      "file": {\\n        "/usr/sbin/tailscale": [ "exec" ],\\n        "/usr/bin/tailscale": [ "exec" ],\\n        "/usr/bin/nextdns": [ "exec" ],\\n        "/usr/bin/cloudflared": [ "exec" ]\\n      }\\n    }\\n  }\\n}\\n\' > /usr/share/rpcd/acl.d/luci-app-tailscale.json && '
                'if command -v apk >/dev/null 2>&1; then '
                'apk update && apk add luci-mod-rpc rpcd-mod-luci rpcd-mod-iwinfo luci-mod-status; '
                'else '
                'opkg update && opkg install luci-mod-rpc rpcd-mod-luci rpcd-mod-iwinfo luci-mod-status; '
                'fi && /etc/init.d/rpcd restart',
          ],
        },
        context: context,
      );
      if (_execSucceeded(res)) {
        return true;
      }

      final fallbackRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': '/bin/sh',
          'args': [
            '-c',
            'mkdir -p /usr/share/rpcd/acl.d/ && '
                'printf \'{\\n  "luci-app-tailscale": {\\n    "description": "Tailscale VPN ACL Permissions",\\n    "read": {\\n      "file": {\\n        "/usr/sbin/tailscale": [ "exec" ],\\n        "/usr/bin/tailscale": [ "exec" ],\\n        "/usr/bin/nextdns": [ "exec" ],\\n        "/usr/bin/cloudflared": [ "exec" ]\\n      }\\n    },\\n    "write": {\\n      "file": {\\n        "/usr/sbin/tailscale": [ "exec" ],\\n        "/usr/bin/tailscale": [ "exec" ],\\n        "/usr/bin/nextdns": [ "exec" ],\\n        "/usr/bin/cloudflared": [ "exec" ]\\n      }\\n    }\\n  }\\n}\\n\' > /usr/share/rpcd/acl.d/luci-app-tailscale.json && '
                'if command -v apk >/dev/null 2>&1; then '
                'apk update && apk add luci-mod-rpc rpcd-mod-luci rpcd-mod-iwinfo luci-mod-status; '
                'else '
                'opkg update && opkg install luci-mod-rpc rpcd-mod-luci rpcd-mod-iwinfo luci-mod-status; '
                'fi && /etc/init.d/rpcd restart',
          ],
        },
        context: context,
      );
      return _execSucceeded(fallbackRes);
    } catch (e, stack) {
      Logger.exception('autoFixPermissions failed', e, stack);
      return false;
    }
  }

  @override
  Future<bool> ensureSilentPermissions(
    String ipAddress,
    String sysauth,
    bool useHttps,
  ) async {
    try {
      const aclScript =
          'if [ ! -f /usr/share/rpcd/acl.d/yet-another-luci-app.json ]; then '
          'mkdir -p /usr/share/rpcd/acl.d/ && '
          'printf \'{\\n  "yet-another-luci-app": {\\n    "description": "Yet Another LuCI App Silent RPC Permissions",\\n    "read": {\\n      "file": {\\n        "/usr/sbin/tailscale": [ "exec" ],\\n        "/usr/bin/tailscale": [ "exec" ],\\n        "/usr/bin/nextdns": [ "exec" ],\\n        "/usr/bin/cloudflared": [ "exec" ]\\n      },\\n      "ubus": {\\n        "iwinfo": [ "*" ],\\n        "rc": [ "*" ],\\n        "file": [ "*" ],\\n        "luci-rpc": [ "*" ]\\n      }\\n    },\\n    "write": {\\n      "file": {\\n        "/usr/sbin/tailscale": [ "exec" ],\\n        "/usr/bin/tailscale": [ "exec" ],\\n        "/usr/bin/nextdns": [ "exec" ],\\n        "/usr/bin/cloudflared": [ "exec" ]\\n      },\\n      "ubus": {\\n        "iwinfo": [ "*" ],\\n        "rc": [ "*" ],\\n        "file": [ "*" ],\\n        "luci-rpc": [ "*" ]\\n      }\\n    }\\n  }\\n}\\n\' > /usr/share/rpcd/acl.d/yet-another-luci-app.json && '
          '(/etc/init.d/rpcd reload 2>/dev/null || /etc/init.d/rpcd restart 2>/dev/null || true); '
          'fi';

      await call(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': '/bin/sh',
          'params': ['-c', aclScript],
        },
      );
      return true;
    } catch (e) {
      Logger.warning('Silent background permission setup skipped/failed: $e');
      return false;
    }
  }

  @override
  Future<bool> manageServiceAction(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String serviceName,
    required String action,
    BuildContext? context,
  }) async {
    try {
      try {
        final rcRes = await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'rc',
          method: 'init',
          params: {'name': serviceName, 'action': action},
          context: context,
        );
        if (_execSucceeded(rcRes)) return true;
      } catch (_) {
        // Older LuCI/rpcd builds may not expose rc.init; fall back below.
      }

      final res = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': '/etc/init.d/$serviceName',
          'params': [action],
        },
        context: context,
      );
      return _execSucceeded(res);
    } catch (e, stack) {
      Logger.exception('manageServiceAction failed for $serviceName', e, stack);
      return false;
    }
  }

  /// Enforces client restriction via firewall rules (UCI firewall + nftables/iptables)
  /// and notifies user if the firewall rule was created for the first time.
  Future<bool> _enforceFirewallBlock({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String macAddress,
    String rulePrefix = 'nointernet_wireless_clients',
    BuildContext? context,
  }) async {
    final macUpper = macAddress.toUpperCase().replaceAll('-', ':');
    final macLower = macAddress.toLowerCase();
    final ruleName = "nointernet_wireless_clients";

    bool ruleExisted = false;

    // 1. Check existing uci firewall rules via native ubus call
    try {
      final getRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': 'firewall'},
        context: mountedContext(context),
      );

      if (getRes is List && getRes.length > 1 && getRes[0] == 0) {
        final values =
            (getRes[1] as Map<String, dynamic>?)?['values']
                as Map<String, dynamic>? ??
            {};
        String? targetSecKey;
        List<String> currentMacs = [];

        for (final entry in values.entries) {
          final sec = entry.value;
          if (sec is Map<String, dynamic>) {
            final name = sec['name']?.toString() ?? '';
            if (name == ruleName) {
              ruleExisted = true;
              targetSecKey = entry.key;
              final srcMac = sec['src_mac'];
              if (srcMac is List) {
                currentMacs = srcMac
                    .map((e) => e.toString().toUpperCase())
                    .toList();
              } else if (srcMac != null) {
                currentMacs = [srcMac.toString().toUpperCase()];
              }
              break;
            }
          }
        }

        if (!ruleExisted) {
          await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'add',
            params: {
              'config': 'firewall',
              'type': 'rule',
              'values': {
                'name': ruleName,
                'src': '*',
                'dest': 'wan',
                'src_mac': [macUpper],
                'target': 'DROP',
                'enabled': '1',
              },
            },
            context: mountedContext(context),
          );
        } else if (targetSecKey != null && !currentMacs.contains(macUpper)) {
          currentMacs.add(macUpper);
          await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'set',
            params: {
              'config': 'firewall',
              'section': targetSecKey,
              'values': {'src': '*', 'src_mac': currentMacs},
            },
            context: mountedContext(context),
          );
        }

        await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'uci',
          method: 'commit',
          params: {'config': 'firewall'},
          context: mountedContext(context),
        );
        await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'rc',
          method: 'init',
          params: {'name': 'firewall', 'action': 'reload'},
          context: mountedContext(context),
        );
      }
    } catch (e) {
      Logger.warning(
        'Native ubus firewall rule check/add encountered issue: $e',
      );
    }

    // 2. Shell fallback check and execute for single universal rule (uci, nft, and iptables)
    final shellScript =
        '''
MAC_U="$macUpper"
MAC_L="$macLower"
RULE_NAME="$ruleName"

EXISTS=\$(uci show firewall 2>/dev/null | grep -i "name=['"]*\${RULE_NAME}['"]*" | head -n 1)
if [ -z "\$EXISTS" ]; then
  uci add firewall rule >/dev/null
  uci set firewall.@rule[-1].name="\$RULE_NAME"
  uci set firewall.@rule[-1].src='*'
  uci set firewall.@rule[-1].dest='wan'
  uci add_list firewall.@rule[-1].src_mac="\$MAC_U"
  uci set firewall.@rule[-1].target='DROP'
  uci set firewall.@rule[-1].enabled='1'
else
  SEC=\$(uci show firewall 2>/dev/null | grep -i "name=['"]*\${RULE_NAME}['"]*" | cut -d. -f2)
  if [ -n "\$SEC" ]; then
    uci set firewall.\${SEC}.src='*' 2>/dev/null || true
    MAC_EXISTS=\$(uci get firewall.\${SEC}.src_mac 2>/dev/null | grep -i "\$MAC_U")
    if [ -z "\$MAC_EXISTS" ]; then
      uci add_list firewall.\${SEC}.src_mac="\$MAC_U"
    fi
  fi
fi
uci commit firewall
/etc/init.d/firewall reload >/dev/null 2>&1

nft add rule inet fw4 forward ether saddr "\$MAC_U" drop >/dev/null 2>&1 || true
nft add rule inet fw4 forward ether saddr "\$MAC_L" drop >/dev/null 2>&1 || true
iptables -I FORWARD -m mac --mac-source "\$MAC_U" -j DROP >/dev/null 2>&1 || true
iptables -I FORWARD -m mac --mac-source "\$MAC_L" -j DROP >/dev/null 2>&1 || true
exit 0
''';

    await callWithContext(
      ipAddress,
      sysauth,
      useHttps,
      object: 'file',
      method: 'exec',
      params: fileExecParams('/bin/sh', ['-c', shellScript]),
      context: mountedContext(context),
    );

    if (!ruleExisted) {
      Logger.info(
        'Created firewall rule "$ruleName" to restrict client $macUpper',
      );
    }

    return true;
  }

  /// Removes firewall block rules for the specified client MAC.
  Future<bool> _removeFirewallBlock({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String macAddress,
    BuildContext? context,
  }) async {
    final macUpper = macAddress.toUpperCase().replaceAll('-', ':');
    final macLower = macAddress.toLowerCase();
    final macClean = macUpper.replaceAll(':', '');
    final ruleName = "nointernet_wireless_clients";
    bool modified = false;

    try {
      final getRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': 'firewall'},
        context: mountedContext(context),
      );

      if (getRes is List && getRes.length > 1 && getRes[0] == 0) {
        final values =
            (getRes[1] as Map<String, dynamic>?)?['values']
                as Map<String, dynamic>? ??
            {};
        for (final entry in values.entries) {
          final secKey = entry.key;
          final sec = entry.value;
          if (sec is Map<String, dynamic>) {
            final name = sec['name']?.toString() ?? '';
            final target = sec['target']?.toString().toUpperCase() ?? '';
            final srcMac = sec['src_mac'];
            final destMac = sec['dest_mac'];

            List<String> macs = [];
            if (srcMac is List) {
              macs.addAll(
                srcMac.map(
                  (e) => e.toString().toUpperCase().replaceAll('-', ':'),
                ),
              );
            } else if (srcMac != null) {
              macs.add(srcMac.toString().toUpperCase().replaceAll('-', ':'));
            }
            if (destMac is List) {
              macs.addAll(
                destMac.map(
                  (e) => e.toString().toUpperCase().replaceAll('-', ':'),
                ),
              );
            } else if (destMac != null) {
              macs.add(destMac.toString().toUpperCase().replaceAll('-', ':'));
            }

            final matchesTargetMac = macs.any(
              (m) => m == macUpper || m.toLowerCase() == macLower,
            );
            final isBlockTarget =
                target == 'DROP' ||
                target == 'REJECT' ||
                target == 'STOP' ||
                name.startsWith('Pause_Internet_') ||
                name.startsWith('Ban_Client_') ||
                name.startsWith('Kick_Client_') ||
                name == ruleName;

            if (matchesTargetMac && isBlockTarget) {
              if (name == ruleName || macs.length > 1) {
                macs.removeWhere(
                  (m) => m == macUpper || m.toLowerCase() == macLower,
                );
                if (macs.isEmpty) {
                  await callWithContext(
                    ipAddress,
                    sysauth,
                    useHttps,
                    object: 'uci',
                    method: 'delete',
                    params: {'config': 'firewall', 'section': secKey},
                    context: mountedContext(context),
                  );
                } else {
                  await callWithContext(
                    ipAddress,
                    sysauth,
                    useHttps,
                    object: 'uci',
                    method: 'set',
                    params: {
                      'config': 'firewall',
                      'section': secKey,
                      'values': {'src_mac': macs},
                    },
                    context: mountedContext(context),
                  );
                }
              } else {
                await callWithContext(
                  ipAddress,
                  sysauth,
                  useHttps,
                  object: 'uci',
                  method: 'delete',
                  params: {'config': 'firewall', 'section': secKey},
                  context: mountedContext(context),
                );
              }
              modified = true;
            }
          }
        }
        if (modified) {
          await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'commit',
            params: {'config': 'firewall'},
            context: mountedContext(context),
          );
          await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'rc',
            method: 'init',
            params: {'name': 'firewall', 'action': 'reload'},
            context: mountedContext(context),
          );
        }
      }
    } catch (e) {
      Logger.warning('Native ubus firewall remove encountered issue: $e');
    }

    final script =
        '''
MAC_U="$macUpper"
MAC_L="$macLower"
CLEAN="$macClean"
RULE_NAME="$ruleName"

for sec in \$(uci show firewall 2>/dev/null | grep -iE "src_mac|dest_mac" | grep -i "\$MAC_U" | cut -d. -f2); do
  uci del_list firewall.\${sec}.src_mac="\$MAC_U" 2>/dev/null || true
  uci del_list firewall.\${sec}.src_mac="\$MAC_L" 2>/dev/null || true
  uci del_list firewall.\${sec}.dest_mac="\$MAC_U" 2>/dev/null || true
  uci del_list firewall.\${sec}.dest_mac="\$MAC_L" 2>/dev/null || true
  REMAINING=\$(uci get firewall.\${sec}.src_mac 2>/dev/null | tr ' ' '\\n' | grep -v "^\$" | wc -l)
  if [ "\$REMAINING" -eq 0 ]; then
    uci delete firewall.\${sec} 2>/dev/null || true
  fi
done

for legacy in \$(uci show firewall 2>/dev/null | grep -iE "Pause_Internet_\${CLEAN}|Ban_Client_\${CLEAN}|Kick_Client_\${CLEAN}" | cut -d. -f2); do
  uci delete firewall.\${legacy} 2>/dev/null || true
done

uci commit firewall
/etc/init.d/firewall reload >/dev/null 2>&1 || true

nft delete rule inet fw4 forward ether saddr "\$MAC_U" >/dev/null 2>&1 || true
nft delete rule inet fw4 forward ether saddr "\$MAC_L" >/dev/null 2>&1 || true
iptables -D FORWARD -m mac --mac-source "\$MAC_U" -j DROP >/dev/null 2>&1 || true
iptables -D FORWARD -m mac --mac-source "\$MAC_L" -j DROP >/dev/null 2>&1 || true
exit 0
''';

    try {
      await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: fileExecParams('/bin/sh', ['-c', script]),
        context: mountedContext(context),
      );
    } catch (e) {
      Logger.warning('_removeFirewallBlock shell script error: $e');
    }

    return true;
  }

  /// Removes wireless MAC-filter ban rules for the specified client MAC.
  Future<bool> _removeWirelessMacFilter({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String macAddress,
    BuildContext? context,
  }) async {
    final macUpper = macAddress.toUpperCase().replaceAll('-', ':');
    final macLower = macAddress.toLowerCase();
    bool modified = false;

    try {
      final getRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': 'wireless'},
        context: mountedContext(context),
      );

      if (getRes is List && getRes.length > 1 && getRes[0] == 0) {
        final values =
            (getRes[1] as Map<String, dynamic>?)?['values']
                as Map<String, dynamic>? ??
            {};
        for (final entry in values.entries) {
          final secKey = entry.key;
          final sec = entry.value;
          if (sec is Map<String, dynamic>) {
            final macfilter = sec['macfilter']?.toString().toLowerCase();
            if (macfilter == 'deny' || macfilter == '2') {
              final rawMaclist = sec['maclist'];
              List<String> macs = rawMaclist is List
                  ? rawMaclist
                        .map(
                          (e) =>
                              e.toString().toUpperCase().replaceAll('-', ':'),
                        )
                        .toList()
                  : (rawMaclist != null
                        ? [
                            rawMaclist.toString().toUpperCase().replaceAll(
                              '-',
                              ':',
                            ),
                          ]
                        : []);

              if (macs.any(
                (m) => m == macUpper || m.toLowerCase() == macLower,
              )) {
                macs.removeWhere(
                  (m) => m == macUpper || m.toLowerCase() == macLower,
                );
                await callWithContext(
                  ipAddress,
                  sysauth,
                  useHttps,
                  object: 'uci',
                  method: 'set',
                  params: {
                    'config': 'wireless',
                    'section': secKey,
                    'values': {'maclist': macs},
                  },
                  context: mountedContext(context),
                );
                modified = true;
              }
            }
          }
        }
        if (modified) {
          await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'commit',
            params: {'config': 'wireless'},
            context: mountedContext(context),
          );
          await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'network.wireless',
            method: 'up',
            params: {},
            context: mountedContext(context),
          );
        }
      }
    } catch (e) {
      Logger.warning('_removeWirelessMacFilter ubus error: $e');
    }

    final script =
        '''
MAC_U="$macUpper"
MAC_L="$macLower"

for sec in \$(uci show wireless 2>/dev/null | grep -i "maclist" | grep -i "\$MAC_U" | cut -d. -f2); do
  uci del_list wireless.\${sec}.maclist="\$MAC_U" 2>/dev/null || true
  uci del_list wireless.\${sec}.maclist="\$MAC_L" 2>/dev/null || true
done

uci commit wireless
wifi reload >/dev/null 2>&1 || ubus call network.wireless reload >/dev/null 2>&1 || true
exit 0
''';

    try {
      await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: fileExecParams('/bin/sh', ['-c', script]),
        context: mountedContext(context),
      );
    } catch (e) {
      Logger.warning('_removeWirelessMacFilter shell error: $e');
    }

    return true;
  }

  @override
  Future<bool> disconnectWirelessClient(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    String? iface,
    int banTimeSeconds = 0,
    BuildContext? context,
  }) async {
    try {
      final macUpper = macAddress.toUpperCase().replaceAll('-', ':');
      final int banTimeMs = (banTimeSeconds <= 0 ? 0 : banTimeSeconds) * 1000;
      bool ubusSuccess = false;

      // 1. Native ubus call to hostapd.* del_client (whitelisted in OpenWrt rpcd ACLs)
      try {
        final hostapdObjects = <String>[];
        if (iface != null && iface.isNotEmpty) {
          hostapdObjects.add('hostapd.$iface');
        }
        final ubusList = await call(
          ipAddress,
          sysauth,
          useHttps,
          object: 'ubus',
          method: 'list',
          params: {},
        );
        if (ubusList is List) {
          for (final obj in ubusList) {
            final s = obj.toString();
            if (s.startsWith('hostapd.') && !hostapdObjects.contains(s)) {
              hostapdObjects.add(s);
            }
          }
        }

        for (final obj in hostapdObjects) {
          try {
            final delRes = await callWithContext(
              ipAddress,
              sysauth,
              useHttps,
              object: obj,
              method: 'del_client',
              params: {
                'addr': macUpper,
                'reason': 1,
                'deauth': true,
                'ban_time': banTimeMs,
              },
              context: mountedContext(context),
            );
            if (delRes is List && delRes.isNotEmpty && delRes[0] == 0) {
              ubusSuccess = true;
            }
          } catch (_) {}
        }
      } catch (e) {
        Logger.warning('Native hostapd del_client failed: $e');
      }

      // 2. Shell fallback for custom non-standard firmware setups
      try {
        final macLower = macAddress.toLowerCase();
        final targetIface = (iface != null && iface.isNotEmpty) ? iface : '';
        final cmdScript = '''
MAC_U="$macUpper"
MAC_L="$macLower"
IFACE="$targetIface"
BAN_MS="$banTimeMs"

(
  if [ -n "\$IFACE" ]; then
    /usr/sbin/hostapd_cli -i "\$IFACE" deny_acl ADD "\$MAC_U" 2>/dev/null || true
    /usr/sbin/hostapd_cli -i "\$IFACE" deauth "\$MAC_U" 2>/dev/null || true
  fi

  for s in /var/run/hostapd/* /var/run/hostapd-*/*; do
    if [ -S "\$s" ]; then
      s_dir="\${s%/*}"
      s_if="\${s##*/}"
      /usr/sbin/hostapd_cli -p "\$s_dir" -i "\$s_if" deny_acl ADD "\$MAC_U" 2>/dev/null || true
      /usr/sbin/hostapd_cli -p "\$s_dir" -i "\$s_if" deauth "\$MAC_U" 2>/dev/null || true
    fi
  done

  for dev in \$(iw dev 2>/dev/null | awk '\$1=="Interface"{print \$2}'); do
    iw dev "\$dev" station del "\$MAC_L" 2>/dev/null || true
    iw dev "\$dev" station del "\$MAC_U" 2>/dev/null || true
  done
) >/dev/null 2>&1 &
exit 0
''';

        await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'file',
          method: 'exec',
          params: fileExecParams('/bin/sh', ['-c', cmdScript]),
          context: mountedContext(context),
        );
      } catch (_) {}

      return ubusSuccess || true;
    } catch (e, stack) {
      Logger.exception('disconnectWirelessClient failed', e, stack);
      return false;
    }
  }

  @override
  Future<bool> pauseClientInternet(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    required bool pause,
    BuildContext? context,
  }) async {
    if (pause) {
      return _enforceFirewallBlock(
        ipAddress: ipAddress,
        sysauth: sysauth,
        useHttps: useHttps,
        macAddress: macAddress,
        rulePrefix: 'Pause_Internet_',
        context: context,
      );
    } else {
      return _removeFirewallBlock(
        ipAddress: ipAddress,
        sysauth: sysauth,
        useHttps: useHttps,
        macAddress: macAddress,
        context: context,
      );
    }
  }

  @override
  Future<bool> banWirelessClient(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    String? iface,
    int banTimeSeconds = 300,
    BuildContext? context,
  }) async {
    return disconnectWirelessClient(
      ipAddress,
      sysauth,
      useHttps,
      macAddress: macAddress,
      iface: iface,
      banTimeSeconds: banTimeSeconds,
      context: context,
    );
  }

  @override
  Future<bool> unbanWirelessClient(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    BuildContext? context,
  }) async {
    final macUpper = macAddress.toUpperCase().replaceAll('-', ':');
    final macLower = macAddress.toLowerCase();

    final unbanScript =
        '''
MAC_U="$macUpper"
MAC_L="$macLower"

(
  for s in /var/run/hostapd/* /var/run/hostapd-*/*; do
    if [ -S "\$s" ]; then
      s_dir="\${s%/*}"
      s_if="\${s##*/}"
      /usr/sbin/hostapd_cli -p "\$s_dir" -i "\$s_if" deny_acl REMOVE "\$MAC_U" 2>/dev/null || true
      /usr/sbin/hostapd_cli -p "\$s_dir" -i "\$s_if" deny_acl REMOVE "\$MAC_L" 2>/dev/null || true
    fi
  done

  nft delete rule inet fw4 input mac saddr "\$MAC_U" drop 2>/dev/null || true
  nft delete rule inet fw4 forward mac saddr "\$MAC_U" drop 2>/dev/null || true
  nft delete rule inet fw4 input mac saddr "\$MAC_L" drop 2>/dev/null || true
  nft delete rule inet fw4 forward mac saddr "\$MAC_L" drop 2>/dev/null || true

  iptables -D INPUT -m mac --mac-source "\$MAC_U" -j DROP 2>/dev/null || true
  iptables -D FORWARD -m mac --mac-source "\$MAC_U" -j DROP 2>/dev/null || true
  iptables -D INPUT -m mac --mac-source "\$MAC_L" -j DROP 2>/dev/null || true
  iptables -D FORWARD -m mac --mac-source "\$MAC_L" -j DROP 2>/dev/null || true
  ebtables -D INPUT -s "\$MAC_U" -j DROP 2>/dev/null || true
  ebtables -D FORWARD -s "\$MAC_U" -j DROP 2>/dev/null || true
) &
exit 0
''';

    try {
      await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: fileExecParams('/bin/sh', ['-c', unbanScript]),
        context: mountedContext(context),
      );
    } catch (e) {
      Logger.warning('unbanWirelessClient script error: $e');
    }

    final fwOk = await _removeFirewallBlock(
      ipAddress: ipAddress,
      sysauth: sysauth,
      useHttps: useHttps,
      macAddress: macAddress,
      context: context,
    );
    final wifiOk = await _removeWirelessMacFilter(
      ipAddress: ipAddress,
      sysauth: sysauth,
      useHttps: useHttps,
      macAddress: macAddress,
      context: context,
    );
    return fwOk && wifiOk;
  }

  @override
  Future<Map<String, List<Map<String, dynamic>>>>
  fetchRestrictedAndBannedClientsLive(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    try {
      final script = '''
DENY_MACS=""
for s in /var/run/hostapd/* /var/run/hostapd-*/*; do
  if [ -S "\$s" ]; then
    s_dir="\${s%/*}"
    s_if="\${s##*/}"
    DENY_MACS="\$DENY_MACS \$(/usr/sbin/hostapd_cli -p "\$s_dir" -i "\$s_if" deny_acl SHOW 2>/dev/null | grep -oE "([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}" || true)"
  fi
done

WIFI_UCI=\$(uci show wireless 2>/dev/null | grep -iE "maclist" | grep -oE "([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}" || true)

FW_UCI=\$(uci show firewall 2>/dev/null | grep -iE "(src_mac|dest_mac)" | grep -oE "([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}" || true)
NFT_MACS=\$(nft list chain inet fw4 input 2>/dev/null; nft list chain inet fw4 forward 2>/dev/null | grep -iE "drop|reject" | grep -oE "([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}" || true)
IPT_MACS=\$(iptables -L INPUT -v -n 2>/dev/null; iptables -L FORWARD -v -n 2>/dev/null | grep -iE "DROP|REJECT" | grep -oE "([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}" || true)

echo "RESTRICTED:"
echo "\$FW_UCI \$NFT_MACS \$IPT_MACS" | tr ' ' '\\n' | grep -vE "^00:00:00:00:00:00\$|^FF:FF:FF:FF:FF:FF\$" | sort -u | grep -v "^\$"

echo "BANNED:"
echo "\$DENY_MACS \$WIFI_UCI" | tr ' ' '\\n' | grep -vE "^00:00:00:00:00:00\$|^FF:FF:FF:FF:FF:FF\$" | sort -u | grep -v "^\$"
''';

      final res = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': '/bin/sh',
          'params': ['-c', script],
        },
        context: mountedContext(context),
      );

      final result = <String, List<Map<String, dynamic>>>{
        'restricted': [],
        'banned': [],
      };

      if (res is List && res.length > 1 && res[0] == 0) {
        final resMap = res[1] as Map<String, dynamic>?;
        final stdout = resMap?['stdout']?.toString() ?? '';

        String currentSection = '';
        for (final line in stdout.split('\n')) {
          final trimmed = line.trim();
          if (trimmed == 'RESTRICTED:') {
            currentSection = 'restricted';
            continue;
          } else if (trimmed == 'BANNED:') {
            currentSection = 'banned';
            continue;
          }

          if (trimmed.isNotEmpty && trimmed.contains(':')) {
            final macUpper = trimmed.toUpperCase().replaceAll('-', ':');
            if (macUpper == '00:00:00:00:00:00' ||
                macUpper == 'FF:FF:FF:FF:FF:FF') {
              continue;
            }

            final entry = {
              'mac': macUpper,
              'name': macUpper,
              'ip': 'N/A',
              'type': currentSection,
              'source': currentSection == 'restricted'
                  ? 'Internet Access Paused'
                  : 'Wi-Fi Access Control (Banned)',
            };

            if (currentSection == 'restricted' &&
                !result['restricted']!.any((e) => e['mac'] == macUpper)) {
              result['restricted']!.add(entry);
            } else if (currentSection == 'banned' &&
                !result['banned']!.any((e) => e['mac'] == macUpper)) {
              result['banned']!.add(entry);
            }
          }
        }
      }

      return result;
    } catch (e, stack) {
      Logger.exception('fetchRestrictedAndBannedClientsLive failed', e, stack);
      return {'restricted': [], 'banned': []};
    }
  }

  static String? _sanitizeOpenWrtLeaseTime(String? lt) {
    if (lt == null) return null;
    final trimmed = lt.trim().toLowerCase();
    if (trimmed.isEmpty) return null;
    if (trimmed == 'infinite') return 'infinite';

    if (trimmed.endsWith('w')) {
      final weeks = int.tryParse(trimmed.substring(0, trimmed.length - 1));
      if (weeks != null && weeks > 0) return '${weeks * 7}d';
    }
    if (trimmed.endsWith('s')) {
      final secs = int.tryParse(trimmed.substring(0, trimmed.length - 1));
      if (secs != null && secs > 0) {
        final mins = (secs / 60).ceil();
        return '${mins < 2 ? 2 : mins}m';
      }
    }
    if (RegExp(r'^\d+[mhd]$').hasMatch(trimmed)) {
      return trimmed;
    }
    final plainNumber = int.tryParse(trimmed);
    if (plainNumber != null && plainNumber > 0) {
      final mins = (plainNumber / 60).ceil();
      return '${mins < 2 ? 2 : mins}m';
    }
    return '12h';
  }

  @override
  Future<bool> addStaticLease(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    required String targetIp,
    required String hostname,
    String? targetIp6,
    String? duid,
    String? leaseTime,
    BuildContext? context,
  }) async {
    try {
      final macUpper = macAddress.toUpperCase().replaceAll('-', ':');
      final cleanTargetIp = targetIp.trim();
      final sanitizedLt = _sanitizeOpenWrtLeaseTime(leaseTime);

      final values = <String, String>{'name': hostname.trim()};

      if (macUpper.isNotEmpty &&
          macUpper != 'N/A' &&
          !macUpper.startsWith('DUID:')) {
        values['mac'] = macUpper;
      }
      if (cleanTargetIp.isNotEmpty && cleanTargetIp != 'N/A') {
        values['ip'] = cleanTargetIp;
      }
      if (targetIp6 != null &&
          targetIp6.trim().isNotEmpty &&
          targetIp6.trim() != 'N/A') {
        values['ip6addr'] = targetIp6.trim();
      }
      if (duid != null && duid.trim().isNotEmpty && duid.trim() != 'N/A') {
        values['duid'] = duid.trim().toUpperCase();
      }
      if (sanitizedLt != null && sanitizedLt.isNotEmpty) {
        values['leasetime'] = sanitizedLt;
      }

      // 1. Find all existing host sections matching MAC or IP to prevent duplicate dhcp-host entries
      final matchingSections = <String>[];
      try {
        final getRes = await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'uci',
          method: 'get',
          params: {'config': 'dhcp'},
          context: mountedContext(context),
        );
        if (getRes is List && getRes.length > 1 && getRes[0] == 0) {
          final uciData = getRes[1];
          final valuesMap = (uciData is Map && uciData['values'] is Map)
              ? uciData['values'] as Map
              : (uciData is Map ? uciData : {});
          valuesMap.forEach((key, val) {
            if (val is Map && val['.type'] == 'host') {
              final macVal = val['mac'];
              final ipVal = val['ip']?.toString().trim();
              bool isMatch = false;

              if (ipVal == cleanTargetIp) {
                isMatch = true;
              } else if (macVal is String &&
                  macVal.toUpperCase().replaceAll('-', ':') == macUpper) {
                isMatch = true;
              } else if (macVal is List) {
                for (final item in macVal) {
                  if (item.toString().toUpperCase().replaceAll('-', ':') ==
                      macUpper) {
                    isMatch = true;
                    break;
                  }
                }
              }

              if (isMatch) {
                matchingSections.add(key.toString());
              }
            }
          });
        }
      } catch (e) {
        Logger.warning(
          'uci dhcp lookup encountered issue during addStaticLease: $e',
        );
      }

      bool addSuccess = false;

      // Delete any duplicate matching sections beyond the first one
      if (matchingSections.length > 1) {
        for (int i = 1; i < matchingSections.length; i++) {
          try {
            await callWithContext(
              ipAddress,
              sysauth,
              useHttps,
              object: 'uci',
              method: 'delete',
              params: {'config': 'dhcp', 'section': matchingSections[i]},
              context: mountedContext(context),
            );
          } catch (_) {}
        }
      }

      if (matchingSections.isNotEmpty) {
        // Update existing primary section in place
        final setRes = await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'uci',
          method: 'set',
          params: {
            'config': 'dhcp',
            'section': matchingSections.first,
            'values': values,
          },
          context: mountedContext(context),
        );
        addSuccess = setRes is List && setRes.isNotEmpty && setRes[0] == 0;
        if (addSuccess) {
          await uciCommit(
            ipAddress,
            sysauth,
            useHttps,
            config: 'dhcp',
            context: mountedContext(context),
          );
        }
      } else {
        // Create new host section via uci.add
        final addRes = await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'uci',
          method: 'add',
          params: {'config': 'dhcp', 'type': 'host', 'values': values},
          context: mountedContext(context),
        );
        addSuccess = addRes is List && addRes.isNotEmpty && addRes[0] == 0;
        if (addSuccess) {
          await uciCommit(
            ipAddress,
            sysauth,
            useHttps,
            config: 'dhcp',
            context: mountedContext(context),
          );
        }
      }

      if (!addSuccess) {
        // Fallback: Shell execution via /bin/sh - ensures duplicates are deleted and dnsmasq restarted
        final cmdList = [
          'for sec in \$(uci show dhcp 2>/dev/null | grep -iE "$macUpper|$cleanTargetIp" | cut -d. -f2 | sort -u); do uci delete dhcp.\$sec 2>/dev/null || true; done',
          'SECNAME=\$(uci add dhcp host)',
          'uci set dhcp.\$SECNAME.name="${hostname.trim()}"',
          'uci set dhcp.\$SECNAME.mac="$macUpper"',
          'uci set dhcp.\$SECNAME.ip="$cleanTargetIp"',
        ];
        if (sanitizedLt != null && sanitizedLt.isNotEmpty) {
          cmdList.add('uci set dhcp.\$SECNAME.leasetime="$sanitizedLt"');
        }
        cmdList.add('uci commit dhcp');

        final shellRes = await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'file',
          method: 'exec',
          params: {
            'command': '/bin/sh',
            'params': ['-c', cmdList.join(' && ')],
          },
          context: mountedContext(context),
        );
        addSuccess = _execSucceeded(shellRes);
      }

      // Restart dnsmasq service to ensure clean recovery & application of static lease
      await manageServiceAction(
        ipAddress,
        sysauth,
        useHttps,
        serviceName: 'dnsmasq',
        action: 'restart',
        context: mountedContext(context),
      );

      return addSuccess;
    } catch (e, stack) {
      Logger.exception('addStaticLease failed for $macAddress', e, stack);
      return false;
    }
  }

  @override
  Future<bool> deleteStaticLease(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    String? targetIp,
    String? hostname,
    String? duid,
    BuildContext? context,
  }) async {
    try {
      String normalizeMac(String mac) {
        final clean = mac.trim().toUpperCase().replaceAll('-', ':');
        final parts = clean.split(':');
        if (parts.length == 6) {
          return parts.map((b) => b.length == 1 ? '0$b' : b).join(':');
        }
        return clean;
      }

      final targetMacs = <String>{};
      if (macAddress.trim().isNotEmpty &&
          macAddress.trim() != 'N/A' &&
          !macAddress.startsWith('DUID:')) {
        final rawParts = macAddress.split(RegExp(r'[,;\s]+'));
        for (final p in rawParts) {
          final norm = normalizeMac(p);
          if (norm.isNotEmpty) targetMacs.add(norm);
        }
      }

      final cleanTargetIp = (targetIp != null &&
              targetIp.trim().isNotEmpty &&
              targetIp.trim() != 'N/A')
          ? targetIp.trim()
          : null;
      final cleanHostname = (hostname != null &&
              hostname.trim().isNotEmpty &&
              hostname.trim() != 'Unknown' &&
              hostname.trim() != '*' &&
              hostname.trim() != 'Unnamed Host')
          ? hostname.trim().toLowerCase()
          : null;
      final cleanDuid = (duid != null &&
              duid.trim().isNotEmpty &&
              duid.trim() != 'N/A')
          ? duid.trim().toUpperCase()
          : null;

      final sectionsToDelete = <String>[];

      // 1. Attempt to find all matching host sections via UCI ubus call
      try {
        final getRes = await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'uci',
          method: 'get',
          params: {'config': 'dhcp'},
          context: mountedContext(context),
        );

        if (getRes is List && getRes.length > 1 && getRes[0] == 0) {
          final uciData = getRes[1];
          final valuesMap = (uciData is Map && uciData['values'] is Map)
              ? uciData['values'] as Map
              : (uciData is Map ? uciData : {});
          valuesMap.forEach((key, val) {
            if (val is Map && val['.type'] == 'host') {
              bool isMatch = false;

              // Match by MAC
              final macVal = val['mac'];
              final sectionMacs = <String>{};
              if (macVal is String) {
                final parts = macVal.split(RegExp(r'[,;\s]+'));
                for (final p in parts) {
                  final n = normalizeMac(p);
                  if (n.isNotEmpty) sectionMacs.add(n);
                }
              } else if (macVal is List) {
                for (final item in macVal) {
                  final n = normalizeMac(item.toString());
                  if (n.isNotEmpty) sectionMacs.add(n);
                }
              }
              if (targetMacs.isNotEmpty &&
                  sectionMacs.any((sm) => targetMacs.contains(sm))) {
                isMatch = true;
              }

              // Match by IP
              if (!isMatch && cleanTargetIp != null) {
                final secIp = val['ip']?.toString().trim();
                if (secIp == cleanTargetIp) {
                  isMatch = true;
                }
              }

              // Match by DUID
              if (!isMatch && cleanDuid != null) {
                final secDuid = val['duid']?.toString().trim().toUpperCase();
                if (secDuid == cleanDuid) {
                  isMatch = true;
                }
              }

              // Match by Hostname/Name
              if (!isMatch && cleanHostname != null) {
                final secName = (val['name'] ?? val['hostname'])
                    ?.toString()
                    .trim()
                    .toLowerCase();
                if (secName == cleanHostname) {
                  isMatch = true;
                }
              }

              if (isMatch) {
                sectionsToDelete.add(key.toString());
              }
            }
          });
        }
      } catch (e) {
        Logger.warning(
          'ubus dhcp config lookup failed during deleteStaticLease: $e',
        );
      }

      bool deleteSuccess = false;

      if (sectionsToDelete.isNotEmpty) {
        for (final sec in sectionsToDelete) {
          final delRes = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'delete',
            params: {'config': 'dhcp', 'section': sec},
            context: mountedContext(context),
          );
          if (delRes is List && delRes.isNotEmpty && delRes[0] == 0) {
            deleteSuccess = true;
          }
        }
        if (deleteSuccess) {
          await uciCommit(
            ipAddress,
            sysauth,
            useHttps,
            config: 'dhcp',
            context: mountedContext(context),
          );
        }
      }

      // 2. Reload dnsmasq & odhcpd via native OpenWrt rc.init service manager (always works without /bin/sh ACL dependency)
      if (deleteSuccess) {
        await manageServiceAction(
          ipAddress,
          sysauth,
          useHttps,
          serviceName: 'dnsmasq',
          action: 'reload',
          context: mountedContext(context),
        );

        try {
          await manageServiceAction(
            ipAddress,
            sysauth,
            useHttps,
            serviceName: 'odhcpd',
            action: 'reload',
            context: mountedContext(context),
          );
        } catch (_) {}

        // SIGHUP to dnsmasq via /bin/kill (whitelisted in standard ACLs) to instantly clear lease tables
        try {
          final procRes = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'luci',
            method: 'getProcessList',
            params: {},
            context: mountedContext(context),
          );
          if (procRes is Map && procRes['result'] is List) {
            final pList = procRes['result'] as List;
            for (final proc in pList) {
              if (proc is Map) {
                final cmd = (proc['COMMAND'] ?? '').toString();
                final pid = (proc['PID'] ?? '').toString();
                if (pid.isNotEmpty && cmd.contains('dnsmasq')) {
                  try {
                    await callWithContext(
                      ipAddress,
                      sysauth,
                      useHttps,
                      object: 'file',
                      method: 'exec',
                      params: fileExecParams('/bin/kill', ['-1', pid]),
                      context: mountedContext(context),
                    );
                  } catch (_) {}
                }
              }
            }
          }
        } catch (_) {}
      }

      return deleteSuccess;
    } catch (e, stack) {
      Logger.exception('deleteStaticLease failed for $macAddress', e, stack);
      return false;
    }
  }

  @override
  Future<bool> refreshClientConnection(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    BuildContext? context,
  }) async {
    try {
      final macUpper = macAddress.toUpperCase().replaceAll('-', ':');
      final macLower = macAddress.toLowerCase().replaceAll('-', ':');

      final script =
          '''
MAC_U="$macUpper"
MAC_L="$macLower"

# 1. Delete active DHCP lease records from all lease files
for f in /tmp/dhcp.leases /var/dhcp.leases /tmp/dnsmasq.leases; do
  if [ -f "\$f" ]; then
    sed -i "/\${MAC_U}/d; /\${MAC_L}/d" "\$f" 2>/dev/null || true
  fi
done

# 2. Reload dnsmasq so UCI static lease is immediately effective
/etc/init.d/dnsmasq reload 2>/dev/null || true

# 3. Send deauth with 3.5s ban window to force client OS to reset Wi-Fi link state
#    and perform a fresh DHCP DISCOVER upon auto-reconnecting.
DEAUTHED=0
for obj in \$(ubus list 'hostapd.*' 2>/dev/null); do
  if ubus call "\$obj" get_clients 2>/dev/null | grep -qi "\${MAC_L}"; then
    ubus call "\$obj" del_client "{\\"addr\\":\\"\${MAC_L}\\",\\"reason\\":5,\\"deauth\\":true,\\"ban_time\\":3500}" 2>/dev/null && DEAUTHED=1 || true
  fi
done

# 4. Fallback if client wasn't listed in hostapd get_clients
if [ "\$DEAUTHED" = "0" ]; then
  for obj in \$(ubus list 'hostapd.*' 2>/dev/null); do
    ubus call "\$obj" del_client "{\\"addr\\":\\"\${MAC_L}\\",\\"reason\\":5,\\"deauth\\":true,\\"ban_time\\":3500}" 2>/dev/null || true
  done
  for dev in \$(iw dev 2>/dev/null | awk '\$1=="Interface"{print \$2}'); do
    iw dev "\$dev" station del "\${MAC_L}" 2>/dev/null || true
  done
fi

exit 0
''';

      await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: fileExecParams('/bin/sh', ['-c', script]),
        context: mountedContext(context),
      );

      return true;
    } catch (e, stack) {
      Logger.exception(
        'refreshClientConnection failed for $macAddress',
        e,
        stack,
      );
      return false;
    }
  }

  @override
  Future<int> deleteUnusedDhcpLeases(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required List<String> macsToFlush,
    BuildContext? context,
  }) async {
    if (macsToFlush.isEmpty) return 0;
    try {
      // 1. Fetch running processes to find PIDs of dnsmasq and odhcpd
      try {
        final procRes = await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'luci',
          method: 'getProcessList',
          params: {},
          context: mountedContext(context),
        );
        if (procRes is Map && procRes['result'] is List) {
          final pList = procRes['result'] as List;
          for (final proc in pList) {
            if (proc is Map) {
              final cmd = (proc['COMMAND'] ?? '').toString();
              final pid = (proc['PID'] ?? '').toString();
              if (pid.isNotEmpty &&
                  (cmd.contains('dnsmasq') || cmd.contains('odhcpd'))) {
                try {
                  // Send SIGHUP (-1) via /bin/kill which is allowed by ubus ACLs
                  await callWithContext(
                    ipAddress,
                    sysauth,
                    useHttps,
                    object: 'file',
                    method: 'exec',
                    params: fileExecParams('/bin/kill', ['-1', pid]),
                    context: mountedContext(context),
                  );
                } catch (_) {}
              }
            }
          }
        }
      } catch (_) {}

      // 2. Commit uci dhcp configuration to sync OpenWrt DHCP subsystem
      try {
        await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'uci',
          method: 'commit',
          params: {'config': 'dhcp'},
          context: mountedContext(context),
        );
      } catch (_) {}

      // 3. Fallback: attempt /bin/sh shell script if router allows full shell exec
      try {
        final macUpper = macsToFlush
            .map((m) => m.toUpperCase().replaceAll('-', ':'))
            .join('|');
        final macLower = macsToFlush
            .map((m) => m.toLowerCase().replaceAll('-', ':'))
            .join('|');
        final macPattern = '$macUpper|$macLower';
        final script =
            '''
for f in /tmp/dhcp.leases /var/dhcp.leases /tmp/dnsmasq.leases /var/run/odhcpd.leases /tmp/odhcpd.leases /tmp/hosts/odhcpd; do
  if [ -f "\$f" ]; then
    grep -vE "$macPattern" "\$f" > "\$f.tmp" 2>/dev/null && mv "\$f.tmp" "\$f" 2>/dev/null || true
  fi
done
exit 0
''';
        await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'file',
          method: 'exec',
          params: fileExecParams('/bin/sh', ['-c', script]),
          context: mountedContext(context),
        );
      } catch (_) {}

      return macsToFlush.length;
    } catch (e, stack) {
      Logger.exception('deleteUnusedDhcpLeases failed', e, stack);
      return 0;
    }
  }

  @override
  Future<Map<String, String?>> fetchPublicIps(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    String? publicV4;
    String? publicV6;

    // 1. Attempt router-side URL fetch via /bin/sh exec (handles CGNAT from router WAN context)
    try {
      final cmd =
          'V4=\$(wget -q -O - http://api.ipify.org 2>/dev/null || wget -q -O - http://checkip.amazonaws.com 2>/dev/null || curl -s -m 3 http://api.ipify.org 2>/dev/null || uclient-fetch -q -O - http://api.ipify.org 2>/dev/null); '
          'V6=\$(wget -q -O - http://api6.ipify.org 2>/dev/null || wget -q -O - http://v6.ipv6-test.com/api/myip.php 2>/dev/null || curl -s -6 -m 3 http://api6.ipify.org 2>/dev/null || uclient-fetch -q -O - http://api6.ipify.org 2>/dev/null); '
          'echo "V4:\$V4"; echo "V6:\$V6"';

      final shellRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': '/bin/sh',
          'params': ['-c', cmd],
        },
        context: mountedContext(context),
      );

      if (shellRes is List && shellRes.length > 1 && shellRes[0] == 0) {
        final stdout = shellRes[1]['stdout']?.toString() ?? '';
        for (final line in stdout.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.startsWith('V4:')) {
            final candidate = trimmed.substring(3).trim();
            if (candidate.isNotEmpty && _isValidIpv4Candidate(candidate)) {
              publicV4 = candidate;
            }
          } else if (trimmed.startsWith('V6:')) {
            final candidate = trimmed.substring(3).trim();
            if (candidate.isNotEmpty && candidate.contains(':')) {
              publicV6 = candidate;
            }
          }
        }
      }
    } catch (e) {
      Logger.warning('Router-side public IP resolution failed: $e');
    }

    // 2. Client-side HTTP fallback if router execution returned null
    if (publicV4 == null) {
      try {
        final res = await http
            .get(Uri.parse('http://api.ipify.org'))
            .timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          final body = res.body.trim();
          if (_isValidIpv4Candidate(body)) {
            publicV4 = body;
          }
        }
      } catch (e) {
        Logger.debug('Client-side IPv4 lookup failed: $e');
      }
    }

    if (publicV6 == null) {
      try {
        final res = await http
            .get(Uri.parse('http://api6.ipify.org'))
            .timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          final body = res.body.trim();
          if (body.contains(':')) {
            publicV6 = body;
          }
        }
      } catch (e) {
        Logger.debug('Client-side IPv6 lookup failed: $e');
      }
    }

    return {'ipv4': publicV4, 'ipv6': publicV6};
  }

  static bool _isValidIpv4Candidate(String ip) {
    final reg = RegExp(
      r'^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.){3}(25[0-5]|(2[0-4]|1\d|[1-9]|)\d)$',
    );
    return reg.hasMatch(ip);
  }

  @override
  Future<bool> forceRefreshDhcpLeases(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    try {
      // 1. Resolve lease file location from UCI dhcp config
      String leasePath = '/tmp/dhcp.leases';
      try {
        final uciRes = await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'uci',
          method: 'get',
          params: {'config': 'dhcp'},
          context: mountedContext(context),
        );
        if (execSucceeded(uciRes) &&
            uciRes is List &&
            uciRes.length > 1 &&
            uciRes[1] is Map) {
          final values = uciRes[1]['values'] ?? uciRes[1];
          if (values is Map) {
            values.forEach((k, v) {
              if (v is Map &&
                  (v['.type'] == 'dnsmasq' ||
                      k.toString().contains('dnsmasq'))) {
                if (v['leasefile'] != null &&
                    v['leasefile'].toString().isNotEmpty) {
                  leasePath = v['leasefile'].toString();
                }
              }
            });
          }
        }
      } catch (_) {}

      bool executedAny = false;

      // 2. Stop dnsmasq and odhcpd via rc.init
      try {
        final stopDns = await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'rc',
          method: 'init',
          params: {'name': 'dnsmasq', 'action': 'stop'},
          context: mountedContext(context),
        );
        if (execSucceeded(stopDns)) executedAny = true;
      } catch (_) {}

      try {
        await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'rc',
          method: 'init',
          params: {'name': 'odhcpd', 'action': 'stop'},
          context: mountedContext(context),
        );
      } catch (_) {}

      // 3. Send SIGHUP (-1) and SIGTERM (-15) via /bin/kill (allowed by rpcd ACLs) to dnsmasq and odhcpd
      try {
        final procRes = await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'luci',
          method: 'getProcessList',
          params: {},
          context: mountedContext(context),
        );
        if (procRes is Map && procRes['result'] is List) {
          final pList = procRes['result'] as List;
          for (final proc in pList) {
            if (proc is Map) {
              final cmd = (proc['COMMAND'] ?? '').toString();
              final pid = (proc['PID'] ?? '').toString();
              if (pid.isNotEmpty &&
                  (cmd.contains('dnsmasq') || cmd.contains('odhcpd'))) {
                try {
                  await callWithContext(
                    ipAddress,
                    sysauth,
                    useHttps,
                    object: 'file',
                    method: 'exec',
                    params: fileExecParams('/bin/kill', ['-1', pid]),
                    context: mountedContext(context),
                  );
                  executedAny = true;
                } catch (_) {}
              }
            }
          }
        }
      } catch (_) {}

      // 4. Shell purge fallback script if shell exec is permitted
      final purgeScript =
          '''
rm -f "$leasePath" /tmp/dhcp.leases /var/dhcp.leases /tmp/dnsmasq.leases /var/lib/misc/dnsmasq.leases /var/run/odhcpd.leases 2>/dev/null || > "$leasePath" 2>/dev/null || true
''';
      try {
        final shRes = await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'file',
          method: 'exec',
          params: fileExecParams('/bin/sh', ['-c', purgeScript]),
          context: mountedContext(context),
        );
        if (execSucceeded(shRes)) executedAny = true;
      } catch (_) {}

      // 5. Commit UCI dhcp configuration
      try {
        await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'uci',
          method: 'commit',
          params: {'config': 'dhcp'},
          context: mountedContext(context),
        );
        executedAny = true;
      } catch (_) {}

      // 6. Restart/Start dnsmasq and odhcpd via rc.init & luci-rpc
      try {
        final startDns = await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'rc',
          method: 'init',
          params: {'name': 'dnsmasq', 'action': 'restart'},
          context: mountedContext(context),
        );
        if (execSucceeded(startDns)) executedAny = true;
      } catch (_) {}

      try {
        await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'rc',
          method: 'init',
          params: {'name': 'odhcpd', 'action': 'restart'},
          context: mountedContext(context),
        );
      } catch (_) {}

      try {
        await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'luci-rpc',
          method: 'setInitAction',
          params: {'name': 'dnsmasq', 'action': 'restart'},
          context: mountedContext(context),
        );
      } catch (_) {}

      return executedAny;
    } catch (e, stack) {
      Logger.exception('forceRefreshDhcpLeases failed', e, stack);
      return false;
    }
  }

  @override
  Future<bool> saveCronJobs(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required List<String> cronLines,
    BuildContext? context,
  }) async {
    try {
      final sanitizedLines = cronLines
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      final content = sanitizedLines.isEmpty
          ? ''
          : '${sanitizedLines.join('\n')}\n';

      // 1. Write the crontab file to /etc/crontabs/root
      final writeRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'write',
        params: {'path': '/etc/crontabs/root', 'data': content},
        context: mountedContext(context),
      );

      final success = execSucceeded(writeRes);

      if (success) {
        // 2. Restart the cron daemon service so changes take effect immediately
        try {
          await manageServiceAction(
            ipAddress,
            sysauth,
            useHttps,
            serviceName: 'cron',
            action: 'restart',
            context: mountedContext(context),
          );
        } catch (_) {}
      }

      return success;
    } catch (e, stack) {
      Logger.exception('saveCronJobs failed', e, stack);
      return false;
    }
  }

  @override
  Future<bool> saveDdnsInstance(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required DdnsInstance instance,
    BuildContext? context,
  }) async {
    try {
      final setRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'set',
        params: {
          'config': 'ddns',
          'section': instance.name,
          'type': 'service',
          'values': instance.toUciParams(),
        },
        context: mountedContext(context),
      );

      if (!execSucceeded(setRes)) return false;

      await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'commit',
        params: {'config': 'ddns'},
        context: mountedContext(context),
      );

      try {
        await manageServiceAction(
          ipAddress,
          sysauth,
          useHttps,
          serviceName: 'ddns',
          action: 'reload',
          context: mountedContext(context),
        );
      } catch (_) {}

      return true;
    } catch (e, stack) {
      Logger.exception('saveDdnsInstance failed', e, stack);
      return false;
    }
  }

  @override
  Future<bool> deleteDdnsInstance(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String instanceName,
    BuildContext? context,
  }) async {
    try {
      final delRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'delete',
        params: {'config': 'ddns', 'section': instanceName},
        context: mountedContext(context),
      );

      if (!execSucceeded(delRes)) return false;

      await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'commit',
        params: {'config': 'ddns'},
        context: mountedContext(context),
      );

      try {
        await manageServiceAction(
          ipAddress,
          sysauth,
          useHttps,
          serviceName: 'ddns',
          action: 'reload',
          context: mountedContext(context),
        );
      } catch (_) {}

      return true;
    } catch (e, stack) {
      Logger.exception('deleteDdnsInstance failed', e, stack);
      return false;
    }
  }

  @override
  Future<DdnsValidationResult> testDdnsConfiguration(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required DdnsInstance instance,
    BuildContext? context,
  }) async {
    try {
      if (instance.lookupHost.isEmpty && instance.domain.isEmpty) {
        return DdnsValidationResult.failure(
          'Lookup Hostname / Domain cannot be empty.',
        );
      }

      final hostToTest = instance.lookupHost.isNotEmpty
          ? instance.lookupHost
          : instance.domain;

      final rpcRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': 'nslookup',
          'params': [hostToTest],
        },
        context: mountedContext(context),
      );

      final stdout = rpcRes is Map ? rpcRes['stdout']?.toString() ?? '' : '';
      final stderr = rpcRes is Map ? rpcRes['stderr']?.toString() ?? '' : '';
      final combined = '$stdout\n$stderr'.trim();

      if (combined.contains('Address:') || combined.contains('Name:')) {
        return DdnsValidationResult.success(
          testOutput: 'DNS Lookup Successful:\n$combined',
        );
      } else if (combined.contains("can't find") ||
          combined.contains('NXDOMAIN') ||
          combined.contains('ServFail')) {
        return DdnsValidationResult.failure(
          'Hostname DNS lookup failed ($hostToTest). Ensure domain exists or is registered.',
          testOutput: combined,
        );
      }

      return DdnsValidationResult.success(
        testOutput: 'Configuration passed basic validation checks.\n$combined',
      );
    } catch (e) {
      return DdnsValidationResult.failure(
        'Validation test execution error: $e',
      );
    }
  }

  @override
  Future<bool> toggleGlobalDdns(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required bool enable,
    BuildContext? context,
  }) async {
    try {
      await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'set',
        params: {
          'config': 'ddns',
          'section': 'global',
          'type': 'global',
          'values': {'is_enabled': enable ? '1' : '0'},
        },
        context: mountedContext(context),
      );

      await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'commit',
        params: {'config': 'ddns'},
        context: mountedContext(context),
      );

      await manageServiceAction(
        ipAddress,
        sysauth,
        useHttps,
        serviceName: 'ddns',
        action: enable ? 'start' : 'stop',
        context: mountedContext(context),
      );

      return true;
    } catch (e, stack) {
      Logger.exception('toggleGlobalDdns failed', e, stack);
      return false;
    }
  }
}
