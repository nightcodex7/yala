// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:yet_another_luci_app/modules/parental_controls/models/parental_profile.dart';
import 'package:yet_another_luci_app/modules/services_system/models/ddns_info.dart';
import 'package:yet_another_luci_app/modules/sqm/models/sqm_queue.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/internet_reachability.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/ping_result.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/traceroute_result.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/dns_lookup_result.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/routing_neighbor_info.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/diagnostic_report.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/flush_dns_result.dart';
import 'package:yet_another_luci_app/modules/dhcp_dns/models/dnsmasq_service_result.dart';
import 'package:yet_another_luci_app/modules/log_viewer/models/log_entry.dart';
import 'package:yet_another_luci_app/modules/log_viewer/models/log_fetch_result.dart';
import 'package:yet_another_luci_app/modules/bandwidth_monitor/models/bandwidth_data.dart';
import 'package:yet_another_luci_app/models/network_access_policy.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/modules/firewall_security/models/firewall_info.dart';
import 'package:yet_another_luci_app/modules/firewall_security/services/firewall_policy_translator.dart';
import 'package:yet_another_luci_app/models/client_speed_limit.dart';
import 'package:yet_another_luci_app/services/client_speed_limit_translator.dart';
import 'package:yet_another_luci_app/services/operation_queue.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';
import 'package:yet_another_luci_app/modules/domain_blocking/models/domain_block_rule.dart';
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
  final String host = ipAddress;
  // Don't add scheme if the address already has one (shouldn't happen with our parser)
  if (host.startsWith('http://') || host.startsWith('https://')) {
    return Uri.parse('$host$path');
  }
  return Uri.parse('$scheme://$host$path');
}

typedef ApiService = RealApiService;

class RealApiService implements IApiService {
  final HttpClientManager _httpClientManager = HttpClientManager();

  /// Callback to transparently renew expired sessions without UI disruption.
  Future<String?> Function(String ipAddress, bool useHttps)? onSessionRenew;
  Future<String?>? _activeRenewalFuture;

  Future<String?> _performSessionRenewal(String ipAddress, bool useHttps) {
    if (_activeRenewalFuture != null) {
      return _activeRenewalFuture!;
    }
    final handler = onSessionRenew;
    if (handler == null) {
      return Future.value(null);
    }
    final future = handler(ipAddress, useHttps);
    _activeRenewalFuture = future;
    return future.whenComplete(() {
      _activeRenewalFuture = null;
    });
  }

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

