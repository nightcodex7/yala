// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

enum StorageDataSource {
  rpcJson, // Natively in Bytes from OpenWrt RPC JSON (luci-rpc.getMountPoints, system.mounts, etc.)
  dfKBlocks, // 1K-blocks (KB) from plain df or df -k command output
  dfHuman, // Human-readable string from df -h (e.g. 123M, 1.5G, 500K)
}

/// Representation of an individual mounted filesystem partition or device.
class MountPointItem {
  final String mountPath;
  final String device;
  final String filesystemType;
  final int sizeBytes;
  final int usedBytes;
  final int availableBytes;

  const MountPointItem({
    required this.mountPath,
    required this.device,
    required this.filesystemType,
    required this.sizeBytes,
    required this.usedBytes,
    required this.availableBytes,
  });

  factory MountPointItem.fromJson(
    Map<String, dynamic> json, {
    StorageDataSource dataSource = StorageDataSource.rpcJson,
  }) {
    final mount =
        json['mount']?.toString() ??
        json['target']?.toString() ??
        json['mountpoint']?.toString() ??
        json['dest']?.toString() ??
        json['path']?.toString() ??
        '/';
    final dev =
        json['device']?.toString() ??
        json['dev']?.toString() ??
        json['src']?.toString() ??
        json['source']?.toString() ??
        'unknown';

    String fs =
        json['fs']?.toString() ??
        json['fstype']?.toString() ??
        json['type']?.toString() ??
        json['filesystem']?.toString() ??
        '';

    if (fs.isEmpty || fs.toLowerCase() == 'unknown') {
      if (dev.contains('ubi')) {
        fs = 'ubifs';
      } else if (dev.contains('overlay') || mount.contains('overlay')) {
        fs = 'overlayfs';
      } else if (dev == 'tmpfs' || mount == '/tmp' || mount == '/dev') {
        fs = 'tmpfs';
      } else if (dev.contains('root') || mount == '/rom') {
        fs = 'squashfs';
      } else if (dev.contains('mtdblock')) {
        fs = 'jffs2';
      } else {
        fs = 'ext4';
      }
    }

    bool hasUnitSuffix = false;
    int parseNum(dynamic val) {
      if (val == null) return 0;
      if (val is num) return val.toInt();
      if (val is String) {
        final clean = val.replaceAll(',', '').trim();
        final lower = clean.toLowerCase();
        if (lower.endsWith('g') || lower.endsWith('gb')) {
          hasUnitSuffix = true;
          final n =
              double.tryParse(clean.replaceAll(RegExp(r'[a-zA-Z]'), '')) ?? 0;
          return (n * 1024 * 1024 * 1024).toInt();
        }
        if (lower.endsWith('m') || lower.endsWith('mb')) {
          hasUnitSuffix = true;
          final n =
              double.tryParse(clean.replaceAll(RegExp(r'[a-zA-Z]'), '')) ?? 0;
          return (n * 1024 * 1024).toInt();
        }
        if (lower.endsWith('k') || lower.endsWith('kb')) {
          hasUnitSuffix = true;
          final n =
              double.tryParse(clean.replaceAll(RegExp(r'[a-zA-Z]'), '')) ?? 0;
          return (n * 1024).toInt();
        }
        if (lower.endsWith('b')) {
          hasUnitSuffix = true;
          final n =
              double.tryParse(clean.replaceAll(RegExp(r'[a-zA-Z]'), '')) ?? 0;
          return n.toInt();
        }
        return int.tryParse(clean) ?? (double.tryParse(clean)?.toInt() ?? 0);
      }
      return 0;
    }

    int rawSize = parseNum(
      json['size'] ??
          json['total'] ??
          json['blocks'] ??
          json['sizeBytes'] ??
          json['bytes'] ??
          json['capacity'],
    );
    int rawAvail = parseNum(
      json['avail'] ??
          json['available'] ??
          json['free'] ??
          json['availableBytes'] ??
          json['freeBytes'],
    );
    int rawUsed = parseNum(json['used'] ?? json['usedBytes']);

    final bsize = parseNum(
      json['bsize'] ?? json['block_size'] ?? json['blockSize'],
    );
    final unitStr = json['unit']?.toString().toLowerCase() ?? '';

    final isExplicitBytes =
        hasUnitSuffix ||
        json.containsKey('sizeBytes') ||
        json.containsKey('bytes') ||
        json.containsKey('usedBytes') ||
        json.containsKey('availableBytes') ||
        json.containsKey('size_bytes') ||
        json.containsKey('used_bytes') ||
        json.containsKey('avail_bytes') ||
        json.containsKey('total_bytes') ||
        unitStr == 'bytes' ||
        unitStr == 'b';

    final multiplier = determineByteMultiplier(
      rawSize: rawSize,
      rawUsed: rawUsed,
      rawAvail: rawAvail,
      bsize: bsize,
      hasExplicitByteKey: isExplicitBytes,
      hasUnitSuffix: hasUnitSuffix,
      unitStr: unitStr,
      mountPath: mount,
      dataSource: dataSource,
    );

    int sizeBytes = rawSize * multiplier;
    int availBytes = rawAvail * multiplier;
    int usedBytes = rawUsed * multiplier;

    if (mount == '/rom' || fs.toLowerCase() == 'squashfs') {
      availBytes = 0;
      if (usedBytes == 0) {
        usedBytes = sizeBytes;
      }
    } else {
      if (usedBytes == 0 && sizeBytes > availBytes && availBytes > 0) {
        usedBytes = sizeBytes - availBytes;
      } else if (availBytes == 0 && sizeBytes > usedBytes && usedBytes > 0) {
        availBytes = sizeBytes - usedBytes;
      }
    }

    return MountPointItem(
      mountPath: mount,
      device: dev,
      filesystemType: fs,
      sizeBytes: sizeBytes,
      usedBytes: usedBytes,
      availableBytes: availBytes < 0 ? 0 : availBytes,
    );
  }

