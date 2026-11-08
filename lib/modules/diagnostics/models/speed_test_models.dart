// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';

/// Active phase / stage of the speed test execution.
enum SpeedTestStage {
  idle,
  discoveringEndpoint,
  measuringLatency,
  measuringDownload,
  measuringUpload,
  completed,
  failed,
  cancelled,
}

extension SpeedTestStageX on SpeedTestStage {
  bool get isRunning =>
      this == SpeedTestStage.discoveringEndpoint ||
      this == SpeedTestStage.measuringLatency ||
      this == SpeedTestStage.measuringDownload ||
      this == SpeedTestStage.measuringUpload;

  bool get isDone =>
      this == SpeedTestStage.completed ||
      this == SpeedTestStage.failed ||
      this == SpeedTestStage.cancelled;
}

/// Real-time progress snapshot during a running speed test.
@immutable
class SpeedTestProgress {
  final SpeedTestStage stage;
  final double? currentSpeedMbps;
  final double progressPercent; // 0.0 to 1.0
  final int transferredBytes;
  final int totalExpectedBytes;
  final double? currentLatencyMs;
  final double? currentJitterMs;
  final String? statusMessage;

  const SpeedTestProgress({
    required this.stage,
    this.currentSpeedMbps,
    this.progressPercent = 0.0,
    this.transferredBytes = 0,
    this.totalExpectedBytes = 0,
    this.currentLatencyMs,
    this.currentJitterMs,
    this.statusMessage,
  });

