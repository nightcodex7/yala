// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Represents a matched device fingerprint rule (OUI or Hostname based).
class FingerprintMatch {
  final String vendor;
  final String deviceType;
  final String iconHint;

  const FingerprintMatch({
    required this.vendor,
    required this.deviceType,
    required this.iconHint,
  });

  factory FingerprintMatch.fromJson(Map<String, dynamic> json) {
    return FingerprintMatch(
      vendor: json['vendor']?.toString() ?? '',
      deviceType: json['device_type']?.toString() ?? '',
      iconHint: json['icon_hint']?.toString() ?? '',
    );
  }
}

class OuiRule {
  final String prefix;
  final FingerprintMatch match;

  OuiRule({required this.prefix, required this.match});
}

class HostnameRule {
  final RegExp pattern;
  final FingerprintMatch match;

  HostnameRule({required String rawPattern, required this.match})
    : pattern = RegExp(rawPattern, caseSensitive: false);
}

/// Service that loads local client fingerprints (base or advanced private layer).
class ClientFingerprintService {
  ClientFingerprintService._();
  static final ClientFingerprintService instance = ClientFingerprintService._();

  bool _isInitialized = false;
  String _activeEdition = 'uninitialized';
  final List<OuiRule> _ouiRules = [];
  final List<HostnameRule> _hostnameRules = [];

  bool get isInitialized => _isInitialized;
  String get activeEdition => _activeEdition;

  /// Loads fingerprint definitions, preferring advanced private asset if present.
  Future<void> initialize() async {
    if (_isInitialized) return;

    String? jsonContent;

    // 1. Try loading private advanced asset
    try {
      jsonContent = await rootBundle.loadString(
        'assets/fingerprints/advanced.json',
      );
    } catch (_) {
      // Advanced asset not bundled (e.g. FOSS Community Build)
      jsonContent = null;
    }

    // 2. Fall back to standard default base asset
    if (jsonContent == null || jsonContent.isEmpty) {
      try {
        jsonContent = await rootBundle.loadString(
          'assets/fingerprints/default.json',
        );
      } catch (e) {
        if (kDebugMode) {
          print(
            'ClientFingerprintService: Failed to load default fingerprints: $e',
          );
        }
      }
    }

    if (jsonContent != null && jsonContent.isNotEmpty) {
      _parseFingerprints(jsonContent);
    }

    _isInitialized = true;
  }

  void _parseFingerprints(String rawJson) {
    try {
      final Map<String, dynamic> decoded = jsonDecode(rawJson);
      _activeEdition = decoded['edition']?.toString() ?? 'unknown';

      final ouiList = decoded['oui_rules'] as List<dynamic>? ?? [];
      for (final item in ouiList) {
        if (item is Map<String, dynamic>) {
          final prefix = (item['prefix']?.toString() ?? '')
              .replaceAll(':', '')
              .replaceAll('-', '')
              .toUpperCase();
          if (prefix.isNotEmpty) {
            _ouiRules.add(
              OuiRule(prefix: prefix, match: FingerprintMatch.fromJson(item)),
            );
          }
        }
      }

      final hostList = decoded['hostname_rules'] as List<dynamic>? ?? [];
      for (final item in hostList) {
        if (item is Map<String, dynamic>) {
          final rawPat = item['pattern']?.toString() ?? '';
          if (rawPat.isNotEmpty) {
            try {
              _hostnameRules.add(
                HostnameRule(
                  rawPattern: rawPat,
                  match: FingerprintMatch.fromJson(item),
                ),
              );
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('ClientFingerprintService: Error parsing fingerprints: $e');
      }
    }
  }

  /// Lookup device match by MAC address (first 6 hex characters).
  FingerprintMatch? lookupByMac(String mac) {
    final cleanMac = mac.replaceAll(':', '').replaceAll('-', '').toUpperCase();
    if (cleanMac.length < 6) return null;
    final prefix6 = cleanMac.substring(0, 6);

    for (final rule in _ouiRules) {
      if (rule.prefix == prefix6) {
        return rule.match;
      }
    }
    return null;
  }

  /// Lookup device match by hostname regex rules.
  FingerprintMatch? lookupByHostname(String? hostname) {
    if (hostname == null || hostname.trim().isEmpty) return null;
    final cleanHost = hostname.trim();

    for (final rule in _hostnameRules) {
      if (rule.pattern.hasMatch(cleanHost)) {
        return rule.match;
      }
    }
    return null;
  }
}
