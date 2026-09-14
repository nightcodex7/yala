// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

class SystemMetrics {
  final int uptimeSeconds;
  final double load1m;
  final double load5m;
  final double load15m;
  final double cpuUsagePercent;
  final int totalMemoryBytes;
  final int freeMemoryBytes;
  final int bufferedMemoryBytes;
  final int cachedMemoryBytes;

  const SystemMetrics({
    required this.uptimeSeconds,
    required this.load1m,
    required this.load5m,
    required this.load15m,
    required this.cpuUsagePercent,
    required this.totalMemoryBytes,
    required this.freeMemoryBytes,
    required this.bufferedMemoryBytes,
    required this.cachedMemoryBytes,
  });

  factory SystemMetrics.fromSysInfo(
    Map<String, dynamic>? sysInfo, {
    Map<String, dynamic>? boardInfo,
  }) {
    if (sysInfo == null) {
      return const SystemMetrics(
        uptimeSeconds: 0,
        load1m: 0.0,
        load5m: 0.0,
        load15m: 0.0,
        cpuUsagePercent: 0.0,
        totalMemoryBytes: 0,
        freeMemoryBytes: 0,
        bufferedMemoryBytes: 0,
        cachedMemoryBytes: 0,
      );
    }

    final uptime =
        (sysInfo['uptime'] as num?)?.toInt() ??
        int.tryParse(sysInfo['uptime']?.toString() ?? '') ??
        0;

    // Load averages
    double l1 = 0.0;
    double l5 = 0.0;
    double l15 = 0.0;
    final rawLoad =
        sysInfo['load'] ??
        sysInfo['sysload'] ??
        sysInfo['cpu_load'] ??
        sysInfo['loadavg'];
    final loadList = rawLoad is List
        ? rawLoad
        : (rawLoad is Map
              ? rawLoad.values.toList()
              : (rawLoad != null ? [rawLoad] : null));

    if (loadList != null && loadList.isNotEmpty) {
      double parseLoad(dynamic val) {
        if (val == null) return 0.0;
        final num? n = val is num ? val : num.tryParse(val.toString().trim());
        if (n == null) return 0.0;
        final double dVal = n.toDouble();
        return dVal > 10.0 ? dVal / 65536.0 : dVal;
      }

      l1 = parseLoad(loadList[0]);
      if (loadList.length > 1) l5 = parseLoad(loadList[1]);
      if (loadList.length > 2) l15 = parseLoad(loadList[2]);
    }

    // Direct CPU percentage override if provided directly in sysInfo
    double? directCpu;
    final rawCpuDirect =
        sysInfo['cpu'] ??
        sysInfo['cpu_usage'] ??
        sysInfo['cpuload'] ??
        sysInfo['cpu_percent'];
    if (rawCpuDirect != null) {
      if (rawCpuDirect is Map) {
        final usageVal =
            rawCpuDirect['usage'] ??
            rawCpuDirect['percent'] ??
            rawCpuDirect['load'] ??
            rawCpuDirect['total'];
        final idleVal = rawCpuDirect['idle'];
        if (usageVal != null) {
          final num? n = usageVal is num
              ? usageVal
              : num.tryParse(usageVal.toString().replaceAll('%', '').trim());
          if (n != null) directCpu = n.toDouble();
        } else if (idleVal != null) {
          final num? n = idleVal is num
              ? idleVal
              : num.tryParse(idleVal.toString().replaceAll('%', '').trim());
          if (n != null) directCpu = 100.0 - n.toDouble();
        }
      } else {
        final num? parsedCpu = rawCpuDirect is num
            ? rawCpuDirect
            : num.tryParse(rawCpuDirect.toString().replaceAll('%', '').trim());
        if (parsedCpu != null) {
          directCpu = parsedCpu.toDouble();
        }
      }
    }

    double cpuPercent;
    if (directCpu != null) {
      final double val = directCpu;
      cpuPercent =
          (val > 500.0
                  ? (val / 65536.0 * 100.0)
                  : (val <= 1.0 ? val * 100.0 : val))
              .clamp(0.0, 100.0);
    } else {
      if (l1 <= 0.15) {
        cpuPercent = (l1 * 100.0).clamp(0.0, 100.0);
      } else {
        final cores = _detectCpuCores(sysInfo, boardInfo);
        final double loadPerCore = l1 / cores;
        if (loadPerCore <= 1.0) {
          cpuPercent = (15.0 + (loadPerCore - 0.15) * (35.0 / 0.85)).clamp(
            0.0,
            100.0,
          );
        } else {
          cpuPercent = (50.0 + (loadPerCore - 1.0) * 35.0).clamp(0.0, 100.0);
        }
      }
    }

    // Memory parsing
    final memMap = sysInfo['memory'] as Map<String, dynamic>?;
    final total =
        (memMap?['total'] as num?)?.toInt() ??
        int.tryParse(memMap?['total']?.toString() ?? '') ??
        0;
    final free =
        (memMap?['free'] as num?)?.toInt() ??
        int.tryParse(memMap?['free']?.toString() ?? '') ??
        0;
    final buffered =
        (memMap?['buffered'] as num?)?.toInt() ??
        int.tryParse(memMap?['buffered']?.toString() ?? '') ??
        0;
    final cached =
        (memMap?['cached'] as num?)?.toInt() ??
        int.tryParse(memMap?['cached']?.toString() ?? '') ??
        0;

    return SystemMetrics(
      uptimeSeconds: uptime,
      load1m: l1,
      load5m: l5,
      load15m: l15,
      cpuUsagePercent: cpuPercent,
      totalMemoryBytes: total,
      freeMemoryBytes: free,
      bufferedMemoryBytes: buffered,
      cachedMemoryBytes: cached,
    );
  }