  static int determineByteMultiplier({
    required int rawSize,
    required int rawUsed,
    required int rawAvail,
    required int bsize,
    required bool hasExplicitByteKey,
    required bool hasUnitSuffix,
    required String unitStr,
    required String mountPath,
    required StorageDataSource dataSource,
  }) {
    if (bsize > 0) {
      return bsize;
    }

    if (dataSource == StorageDataSource.rpcJson) {
      if (hasExplicitByteKey ||
          hasUnitSuffix ||
          unitStr == 'bytes' ||
          unitStr == 'b') {
        return 1;
      }
      if (rawSize > 0 && rawSize <= 8192) {
        return 1024 * 1024;
      }
      if (rawSize > 8192 && rawSize <= 1048576) {
        return 1024;
      }
      return 1;
    }

    if (hasExplicitByteKey ||
        hasUnitSuffix ||
        unitStr == 'bytes' ||
        unitStr == 'b') {
      return 1;
    }

    if (unitStr == 'kb' || unitStr == 'k' || unitStr == 'kblocks') {
      return 1024;
    }
    if (unitStr == 'mb' || unitStr == 'm') {
      return 1024 * 1024;
    }
    if (unitStr == 'gb' || unitStr == 'g') {
      return 1024 * 1024 * 1024;
    }

    if (rawSize <= 0) {
      return 1024;
    }

    if (dataSource == StorageDataSource.dfKBlocks) {
      return 1024;
    }

    if (dataSource == StorageDataSource.dfHuman) {
      return 1;
    }

    final bool isSystemMount =
        mountPath == '/' ||
        mountPath == '/overlay' ||
        mountPath == '/rom' ||
        mountPath == '/tmp' ||
        mountPath == '/dev';

    if (rawSize >= 1048576) {
      if (isSystemMount) {
        return 1;
      }
      final bool isExactMbMultiple = (rawSize % 1048576 == 0);
      final double ifKbToGb =
          (rawSize.toDouble() * 1024.0) / (1024.0 * 1024.0 * 1024.0);

      if (ifKbToGb > 100000.0 || (isExactMbMultiple && rawSize >= 16777216)) {
        return 1;
      }
      return 1;
    }

    if (rawSize > 0 && rawSize <= 8192) {
      if (rawSize == 16 ||
          rawSize == 32 ||
          rawSize == 64 ||
          rawSize == 128 ||
          rawSize == 256 ||
          rawSize == 384 ||
          rawSize == 512 ||
          rawSize == 1024 ||
          rawSize == 2048 ||
          rawSize == 4096 ||
          rawSize == 8192) {
        return 1024 * 1024;
      }
    }

    return 1024;
  }

