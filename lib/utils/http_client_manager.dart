// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'logger.dart';

/// HTTP client manager that provides secure client instances with proper
/// certificate validation and connection pooling
class HttpClientManager {
  static final HttpClientManager _instance = HttpClientManager._internal();
  factory HttpClientManager() => _instance;
  Future<void>? _initFuture;

  /// Ensures accepted certificates are fully loaded from secure storage before network calls
  Future<void> ensureInitialized() {
    _initFuture ??= _loadAcceptedCertificates();
    return _initFuture!;
  }

  HttpClientManager._internal() {
    ensureInitialized();
  }

  final Map<String, Dio> _clients = {};
  final Map<String, bool> _userAcceptedCerts = {};
  static const String _acceptedCertsKey = 'accepted_certificates';

  /// Creates or returns a cached HTTP client for the given host
  /// In production builds, certificate validation is enforced with user warnings
  /// In debug builds, self-signed certificates can be allowed automatically
  Dio getClient(String hostWithPort, bool useHttps, {BuildContext? context}) {
    // Extract just the hostname without port for certificate validation
    final host = _extractHostname(hostWithPort);
    final key = '$hostWithPort-$useHttps';

    if (_clients.containsKey(key)) {
      return _clients[key]!;
    }

    final client = _createSecureClient(host, useHttps, context: context);
    _clients[key] = client;
    return client;
  }

  String _extractHostname(String hostWithPort) {
    // Remove port if present (handles both IPv4 and IPv6)
    if (hostWithPort.startsWith('[')) {
      // IPv6 address
      final endBracket = hostWithPort.indexOf(']');
      if (endBracket != -1) {
        return hostWithPort.substring(0, endBracket + 1);
      }
    } else {
      // IPv4 or hostname
      final colonIndex = hostWithPort.lastIndexOf(':');
      if (colonIndex != -1) {
        // Check if what follows the colon is a port number
        final portPart = hostWithPort.substring(colonIndex + 1);
        if (int.tryParse(portPart) != null) {
          return hostWithPort.substring(0, colonIndex);
        }
      }
    }
    return hostWithPort;
  }

