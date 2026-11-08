// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';

/// Immutable model representing bandwidth and speed restrictions for a specific client device.
@immutable
class ClientSpeedLimit {
  final String targetMac;
  final String ipAddress;
  final List<String> ipv6Addresses;
  final double downloadValue;
  final String downloadUnit; // 'Mbps' or 'Kbps'
  final double uploadValue;
  final String uploadUnit; // 'Mbps' or 'Kbps'
  final bool enabled;
  final String? hostname;
  final DateTime updatedAt;

  const ClientSpeedLimit({
    required this.targetMac,
    required this.ipAddress,
    this.ipv6Addresses = const [],
    required this.downloadValue,
    this.downloadUnit = 'Mbps',
    required this.uploadValue,
    this.uploadUnit = 'Mbps',
    this.enabled = true,
    this.hostname,
    required this.updatedAt,
  });

  /// Factory creating an unrestricted/disabled default speed limit object for [targetMac].
  factory ClientSpeedLimit.unrestricted({
    required String targetMac,
    required String ipAddress,
    List<String> ipv6Addresses = const [],
    String? hostname,
  }) {
    return ClientSpeedLimit(
      targetMac: ClientNamingHelper.normalizeMac(targetMac),
      ipAddress: ipAddress,
      ipv6Addresses: ipv6Addresses,
      downloadValue: 0,
      downloadUnit: 'Mbps',
      uploadValue: 0,
      uploadUnit: 'Mbps',
      enabled: false,
      hostname: hostname,
      updatedAt: DateTime.now(),
    );
  }

  /// Whether speed limiting is active and configured with non-zero rates.
  bool get isEffectivelyRestricted =>
      enabled && (downloadBitsPerSecond > 0 || uploadBitsPerSecond > 0);

  /// Download bandwidth rate in bits per second (bps).
  double get downloadBitsPerSecond {
    if (downloadValue <= 0) return 0.0;
    if (downloadUnit.toLowerCase() == 'kbps') {
      return downloadValue * 1000.0;
    }
    // Default to Mbps (decimal: 1,000,000 bits)
    return downloadValue * 1000000.0;
  }

  /// Upload bandwidth rate in bits per second (bps).
  double get uploadBitsPerSecond {
    if (uploadValue <= 0) return 0.0;
    if (uploadUnit.toLowerCase() == 'kbps') {
      return uploadValue * 1000.0;
    }
    // Default to Mbps (decimal: 1,000,000 bits)
    return uploadValue * 1000000.0;
  }

  /// Download bandwidth in bytes per second (B/s).
  double get downloadBytesPerSecond => downloadBitsPerSecond / 8.0;

  /// Upload bandwidth in bytes per second (B/s).
  double get uploadBytesPerSecond => uploadBitsPerSecond / 8.0;

  /// Download rate in integer bytes per second for netfilter token buckets.
  int get downloadBytesPerSecondInt => downloadBytesPerSecond.round();

  /// Upload rate in integer bytes per second for netfilter token buckets.
  int get uploadBytesPerSecondInt => uploadBytesPerSecond.round();

  /// Burst buffer in bytes (minimum 64 KB or 10% of rate) to avoid dropping TCP handshakes.
  int get downloadBurstBytes {
    final tenPercent = (downloadBytesPerSecond * 0.1).round();
    return tenPercent < 65536 ? 65536 : tenPercent;
  }

  /// Burst buffer in bytes for upload (minimum 32 KB or 10% of rate).
  int get uploadBurstBytes {
    final tenPercent = (uploadBytesPerSecond * 0.1).round();
    return tenPercent < 32768 ? 32768 : tenPercent;
  }

  /// Formatted human-readable download speed string reusing [Client.formatSpeed].
  String get formattedDownloadSpeed {
    if (downloadValue <= 0) return 'Unlimited';
    return Client.formatSpeed(downloadBytesPerSecond, speedUnit: 'bits');
  }

  /// Formatted human-readable upload speed string reusing [Client.formatSpeed].
  String get formattedUploadSpeed {
    if (uploadValue <= 0) return 'Unlimited';
    return Client.formatSpeed(uploadBytesPerSecond, speedUnit: 'bits');
  }

  /// Short summary badge string (e.g. "↓ 10 Mbps  ↑ 2 Mbps").
  String get compactSummary {
    if (!isEffectivelyRestricted) return 'Unrestricted';
    final dl = downloadBitsPerSecond > 0 ? '↓ $formattedDownloadSpeed' : '↓ ∞';
    final ul = uploadBitsPerSecond > 0 ? '↑ $formattedUploadSpeed' : '↑ ∞';
    return '$dl  $ul';
  }

  ClientSpeedLimit copyWith({
    String? targetMac,
    String? ipAddress,
    List<String>? ipv6Addresses,
    double? downloadValue,
    String? downloadUnit,
    double? uploadValue,
    String? uploadUnit,
    bool? enabled,
    String? hostname,
    DateTime? updatedAt,
  }) {
    return ClientSpeedLimit(
      targetMac: targetMac ?? this.targetMac,
      ipAddress: ipAddress ?? this.ipAddress,
      ipv6Addresses: ipv6Addresses ?? this.ipv6Addresses,
      downloadValue: downloadValue ?? this.downloadValue,
      downloadUnit: downloadUnit ?? this.downloadUnit,
      uploadValue: uploadValue ?? this.uploadValue,
      uploadUnit: uploadUnit ?? this.uploadUnit,
      enabled: enabled ?? this.enabled,
      hostname: hostname ?? this.hostname,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'targetMac': targetMac,
      'ipAddress': ipAddress,
      'ipv6Addresses': ipv6Addresses,
      'downloadValue': downloadValue,
      'downloadUnit': downloadUnit,
      'uploadValue': uploadValue,
      'uploadUnit': uploadUnit,
      'enabled': enabled,
      'hostname': hostname,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ClientSpeedLimit.fromJson(Map<String, dynamic> json) {
    return ClientSpeedLimit(
      targetMac: ClientNamingHelper.normalizeMac(
        (json['targetMac'] as String?) ?? '',
      ),
      ipAddress: (json['ipAddress'] as String?) ?? '',
      ipv6Addresses:
          (json['ipv6Addresses'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      downloadValue: (json['downloadValue'] as num?)?.toDouble() ?? 0.0,
      downloadUnit: (json['downloadUnit'] as String?) ?? 'Mbps',
      uploadValue: (json['uploadValue'] as num?)?.toDouble() ?? 0.0,
      uploadUnit: (json['uploadUnit'] as String?) ?? 'Mbps',
      enabled: json['enabled'] == true,
      hostname: json['hostname'] as String?,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClientSpeedLimit &&
          runtimeType == other.runtimeType &&
          targetMac == other.targetMac &&
          ipAddress == other.ipAddress &&
          downloadValue == other.downloadValue &&
          downloadUnit == other.downloadUnit &&
          uploadValue == other.uploadValue &&
          uploadUnit == other.uploadUnit &&
          enabled == other.enabled;

  @override
  int get hashCode =>
      targetMac.hashCode ^
      ipAddress.hashCode ^
      downloadValue.hashCode ^
      downloadUnit.hashCode ^
      uploadValue.hashCode ^
      uploadUnit.hashCode ^
      enabled.hashCode;
}