  double get usedPercent {
    if (sizeBytes <= 0) return 0.0;
    return ((usedBytes / sizeBytes) * 100).clamp(0.0, 100.0);
  }

  bool get isOverlay =>
      mountPath == '/overlay' ||
      mountPath.contains('overlay') ||
      device.contains('overlay') ||
      device.contains('ubi');

  bool get isRoot =>
      mountPath == '/' ||
      mountPath == '/rom' ||
      device == '/dev/root' ||
      device.contains('root');

  bool get isTmp =>
      mountPath == '/tmp' ||
      mountPath == '/dev' ||
      mountPath.contains('/tmp') ||
      filesystemType == 'tmpfs' ||
      device == 'tmpfs';
}

/// Overview of router storage, overlay filesystem, flash, and mounted devices.
class StorageOverview {
  final List<MountPointItem> mountPoints;

  const StorageOverview({required this.mountPoints});

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final double b = bytes.toDouble();
    if (b < 1024) {
      return '$bytes B';
    }
    final double kb = b / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    final double mb = kb / 1024;
    if (mb < 1024) {
      return '${mb.toStringAsFixed(1)} MB';
    }
    final double gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }

  factory StorageOverview.fromRpcData(
    dynamic data, {
    bool isReviewerMode = false,
  }) {
    final list = <MountPointItem>[];

    int parseNum(dynamic val) {
      if (val == null) return 0;
      if (val is num) return val.toInt();
      if (val is String) {
        final clean = val.replaceAll(',', '').trim();
        if (clean.endsWith('G') ||
            clean.endsWith('GB') ||
            clean.endsWith('g') ||
            clean.endsWith('gb')) {
          final n =
              double.tryParse(clean.replaceAll(RegExp(r'[a-zA-Z]'), '')) ?? 0;
          return (n * 1024 * 1024 * 1024).toInt();
        }
        if (clean.endsWith('M') ||
            clean.endsWith('MB') ||
            clean.endsWith('m') ||
            clean.endsWith('mb')) {
          final n =
              double.tryParse(clean.replaceAll(RegExp(r'[a-zA-Z]'), '')) ?? 0;
          return (n * 1024 * 1024).toInt();
        }
        if (clean.endsWith('K') ||
            clean.endsWith('KB') ||
            clean.endsWith('k') ||
            clean.endsWith('kb')) {
          final n =
              double.tryParse(clean.replaceAll(RegExp(r'[a-zA-Z]'), '')) ?? 0;
          return (n * 1024).toInt();
        }
        return int.tryParse(clean) ?? (double.tryParse(clean)?.toInt() ?? 0);
      }
      return 0;
    }

    if (data is String) {
      final rawLines = data.split('\n');
      final lines = <String>[];

      bool isHumanFormat = false;
      for (final l in rawLines) {
        if (l.contains('Size') || l.contains('Used') || l.contains('Avail')) {
          if (l.contains('Human') || l.contains('-h') || l.contains('Size')) {
            isHumanFormat = true;
          }
        }
      }

      String pendingDev = '';
      for (final l in rawLines) {
        final trimmed = l.trim();
        if (trimmed.isEmpty) continue;
        if (trimmed.startsWith('Filesystem') ||
            trimmed.startsWith('Sys.') ||
            trimmed.startsWith('1K-blocks')) {
          continue;
        }

        final parts = trimmed.split(RegExp(r'\s+'));
        if (parts.length == 1 &&
            (parts[0].startsWith('/') ||
                parts[0].contains(':') ||
                parts[0] == 'tmpfs' ||
                parts[0].startsWith('overlay'))) {
          pendingDev = parts[0];
          continue;
        }
        if (pendingDev.isNotEmpty) {
          lines.add('$pendingDev $trimmed');
          pendingDev = '';
        } else {
          lines.add(trimmed);
        }
      }

      for (final line in lines) {
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 2) continue;

        // /proc/mounts fallback line: <device> <target> <type> <options>...
        if (parts.length >= 3 &&
            int.tryParse(parts[1]) == null &&
            (parts[1].startsWith('/') || parts[1] == 'swap')) {
          final dev = parts[0];
          final target = parts[1];
          final fs = parts[2];

          if (target.startsWith('/proc') ||
              target.startsWith('/sys') ||
              target.startsWith('/dev/pts') ||
              target == '/dev/shm') {
            continue;
          }

          list.add(
            MountPointItem(
              mountPath: target,
              device: dev,
              filesystemType: fs,
              sizeBytes: 0,
              usedBytes: 0,
              availableBytes: 0,
            ),
          );
          continue;
        }

        // df output line matching: search for column with '%'
        int percentIdx = -1;
        for (int i = 0; i < parts.length; i++) {
          if (parts[i].endsWith('%') || parts[i].contains('%')) {
            percentIdx = i;
            break;
          }
        }

        if (percentIdx >= 1) {
          final dev = parts[0];
          String fs = '';
          int blockIdx = 1;

          if (percentIdx >= 5 &&
              int.tryParse(parts[1]) == null &&
              !parts[1].contains('%')) {
            fs = parts[1];
            blockIdx = 2;
          }

          final sizeRawStr = parts[blockIdx];
          final hasUnitSuffix = RegExp(
            r'[a-zA-Z]$',
          ).hasMatch(sizeRawStr.trim());
          final lineDataSource = (hasUnitSuffix || isHumanFormat)
              ? StorageDataSource.dfHuman
              : StorageDataSource.dfKBlocks;

          int rawSize = parseNum(sizeRawStr);
          int rawUsed = percentIdx - blockIdx >= 2
              ? parseNum(parts[blockIdx + 1])
              : 0;
          int rawAvail = percentIdx - blockIdx >= 3
              ? parseNum(parts[blockIdx + 2])
              : 0;

          final target = parts.sublist(percentIdx + 1).join(' ');
          final mountPath = target.isEmpty ? '/' : target;

          final multiplier = MountPointItem.determineByteMultiplier(
            rawSize: rawSize,
            rawUsed: rawUsed,
            rawAvail: rawAvail,
            bsize: 0,
            hasExplicitByteKey: hasUnitSuffix,
            hasUnitSuffix: hasUnitSuffix,
            unitStr: hasUnitSuffix ? 'human' : '',
            mountPath: mountPath,
            dataSource: lineDataSource,
          );

          int sizeBytes = rawSize * multiplier;
          int usedBytes = rawUsed * multiplier;
          int availBytes = rawAvail * multiplier;

          if (fs.isEmpty || fs.toLowerCase() == 'unknown') {
            if (dev.contains('ubi')) {
              fs = 'ubifs';
            } else if (dev.contains('overlay') ||
                mountPath.contains('overlay')) {
              fs = 'overlayfs';
            } else if (dev == 'tmpfs' ||
                mountPath == '/tmp' ||
                mountPath == '/dev') {
              fs = 'tmpfs';
            } else if (dev.contains('root') || mountPath == '/rom') {
              fs = 'squashfs';
            } else if (dev.contains('mtdblock')) {
              fs = 'jffs2';
            } else {
              fs = 'ext4';
            }
          }

          if (mountPath == '/rom' || fs.toLowerCase() == 'squashfs') {
            availBytes = 0;
            if (usedBytes == 0) {
              usedBytes = sizeBytes;
            }
          }

          list.add(
            MountPointItem(
              mountPath: mountPath,
              device: dev,
              filesystemType: fs,
              sizeBytes: sizeBytes,
              usedBytes: usedBytes,
              availableBytes: availBytes < 0 ? 0 : availBytes,
            ),
          );
        }
      }
    } else if (data is List) {
      for (final item in data) {
        if (item is Map) {
          list.add(
            MountPointItem.fromJson(
              Map<String, dynamic>.from(item),
              dataSource: StorageDataSource.rpcJson,
            ),
          );
        }
      }
    } else if (data is Map) {
      final mapData = Map<String, dynamic>.from(data);

      // Check for system.info root & tmp maps if present
      if (mapData['root'] is Map) {
        final rootMap = Map<String, dynamic>.from(mapData['root']);
        final totalKb = parseNum(rootMap['total']);
        final usedKb = parseNum(rootMap['used']);
        final availKb = parseNum(rootMap['avail'] ?? rootMap['free']);
        list.add(
          MountPointItem(
            mountPath: '/',
            device: '/dev/root',
            filesystemType: 'overlayfs',
            sizeBytes: totalKb * 1024,
            usedBytes: usedKb * 1024,
            availableBytes: availKb * 1024,
          ),
        );
      }
      if (mapData['tmp'] is Map) {
        final tmpMap = Map<String, dynamic>.from(mapData['tmp']);
        final totalKb = parseNum(tmpMap['total']);
        final usedKb = parseNum(tmpMap['used']);
        final availKb = parseNum(tmpMap['avail'] ?? tmpMap['free']);
        list.add(
          MountPointItem(
            mountPath: '/tmp',
            device: 'tmpfs',
            filesystemType: 'tmpfs',
            sizeBytes: totalKb * 1024,
            usedBytes: usedKb * 1024,
            availableBytes: availKb * 1024,
          ),
        );
      }

      final inner =
          mapData['mountPoints'] ??
          mapData['mounts'] ??
          mapData['result'] ??
          mapData['values'] ??
          mapData['data'] ??
          mapData['fs'];

      if (inner is List) {
        for (final item in inner) {
          if (item is Map) {
            list.add(
              MountPointItem.fromJson(
                Map<String, dynamic>.from(item),
                dataSource: StorageDataSource.rpcJson,
              ),
            );
          }
        }
      } else if (inner is Map) {
        final targetMap = Map<String, dynamic>.from(inner);
        targetMap.forEach((key, val) {
          if (val is Map) {
            final copy = Map<String, dynamic>.from(val);
            if (copy['mount'] == null &&
                copy['target'] == null &&
                copy['mountpoint'] == null &&
                copy['dest'] == null) {
              copy['mount'] = key;
            }
            list.add(
              MountPointItem.fromJson(
                copy,
                dataSource: StorageDataSource.rpcJson,
              ),
            );
          }
        });
      } else {
        mapData.forEach((key, val) {
          if (key == 'root' || key == 'tmp') return;
          if (val is Map) {
            final copy = Map<String, dynamic>.from(val);
            final typeStr = copy['.type']?.toString();
            if (typeStr != null && typeStr != 'mount' && typeStr != 'swap') {
              return;
            }
            if (copy['mount'] == null &&
                copy['target'] == null &&
                copy['mountpoint'] == null &&
                copy['dest'] == null) {
              copy['mount'] = key;
            }
            list.add(
              MountPointItem.fromJson(
                copy,
                dataSource: StorageDataSource.rpcJson,
              ),
            );
          }
        });
      }
    }

    // Default mock data only if in Reviewer Mode
    if (isReviewerMode && list.isEmpty) {
      list.addAll([
        const MountPointItem(
          mountPath: '/',
          device: '/dev/root',
          filesystemType: 'squashfs',
          sizeBytes: 134217728, // 128 MB
          usedBytes: 47185920, // 45 MB
          availableBytes: 87031808,
        ),
        const MountPointItem(
          mountPath: '/overlay',
          device: '/dev/mtdblock6',
          filesystemType: 'ext4',
          sizeBytes: 67108864, // 64 MB
          usedBytes: 16777216, // 16 MB
          availableBytes: 50331648,
        ),
        const MountPointItem(
          mountPath: '/tmp',
          device: 'tmpfs',
          filesystemType: 'tmpfs',
          sizeBytes: 268435456, // 256 MB
          usedBytes: 2097152, // 2 MB
          availableBytes: 266338304,
        ),
      ]);
    }

    return StorageOverview(mountPoints: list);
  }

  MountPointItem? get rootFs {
    if (mountPoints.isEmpty) return null;
    for (final m in mountPoints) {
      if (m.mountPath == '/') return m;
    }
    for (final m in mountPoints) {
      if (m.mountPath == '/rom' || m.device == '/dev/root') return m;
    }
    for (final m in mountPoints) {
      if (m.isRoot) return m;
    }
    return mountPoints.first;
  }

  MountPointItem? get overlayFs {
    if (mountPoints.isEmpty) return null;
    for (final m in mountPoints) {
      if (m.mountPath == '/overlay' ||
          m.device.contains('ubi') ||
          m.device.contains('overlay')) {
        return m;
      }
    }
    return null;
  }

  MountPointItem? get tmpFs {
    if (mountPoints.isEmpty) return null;
    for (final m in mountPoints) {
      if (m.mountPath == '/tmp') return m;
    }
    for (final m in mountPoints) {
      if (m.isTmp) return m;
    }
    return null;
  }

  /// Priority order for primary dashboard storage display:
  /// 1. Overlay (/overlay) [1st priority]
  /// 2. TempFS (/tmp) [2nd priority]
  /// Fallback: If any one or both are not found, fill from other mounted partitions (e.g. Root /) in order.
  /// Maximum of 2 storage items returned for dashboard card display.
  List<MountPointItem> get priorityDisplayMounts {
    if (mountPoints.isEmpty) return [];

    final selected = <MountPointItem>[];

    // 1st priority: Overlay FS (/overlay)
    MountPointItem? overlayItem;
    for (final m in mountPoints) {
      if (m.mountPath == '/overlay' || m.isOverlay) {
        overlayItem = m;
        break;
      }
    }
    overlayItem ??= overlayFs;
    if (overlayItem != null && mountPoints.contains(overlayItem)) {
      selected.add(overlayItem);
    }

    // 2nd priority: TempFS (/tmp)
    MountPointItem? tmpItem;
    for (final m in mountPoints) {
      if ((m.mountPath == '/tmp' || m.isTmp) && !selected.contains(m)) {
        tmpItem = m;
        break;
      }
    }
    tmpItem ??= tmpFs;
    if (tmpItem != null &&
        !selected.contains(tmpItem) &&
        mountPoints.contains(tmpItem)) {
      selected.add(tmpItem);
    }

    // Fallback: If we have fewer than 2 partitions, pick from any remaining mount points (e.g. Root /)
    for (final m in mountPoints) {
      if (selected.length >= 2) break;
      if (!selected.contains(m)) {
        selected.add(m);
      }
    }

    return selected.take(2).toList();
  }

  List<MountPointItem> get mountedDevices {
    return mountPoints;
  }

  int get totalSizeBytes {
    final primary = overlayFs ?? rootFs;
    final primarySize = primary?.sizeBytes ?? 0;
    int extraSize = 0;
    for (final m in mountPoints) {
      if (!m.isTmp &&
          m != primary &&
          m.mountPath != '/' &&
          m.mountPath != '/rom' &&
          m.mountPath != '/overlay') {
        extraSize += m.sizeBytes;
      }
    }
    return primarySize + extraSize;
  }

  int get totalUsedBytes {
    final primary = overlayFs ?? rootFs;
    final primaryUsed = primary?.usedBytes ?? 0;
    int extraUsed = 0;
    for (final m in mountPoints) {
      if (!m.isTmp &&
          m != primary &&
          m.mountPath != '/' &&
          m.mountPath != '/rom' &&
          m.mountPath != '/overlay') {
        extraUsed += m.usedBytes;
      }
    }
    return primaryUsed + extraUsed;
  }

  double get overallUsedPercent {
    final total = totalSizeBytes;
    if (total <= 0) return 0.0;
    return ((totalUsedBytes / total) * 100).clamp(0.0, 100.0);
  }
}
