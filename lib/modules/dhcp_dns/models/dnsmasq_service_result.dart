// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

enum DnsmasqServiceStatus { success, notRunning, rpcFailed }

class DnsmasqServiceResult {
  final DnsmasqServiceStatus status;
  final String message;
  final String? rawOutput;
  final DateTime timestamp;

  const DnsmasqServiceResult({
    required this.status,
    required this.message,
    this.rawOutput,
    required this.timestamp,
  });

  bool get isSuccess => status == DnsmasqServiceStatus.success;

  factory DnsmasqServiceResult.success({String? rawOutput}) =>
      DnsmasqServiceResult(
        status: DnsmasqServiceStatus.success,
        message: 'dnsmasq reloaded successfully.',
        rawOutput: rawOutput,
        timestamp: DateTime.now(),
      );

  factory DnsmasqServiceResult.notRunning() => DnsmasqServiceResult(
    status: DnsmasqServiceStatus.notRunning,
    message: 'dnsmasq does not appear to be running.',
    timestamp: DateTime.now(),
  );

  factory DnsmasqServiceResult.failure(String reason) => DnsmasqServiceResult(
    status: DnsmasqServiceStatus.rpcFailed,
    message: reason,
    timestamp: DateTime.now(),
  );
}