  SpeedTestProgress copyWith({
    SpeedTestStage? stage,
    double? currentSpeedMbps,
    double? progressPercent,
    int? transferredBytes,
    int? totalExpectedBytes,
    double? currentLatencyMs,
    double? currentJitterMs,
    String? statusMessage,
  }) {
    return SpeedTestProgress(
      stage: stage ?? this.stage,
      currentSpeedMbps: currentSpeedMbps ?? this.currentSpeedMbps,
      progressPercent: progressPercent ?? this.progressPercent,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      totalExpectedBytes: totalExpectedBytes ?? this.totalExpectedBytes,
      currentLatencyMs: currentLatencyMs ?? this.currentLatencyMs,
      currentJitterMs: currentJitterMs ?? this.currentJitterMs,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}

/// Final immutable result of an Internet Speed Test.
@immutable
class SpeedTestResult {
  /// Sustained download throughput in Mbps (decimal: bits / 1,000,000).
  final double? downloadSpeedMbps;

  /// Sustained upload throughput in Mbps (decimal: bits / 1,000,000).
  final double? uploadSpeedMbps;

  /// Idle latency in milliseconds (median of pre-traffic probes).
  final double? idleLatencyMs;

  /// Latency jitter in milliseconds (mean absolute difference between consecutive samples).
  final double? jitterMs;

  /// Loaded latency during active transfer in milliseconds, if reliably measured.
  final double? loadedLatencyMs;

  /// Packet loss percentage, ONLY if validly measured; null if not measured.
  final double? packetLossPercent;

  /// Detected client network transport (Wi-Fi, Cellular, Ethernet, VPN, Unknown).
  final String connectionType;

  /// Vantage point where the test originated (e.g. "Device Internet Speed Test").
  final String vantagePoint;

  /// Speed test service / endpoint name (e.g. "Cloudflare Anycast (speed.cloudflare.com)").
  final String serverName;

  /// Timestamp when the test completed.
  final DateTime timestamp;

  /// Total download bytes transferred.
  final int downloadBytes;

  /// Total upload bytes accepted.
  final int uploadBytes;

  /// Active download duration in milliseconds.
  final int downloadDurationMs;

  /// Active upload duration in milliseconds.
  final int uploadDurationMs;

  /// Raw idle latency samples in milliseconds.
  final List<double> latencySamples;

  /// Final stage (completed, failed, cancelled).
  final SpeedTestStage stage;

  /// Error message if a phase failed.
  final String? errorMessage;

  /// Whether the failure was specifically caused by rpcd ACL permission denial (status 6).
  final bool isPermissionDenied;

  const SpeedTestResult({
    this.downloadSpeedMbps,
    this.uploadSpeedMbps,
    this.idleLatencyMs,
    this.jitterMs,
    this.loadedLatencyMs,
    this.packetLossPercent,
    this.connectionType = 'Unknown',
    this.vantagePoint = 'Device Internet Speed Test',
    this.serverName = 'Cloudflare Anycast (speed.cloudflare.com)',
    required this.timestamp,
    this.downloadBytes = 0,
    this.uploadBytes = 0,
    this.downloadDurationMs = 0,
    this.uploadDurationMs = 0,
    this.latencySamples = const [],
    this.stage = SpeedTestStage.completed,
    this.errorMessage,
    this.isPermissionDenied = false,
  });

  bool get isSuccess =>
      stage == SpeedTestStage.completed &&
      (downloadSpeedMbps != null || uploadSpeedMbps != null);

  /// Helper to check if failure was due to missing OpenWrt rpcd execution permissions
  bool get isRpcPermissionError =>
      isPermissionDenied ||
      (errorMessage != null &&
          (errorMessage!.contains('RPC execution permissions') ||
              errorMessage!.contains('RPC Setup')));

  Map<String, dynamic> toJson() => {
    'downloadSpeedMbps': downloadSpeedMbps,
    'uploadSpeedMbps': uploadSpeedMbps,
    'idleLatencyMs': idleLatencyMs,
    'jitterMs': jitterMs,
    'loadedLatencyMs': loadedLatencyMs,
    'packetLossPercent': packetLossPercent,
    'connectionType': connectionType,
    'vantagePoint': vantagePoint,
    'serverName': serverName,
    'timestamp': timestamp.toIso8601String(),
    'downloadBytes': downloadBytes,
    'uploadBytes': uploadBytes,
    'downloadDurationMs': downloadDurationMs,
    'uploadDurationMs': uploadDurationMs,
    'latencySamples': latencySamples,
    'stage': stage.name,
    'errorMessage': errorMessage,
    'isPermissionDenied': isPermissionDenied,
  };

  factory SpeedTestResult.fromJson(Map<String, dynamic> json) {
    return SpeedTestResult(
      downloadSpeedMbps: (json['downloadSpeedMbps'] as num?)?.toDouble(),
      uploadSpeedMbps: (json['uploadSpeedMbps'] as num?)?.toDouble(),
      idleLatencyMs: (json['idleLatencyMs'] as num?)?.toDouble(),
      jitterMs: (json['jitterMs'] as num?)?.toDouble(),
      loadedLatencyMs: (json['loadedLatencyMs'] as num?)?.toDouble(),
      packetLossPercent: (json['packetLossPercent'] as num?)?.toDouble(),
      connectionType: json['connectionType'] as String? ?? 'Unknown',
      vantagePoint:
          json['vantagePoint'] as String? ?? 'Device Internet Speed Test',
      serverName:
          json['serverName'] as String? ??
          'Cloudflare Anycast (speed.cloudflare.com)',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      downloadBytes: json['downloadBytes'] as int? ?? 0,
      uploadBytes: json['uploadBytes'] as int? ?? 0,
      downloadDurationMs: json['downloadDurationMs'] as int? ?? 0,
      uploadDurationMs: json['uploadDurationMs'] as int? ?? 0,
      latencySamples:
          (json['latencySamples'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const [],
      stage: SpeedTestStage.values.firstWhere(
        (e) => e.name == json['stage'],
        orElse: () => SpeedTestStage.completed,
      ),
      errorMessage: json['errorMessage'] as String?,
      isPermissionDenied: json['isPermissionDenied'] as bool? ?? false,
    );
  }
}