  int get usedMemoryBytes {
    final used =
        totalMemoryBytes -
        freeMemoryBytes -
        bufferedMemoryBytes -
        cachedMemoryBytes;
    return used < 0 ? 0 : used;
  }

  double get memoryUsagePercent {
    if (totalMemoryBytes <= 0) return 0.0;
    final used = totalMemoryBytes - freeMemoryBytes - bufferedMemoryBytes;
    return ((used / totalMemoryBytes) * 100).clamp(0.0, 100.0);
  }

  String get formattedUptime {
    if (uptimeSeconds <= 0) return 'N/A';
    final days = uptimeSeconds ~/ 86400;
    final hours = (uptimeSeconds % 86400) ~/ 3600;
    final minutes = (uptimeSeconds % 3600) ~/ 60;

    final parts = <String>[];
    if (days > 0) parts.add('${days}d');
    if (hours > 0 || days > 0) parts.add('${hours}h');
    parts.add('${minutes}m');
    return parts.join(' ');
  }

  String get formattedLoadAverage {
    return '${load1m.toStringAsFixed(2)}, ${load5m.toStringAsFixed(2)}, ${load15m.toStringAsFixed(2)}';
  }

  String get formattedMemoryUsage {
    if (totalMemoryBytes <= 0) return 'N/A';
    final usedMB = (usedMemoryBytes / (1024 * 1024)).toStringAsFixed(0);
    final totalMB = (totalMemoryBytes / (1024 * 1024)).toStringAsFixed(0);
    return '$usedMB / $totalMB MB (${memoryUsagePercent.toStringAsFixed(0)}%)';
  }

  static int _detectCpuCores(
    Map<String, dynamic>? sysInfo,
    Map<String, dynamic>? boardInfo,
  ) {
    final directCount =
        sysInfo?['cpus'] ??
        sysInfo?['cpu_count'] ??
        sysInfo?['cores'] ??
        boardInfo?['cpu_count'] ??
        boardInfo?['cores'];
    if (directCount != null) {
      final int? c = directCount is int
          ? directCount
          : int.tryParse(directCount.toString());
      if (c != null && c > 0) return c;
    }

    final model =
        (boardInfo?['model']?.toString() ?? sysInfo?['model']?.toString() ?? '')
            .toLowerCase();
    final system =
        (boardInfo?['system']?.toString() ??
                sysInfo?['system']?.toString() ??
                '')
            .toLowerCase();
    final combined = '$model $system';

    if (combined.contains('octa') || combined.contains('8-core')) return 8;
    if (combined.contains('quad') ||
        combined.contains('4-core') ||
        combined.contains('mt7621') ||
        combined.contains('ipq401') ||
        combined.contains('ipq806') ||
        combined.contains('ipq6000') ||
        combined.contains('ipq807') ||
        combined.contains('mt7986') ||
        combined.contains('rk3399') ||
        combined.contains('rk3568') ||
        combined.contains('bcm4908') ||
        combined.contains('filogic 830')) {
      return 4;
    }
    if (combined.contains('dual') ||
        combined.contains('2-core') ||
        combined.contains('mt7981') ||
        combined.contains('ipq5000') ||
        combined.contains('filogic 820') ||
        combined.contains('x86') ||
        combined.contains('r2s') ||
        combined.contains('r4s')) {
      return 2;
    }
    return 2;
  }
}