  Dio _createSecureClient(String host, bool useHttps, {BuildContext? context}) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        followRedirects: true,
        // Status is validated per request when needed (e.g., handle 302 on login)
      ),
    );

    // Automatically evict dead cached clients on socket/connection errors
    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (e, handler) {
          Logger.error(
            'HTTP ${e.requestOptions.method} ${e.requestOptions.uri} failed',
            e,
            e.stackTrace,
          );

          if (e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.sendTimeout ||
              e.type == DioExceptionType.receiveTimeout ||
              e.type == DioExceptionType.connectionError ||
              e.error is SocketException) {
            Logger.info(
              'Network transition or socket failure detected for $host. Evicting stale client.',
            );
            disposeClient(host, useHttps, forceCloseAdapter: false);
          }

          handler.next(e);
        },
      ),
    );

    final adapter = IOHttpClientAdapter();
    adapter.createHttpClient = () {
      final httpClient = HttpClient();
      httpClient.connectionTimeout = const Duration(seconds: 15);
      httpClient.badCertificateCallback = (cert, certHost, port) {
        final certKey = '$certHost:$port';
        if (_userAcceptedCerts[certKey] == true ||
            _userAcceptedCerts[certHost] == true) {
          return true;
        }
        // Self-signed SSL certificates are standard on local OpenWrt routers
        if (_isLocalOrPrivateHost(certHost) || _isLocalOrPrivateHost(host)) {
          return true;
        }
        return false;
      };
      return httpClient;
    };
    dio.httpClientAdapter = adapter;

    return dio;
  }

  /// Helper to check if a hostname/IP belongs to private/local router networks
  static bool _isLocalOrPrivateHost(String host) {
    if (host.isEmpty) return false;
    var lowerHost = host.toLowerCase().trim();
    if (lowerHost.startsWith('[') && lowerHost.endsWith(']')) {
      lowerHost = lowerHost.substring(1, lowerHost.length - 1).trim();
    }

    // Check for localhost / local domains
    if (lowerHost == 'localhost' ||
        lowerHost == 'openwrt' ||
        lowerHost.endsWith('.local') ||
        lowerHost.endsWith('.lan')) {
      return true;
    }

    // Try parsing as IPv4
    try {
      final parts = host.split('.');
      if (parts.length == 4) {
        final octets = parts.map(int.tryParse).toList();
        if (octets.every((o) => o != null && o >= 0 && o <= 255)) {
          final o0 = octets[0]!;
          final o1 = octets[1]!;

          // 127.0.0.0/8 (Loopback)
          if (o0 == 127) return true;
          // 10.0.0.0/8 (Private Class A)
          if (o0 == 10) return true;
          // 172.16.0.0/12 (Private Class B)
          if (o0 == 172 && o1 >= 16 && o1 <= 31) return true;
          // 192.168.0.0/16 (Private Class C)
          if (o0 == 192 && o1 == 168) return true;
          // 169.254.0.0/16 (Link-Local)
          if (o0 == 169 && o1 == 254) return true;
        }
      }
    } catch (_) {}

    // Try parsing as IPv6 (link-local fe80::, unique local fc00::/fd00::, loopback ::1)
    if (host.contains(':')) {
      if (lowerHost == '::1' ||
          lowerHost.startsWith('fe80:') ||
          lowerHost.startsWith('fc00:') ||
          lowerHost.startsWith('fd00:')) {
        return true;
      }
    }

    return false;
  }

  /// Load accepted certificates from secure storage
  Future<void> _loadAcceptedCertificates() async {
    try {
      final storage = const FlutterSecureStorage();
      final certsJson = await storage.read(key: _acceptedCertsKey);
      if (certsJson != null) {
        final certs = Map<String, dynamic>.from(jsonDecode(certsJson));
        _userAcceptedCerts.clear();
        certs.forEach((key, value) {
          if (value == true) {
            _userAcceptedCerts[key] = true;
          }
        });
      }
    } catch (e) {
      // Ignore errors loading certificates
    }
  }

  /// Save accepted certificates to secure storage
  Future<void> _saveAcceptedCertificates() async {
    try {
      final storage = const FlutterSecureStorage();
      await storage.write(
        key: _acceptedCertsKey,
        value: jsonEncode(_userAcceptedCerts),
      );
    } catch (e) {
      // Ignore errors saving certificates
    }
  }

  /// Disposes of a specific client
  void disposeClient(
    String host,
    bool useHttps, {
    bool forceCloseAdapter = false,
  }) {
    // Remove any cached clients that match the host (with or without port)
    final hostname = _extractHostname(host);
    final keysToRemove = _clients.keys
        .where(
          (k) =>
              (k.startsWith(host) || k.startsWith(hostname)) &&
              k.endsWith('-$useHttps'),
        )
        .toList();
    for (final key in keysToRemove) {
      final dio = _clients.remove(key);
      if (forceCloseAdapter) {
        final adapter = dio?.httpClientAdapter;
        if (adapter is IOHttpClientAdapter) {
          adapter.close(force: true);
        }
      }
    }
  }

  /// Disposes of all cached clients
  void disposeAll({bool forceCloseAdapter = false}) {
    for (final dio in _clients.values) {
      if (forceCloseAdapter) {
        final adapter = dio.httpClientAdapter;
        if (adapter is IOHttpClientAdapter) {
          adapter.close(force: true);
        }
      }
    }
    _clients.clear();
    // Don't clear accepted certificates on dispose
  }

  /// Clear accepted certificates (useful for logout or security reset)
  Future<void> clearAcceptedCertificates() async {
    // Clear in-memory certificates
    _userAcceptedCerts.clear();

    // Clear all cached HTTP clients
    disposeAll(forceCloseAdapter: true);

    // Delete from secure storage
    try {
      final storage = const FlutterSecureStorage();
      await storage.delete(key: _acceptedCertsKey);
    } catch (e) {
      // Ignore errors
    }
  }

  /// Clear certificates for a specific host
  Future<void> clearCertificatesForHost(String host) async {
    // Remove certificates for this host across all ports
    _userAcceptedCerts.removeWhere(
      (key, _) => key == host || key.startsWith('$host:'),
    );

    // Close and remove cached HTTP clients for this host
    final keysToRemove = _clients.keys
        .where((key) => key.startsWith(host))
        .toList();
    for (final key in keysToRemove) {
      _clients[key]?.close();
      _clients.remove(key);
    }

    // Save the updated certificates
    await _saveAcceptedCertificates();
  }

  /// Prompts user to accept certificate for a given host
  /// Returns true if user accepts, false otherwise
  Future<bool> promptForCertificateAcceptance({
    required BuildContext context,
    required String hostWithPort,
    required bool useHttps,
  }) async {
    if (!useHttps) return true; // Non-HTTPS doesn't need certificate acceptance
    if (!context.mounted) return false;

    final host = _extractHostname(hostWithPort);

    // Parse the host to get the port if specified
    int port = 443; // Default HTTPS port
    if (hostWithPort.contains(':') && !hostWithPort.startsWith('[')) {
      final parts = hostWithPort.split(':');
      if (parts.length == 2) {
        port = int.tryParse(parts[1]) ?? 443;
      }
    }

    // Check if already accepted or local router host
    final certKey = '$host:$port';
    if (_userAcceptedCerts[certKey] == true ||
        _userAcceptedCerts[host] == true ||
        _isLocalOrPrivateHost(host)) {
      return true;
    }

    // Try to make a test connection to trigger certificate validation
    final testClient = HttpClient();
    testClient.connectionTimeout = const Duration(seconds: 15);

    // Apply the same certificate validation logic
    testClient.badCertificateCallback = (cert, certHost, port) {
      return _userAcceptedCerts['$certHost:$port'] == true ||
          _userAcceptedCerts[certHost] == true ||
          _isLocalOrPrivateHost(certHost);
    };

    try {
      final uri = Uri.parse('https://$hostWithPort');
      final request = await testClient.getUrl(uri);
      await request.close();
      // If we get here, certificate is already valid or accepted
      return true;
    } catch (e) {
      if (e is HandshakeException) {
        // Extract certificate details from the exception if possible
        // For now, show a simplified dialog
        if (context.mounted) {
          final result = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext dialogContext) => AlertDialog(
              icon: Icon(
                Icons.warning_amber_rounded,
                color: Theme.of(context).colorScheme.error,
                size: 32,
              ),
              title: const Text('Certificate Warning'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'The certificate for $host is not trusted by your device. This could indicate a security risk.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.errorContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Theme.of(context).colorScheme.error,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Only proceed if you trust this router and understand the security implications.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  child: const Text('Accept Risk'),
                ),
              ],
            ),
          );

          if (result == true) {
            // Store acceptance persistently
            _userAcceptedCerts['$host:$port'] = true;
            await _saveAcceptedCertificates();
            return true;
          }
        }
      }
    } finally {
      testClient.close();
    }

    return false;
  }
}

/// Dialog for warning users about untrusted certificates
class CertificateWarningDialog extends StatelessWidget {
  final X509Certificate certificate;
  final String host;
  final int port;

  const CertificateWarningDialog({
    super.key,
    required this.certificate,
    required this.host,
    required this.port,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      icon: Icon(
        Icons.warning_amber_rounded,
        color: colorScheme.error,
        size: 32,
      ),
      title: const Text('Certificate Warning'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The certificate for $host:$port is not trusted by your device. This could indicate a security risk.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Certificate Details:',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildCertDetail('Subject', certificate.subject),
                  _buildCertDetail('Issuer', certificate.issuer),
                  _buildCertDetail(
                    'Valid From',
                    certificate.startValidity.toLocal().toString().split(
                      '.',
                    )[0],
                  ),
                  _buildCertDetail(
                    'Valid Until',
                    certificate.endValidity.toLocal().toString().split('.')[0],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: colorScheme.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Only proceed if you trust this router and understand the security implications.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          child: const Text('Accept Risk'),
        ),
      ],
    );
  }

  Widget _buildCertDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(value, style: GoogleFonts.geistMono(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
