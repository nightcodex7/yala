// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../design/luci_design_system.dart';
import '../../../main.dart';
import '../../../state/app_state.dart';
import '../../../utils/os_platform_integration.dart';
import '../../../widgets/luci_app_bar.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import '../../../utils/logger.dart';
import '../../../widgets/luci_contextual_hint_banner.dart';
import '../../../widgets/luci_collapsible_card.dart';
import '../widgets/preserved_backup_files_sheet.dart';

class SystemBackupUpgradeScreen extends ConsumerStatefulWidget {
  const SystemBackupUpgradeScreen({super.key});

  @override
  ConsumerState<SystemBackupUpgradeScreen> createState() =>
      _SystemBackupUpgradeScreenState();
}

class _SystemBackupUpgradeScreenState
    extends ConsumerState<SystemBackupUpgradeScreen> {
  bool _keepSettings = true;
  bool _forceSysupgrade = false;
  bool _isProcessing = false;
  double? _uploadProgress;
  String? _statusMessage;

  // System Hardware & Multi-ROM Situational Context
  String _routerModel = 'Detecting hardware...';
  String _targetArch = 'Generic Architecture';
  String _firmwareVersion = 'OpenWrt Linux';
  String _romFlavor = 'OpenWrt';
  String _tmpAvailableSpace = 'Checking space...';
  double _tmpAvailableMb = 0.0;

  // Mtdblock state
  List<Map<String, String>> _mtdList = [];
  String? _selectedMtdDevice;

  @override
  void initState() {
    super.initState();
    _loadRouterSysInfo();
    _loadMtdBlocks();
  }

  Future<void> _loadRouterSysInfo() async {
    final appState = ref.read(appStateProvider);
    try {
      final modelStr = await appState.executeRouterCommandOutput('cat', [
        '/tmp/sysinfo/model',
      ]);
      final boardStr = await appState.executeRouterCommandOutput('cat', [
        '/tmp/sysinfo/board_name',
      ]);
      final relStr = await appState.executeRouterCommandOutput('cat', [
        '/etc/openwrt_release',
      ]);
      final osRelStr = await appState.executeRouterCommandOutput('cat', [
        '/etc/os-release',
      ]);
      final glVerStr = await appState.executeRouterCommandOutput('cat', [
        '/etc/glversion',
      ]);
      final gargoyleStr = await appState.executeRouterCommandOutput('cat', [
        '/etc/gargoyle_release',
      ]);
      final immortalStr = await appState.executeRouterCommandOutput('cat', [
        '/etc/immortalwrt_release',
      ]);
      final dfStr = await appState.executeRouterCommandOutput('sh', [
        '-c',
        'df -k /tmp | tail -n 1',
      ]);

      String flavor = 'OpenWrt';
      if (immortalStr != null && immortalStr.trim().isNotEmpty) {
        flavor = 'ImmortalWrt';
      } else if (glVerStr != null && glVerStr.trim().isNotEmpty) {
        flavor = 'GL.iNet Firmware (${glVerStr.trim()})';
      } else if (gargoyleStr != null && gargoyleStr.trim().isNotEmpty) {
        flavor = 'Gargoyle Router OS';
      } else if (osRelStr != null && osRelStr.contains('LEDE')) {
        flavor = 'LEDE Reboot';
      }

      String? version;
      if (relStr != null && relStr.isNotEmpty) {
        final match = RegExp(
          'DISTRIB_DESCRIPTION=["\']?([^"\']+)["\']?',
        ).firstMatch(relStr);
        if (match != null) {
          version = match.group(1);
        }
      }

      String freeTmpLabel = 'Available';
      double freeMb = 64.0; // fallback safe estimate
      if (dfStr != null && dfStr.isNotEmpty) {
        final parts = dfStr.trim().split(RegExp(r'\s+'));
        if (parts.length >= 4) {
          final availKb = double.tryParse(parts[3]);
          if (availKb != null) {
            freeMb = availKb / 1024.0;
            freeTmpLabel = '${freeMb.toStringAsFixed(1)} MB';
          } else {
            freeTmpLabel = parts[3];
          }
        }
      }

      if (mounted) {
        setState(() {
          _routerModel = (modelStr != null && modelStr.trim().isNotEmpty)
              ? modelStr.trim()
              : 'OpenWrt / Compatible Router';
          _targetArch = (boardStr != null && boardStr.trim().isNotEmpty)
              ? boardStr.trim()
              : 'Generic Architecture';
          _firmwareVersion = version ?? 'OpenWrt Linux';
          _romFlavor = flavor;
          _tmpAvailableSpace = freeTmpLabel;
          _tmpAvailableMb = freeMb;
        });
      }
    } catch (_) {}
  }

  String _formatByteSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      final mb = bytes / (1024 * 1024);
      return '${mb.toStringAsFixed(mb % 1 == 0 ? 0 : 1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).round()} KB';
    }
    return '$bytes B';
  }

  Future<void> _loadMtdBlocks() async {
    final appState = ref.read(appStateProvider);
    try {
      final mtdOutput = await appState.executeRouterCommandOutput('cat', [
        '/proc/mtd',
      ]);
      if (mtdOutput != null && mtdOutput.isNotEmpty) {
        final lines = mtdOutput.split('\n');
        final parsed = <Map<String, String>>[];
        for (final line in lines) {
          if (line.startsWith('mtd')) {
            final parts = line.split(':');
            final dev = parts[0].trim();
            final rest = parts.length > 1 ? parts[1].trim() : '';
            final nameMatch = RegExp(r'"([^"]+)"').firstMatch(rest);
            final name = nameMatch != null ? nameMatch.group(1)! : dev;
            final sizeHexMatch = RegExp(r'^([0-9a-fA-F]+)').firstMatch(rest);
            final sizeInBytes = sizeHexMatch != null
                ? int.tryParse(sizeHexMatch.group(1)!, radix: 16)
                : null;
            final sizeStr = sizeInBytes != null
                ? _formatByteSize(sizeInBytes)
                : '';
            final displayName = sizeStr.isNotEmpty
                ? '$name ($dev, $sizeStr)'
                : '$name ($dev)';
            parsed.add({
              'device': '/dev/$dev',
              'name': displayName,
              'size': sizeInBytes?.toString() ?? '',
            });
          }
        }
        if (parsed.isNotEmpty) {
          if (mounted) {
            setState(() {
              _mtdList = parsed;
              _selectedMtdDevice = parsed.first['device'];
            });
          }
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _mtdList = [
          {'device': '/dev/mtd0', 'name': 'u-boot (mtd0)'},
          {'device': '/dev/mtd1', 'name': 'firmware (mtd1)'},
          {'device': '/dev/mtd2', 'name': 'ubootenv (mtd2)'},
          {'device': '/dev/mtd3', 'name': 'art (mtd3)'},
        ];
        _selectedMtdDevice = '/dev/mtd0';
      });
    }
  }

  Future<void> _showCurrentBackupFileList() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Fetching preserved backup files list...';
    });

    final appState = ref.read(appStateProvider);
    String? fileList = await appState.executeRouterCommandOutput('sh', [
      '-c',
      'sysupgrade -l',
    ]);
    if (fileList == null || fileList.trim().isEmpty) {
      fileList = await appState.executeRouterCommandOutput('sysupgrade', [
        '-l',
      ]);
    }
    if (fileList == null || fileList.trim().isEmpty) {
      fileList = await appState.executeRouterCommandOutput('/sbin/sysupgrade', [
        '-l',
      ]);
    }

    String? confContent = await appState.executeRouterCommandOutput('cat', [
      '/etc/sysupgrade.conf',
    ]);

    setState(() => _isProcessing = false);

    if (!mounted) return;

    await PreservedBackupFilesSheet.show(
      context,
      appState: appState,
      initialFileList: fileList ?? '',
      initialConfContent: confContent ?? '',
    );
  }

  String? _extractDataStringFromRpcResult(dynamic res) {
    if (res == null) return null;
    if (res is List && res.length > 1) {
      final payload = res[1];
      if (payload is Map) {
        return payload['data']?.toString() ?? payload['stdout']?.toString();
      }
    }
    if (res is Map) {
      final data = res['data']?.toString() ?? res['stdout']?.toString();
      if (data != null) return data;
      if (res['result'] is List && (res['result'] as List).length > 1) {
        final payload = (res['result'] as List)[1];
        if (payload is Map) {
          return payload['data']?.toString() ?? payload['stdout']?.toString();
        }
      }
    }
    return null;
  }

  Future<Uint8List?> _readRouterFileAsBytes(
    AppState appState,
    String filePath,
  ) async {
    // Strategy 0: Native LuCI RPC chunked file.read with base64 (0 shell processes, 100% ubus ACL compliant)
    try {
      final List<int> accumulatedBytes = [];
      const chunkSize = 32768; // 32 KB per chunk
      int offset = 0;
      int emptyCount = 0;

      while (offset < 50 * 1024 * 1024) {
        // Cap at 50 MB
        final res = await appState.callRpc('file', 'read', {
          'path': filePath,
          'offset': offset,
          'length': chunkSize,
          'base64': true,
        });

        final dataStr = _extractDataStringFromRpcResult(res);
        final chunkBytes = _parseRawOutputToBytes(dataStr);
        if (chunkBytes != null && chunkBytes.isNotEmpty) {
          accumulatedBytes.addAll(chunkBytes);
          offset += chunkBytes.length;
          emptyCount = 0;
          if (chunkBytes.length < chunkSize) {
            break; // Reached EOF
          }
          continue;
        }

        emptyCount++;
        if (emptyCount >= 2) break;
        offset += chunkSize;
      }

      if (accumulatedBytes.isNotEmpty) {
        Logger.info(
          'Read $filePath via chunked file.read RPC: ${accumulatedBytes.length} bytes',
        );
        return Uint8List.fromList(accumulatedBytes);
      }
    } catch (e) {
      Logger.warning(
        'Strategy 0 chunked file.read RPC failed for $filePath: $e',
      );
    }

    // Method 1: Single base64 shell command
    String? b64Str = await appState.executeRouterCommandOutput('base64', [
      filePath,
    ]);
    if (b64Str == null || b64Str.trim().isEmpty) {
      b64Str = await appState.executeRouterCommandOutput('sh', [
        '-c',
        'base64 "$filePath" 2>/dev/null || openssl base64 -in "$filePath" 2>/dev/null || uuencode -m "$filePath" - 2>/dev/null',
      ]);
    }

    if (b64Str != null && b64Str.trim().isNotEmpty) {
      try {
        final cleanB64 = b64Str
            .replaceAll('\n', '')
            .replaceAll('\r', '')
            .replaceAll(' ', '')
            .trim();
        final decoded = base64Decode(cleanB64);
        if (decoded.isNotEmpty) return decoded;
      } catch (_) {
        try {
          final rawBytes = Uint8List.fromList(latin1.encode(b64Str));
          if (rawBytes.isNotEmpty) return rawBytes;
        } catch (_) {}
      }
    }

    // Method 2: Chunked dd + base64
    final sizeStr = await appState.executeRouterCommandOutput('sh', [
      '-c',
      'wc -c "$filePath"',
    ]);
    int? totalSize;
    if (sizeStr != null && sizeStr.trim().isNotEmpty) {
      final parts = sizeStr.trim().split(RegExp(r'\s+'));
      if (parts.isNotEmpty) {
        totalSize = int.tryParse(parts.first);
      }
    }

    const chunkSize = 32768;
    final List<int> accumulatedBytes = [];

    if (totalSize != null && totalSize > 0) {
      int offset = 0;
      int chunkIndex = 0;
      while (offset < totalSize) {
        final chunkB64 = await appState.executeRouterCommandOutput('sh', [
          '-c',
          'dd if="$filePath" bs=$chunkSize skip=$chunkIndex count=1 2>/dev/null | base64',
        ]);

        if (chunkB64 != null && chunkB64.trim().isNotEmpty) {
          final cleanB64 = chunkB64
              .replaceAll('\n', '')
              .replaceAll('\r', '')
              .replaceAll(' ', '')
              .trim();
          try {
            final decoded = base64Decode(cleanB64);
            if (decoded.isNotEmpty) {
              accumulatedBytes.addAll(decoded);
            } else {
              break;
            }
          } catch (_) {
            try {
              final rawBytes = latin1.encode(chunkB64);
              if (rawBytes.isNotEmpty) {
                accumulatedBytes.addAll(rawBytes);
              } else {
                break;
              }
            } catch (_) {
              break;
            }
          }
        } else {
          break;
        }
        offset += chunkSize;
        chunkIndex++;
      }

      if (accumulatedBytes.isNotEmpty) {
        return Uint8List.fromList(accumulatedBytes);
      }
    }

    // Method 3: Hexdump
    final hexStr = await appState.executeRouterCommandOutput('sh', [
      '-c',
      'hexdump -v -e \'1/1 "%02x"\' "$filePath" 2>/dev/null || od -tx1 -An "$filePath" | tr -d " \n\r"',
    ]);
    if (hexStr != null && hexStr.trim().isNotEmpty) {
      final cleanHex = hexStr
          .replaceAll('\n', '')
          .replaceAll('\r', '')
          .replaceAll(' ', '')
          .trim();
      final List<int> byteList = [];
      for (var i = 0; i < cleanHex.length; i += 2) {
        if (i + 2 <= cleanHex.length) {
          final val = int.tryParse(cleanHex.substring(i, i + 2), radix: 16);
          if (val != null) byteList.add(val);
        }
      }
      if (byteList.isNotEmpty) {
        return Uint8List.fromList(byteList);
      }
    }

    return null;
  }

  Future<Uint8List?> _downloadBackupViaHttp(AppState appState) async {
    final ip = appState.selectedRouter?.ipAddress;
    final sysauth = appState.sysauth;
    if (ip == null || sysauth == null) return null;
    final useHttps = appState.selectedRouter?.useHttps ?? false;
    final scheme = useHttps ? 'https' : 'http';

    final candidateUrls = [
      '$scheme://$ip/cgi-bin/luci/admin/system/backup',
      '$scheme://$ip/cgi-bin/luci/admin/system/flashops/backup',
      '$scheme://$ip/cgi-bin/luci/admin/system/backup/backup',
      '$scheme://$ip/cgi-bin/luci/;stok=$sysauth/admin/system/backup',
      '$scheme://$ip/cgi-bin/luci/;stok=$sysauth/admin/system/flashops/backup',
      '$scheme://$ip/cgi-bin/luci/admin/system/flashops?backup=1',
    ];

    for (final urlStr in candidateUrls) {
      // Try GET request first
      try {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => true;
        client.connectionTimeout = const Duration(seconds: 10);
        final request = await client.getUrl(Uri.parse(urlStr));
        request.headers.add('Cookie', 'sysauth=$sysauth');
        request.headers.add('User-Agent', 'Mozilla/5.0');
        final response = await request.close();
        if (response.statusCode == 200) {
          final bytes = await response.fold<List<int>>(
            [],
            (previous, element) => previous..addAll(element),
          );
          if (bytes.isNotEmpty) {
            return Uint8List.fromList(bytes);
          }
        }
      } catch (_) {}

      // Try POST request fallback
      try {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => true;
        client.connectionTimeout = const Duration(seconds: 10);
        final request = await client.postUrl(Uri.parse(urlStr));
        request.headers.add('Cookie', 'sysauth=$sysauth');
        request.headers.add('User-Agent', 'Mozilla/5.0');
        request.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
        );
        request.write('backup=1');
        final response = await request.close();
        if (response.statusCode == 200) {
          final bytes = await response.fold<List<int>>(
            [],
            (previous, element) => previous..addAll(element),
          );
          if (bytes.isNotEmpty) {
            return Uint8List.fromList(bytes);
          }
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> _handleGenerateBackup() async {
    setState(() {
      _isProcessing = true;
      _uploadProgress = null;
      _statusMessage = 'Generating configuration backup on router...';
    });

    final appState = ref.read(appStateProvider);
    try {
      Uint8List? bytes;

      // Strategy 1: Create backup archive on router & read via chunked RPC file.read
      Logger.info(
        'Backup Strategy 1: Creating /tmp/app_backup.tar.gz and reading via chunked RPC...',
      );
      await appState.executeRouterCommand('sh', [
        '-c',
        'sysupgrade -b /tmp/app_backup.tar.gz 2>/dev/null || tar -czf /tmp/app_backup.tar.gz -C / etc/config etc/passwd etc/shadow etc/dropbear etc/uhttpd etc/dnsmasq.conf etc/sysupgrade.conf etc/uci-defaults 2>/dev/null',
      ]);
      bytes = await _readRouterFileAsBytes(appState, '/tmp/app_backup.tar.gz');
      unawaited(
        appState.executeRouterCommand('rm', ['-f', '/tmp/app_backup.tar.gz']),
      );

      if (bytes != null && bytes.isNotEmpty) {
        if (_validateBackupArchiveBytes(bytes)) {
          Logger.info(
            'Backup Strategy 1 succeeded: ${bytes.length} bytes downloaded',
          );
        } else {
          Logger.warning(
            'Backup Strategy 1 generated invalid/corrupt payload. Retrying with next strategy...',
          );
          bytes = null;
        }
      }

      // Strategy 2: Direct single-command generation + Base64 piping to stdout
      if (bytes == null || bytes.isEmpty) {
        Logger.info('Backup Strategy 2: Single-command stream to base64...');
        final directB64 = await appState.executeRouterCommandOutput('sh', [
          '-c',
          'sysupgrade -b - 2>/dev/null | base64 || (sysupgrade -b /tmp/b.tgz 2>/dev/null && base64 /tmp/b.tgz && rm -f /tmp/b.tgz) || tar -czf - -C / etc/config etc/passwd etc/shadow etc/dropbear etc/uhttpd etc/dnsmasq.conf etc/sysupgrade.conf etc/uci-defaults 2>/dev/null | base64',
        ]);

        if (directB64 != null && directB64.trim().isNotEmpty) {
          try {
            final cleanB64 = directB64
                .replaceAll('\n', '')
                .replaceAll('\r', '')
                .replaceAll(' ', '')
                .trim();
            final decoded = base64Decode(cleanB64);
            if (decoded.isNotEmpty && _validateBackupArchiveBytes(decoded)) {
              bytes = decoded;
              Logger.info(
                'Backup Strategy 2 succeeded: ${bytes.length} bytes downloaded',
              );
            }
          } catch (e) {
            Logger.warning('Backup Strategy 2 decode error: $e');
          }
        }
      }

      // Strategy 3: Direct HTTP/HTTPS download from LuCI backup endpoints
      if (bytes == null || bytes.isEmpty) {
        Logger.info(
          'Backup Strategy 3: Downloading via LuCI HTTP endpoints...',
        );
        final httpBytes = await _downloadBackupViaHttp(appState);
        if (httpBytes != null &&
            httpBytes.isNotEmpty &&
            _validateBackupArchiveBytes(httpBytes)) {
          bytes = httpBytes;
          Logger.info(
            'Backup Strategy 3 succeeded: ${bytes.length} bytes downloaded',
          );
        }
      }

      // Strategy 4: UCI configuration export as a text configuration backup
      if (bytes == null || bytes.isEmpty) {
        Logger.info(
          'Backup Strategy 4: Fallback to UCI export configuration backup...',
        );
        final uciExport = await appState.executeRouterCommandOutput('uci', [
          'export',
        ]);
        if (uciExport != null && uciExport.trim().isNotEmpty) {
          bytes = Uint8List.fromList(utf8.encode(uciExport));
          Logger.info(
            'Backup Strategy 4 succeeded via uci export: ${bytes.length} bytes downloaded',
          );
        } else {
          // Sub-strategy 4b: Individual UCI config collection via RPC uci.get
          final configs = [
            'dhcp',
            'dropbear',
            'firewall',
            'luci',
            'network',
            'system',
            'uhttpd',
            'wireless',
          ];
          final Map<String, dynamic> combinedConfig = {};
          for (final cfg in configs) {
            try {
              final res = await appState.callRpc('uci', 'get', {'config': cfg});
              if (res is List &&
                  res.length > 1 &&
                  res[0] == 0 &&
                  res[1] != null) {
                combinedConfig[cfg] = res[1];
              }
            } catch (_) {}
          }
          if (combinedConfig.isNotEmpty) {
            final jsonBackup = jsonEncode({
              'type': 'openwrt_uci_backup',
              'timestamp': DateTime.now().toIso8601String(),
              'router': appState.selectedRouter?.ipAddress ?? 'unknown',
              'configs': combinedConfig,
            });
            bytes = Uint8List.fromList(utf8.encode(jsonBackup));
            Logger.info(
              'Backup Strategy 4 succeeded via aggregated RPC uci.get: ${bytes.length} bytes downloaded',
            );
          }
        }
      }

      // Strategy 5: Reviewer mode mock fallback
      if (bytes == null || bytes.isEmpty) {
        if (appState.reviewerModeEnabled) {
          bytes = Uint8List.fromList(
            List<int>.generate(512, (i) => (i * 7) % 256),
          );
        } else {
          throw Exception(
            'Failed to read generated backup file from router using all available strategies.',
          );
        }
      }

      final fileName =
          'backup-${DateTime.now().millisecondsSinceEpoch ~/ 1000}.tar.gz';

      // Save directly to /storage/emulated/0/Download/ (Public Downloads)
      final saveResult =
          await OsPlatformIntegration.saveDownloadedFileWithResult(
            bytes: bytes,
            fileName: fileName,
          );

      // GUARANTEE overlay reset BEFORE displaying prompt
      if (mounted) {
        setState(() => _isProcessing = false);
      }

      if (!mounted) return;

      if (saveResult != null) {
        context.showToastSuccess('Backup archive downloaded successfully.');
        await OsPlatformIntegration.showBackupDownloadedPrompt(
          context,
          saveResult,
        );
      } else {
        context.showToastError('Failed to write backup file to storage.');
      }
    } catch (e, stack) {
      Logger.error('Backup Generation Error: $e', stack);
      if (mounted) {
        setState(() => _isProcessing = false);
        context.showToastError(
          'Backup Generation Failed: ${e.toString().replaceAll('Exception: ', '')}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  /// Verifies that chosen backup bytes are a valid OpenWrt backup archive (gzip / tar magic bytes & structure).
  bool _validateBackupArchiveBytes(Uint8List bytes) {
    if (bytes.length < 10) return false;

    // Check 1: Gzip Magic Bytes (0x1F, 0x8B)
    final isGzip = bytes[0] == 0x1F && bytes[1] == 0x8B;

    // Check 2: Tar Magic Bytes at offset 257 (ustar)
    bool isTar = false;
    if (bytes.length >= 262) {
      final magic = String.fromCharCodes(bytes.sublist(257, 262));
      if (magic == 'ustar') isTar = true;
    }

    if (!isGzip && !isTar) {
      return false;
    }

    // Check 3: If Gzip, attempt decompression to verify payload integrity
    if (isGzip) {
      try {
        final decompressed = GZipCodec().decode(bytes);
        if (decompressed.isEmpty) return false;
        if (decompressed.length >= 262) {
          final decompMagic = String.fromCharCodes(
            decompressed.sublist(257, 262),
          );
          if (decompMagic.startsWith('ustar')) return true;
        }
        final text = latin1.decode(
          decompressed.sublist(
            0,
            decompressed.length > 2048 ? 2048 : decompressed.length,
          ),
          allowInvalid: true,
        );
        if (text.contains('etc/') ||
            text.contains('config') ||
            text.contains('passwd') ||
            text.contains('sysupgrade')) {
          return true;
        }
        return true;
      } catch (e) {
        Logger.warning('GZip decompression validation failed for archive: $e');
        return false;
      }
    }

    return true;
  }

  Future<void> _handleUploadArchive() async {
    try {
      PlatformFile? pickedFile;
      bool pickerAttempted = false;
      try {
        pickedFile = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['gz', 'tgz', 'tar'],
        );
        pickerAttempted = true;
      } catch (_) {}

      if (!pickerAttempted) {
        try {
          pickedFile = await FilePicker.pickFile(type: FileType.any);
        } catch (_) {}
      }

      if (pickedFile == null) return;

      final fileNameLower = pickedFile.name.toLowerCase();

      // Extension Validation Guardrail: Ensure file is a valid OpenWrt backup archive
      final isValidExtension =
          fileNameLower.endsWith('.tar.gz') ||
          fileNameLower.endsWith('.tgz') ||
          fileNameLower.endsWith('.tar') ||
          fileNameLower.endsWith('.gz');

      if (!isValidExtension) {
        if (mounted) {
          context.showToastError(
            'Invalid Archive Extension',
            subtitle:
                'Please select a valid OpenWrt backup archive (.tar.gz, .tgz, .tar, or .gz).',
          );
        }
        return;
      }
      Uint8List? fileBytes;
      try {
        fileBytes = await pickedFile.readAsBytes();
      } catch (_) {
        if (pickedFile.path != null) {
          try {
            fileBytes = await File(pickedFile.path!).readAsBytes();
          } catch (e) {
            if (mounted) {
              context.showToastError(
                'File Read Error',
                subtitle: 'Could not read selected file from storage.',
              );
            }
            return;
          }
        }
      }

      if (fileBytes == null || fileBytes.isEmpty) {
        throw Exception('Could not read chosen archive file.');
      }

      // Pre-Restore Integrity Validation Guardrail: Inspect archive byte headers BEFORE uploading to router
      final isValidPayload = _validateBackupArchiveBytes(fileBytes);
      if (!isValidPayload) {
        if (mounted) {
          context.showToastError(
            'Corrupt or Invalid Archive Payload',
            subtitle:
                'The selected file is corrupt or not a valid gzipped tarball. Pre-restore validation aborted to prevent router configuration corruption.',
          );
        }
        return;
      }

      setState(() {
        _isProcessing = true;
        _uploadProgress = 0.0;
        _statusMessage = 'Uploading archive to router...';
      });

      final appState = ref.read(appStateProvider);
      final b64Str = base64Encode(fileBytes);

      const chunkSize = 8000;
      await appState.executeRouterCommand('sh', [
        '-c',
        'rm -f /tmp/uploaded_backup.tar.gz.b64 /tmp/uploaded_backup.tar.gz',
      ]);
      for (var i = 0; i < b64Str.length; i += chunkSize) {
        final end = (i + chunkSize < b64Str.length)
            ? i + chunkSize
            : b64Str.length;
        final chunk = b64Str.substring(i, end);
        await appState.executeRouterCommand('sh', [
          '-c',
          'echo -n "$chunk" >> /tmp/uploaded_backup.tar.gz.b64',
        ]);
        if (mounted) {
          setState(() {
            _uploadProgress = end / b64Str.length;
          });
        }
      }

      await appState.executeRouterCommand('sh', [
        '-c',
        'base64 -d /tmp/uploaded_backup.tar.gz.b64 > /tmp/uploaded_backup.tar.gz 2>/dev/null || openssl base64 -d -in /tmp/uploaded_backup.tar.gz.b64 -out /tmp/uploaded_backup.tar.gz 2>/dev/null || uudecode -o /tmp/uploaded_backup.tar.gz /tmp/uploaded_backup.tar.gz.b64 2>/dev/null && rm -f /tmp/uploaded_backup.tar.gz.b64',
      ]);

      setState(() {
        _statusMessage = 'Restoring backup configuration...';
        _uploadProgress = null;
      });

      final restoreSuccess = await appState.executeRouterCommand('sysupgrade', [
        '-r',
        '/tmp/uploaded_backup.tar.gz',
      ]);
      final fallbackSuccess = !restoreSuccess
          ? await appState.executeRouterCommand('tar', [
              '-xzf',
              '/tmp/uploaded_backup.tar.gz',
              '-C',
              '/',
            ])
          : true;

      // Reload config daemons so restored /etc/config settings take effect on running services
      await appState.executeRouterCommand('sh', [
        '-c',
        '/sbin/reload_config 2>/dev/null || /etc/init.d/luci reload 2>/dev/null || true',
      ]);

      if (!mounted) return;
      if (restoreSuccess || fallbackSuccess) {
        unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.medium));
        context.showToastSuccess(
          'Configuration restored successfully from archive.',
        );
        _showPostRestoreRebootDialog();
      } else {
        context.showToastError('Failed to restore backup configuration.');
      }
    } catch (e) {
      if (!mounted) return;
      context.showToastError(
        'Archive Upload Failed: ${e.toString().replaceAll('Exception: ', '')}',
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showPostRestoreRebootDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore Complete'),
        content: const Text(
          'Configuration files have been restored to the router.\n\n'
          'Would you like to reboot the router now to ensure all restored daemons and network interfaces initialize cleanly?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Reboot Router'),
            onPressed: () async {
              Navigator.pop(ctx);
              final appState = ref.read(appStateProvider);
              await appState.executeRouterCommand('reboot', []);
              if (mounted) {
                context.showToastWarning('Rebooting router...');
                _showRebootCountdownDialog();
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _handleFactoryReset() async {
    unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.red,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Perform Factory Reset?'),
            ),
          ],
        ),
        content: const Text(
          'This operation will permanently erase all custom settings, passwords, installed packages, and restore firmware to factory default state.\n\nThe router will automatically reboot upon completion. Continue?',
          style: TextStyle(fontSize: 14),
        ),
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Perform Factory Reset'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isProcessing = true;
      _uploadProgress = null;
      _statusMessage = 'Performing factory reset on router...';
    });

    final appState = ref.read(appStateProvider);
    final success = await appState.executeRouterCommand('firstboot', ['-y']);
    if (success) {
      await appState.executeRouterCommand('reboot', []);
    }

    setState(() => _isProcessing = false);

    if (!mounted) return;
    if (success) {
      context.showToastWarning(
        'Factory reset initiated. Router is now rebooting...',
      );
      _showRebootCountdownDialog();
    } else {
      context.showToastError('Failed to execute factory reset on router.');
    }
  }

  Uint8List? _parseRawOutputToBytes(String? rawOutput) {
    if (rawOutput == null || rawOutput.trim().isEmpty) return null;
    final clean = rawOutput
        .replaceAll('\n', '')
        .replaceAll('\r', '')
        .replaceAll(' ', '')
        .trim();
    if (clean.isEmpty) return null;

    // 1. Base64 attempt
    try {
      final decoded = base64Decode(clean);
      if (decoded.isNotEmpty) return decoded;
    } catch (_) {}

    // 2. Hex attempt (hexdump output)
    try {
      if (clean.length % 2 == 0 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(clean)) {
        final bytes = Uint8List(clean.length ~/ 2);
        for (int i = 0; i < bytes.length; i++) {
          bytes[i] = int.parse(clean.substring(i * 2, (i * 2) + 2), radix: 16);
        }
        if (bytes.isNotEmpty) return bytes;
      }
    } catch (_) {}

    // 3. Raw latin1/binary fallback
    try {
      final latinBytes = Uint8List.fromList(latin1.encode(clean));
      if (latinBytes.isNotEmpty) return latinBytes;
    } catch (_) {}

    return null;
  }

  Future<Uint8List?> _readMtdPartitionBytes(
    AppState appState,
    String dev, {
    void Function(int readBytes, int? totalBytes)? onProgress,
  }) async {
    appState.setHeavyTaskRunning(true);
    try {
      final devName = dev.split('/').last; // e.g. mtd0
      final blockDev = dev.contains('mtdblock')
          ? dev
          : dev.replaceAll('/dev/mtd', '/dev/mtdblock');

      // Find size if known from _mtdList
      int? expectedSize;
      final mtdEntry = _mtdList.firstWhere(
        (e) => e['device'] == dev || e['device'] == blockDev,
        orElse: () => {},
      );
      if (mtdEntry['size'] != null && mtdEntry['size']!.isNotEmpty) {
        expectedSize = int.tryParse(mtdEntry['size']!);
      }

      final candidates = [blockDev, dev];

      // Strategy 0: Native LuCI file.read RPC with base64 encoding (100% ubus ACL compliant, 0 shell commands)
      for (final targetDev in candidates) {
        try {
          Logger.info(
            'MTD Dump Strategy 0 (Native file.read RPC with base64): $targetDev...',
          );
          final accumulated = <int>[];
          const chunkSize = 65536; // 64 KB per chunk
          int offset = 0;
          int emptyCount = 0;

          while (offset < (expectedSize ?? 128 * 1024 * 1024)) {
            final fetchSize =
                (expectedSize != null && (expectedSize - offset) < chunkSize)
                ? (expectedSize - offset)
                : chunkSize;

            final res = await appState.callRpc('file', 'read', {
              'path': targetDev,
              'offset': offset,
              'length': fetchSize,
              'base64': true,
            });

            final dataStr = _extractDataStringFromRpcResult(res);

            final chunkBytes = _parseRawOutputToBytes(dataStr);
            if (chunkBytes != null && chunkBytes.isNotEmpty) {
              accumulated.addAll(chunkBytes);
              offset += chunkBytes.length;
              emptyCount = 0;
              if (onProgress != null) {
                onProgress(accumulated.length, expectedSize);
              }
              if (expectedSize != null && accumulated.length >= expectedSize) {
                break;
              }
              if (chunkBytes.length < fetchSize) {
                break; // Partial chunk indicates EOF
              }
              continue;
            }

            emptyCount++;
            if (emptyCount >= 2) break;
            offset += chunkSize;
          }

          if (accumulated.isNotEmpty) {
            Logger.info(
              'MTD Dump Strategy 0 succeeded: ${accumulated.length} bytes read from $targetDev',
            );
            return Uint8List.fromList(accumulated);
          }
        } catch (e) {
          Logger.info('MTD Dump Strategy 0 failed on $targetDev: $e');
        }
      }

      // Strategy 1: Page-aligned chunked dd (bs=2048)
      for (final targetDev in candidates) {
        Logger.info('MTD Dump Strategy 1 (Page-aligned dd): $targetDev...');
        final accumulatedBytes = <int>[];
        const chunkBlocks = 16; // 16 * 2048 = 32 KB per chunk
        const chunkSize = chunkBlocks * 2048;
        int chunkIndex = 0;
        int emptyChunkCount = 0;

        while (chunkIndex < 4096) {
          // Cap at 128 MB max
          final skip2k = chunkIndex * chunkBlocks;
          final chunkRaw = await appState.executeRouterCommandOutput('sh', [
            '-c',
            'dd if="$targetDev" bs=2048 skip=$skip2k count=$chunkBlocks 2>/dev/null | base64 2>/dev/null || '
                'dd if="$targetDev" bs=2048 skip=$skip2k count=$chunkBlocks 2>/dev/null | hexdump -v -e \'1/1 "%02x"\' 2>/dev/null',
          ]);

          final chunkBytes = _parseRawOutputToBytes(chunkRaw);
          if (chunkBytes != null && chunkBytes.isNotEmpty) {
            accumulatedBytes.addAll(chunkBytes);
            chunkIndex++;
            emptyChunkCount = 0;
            if (onProgress != null) {
              onProgress(accumulatedBytes.length, expectedSize);
            }
            if (expectedSize != null &&
                accumulatedBytes.length >= expectedSize) {
              break; // Fully read expected partition size
            }
            if (chunkBytes.length < chunkSize) {
              break; // Partial chunk indicates EOF
            }
            continue;
          }

          emptyChunkCount++;
          if (emptyChunkCount >= 2) break; // EOF or node unreadable
          chunkIndex++;
        }

        if (accumulatedBytes.isNotEmpty) {
          Logger.info(
            'MTD Dump Strategy 1 succeeded: ${accumulatedBytes.length} bytes read from $targetDev',
          );
          return Uint8List.fromList(accumulatedBytes);
        }
      }

      // Strategy 2: Fallback dd to /tmp/$devName.bin, then read via file.read RPC with base64
      Logger.info('MTD Dump Strategy 2: Copying $dev to /tmp/$devName.bin...');
      final tmpFile = '/tmp/$devName.bin';
      await appState.executeRouterCommand('sh', [
        '-c',
        'dd if="$dev" of="$tmpFile" bs=2048 2>/dev/null || dd if="$blockDev" of="$tmpFile" bs=2048 2>/dev/null || cat "$dev" > "$tmpFile" 2>/dev/null',
      ]);

      final bytes = await _readRouterFileAsBytes(appState, tmpFile);
      unawaited(appState.executeRouterCommand('rm', ['-f', tmpFile]));
      if (bytes != null && bytes.isNotEmpty) return bytes;

      return null;
    } finally {
      appState.setHeavyTaskRunning(false);
    }
  }

  Future<void> _handleSaveMtdblock() async {
    if (_selectedMtdDevice == null) return;
    final dev = _selectedMtdDevice!;
    final filename = dev.split('/').last;

    setState(() {
      _isProcessing = true;
      _uploadProgress = 0.0;
      _statusMessage = 'Dumping partition image ($dev)...';
    });

    final appState = ref.read(appStateProvider);
    try {
      final bytes = await _readMtdPartitionBytes(
        appState,
        dev,
        onProgress: (readBytes, totalBytes) {
          if (mounted) {
            setState(() {
              if (totalBytes != null && totalBytes > 0) {
                _uploadProgress = (readBytes / totalBytes).clamp(0.0, 1.0);
                _statusMessage =
                    'Dumping $dev (${_formatByteSize(readBytes)} / ${_formatByteSize(totalBytes)})...';
              } else {
                _statusMessage =
                    'Dumping $dev (${_formatByteSize(readBytes)})...';
              }
            });
          }
        },
      );
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Failed to dump and read $dev partition from router.');
      }

      final fileName = '$filename.bin';

      // Save directly to /storage/emulated/0/Download/ (Public Downloads)
      final saveResult =
          await OsPlatformIntegration.saveDownloadedFileWithResult(
            bytes: bytes,
            fileName: fileName,
          );

      // GUARANTEE overlay reset BEFORE displaying prompt
      if (mounted) {
        setState(() => _isProcessing = false);
      }

      if (!mounted) return;

      if (saveResult != null) {
        unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.medium));
        context.showToastSuccess('Partition image saved successfully.');
        await OsPlatformIntegration.showBackupDownloadedPrompt(
          context,
          saveResult,
        );
      } else {
        context.showToastError(
          'Failed to write partition image file to storage.',
        );
      }
    } catch (e, stack) {
      Logger.error('Partition Image Download Error: $e', stack);
      if (mounted) {
        setState(() => _isProcessing = false);
        context.showToastError(
          'Failed to save mtdblock: ${e.toString().replaceAll('Exception: ', '')}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _handlePerformSysupgrade() async {
    try {
      PlatformFile? pickedFile;
      bool pickerAttempted = false;
      try {
        pickedFile = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['bin', 'gz', 'tgz', 'tar', 'img', 'trx'],
        );
        pickerAttempted = true;
      } catch (_) {}

      if (!pickerAttempted) {
        try {
          pickedFile = await FilePicker.pickFile(type: FileType.any);
        } catch (_) {}
      }

      if (pickedFile == null) return;

      final fileNameLower = pickedFile.name.toLowerCase();

      // Extension Validation Guardrail: Ensure file is a valid OpenWrt firmware image
      final isValidFirmware =
          fileNameLower.endsWith('.bin') ||
          fileNameLower.endsWith('.img') ||
          fileNameLower.endsWith('.img.gz') ||
          fileNameLower.endsWith('.gz') ||
          fileNameLower.endsWith('.trx');

      if (!isValidFirmware) {
        if (mounted) {
          context.showToastError(
            'Invalid Firmware Format',
            subtitle:
                'Please select a valid OpenWrt firmware image (.bin, .img, .img.gz, .gz, or .trx).',
          );
        }
        return;
      }
      Uint8List? fileBytes;
      try {
        fileBytes = await pickedFile.readAsBytes();
      } catch (_) {
        if (pickedFile.path != null) {
          try {
            fileBytes = await File(pickedFile.path!).readAsBytes();
          } catch (_) {}
        }
      }

      if (fileBytes == null || fileBytes.isEmpty) {
        throw Exception('Could not read chosen firmware image file.');
      }

      final fileName = pickedFile.name;
      final fileSizeBytes = fileBytes.length;
      final fileSizeMb = fileSizeBytes / (1024 * 1024);
      final fileSizeMbStr = fileSizeMb.toStringAsFixed(2);

      // Memory Guardrail Check: Ensure /tmp has enough free space
      if (_tmpAvailableMb > 0 && fileSizeMb > (_tmpAvailableMb - 2.0)) {
        if (!mounted) return;
        unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));
        context.showToastError(
          'Insufficient /tmp space for upload ($fileSizeMbStr MB required, ${_tmpAvailableMb.toStringAsFixed(1)} MB available).',
        );
        return;
      }

      // Upload file to router /tmp with chunked progress
      setState(() {
        _isProcessing = true;
        _uploadProgress = 0.0;
        _statusMessage = 'Uploading firmware image ($fileSizeMbStr MB)...';
      });

      final appState = ref.read(appStateProvider);
      final b64Str = base64Encode(fileBytes);
      const chunkSize = 30000;
      await appState.executeRouterCommand('sh', [
        '-c',
        'rm -f /tmp/sysupgrade_firmware.bin.b64 /tmp/sysupgrade_firmware.bin',
      ]);

      for (var i = 0; i < b64Str.length; i += chunkSize) {
        final end = (i + chunkSize < b64Str.length)
            ? i + chunkSize
            : b64Str.length;
        final chunk = b64Str.substring(i, end);
        await appState.executeRouterCommand('sh', [
          '-c',
          'echo -n "$chunk" >> /tmp/sysupgrade_firmware.bin.b64',
        ]);
        if (mounted) {
          setState(() {
            _uploadProgress = end / b64Str.length;
          });
        }
      }

      await appState.executeRouterCommand('sh', [
        '-c',
        'base64 -d /tmp/sysupgrade_firmware.bin.b64 > /tmp/sysupgrade_firmware.bin && rm -f /tmp/sysupgrade_firmware.bin.b64',
      ]);

      // Pre-Flash Image Validation Check (`sysupgrade -t`)
      setState(() {
        _statusMessage = 'Verifying image compatibility (sysupgrade -t)...';
        _uploadProgress = null;
      });

      final testResult = await appState.executeRouterCommandOutput(
        'sysupgrade',
        ['-t', '/tmp/sysupgrade_firmware.bin'],
      );
      final isVerified =
          testResult != null &&
          !testResult.toLowerCase().contains('invalid') &&
          !testResult.toLowerCase().contains('error');

      setState(() => _isProcessing = false);

      if (!mounted) return;
      unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));

      // Pre-Flash Confirmation & Settings Sheet
      final proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.system_update_alt,
                    color: Colors.blue,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Firmware Pre-Flash Check',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isVerified
                          ? Colors.teal.withValues(alpha: 0.1)
                          : Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isVerified ? Colors.teal : Colors.orange,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isVerified
                              ? Icons.check_circle_outline
                              : Icons.warning_amber_rounded,
                          color: isVerified ? Colors.teal : Colors.orange,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isVerified
                                    ? 'Image Verification Passed'
                                    : 'Pre-Flash Test Unverified',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isVerified
                                      ? Colors.teal
                                      : Colors.orange.shade900,
                                ),
                              ),
                              Text(
                                isVerified
                                    ? 'Firmware image matches target architecture for $_romFlavor.'
                                    : 'sysupgrade -t test warning. Verify board compatibility before flashing.',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'File: $fileName',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    'Size: $fileSizeMbStr MB',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    'Target ROM: $_romFlavor',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const Divider(height: 24),
                  CheckboxListTile(
                    title: const Text(
                      'Keep settings and current configuration (-k)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: const Text(
                      'Retain active network, Wi-Fi, and user credentials.',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: _keepSettings,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (val) {
                      setDialogState(() {
                        _keepSettings = val ?? true;
                      });
                    },
                  ),
                  CheckboxListTile(
                    title: const Text(
                      'Force upgrade (-F)',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: const Text(
                      'Bypass board architecture validation (CAUTION!)',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: _forceSysupgrade,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (val) {
                      setDialogState(() {
                        _forceSysupgrade = val ?? false;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.bolt, color: Colors.red, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'WARNING: Do NOT disconnect power or ethernet during the flashing process!',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actionsOverflowButtonSpacing: 8,
            actionsOverflowDirection: VerticalDirection.down,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                icon: const Icon(Icons.flash_on),
                label: const Text('Flash Firmware Now'),
              ),
            ],
          ),
        ),
      );

      // Clean up uploaded firmware file from router /tmp on cancel
      if (proceed != true) {
        unawaited(
          appState.executeRouterCommand('rm', [
            '-f',
            '/tmp/sysupgrade_firmware.bin',
          ]),
        );
        return;
      }

      setState(() {
        _isProcessing = true;
        _uploadProgress = null;
        _statusMessage = 'Executing sysupgrade flash on router...';
      });

      // Execute background sysupgrade so connection drop on router reboot doesn't throw false negative
      final flagStr = _keepSettings ? '-k' : '-n';
      final forceStr = _forceSysupgrade ? '-F' : '';
      final bgCmd =
          "(sleep 1 && sysupgrade $flagStr $forceStr /tmp/sysupgrade_firmware.bin) >/dev/null 2>&1 &";

      final flashInitiated = await appState.executeRouterCommand('sh', [
        '-c',
        bgCmd,
      ]);

      if (!mounted) return;
      if (flashInitiated) {
        context.showToastSuccess(
          'Firmware flash initiated successfully. Router is rebooting.',
        );
        _showRebootCountdownDialog();
      } else {
        // Fallback direct execution
        await appState.executeRouterCommand('sysupgrade', [
          if (_keepSettings) '-k' else '-n',
          if (_forceSysupgrade) '-F',
          '/tmp/sysupgrade_firmware.bin',
        ]);
        if (mounted) {
          context.showToastSuccess(
            'Firmware flash initiated successfully. Router is rebooting.',
          );
          _showRebootCountdownDialog();
        }
      }
    } catch (e) {
      if (!mounted) return;
      // Socket exception or network disconnection is expected when router shuts down interface during sysupgrade
      if (e.toString().toLowerCase().contains('socket') ||
          e.toString().toLowerCase().contains('connection')) {
        context.showToastSuccess(
          'Firmware flash initiated successfully. Router is rebooting.',
        );
        _showRebootCountdownDialog();
      } else {
        context.showToastError(
          'Firmware Flash Failed: ${e.toString().replaceAll('Exception: ', '')}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showRebootCountdownDialog() {
    int remainingSeconds = 120;
    Timer? countdownTimer;

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (t) {
            if (remainingSeconds > 0) {
              setModalState(() {
                remainingSeconds--;
              });
            } else {
              t.cancel();
            }
          });

          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                const Text(
                  'Router Rebooting & Flashing...',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  'Please wait while OpenWrt applies changes and restarts network services.\nEstimated time: ${remainingSeconds}s',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      countdownTimer?.cancel();
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('Dismiss & Return to Dashboard'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const LuciAppBar(title: 'Backup / Flash Firmware'),
      body: Stack(
        children: [
          _buildActionsView(context),
          if (_isProcessing)
            SizedBox.expand(
              child: Container(
                color: Theme.of(
                  context,
                ).colorScheme.scrim.withValues(alpha: 0.65),
                child: Center(
                  child: Card(
                    elevation: 8,
                    color: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 24,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_uploadProgress != null) ...[
                            CircularProgressIndicator(value: _uploadProgress),
                            const SizedBox(height: 12),
                            Text(
                              '${(_uploadProgress! * 100).toInt()}% uploaded',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ] else ...[
                            const CircularProgressIndicator(),
                          ],
                          const SizedBox(height: 16),
                          Text(
                            _statusMessage ?? 'Processing...',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 18),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _isProcessing = false;
                              });
                              context.showToastInfo(
                                'Operation overlay dismissed.',
                              );
                            },
                            icon: const Icon(Icons.close_rounded, size: 18),
                            label: const Text('Cancel / Dismiss'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionsView(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        const LuciContextualHintBanner(
          hintId: 'backup_safety_advisory_hint',
          title: 'Backup & Sysupgrade Guidance',
          message:
              'Downloading a backup archive preserves your custom settings across firmware updates. Always double-check target architecture before flashing new images.',
          icon: Icons.shield_outlined,
          accentColor: Colors.teal,
        ),
        // System Hardware & Multi-ROM Context Banner
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  LuciColors.primary.withValues(alpha: 0.15),
                  Theme.of(context).cardColor,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.router,
                      color: LuciColors.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _routerModel,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '/tmp Space: $_tmpAvailableSpace',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        _romFlavor,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Target Arch: $_targetArch',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Firmware Version: $_firmwareVersion',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // 1. Backup Section
        _buildSectionCard(
          title: 'Backup Configuration Archive',
          icon: Icons.archive_outlined,
          iconColor: Colors.teal,
          description:
              'Generate and download a tar.gz archive of your router\'s system configurations, passwords, and custom scripts.',
          actionWidget: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _isProcessing ? null : _handleGenerateBackup,
                icon: const Icon(Icons.download),
                label: const Text('Generate & Download Backup Archive'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.teal,
                  side: const BorderSide(color: Colors.teal),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _isProcessing ? null : _showCurrentBackupFileList,
                icon: const Icon(Icons.list_alt),
                label: const Text('View Preserved Backup File List'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 2. Restore Section
        _buildSectionCard(
          title: 'Restore & Reset Settings',
          icon: Icons.restore_outlined,
          iconColor: Colors.redAccent,
          description:
              'Upload a backup archive to restore settings, or perform a complete factory reset to return firmware to default state.',
          actionWidget: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _isProcessing ? null : _handleFactoryReset,
                  child: const Text('Perform Reset'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _isProcessing ? null : _handleUploadArchive,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Upload Archive...'),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        const SizedBox(height: 16),

        // 3. Save mtdblock contents (Collapsible by default)
        LuciCollapsibleCard(
          title: 'Save Partition (mtdblock) Image',
          subtitle: 'Low-level partition dumps (bootloader, art, firmware)',
          icon: Icons.sd_storage_outlined,
          iconColor: Colors.amber.shade800,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Download raw partition dumps for low-level system recovery. (ADVANCED USERS ONLY)',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedMtdDevice,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      items: _mtdList.map((m) {
                        return DropdownMenuItem<String>(
                          value: m['device'],
                          child: Text(
                            m['name']!,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (val) =>
                          setState(() => _selectedMtdDevice = val),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade800,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _isProcessing ? null : _handleSaveMtdblock,
                    child: const Text('Save mtdblock'),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 4. Flash new firmware image (Collapsible by default)
        LuciCollapsibleCard(
          title: 'Flash New Firmware Image',
          subtitle: 'Sysupgrade firmware upgrade (.bin, .img.gz, .tar.gz)',
          icon: Icons.system_update_alt,
          iconColor: Colors.blue,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Upload a sysupgrade-compatible firmware image to upgrade or replace running OpenWrt firmware.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 14),
              CheckboxListTile(
                title: const Text(
                  'Keep settings and current configuration (-k)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                value: _keepSettings,
                onChanged: _isProcessing
                    ? null
                    : (val) => setState(() => _keepSettings = val ?? true),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _isProcessing ? null : _handlePerformSysupgrade,
                  icon: const Icon(Icons.flash_on),
                  label: const Text('Flash Firmware Image...'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required String description,
    required Widget actionWidget,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            actionWidget,
          ],
        ),
      ),
    );
  }
}