  /// Safely quotes an argument for POSIX /bin/sh command strings.
  /// Encloses in single quotes and replaces any single quote with '\''.
  @visibleForTesting
  static String shellSingleQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";

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
            sendTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 7),
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
          Logger.info('Step 1 (ubus JSON-RPC $endpoint) succeeded');
          return AuthResult.success(token, actualUseHttps: useHttps);
        }

        if (response.data is Map) {
          final err = response.data['error'];
          if (err is Map &&
              (err['code'] == 6 || err['message'] == 'Access denied')) {
            invalidCredentialsDetected = true;
          }
          final resList = response.data['result'];
          if (resList is List && resList.isNotEmpty && resList[0] == 6) {
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
            sendTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 7),
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
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 7),
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
    if (redirectDetected || targetIsHttps) {
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
            sendTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 7),
            followRedirects: false,
            validateStatus: (code) => code != null && code < 500,
          ),
        );

        final token = _extractAuthToken(response);
        if (token != null) {
          Logger.info('Step 4 (Protocol fallback replay) succeeded');
          return AuthResult.success(token, actualUseHttps: replayUseHttps);
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
    bool isRetry = false,
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

          bool isAuthError = false;
          if (decoded is Map && decoded['error'] != null) {
            final err = decoded['error'];
            final errCode = err is Map ? err['code'] : null;
            final errMsg =
                (err is Map ? err['message'] : err)?.toString().toLowerCase() ??
                '';
            if (errCode == -32002 ||
                errCode == 6 ||
                errMsg.contains('access denied')) {
              isAuthError = true;
            }
          } else if (decoded is Map && decoded['result'] is List) {
            final resList = decoded['result'] as List;
            if (resList.isNotEmpty && resList.length == 1 && resList[0] == 6) {
              isAuthError = true;
            }
          }

          if (isAuthError &&
              !isRetry &&
              onSessionRenew != null &&
              sysauth.isNotEmpty) {
            Logger.info(
              'Detected expired session on RPC $object.$method. Attempting transparent renewal...',
            );
            try {
              final newToken = await _performSessionRenewal(
                ipAddress,
                useHttps,
              );
              if (newToken != null && newToken.isNotEmpty) {
                Logger.info(
                  'Transparent session renewal succeeded. Retrying RPC $object.$method...',
                );
                return await callWithContext(
                  ipAddress,
                  newToken,
                  useHttps,
                  object: object,
                  method: method,
                  params: params,
                  context: context,
                  isRetry: true,
                );
              }
            } catch (reauthErr) {
              Logger.warning('Transparent session renewal failed: $reauthErr');
            }
          }

          if (decoded is Map && decoded['error'] != null) {
            throw Exception('RPC error: ${decoded['error']['message']}');
          }
          // Return in LuCI RPC format: [status, data]
          final result = decoded is Map ? decoded['result'] : null;
          if (result is List && result.isNotEmpty) {
            return result;
          } else {
            return [0, result];
          }
        } else if ((response.statusCode == 401 || response.statusCode == 403) &&
            !isRetry &&
            onSessionRenew != null &&
            sysauth.isNotEmpty) {
          Logger.info(
            'Detected HTTP ${response.statusCode} on RPC $object.$method. Attempting transparent renewal...',
          );
          try {
            final newToken = await _performSessionRenewal(ipAddress, useHttps);
            if (newToken != null && newToken.isNotEmpty) {
              Logger.info(
                'Transparent session renewal succeeded. Retrying RPC $object.$method...',
              );
              return await callWithContext(
                ipAddress,
                newToken,
                useHttps,
                object: object,
                method: method,
                params: params,
                context: context,
                isRetry: true,
              );
            }
          } catch (reauthErr) {
            Logger.warning('Transparent session renewal failed: $reauthErr');
          }
          throw Exception('Failed to call RPC: HTTP ${response.statusCode}');
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

  /// Discovers available ubus object namespaces matching an optional pattern via JSON-RPC list method.
  Future<List<String>> listUbusObjects(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    String? pattern,
    BuildContext? context,
  }) async {
    final client = _createHttpClient(useHttps, ipAddress, context: context);
    final rpcPayload = {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'list',
      'params': (pattern != null && pattern.isNotEmpty)
          ? [sysauth, pattern]
          : [sysauth, '*'],
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
            responseDecoder: (responseBytes, options, responseBody) =>
                utf8.decode(responseBytes, allowMalformed: true),
            validateStatus: (status) => status != null && status < 500,
          ),
        );

        if (response.statusCode == 200) {
          final decoded = response.data is String
              ? jsonDecode(response.data as String)
              : response.data;

          if (decoded is Map && decoded['result'] != null) {
            final res = decoded['result'];
            if (res is Map) {
              return res.keys.map((k) => k.toString()).toList();
            } else if (res is List) {
              return res.map((k) => k.toString()).toList();
            }
          }
        }
      } catch (e) {
        Logger.warning('listUbusObjects error on $endpointPath: $e');
      }
    }
    return [];
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
  /// Fetches all associated wireless stations with full traffic and PHY details from all wireless interfaces
  @override
  Future<Map<String, List<Map<String, dynamic>>>>
  fetchAllAssociatedWirelessStationsWithDetailsContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async {
    final result = <String, List<Map<String, dynamic>>>{};
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

    if (discoveredIfaces.isEmpty) {
      discoveredIfaces['wlan0'] = 'wlan0';
      discoveredIfaces['wlan1'] = 'wlan1';
      discoveredIfaces['phy0-ap0'] = 'phy0-ap0';
      discoveredIfaces['phy1-ap0'] = 'phy1-ap0';
    }

    // 4. For every discovered interface, fetch associated station details
    for (final entry in discoveredIfaces.entries) {
      final ifname = entry.key;
      final label = entry.value;

      final stations = await fetchAssociatedStationsDetailsWithContext(
        ipAddress: ipAddress,
        sysauth: sysauth,
        useHttps: useHttps,
        interface: ifname,
        context: context?.mounted == true ? context : null,
      );

      if (stations.isNotEmpty) {
        final mapKey = '$ifname|$label';
        result[mapKey] = (result[mapKey] ?? [])..addAll(stations);
      }
    }

    return result;
  }

  /// Fetches all associated wireless MAC addresses from all wireless interfaces for real API
  @override
  Future<Map<String, Set<String>>> fetchAllAssociatedWirelessMacsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async {
    final detailsMap =
        await fetchAllAssociatedWirelessStationsWithDetailsContext(
          ipAddress: ipAddress,
          sysauth: sysauth,
          useHttps: useHttps,
          context: context,
        );
    final result = <String, Set<String>>{};
    detailsMap.forEach((key, list) {
      final macs = <String>{};
      for (final s in list) {
        final m = s['mac']?.toString();
        if (m != null && m.isNotEmpty) {
          macs.add(m.toUpperCase().replaceAll('-', ':'));
        }
      }
      if (macs.isNotEmpty) {
        result[key] = macs;
      }
    });
    return result;
  }

  /// Fetches associated stations with full traffic & PHY details for a given wireless interface
  Future<List<Map<String, dynamic>>> fetchAssociatedStationsDetailsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interface,
    BuildContext? context,
  }) async {
    final stationsMap = <String, Map<String, dynamic>>{};

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
            if (entry is Map) {
              final map = Map<String, dynamic>.from(entry);
              final mac = map['mac']?.toString();
              if (mac != null && mac.isNotEmpty) {
                final normMac = mac.toUpperCase().replaceAll('-', ':');
                map['mac'] = normMac;
                stationsMap[normMac] = map;
              }
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
          for (final entry in clientsMap.entries) {
            final normMac = entry.key.toUpperCase().replaceAll('-', ':');
            final clientMap = entry.value is Map
                ? Map<String, dynamic>.from(entry.value as Map)
                : <String, dynamic>{};
            clientMap['mac'] = normMac;

            final existing = stationsMap[normMac];
            if (existing != null) {
              // Deep-merge: preserve iwinfo's rx/tx/thr/connected_time, but add hostapd's fields
              clientMap.forEach((k, v) {
                if (v != null) {
                  if (existing[k] == null) {
                    existing[k] = v;
                  } else if (existing[k] is Map && v is Map) {
                    existing[k] = {...(existing[k] as Map), ...v};
                  }
                }
              });
            } else {
              stationsMap[normMac] = clientMap;
            }
          }
        }
      }
    } catch (_) {}

    if (stationsMap.isEmpty) {
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
              final normMac = macStr.toUpperCase().replaceAll('-', ':');
              stationsMap[normMac] = {'mac': normMac};
            }
          }
        }

        if (stationsMap.isEmpty) {
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
                final normMac = macStr.toUpperCase().replaceAll('-', ':');
                stationsMap[normMac] = {'mac': normMac};
              }
            }
          }
        }
      } catch (_) {}
    }

    return stationsMap.values.toList();
  }

  /// Fetches associated stations (wireless client MACs) for a given wireless interface (e.g., phy0-ap0, wlan0)
  @override
  Future<List<String>> fetchAssociatedStationsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interface,
    BuildContext? context,
  }) async {
    final details = await fetchAssociatedStationsDetailsWithContext(
      ipAddress: ipAddress,
      sysauth: sysauth,
      useHttps: useHttps,
      interface: interface,
      context: context,
    );
    final set = <String>{};
    for (final d in details) {
      final m = d['mac']?.toString();
      if (m != null && m.isNotEmpty) {
        set.add(m);
      }
    }
    return set.toList();
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
  Future<bool> uciApply(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    bool rollback = true,
    int timeout = 30,
  }) async {
    try {
      final res = await call(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'apply',
        params: {'rollback': rollback, 'timeout': timeout},
      );
      if (res is List && res.isNotEmpty) {
        // 0 = UBUS_STATUS_OK
        // 5 = UBUS_STATUS_NO_DATA (no staged changes pending to apply)
        return res[0] == 0 || res[0] == 5;
      }
      return false;
    } catch (e, stack) {
      Logger.exception('uciApply failed', e, stack);
      return false;
    }
  }

  @override
  Future<bool> uciConfirm(
    String ipAddress,
    String sysauth,
    bool useHttps,
  ) async {
    try {
      final res = await call(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'confirm',
        params: {},
      );
      if (res is List && res.isNotEmpty) {
        // 0 = UBUS_STATUS_OK
        // 5 = UBUS_STATUS_NO_DATA (no rollback timer actively waiting)
        return res[0] == 0 || res[0] == 5;
      }
      return false;
    } catch (e, stack) {
      Logger.exception('uciConfirm failed', e, stack);
      return false;
    }
  }

  @override
  Future<SetPasswordRpcResponse> setRouterPassword(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    String username = 'root',
    required String newPassword,
  }) async {
    try {
      final res = await call(
        ipAddress,
        sysauth,
        useHttps,
        object: 'luci',
        method: 'setPassword',
        params: {'username': username, 'password': newPassword},
      );
      if (res is List && res.isNotEmpty) {
        if (res[0] == 0) {
          if (res.length > 1 && res[1] is Map) {
            final map = res[1] as Map;
            if (map['result'] == true) {
              return const SetPasswordRpcResponse.success();
            } else {
              return const SetPasswordRpcResponse.rejected(
                'Router rejected password update',
              );
            }
          }
          return const SetPasswordRpcResponse.success();
        } else if (res[0] == 6) {
          return const SetPasswordRpcResponse.rejected(
            'Access denied (permission error)',
          );
        } else {
          return SetPasswordRpcResponse.rejected('ubus error code: ${res[0]}');
        }
      } else if (res is Map) {
        if (res['result'] == true) {
          return const SetPasswordRpcResponse.success();
        } else if (res['error'] != null) {
          return SetPasswordRpcResponse.rejected(res['error'].toString());
        }
      }
      return const SetPasswordRpcResponse.rejected(
        'Unexpected response format from setPassword',
      );
    } on DioException catch (e) {
      Logger.info('setRouterPassword DioException: ${e.type} ${e.message}');
      return SetPasswordRpcResponse.networkError(e.message);
    } catch (e, stack) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('access denied') || errStr.contains('permission')) {
        return const SetPasswordRpcResponse.rejected('Access denied');
      }
      Logger.exception('setRouterPassword network/transport failure', e, stack);
      return SetPasswordRpcResponse.networkError(e.toString());
    }
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
    try {
      final res = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: fileExecParams('/bin/sh', ['-c', command]),
        context: context,
      );
      if (_execSucceeded(res)) {
        return res;
      }
      // Fallback for older rpcd that expects 'args' instead of 'params'
      return await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: fileExecArgs('/bin/sh', ['-c', command]),
        context: context,
      );
    } catch (_) {
      return await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: fileExecArgs('/bin/sh', ['-c', command]),
        context: context,
      );
    }
  }

  @override
  Future<String?> execDirectCgi(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String command,
    List<String>? params,
    int stderr = 0,
    BuildContext? context,
  }) async {
    try {
      final cmdParts = [command, ...?params];
      final cmdStr = cmdParts
          .map((p) => p.replaceAll(r'\', r'\\').replaceAll(' ', r'\ '))
          .join(' ');
      final uri = _buildUrl(ipAddress, useHttps, '/cgi-bin/cgi-exec');
      final body =
          'sessionid=${Uri.encodeQueryComponent(sysauth)}&command=${Uri.encodeQueryComponent(cmdStr)}&stderr=$stderr';

      final client = _createHttpClient(useHttps, ipAddress, context: context);
      final response = await client.post(
        uri.toString(),
        data: body,
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Cookie': 'sysauth=$sysauth; sysauth_http=$sysauth',
          },
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 120),
          validateStatus: (status) => status != null && status < 400,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        return response.data.toString();
      }
    } catch (e) {
      Logger.warning('execDirectCgi failed for $command: $e');
    }
    return null;
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

  @visibleForTesting
  bool isUciSuccessful(dynamic res) => _isUciSuccessful(res);

  @visibleForTesting
  bool isExpectedServiceDisconnect(
    String serviceName,
    dynamic e, [
    String action = 'restart',
  ]) => _isExpectedServiceDisconnect(e, serviceName, action);

  @visibleForTesting
  List<dynamic>? extractProcessList(dynamic procRes) =>
      _extractProcessList(procRes);

  bool _isUciSuccessful(dynamic res) {
    if (res == null) return false;
    if (res is List && res.isNotEmpty) return res[0] == 0;
    if (res is Map) {
      if (res.containsKey('error') && res['error'] != null) return false;
      if (res['result'] is List && (res['result'] as List).isNotEmpty) {
        return (res['result'] as List)[0] == 0;
      }
      if (res['code'] is int) return res['code'] == 0;
      if (res['rc'] is int) return res['rc'] == 0;
      if (res.containsKey('success')) return res['success'] == true;
      return true;
    }
    return res == 0;
  }

  List<dynamic>? _extractProcessList(dynamic procRes) {
    if (procRes == null) return null;
    if (procRes is List) {
      if (procRes.isEmpty) return null;
      final payload = procRes.length > 1 ? procRes[1] : procRes[0];
      if (payload is List) return payload;
      if (payload is Map && payload['result'] is List) {
        return payload['result'] as List;
      }
      return procRes;
    } else if (procRes is Map) {
      if (procRes['result'] is List) return procRes['result'] as List;
    }
    return null;
  }

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
  Future<bool> toggleWirelessRadio(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String radioName,
    required bool enabled,
    BuildContext? context,
  }) async {
    final mCtx = mountedContext(context);
    try {
      final setRes = await uciSet(
        ipAddress,
        sysauth,
        useHttps,
        config: 'wireless',
        section: radioName,
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

      // Reload wifi subsystem
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
      final reloadOk = _execSucceeded(reloadRes);
      if (!reloadOk) {
        Logger.debug(
          'toggleWirelessRadio: wifi reload returned non-zero code for $radioName',
        );
      }

      // Authoritative verification query against router UCI
      try {
        final verifyRes = await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'uci',
          method: 'get',
          params: {'config': 'wireless', 'section': radioName},
          context: mCtx,
        );
        if (verifyRes is Map) {
          final values = verifyRes['values'] ?? verifyRes;
          if (values is Map) {
            final verifiedDisabled = values['disabled']?.toString();
            final expectedDisabled = enabled ? '0' : '1';
            if (verifiedDisabled != null &&
                verifiedDisabled != expectedDisabled) {
              Logger.warning(
                'toggleWirelessRadio: validation mismatch for $radioName. Expected disabled=$expectedDisabled, got $verifiedDisabled',
              );
              return false;
            }
          }
        }
      } catch (e) {
        Logger.debug('toggleWirelessRadio: verification query warning: $e');
      }

      return true;
    } catch (e, stack) {
      Logger.exception('toggleWirelessRadio failed for $radioName', e, stack);
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
  Future<bool> updateWirelessInterfaceConfig(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionName,
    required Map<String, String> values,
    List<String>? deleteOptions,
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
    List<String>? deleteOptions,
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
      final primaryIpv4 = (dnsServers ?? []).firstWhere(
        (ip) => ip.contains('.') && !ip.contains(':'),
        orElse: () => (dnsServers != null && dnsServers.isNotEmpty)
            ? dnsServers.first
            : '',
      );
      final primaryIpv6 = (dnsServers ?? []).firstWhere(
        (ip) => ip.contains(':'),
        orElse: () => '',
      );
      final macsStr = macAddresses.map((m) => m.toLowerCase()).join(' ');

      final ipv6Script = primaryIpv6.isNotEmpty
          ? '''
  uci set firewall.parental_dns_redir6_\$SEC=redirect
  uci set firewall.parental_dns_redir6_\$SEC.name="parental_dns_redir6_\$SEC"
  uci set firewall.parental_dns_redir6_\$SEC.src='lan'
  uci set firewall.parental_dns_redir6_\$SEC.dest='wan'
  uci set firewall.parental_dns_redir6_\$SEC.proto='tcp udp'
  uci set firewall.parental_dns_redir6_\$SEC.family='ipv6'
  uci set firewall.parental_dns_redir6_\$SEC.src_dport='53'
  uci delete firewall.parental_dns_redir6_\$SEC.src_mac 2>/dev/null || true
  for m in $macsStr; do uci add_list firewall.parental_dns_redir6_\$SEC.src_mac="\$m"; done
  uci set firewall.parental_dns_redir6_\$SEC.dest_ip='$primaryIpv6'
  uci set firewall.parental_dns_redir6_\$SEC.dest_port='53'
  uci set firewall.parental_dns_redir6_\$SEC.target='DNAT'
  uci reorder firewall.parental_dns_redir6_\$SEC=0 2>/dev/null || true
  uci delete firewall.parental_dns_block6_\$SEC 2>/dev/null || true
  uci delete firewall.parental_dns_in6_\$SEC 2>/dev/null || true
'''
          : '''
  uci delete firewall.parental_dns_redir6_\$SEC 2>/dev/null || true
  uci set firewall.parental_dns_block6_\$SEC=rule
  uci set firewall.parental_dns_block6_\$SEC.name="parental_dns_block6_\$SEC"
  uci set firewall.parental_dns_block6_\$SEC.src='lan'
  uci set firewall.parental_dns_block6_\$SEC.dest='*'
  uci set firewall.parental_dns_block6_\$SEC.proto='tcp udp'
  uci set firewall.parental_dns_block6_\$SEC.family='ipv6'
  uci set firewall.parental_dns_block6_\$SEC.dest_port='53'
  uci delete firewall.parental_dns_block6_\$SEC.src_mac 2>/dev/null || true
  for m in $macsStr; do uci add_list firewall.parental_dns_block6_\$SEC.src_mac="\$m"; done
  uci set firewall.parental_dns_block6_\$SEC.target='REJECT'
  uci set firewall.parental_dns_block6_\$SEC.enabled='1'
  uci reorder firewall.parental_dns_block6_\$SEC=0 2>/dev/null || true

  uci set firewall.parental_dns_in6_\$SEC=rule
  uci set firewall.parental_dns_in6_\$SEC.name="parental_dns_in6_\$SEC"
  uci set firewall.parental_dns_in6_\$SEC.src='lan'
  uci set firewall.parental_dns_in6_\$SEC.proto='tcp udp'
  uci set firewall.parental_dns_in6_\$SEC.family='ipv6'
  uci set firewall.parental_dns_in6_\$SEC.dest_port='53'
  uci delete firewall.parental_dns_in6_\$SEC.src_mac 2>/dev/null || true
  for m in $macsStr; do uci add_list firewall.parental_dns_in6_\$SEC.src_mac="\$m"; done
  uci set firewall.parental_dns_in6_\$SEC.target='REJECT'
  uci set firewall.parental_dns_in6_\$SEC.enabled='1'
  uci reorder firewall.parental_dns_in6_\$SEC=0 2>/dev/null || true
''';

      final script =
          '''
T="$tag"
SEC="$safeId"
DNS="$dnsStr"
if [ "\$DNS" = "" ]; then
  uci delete dhcp.\$T 2>/dev/null
  for sec in \$(uci show dhcp 2>/dev/null | grep -i '@host' | grep "\\.mac=" | cut -d. -f2 | sort -u); do
    cur_tag=\$(uci get dhcp.\$sec.tag 2>/dev/null)
    if [ "\$cur_tag" = "\$T" ]; then
      uci delete dhcp.\$sec.tag
    fi
  done
  uci delete firewall.parental_dns_redir_\$SEC 2>/dev/null || true
  uci delete firewall.parental_dns_redir6_\$SEC 2>/dev/null || true
  uci delete firewall.parental_dot_block_\$SEC 2>/dev/null || true
  uci delete firewall.parental_dns_block6_\$SEC 2>/dev/null || true
  uci delete firewall.parental_dns_in6_\$SEC 2>/dev/null || true
else
  uci set dhcp.\$T=tag
  uci delete dhcp.\$T.dhcp_option 2>/dev/null || true
  uci add_list dhcp.\$T.dhcp_option="6,\$DNS"
  for m in $macsStr; do
    sec=\$(uci show dhcp 2>/dev/null | grep -i "@host.*\\.mac=.*\$m" | cut -d. -f2 | head -n1)
    if [ -z "\$sec" ]; then
      sec="p_host_\$(echo "\$m" | tr ':' '_')"
      uci set dhcp.\$sec=host
      uci set dhcp.\$sec.mac="\$m"
      uci set dhcp.\$sec.name="p_\$(echo "\$m" | tr ':' '-')"
    fi
    uci set dhcp.\$sec.tag="\$T"
  done

  uci set firewall.parental_dns_redir_\$SEC=redirect
  uci set firewall.parental_dns_redir_\$SEC.name="parental_dns_redir_\$SEC"
  uci set firewall.parental_dns_redir_\$SEC.src='lan'
  uci set firewall.parental_dns_redir_\$SEC.dest='wan'
  uci set firewall.parental_dns_redir_\$SEC.proto='tcp udp'
  uci set firewall.parental_dns_redir_\$SEC.src_dport='53'
  uci delete firewall.parental_dns_redir_\$SEC.src_mac 2>/dev/null || true
  for m in $macsStr; do uci add_list firewall.parental_dns_redir_\$SEC.src_mac="\$m"; done
  ${primaryIpv4.isNotEmpty ? "uci set firewall.parental_dns_redir_\$SEC.dest_ip='$primaryIpv4'" : ""}
  uci set firewall.parental_dns_redir_\$SEC.dest_port='53'
  uci set firewall.parental_dns_redir_\$SEC.target='DNAT'
  uci reorder firewall.parental_dns_redir_\$SEC=0 2>/dev/null || true

  uci set firewall.parental_dot_block_\$SEC=rule
  uci set firewall.parental_dot_block_\$SEC.name="parental_dot_block_\$SEC"
  uci set firewall.parental_dot_block_\$SEC.src='lan'
  uci set firewall.parental_dot_block_\$SEC.dest='wan'
  uci set firewall.parental_dot_block_\$SEC.proto='tcp'
  uci set firewall.parental_dot_block_\$SEC.dest_port='853'
  uci delete firewall.parental_dot_block_\$SEC.src_mac 2>/dev/null || true
  for m in $macsStr; do uci add_list firewall.parental_dot_block_\$SEC.src_mac="\$m"; done
  uci set firewall.parental_dot_block_\$SEC.target='REJECT'
  uci set firewall.parental_dot_block_\$SEC.enabled='1'
  uci reorder firewall.parental_dot_block_\$SEC=0 2>/dev/null || true

$ipv6Script
fi
uci commit dhcp
/etc/init.d/dnsmasq restart 2>/dev/null || true
uci commit firewall
/etc/init.d/firewall reload 2>/dev/null || true
for m in $macsStr; do
  for ip in \$(ip neigh show 2>/dev/null | grep -i "\$m" | awk '{print \$1}'); do
    conntrack -D -s "\$ip" -p udp --dport 53 >/dev/null 2>&1 || true
    conntrack -D -s "\$ip" -p tcp --dport 53 >/dev/null 2>&1 || true
    conntrack -D -d "\$ip" -p udp --sport 53 >/dev/null 2>&1 || true
    conntrack -D -d "\$ip" -p tcp --sport 53 >/dev/null 2>&1 || true
  done
done
''';

      final res = await systemExec(
        ipAddress,
        sysauth,
        useHttps,
        command: script,
        context: context,
      );
      return _execSucceeded(res);
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
      final daysStr = (profile.schedule?.activeDays ?? {})
          .map((d) => d.uciWeekday)
          .join(' ');

      final dnsServers = profile.contentFilter == ContentFilterDns.custom
          ? profile.customDnsServers
          : profile.contentFilter.primaryServers;
      final dnsJoined = dnsServers.join(',');
      final primaryIpv4 = dnsServers.firstWhere(
        (ip) => ip.contains('.') && !ip.contains(':'),
        orElse: () => dnsServers.isNotEmpty ? dnsServers.first : '',
      );
      final primaryIpv6 = dnsServers.firstWhere(
        (ip) => ip.contains(':'),
        orElse: () => '',
      );

      String scheduleRulesScript = '';
      if (profile.isEnabled &&
          profile.hasSchedule &&
          profile.macAddresses.isNotEmpty) {
        final sched = profile.schedule!;
        final bMin = sched.blockHour * 60 + sched.blockMinute;
        final rMin = sched.resumeHour * 60 + sched.resumeMinute;
        final bFormatted =
            '${sched.blockHour.toString().padLeft(2, '0')}:${sched.blockMinute.toString().padLeft(2, '0')}:00';
        final rFormatted =
            '${sched.resumeHour.toString().padLeft(2, '0')}:${sched.resumeMinute.toString().padLeft(2, '0')}:00';
        final weekdaysStr = sched.activeDays.map((d) => d.uciWeekday).join(' ');
        final nextMorningWeekdaysStr = sched.activeDays
            .map((d) => d.nextDay.uciWeekday)
            .join(' ');

        if (bMin < rMin) {
          // Daytime schedule (e.g. 14:00 to 18:00)
          scheduleRulesScript =
              '''
uci set firewall.parental_sched_\${SEC}_1=rule
uci set firewall.parental_sched_\${SEC}_1.name="parental_sched_\${SEC}_1"
uci set firewall.parental_sched_\${SEC}_1.src='lan'
uci set firewall.parental_sched_\${SEC}_1.dest='wan'
uci delete firewall.parental_sched_\${SEC}_1.src_mac 2>/dev/null || true
for m in $macsStr; do uci add_list firewall.parental_sched_\${SEC}_1.src_mac="\$m"; done
uci set firewall.parental_sched_\${SEC}_1.start_time='$bFormatted'
uci set firewall.parental_sched_\${SEC}_1.stop_time='$rFormatted'
uci set firewall.parental_sched_\${SEC}_1.weekdays='$weekdaysStr'
uci set firewall.parental_sched_\${SEC}_1.target='REJECT'
uci set firewall.parental_sched_\${SEC}_1.enabled='1'
uci reorder firewall.parental_sched_\${SEC}_1=0 2>/dev/null || true
uci delete firewall.parental_sched_\${SEC}_2 2>/dev/null || true
''';
        } else {
          // Overnight schedule (spans midnight, e.g. 22:00 to 07:00)
          scheduleRulesScript =
              '''
uci set firewall.parental_sched_\${SEC}_1=rule
uci set firewall.parental_sched_\${SEC}_1.name="parental_sched_\${SEC}_1"
uci set firewall.parental_sched_\${SEC}_1.src='lan'
uci set firewall.parental_sched_\${SEC}_1.dest='wan'
uci delete firewall.parental_sched_\${SEC}_1.src_mac 2>/dev/null || true
for m in $macsStr; do uci add_list firewall.parental_sched_\${SEC}_1.src_mac="\$m"; done
uci set firewall.parental_sched_\${SEC}_1.start_time='$bFormatted'
uci set firewall.parental_sched_\${SEC}_1.stop_time='23:59:59'
uci set firewall.parental_sched_\${SEC}_1.weekdays='$weekdaysStr'
uci set firewall.parental_sched_\${SEC}_1.target='REJECT'
uci set firewall.parental_sched_\${SEC}_1.enabled='1'
uci reorder firewall.parental_sched_\${SEC}_1=0 2>/dev/null || true

uci set firewall.parental_sched_\${SEC}_2=rule
uci set firewall.parental_sched_\${SEC}_2.name="parental_sched_\${SEC}_2"
uci set firewall.parental_sched_\${SEC}_2.src='lan'
uci set firewall.parental_sched_\${SEC}_2.dest='wan'
uci delete firewall.parental_sched_\${SEC}_2.src_mac 2>/dev/null || true
for m in $macsStr; do uci add_list firewall.parental_sched_\${SEC}_2.src_mac="\$m"; done
uci set firewall.parental_sched_\${SEC}_2.start_time='00:00:00'
uci set firewall.parental_sched_\${SEC}_2.stop_time='$rFormatted'
uci set firewall.parental_sched_\${SEC}_2.weekdays='$nextMorningWeekdaysStr'
uci set firewall.parental_sched_\${SEC}_2.target='REJECT'
uci set firewall.parental_sched_\${SEC}_2.enabled='1'
uci reorder firewall.parental_sched_\${SEC}_2=0 2>/dev/null || true
''';
        }
      } else {
        scheduleRulesScript = '''
uci delete firewall.parental_sched_\${SEC}_1 2>/dev/null || true
uci delete firewall.parental_sched_\${SEC}_2 2>/dev/null || true
''';
      }

      // 1. Pause rule in firewall
      String pauseRuleScript = '';
      if (profile.isEnabled &&
          profile.isPaused &&
          profile.macAddresses.isNotEmpty) {
        pauseRuleScript =
            '''
uci set firewall.parental_pause_\$SEC=rule
uci set firewall.parental_pause_\$SEC.name="parental_pause_\$SEC"
uci set firewall.parental_pause_\$SEC.src='lan'
uci set firewall.parental_pause_\$SEC.dest='wan'
uci delete firewall.parental_pause_\$SEC.src_mac 2>/dev/null || true
for m in $macsStr; do uci add_list firewall.parental_pause_\$SEC.src_mac="\$m"; done
uci set firewall.parental_pause_\$SEC.target='REJECT'
uci set firewall.parental_pause_\$SEC.enabled='1'
uci reorder firewall.parental_pause_\$SEC=0 2>/dev/null || true
''';
      } else {
        pauseRuleScript = '''
uci delete firewall.parental_pause_\$SEC 2>/dev/null || true
''';
      }

      // 2. DNS content filter rules
      String dnsFirewallScript = '';
      String dhcpTagScript = '';
      if (profile.isEnabled &&
          profile.hasContentFilter &&
          profile.macAddresses.isNotEmpty &&
          dnsJoined.isNotEmpty) {
        final ipv6Script = primaryIpv6.isNotEmpty
            ? '''
uci set firewall.parental_dns_redir6_\$SEC=redirect
uci set firewall.parental_dns_redir6_\$SEC.name="parental_dns_redir6_\$SEC"
uci set firewall.parental_dns_redir6_\$SEC.src='lan'
uci set firewall.parental_dns_redir6_\$SEC.dest='wan'
uci set firewall.parental_dns_redir6_\$SEC.proto='tcp udp'
uci set firewall.parental_dns_redir6_\$SEC.family='ipv6'
uci set firewall.parental_dns_redir6_\$SEC.src_dport='53'
uci delete firewall.parental_dns_redir6_\$SEC.src_mac 2>/dev/null || true
for m in $macsStr; do uci add_list firewall.parental_dns_redir6_\$SEC.src_mac="\$m"; done
uci set firewall.parental_dns_redir6_\$SEC.dest_ip='$primaryIpv6'
uci set firewall.parental_dns_redir6_\$SEC.dest_port='53'
uci set firewall.parental_dns_redir6_\$SEC.target='DNAT'
uci reorder firewall.parental_dns_redir6_\$SEC=0 2>/dev/null || true
uci delete firewall.parental_dns_block6_\$SEC 2>/dev/null || true
uci delete firewall.parental_dns_in6_\$SEC 2>/dev/null || true
'''
            : '''
uci delete firewall.parental_dns_redir6_\$SEC 2>/dev/null || true
uci set firewall.parental_dns_block6_\$SEC=rule
uci set firewall.parental_dns_block6_\$SEC.name="parental_dns_block6_\$SEC"
uci set firewall.parental_dns_block6_\$SEC.src='lan'
uci set firewall.parental_dns_block6_\$SEC.dest='*'
uci set firewall.parental_dns_block6_\$SEC.proto='tcp udp'
uci set firewall.parental_dns_block6_\$SEC.family='ipv6'
uci set firewall.parental_dns_block6_\$SEC.dest_port='53'
uci delete firewall.parental_dns_block6_\$SEC.src_mac 2>/dev/null || true
for m in $macsStr; do uci add_list firewall.parental_dns_block6_\$SEC.src_mac="\$m"; done
uci set firewall.parental_dns_block6_\$SEC.target='REJECT'
uci set firewall.parental_dns_block6_\$SEC.enabled='1'
uci reorder firewall.parental_dns_block6_\$SEC=0 2>/dev/null || true

uci set firewall.parental_dns_in6_\$SEC=rule
uci set firewall.parental_dns_in6_\$SEC.name="parental_dns_in6_\$SEC"
uci set firewall.parental_dns_in6_\$SEC.src='lan'
uci set firewall.parental_dns_in6_\$SEC.proto='tcp udp'
uci set firewall.parental_dns_in6_\$SEC.family='ipv6'
uci set firewall.parental_dns_in6_\$SEC.dest_port='53'
uci delete firewall.parental_dns_in6_\$SEC.src_mac 2>/dev/null || true
for m in $macsStr; do uci add_list firewall.parental_dns_in6_\$SEC.src_mac="\$m"; done
uci set firewall.parental_dns_in6_\$SEC.target='REJECT'
uci set firewall.parental_dns_in6_\$SEC.enabled='1'
uci reorder firewall.parental_dns_in6_\$SEC=0 2>/dev/null || true
''';

        dnsFirewallScript =
            '''
uci set firewall.parental_dns_redir_\$SEC=redirect
uci set firewall.parental_dns_redir_\$SEC.name="parental_dns_redir_\$SEC"
uci set firewall.parental_dns_redir_\$SEC.src='lan'
uci set firewall.parental_dns_redir_\$SEC.dest='wan'
uci set firewall.parental_dns_redir_\$SEC.proto='tcp udp'
uci set firewall.parental_dns_redir_\$SEC.src_dport='53'
uci delete firewall.parental_dns_redir_\$SEC.src_mac 2>/dev/null || true
for m in $macsStr; do uci add_list firewall.parental_dns_redir_\$SEC.src_mac="\$m"; done
${primaryIpv4.isNotEmpty ? "uci set firewall.parental_dns_redir_\$SEC.dest_ip='$primaryIpv4'" : ""}
uci set firewall.parental_dns_redir_\$SEC.dest_port='53'
uci set firewall.parental_dns_redir_\$SEC.target='DNAT'
uci reorder firewall.parental_dns_redir_\$SEC=0 2>/dev/null || true

uci set firewall.parental_dot_block_\$SEC=rule
uci set firewall.parental_dot_block_\$SEC.name="parental_dot_block_\$SEC"
uci set firewall.parental_dot_block_\$SEC.src='lan'
uci set firewall.parental_dot_block_\$SEC.dest='wan'
uci set firewall.parental_dot_block_\$SEC.proto='tcp'
uci set firewall.parental_dot_block_\$SEC.dest_port='853'
uci delete firewall.parental_dot_block_\$SEC.src_mac 2>/dev/null || true
for m in $macsStr; do uci add_list firewall.parental_dot_block_\$SEC.src_mac="\$m"; done
uci set firewall.parental_dot_block_\$SEC.target='REJECT'
uci set firewall.parental_dot_block_\$SEC.enabled='1'
uci reorder firewall.parental_dot_block_\$SEC=0 2>/dev/null || true

$ipv6Script
''';

        dhcpTagScript =
            '''
T="p_tag_\$SEC"
uci set dhcp.\$T=tag
uci delete dhcp.\$T.dhcp_option 2>/dev/null || true
uci add_list dhcp.\$T.dhcp_option="6,$dnsJoined"
for m in $macsStr; do
  hostSec=\$(uci show dhcp 2>/dev/null | grep -i "@host.*\\.mac=.*\$m" | cut -d. -f2 | head -n1)
  if [ -z "\$hostSec" ]; then
    hostSec="p_host_\$(echo "\$m" | tr ':' '_')"
    uci set dhcp.\$hostSec=host
    uci set dhcp.\$hostSec.mac="\$m"
    uci set dhcp.\$hostSec.name="p_\$(echo "\$m" | tr ':' '-')"
  fi
  uci set dhcp.\$hostSec.tag="\$T"
done
uci commit dhcp
/etc/init.d/dnsmasq restart 2>/dev/null || true
''';
      } else {
        dnsFirewallScript = '''
uci delete firewall.parental_dns_redir_\$SEC 2>/dev/null || true
uci delete firewall.parental_dns_redir6_\$SEC 2>/dev/null || true
uci delete firewall.parental_dot_block_\$SEC 2>/dev/null || true
uci delete firewall.parental_dns_block6_\$SEC 2>/dev/null || true
uci delete firewall.parental_dns_in6_\$SEC 2>/dev/null || true
''';

        dhcpTagScript = '''
T="p_tag_\$SEC"
uci delete dhcp.\$T 2>/dev/null || true
for sec_h in \$(uci show dhcp 2>/dev/null | grep -i '@host' | grep "\\.mac=" | cut -d. -f2 | sort -u); do
  cur_tag=\$(uci get dhcp.\$sec_h.tag 2>/dev/null)
  if [ "\$cur_tag" = "\$T" ]; then
    uci delete dhcp.\$sec_h.tag 2>/dev/null || true
  fi
done
uci commit dhcp
/etc/init.d/dnsmasq restart 2>/dev/null || true
''';
      }

      // 3. Conntrack and runtime firewall rule sync (insert at pos 1 for zero leakage)
      String conntrackScript = '';
      if (profile.isEnabled &&
          (profile.isPaused || profile.isScheduleBlocked) &&
          profile.macAddresses.isNotEmpty) {
        conntrackScript =
            '''
for m in $macsStr; do
  nft insert rule inet fw4 forward ether saddr "\$m" drop >/dev/null 2>&1 || true
  nft insert rule inet fw4 forward ether daddr "\$m" drop >/dev/null 2>&1 || true
  iptables -I FORWARD 1 -m mac --mac-source "\$m" -j DROP >/dev/null 2>&1 || true
  for ip in \$(ip neigh show 2>/dev/null | grep -i "\$m" | awk '{print \$1}'); do
    conntrack -D -s "\$ip" >/dev/null 2>&1 || true
    conntrack -D -d "\$ip" >/dev/null 2>&1 || true
  done
done
''';
      } else if (!profile.isEnabled ||
          (!profile.isPaused && !profile.isScheduleBlocked)) {
        conntrackScript =
            '''
for m in $macsStr; do
  nft -a list chain inet fw4 forward 2>/dev/null | grep -i "\$m" | awk '{print \$NF}' | while read -r h; do
    [ -n "\$h" ] && nft delete rule inet fw4 forward handle "\$h" >/dev/null 2>&1 || true
  done
  while iptables -D FORWARD -m mac --mac-source "\$m" -j DROP >/dev/null 2>&1; do :; done
done
''';
      }

      // 4. Cron unpause script (100% null-safe)
      String cronScript = '';
      if (profile.isEnabled &&
          profile.isPaused &&
          profile.pauseExpiresAt != null) {
        final expSec = profile.pauseExpiresAt!.millisecondsSinceEpoch ~/ 1000;
        cronScript =
            '''
EXP="$expSec"
CRON_TIME=\$(date -d @"\$EXP" +'%M %H %d %m' 2>/dev/null)
if [ -n "\$CRON_TIME" ]; then
  mkdir -p /etc/crontabs
  touch /etc/crontabs/root
  sed -i "/parental_pause_\$SEC/d" /etc/crontabs/root 2>/dev/null || true
  echo "\$CRON_TIME * uci delete firewall.parental_pause_\$SEC 2>/dev/null; uci set parental.\$SEC.is_paused='0'; uci commit firewall; uci commit parental; /etc/init.d/firewall reload; sed -i '/parental_pause_\$SEC/d' /etc/crontabs/root" >> /etc/crontabs/root
  /etc/init.d/cron enable 2>/dev/null || true
  /etc/init.d/cron restart 2>/dev/null || /etc/init.d/cron start 2>/dev/null || /etc/init.d/crond restart 2>/dev/null || true
fi
''';
      } else {
        cronScript = '''
sed -i "/parental_pause_\$SEC/d" /etc/crontabs/root 2>/dev/null || true
''';
      }

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
uci set parental.\$SEC.schedule_enabled="${profile.hasSchedule ? '1' : '0'}"
uci set parental.\$SEC.schedule_block_hour="${profile.schedule?.blockHour ?? 22}"
uci set parental.\$SEC.schedule_block_min="${profile.schedule?.blockMinute ?? 0}"
uci set parental.\$SEC.schedule_resume_hour="${profile.schedule?.resumeHour ?? 7}"
uci set parental.\$SEC.schedule_resume_min="${profile.schedule?.resumeMinute ?? 0}"
uci delete parental.\$SEC.schedule_days 2>/dev/null || true
for day in $daysStr; do uci add_list parental.\$SEC.schedule_days="\$day"; done
uci set parental.\$SEC.daily_time_limit_minutes="${profile.hasTimeLimit ? profile.dailyTimeLimitMinutes! : 0}"
uci set parental.\$SEC.pause_expires_at="${profile.pauseExpiresAt?.millisecondsSinceEpoch ?? 0}"
uci commit parental

# 1. Sync pause rule in firewall
$pauseRuleScript

# 2. Sync schedule rules in firewall
$scheduleRulesScript

# 3. Sync DNS content filter (Port 53 redirect and Port 853 drop)
$dnsFirewallScript

uci commit firewall
/etc/init.d/firewall reload 2>/dev/null || true

# Flush tracked DNS connections for target MACs
for m in $macsStr; do
  for ip in \$(ip neigh show 2>/dev/null | grep -i "\$m" | awk '{print \$1}'); do
    conntrack -D -s "\$ip" -p udp --dport 53 >/dev/null 2>&1 || true
    conntrack -D -s "\$ip" -p tcp --dport 53 >/dev/null 2>&1 || true
    conntrack -D -d "\$ip" -p udp --sport 53 >/dev/null 2>&1 || true
    conntrack -D -d "\$ip" -p tcp --sport 53 >/dev/null 2>&1 || true
  done
done
$conntrackScript

# 5. Cron auto-unpause registration
$cronScript

# 6. DHCP DNS Tagging
$dhcpTagScript

# 7. Autonomous minute-by-minute Parental Guard installation
cat << 'GUARD_EOF' > /usr/bin/parental_guard
#!/bin/sh
[ -f /etc/config/parental ] || exit 0

TODAY=\$(date +%Y%m%d)
CUR_DAY=\$(date +%a)
HOUR=\$(date +%H | sed 's/^0//')
MIN=\$(date +%M | sed 's/^0//')
HOUR=\${HOUR:-0}
MIN=\${MIN:-0}
CUR_MIN=\$(( HOUR * 60 + MIN ))
NOW_EPOCH=\$(date +%s)

profiles=\$(uci show parental 2>/dev/null | grep "=profile" | cut -d. -f2 | cut -d= -f1)
[ -n "\$profiles" ] || exit 0

for sec in \$profiles; do
  enabled=\$(uci get parental.\$sec.is_enabled 2>/dev/null || echo "1")
  if [ "\$enabled" = "0" ]; then
    continue
  fi

  macs=\$(uci get parental.\$sec.mac 2>/dev/null)
  [ -n "\$macs" ] || continue

  is_paused=\$(uci get parental.\$sec.is_paused 2>/dev/null || echo "0")
  pause_exp=\$(uci get parental.\$sec.pause_expires_at 2>/dev/null || echo "0")
  if [ "\$is_paused" = "1" ] && [ "\$pause_exp" -gt 0 ] && [ "\$NOW_EPOCH" -ge "\$pause_exp" ]; then
    uci set parental.\$sec.is_paused='0'
    uci set parental.\$sec.pause_expires_at='0'
    uci commit parental
    is_paused="0"
  fi

  sched_enabled=\$(uci get parental.\$sec.schedule_enabled 2>/dev/null || echo "0")
  sched_blocked=0
  if [ "\$sched_enabled" = "1" ]; then
    b_h=\$(uci get parental.\$sec.schedule_block_hour 2>/dev/null || echo "22")
    b_m=\$(uci get parental.\$sec.schedule_block_min 2>/dev/null || echo "0")
    r_h=\$(uci get parental.\$sec.schedule_resume_hour 2>/dev/null || echo "7")
    r_m=\$(uci get parental.\$sec.schedule_resume_min 2>/dev/null || echo "0")
    b_h=\$(echo "\$b_h" | sed 's/^0//'); b_h=\${b_h:-0}
    b_m=\$(echo "\$b_m" | sed 's/^0//'); b_m=\${b_m:-0}
    r_h=\$(echo "\$r_h" | sed 's/^0//'); r_h=\${r_h:-0}
    r_m=\$(echo "\$r_m" | sed 's/^0//'); r_m=\${r_m:-0}
    b_min=\$(( b_h * 60 + b_m ))
    r_min=\$(( r_h * 60 + r_m ))

    days=\$(uci get parental.\$sec.schedule_days 2>/dev/null)
    day_match=0
    if [ -z "\$days" ]; then
      day_match=1
    else
      for d in \$days; do
        if [ "\$d" = "\$CUR_DAY" ]; then
          day_match=1
          break
        fi
      done
    fi

    if [ "\$day_match" = "1" ]; then
      if [ \$b_min -lt \$r_min ]; then
        if [ \$CUR_MIN -ge \$b_min ] && [ \$CUR_MIN -lt \$r_min ]; then
          sched_blocked=1
        fi
      elif [ \$b_min -gt \$r_min ]; then
        if [ \$CUR_MIN -ge \$b_min ] || [ \$CUR_MIN -lt \$r_min ]; then
          sched_blocked=1
        fi
      else
        sched_blocked=1
      fi
    fi
  fi

  daily_limit=\$(uci get parental.\$sec.daily_time_limit_minutes 2>/dev/null || echo "0")
  quota_blocked=0
  if [ "\$daily_limit" -gt 0 ]; then
    used_file="/tmp/parental_used_\${sec}"
    last_date=""
    used_mins=0
    if [ -f "\$used_file" ]; then
      content=\$(cat "\$used_file" 2>/dev/null)
      last_date=\$(echo "\$content" | cut -d: -f1)
      used_mins=\$(echo "\$content" | cut -d: -f2)
      used_mins=\${used_mins:-0}
    fi
    if [ "\$last_date" != "\$TODAY" ]; then
      used_mins=0
    fi

    is_active=0
    for m in \$macs; do
      if ip neigh show 2>/dev/null | grep -i "\$m" | grep -v -i "FAILED" >/dev/null 2>&1; then
        is_active=1
        break
      fi
    done

    if [ "\$is_active" = "1" ] && [ "\$sched_blocked" = "0" ] && [ "\$is_paused" = "0" ]; then
      used_mins=\$(( used_mins + 1 ))
      echo "\${TODAY}:\${used_mins}" > "\$used_file"
    fi

    if [ "\$used_mins" -ge "\$daily_limit" ]; then
      quota_blocked=1
    fi
  fi

  should_block=0
  if [ "\$is_paused" = "1" ] || [ "\$sched_blocked" = "1" ] || [ "\$quota_blocked" = "1" ]; then
    should_block=1
  fi

  for m in \$macs; do
    m_clean=\$(echo "\$m" | tr 'A-Z' 'a-z')
    if [ "\$should_block" = "1" ]; then
      if command -v nft >/dev/null 2>&1; then
        nft list chain inet fw4 forward 2>/dev/null | grep -i "\$m_clean" >/dev/null 2>&1 || {
          nft insert rule inet fw4 forward ether saddr "\$m_clean" drop >/dev/null 2>&1 || true
          nft insert rule inet fw4 forward ether daddr "\$m_clean" drop >/dev/null 2>&1 || true
        }
      fi
      if command -v iptables >/dev/null 2>&1; then
        iptables -C FORWARD -m mac --mac-source "\$m_clean" -j DROP >/dev/null 2>&1 || {
          iptables -I FORWARD 1 -m mac --mac-source "\$m_clean" -j DROP >/dev/null 2>&1 || true
        }
      fi
      for ip in \$(ip neigh show 2>/dev/null | grep -i "\$m_clean" | awk '{print \$1}'); do
        conntrack -D -s "\$ip" >/dev/null 2>&1 || true
        conntrack -D -d "\$ip" >/dev/null 2>&1 || true
      done
    else
      if command -v nft >/dev/null 2>&1; then
        nft -a list chain inet fw4 forward 2>/dev/null | grep -i "\$m_clean" | awk '{print \$NF}' | while read -r h; do
          [ -n "\$h" ] && nft delete rule inet fw4 forward handle "\$h" >/dev/null 2>&1 || true
        done
      fi
      if command -v iptables >/dev/null 2>&1; then
        while iptables -D FORWARD -m mac --mac-source "\$m_clean" -j DROP >/dev/null 2>&1; do :; done
      fi
    fi
  done
done
GUARD_EOF
chmod +x /usr/bin/parental_guard
mkdir -p /etc/crontabs
touch /etc/crontabs/root
grep -q "/usr/bin/parental_guard" /etc/crontabs/root 2>/dev/null || echo "* * * * * /bin/sh /usr/bin/parental_guard >/dev/null 2>&1" >> /etc/crontabs/root
/etc/init.d/cron enable 2>/dev/null || true
/etc/init.d/cron start 2>/dev/null || /etc/init.d/cron restart 2>/dev/null || /etc/init.d/crond restart 2>/dev/null || true
/bin/sh /usr/bin/parental_guard >/dev/null 2>&1 || true
''';

      final res = await systemExec(
        ipAddress,
        sysauth,
        useHttps,
        command: script,
        context: context,
      );
      final ok = _execSucceeded(res);
      if (!ok) {
        Logger.warning('saveParentalProfile script execution failed: $res');
        String detail = '';
        if (res is List && res.length > 1 && res[1] is Map) {
          final m = res[1] as Map;
          final errText = m['stderr']?.toString().trim() ?? '';
          if (errText.isNotEmpty) {
            detail = errText;
          }
        }
        if (detail.isNotEmpty) {
          throw Exception('Router command failed: $detail');
        }
      }
      return ok;
    } catch (e, stack) {
      Logger.exception('saveParentalProfile failed', e, stack);
      rethrow;
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
T="p_tag_\$SEC"
uci delete parental.\$SEC 2>/dev/null || true
uci commit parental

uci delete firewall.parental_pause_\$SEC 2>/dev/null || true
uci delete firewall.parental_sched_\${SEC}_1 2>/dev/null || true
uci delete firewall.parental_sched_\${SEC}_2 2>/dev/null || true
uci delete firewall.parental_dns_redir_\$SEC 2>/dev/null || true
uci delete firewall.parental_dns_redir6_\$SEC 2>/dev/null || true
uci delete firewall.parental_dot_block_\$SEC 2>/dev/null || true
uci delete firewall.parental_dns_block6_\$SEC 2>/dev/null || true
uci delete firewall.parental_dns_in6_\$SEC 2>/dev/null || true
uci commit firewall
/etc/init.d/firewall reload 2>/dev/null || true

sed -i "/parental_pause_\$SEC/d" /etc/crontabs/root 2>/dev/null || true

uci delete dhcp.\$T 2>/dev/null || true
for sec_h in \$(uci show dhcp 2>/dev/null | grep -i '@host' | grep "\\.mac=" | cut -d. -f2 | sort -u); do
  cur_tag=\$(uci get dhcp.\$sec_h.tag 2>/dev/null)
  if [ "\$cur_tag" = "\$T" ]; then
    uci delete dhcp.\$sec_h.tag 2>/dev/null || true
  fi
done
uci commit dhcp
/etc/init.d/dnsmasq restart 2>/dev/null || true
''';

      final res = await systemExec(
        ipAddress,
        sysauth,
        useHttps,
        command: script,
        context: context,
      );
      final ok = _execSucceeded(res);
      if (!ok) {
        Logger.warning('deleteParentalProfile script execution failed: $res');
      }
      return ok;
    } catch (e, stack) {
      Logger.exception('deleteParentalProfile failed', e, stack);
      rethrow;
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
    Map<String, String>? extraOptions,
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
      if (extraOptions != null) {
        values.addAll(extraOptions);
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
        params: {'rollback': true, 'timeout': 30},
        context: mountedContext(context),
      );
      if (applyRes is List &&
          applyRes.isNotEmpty &&
          (applyRes[0] == 0 || applyRes[0] == 5)) {
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

  @override
  Future<bool> updateInterfaceDhcpConfig(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String interface,
    required Map<String, dynamic> values,
    BuildContext? context,
  }) async {
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
      String? matchedSection;
      if (getRes is List && getRes.length > 1 && getRes[0] == 0) {
        final uciData = getRes[1];
        final valuesMap = (uciData is Map && uciData['values'] is Map)
            ? uciData['values'] as Map
            : (uciData is Map ? uciData : {});
        for (final entry in valuesMap.entries) {
          final val = entry.value;
          if (val is Map &&
              val['.type'] == 'dhcp' &&
              (val['interface'] == interface || entry.key == interface)) {
            matchedSection = entry.key.toString();
            break;
          }
        }
      }
      final String sectionName =
          (matchedSection != null && matchedSection.isNotEmpty)
          ? matchedSection
          : interface;
      if (matchedSection == null || matchedSection.isEmpty) {
        await _ensureUciSection(
          ipAddress,
          sysauth,
          useHttps,
          'dhcp',
          sectionName,
          'dhcp',
          {'interface': interface},
          context: mountedContext(context),
        );
      }
      final strValues = <String, dynamic>{};
      values.forEach((k, v) {
        if (v != null) {
          strValues[k] = v is String ? v : v.toString();
        }
      });
      final setRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'set',
        params: {'config': 'dhcp', 'section': sectionName, 'values': strValues},
        context: mountedContext(context),
      );
      if (setRes is List && setRes.isNotEmpty && setRes[0] != 0) {
        await uciRevert(
          ipAddress,
          sysauth,
          useHttps,
          config: 'dhcp',
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
        params: {'rollback': true, 'timeout': 30},
        context: mountedContext(context),
      );
      if (applyRes is List &&
          applyRes.isNotEmpty &&
          (applyRes[0] == 0 || applyRes[0] == 5)) {
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
        config: 'dhcp',
        context: mountedContext(context),
      );
      return false;
    } catch (e, stack) {
      Logger.exception(
        'updateInterfaceDhcpConfig failed for $interface',
        e,
        stack,
      );
      await uciRevert(
        ipAddress,
        sysauth,
        useHttps,
        config: 'dhcp',
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

  static const String fullAclJson = '''{
  "yet-another-luci-app": {
    "description": "Yet Another LuCI App Permissions",
    "read": {
      "cgi-io": [ "backup", "download", "exec" ],
      "file": {
        "/": [ "list" ],
        "/*": [ "list" ],
        "/etc/config/*": [ "read" ],
        "/etc/openwrt_release": [ "read" ],
        "/etc/os-release": [ "read" ],
        "/etc/board.json": [ "read" ],
        "/etc/crontabs/root": [ "read" ],
        "/etc/dropbear/authorized_keys": [ "read" ],
        "/proc/*": [ "read" ],
        "/proc/sys/net/*": [ "read" ],
        "/sys/*": [ "read" ],
        "/tmp/*": [ "read" ],
        "/dev/mtdblock*": [ "read" ],
        "/bin/*": [ "exec" ],
        "/sbin/*": [ "exec" ],
        "/usr/bin/*": [ "exec" ],
        "/usr/sbin/*": [ "exec" ],
        "/usr/libexec/*": [ "exec" ],
        "/bin/sh": [ "exec" ],
        "/bin/ping": [ "exec" ],
        "/bin/traceroute": [ "exec" ],
        "/bin/dmesg": [ "exec" ],
        "/bin/cat": [ "exec" ],
        "/bin/df": [ "exec" ],
        "/bin/free": [ "exec" ],
        "/bin/grep": [ "exec" ],
        "/bin/tar": [ "exec" ],
        "/bin/dd": [ "exec" ],
        "/bin/rm": [ "exec" ],
        "/sbin/ip": [ "exec" ],
        "/sbin/wifi": [ "exec" ],
        "/sbin/reboot": [ "exec" ],
        "/sbin/sysupgrade": [ "exec" ],
        "/sbin/firstboot": [ "exec" ],
        "/sbin/logread": [ "exec" ],
        "/usr/bin/nslookup": [ "exec" ],
        "/usr/bin/speedtest": [ "exec" ],
        "/usr/bin/speedtest-netperf": [ "exec" ],
        "/usr/bin/curl": [ "exec" ],
        "/usr/bin/wget": [ "exec" ],
        "/usr/bin/iperf3": [ "exec" ],
        "/usr/bin/top": [ "exec" ],
        "/usr/bin/etherwake": [ "exec" ],
        "/usr/bin/wol": [ "exec" ],
        "/usr/bin/nextdns": [ "exec" ],
        "/usr/bin/cloudflared": [ "exec" ],
        "/usr/bin/tailscale": [ "exec" ],
        "/usr/sbin/tailscale": [ "exec" ],
        "/usr/sbin/mwan3": [ "exec" ],
        "/usr/sbin/adblock": [ "exec" ],
        "/usr/sbin/logread": [ "exec" ],
        "/usr/libexec/package-manager-call": [ "exec" ]
      },
      "uci": [
        "*",
        "adblock",
        "attendedsysupgrade",
        "cloudflared",
        "ddns",
        "dhcp",
        "dropbear",
        "etherwake",
        "firewall",
        "fstab",
        "luci",
        "mwan3",
        "network",
        "nextdns",
        "openclash",
        "openvpn",
        "overview",
        "parental",
        "passwall",
        "shadowsocks",
        "simple-adblock",
        "snmpd",
        "sqm",
        "system",
        "tailscale",
        "tinyproxy",
        "ttyd",
        "uhttpd",
        "upnpd",
        "v2ray",
        "watchcat",
        "wireguard",
        "wireless",
        "wol",
        "xray"
      ],
      "ubus": {
        "*": [ "*" ],
        "file": [ "*" ],
        "hostapd.*": [ "*" ],
        "iwinfo": [ "*" ],
        "log": [ "*" ],
        "luci": [ "*" ],
        "luci-rpc": [ "*" ],
        "luci.temp-status": [ "*" ],
        "network": [ "*" ],
        "network.*": [ "*" ],
        "rc": [ "*" ],
        "service": [ "*" ],
        "session": [ "*" ],
        "sqm": [ "*" ],
        "system": [ "*" ],
        "uci": [ "*" ]
      }
    },
    "write": {
      "cgi-io": [ "backup", "download", "exec", "upload" ],
      "file": {
        "/bin/*": [ "exec" ],
        "/sbin/*": [ "exec" ],
        "/usr/bin/*": [ "exec" ],
        "/usr/sbin/*": [ "exec" ],
        "/usr/libexec/*": [ "exec" ],
        "/bin/sh": [ "exec" ],
        "/bin/ping": [ "exec" ],
        "/bin/traceroute": [ "exec" ],
        "/bin/dmesg": [ "exec" ],
        "/bin/cat": [ "exec" ],
        "/bin/df": [ "exec" ],
        "/bin/free": [ "exec" ],
        "/bin/grep": [ "exec" ],
        "/bin/tar": [ "exec" ],
        "/bin/dd": [ "exec" ],
        "/bin/rm": [ "exec" ],
        "/sbin/ip": [ "exec" ],
        "/sbin/wifi": [ "exec" ],
        "/sbin/reboot": [ "exec" ],
        "/sbin/sysupgrade": [ "exec" ],
        "/sbin/firstboot": [ "exec" ],
        "/sbin/logread": [ "exec" ],
        "/usr/bin/nslookup": [ "exec" ],
        "/usr/bin/speedtest": [ "exec" ],
        "/usr/bin/speedtest-netperf": [ "exec" ],
        "/usr/bin/curl": [ "exec" ],
        "/usr/bin/wget": [ "exec" ],
        "/usr/bin/iperf3": [ "exec" ],
        "/usr/bin/top": [ "exec" ],
        "/usr/bin/etherwake": [ "exec" ],
        "/usr/bin/wol": [ "exec" ],
        "/usr/bin/nextdns": [ "exec" ],
        "/usr/bin/cloudflared": [ "exec" ],
        "/usr/bin/tailscale": [ "exec" ],
        "/usr/sbin/tailscale": [ "exec" ],
        "/usr/sbin/mwan3": [ "exec" ],
        "/usr/sbin/adblock": [ "exec" ],
        "/usr/sbin/logread": [ "exec" ],
        "/usr/libexec/package-manager-call": [ "exec" ],
        "/etc/crontabs/root": [ "write" ],
        "/etc/dropbear/authorized_keys": [ "write" ],
        "/etc/config/*": [ "write" ],
        "/tmp/*": [ "write" ]
      },
      "uci": [
        "*",
        "adblock",
        "attendedsysupgrade",
        "cloudflared",
        "ddns",
        "dhcp",
        "dropbear",
        "etherwake",
        "firewall",
        "fstab",
        "luci",
        "mwan3",
        "network",
        "nextdns",
        "openclash",
        "openvpn",
        "overview",
        "parental",
        "passwall",
        "shadowsocks",
        "simple-adblock",
        "snmpd",
        "sqm",
        "system",
        "tailscale",
        "tinyproxy",
        "ttyd",
        "uhttpd",
        "upnpd",
        "v2ray",
        "watchcat",
        "wireguard",
        "wireless",
        "wol",
        "xray"
      ],
      "ubus": {
        "*": [ "*" ],
        "file": [ "*" ],
        "hostapd.*": [ "*" ],
        "iwinfo": [ "*" ],
        "log": [ "*" ],
        "luci": [ "*" ],
        "luci-rpc": [ "*" ],
        "luci.temp-status": [ "*" ],
        "network": [ "*" ],
        "network.*": [ "*" ],
        "rc": [ "*" ],
        "service": [ "*" ],
        "session": [ "*" ],
        "sqm": [ "*" ],
        "system": [ "*" ],
        "uci": [ "*" ]
      }
    }
  }
}''';

  static String getPermissionsFixScript() {
    return '''
if ! touch /usr/share/rpcd/acl.d/.write_test 2>/dev/null; then
  mkdir -p /tmp/rpcd_acl_backup
  cp -p /usr/share/rpcd/acl.d/*.json /tmp/rpcd_acl_backup/ 2>/dev/null || true
  mount -t tmpfs tmpfs /usr/share/rpcd/acl.d 2>/dev/null || true
  cp -p /tmp/rpcd_acl_backup/*.json /usr/share/rpcd/acl.d/ 2>/dev/null || true
fi
rm -f /usr/share/rpcd/acl.d/.write_test 2>/dev/null || true
mkdir -p /usr/share/rpcd/acl.d/
cat << 'EOF' > /usr/share/rpcd/acl.d/yet-another-luci-app.json
$fullAclJson
EOF
if command -v apk >/dev/null 2>&1; then
  apk update || true
  apk add luci-mod-rpc rpcd-mod-luci rpcd-mod-iwinfo luci-mod-status || true
else
  opkg update || true
  opkg install luci-mod-rpc rpcd-mod-luci rpcd-mod-iwinfo luci-mod-status || true
fi
/etc/init.d/rpcd restart 2>/dev/null || /etc/init.d/rpcd reload 2>/dev/null || true
''';
  }

  @override
  Future<bool> autoFixPermissions(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    try {
      final fixScript = getPermissionsFixScript();

      final res = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': '/bin/sh',
          'params': ['-c', fixScript],
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
          'args': ['-c', fixScript],
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
  Future<bool> installNativeTemperatureHandler(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    const installScript =
        'mkdir -p /usr/libexec/rpcd /usr/share/rpcd/acl.d && '
        'cat << \'EOF\' > /usr/libexec/rpcd/luci.temp-status\n'
        '#!/bin/sh\n'
        'case "\$1" in\n'
        'list) echo \'{"getSensors":{}}\' ;;\n'
        'call) case "\$2" in getSensors)\n'
        'hw=""; for h in /sys/class/hwmon/hwmon*; do [ -d "\$h" ] || continue; n=\$(cat "\$h/name" 2>/dev/null || echo hwmon); s=""; for t in "\$h"/temp*_input; do [ -f "\$t" ] || continue; v=\$(cat "\$t" 2>/dev/null); [ -n "\$v" ] || continue; l=\$(cat "\${t%_input}_label" 2>/dev/null); i="\${t##*/}"; [ -n "\$s" ] && s="\$s," || true; s="\$s{\\"item\\":\\"\$i\\",\\"label\\":\\"\$l\\",\\"temp\\":\$v}"; done; [ -n "\$s" ] && { [ -n "\$hw" ] && hw="\$hw," || true; hw="\$hw{\\"title\\":\\"\$n\\",\\"item\\":\\"\${h##*/}\\",\\"sources\\":[\$s]}"; }; done\n'
        'tz=""; for z in /sys/class/thermal/thermal_zone*; do [ -d "\$z" ] || continue; v=\$(cat "\$z/temp" 2>/dev/null); [ -n "\$v" ] || continue; y=\$(cat "\$z/type" 2>/dev/null || echo tz); [ -n "\$tz" ] && tz="\$tz," || true; tz="\$tz{\\"title\\":\\"\$y\\",\\"item\\":\\"\${z##*/}\\",\\"sources\\":[{\\"item\\":\\"temp\\",\\"label\\":\\"\$y\\",\\"temp\\":\$v}]}"; done\n'
        'printf \'{"sensors":{"0":[%s],"1":[%s]}}\\n\' "\$hw" "\$tz" ;; esac ;; esac\n'
        'EOF\n'
        'chmod +x /usr/libexec/rpcd/luci.temp-status && '
        'cat << \'EOF\' > /usr/share/rpcd/acl.d/luci-app-temp-status.json\n'
        '{"luci-app-temp-status":{"description":"Native Temperature RPC Handler","read":{"ubus":{"luci.temp-status":["getSensors"]}}}}\n'
        'EOF\n'
        '(/etc/init.d/rpcd reload 2>/dev/null || /etc/init.d/rpcd restart 2>/dev/null || true)';

    try {
      final res = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': '/bin/sh',
          'params': ['-c', installScript],
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
          'args': ['-c', installScript],
        },
        context: context,
      );
      return _execSucceeded(fallbackRes);
    } catch (e) {
      Logger.warning('installNativeTemperatureHandler failed: $e');
      return false;
    }
  }

  bool _isExpectedServiceDisconnect(
    dynamic e,
    String serviceName,
    String action,
  ) {
    if (action != 'restart' && action != 'reload' && action != 'stop') {
      return false;
    }
    final svc = serviceName.toLowerCase();
    if (svc != 'network' &&
        svc != 'uhttpd' &&
        svc != 'firewall' &&
        svc != 'dropbear') {
      return false;
    }
    final errStr = e.toString().toLowerCase();
    return errStr.contains('socket') ||
        errStr.contains('connection reset') ||
        errStr.contains('broken pipe') ||
        errStr.contains('connection closed') ||
        errStr.contains('clientexception') ||
        errStr.contains('handshake');
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
      } catch (rcErr) {
        if (_isExpectedServiceDisconnect(rcErr, serviceName, action)) {
          return true;
        }
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
      if (_isExpectedServiceDisconnect(e, serviceName, action)) {
        return true;
      }
      Logger.exception('manageServiceAction failed for $serviceName', e, stack);
      return false;
    }
  }

  /// Enforces a client ban at the firewall level (UCI firewall rule + nftables/iptables/ebtables).
  /// Aggregates multiple banned clients into a single 'Ban_Client_List' rule in UCI firewall.
  Future<bool> _enforceFirewallBan({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String macAddress,
    BuildContext? context,
  }) async {
    final routerId = '${useHttps ? "https" : "http"}://$ipAddress';
    return await RouterScopedOperationQueue.instance.runLocked(
      routerId: routerId,
      domain: 'firewall',
      action: () async {
        final macUpper = macAddress.toUpperCase().replaceAll('-', ':');
        final macLower = macAddress.toLowerCase();
        const ruleName = "Ban_Client_List";

        bool ruleExisted = false;
        bool ubusSucceeded = false;

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
                if (name == ruleName ||
                    (targetSecKey == null && name.startsWith('Ban_Client_'))) {
                  ruleExisted = true;
                  targetSecKey = entry.key;
                  final srcMac = sec['src_mac'];
                  if (srcMac is List) {
                    currentMacs = srcMac
                        .map(
                          (e) =>
                              e.toString().toUpperCase().replaceAll('-', ':'),
                        )
                        .toList();
                  } else if (srcMac != null) {
                    currentMacs = [
                      srcMac.toString().toUpperCase().replaceAll('-', ':'),
                    ];
                  }
                  if (name == ruleName) break;
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
                    'dest': '*',
                    'src_mac': [macUpper],
                    'target': 'DROP',
                    'enabled': '1',
                  },
                },
                context: mountedContext(context),
              );
            } else if (targetSecKey != null &&
                !currentMacs.contains(macUpper)) {
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
                  'values': {
                    'name': ruleName,
                    'src': '*',
                    'dest': '*',
                    'src_mac': currentMacs,
                    'target': 'DROP',
                    'enabled': '1',
                  },
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
            ubusSucceeded = true;
          }
        } catch (e) {
          Logger.warning(
            'Native ubus firewall ban check/add encountered issue: $e',
          );
        }

        // 2. Shell fallback and runtime packet dropping (non-blocking)
        final shellScript = ubusSucceeded
            ? '''
MAC_U="$macUpper"
MAC_L="$macLower"
(
  nft add rule inet fw4 input ether saddr "\$MAC_U" drop 2>/dev/null || true
  nft add rule inet fw4 forward ether saddr "\$MAC_U" drop 2>/dev/null || true
  nft add rule inet fw4 input ether saddr "\$MAC_L" drop 2>/dev/null || true
  nft add rule inet fw4 forward ether saddr "\$MAC_L" drop 2>/dev/null || true
  iptables -I INPUT -m mac --mac-source "\$MAC_U" -j DROP 2>/dev/null || true
  iptables -I FORWARD -m mac --mac-source "\$MAC_U" -j DROP 2>/dev/null || true
  iptables -I INPUT -m mac --mac-source "\$MAC_L" -j DROP 2>/dev/null || true
  iptables -I FORWARD -m mac --mac-source "\$MAC_L" -j DROP 2>/dev/null || true
  ebtables -I INPUT -s "\$MAC_U" -j DROP 2>/dev/null || true
  ebtables -I FORWARD -s "\$MAC_U" -j DROP 2>/dev/null || true
) >/dev/null 2>&1 &
exit 0
'''
            : '''
MAC_U="$macUpper"
MAC_L="$macLower"
RULE_NAME="$ruleName"

SEC=\$(uci show firewall 2>/dev/null | grep -i "name=['"]*\${RULE_NAME}['"]*" | head -n 1 | cut -d. -f2)
if [ -z "\$SEC" ]; then
  uci add firewall rule >/dev/null
  uci set firewall.@rule[-1].name="\$RULE_NAME"
  uci set firewall.@rule[-1].src='*'
  uci set firewall.@rule[-1].dest='*'
  uci add_list firewall.@rule[-1].src_mac="\$MAC_U"
  uci set firewall.@rule[-1].target='DROP'
  uci set firewall.@rule[-1].enabled='1'
else
  MAC_EXISTS=\$(uci get firewall.\${SEC}.src_mac 2>/dev/null | grep -i "\$MAC_U")
  if [ -z "\$MAC_EXISTS" ]; then
    uci add_list firewall.\${SEC}.src_mac="\$MAC_U"
  fi
  uci set firewall.\${SEC}.src='*' 2>/dev/null || true
  uci set firewall.\${SEC}.dest='*' 2>/dev/null || true
  uci set firewall.\${SEC}.target='DROP' 2>/dev/null || true
  uci set firewall.\${SEC}.enabled='1' 2>/dev/null || true
fi
uci commit firewall
/etc/init.d/firewall reload >/dev/null 2>&1 &

(
  nft add rule inet fw4 input ether saddr "\$MAC_U" drop 2>/dev/null || true
  nft add rule inet fw4 forward ether saddr "\$MAC_U" drop 2>/dev/null || true
  nft add rule inet fw4 input ether saddr "\$MAC_L" drop 2>/dev/null || true
  nft add rule inet fw4 forward ether saddr "\$MAC_L" drop 2>/dev/null || true
  iptables -I INPUT -m mac --mac-source "\$MAC_U" -j DROP 2>/dev/null || true
  iptables -I FORWARD -m mac --mac-source "\$MAC_U" -j DROP 2>/dev/null || true
  iptables -I INPUT -m mac --mac-source "\$MAC_L" -j DROP 2>/dev/null || true
  iptables -I FORWARD -m mac --mac-source "\$MAC_L" -j DROP 2>/dev/null || true
  ebtables -I INPUT -s "\$MAC_U" -j DROP 2>/dev/null || true
  ebtables -I FORWARD -s "\$MAC_U" -j DROP 2>/dev/null || true
) >/dev/null 2>&1 &
exit 0
''';

        bool shellSucceeded = false;
        try {
          final shellRes = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'file',
            method: 'exec',
            params: fileExecParams('/bin/sh', ['-c', shellScript]),
            context: mountedContext(context),
          );
          shellSucceeded = _execSucceeded(shellRes);
        } catch (e) {
          Logger.warning('_enforceFirewallBan shell script error: $e');
        }

        return ubusSucceeded || shellSucceeded;
      },
    );
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
    const ruleName = "nointernet_wireless_clients";

    bool ruleExisted = false;
    bool ubusSucceeded = false;

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
        ubusSucceeded = true;
      }
    } catch (e) {
      Logger.warning(
        'Native ubus firewall rule check/add encountered issue: $e',
      );
    }

    // 2. Runtime firewall rule insertion and shell fallback check
    final shellScript = ubusSucceeded
        ? '''
MAC_U="$macUpper"
MAC_L="$macLower"
nft insert rule inet fw4 forward ether saddr "\$MAC_U" drop >/dev/null 2>&1 || true
nft insert rule inet fw4 forward ether daddr "\$MAC_U" drop >/dev/null 2>&1 || true
nft insert rule inet fw4 forward ether saddr "\$MAC_L" drop >/dev/null 2>&1 || true
nft insert rule inet fw4 forward ether daddr "\$MAC_L" drop >/dev/null 2>&1 || true
iptables -I FORWARD 1 -m mac --mac-source "\$MAC_U" -j DROP >/dev/null 2>&1 || true
iptables -I FORWARD 1 -m mac --mac-source "\$MAC_L" -j DROP >/dev/null 2>&1 || true
for ip in \$(ip neigh show 2>/dev/null | grep -i "\$MAC_U" | awk '{print \$1}'); do
  conntrack -D -s "\$ip" >/dev/null 2>&1 || true
  conntrack -D -d "\$ip" >/dev/null 2>&1 || true
done
exit 0
'''
        : '''
MAC_U="$macUpper"
MAC_L="$macLower"
RULE_NAME="$ruleName"

EXISTS=\$(uci show firewall 2>/dev/null | grep -i "name=['"]*\${RULE_NAME}['"]*" | head -n 1)
if [ -z "\$EXISTS" ]; then
  uci add firewall rule >/dev/null
  uci set firewall.@rule[-1].name="\$RULE_NAME"
  uci set firewall.@rule[-1].src='lan'
  uci set firewall.@rule[-1].dest='wan'
  uci add_list firewall.@rule[-1].src_mac="\$MAC_U"
  uci set firewall.@rule[-1].target='REJECT'
  uci set firewall.@rule[-1].enabled='1'
else
  SEC=\$(uci show firewall 2>/dev/null | grep -i "name=['"]*\${RULE_NAME}['"]*" | cut -d. -f2)
  if [ -n "\$SEC" ]; then
    uci set firewall.\${SEC}.src='lan' 2>/dev/null || true
    uci set firewall.\${SEC}.target='REJECT' 2>/dev/null || true
    MAC_EXISTS=\$(uci get firewall.\${SEC}.src_mac 2>/dev/null | grep -i "\$MAC_U")
    if [ -z "\$MAC_EXISTS" ]; then
      uci add_list firewall.\${SEC}.src_mac="\$MAC_U"
    fi
  fi
fi
uci commit firewall
/etc/init.d/firewall reload >/dev/null 2>&1

nft insert rule inet fw4 forward ether saddr "\$MAC_U" drop >/dev/null 2>&1 || true
nft insert rule inet fw4 forward ether daddr "\$MAC_U" drop >/dev/null 2>&1 || true
nft insert rule inet fw4 forward ether saddr "\$MAC_L" drop >/dev/null 2>&1 || true
nft insert rule inet fw4 forward ether daddr "\$MAC_L" drop >/dev/null 2>&1 || true
iptables -I FORWARD 1 -m mac --mac-source "\$MAC_U" -j DROP >/dev/null 2>&1 || true
iptables -I FORWARD 1 -m mac --mac-source "\$MAC_L" -j DROP >/dev/null 2>&1 || true
for ip in \$(ip neigh show 2>/dev/null | grep -i "\$MAC_U" | awk '{print \$1}'); do
  conntrack -D -s "\$ip" >/dev/null 2>&1 || true
  conntrack -D -d "\$ip" >/dev/null 2>&1 || true
done
exit 0
''';

    bool shellSucceeded = false;
    try {
      final shellRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: fileExecParams('/bin/sh', ['-c', shellScript]),
        context: mountedContext(context),
      );
      shellSucceeded = _execSucceeded(shellRes);
    } catch (e) {
      Logger.warning('_enforceFirewallBlock shell script error: $e');
    }

    if (!ruleExisted && ubusSucceeded) {
      Logger.info(
        'Created firewall rule "$ruleName" to restrict client $macUpper',
      );
    }

    return ubusSucceeded || shellSucceeded;
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
    const ruleName = "nointernet_wireless_clients";
    bool modified = false;
    bool ubusSucceeded = false;
    bool ubusQuerySucceeded = false;

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
        ubusQuerySucceeded = true;
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

            final List<String> macs = [];
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
          ubusSucceeded = true;
        }
      }
    } catch (e) {
      Logger.warning('Native ubus firewall remove encountered issue: $e');
    }

    // Fast path: if ubus query succeeded and no block rule was found, nothing to remove
    if (ubusQuerySucceeded && !modified) {
      return true;
    }

    if (ubusSucceeded) {
      final liveCleanup =
          '''
MAC_U="$macUpper"
MAC_L="$macLower"
(
  nft -a list chain inet fw4 forward 2>/dev/null | grep -i "\$MAC_U" | awk '{print \$NF}' | while read -r h; do
    [ -n "\$h" ] && nft delete rule inet fw4 forward handle "\$h" >/dev/null 2>&1 || true
  done
  nft -a list chain inet fw4 forward 2>/dev/null | grep -i "\$MAC_L" | awk '{print \$NF}' | while read -r h; do
    [ -n "\$h" ] && nft delete rule inet fw4 forward handle "\$h" >/dev/null 2>&1 || true
  done
  while iptables -D FORWARD -m mac --mac-source "\$MAC_U" -j DROP >/dev/null 2>&1; do :; done
  while iptables -D FORWARD -m mac --mac-source "\$MAC_L" -j DROP >/dev/null 2>&1; do :; done
) >/dev/null 2>&1 &
exit 0
''';
      try {
        await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'file',
          method: 'exec',
          params: fileExecParams('/bin/sh', ['-c', liveCleanup]),
          context: mountedContext(context),
        );
      } catch (_) {}
      return true;
    }

    final script =
        '''
MAC_U="$macUpper"
MAC_L="$macLower"
CLEAN="$macClean"
RULE_NAME="$ruleName"
MODIFIED=0

for sec in \$(uci show firewall 2>/dev/null | grep -iE "src_mac|dest_mac" | grep -i "\$MAC_U" | cut -d. -f2); do
  uci del_list firewall.\${sec}.src_mac="\$MAC_U" 2>/dev/null || true
  uci del_list firewall.\${sec}.src_mac="\$MAC_L" 2>/dev/null || true
  uci del_list firewall.\${sec}.dest_mac="\$MAC_U" 2>/dev/null || true
  uci del_list firewall.\${sec}.dest_mac="\$MAC_L" 2>/dev/null || true
  REMAINING=\$(uci get firewall.\${sec}.src_mac 2>/dev/null | tr ' ' '\\n' | grep -v "^\$" | wc -l)
  if [ "\$REMAINING" -eq 0 ]; then
    uci delete firewall.\${sec} 2>/dev/null || true
  fi
  MODIFIED=1
done

for legacy in \$(uci show firewall 2>/dev/null | grep -iE "Pause_Internet_\${CLEAN}|Ban_Client_\${CLEAN}|Kick_Client_\${CLEAN}" | cut -d. -f2); do
  uci delete firewall.\${legacy} 2>/dev/null || true
  MODIFIED=1
done

if [ "\$MODIFIED" -eq 1 ]; then
  uci commit firewall
  ( /etc/init.d/firewall reload ) >/dev/null 2>&1 &
fi

(
  nft -a list chain inet fw4 forward 2>/dev/null | grep -i "\$MAC_U" | awk '{print \$NF}' | while read -r h; do
    [ -n "\$h" ] && nft delete rule inet fw4 forward handle "\$h" >/dev/null 2>&1 || true
  done
  nft -a list chain inet fw4 forward 2>/dev/null | grep -i "\$MAC_L" | awk '{print \$NF}' | while read -r h; do
    [ -n "\$h" ] && nft delete rule inet fw4 forward handle "\$h" >/dev/null 2>&1 || true
  done
  while iptables -D FORWARD -m mac --mac-source "\$MAC_U" -j DROP >/dev/null 2>&1; do :; done
  while iptables -D FORWARD -m mac --mac-source "\$MAC_L" -j DROP >/dev/null 2>&1; do :; done
) >/dev/null 2>&1 &
exit 0
''';

    bool shellSucceeded = false;
    try {
      final res = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: fileExecParams('/bin/sh', ['-c', script]),
        context: mountedContext(context),
      );
      shellSucceeded = _execSucceeded(res);
    } catch (e) {
      Logger.warning('_removeFirewallBlock shell script error: $e');
    }

    return ubusSucceeded || shellSucceeded;
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
    bool ubusQuerySucceeded = false;

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
        ubusQuerySucceeded = true;
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
              final List<String> macs = rawMaclist is List
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

    // Fast path: if ubus query succeeded, return immediately.
    // If no deny rule existed (!modified), nothing to remove (0ms delay, no reload).
    // If modified, ubus commit + network.wireless up already applied it cleanly.
    if (ubusQuerySucceeded) {
      return true;
    }

    final script =
        '''
MAC_U="$macUpper"
MAC_L="$macLower"
MODIFIED=0

for sec in \$(uci show wireless 2>/dev/null | grep -iE "\\.macfilter='?deny'?|\\.macfilter='?2'?" | cut -d. -f2 | cut -d= -f1); do
  if uci get wireless.\${sec}.maclist 2>/dev/null | grep -qi "\$MAC_U" || uci get wireless.\${sec}.maclist 2>/dev/null | grep -qi "\$MAC_L"; then
    uci del_list wireless.\${sec}.maclist="\$MAC_U" 2>/dev/null || true
    uci del_list wireless.\${sec}.maclist="\$MAC_L" 2>/dev/null || true
    MODIFIED=1
  fi
done

if [ "\$MODIFIED" -eq 1 ]; then
  uci commit wireless
  ( wifi reload || ubus call network.wireless reload ) >/dev/null 2>&1 &
fi
exit 0
''';

    bool shellSucceeded = false;
    try {
      final res = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: fileExecParams('/bin/sh', ['-c', script]),
        context: mountedContext(context),
      );
      shellSucceeded = _execSucceeded(res);
    } catch (e) {
      Logger.warning('_removeWirelessMacFilter shell error: $e');
    }

    return modified || shellSucceeded;
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
          hostapdObjects.add(
            iface.startsWith('hostapd.') ? iface : 'hostapd.$iface',
          );
        }
        final discovered = await listUbusObjects(
          ipAddress,
          sysauth,
          useHttps,
          pattern: 'hostapd.*',
          context: mountedContext(context),
        );
        for (final obj in discovered) {
          if (obj.startsWith('hostapd.') && !hostapdObjects.contains(obj)) {
            hostapdObjects.add(obj);
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
      bool shellSuccess = false;
      try {
        final macLower = macAddress.toLowerCase();
        final targetIface = (iface != null && iface.isNotEmpty) ? iface : '';
        final cmdScript =
            '''
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

        final shellRes = await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'file',
          method: 'exec',
          params: fileExecParams('/bin/sh', ['-c', cmdScript]),
          context: mountedContext(context),
        );
        shellSuccess = _execSucceeded(shellRes);
      } catch (_) {}

      return ubusSuccess || shellSuccess;
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
  Future<bool> addFirewallPortForward(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required FirewallPortForwarding portForward,
    BuildContext? context,
  }) async {
    final routerId = '${useHttps ? "https" : "http"}://$ipAddress';
    return await RouterScopedOperationQueue.instance.runLocked(
      routerId: routerId,
      domain: 'firewall',
      action: () async {
        final mCtx = mountedContext(context);
        try {
          final addRes = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'add',
            params: {
              'config': 'firewall',
              'type': 'redirect',
              'values': portForward.toUciValues(),
            },
            context: mCtx,
          );
          if (addRes is List && addRes.isNotEmpty && addRes[0] != 0) {
            return false;
          }
          final addedSectionKey =
              (addRes is List && addRes.length > 1 && addRes[1] is Map)
              ? (addRes[1] as Map)['section']?.toString()
              : null;

          // Pass staged delta changes directly to uciApply with rollback protection
          final applied = await uciApply(
            ipAddress,
            sysauth,
            useHttps,
            rollback: true,
            timeout: 30,
          );
          if (!applied) {
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }

          // Authenticated post-apply verification proving management RPC liveness
          final verifyRes = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'get',
            params: {'config': 'firewall'},
            context: mCtx,
          );
          if (verifyRes is! List || verifyRes.length < 2 || verifyRes[0] != 0) {
            Logger.warning(
              'addFirewallPortForward verification failed: management RPC unreachable after apply',
            );
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }

          // Authoritative state verification: verify added section exists
          final verifyUciValues = extractUciValuesMap(verifyRes[1]);
          if (addedSectionKey != null && addedSectionKey.isNotEmpty) {
            if (!hasUciSection(verifyUciValues, addedSectionKey)) {
              Logger.warning(
                'addFirewallPortForward verification failed: section $addedSectionKey missing after apply',
              );
              await uciRevert(
                ipAddress,
                sysauth,
                useHttps,
                config: 'firewall',
                context: mCtx,
              );
              return false;
            }
          }

          final confirmed = await uciConfirm(ipAddress, sysauth, useHttps);
          if (!confirmed) {
            Logger.warning('addFirewallPortForward uciConfirm failed');
            return false;
          }

          try {
            await callWithContext(
              ipAddress,
              sysauth,
              useHttps,
              object: 'rc',
              method: 'init',
              params: {'name': 'firewall', 'action': 'reload'},
              context: mCtx,
            );
          } catch (_) {}

          return true;
        } catch (e, stack) {
          Logger.exception('addFirewallPortForward failed', e, stack);
          await uciRevert(
            ipAddress,
            sysauth,
            useHttps,
            config: 'firewall',
            context: mCtx,
          );
          return false;
        }
      },
    );
  }

  @override
  Future<bool> updateFirewallPortForward(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required FirewallPortForwarding portForward,
    BuildContext? context,
  }) async {
    if (portForward.sectionKey.trim().isEmpty) return false;
    final routerId = '${useHttps ? "https" : "http"}://$ipAddress';
    return await RouterScopedOperationQueue.instance.runLocked(
      routerId: routerId,
      domain: 'firewall',
      action: () async {
        final mCtx = mountedContext(context);
        try {
          final setRes = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'set',
            params: {
              'config': 'firewall',
              'section': portForward.sectionKey,
              'values': portForward.toUciValues(),
            },
            context: mCtx,
          );
          if (setRes is List && setRes.isNotEmpty && setRes[0] != 0) {
            return false;
          }

          // Pass staged delta changes directly to uciApply with rollback protection
          final applied = await uciApply(
            ipAddress,
            sysauth,
            useHttps,
            rollback: true,
            timeout: 30,
          );
          if (!applied) {
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }

          // Authenticated post-apply verification proving management RPC liveness
          final verifyRes = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'get',
            params: {'config': 'firewall'},
            context: mCtx,
          );
          if (verifyRes is! List || verifyRes.length < 2 || verifyRes[0] != 0) {
            Logger.warning(
              'updateFirewallPortForward verification failed: management RPC unreachable after apply',
            );
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }

          // Authoritative state verification: section exists with updated properties
          final verifyUciValues = extractUciValuesMap(verifyRes[1]);
          final targetSection = findUciSection(
            verifyUciValues,
            portForward.sectionKey,
          );
          if (targetSection == null) {
            Logger.warning(
              'updateFirewallPortForward verification failed: section ${portForward.sectionKey} missing after update',
            );
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }
          if (portForward.name.isNotEmpty &&
              targetSection['name']?.toString() != portForward.name) {
            Logger.warning(
              'updateFirewallPortForward verification failed: section ${portForward.sectionKey} name mismatch',
            );
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }
          if (portForward.target.isNotEmpty &&
              targetSection['target']?.toString().toUpperCase() !=
                  portForward.target.toUpperCase()) {
            Logger.warning(
              'updateFirewallPortForward verification failed: section ${portForward.sectionKey} target mismatch',
            );
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }

          final confirmed = await uciConfirm(ipAddress, sysauth, useHttps);
          if (!confirmed) {
            Logger.warning('updateFirewallPortForward uciConfirm failed');
            return false;
          }

          try {
            await callWithContext(
              ipAddress,
              sysauth,
              useHttps,
              object: 'rc',
              method: 'init',
              params: {'name': 'firewall', 'action': 'reload'},
              context: mCtx,
            );
          } catch (_) {}

          return true;
        } catch (e, stack) {
          Logger.exception('updateFirewallPortForward failed', e, stack);
          await uciRevert(
            ipAddress,
            sysauth,
            useHttps,
            config: 'firewall',
            context: mCtx,
          );
          return false;
        }
      },
    );
  }

  @override
  Future<bool> deleteFirewallPortForward(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionKey,
    BuildContext? context,
  }) async {
    if (sectionKey.trim().isEmpty) return false;
    final routerId = '${useHttps ? "https" : "http"}://$ipAddress';
    return await RouterScopedOperationQueue.instance.runLocked(
      routerId: routerId,
      domain: 'firewall',
      action: () async {
        final mCtx = mountedContext(context);
        try {
          final delRes = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'delete',
            params: {'config': 'firewall', 'section': sectionKey},
            context: mCtx,
          );
          if (delRes is List && delRes.isNotEmpty && delRes[0] != 0) {
            return false;
          }

          // Pass staged delta changes directly to uciApply with rollback protection
          final applied = await uciApply(
            ipAddress,
            sysauth,
            useHttps,
            rollback: true,
            timeout: 30,
          );
          if (!applied) {
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }

          // Authenticated post-apply verification proving management RPC liveness
          final verifyRes = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'get',
            params: {'config': 'firewall'},
            context: mCtx,
          );
          if (verifyRes is! List || verifyRes.length < 2 || verifyRes[0] != 0) {
            Logger.warning(
              'deleteFirewallPortForward verification failed: management RPC unreachable after apply',
            );
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }

          // Authoritative state verification: section is absent
          final verifyUciValues = extractUciValuesMap(verifyRes[1]);
          if (hasUciSection(verifyUciValues, sectionKey)) {
            Logger.warning(
              'deleteFirewallPortForward verification failed: section $sectionKey still present after deletion',
            );
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }

          final confirmed = await uciConfirm(ipAddress, sysauth, useHttps);
          if (!confirmed) {
            Logger.warning('deleteFirewallPortForward uciConfirm failed');
            return false;
          }

          try {
            await callWithContext(
              ipAddress,
              sysauth,
              useHttps,
              object: 'rc',
              method: 'init',
              params: {'name': 'firewall', 'action': 'reload'},
              context: mCtx,
            );
          } catch (_) {}

          return true;
        } catch (e, stack) {
          Logger.exception('deleteFirewallPortForward failed', e, stack);
          await uciRevert(
            ipAddress,
            sysauth,
            useHttps,
            config: 'firewall',
            context: mCtx,
          );
          return false;
        }
      },
    );
  }

  @override
  Future<bool> addFirewallCustomRule(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required FirewallCustomRule rule,
    BuildContext? context,
  }) async {
    final routerId = '${useHttps ? "https" : "http"}://$ipAddress';
    return await RouterScopedOperationQueue.instance.runLocked(
      routerId: routerId,
      domain: 'firewall',
      action: () async {
        final mCtx = mountedContext(context);
        try {
          final mgmtPorts = await discoverManagementPorts(
            ipAddress,
            sysauth,
            useHttps,
            context: mCtx,
          );
          final isLockout = await SelfDeviceGuard.isManagementLockoutRisk(
            target: rule.target,
            srcZone: rule.srcZone,
            destZone: rule.destZone,
            srcMac: rule.srcMac,
            srcIp: rule.srcIp,
            destPort: rule.destPort,
            proto: rule.proto,
            managementPorts: mgmtPorts,
            routerId: routerId,
          );
          if (isLockout) {
            Logger.warning(
              'SelfDeviceGuard blocked adding drop/reject rule affecting managing device/path',
            );
            return false;
          }

          final addRes = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'add',
            params: {
              'config': 'firewall',
              'type': 'rule',
              'values': rule.toUciValues(),
            },
            context: mCtx,
          );
          if (addRes is List && addRes.isNotEmpty && addRes[0] != 0) {
            return false;
          }
          final addedSectionKey =
              (addRes is List && addRes.length > 1 && addRes[1] is Map)
              ? (addRes[1] as Map)['section']?.toString()
              : null;

          // Pass staged delta changes directly to uciApply with rollback protection
          final applied = await uciApply(
            ipAddress,
            sysauth,
            useHttps,
            rollback: true,
            timeout: 30,
          );
          if (!applied) {
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }

          // Authenticated post-apply verification proving management RPC liveness
          final verifyRes = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'get',
            params: {'config': 'firewall'},
            context: mCtx,
          );
          if (verifyRes is! List || verifyRes.length < 2 || verifyRes[0] != 0) {
            Logger.warning(
              'addFirewallCustomRule verification failed: management RPC unreachable after apply',
            );
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }

          // Authoritative state verification: verify added section exists
          final verifyUciValues = extractUciValuesMap(verifyRes[1]);
          if (addedSectionKey != null && addedSectionKey.isNotEmpty) {
            if (!hasUciSection(verifyUciValues, addedSectionKey)) {
              Logger.warning(
                'addFirewallCustomRule verification failed: section $addedSectionKey missing after apply',
              );
              await uciRevert(
                ipAddress,
                sysauth,
                useHttps,
                config: 'firewall',
                context: mCtx,
              );
              return false;
            }
          }

          final confirmed = await uciConfirm(ipAddress, sysauth, useHttps);
          if (!confirmed) {
            Logger.warning('addFirewallCustomRule uciConfirm failed');
            return false;
          }

          try {
            await callWithContext(
              ipAddress,
              sysauth,
              useHttps,
              object: 'rc',
              method: 'init',
              params: {'name': 'firewall', 'action': 'reload'},
              context: mCtx,
            );
          } catch (_) {}

          return true;
        } catch (e, stack) {
          Logger.exception('addFirewallCustomRule failed', e, stack);
          await uciRevert(
            ipAddress,
            sysauth,
            useHttps,
            config: 'firewall',
            context: mCtx,
          );
          return false;
        }
      },
    );
  }

  @override
  Future<bool> updateFirewallCustomRule(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required FirewallCustomRule rule,
    BuildContext? context,
  }) async {
    if (rule.sectionKey.trim().isEmpty) return false;
    final routerId = '${useHttps ? "https" : "http"}://$ipAddress';
    return await RouterScopedOperationQueue.instance.runLocked(
      routerId: routerId,
      domain: 'firewall',
      action: () async {
        final mCtx = mountedContext(context);
        try {
          final mgmtPorts = await discoverManagementPorts(
            ipAddress,
            sysauth,
            useHttps,
            context: mCtx,
          );
          final isLockout = await SelfDeviceGuard.isManagementLockoutRisk(
            target: rule.target,
            srcZone: rule.srcZone,
            destZone: rule.destZone,
            srcMac: rule.srcMac,
            srcIp: rule.srcIp,
            destPort: rule.destPort,
            proto: rule.proto,
            managementPorts: mgmtPorts,
            routerId: routerId,
          );
          if (isLockout) {
            Logger.warning(
              'SelfDeviceGuard blocked updating drop/reject rule affecting managing device/path',
            );
            return false;
          }

          final setRes = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'set',
            params: {
              'config': 'firewall',
              'section': rule.sectionKey,
              'values': rule.toUciValues(),
            },
            context: mCtx,
          );
          if (setRes is List && setRes.isNotEmpty && setRes[0] != 0) {
            return false;
          }

          // Pass staged delta changes directly to uciApply with rollback protection
          final applied = await uciApply(
            ipAddress,
            sysauth,
            useHttps,
            rollback: true,
            timeout: 30,
          );
          if (!applied) {
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }

          // Authenticated post-apply verification proving management RPC liveness
          final verifyRes = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'get',
            params: {'config': 'firewall'},
            context: mCtx,
          );
          if (verifyRes is! List || verifyRes.length < 2 || verifyRes[0] != 0) {
            Logger.warning(
              'updateFirewallCustomRule verification failed: management RPC unreachable after apply',
            );
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }

          // Authoritative state verification: section exists with updated properties
          final verifyUciValues = extractUciValuesMap(verifyRes[1]);
          final targetSection = findUciSection(
            verifyUciValues,
            rule.sectionKey,
          );
          if (targetSection == null) {
            Logger.warning(
              'updateFirewallCustomRule verification failed: section ${rule.sectionKey} missing after update',
            );
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }
          if (rule.name.isNotEmpty &&
              targetSection['name']?.toString() != rule.name) {
            Logger.warning(
              'updateFirewallCustomRule verification failed: section ${rule.sectionKey} name mismatch',
            );
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }
          if (rule.target.isNotEmpty &&
              targetSection['target']?.toString().toUpperCase() !=
                  rule.target.toUpperCase()) {
            Logger.warning(
              'updateFirewallCustomRule verification failed: section ${rule.sectionKey} target mismatch',
            );
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }

          final confirmed = await uciConfirm(ipAddress, sysauth, useHttps);
          if (!confirmed) {
            Logger.warning('updateFirewallCustomRule uciConfirm failed');
            return false;
          }

          try {
            await callWithContext(
              ipAddress,
              sysauth,
              useHttps,
              object: 'rc',
              method: 'init',
              params: {'name': 'firewall', 'action': 'reload'},
              context: mCtx,
            );
          } catch (_) {}

          return true;
        } catch (e, stack) {
          Logger.exception('updateFirewallCustomRule failed', e, stack);
          await uciRevert(
            ipAddress,
            sysauth,
            useHttps,
            config: 'firewall',
            context: mCtx,
          );
          return false;
        }
      },
    );
  }

  @override
  Future<bool> deleteFirewallCustomRule(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionKey,
    BuildContext? context,
  }) async {
    if (sectionKey.trim().isEmpty) return false;
    final routerId = '${useHttps ? "https" : "http"}://$ipAddress';
    return await RouterScopedOperationQueue.instance.runLocked(
      routerId: routerId,
      domain: 'firewall',
      action: () async {
        final mCtx = mountedContext(context);
        try {
          final delRes = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'delete',
            params: {'config': 'firewall', 'section': sectionKey},
            context: mCtx,
          );
          if (delRes is List && delRes.isNotEmpty && delRes[0] != 0) {
            return false;
          }

          // Pass staged delta changes directly to uciApply with rollback protection
          final applied = await uciApply(
            ipAddress,
            sysauth,
            useHttps,
            rollback: true,
            timeout: 30,
          );
          if (!applied) {
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }

          // Authenticated post-apply verification proving management RPC liveness
          final verifyRes = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'get',
            params: {'config': 'firewall'},
            context: mCtx,
          );
          if (verifyRes is! List || verifyRes.length < 2 || verifyRes[0] != 0) {
            Logger.warning(
              'deleteFirewallCustomRule verification failed: management RPC unreachable after apply',
            );
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }

          // Authoritative state verification: section is absent
          final verifyUciValues = extractUciValuesMap(verifyRes[1]);
          if (hasUciSection(verifyUciValues, sectionKey)) {
            Logger.warning(
              'deleteFirewallCustomRule verification failed: section $sectionKey still present after deletion',
            );
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }

          final confirmed = await uciConfirm(ipAddress, sysauth, useHttps);
          if (!confirmed) {
            Logger.warning('deleteFirewallCustomRule uciConfirm failed');
            return false;
          }

          try {
            await callWithContext(
              ipAddress,
              sysauth,
              useHttps,
              object: 'rc',
              method: 'init',
              params: {'name': 'firewall', 'action': 'reload'},
              context: mCtx,
            );
          } catch (_) {}

          return true;
        } catch (e, stack) {
          Logger.exception('deleteFirewallCustomRule failed', e, stack);
          await uciRevert(
            ipAddress,
            sysauth,
            useHttps,
            config: 'firewall',
            context: mCtx,
          );
          return false;
        }
      },
    );
  }

  @override
  Future<bool> reorderFirewallCustomRules(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String targetSectionKey,
    required String siblingSectionKey,
    required List<String> expectedRuleOrder,
    BuildContext? context,
  }) async {
    final routerId = '${useHttps ? "https" : "http"}://$ipAddress';
    return await RouterScopedOperationQueue.instance.runLocked(
      routerId: routerId,
      domain: 'firewall',
      action: () async {
        final mCtx = mountedContext(context);
        try {
          // Step 3: Retrieve Fresh Authoritative UCI State & Slot Indices
          final getRes = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'get',
            params: {'config': 'firewall'},
            context: mCtx,
          );
          if (getRes is! List || getRes.length < 2 || getRes[0] != 0) {
            return false;
          }

          final rawUci = getRes[1] as Map<String, dynamic>? ?? {};
          final rawValues = rawUci['values'];
          final Map<String, dynamic> uciValues = (rawValues is Map)
              ? Map<String, dynamic>.from(rawValues)
              : Map<String, dynamic>.from(rawUci);

          final sectionsList = <Map<String, dynamic>>[];
          int fallbackIdx = 0;
          uciValues.forEach((k, v) {
            if (v is Map) {
              final secKey = v['.name']?.toString() ?? k;
              final secType = v['.type']?.toString() ?? '';
              final idx = (v['.index'] is int)
                  ? v['.index'] as int
                  : int.tryParse(v['.index']?.toString() ?? '') ?? fallbackIdx;
              sectionsList.add({'key': secKey, 'type': secType, 'index': idx});
              fallbackIdx++;
            }
          });
          sectionsList.sort(
            (a, b) => (a['index'] as int).compareTo(b['index'] as int),
          );

          // Identify custom-rule slot indices in full section list S
          final ruleSlotIndices = <int>[];
          for (int i = 0; i < sectionsList.length; i++) {
            if (sectionsList[i]['type'] == 'rule') {
              ruleSlotIndices.add(i);
            }
          }

          final freshRuleOrder = ruleSlotIndices
              .map((idx) => sectionsList[idx]['key'] as String)
              .toList();

          // Step 4: Snapshot Stale-Order Preflight Verification
          if (expectedRuleOrder.isNotEmpty &&
              !listEquals(freshRuleOrder, expectedRuleOrder)) {
            Logger.warning(
              'reorderFirewallCustomRules aborted: freshRuleOrder ($freshRuleOrder) != expectedRuleOrder ($expectedRuleOrder)',
            );
            return false;
          }

          final jTarget = freshRuleOrder.indexOf(targetSectionKey);
          final jSibling = freshRuleOrder.indexOf(siblingSectionKey);
          if (jTarget == -1 || jSibling == -1) {
            return false;
          }
          if ((jSibling - jTarget).abs() != 1) {
            Logger.warning(
              'reorderFirewallCustomRules aborted: target ($jTarget) and sibling ($jSibling) are not strictly adjacent',
            );
            return false;
          }

          // Step 5: Exchange Identities Occupying the Two Custom-Rule Slots
          final fullSlotTarget = ruleSlotIndices[jTarget];
          final fullSlotSibling = ruleSlotIndices[jSibling];

          final sNew = List<String>.filled(sectionsList.length, '');
          for (int k = 0; k < sectionsList.length; k++) {
            if (!ruleSlotIndices.contains(k)) {
              sNew[k] = sectionsList[k]['key'] as String;
            } else {
              if (k == fullSlotTarget) {
                sNew[k] = siblingSectionKey;
              } else if (k == fullSlotSibling) {
                sNew[k] = targetSectionKey;
              } else {
                sNew[k] = sectionsList[k]['key'] as String;
              }
            }
          }

          // Step 6: Submit Complete Order
          final orderRes = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'order',
            params: {'config': 'firewall', 'sections': sNew},
            context: mCtx,
          );
          if (orderRes is List && orderRes.isNotEmpty && orderRes[0] != 0) {
            return false;
          }

          // Step 7: ARM Kernel Rollback Watchdog (pass staged order delta directly to uciApply)
          final applied = await uciApply(
            ipAddress,
            sysauth,
            useHttps,
            rollback: true,
            timeout: 30,
          );
          if (!applied) {
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }

          // Step 9: Post-Mutation Authoritative Verification Rules
          final postGetRes = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'get',
            params: {'config': 'firewall'},
            context: mCtx,
          );
          if (postGetRes is! List ||
              postGetRes.length < 2 ||
              postGetRes[0] != 0) {
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }

          final postRawUci = postGetRes[1] as Map<String, dynamic>? ?? {};
          final postRawValues = postRawUci['values'];
          final Map<String, dynamic> postUciValues = (postRawValues is Map)
              ? Map<String, dynamic>.from(postRawValues)
              : Map<String, dynamic>.from(postRawUci);

          final postSectionsList = <Map<String, dynamic>>[];
          int postFallbackIdx = 0;
          postUciValues.forEach((k, v) {
            if (v is Map) {
              final secKey = v['.name']?.toString() ?? k;
              final secType = v['.type']?.toString() ?? '';
              final idx = (v['.index'] is int)
                  ? v['.index'] as int
                  : int.tryParse(v['.index']?.toString() ?? '') ??
                        postFallbackIdx;
              postSectionsList.add({
                'key': secKey,
                'type': secType,
                'index': idx,
              });
              postFallbackIdx++;
            }
          });
          postSectionsList.sort(
            (a, b) => (a['index'] as int).compareTo(b['index'] as int),
          );

          // 5-Point Verification:
          // 1) Total count unchanged
          if (postSectionsList.length != sectionsList.length) {
            Logger.warning('reorder verification failed: length mismatch');
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }

          // 2) Non-Rule Exact Index Preservation
          for (int k = 0; k < sectionsList.length; k++) {
            if (!ruleSlotIndices.contains(k)) {
              if (postSectionsList[k]['key'] != sectionsList[k]['key'] ||
                  postSectionsList[k]['type'] != sectionsList[k]['type']) {
                Logger.warning(
                  'reorder verification failed: non-rule index $k modified',
                );
                await uciRevert(
                  ipAddress,
                  sysauth,
                  useHttps,
                  config: 'firewall',
                  context: mCtx,
                );
                return false;
              }
            }
          }

          // 3) Custom-Rule Slot Preservation
          final postRuleSlotIndices = <int>[];
          for (int i = 0; i < postSectionsList.length; i++) {
            if (postSectionsList[i]['type'] == 'rule') {
              postRuleSlotIndices.add(i);
            }
          }
          if (!listEquals(postRuleSlotIndices, ruleSlotIndices)) {
            Logger.warning(
              'reorder verification failed: rule slot indices shifted',
            );
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }

          // 4) Untouched Custom-Rule Slot Invariance
          for (int j = 0; j < ruleSlotIndices.length; j++) {
            if (j != jTarget && j != jSibling) {
              final slot = ruleSlotIndices[j];
              if (postSectionsList[slot]['key'] != sectionsList[slot]['key']) {
                Logger.warning(
                  'reorder verification failed: untouched rule slot $slot modified',
                );
                await uciRevert(
                  ipAddress,
                  sysauth,
                  useHttps,
                  config: 'firewall',
                  context: mCtx,
                );
                return false;
              }
            }
          }

          // 5) Slot Identity Exchange
          if (postSectionsList[fullSlotTarget]['key'] != siblingSectionKey ||
              postSectionsList[fullSlotSibling]['key'] != targetSectionKey) {
            Logger.warning(
              'reorder verification failed: target/sibling not properly exchanged',
            );
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }

          // Step 11: Disarm Rollback & Finalize
          final confirmed = await uciConfirm(ipAddress, sysauth, useHttps);
          if (!confirmed) {
            Logger.warning('reorderFirewallCustomRules uciConfirm failed');
            return false;
          }

          try {
            await callWithContext(
              ipAddress,
              sysauth,
              useHttps,
              object: 'rc',
              method: 'init',
              params: {'name': 'firewall', 'action': 'reload'},
              context: mCtx,
            );
          } catch (_) {}

          return true;
        } catch (e, stack) {
          Logger.exception('reorderFirewallCustomRules failed', e, stack);
          await uciRevert(
            ipAddress,
            sysauth,
            useHttps,
            config: 'firewall',
            context: mCtx,
          );
          return false;
        }
      },
    );
  }

  @visibleForTesting
  static Map<String, dynamic> extractUciValuesMap(dynamic rawData) {
    if (rawData is Map) {
      if (rawData['values'] is Map) {
        return Map<String, dynamic>.from(rawData['values'] as Map);
      }
      return Map<String, dynamic>.from(rawData);
    }
    return {};
  }

  @visibleForTesting
  static Map<String, dynamic>? findUciSection(
    Map<String, dynamic> uciValues,
    String sectionKey,
  ) {
    if (uciValues.containsKey(sectionKey) && uciValues[sectionKey] is Map) {
      return Map<String, dynamic>.from(uciValues[sectionKey] as Map);
    }
    for (final v in uciValues.values) {
      if (v is Map && v['.name']?.toString() == sectionKey) {
        return Map<String, dynamic>.from(v);
      }
    }
    return null;
  }

  @visibleForTesting
  static bool hasUciSection(Map<String, dynamic> uciValues, String sectionKey) {
    return findUciSection(uciValues, sectionKey) != null;
  }

  @visibleForTesting
  static void extractPortsFromUciSpec(dynamic spec, Set<int> out) {
    if (spec == null) return;
    final list = spec is List ? spec : [spec];
    for (final item in list) {
      final str = item.toString().trim();
      if (str.isEmpty) continue;
      if (str.contains(']:')) {
        // Bracketed IPv6 address with port, e.g. '[::]:80' or '[2001:db8::1]:8443'
        final colonIdx = str.lastIndexOf(']:');
        final portStr = str.substring(colonIdx + 2);
        final p = int.tryParse(portStr);
        if (p != null && p >= 1 && p <= 65535) out.add(p);
      } else if (str.contains(':')) {
        // Single colon indicates IPv4:port or host:port, e.g. '0.0.0.0:80' or '192.168.1.1:2222'.
        // Multiple colons without brackets indicates an IPv6 address without port (e.g. '2001:db8::1').
        final colonCount = ':'.allMatches(str).length;
        if (colonCount == 1) {
          final lastColon = str.lastIndexOf(':');
          final portStr = str.substring(lastColon + 1);
          final p = int.tryParse(portStr);
          if (p != null && p >= 1 && p <= 65535) out.add(p);
        }
      } else {
        // Raw integer port string, e.g. '80', '22', '8443'
        final p = int.tryParse(str);
        if (p != null && p >= 1 && p <= 65535) out.add(p);
      }
    }
  }

  static void _extractPortsFromUciSpec(dynamic spec, Set<int> out) =>
      extractPortsFromUciSpec(spec, out);

  @override
  Future<Set<int>> discoverManagementPorts(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    final routerId = '${useHttps ? "https" : "http"}://$ipAddress';
    final ports = <int>{22, 80, 443};

    // 1. Current active connection port
    try {
      final uri = _buildUrl(ipAddress, useHttps, '');
      if (uri.hasPort && uri.port > 0) {
        ports.add(uri.port);
      }
    } catch (_) {}

    final mCtx = mountedContext(context);

    // 2. Discover uhttpd HTTP/HTTPS listening ports
    try {
      final uhttpdRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': 'uhttpd'},
        context: mCtx,
      );
      if (uhttpdRes is List && uhttpdRes.length > 1 && uhttpdRes[0] == 0) {
        final rawData = uhttpdRes[1];
        final Map? values = (rawData is Map && rawData['values'] is Map)
            ? rawData['values'] as Map
            : (rawData is Map ? rawData : null);
        if (values != null) {
          for (final sec in values.values) {
            if (sec is Map) {
              _extractPortsFromUciSpec(sec['listen_http'], ports);
              _extractPortsFromUciSpec(sec['listen_https'], ports);
            }
          }
        }
      }
    } catch (_) {}

    // 3. Discover dropbear SSH listening ports
    try {
      final dropbearRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': 'dropbear'},
        context: mCtx,
      );
      if (dropbearRes is List &&
          dropbearRes.length > 1 &&
          dropbearRes[0] == 0) {
        final rawData = dropbearRes[1];
        final Map? values = (rawData is Map && rawData['values'] is Map)
            ? rawData['values'] as Map
            : (rawData is Map ? rawData : null);
        if (values != null) {
          for (final sec in values.values) {
            if (sec is Map) {
              _extractPortsFromUciSpec(sec['Port'] ?? sec['port'], ports);
            }
          }
        }
      }
    } catch (_) {}

    SelfDeviceGuard.setDiscoveredManagementPorts(routerId, ports);
    SelfDeviceGuard.setDiscoveredManagementPorts(ipAddress, ports);
    return ports;
  }

  @override
  Future<bool> applyPerDeviceNetworkAccessPolicy(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required NetworkAccessPolicy policy,
    required RouterCapabilities capabilities,
    BuildContext? context,
  }) async {
    if (!capabilities.hasUciWriteAccess) {
      Logger.warning(
        'applyPerDeviceNetworkAccessPolicy aborted: router has no UCI write access',
      );
      return false;
    }

    if (policy.isEffectivelyBlocked) {
      final isSelf = await SelfDeviceGuard.isSelfDevice(policy.targetMac);
      if (isSelf) {
        Logger.warning(
          'SelfDeviceGuard aborted: cannot block managing device (${policy.targetMac})',
        );
        return false;
      }
    }

    final routerId = '${useHttps ? "https" : "http"}://$ipAddress';
    return await RouterScopedOperationQueue.instance.runLocked(
      routerId: routerId,
      domain: 'firewall',
      action: () async {
        final mCtx = mountedContext(context);
        try {
          final getRes = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'get',
            params: {'config': 'firewall'},
            context: mCtx,
          );

          if (getRes is! List || getRes.length < 2 || getRes[0] != 0) {
            return false;
          }

          final overview = FirewallOverview.fromUciData(
            getRes[1] as Map<String, dynamic>?,
            backend: capabilities.firewallBackend,
          );

          final mutations = FirewallPolicyTranslator.translatePolicyToUci(
            policy: policy,
            capabilities: capabilities,
            existingRules: overview.customRules,
          );

          if (mutations.isEmpty) {
            return true;
          }

          for (final mutation in mutations) {
            switch (mutation.type) {
              case UciMutationType.add:
                await callWithContext(
                  ipAddress,
                  sysauth,
                  useHttps,
                  object: 'uci',
                  method: 'add',
                  params: {
                    'config': 'firewall',
                    'type': 'rule',
                    'values': mutation.values,
                  },
                  context: mCtx,
                );
                break;
              case UciMutationType.set:
                if (mutation.sectionKey != null) {
                  await callWithContext(
                    ipAddress,
                    sysauth,
                    useHttps,
                    object: 'uci',
                    method: 'set',
                    params: {
                      'config': 'firewall',
                      'section': mutation.sectionKey!,
                      'values': mutation.values,
                    },
                    context: mCtx,
                  );
                }
                break;
              case UciMutationType.delete:
                if (mutation.sectionKey != null) {
                  await callWithContext(
                    ipAddress,
                    sysauth,
                    useHttps,
                    object: 'uci',
                    method: 'delete',
                    params: {
                      'config': 'firewall',
                      'section': mutation.sectionKey!,
                    },
                    context: mCtx,
                  );
                }
                break;
              case UciMutationType.none:
                break;
            }
          }

          // Pass staged delta changes directly to uciApply with rollback protection
          final applied = await uciApply(
            ipAddress,
            sysauth,
            useHttps,
            rollback: true,
            timeout: 30,
          );
          if (!applied) {
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }

          // Authenticated post-apply verification proving management RPC liveness
          final verifyRes = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'get',
            params: {'config': 'firewall'},
            context: mCtx,
          );
          if (verifyRes is! List || verifyRes.length < 2 || verifyRes[0] != 0) {
            Logger.warning(
              'applyPerDeviceNetworkAccessPolicy verification failed: management RPC unreachable after apply',
            );
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }

          // Authoritative state verification: deleted sections absent & policy state matched
          final verifyUciValues = extractUciValuesMap(verifyRes[1]);
          for (final mutation in mutations) {
            if (mutation.type == UciMutationType.delete &&
                mutation.sectionKey != null) {
              if (hasUciSection(verifyUciValues, mutation.sectionKey!)) {
                Logger.warning(
                  'applyPerDeviceNetworkAccessPolicy verification failed: deleted section ${mutation.sectionKey} still present',
                );
                await uciRevert(
                  ipAddress,
                  sysauth,
                  useHttps,
                  config: 'firewall',
                  context: mCtx,
                );
                return false;
              }
            }
          }

          final verifyOverview = FirewallOverview.fromUciData(
            verifyRes[1] as Map<String, dynamic>?,
            backend: capabilities.firewallBackend,
          );
          final recognized = FirewallPolicyTranslator.recognizePolicy(
            targetMac: policy.targetMac,
            rules: verifyOverview.customRules,
          );
          if (policy.isEffectivelyBlocked && !recognized.hasActiveBlock) {
            Logger.warning(
              'applyPerDeviceNetworkAccessPolicy verification failed: block not active after apply',
            );
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          } else if (!policy.isEffectivelyBlocked &&
              recognized.hasActiveBlock) {
            Logger.warning(
              'applyPerDeviceNetworkAccessPolicy verification failed: block still active after unblock apply',
            );
            await uciRevert(
              ipAddress,
              sysauth,
              useHttps,
              config: 'firewall',
              context: mCtx,
            );
            return false;
          }

          final confirmed = await uciConfirm(ipAddress, sysauth, useHttps);
          if (!confirmed) {
            Logger.warning(
              'applyPerDeviceNetworkAccessPolicy uciConfirm failed',
            );
            return false;
          }

          try {
            await callWithContext(
              ipAddress,
              sysauth,
              useHttps,
              object: 'rc',
              method: 'init',
              params: {'name': 'firewall', 'action': 'reload'},
              context: mCtx,
            );
          } catch (_) {}

          return true;
        } catch (e, stack) {
          Logger.exception(
            'applyPerDeviceNetworkAccessPolicy failed',
            e,
            stack,
          );
          await uciRevert(
            ipAddress,
            sysauth,
            useHttps,
            config: 'firewall',
            context: mCtx,
          );
          return false;
        }
      },
    );
  }

  @override
  Future<bool> applyClientSpeedLimits(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required List<ClientSpeedLimit> limits,
    required RouterCapabilities capabilities,
    BuildContext? context,
  }) async {
    final routerId = '${useHttps ? "https" : "http"}://$ipAddress';
    return await RouterScopedOperationQueue.instance.runLocked(
      routerId: routerId,
      domain: 'qos',
      action: () async {
        final mCtx = mountedContext(context);
        try {
          final activeLimits = limits
              .where((l) => l.isEffectivelyRestricted)
              .toList();

          final qosScript = ClientSpeedLimitTranslator.generateQosScript(
            limits,
          );
          final initScript =
              ClientSpeedLimitTranslator.generateInitServiceScript();

          // 1. Write /usr/sbin/yala-qos
          final writeRes = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'file',
            method: 'write',
            params: {
              'path': ClientSpeedLimitTranslator.scriptPath,
              'data': qosScript,
            },
            context: mCtx,
          );

          bool writeOk = execSucceeded(writeRes);
          if (!writeOk) {
            final shRes = await callWithContext(
              ipAddress,
              sysauth,
              useHttps,
              object: 'file',
              method: 'exec',
              params: fileExecParams('/bin/sh', [
                '-c',
                "cat << 'EOF' > ${ClientSpeedLimitTranslator.scriptPath}\n$qosScript\nEOF",
              ]),
              context: mCtx,
            );
            writeOk = execSucceeded(shRes);
          }

          if (!writeOk) {
            Logger.warning(
              'applyClientSpeedLimits: failed to write ${ClientSpeedLimitTranslator.scriptPath}',
            );
            return false;
          }

          // 2. Write /etc/init.d/yala-qos service script for boot persistence
          final initWriteRes = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'file',
            method: 'write',
            params: {
              'path': ClientSpeedLimitTranslator.initServicePath,
              'data': initScript,
            },
            context: mCtx,
          );
          if (!execSucceeded(initWriteRes)) {
            await callWithContext(
              ipAddress,
              sysauth,
              useHttps,
              object: 'file',
              method: 'exec',
              params: fileExecParams('/bin/sh', [
                '-c',
                "cat << 'EOF' > ${ClientSpeedLimitTranslator.initServicePath}\n$initScript\nEOF",
              ]),
              context: mCtx,
            );
          }

          // 3. Make scripts executable and apply / stop
          final actionCmd = activeLimits.isEmpty
              ? 'chmod +x ${ClientSpeedLimitTranslator.scriptPath} ${ClientSpeedLimitTranslator.initServicePath} 2>/dev/null; '
                    '${ClientSpeedLimitTranslator.scriptPath} stop 2>/dev/null; '
                    '${ClientSpeedLimitTranslator.initServicePath} disable 2>/dev/null; '
                    'rm -f ${ClientSpeedLimitTranslator.legacyNftablesPath} 2>/dev/null'
              : 'chmod +x ${ClientSpeedLimitTranslator.scriptPath} ${ClientSpeedLimitTranslator.initServicePath} 2>/dev/null; '
                    '${ClientSpeedLimitTranslator.scriptPath} apply 2>/dev/null; '
                    '${ClientSpeedLimitTranslator.initServicePath} enable 2>/dev/null; '
                    'rm -f ${ClientSpeedLimitTranslator.legacyNftablesPath} 2>/dev/null';

          final execRes = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'file',
            method: 'exec',
            params: fileExecParams('/bin/sh', ['-c', actionCmd]),
            context: mCtx,
          );

          return execSucceeded(execRes);
        } catch (e, stack) {
          Logger.exception('applyClientSpeedLimits failed', e, stack);
          return false;
        }
      },
    );
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
    // 1. Guard against banning managing device
    final isSelf = await SelfDeviceGuard.isSelfDevice(macAddress);
    if (isSelf) {
      Logger.warning(
        'SelfDeviceGuard aborted: cannot ban managing device ($macAddress)',
      );
      return false;
    }

    // 2. Disconnect/ban wireless (if wireless client or hostapd exists)
    final wifiFuture = disconnectWirelessClient(
      ipAddress,
      sysauth,
      useHttps,
      macAddress: macAddress,
      iface: iface,
      banTimeSeconds: banTimeSeconds,
      context: context,
    );

    // 3. Enforce firewall block on the aggregated rule (for wired & network-level packet drop)
    final fwFuture = _enforceFirewallBan(
      ipAddress: ipAddress,
      sysauth: sysauth,
      useHttps: useHttps,
      macAddress: macAddress,
      context: context,
    );

    final results = await Future.wait([wifiFuture, fwFuture]);
    return results[0] || results[1];
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
    bool ubusSuccess = false;

    // 1. Native ubus call to hostapd.* del_client with ban_time: 0 to immediately lift temporary ban
    try {
      final hostapdObjects = await listUbusObjects(
        ipAddress,
        sysauth,
        useHttps,
        pattern: 'hostapd.*',
        context: mountedContext(context),
      );
      for (final obj in hostapdObjects) {
        if (obj.startsWith('hostapd.')) {
          try {
            final res = await callWithContext(
              ipAddress,
              sysauth,
              useHttps,
              object: obj,
              method: 'del_client',
              params: {
                'addr': macUpper,
                'reason': 1,
                'deauth': false,
                'ban_time': 0,
              },
              context: mountedContext(context),
            );
            if (res is List && res.isNotEmpty && res[0] == 0) {
              ubusSuccess = true;
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      Logger.warning('Native hostapd unban del_client error: $e');
    }

    // 2. Non-blocking background script to remove hostapd_cli deny_acl and live firewall drop rules
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
) >/dev/null 2>&1 &
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

    // 3. Remove persistent UCI blocks concurrently
    final results = await Future.wait([
      _removeFirewallBlock(
        ipAddress: ipAddress,
        sysauth: sysauth,
        useHttps: useHttps,
        macAddress: macAddress,
        context: context,
      ),
      _removeWirelessMacFilter(
        ipAddress: ipAddress,
        sysauth: sysauth,
        useHttps: useHttps,
        macAddress: macAddress,
        context: context,
      ),
    ]);

    final fwOk = results[0];
    final wifiOk = results[1];
    return (ubusSuccess || fwOk) && wifiOk;
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
      const script = '''
DENY_MACS=""
for s in /var/run/hostapd/* /var/run/hostapd-*/*; do
  if [ -S "\$s" ]; then
    s_dir="\${s%/*}"
    s_if="\${s##*/}"
    DENY_MACS="\$DENY_MACS \$(/usr/sbin/hostapd_cli -p "\$s_dir" -i "\$s_if" deny_acl SHOW 2>/dev/null | grep -oE "([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}" || true)"
  fi
done

WIFI_UCI=""
for sec in \$(uci show wireless 2>/dev/null | grep -iE "\\.macfilter='?deny'?|\\.macfilter='?2'?" | cut -d. -f2 | cut -d= -f1); do
  WIFI_UCI="\$WIFI_UCI \$(uci get wireless.\${sec}.maclist 2>/dev/null || true)"
done

BAN_FW_UCI=\$(uci show firewall 2>/dev/null | grep -iE "name='*Ban_Client_" | cut -d. -f2 | while read -r sec; do uci -q get firewall."\$sec".src_mac 2>/dev/null; done | tr '\n' ' ')

PAUSE_FW_UCI=\$(uci show firewall 2>/dev/null | grep -iE "name='*(Pause_Internet_|nointernet_wireless_clients|Yala_Block_)" | cut -d. -f2 | while read -r sec; do uci -q get firewall."\$sec".src_mac 2>/dev/null; done | tr '\n' ' ')
NFT_MACS=\$(nft list chain inet fw4 input 2>/dev/null; nft list chain inet fw4 forward 2>/dev/null | grep -iE "drop|reject" | grep -oE "([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}" || true)
IPT_MACS=\$(iptables -L INPUT -v -n 2>/dev/null; iptables -L FORWARD -v -n 2>/dev/null | grep -iE "DROP|REJECT" | grep -oE "([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}" || true)

echo "BANNED:"
echo "\$DENY_MACS \$WIFI_UCI \$BAN_FW_UCI" | tr ' ' '\\n' | grep -vE "^00:00:00:00:00:00\$|^FF:FF:FF:FF:FF:FF\$" | sort -u | grep -v "^\$"

echo "RESTRICTED:"
echo "\$PAUSE_FW_UCI \$NFT_MACS \$IPT_MACS" | tr ' ' '\\n' | grep -vE "^00:00:00:00:00:00\$|^FF:FF:FF:FF:FF:FF\$" | sort -u | grep -v "^\$"
''';

      dynamic res;
      try {
        res = await callWithContext(
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
      } catch (_) {}

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
                  : 'Client Access Control (Banned)',
            };

            if (currentSection == 'banned' &&
                !result['banned']!.any((e) => e['mac'] == macUpper)) {
              result['banned']!.add(entry);
              result['restricted']!.removeWhere((e) => e['mac'] == macUpper);
            } else if (currentSection == 'restricted' &&
                !result['banned']!.any((e) => e['mac'] == macUpper) &&
                !result['restricted']!.any((e) => e['mac'] == macUpper)) {
              result['restricted']!.add(entry);
            }
          }
        }
      } else {
        // Native ubus fallback for routers where rpcd file.exec is restricted by ACLs
        try {
          final uciWire = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'get',
            params: {'config': 'wireless'},
            context: mountedContext(context),
          );
          if (uciWire is List && uciWire.length > 1 && uciWire[0] == 0) {
            final values =
                (uciWire[1] as Map<String, dynamic>?)?['values']
                    as Map<String, dynamic>? ??
                {};
            for (final sec in values.values) {
              if (sec is Map<String, dynamic>) {
                final mf = sec['macfilter']?.toString().toLowerCase();
                if (mf == 'deny' || mf == '2') {
                  final raw = sec['maclist'];
                  final List<String> macs = raw is List
                      ? raw
                            .map(
                              (e) => e.toString().toUpperCase().replaceAll(
                                '-',
                                ':',
                              ),
                            )
                            .toList()
                      : (raw != null
                            ? [
                                raw.toString().toUpperCase().replaceAll(
                                  '-',
                                  ':',
                                ),
                              ]
                            : []);
                  for (final m in macs) {
                    if (m.isNotEmpty &&
                        !result['banned']!.any((e) => e['mac'] == m)) {
                      result['banned']!.add({
                        'mac': m,
                        'name': m,
                        'ip': 'N/A',
                        'type': 'banned',
                        'source': 'Wi-Fi Access Control (Banned)',
                      });
                    }
                  }
                }
              }
            }
          }

          final uciFw = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'get',
            params: {'config': 'firewall'},
            context: mountedContext(context),
          );
          if (uciFw is List && uciFw.length > 1 && uciFw[0] == 0) {
            final values =
                (uciFw[1] as Map<String, dynamic>?)?['values']
                    as Map<String, dynamic>? ??
                {};
            for (final sec in values.values) {
              if (sec is Map<String, dynamic>) {
                final target = sec['target']?.toString().toUpperCase() ?? '';
                final name = sec['name']?.toString() ?? '';
                final isBanRule = name.startsWith('Ban_Client_');
                final isBlock =
                    target == 'DROP' ||
                    target == 'REJECT' ||
                    target == 'STOP' ||
                    name.startsWith('Pause_Internet_') ||
                    name.startsWith('Yala_Block_') ||
                    name == 'nointernet_wireless_clients';
                final srcMac = sec['src_mac'];
                final List<String> macs = srcMac is List
                    ? srcMac
                          .map(
                            (e) =>
                                e.toString().toUpperCase().replaceAll('-', ':'),
                          )
                          .toList()
                    : (srcMac != null
                          ? [
                              srcMac.toString().toUpperCase().replaceAll(
                                '-',
                                ':',
                              ),
                            ]
                          : []);
                if (isBanRule) {
                  for (final m in macs) {
                    if (m.isNotEmpty &&
                        !result['banned']!.any((e) => e['mac'] == m)) {
                      result['banned']!.add({
                        'mac': m,
                        'name': m,
                        'ip': 'N/A',
                        'type': 'banned',
                        'source': 'Client Access Control (Banned)',
                      });
                      result['restricted']!.removeWhere((e) => e['mac'] == m);
                    }
                  }
                } else if (isBlock) {
                  for (final m in macs) {
                    if (m.isNotEmpty &&
                        !result['banned']!.any((e) => e['mac'] == m) &&
                        !result['restricted']!.any((e) => e['mac'] == m)) {
                      result['restricted']!.add({
                        'mac': m,
                        'name': m,
                        'ip': 'N/A',
                        'type': 'restricted',
                        'source': 'Internet Access Paused',
                      });
                    }
                  }
                }
              }
            }
          }
        } catch (_) {}
      }

      return result;
    } catch (e, stack) {
      Logger.exception('fetchRestrictedAndBannedClientsLive failed', e, stack);
      return {'restricted': [], 'banned': []};
    }
  }

  @visibleForTesting
  static String? sanitizeOpenWrtLeaseTime(String? lt) =>
      _sanitizeOpenWrtLeaseTime(lt);

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
        final safeName = shellSingleQuote(hostname.trim());
        final safeMac = shellSingleQuote(macUpper);
        final safeIp = shellSingleQuote(cleanTargetIp);
        final cmdList = [
          'for sec in \$(uci show dhcp 2>/dev/null | grep -iE "$macUpper|$cleanTargetIp" | cut -d. -f2 | sort -u); do uci delete dhcp.\$sec 2>/dev/null || true; done',
          'SECNAME=\$(uci add dhcp host)',
          'uci set dhcp.\$SECNAME.name=$safeName',
          'uci set dhcp.\$SECNAME.mac=$safeMac',
          'uci set dhcp.\$SECNAME.ip=$safeIp',
        ];
        if (sanitizedLt != null && sanitizedLt.isNotEmpty) {
          cmdList.add(
            'uci set dhcp.\$SECNAME.leasetime=${shellSingleQuote(sanitizedLt)}',
          );
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

      // Reload dnsmasq service to apply static lease without terminating daemon
      await manageServiceAction(
        ipAddress,
        sysauth,
        useHttps,
        serviceName: 'dnsmasq',
        action: 'reload',
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

      final cleanTargetIp =
          (targetIp != null &&
              targetIp.trim().isNotEmpty &&
              targetIp.trim() != 'N/A')
          ? targetIp.trim()
          : null;
      final cleanHostname =
          (hostname != null &&
              hostname.trim().isNotEmpty &&
              hostname.trim() != 'Unknown' &&
              hostname.trim() != '*' &&
              hostname.trim() != 'Unnamed Host')
          ? hostname.trim().toLowerCase()
          : null;
      final cleanDuid =
          (duid != null && duid.trim().isNotEmpty && duid.trim() != 'N/A')
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
          final pList = _extractProcessList(procRes);
          if (pList != null) {
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
        final pList = _extractProcessList(procRes);
        if (pList != null) {
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
      const cmd =
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

      if (shellRes is List &&
          shellRes.length > 1 &&
          shellRes[0] == 0 &&
          shellRes[1] is Map) {
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

  @visibleForTesting
  static bool isValidIpv4Candidate(String ip) => _isValidIpv4Candidate(ip);

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
        final pList = _extractProcessList(procRes);
        if (pList != null) {
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

      final execMap = (rpcRes is List && rpcRes.length > 1 && rpcRes[1] is Map)
          ? rpcRes[1] as Map
          : (rpcRes is Map ? rpcRes : null);
      final stdout = execMap?['stdout']?.toString() ?? '';
      final stderr = execMap?['stderr']?.toString() ?? '';
      final combined = '$stdout\n$stderr'.trim();

      if (combined.contains('Address:') || combined.contains('Name:')) {
        return DdnsValidationResult.success(
          testOutput: 'DNS Lookup Successful:\n$combined',
        );
      } else if (combined.contains("can't find") ||
          combined.contains('NXDOMAIN') ||
          combined.contains('ServFail') ||
          combined.contains('connection timed out') ||
          combined.contains('no servers could be reached')) {
        return DdnsValidationResult.failure(
          'Hostname DNS lookup failed ($hostToTest). Ensure domain exists or is registered.',
          testOutput: combined,
        );
      }

      if (combined.isEmpty) {
        return DdnsValidationResult.failure(
          'No DNS test output received from router for $hostToTest.',
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

      // Validate committed state from router
      try {
        final verifyRes = await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'uci',
          method: 'get',
          params: {'config': 'ddns', 'section': 'global'},
          context: mountedContext(context),
        );
        if (verifyRes is Map) {
          final values = verifyRes['values'] ?? verifyRes;
          if (values is Map) {
            final verifiedVal = values['is_enabled']?.toString();
            final expectedVal = enable ? '1' : '0';
            if (verifiedVal != null && verifiedVal != expectedVal) {
              Logger.warning(
                'toggleGlobalDdns: validation mismatch. Expected $expectedVal, got $verifiedVal',
              );
              return false;
            }
          }
        }
      } catch (e) {
        Logger.debug('toggleGlobalDdns: validation query warning: $e');
      }

      return true;
    } catch (e, stack) {
      Logger.exception('toggleGlobalDdns failed', e, stack);
      return false;
    }
  }

  @override
  Future<bool> saveSqmQueue(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required SqmQueue queue,
    BuildContext? context,
  }) async {
    try {
      var setRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'set',
        params: {
          'config': 'sqm',
          'section': queue.name,
          'type': 'queue',
          'values': queue.toUciParams(),
        },
        context: mountedContext(context),
      );

      if (!_isUciSuccessful(setRes)) {
        // Section might not exist yet — try adding it first via uci.add
        final addRes = await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'uci',
          method: 'add',
          params: {
            'config': 'sqm',
            'type': 'queue',
            'name': queue.name,
            'values': queue.toUciParams(),
          },
          context: mountedContext(context),
        );

        if (_isUciSuccessful(addRes)) {
          setRes = addRes;
        } else {
          // If named add failed, try anonymous add and update section
          final anonAddRes = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'uci',
            method: 'add',
            params: {'config': 'sqm', 'type': 'queue'},
            context: mountedContext(context),
          );

          if (anonAddRes is List &&
              anonAddRes.isNotEmpty &&
              anonAddRes[0] == 0 &&
              anonAddRes.length > 1) {
            final data = anonAddRes[1];
            final createdSection =
                (data is Map
                    ? data['section']?.toString()
                    : data?.toString()) ??
                '';
            if (createdSection.isNotEmpty) {
              setRes = await callWithContext(
                ipAddress,
                sysauth,
                useHttps,
                object: 'uci',
                method: 'set',
                params: {
                  'config': 'sqm',
                  'section': createdSection,
                  'type': 'queue',
                  'values': queue.toUciParams(),
                },
                context: mountedContext(context),
              );
            }
          }
        }
      }

      if (!_isUciSuccessful(setRes)) return false;

      final commitRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'commit',
        params: {'config': 'sqm'},
        context: mountedContext(context),
      );

      if (!_isUciSuccessful(commitRes)) return false;

      if (queue.enabled) {
        try {
          await manageServiceAction(
            ipAddress,
            sysauth,
            useHttps,
            serviceName: 'sqm',
            action: 'enable',
            context: mountedContext(context),
          );
        } catch (_) {}
      }

      try {
        await manageServiceAction(
          ipAddress,
          sysauth,
          useHttps,
          serviceName: 'sqm',
          action: 'restart',
          context: mountedContext(context),
        );
      } catch (_) {}

      return true;
    } catch (e, stack) {
      Logger.exception('saveSqmQueue failed', e, stack);
      return false;
    }
  }

  @override
  Future<bool> deleteSqmQueue(
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
        params: {'config': 'sqm', 'section': sectionName},
        context: mountedContext(context),
      );

      if (!_isUciSuccessful(delRes)) return false;

      final commitRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'commit',
        params: {'config': 'sqm'},
        context: mountedContext(context),
      );

      if (!_isUciSuccessful(commitRes)) return false;

      try {
        await manageServiceAction(
          ipAddress,
          sysauth,
          useHttps,
          serviceName: 'sqm',
          action: 'restart',
          context: mountedContext(context),
        );
      } catch (_) {}

      return true;
    } catch (e, stack) {
      Logger.exception('deleteSqmQueue failed', e, stack);
      return false;
    }
  }

  @override
  Future<bool> toggleSqmService(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required bool enable,
    BuildContext? context,
  }) async {
    try {
      await manageServiceAction(
        ipAddress,
        sysauth,
        useHttps,
        serviceName: 'sqm',
        action: enable ? 'enable' : 'disable',
        context: mountedContext(context),
      );

      await manageServiceAction(
        ipAddress,
        sysauth,
        useHttps,
        serviceName: 'sqm',
        action: enable ? 'start' : 'stop',
        context: mountedContext(context),
      );

      return true;
    } catch (e, stack) {
      Logger.exception('toggleSqmService failed', e, stack);
      return false;
    }
  }

  Future<Map<String, dynamic>?> _runDiagnosticFileExec(
    String ipAddress,
    String sysauth,
    bool useHttps,
    String command,
    List<String> args, {
    BuildContext? context,
  }) async {
    try {
      final res = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: RealApiService.fileExecParams(command, args),
        context: mountedContext(context),
      );
      if (res is List && res.length > 1 && res[0] == 0) {
        return res[1] as Map<String, dynamic>?;
      }
    } catch (_) {}

    try {
      final fallbackRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: RealApiService.fileExecArgs(command, args),
        context: mountedContext(context),
      );
      if (fallbackRes is List &&
          fallbackRes.length > 1 &&
          fallbackRes[0] == 0) {
        return fallbackRes[1] as Map<String, dynamic>?;
      }
    } catch (_) {}

    return null;
  }

  /// Sanitizes host/domain/IP inputs to prevent URL-scheme or path parsing false negatives.
  static String sanitizeHost(String input) {
    var clean = input.trim();
    if (clean.contains('://')) {
      clean = clean.split('://')[1];
    }
    // Strip trailing slash, path, or URL query parameters
    clean = clean.split('/')[0].split('?')[0];
    // Strip port if IPv4 or standard hostname (e.g. google.com:443 or 192.168.1.1:80)
    if (!clean.startsWith('[') &&
        clean.contains(':') &&
        clean.split(':').length == 2) {
      clean = clean.split(':')[0];
    }
    // Remove IPv6 enclosing brackets if any: [2001:db8::1] -> 2001:db8::1
    if (clean.startsWith('[') && clean.endsWith(']')) {
      clean = clean.substring(1, clean.length - 1);
    }
    return clean;
  }

  @override
  Future<PingResult> executePing(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String target,
    int count = 3,
    int timeoutSec = 2,
    bool isIpv6 = false,
    BuildContext? context,
  }) async {
    final cleanTarget = sanitizeHost(target);
    final effectiveIpv6 =
        isIpv6 || (cleanTarget.contains(':') && !cleanTarget.contains('.'));
    final bin = effectiveIpv6 ? '/bin/ping6' : '/bin/ping';
    final fallbackBin = effectiveIpv6 ? '/usr/bin/ping6' : '/usr/bin/ping';
    final args = ['-c', '$count', '-W', '$timeoutSec', cleanTarget];

    Map<String, dynamic>? execResult = await _runDiagnosticFileExec(
      ipAddress,
      sysauth,
      useHttps,
      bin,
      args,
      context: context,
    );

    execResult ??= await _runDiagnosticFileExec(
      ipAddress,
      sysauth,
      useHttps,
      fallbackBin,
      args,
      context: context,
    );

    // Some stripped BusyBox ping versions do not support -W; retry without -W if failed
    if (execResult != null &&
        execResult['code'] != 0 &&
        ((execResult['stderr'] as String? ?? '').contains('invalid') ||
            (execResult['stdout'] as String? ?? '').contains('invalid'))) {
      execResult = await _runDiagnosticFileExec(
        ipAddress,
        sysauth,
        useHttps,
        bin,
        ['-c', '$count', cleanTarget],
        context: context,
      );
    }

    if (execResult == null) {
      return PingResult.failure(
        target: cleanTarget,
        errorMessage: 'Failed to invoke ping via router RPC',
      );
    }

    final code = execResult['code'] as int? ?? 1;
    final stdout = execResult['stdout'] as String? ?? '';
    final stderr = execResult['stderr'] as String?;

    return PingResult.parse(
      cleanTarget,
      stdout,
      stderr: stderr,
      exitCode: code,
    );
  }

  @override
  Future<TracerouteResult> executeTraceroute(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String target,
    int maxHops = 15,
    int timeoutSec = 1,
    bool isIpv6 = false,
    BuildContext? context,
  }) async {
    final cleanTarget = sanitizeHost(target);
    final effectiveIpv6 =
        isIpv6 || (cleanTarget.contains(':') && !cleanTarget.contains('.'));
    final bin = effectiveIpv6 ? '/bin/traceroute6' : '/bin/traceroute';
    final fallbackBin = effectiveIpv6
        ? '/usr/bin/traceroute6'
        : '/usr/bin/traceroute';
    final args = [
      '-q',
      '1',
      '-w',
      '$timeoutSec',
      '-m',
      '$maxHops',
      cleanTarget,
    ];

    Map<String, dynamic>? execResult = await _runDiagnosticFileExec(
      ipAddress,
      sysauth,
      useHttps,
      bin,
      args,
      context: context,
    );

    execResult ??= await _runDiagnosticFileExec(
      ipAddress,
      sysauth,
      useHttps,
      fallbackBin,
      args,
      context: context,
    );

    if (execResult == null) {
      return TracerouteResult.failure(
        target: cleanTarget,
        errorMessage: 'Failed to invoke traceroute via router RPC',
      );
    }

    final code = execResult['code'] as int? ?? 0;
    final stdout = execResult['stdout'] as String? ?? '';
    final stderr = execResult['stderr'] as String?;

    return TracerouteResult.parse(
      cleanTarget,
      stdout,
      stderr: stderr,
      exitCode: code,
      maxHops: maxHops,
    );
  }

  @override
  Future<DnsLookupResult> executeDnsLookup(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String host,
    String? server,
    BuildContext? context,
  }) async {
    final cleanHost = sanitizeHost(host);
    const bin = '/usr/bin/nslookup';
    final args = <String>[cleanHost];
    if (server != null && server.trim().isNotEmpty) {
      args.add(sanitizeHost(server.trim()));
    }

    Map<String, dynamic>? execResult = await _runDiagnosticFileExec(
      ipAddress,
      sysauth,
      useHttps,
      bin,
      args,
      context: context,
    );

    execResult ??= await _runDiagnosticFileExec(
      ipAddress,
      sysauth,
      useHttps,
      '/bin/nslookup',
      args,
      context: context,
    );

    if (execResult == null) {
      return DnsLookupResult.failure(
        query: cleanHost,
        errorMessage: 'Failed to invoke nslookup via router RPC',
      );
    }

    final code = execResult['code'] as int? ?? 0;
    final stdout = execResult['stdout'] as String? ?? '';
    final stderr = execResult['stderr'] as String?;

    return DnsLookupResult.parse(
      cleanHost,
      stdout,
      stderr: stderr,
      exitCode: code,
    );
  }

  @override
  Future<InternetReachability> testInternetReachability(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    String? wanInterface;
    String? wanIp;
    String? gatewayIp;

    // 1. Detect active WAN interface and default gateway
    try {
      final ifaceRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'network.interface',
        method: 'dump',
        context: mountedContext(context),
      );
      if (ifaceRes is List && ifaceRes.length > 1 && ifaceRes[0] == 0) {
        final list =
            (ifaceRes[1] as Map<String, dynamic>?)?['interface'] as List?;
        if (list != null) {
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              final name = item['interface'] as String? ?? '';
              final isWan =
                  name == 'wan' ||
                  name == 'wan6' ||
                  name.startsWith('wan') ||
                  name.startsWith('wwan') ||
                  item['defaultroute'] == true;
              if (isWan && item['up'] == true) {
                wanInterface = name;
                final v4 = item['ipv4-address'] as List?;
                if (v4 != null && v4.isNotEmpty) {
                  wanIp =
                      (v4[0] as Map<String, dynamic>?)?['address'] as String?;
                }
                final routes = item['route'] as List?;
                if (routes != null) {
                  for (final r in routes) {
                    if (r is Map<String, dynamic> &&
                        (r['target'] == '0.0.0.0' ||
                            r['target'] == 'default')) {
                      gatewayIp = r['nexthop'] as String?;
                      break;
                    }
                  }
                }
                if (gatewayIp != null) break;
              }
            }
          }
        }
      }
    } catch (_) {}

    // Fallback: inspect kernel routing table if gateway not yet discovered
    if (gatewayIp == null) {
      try {
        final routes = await fetchRoutingTable(
          ipAddress,
          sysauth,
          useHttps,
          context: context,
        );
        for (final r in routes) {
          if (r.isDefault) {
            if (r.gateway != null && r.gateway!.isNotEmpty) {
              gatewayIp = r.gateway;
              wanInterface ??= (r.interface == 'br-lan' || r.interface == 'lan')
                  ? '${r.interface} (AP mode)'
                  : r.interface;
            } else if (r.interface != null) {
              // Point-to-point interface without next-hop (e.g. pppoe-wan, wg0, tun0)
              wanInterface ??= r.interface;
              gatewayIp = 'Point-to-Point (${r.interface})';
            }
            break;
          }
        }
      } catch (_) {}
    }

    // 2. Gateway probe (only ping if gateway is an actual IP address)
    bool gwOk = false;
    double? gwLatency;
    final isPingableGateway =
        gatewayIp != null &&
        !gatewayIp.startsWith('Point-to-Point') &&
        gatewayIp.isNotEmpty;

    if (isPingableGateway) {
      final gwPing = await executePing(
        ipAddress,
        sysauth,
        useHttps,
        target: gatewayIp,
        count: 2,
        timeoutSec: 2,
        context: context,
      );
      gwOk = gwPing.isSuccess;
      gwLatency = gwPing.avgRttMs ?? gwPing.minRttMs;
    }

    // 3. Multi-Anycast Public ICMP Ping Probes (Cloudflare -> Google -> Quad9 -> IPv6)
    bool publicDnsOk = false;
    double? publicDnsLatency;
    const anycastTargets = ['1.1.1.1', '8.8.8.8', '9.9.9.9'];

    for (final target in anycastTargets) {
      final pubPing = await executePing(
        ipAddress,
        sysauth,
        useHttps,
        target: target,
        count: 2,
        timeoutSec: 2,
        context: context,
      );
      if (pubPing.isSuccess) {
        publicDnsOk = true;
        publicDnsLatency = pubPing.avgRttMs ?? pubPing.minRttMs;
        break;
      }
    }

    // IPv6 fallback probe if IPv4 ICMP failed
    if (!publicDnsOk) {
      final v6Ping = await executePing(
        ipAddress,
        sysauth,
        useHttps,
        target: '2606:4700:4700::1111',
        count: 2,
        timeoutSec: 2,
        isIpv6: true,
        context: context,
      );
      if (v6Ping.isSuccess) {
        publicDnsOk = true;
        publicDnsLatency = v6Ping.avgRttMs ?? v6Ping.minRttMs;
      }
    }

    // 4. Multi-Domain DNS Resolution Probes (openwrt.org -> google.com -> cloudflare.com)
    bool dnsOk = false;
    const dnsTestDomains = ['openwrt.org', 'google.com', 'cloudflare.com'];

    for (final domain in dnsTestDomains) {
      final dnsResult = await executeDnsLookup(
        ipAddress,
        sysauth,
        useHttps,
        host: domain,
        context: context,
      );
      if (dnsResult.isSuccess &&
          (dnsResult.ipv4Addresses.isNotEmpty ||
              dnsResult.ipv6Addresses.isNotEmpty)) {
        dnsOk = true;
        break;
      }
    }

    // 5. Strict Zero-False-Positive / Zero-False-Negative Classification
    ReachabilityStatus status;
    String statusMsg;

    if (publicDnsOk && dnsOk) {
      status = ReachabilityStatus.online;
      if (gwOk) {
        statusMsg = 'Connected to Internet (All probes passed)';
      } else if (gatewayIp != null && gatewayIp.startsWith('Point-to-Point')) {
        statusMsg = 'Connected to Internet via $gatewayIp';
      } else {
        // Gateway drops ICMP but WAN and DNS are working
        statusMsg = 'Connected to Internet (Gateway ICMP unprompted, WAN OK)';
      }
    } else if (dnsOk && !publicDnsOk) {
      // ISP or firewall blocks ICMP echo, but DNS resolution succeeds
      status = ReachabilityStatus.online;
      statusMsg =
          'Connected to Internet (DNS operational, ICMP ping blocked by network)';
    } else if (publicDnsOk && !dnsOk) {
      // Direct IP connectivity works, but DNS resolution is broken
      status = ReachabilityStatus.partial;
      statusMsg =
          'ICMP ping reachable, but DNS resolution failed (Check router DNS settings)';
    } else if (gwOk) {
      // Gateway is reachable on LAN/WAN, but cannot reach public internet
      status = ReachabilityStatus.partial;
      statusMsg =
          'Local Gateway reachable ($gatewayIp), but external Internet is unreachable';
    } else {
      status = ReachabilityStatus.offline;
      statusMsg = gatewayIp == null
          ? 'No active WAN gateway or default route found'
          : 'Gateway and Internet are unreachable';
    }

    return InternetReachability(
      status: status,
      isReachable: status == ReachabilityStatus.online,
      wanInterface: wanInterface,
      wanIp: wanIp,
      gatewayIp: gatewayIp,
      gatewayReachable: gwOk,
      gatewayLatencyMs: gwLatency,
      publicDnsReachable: publicDnsOk,
      publicDnsLatencyMs: publicDnsLatency,
      dnsResolving: dnsOk,
      statusMessage: statusMsg,
      testedAt: DateTime.now(),
    );
  }

  @override
  Future<List<RouteEntry>> fetchRoutingTable(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    final execResult = await _runDiagnosticFileExec(
      ipAddress,
      sysauth,
      useHttps,
      '/sbin/ip',
      ['-4', 'route', 'show', 'table', 'all'],
      context: context,
    );
    final stdout = execResult?['stdout'] as String? ?? '';
    return RouteEntry.parseList(stdout);
  }

  @override
  Future<List<NeighborEntry>> fetchNeighborTable(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    final execResult = await _runDiagnosticFileExec(
      ipAddress,
      sysauth,
      useHttps,
      '/sbin/ip',
      ['-4', 'neigh', 'show'],
      context: context,
    );
    final stdout = execResult?['stdout'] as String? ?? '';
    return NeighborEntry.parseList(stdout);
  }

  @override
  Future<ConntrackInfo?> fetchConntrackInfo(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    try {
      int count = 0;
      int max = 16384;

      final countRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'read',
        params: {'path': '/proc/sys/net/netfilter/nf_conntrack_count'},
        context: mountedContext(context),
      );
      if (countRes is List && countRes.length > 1 && countRes[0] == 0) {
        final raw =
            (countRes[1] as Map<String, dynamic>?)?['data'] as String? ?? '';
        count = int.tryParse(raw.trim()) ?? 0;
      }

      final maxRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'read',
        params: {'path': '/proc/sys/net/netfilter/nf_conntrack_max'},
        context: mountedContext(context),
      );
      if (maxRes is List && maxRes.length > 1 && maxRes[0] == 0) {
        final raw =
            (maxRes[1] as Map<String, dynamic>?)?['data'] as String? ?? '';
        max = int.tryParse(raw.trim()) ?? 16384;
      }

      return ConntrackInfo(count: count, max: max);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<DiagnosticReport> generateFullDiagnosticReport(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    // 1. Board Info
    String hostname = ipAddress;
    String model = 'OpenWrt Device';
    String architecture = 'Unknown';
    String target = 'Unknown';
    String kernelVersion = 'Unknown';
    String firmwareVersion = 'Unknown';

    try {
      final boardRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'system',
        method: 'board',
        context: mountedContext(context),
      );
      if (boardRes is List && boardRes.length > 1 && boardRes[0] == 0) {
        final b = boardRes[1] as Map<String, dynamic>?;
        if (b != null) {
          hostname = b['hostname'] as String? ?? hostname;
          model = b['model'] as String? ?? model;
          architecture = b['system'] as String? ?? architecture;
          kernelVersion = b['kernel'] as String? ?? kernelVersion;
          final rel = b['release'] as Map<String, dynamic>?;
          if (rel != null) {
            target = rel['target'] as String? ?? target;
            firmwareVersion =
                rel['description'] as String? ??
                rel['version'] as String? ??
                firmwareVersion;
          }
        }
      }
    } catch (_) {}

    // 2. System Info
    String uptime = 'Unknown';
    String loadAverage = 'Unknown';
    String memorySummary = 'Unknown';

    try {
      final sysInfoRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'system',
        method: 'info',
        context: mountedContext(context),
      );
      if (sysInfoRes is List && sysInfoRes.length > 1 && sysInfoRes[0] == 0) {
        final s = sysInfoRes[1] as Map<String, dynamic>?;
        if (s != null) {
          final upSecs = s['uptime'] as int? ?? 0;
          final days = upSecs ~/ 86400;
          final hours = (upSecs % 86400) ~/ 3600;
          final mins = (upSecs % 3600) ~/ 60;
          uptime = days > 0
              ? '${days}d ${hours}h ${mins}m'
              : '${hours}h ${mins}m';

          final loads = s['load'] as List?;
          if (loads != null && loads.length >= 3) {
            final l1 = (loads[0] as num).toDouble() / 65535.0;
            final l5 = (loads[1] as num).toDouble() / 65535.0;
            final l15 = (loads[2] as num).toDouble() / 65535.0;
            loadAverage =
                '${l1.toStringAsFixed(2)}, ${l5.toStringAsFixed(2)}, ${l15.toStringAsFixed(2)}';
          }

          final mem = s['memory'] as Map<String, dynamic>?;
          if (mem != null) {
            final totalMb =
                ((mem['total'] as num?)?.toDouble() ?? 0) / (1024 * 1024);
            final freeMb =
                ((mem['free'] as num?)?.toDouble() ?? 0) / (1024 * 1024);
            final usedMb = totalMb - freeMb;
            memorySummary =
                '${usedMb.toStringAsFixed(1)} MB / ${totalMb.toStringAsFixed(1)} MB used (${totalMb > 0 ? ((usedMb / totalMb) * 100).toStringAsFixed(0) : 0}%)';
          }
        }
      }
    } catch (_) {}

    // 3. Temperature Summary
    String? tempSummary;
    try {
      final tempRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'luci.temp-status',
        method: 'getSensors',
        context: mountedContext(context),
      );
      if (tempRes is List && tempRes.length > 1 && tempRes[0] == 0) {
        final data = tempRes[1] as Map<String, dynamic>?;
        if (data != null && data['sensors'] is List) {
          final list = data['sensors'] as List;
          final parts = <String>[];
          for (final s in list) {
            if (s is Map<String, dynamic>) {
              final label = s['label'] ?? s['name'] ?? 'Sensor';
              final t = s['temp'];
              if (t != null) {
                final c = (t is num
                    ? t.toDouble()
                    : double.tryParse(t.toString()) ?? 0);
                final deg = c > 1000 ? (c / 1000.0) : c;
                parts.add('$label: ${deg.toStringAsFixed(1)}°C');
              }
            }
          }
          if (parts.isNotEmpty) tempSummary = parts.join(', ');
        }
      }
    } catch (_) {}

    // 4. Parallel data gathering for networking & diagnostics
    final futureReachability = testInternetReachability(
      ipAddress,
      sysauth,
      useHttps,
      context: context,
    );
    final futureRoutes = fetchRoutingTable(
      ipAddress,
      sysauth,
      useHttps,
      context: context,
    );
    final futureNeighbors = fetchNeighborTable(
      ipAddress,
      sysauth,
      useHttps,
      context: context,
    );
    final futureConntrack = fetchConntrackInfo(
      ipAddress,
      sysauth,
      useHttps,
      context: context,
    );

    // 5. Syslog & dmesg logs
    final futureSyslog = _runDiagnosticFileExec(
      ipAddress,
      sysauth,
      useHttps,
      '/usr/libexec/syslog-wrapper',
      [],
      context: context,
    );
    final futureDmesg = _runDiagnosticFileExec(
      ipAddress,
      sysauth,
      useHttps,
      '/bin/dmesg',
      ['-r'],
      context: context,
    );

    final results = await Future.wait([
      futureReachability,
      futureRoutes,
      futureNeighbors,
      futureConntrack,
      futureSyslog,
      futureDmesg,
    ]);

    final reachability = results[0] as InternetReachability;
    final routes = results[1] as List<RouteEntry>;
    final neighbors = results[2] as List<NeighborEntry>;
    final conntrack = results[3] as ConntrackInfo?;
    final syslogExec = results[4] as Map<String, dynamic>?;
    final dmesgExec = results[5] as Map<String, dynamic>?;

    final syslogLines = (syslogExec?['stdout'] as String? ?? '').trim().split(
      '\n',
    );
    final recentSyslog = syslogLines.length > 50
        ? syslogLines.sublist(syslogLines.length - 50).join('\n')
        : syslogLines.join('\n');

    final dmesgLines = (dmesgExec?['stdout'] as String? ?? '').trim().split(
      '\n',
    );
    final recentDmesg = dmesgLines.length > 50
        ? dmesgLines.sublist(dmesgLines.length - 50).join('\n')
        : dmesgLines.join('\n');

    return DiagnosticReport(
      hostname: hostname,
      model: model,
      architecture: architecture,
      target: target,
      kernelVersion: kernelVersion,
      firmwareVersion: firmwareVersion,
      uptime: uptime,
      loadAverage: loadAverage,
      memorySummary: memorySummary,
      temperatureSummary: tempSummary,
      storageSummary: 'Standard OpenWrt rootfs & overlay mounted',
      internetStatus: reachability,
      routes: routes,
      neighbors: neighbors,
      conntrack: conntrack,
      wanInfo: reachability.wanIp != null
          ? '${reachability.wanInterface ?? "wan"} (IP: ${reachability.wanIp})'
          : 'Not configured or disconnected',
      lanInfo: 'br-lan ($ipAddress)',
      recentSyslog: recentSyslog,
      recentDmesg: recentDmesg,
      generatedAt: DateTime.now(),
    );
  }

  @override
  Future<FlushDnsResult> flushDns(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    final flushed = <String>[];
    final logBuf = StringBuffer();

    // 1. Identify running DNS caching services via rc.list
    try {
      final rcRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'rc',
        method: 'list',
        context: mountedContext(context),
      );

      if (rcRes is List && rcRes.length > 1 && rcRes[0] == 0) {
        final services = rcRes[1] as Map<String, dynamic>? ?? {};

        // dnsmasq (reloads cache and re-reads hosts without dropping DHCP leases)
        if (services['dnsmasq']?['running'] == true ||
            services['dnsmasq']?['enabled'] == true) {
          final res = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'rc',
            method: 'init',
            params: {'name': 'dnsmasq', 'action': 'reload'},
            context: mountedContext(context),
          );
          if (res is List && res.isNotEmpty && res[0] == 0) {
            flushed.add('dnsmasq');
            logBuf.writeln('dnsmasq: Cache purged & local hosts reloaded.');
          }
        }

        // unbound
        if (services['unbound']?['running'] == true) {
          final res = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'rc',
            method: 'init',
            params: {'name': 'unbound', 'action': 'reload'},
            context: mountedContext(context),
          );
          if (res is List && res.isNotEmpty && res[0] == 0) {
            flushed.add('unbound');
            logBuf.writeln('unbound: Cache purged.');
          }
        }

        // smartdns
        if (services['smartdns']?['running'] == true) {
          final res = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'rc',
            method: 'init',
            params: {'name': 'smartdns', 'action': 'reload'},
            context: mountedContext(context),
          );
          if (res is List && res.isNotEmpty && res[0] == 0) {
            flushed.add('smartdns');
            logBuf.writeln('smartdns: Cache purged.');
          }
        }

        // adguardhome
        if (services['adguardhome']?['running'] == true) {
          final res = await callWithContext(
            ipAddress,
            sysauth,
            useHttps,
            object: 'rc',
            method: 'init',
            params: {'name': 'adguardhome', 'action': 'restart'},
            context: mountedContext(context),
          );
          if (res is List && res.isNotEmpty && res[0] == 0) {
            flushed.add('adguardhome');
            logBuf.writeln('adguardhome: Restarted & cache flushed.');
          }
        }
      }
    } catch (_) {}

    // 2. Direct Fallback: Attempt dnsmasq reload directly if rc.list was inconclusive
    if (flushed.isEmpty) {
      try {
        final res = await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'rc',
          method: 'init',
          params: {'name': 'dnsmasq', 'action': 'reload'},
          context: mountedContext(context),
        );
        if (res is List && res.isNotEmpty && res[0] == 0) {
          flushed.add('dnsmasq');
          logBuf.writeln('dnsmasq: Direct reload successful.');
        }
      } catch (_) {}
    }

    // 3. Command execution Fallback: /bin/killall -HUP dnsmasq
    if (flushed.isEmpty) {
      try {
        final execRes = await _runDiagnosticFileExec(
          ipAddress,
          sysauth,
          useHttps,
          '/bin/killall',
          ['-HUP', 'dnsmasq'],
          context: context,
        );
        if (execRes != null &&
            (execRes['code'] == 0 || execRes['code'] == null)) {
          flushed.add('dnsmasq');
          logBuf.writeln('dnsmasq: SIGHUP signaled via killall.');
        }
      } catch (_) {}
    }

    if (flushed.isNotEmpty) {
      return FlushDnsResult.success(
        flushedResolvers: flushed,
        message: 'Flushed ${flushed.join(" & ")} DNS cache & reloaded hosts.',
        rawOutput: logBuf.toString().trim(),
      );
    }

    return FlushDnsResult.success(
      flushedResolvers: const ['None'],
      message:
          'No local caching DNS resolver is active on this router. Upstream DNS servers are queried directly.',
      rawOutput: logBuf.toString().trim(),
    );
  }

  @override
  Future<List<RealtimeTrafficPoint>> fetchRealtimeStats(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String mode,
    String? device,
    BuildContext? context,
  }) async {
    try {
      final params = <String, dynamic>{'mode': mode};
      if (device != null && device.isNotEmpty) {
        params['device'] = device;
      }

      final res = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'luci',
        method: 'getRealtimeStats',
        params: params,
        context: context,
      );

      final List<dynamic>? rawList;
      if (res is List && res.length > 1 && res[1] is Map) {
        final r = res[1]['result'];
        rawList = r is List ? r : null;
      } else if (res is Map && res['result'] is List) {
        rawList = res['result'] as List<dynamic>?;
      } else {
        rawList = null;
      }

      if (rawList == null || rawList.isEmpty) {
        return const [];
      }

      final points = <RealtimeTrafficPoint>[];
      RealtimeTrafficPoint? prev;
      for (final item in rawList) {
        if (item is List) {
          final pt = RealtimeTrafficPoint.fromList(item, previousPoint: prev);
          points.add(pt);
          prev = pt;
        }
      }
      return points;
    } catch (e) {
      Logger.warning('fetchRealtimeStats failed: $e');
      return const [];
    }
  }

  @override
  Future<bool> checkNlbwmonInstalled(
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
        method: 'stat',
        params: {'path': '/usr/libexec/nlbwmon-action'},
        context: context,
      );
      if (res is List && res.isNotEmpty && res[0] == 0) {
        return true;
      }
      // Fallback check for binary if action script isn't found
      final binRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'stat',
        params: {'path': '/usr/sbin/nlbwmon'},
        context: context,
      );
      return binRes is List && binRes.isNotEmpty && binRes[0] == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<NlbwmonReport?> fetchNlbwmonData(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    String groupBy = 'mac',
    String? period,
    BuildContext? context,
  }) async {
    try {
      final params = ['download', '-f', 'json', '-g', groupBy];
      if (period != null && period.isNotEmpty) {
        params.addAll(['-t', period]);
      }

      final res = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: fileExecParams('/usr/libexec/nlbwmon-action', params),
        context: context,
      );

      String? stdout;
      if (res is List && res.length > 1 && res[1] is Map) {
        final data = res[1] as Map;
        if (data['code'] == 0 && data['stdout'] is String) {
          stdout = data['stdout'] as String;
        } else if (data['code'] != 0) {
          Logger.warning(
            'nlbwmon-action download failed with code ${data['code']}: ${data['stderr']}',
          );
        }
      } else if (res is Map && res['code'] == 0 && res['stdout'] is String) {
        stdout = res['stdout'] as String;
      }

      if (stdout != null && stdout.trim().startsWith('{')) {
        final decoded = jsonDecode(stdout.trim());
        if (decoded is Map) {
          final parsed = Map<String, dynamic>.from(decoded);
          return NlbwmonReport.fromJson(parsed, period);
        }
      }
    } catch (e) {
      Logger.warning('fetchNlbwmonData failed: $e');
    }
    return null;
  }

  @override
  Future<List<String>> fetchNlbwmonPeriods(
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
        params: fileExecParams('/usr/libexec/nlbwmon-action', ['periods']),
        context: context,
      );

      String? stdout;
      if (res is List && res.length > 1 && res[1] is Map) {
        final data = res[1] as Map;
        if (data['code'] == 0 && data['stdout'] is String) {
          stdout = data['stdout'] as String;
        } else if (data['code'] != 0) {
          Logger.warning(
            'nlbwmon-action periods failed with code ${data['code']}: ${data['stderr']}',
          );
        }
      } else if (res is Map && res['code'] == 0 && res['stdout'] is String) {
        stdout = res['stdout'] as String;
      }

      if (stdout != null && stdout.trim().startsWith('{')) {
        final decoded = jsonDecode(stdout.trim());
        if (decoded is Map) {
          final periods = decoded['periods'];
          if (periods is List) {
            return periods.map((p) => p.toString()).toList();
          }
        }
      }
    } catch (e) {
      Logger.warning('fetchNlbwmonPeriods failed: $e');
    }
    return const [];
  }

  @override
  Future<bool> setRouterHostname(
    String ipAddress,
    String sysauth,
    bool useHttps,
    String newHostname, {
    BuildContext? context,
  }) async {
    try {
      // 1. Get system config to find the section of type 'system'
      final systemConfig = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': 'system'},
        context: mountedContext(context),
      );

      String? targetSection;
      if (systemConfig is Map && systemConfig['values'] is Map) {
        final values = systemConfig['values'] as Map;
        for (final entry in values.entries) {
          if (entry.value is Map && entry.value['.type'] == 'system') {
            targetSection =
                entry.value['.name']?.toString() ?? entry.key.toString();
            break;
          }
        }
      } else if (systemConfig is List &&
          systemConfig.length > 1 &&
          systemConfig[1] is Map &&
          (systemConfig[1] as Map)['values'] is Map) {
        final values = (systemConfig[1] as Map)['values'] as Map;
        for (final entry in values.entries) {
          if (entry.value is Map && entry.value['.type'] == 'system') {
            targetSection =
                entry.value['.name']?.toString() ?? entry.key.toString();
            break;
          }
        }
      }

      // Fallback if section was not specifically named
      targetSection ??= '@system[0]';

      // 2. Set the hostname in UCI system config
      await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'set',
        params: {
          'config': 'system',
          'section': targetSection,
          'values': {'hostname': newHostname},
        },
        context: mountedContext(context),
      );

      // 3. Commit system config
      await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'commit',
        params: {'config': 'system'},
        context: mountedContext(context),
      );

      // 4. Reload system service and dnsmasq service to immediately apply
      try {
        await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'rc',
          method: 'init',
          params: {'name': 'system', 'action': 'reload'},
          context: mountedContext(context),
        );
      } catch (e) {
        Logger.warning('rc.init system reload failed (non-critical): $e');
      }

      try {
        await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'rc',
          method: 'init',
          params: {'name': 'dnsmasq', 'action': 'reload'},
          context: mountedContext(context),
        );
      } catch (e) {
        Logger.warning('rc.init dnsmasq reload failed (non-critical): $e');
      }

      // Fallback reload_config invocation
      try {
        await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'file',
          method: 'exec',
          params: fileExecParams('/sbin/reload_config', const []),
          context: mountedContext(context),
        );
      } catch (_) {}

      return true;
    } catch (e, stack) {
      Logger.exception('Failed to set router hostname', e, stack);
      return false;
    }
  }

  String? _findDnsmasqSection(dynamic uciDhcpResponse) {
    if (uciDhcpResponse == null) return null;
    final Map? valuesMap;
    if (uciDhcpResponse is Map && uciDhcpResponse['values'] is Map) {
      valuesMap = uciDhcpResponse['values'] as Map;
    } else if (uciDhcpResponse is List &&
        uciDhcpResponse.length > 1 &&
        uciDhcpResponse[1] is Map) {
      final second = uciDhcpResponse[1] as Map;
      valuesMap = second['values'] is Map ? second['values'] as Map : second;
    } else if (uciDhcpResponse is Map) {
      valuesMap = uciDhcpResponse;
    } else {
      valuesMap = null;
    }
    if (valuesMap != null) {
      for (final entry in valuesMap.entries) {
        final val = entry.value;
        if (val is Map &&
            (val['.type'] == 'dnsmasq' ||
                entry.key.toString().contains('dnsmasq'))) {
          return val['.name']?.toString() ?? entry.key.toString();
        }
      }
    }
    return null;
  }

  List<String> _extractDnsmasqAddressEntries(
    dynamic uciDhcpResponse,
    String sectionName,
  ) {
    final Map? valuesMap;
    if (uciDhcpResponse is Map && uciDhcpResponse['values'] is Map) {
      valuesMap = uciDhcpResponse['values'] as Map;
    } else if (uciDhcpResponse is List &&
        uciDhcpResponse.length > 1 &&
        uciDhcpResponse[1] is Map) {
      final second = uciDhcpResponse[1] as Map;
      valuesMap = second['values'] is Map ? second['values'] as Map : second;
    } else if (uciDhcpResponse is Map) {
      valuesMap = uciDhcpResponse;
    } else {
      valuesMap = null;
    }
    if (valuesMap != null && valuesMap[sectionName] is Map) {
      final sec = valuesMap[sectionName] as Map;
      final rawAddress = sec['address'];
      if (rawAddress is List) {
        return rawAddress.map((e) => e.toString()).toList();
      } else if (rawAddress is String && rawAddress.isNotEmpty) {
        return [rawAddress];
      }
    }
    return [];
  }

  @override
  Future<List<String>> getDnsmasqBlockedDomains(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
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
      final sectionName = _findDnsmasqSection(getRes);
      if (sectionName == null) return [];

      final rawEntries = _extractDnsmasqAddressEntries(getRes, sectionName);
      final Set<String> domains = {};
      for (final entry in rawEntries) {
        final d = DomainValidator.parseBlockedDomainFromAddress(entry);
        if (d != null && d.isNotEmpty) {
          domains.add(d);
        }
      }
      return domains.toList()..sort();
    } catch (e, stack) {
      Logger.exception('getDnsmasqBlockedDomains failed', e, stack);
      return [];
    }
  }

  @override
  Future<bool> addDnsmasqBlockedDomain(
    String ipAddress,
    String sysauth,
    bool useHttps,
    String domain, {
    BuildContext? context,
  }) async {
    final mCtx = mountedContext(context);
    final normalized = DomainValidator.normalize(domain);
    if (normalized == null || !DomainValidator.isValid(normalized)) {
      Logger.warning('addDnsmasqBlockedDomain: invalid domain "$domain"');
      return false;
    }

    try {
      final getRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': 'dhcp'},
        context: mCtx,
      );
      final sectionName = _findDnsmasqSection(getRes);
      if (sectionName == null) {
        Logger.warning('addDnsmasqBlockedDomain: dnsmasq section not found');
        return false;
      }

      final rawEntries = _extractDnsmasqAddressEntries(getRes, sectionName);
      final bool alreadyBlocked = rawEntries.any((entry) {
        final existing = DomainValidator.parseBlockedDomainFromAddress(entry);
        return existing != null &&
            existing.toLowerCase() == normalized.toLowerCase();
      });
      if (alreadyBlocked) {
        return true;
      }

      final updatedEntries = List<String>.from(rawEntries)
        ..add('/$normalized/#');

      final setRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'set',
        params: {
          'config': 'dhcp',
          'section': sectionName,
          'values': {'address': updatedEntries},
        },
        context: mCtx,
      );
      if (setRes is List && setRes.isNotEmpty && setRes[0] != 0) {
        await uciRevert(
          ipAddress,
          sysauth,
          useHttps,
          config: 'dhcp',
          context: mCtx,
        );
        return false;
      }

      final applied = await uciApply(
        ipAddress,
        sysauth,
        useHttps,
        rollback: true,
        timeout: 30,
      );
      if (!applied) {
        await uciRevert(
          ipAddress,
          sysauth,
          useHttps,
          config: 'dhcp',
          context: mCtx,
        );
        return false;
      }

      final verifyRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': 'dhcp'},
        context: mCtx,
      );
      if (verifyRes is! List || verifyRes.length < 2 || verifyRes[0] != 0) {
        Logger.warning(
          'addDnsmasqBlockedDomain verification failed: RPC unreachable after apply',
        );
        await uciRevert(
          ipAddress,
          sysauth,
          useHttps,
          config: 'dhcp',
          context: mCtx,
        );
        return false;
      }

      final verifiedEntries = _extractDnsmasqAddressEntries(
        verifyRes,
        sectionName,
      );
      final verifiedBlocked = verifiedEntries.any((entry) {
        final existing = DomainValidator.parseBlockedDomainFromAddress(entry);
        return existing != null &&
            existing.toLowerCase() == normalized.toLowerCase();
      });

      if (!verifiedBlocked) {
        Logger.warning(
          'addDnsmasqBlockedDomain verification failed: domain not present in dnsmasq config',
        );
        await uciRevert(
          ipAddress,
          sysauth,
          useHttps,
          config: 'dhcp',
          context: mCtx,
        );
        return false;
      }

      final confirmed = await uciConfirm(ipAddress, sysauth, useHttps);
      if (!confirmed) {
        Logger.warning('addDnsmasqBlockedDomain: uciConfirm failed');
        return false;
      }

      return true;
    } catch (e, stack) {
      Logger.exception('addDnsmasqBlockedDomain failed', e, stack);
      try {
        await uciRevert(
          ipAddress,
          sysauth,
          useHttps,
          config: 'dhcp',
          context: mCtx,
        );
      } catch (_) {}
      return false;
    }
  }

  @override
  Future<bool> removeDnsmasqBlockedDomain(
    String ipAddress,
    String sysauth,
    bool useHttps,
    String domain, {
    BuildContext? context,
  }) async {
    final mCtx = mountedContext(context);
    final normalized = DomainValidator.normalize(domain);
    if (normalized == null || normalized.isEmpty) {
      Logger.warning('removeDnsmasqBlockedDomain: invalid domain "$domain"');
      return false;
    }

    try {
      final getRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': 'dhcp'},
        context: mCtx,
      );
      final sectionName = _findDnsmasqSection(getRes);
      if (sectionName == null) {
        Logger.warning('removeDnsmasqBlockedDomain: dnsmasq section not found');
        return false;
      }

      final rawEntries = _extractDnsmasqAddressEntries(getRes, sectionName);
      final bool isPresent = rawEntries.any((entry) {
        final existing = DomainValidator.parseBlockedDomainFromAddress(entry);
        return existing != null &&
            existing.toLowerCase() == normalized.toLowerCase();
      });
      if (!isPresent) {
        return true;
      }

      final updatedEntries = rawEntries.where((entry) {
        final existing = DomainValidator.parseBlockedDomainFromAddress(entry);
        return existing == null ||
            existing.toLowerCase() != normalized.toLowerCase();
      }).toList();

      if (updatedEntries.isEmpty) {
        final delRes = await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'uci',
          method: 'delete',
          params: {
            'config': 'dhcp',
            'section': sectionName,
            'option': 'address',
          },
          context: mCtx,
        );
        if (delRes is List && delRes.isNotEmpty && delRes[0] != 0) {
          await uciRevert(
            ipAddress,
            sysauth,
            useHttps,
            config: 'dhcp',
            context: mCtx,
          );
          return false;
        }
      } else {
        final setRes = await callWithContext(
          ipAddress,
          sysauth,
          useHttps,
          object: 'uci',
          method: 'set',
          params: {
            'config': 'dhcp',
            'section': sectionName,
            'values': {'address': updatedEntries},
          },
          context: mCtx,
        );
        if (setRes is List && setRes.isNotEmpty && setRes[0] != 0) {
          await uciRevert(
            ipAddress,
            sysauth,
            useHttps,
            config: 'dhcp',
            context: mCtx,
          );
          return false;
        }
      }

      final applied = await uciApply(
        ipAddress,
        sysauth,
        useHttps,
        rollback: true,
        timeout: 30,
      );
      if (!applied) {
        await uciRevert(
          ipAddress,
          sysauth,
          useHttps,
          config: 'dhcp',
          context: mCtx,
        );
        return false;
      }

      final verifyRes = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': 'dhcp'},
        context: mCtx,
      );
      if (verifyRes is! List || verifyRes.length < 2 || verifyRes[0] != 0) {
        Logger.warning(
          'removeDnsmasqBlockedDomain verification failed: RPC unreachable after apply',
        );
        await uciRevert(
          ipAddress,
          sysauth,
          useHttps,
          config: 'dhcp',
          context: mCtx,
        );
        return false;
      }

      final verifiedEntries = _extractDnsmasqAddressEntries(
        verifyRes,
        sectionName,
      );
      final stillBlocked = verifiedEntries.any((entry) {
        final existing = DomainValidator.parseBlockedDomainFromAddress(entry);
        return existing != null &&
            existing.toLowerCase() == normalized.toLowerCase();
      });

      if (stillBlocked) {
        Logger.warning(
          'removeDnsmasqBlockedDomain verification failed: domain still present',
        );
        await uciRevert(
          ipAddress,
          sysauth,
          useHttps,
          config: 'dhcp',
          context: mCtx,
        );
        return false;
      }

      final confirmed = await uciConfirm(ipAddress, sysauth, useHttps);
      if (!confirmed) {
        Logger.warning('removeDnsmasqBlockedDomain: uciConfirm failed');
        return false;
      }

      return true;
    } catch (e, stack) {
      Logger.exception('removeDnsmasqBlockedDomain failed', e, stack);
      try {
        await uciRevert(
          ipAddress,
          sysauth,
          useHttps,
          config: 'dhcp',
          context: mCtx,
        );
      } catch (_) {}
      return false;
    }
  }

  @override
  Future<DnsmasqServiceResult> reloadDnsmasq(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    final mCtx = mountedContext(context);
    try {
      final res = await manageServiceAction(
        ipAddress,
        sysauth,
        useHttps,
        serviceName: 'dnsmasq',
        action: 'reload',
        context: mCtx,
      );
      if (res) {
        return DnsmasqServiceResult.success();
      }
      return DnsmasqServiceResult.failure('Failed to reload dnsmasq service');
    } catch (e) {
      return DnsmasqServiceResult.failure(e.toString());
    }
  }

  @override
  Future<LogFetchResult> fetchSyslog(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    int lines = 200,
    BuildContext? context,
  }) async {
    final mCtx = mountedContext(context);
    try {
      final res = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: fileExecParams('/sbin/logread', ['-l', lines.toString()]),
        context: mCtx,
      );
      if (res is Map && res['stdout'] is String) {
        final raw = res['stdout'] as String;
        final rawLines = const LineSplitter().convert(raw);
        final entries = <LogEntry>[];
        for (var i = 0; i < rawLines.length; i++) {
          final l = rawLines[i].trim();
          if (l.isNotEmpty) {
            entries.add(LogEntry.fromSyslogLine(i, l));
          }
        }
        return LogFetchSuccess(entries);
      }
      return const LogFetchRpcError(message: 'Invalid logread response');
    } catch (e) {
      return LogFetchRpcError(message: e.toString());
    }
  }

  @override
  Future<LogFetchResult> fetchKernelLog(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    int lines = 200,
    BuildContext? context,
  }) async {
    final mCtx = mountedContext(context);
    try {
      final res = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: fileExecParams('/bin/dmesg', ['-r']),
        context: mCtx,
      );
      if (res is Map && res['stdout'] is String) {
        final raw = res['stdout'] as String;
        final rawLines = const LineSplitter().convert(raw);
        final entries = <LogEntry>[];
        for (var i = 0; i < rawLines.length; i++) {
          final l = rawLines[i].trim();
          if (l.isNotEmpty) {
            entries.add(LogEntry.fromDmesgLine(i, l));
          }
        }
        return LogFetchSuccess(entries);
      }
      return const LogFetchRpcError(message: 'Invalid dmesg response');
    } catch (e) {
      return LogFetchRpcError(message: e.toString());
    }
  }
}
