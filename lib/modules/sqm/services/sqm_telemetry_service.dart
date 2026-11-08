// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:yet_another_luci_app/services/api_service.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import '../models/sqm_telemetry.dart';

/// Service responsible for querying and parsing Linux Traffic Control (`tc`) telemetry.
class SqmTelemetryService {
  /// Strict alphanumeric and safe interface name validator.
  /// Disallows shell metacharacters, spaces, slashes, and control characters.
  static final RegExp validInterfaceRegex = RegExp(r'^[a-zA-Z0-9_\-\.]+$');

  /// Parses raw stdout of `tc -s qdisc show dev <interface>` into [SqmQueueTelemetry].
  ///
  /// Safe against malformed, truncated, or empty output. Never throws unhandled exceptions.
  /// Classifies metrics strictly as:
  /// - Directly reported by `tc`
  /// - Safely derived
  /// - Unavailable (null/0) — never manufactures latency or delay.
  static SqmQueueTelemetry parseTcOutput(
    String interfaceName,
    String rawOutput, {
    DateTime? timestamp,
  }) {
    final now = timestamp ?? DateTime.now();
    final clean = rawOutput.trim();

    if (clean.isEmpty) {
      return SqmQueueTelemetry(
        interfaceName: interfaceName,
        qdisc: 'none',
        rawOutput: rawOutput,
        timestamp: now,
      );
    }

    try {
      final lines = clean.split('\n').map((l) => l.trimRight()).toList();

      String qdisc = 'unknown';
      String? handle;
      bool isRoot = false;
      int sentBytes = 0;
      int sentPackets = 0;
      int droppedPackets = 0;
      int overlimits = 0;
      int requeues = 0;
      int backlogBytes = 0;
      int backlogPackets = 0;
      int? memoryUsedBytes;
      int? memoryLimitBytes;
      int? capacityEstimateBps;
      int? ecnMarked;
      int? dropOverlimit;
      int? maxPacket;
      int? newFlowCount;
      final List<CakeTinStats> tins = [];

      // Regex patterns
      //
      // NOTE: When tc is invoked as `tc -s qdisc show dev <iface>`, the kernel
      // does NOT echo back "dev <iface>" on the root qdisc header line.
      // e.g.:  qdisc cake 802b: root refcnt 2 bandwidth 78Mbit ...
      // The "dev <iface>" token only appears when listing all interfaces at once
      // (`tc qdisc show` without a device filter).  Both forms must be handled,
      // so the entire `dev <name>` clause is optional.  When absent, the caller
      // already knows the interface via the `interfaceName` parameter.
      final qdiscHeaderRegex = RegExp(
        r'^qdisc\s+([a-zA-Z0-9_\-]+)(?:\s+([a-zA-Z0-9:]+))?(?:\s+dev\s+([a-zA-Z0-9_\-\.]+))?(?:\s+(root)(?:\s|$))?',
      );
      final sentRegex = RegExp(
        r'Sent\s+(\d+)\s+bytes\s+(\d+)\s+pkt\s*\(dropped\s+(\d+),\s*overlimits\s+(\d+)(?:,?\s*requeues\s+(\d+))?\)',
        caseSensitive: false,
      );
      final backlogRegex = RegExp(
        r'backlog\s+(\d+)[bB]\s+(\d+)[pP](?:,?\s*requeues\s+(\d+))?',
        caseSensitive: false,
      );
      final memoryRegex = RegExp(
        r'memory\s+used:\s*(\d+)[bB](?:\s+of\s+([0-9.]+[a-zA-Z]+))?',
        caseSensitive: false,
      );
      final capacityRegex = RegExp(
        r'capacity\s+estimate:\s*([0-9.]+[a-zA-Z]+)',
        caseSensitive: false,
      );
      final fqCodelStatsRegex = RegExp(
        r'maxpacket\s+(\d+)\s+drop_overlimit\s+(\d+)\s+new_flow_count\s+(\d+)\s+ecn_mark\s+(\d+)',
        caseSensitive: false,
      );
      final tinHeaderRegex = RegExp(r'^([A-Za-z0-9\s]+):$');

      String? currentTinName;
      Map<String, dynamic> currentTinFields = {};
      bool inSecondaryNonRootQdisc = false;

      void flushCurrentTin() {
        if (currentTinName != null && currentTinName!.isNotEmpty) {
          tins.add(
            CakeTinStats(
              name: currentTinName!,
              thresholdBps: currentTinFields['threshold'],
              targetMs: currentTinFields['target'],
              intervalMs: currentTinFields['interval'],
              pkDelayMs: currentTinFields['pk_delay'],
              avDelayMs: currentTinFields['av_delay'],
              spDelayMs: currentTinFields['sp_delay'],
              backlogBytes: currentTinFields['backlogBytes'] ?? 0,
              backlogPackets: currentTinFields['backlogPackets'] ?? 0,
              droppedPackets: currentTinFields['dropped'] ?? 0,
              sentPackets: currentTinFields['sentPackets'],
              sentBytes: currentTinFields['sentBytes'],
              ecnMarked: currentTinFields['ecn_mark'],
            ),
          );
        }
        currentTinName = null;
        currentTinFields = {};
      }

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trim();

        // 1. Qdisc Header
        final qdiscMatch = qdiscHeaderRegex.firstMatch(trimmed);
        if (qdiscMatch != null) {
          final matchedQdisc = qdiscMatch.group(1) ?? 'unknown';
          final matchedHandle = qdiscMatch.group(2);
          final matchedIsRoot =
              qdiscMatch.group(4) != null || trimmed.contains('root');

          // If we already parsed a root qdisc, ignore secondary/ingress qdiscs
          if (isRoot && !matchedIsRoot) {
            inSecondaryNonRootQdisc = true;
            continue;
          }

          flushCurrentTin();
          inSecondaryNonRootQdisc = false;
          qdisc = matchedQdisc;
          handle = matchedHandle;
          isRoot = matchedIsRoot;
          continue;
        }

        if (inSecondaryNonRootQdisc) {
          continue;
        }

        // 2. Sent Line
        final sentMatch = sentRegex.firstMatch(trimmed);
        if (sentMatch != null) {
          sentBytes = int.tryParse(sentMatch.group(1) ?? '0') ?? 0;
          sentPackets = int.tryParse(sentMatch.group(2) ?? '0') ?? 0;
          droppedPackets = int.tryParse(sentMatch.group(3) ?? '0') ?? 0;
          overlimits = int.tryParse(sentMatch.group(4) ?? '0') ?? 0;
          if (sentMatch.group(5) != null) {
            requeues = int.tryParse(sentMatch.group(5)!) ?? 0;
          }
          continue;
        }

        // 3. Backlog Line
        final backlogMatch = backlogRegex.firstMatch(trimmed);
        if (backlogMatch != null) {
          if (currentTinName != null) {
            currentTinFields['backlogBytes'] =
                int.tryParse(backlogMatch.group(1) ?? '0') ?? 0;
            currentTinFields['backlogPackets'] =
                int.tryParse(backlogMatch.group(2) ?? '0') ?? 0;
          } else {
            backlogBytes = int.tryParse(backlogMatch.group(1) ?? '0') ?? 0;
            backlogPackets = int.tryParse(backlogMatch.group(2) ?? '0') ?? 0;
            if (backlogMatch.group(3) != null) {
              requeues = int.tryParse(backlogMatch.group(3)!) ?? requeues;
            }
          }
          continue;
        }

        // 4. Memory Used (CAKE)
        final memMatch = memoryRegex.firstMatch(trimmed);
        if (memMatch != null) {
          memoryUsedBytes = int.tryParse(memMatch.group(1) ?? '0');
          if (memMatch.group(2) != null) {
            memoryLimitBytes = _parseRateOrBytes(memMatch.group(2)!);
          }
          continue;
        }

        // 5. Capacity Estimate (CAKE)
        final capMatch = capacityRegex.firstMatch(trimmed);
        if (capMatch != null && capMatch.group(1) != null) {
          capacityEstimateBps = _parseRateOrBytes(capMatch.group(1)!);
          continue;
        }

        // 6. FQ-CoDel Detailed Stats
        final fqMatch = fqCodelStatsRegex.firstMatch(trimmed);
        if (fqMatch != null) {
          maxPacket = int.tryParse(fqMatch.group(1) ?? '0');
          dropOverlimit = int.tryParse(fqMatch.group(2) ?? '0');
          newFlowCount = int.tryParse(fqMatch.group(3) ?? '0');
          ecnMarked = int.tryParse(fqMatch.group(4) ?? '0');
          continue;
        }

        // 7. CAKE Diffserv Tin Header (e.g. "Bulk:", "Best Effort:", "Voice:")
        final tinMatch = tinHeaderRegex.firstMatch(trimmed);
        if (tinMatch != null && !trimmed.toLowerCase().startsWith('memory')) {
          flushCurrentTin();
          currentTinName = tinMatch.group(1)?.trim();
          continue;
        }

        // 8. Tin fields
        if (currentTinName != null) {
          if (trimmed.startsWith('threshold ')) {
            final rateStr = trimmed.substring('threshold '.length).trim();
            currentTinFields['threshold'] = _parseRateOrBytes(rateStr);
          } else if (trimmed.startsWith('target ')) {
            currentTinFields['target'] = _parseTimeDelayMs(
              trimmed.substring('target '.length).trim(),
            );
          } else if (trimmed.startsWith('interval ')) {
            currentTinFields['interval'] = _parseTimeDelayMs(
              trimmed.substring('interval '.length).trim(),
            );
          } else if (trimmed.startsWith('pk_delay ')) {
            currentTinFields['pk_delay'] = _parseTimeDelayMs(
              trimmed.substring('pk_delay '.length).trim(),
            );
          } else if (trimmed.startsWith('av_delay ')) {
            currentTinFields['av_delay'] = _parseTimeDelayMs(
              trimmed.substring('av_delay '.length).trim(),
            );
          } else if (trimmed.startsWith('sp_delay ')) {
            currentTinFields['sp_delay'] = _parseTimeDelayMs(
              trimmed.substring('sp_delay '.length).trim(),
            );
          } else if (trimmed.startsWith('dropped ')) {
            currentTinFields['dropped'] =
                int.tryParse(trimmed.substring('dropped '.length).trim()) ?? 0;
          } else if (trimmed.startsWith('ecn_mark ')) {
            currentTinFields['ecn_mark'] = int.tryParse(
              trimmed.substring('ecn_mark '.length).trim(),
            );
          }
        }
      }

      flushCurrentTin();

      return SqmQueueTelemetry(
        interfaceName: interfaceName,
        qdisc: qdisc,
        handle: handle,
        root: isRoot,
        sentBytes: sentBytes,
        sentPackets: sentPackets,
        droppedPackets: droppedPackets,
        overlimits: overlimits,
        requeues: requeues,
        backlogBytes: backlogBytes,
        backlogPackets: backlogPackets,
        memoryUsedBytes: memoryUsedBytes,
        memoryLimitBytes: memoryLimitBytes,
        capacityEstimateBps: capacityEstimateBps,
        ecnMarked: ecnMarked,
        dropOverlimit: dropOverlimit,
        maxPacket: maxPacket,
        newFlowCount: newFlowCount,
        tinStats: tins,
        rawOutput: rawOutput,
        timestamp: now,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error parsing tc output for $interfaceName: $e');
      }
      return SqmQueueTelemetry(
        interfaceName: interfaceName,
        qdisc: 'unknown',
        rawOutput: rawOutput,
        timestamp: now,
      );
    }
  }

  /// Parses rates like "100Mbit", "6250Kbit", "4Mb", "32Kb", "10Gbit" into raw integer values.
  static int? _parseRateOrBytes(String s) {
    final clean = s.trim();
    final match = RegExp(r'^([0-9.]+)\s*([a-zA-Z]+)$').firstMatch(clean);
    if (match == null) return int.tryParse(clean);

    final numVal = double.tryParse(match.group(1) ?? '0') ?? 0.0;
    final unit = (match.group(2) ?? '').toLowerCase();

    if (unit.startsWith('gbit') || unit.startsWith('gb')) {
      return (numVal * 1000 * 1000 * 1000).round();
    } else if (unit.startsWith('mbit')) {
      return (numVal * 1000 * 1000).round();
    } else if (unit.startsWith('mb')) {
      return (numVal * 1024 * 1024).round();
    } else if (unit.startsWith('kbit')) {
      return (numVal * 1000).round();
    } else if (unit.startsWith('kb')) {
      return (numVal * 1024).round();
    } else if (unit.startsWith('bit') || unit.startsWith('b')) {
      return numVal.round();
    }
    return numVal.round();
  }

  /// Parses delay strings like "1.2ms", "400us", "100ns", "2s" into milliseconds (double).
  static double? _parseTimeDelayMs(String s) {
    final clean = s.trim();
    final match = RegExp(r'^([0-9.]+)\s*([a-zA-Z]+)$').firstMatch(clean);
    if (match == null) return double.tryParse(clean);

    final numVal = double.tryParse(match.group(1) ?? '0') ?? 0.0;
    final unit = (match.group(2) ?? '').toLowerCase();

    if (unit == 's') {
      return numVal * 1000.0;
    } else if (unit == 'ms') {
      return numVal;
    } else if (unit == 'us') {
      return numVal / 1000.0;
    } else if (unit == 'ns') {
      return numVal / 1000000.0;
    }
    return numVal;
  }

  /// Executes structured `tc -s qdisc show dev <interface>` RPC via [ApiServiceInterface].
  ///
  /// Strictly rejects malformed or unvalidated interface names before RPC execution.
  /// Uses structured argument passing (zero shell interpolation).
  Future<SqmQueueTelemetry?> fetchQueueTelemetry({
    required IApiService apiService,
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interfaceName,
    bool isReviewerMode = false,
  }) async {
    final clean = interfaceName.trim();
    if (clean.isEmpty || !validInterfaceRegex.hasMatch(clean)) {
      if (kDebugMode) {
        debugPrint('Invalid interface name for tc execution: "$interfaceName"');
      }
      return null;
    }

    if (isReviewerMode) {
      return generateMockTelemetry(clean);
    }

    try {
      final arguments = ['-s', 'qdisc', 'show', 'dev', clean];

      // 1. Primary: file.exec with structured parameters
      final execRes = await apiService.call(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: RealApiService.fileExecParams('tc', arguments),
      );

      Map<String, dynamic>? data;
      if (execRes is List && execRes.length > 1 && execRes[0] == 0) {
        data = execRes[1] as Map<String, dynamic>?;
      } else if (execRes is Map<String, dynamic>) {
        data = execRes;
      }

      // 2. Secondary fallback: try args key or /sbin/tc
      if (data == null || data['stdout'] == null) {
        final fallbackRes = await apiService.call(
          ipAddress,
          sysauth,
          useHttps,
          object: 'file',
          method: 'exec',
          params: RealApiService.fileExecArgs('tc', arguments),
        );
        if (fallbackRes is List &&
            fallbackRes.length > 1 &&
            fallbackRes[0] == 0) {
          data = fallbackRes[1] as Map<String, dynamic>?;
        } else if (fallbackRes is Map<String, dynamic>) {
          data = fallbackRes;
        }
      }

      if (data != null) {
        final code = data['code'];
        final stdout = data['stdout']?.toString() ?? '';
        if (code == 0 || stdout.isNotEmpty) {
          return parseTcOutput(clean, stdout);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('tc exec failed for $clean: $e');
      }
    }

    return null;
  }

  /// Generates deterministic, realistic mock SQM telemetry for Reviewer Mode.
  static SqmQueueTelemetry generateMockTelemetry(String interfaceName) {
    final random = math.Random(interfaceName.hashCode ^ 42);
    final sentPackets = 184200 + random.nextInt(500);
    final sentBytes = 124800000 + random.nextInt(500000);
    final droppedPackets = 12 + random.nextInt(5);
    final overlimits = 14000 + random.nextInt(200);

    return SqmQueueTelemetry(
      interfaceName: interfaceName,
      qdisc: 'cake',
      handle: '800e:',
      root: true,
      sentBytes: sentBytes,
      sentPackets: sentPackets,
      droppedPackets: droppedPackets,
      overlimits: overlimits,
      requeues: 0,
      backlogBytes: 0,
      backlogPackets: 0,
      memoryUsedBytes: 124512,
      memoryLimitBytes: 4 * 1024 * 1024,
      capacityEstimateBps: 100 * 1000 * 1000,
      tinStats: const [
        CakeTinStats(
          name: 'Bulk',
          thresholdBps: 6250 * 1000,
          targetMs: 19.3,
          intervalMs: 119.3,
          pkDelayMs: 1.2,
          avDelayMs: 0.4,
          spDelayMs: 0.1,
          backlogBytes: 0,
          backlogPackets: 0,
          droppedPackets: 2,
        ),
        CakeTinStats(
          name: 'Best Effort',
          thresholdBps: 100 * 1000 * 1000,
          targetMs: 5.0,
          intervalMs: 100.0,
          pkDelayMs: 0.3,
          avDelayMs: 0.12,
          spDelayMs: 0.04,
          backlogBytes: 0,
          backlogPackets: 0,
          droppedPackets: 10,
        ),
        CakeTinStats(
          name: 'Voice',
          thresholdBps: 25 * 1000 * 1000,
          targetMs: 5.0,
          intervalMs: 100.0,
          pkDelayMs: 0.1,
          avDelayMs: 0.04,
          spDelayMs: 0.02,
          backlogBytes: 0,
          backlogPackets: 0,
          droppedPackets: 0,
        ),
      ],
      rawOutput: 'Mock Reviewer Mode tc output',
      timestamp: DateTime.now(),
    );
  }
}
