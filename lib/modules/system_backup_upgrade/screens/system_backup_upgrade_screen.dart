// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../../../main.dart';
import '../../../state/app_state.dart';
import '../../../design/luci_design_system.dart';
import '../../../utils/os_platform_integration.dart';
import '../../../widgets/luci_app_bar.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import '../../../utils/logger.dart';
import '../../../widgets/luci_contextual_hint_banner.dart';
import '../../../widgets/luci_collapsible_card.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import '../widgets/preserved_backup_files_sheet.dart';
import 'package:dio/dio.dart';
import '../../../utils/sha256.dart';
import '../models/router_upgrade_scan.dart';
import '../models/upgrade_models.dart';
import '../services/router_upgrade_scan_service.dart';
import '../services/firmware_upgrade_checker.dart';
import '../services/upgrade_readiness_assessor.dart';
import '../services/preservation_impact_analyzer.dart';

class SystemBackupUpgradeScreen extends ConsumerStatefulWidget {
  const SystemBackupUpgradeScreen({super.key});

  @override
  ConsumerState<SystemBackupUpgradeScreen> createState() =>
      _SystemBackupUpgradeScreenState();
}

class _SystemBackupUpgradeScreenState
    extends ConsumerState<SystemBackupUpgradeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _keepSettings = true;
  bool _forceSysupgrade = false;
  bool _isProcessing = false;

  /// Prevents double-tap from submitting the flash command twice.
  bool _flashStarted = false;
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

  // ── Upgrade Center state ──────────────────────────────────────────────────

  /// The most recent router upgrade scan result.
  RouterUpgradeScan? _upgradeScan;

  /// Whether a scan is currently in progress.
  bool _scanInProgress = false;

  /// Whether the user has generated a backup in this session.
  bool _backupGeneratedInSession = false;

  /// Firmware upgrade availability check result.
  FirmwareUpgradeAvailability? _upgradeAvailability;

  /// Whether a firmware upgrade check is running.
  bool _upgradeCheckInProgress = false;

  /// Readiness report (computed after image selection and scan).
  UpgradeReadinessReport? _readinessReport;

  /// Preservation impact inventory.
  PreservationImpactInventory? _preservationInventory;

  /// Package migration analysis.
  PackageMigrationAnalysis? _migrationAnalysis;

  /// The last selected firmware image validation result.
  FirmwareImageValidationResult _imageValidation =
      const FirmwareImageValidationResult(status: ImageValidationStatus.notRun);

  String _preservationFilter = '';
  bool _isPreservedFilesExpanded = false;

  String _resolveTmpSpace(AppLocalizations? l10n) {
    if (_tmpAvailableSpace == 'Checking space...') {
      return l10n?.statusCheckingSpace ?? 'Checking space...';
    }
    if (_tmpAvailableSpace == 'Available') {
      return l10n?.statusAvailableFallback ?? 'Available';
    }
    return _tmpAvailableSpace;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadRouterSysInfo();
    _loadMtdBlocks();
    _performUpgradeScan();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRouterSysInfo() async {
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final sysauth = appState.sysauth;
    final api = appState.apiService;

    // Strategy 1: Use ubus system.board and system.info (standard across all OpenWrt releases)
    if (router != null && sysauth != null && api != null) {
      try {
        final boardRes = await api.call(
          router.ipAddress,
          sysauth,
          router.useHttps,
          object: 'system',
          method: 'board',
        );
        Map<String, dynamic>? board;
        if (boardRes is List && boardRes.length > 1 && boardRes[0] == 0) {
          board = boardRes[1] as Map<String, dynamic>?;
        } else if (boardRes is Map<String, dynamic>) {
          board = boardRes;
        }

        final infoRes = await api.call(
          router.ipAddress,
          sysauth,
          router.useHttps,
          object: 'system',
          method: 'info',
        );
        Map<String, dynamic>? info;
        if (infoRes is List && infoRes.length > 1 && infoRes[0] == 0) {
          info = infoRes[1] as Map<String, dynamic>?;
        } else if (infoRes is Map<String, dynamic>) {
          info = infoRes;
        }

        if (board != null) {
          final rel = board['release'] as Map?;
          final model = board['model']?.toString();
          final boardName = board['board_name']?.toString();
          final target = rel?['target']?.toString();
          final desc = rel?['description']?.toString();
          final dist = rel?['distribution']?.toString() ?? 'OpenWrt';

          double freeMb = 64.0;
          String freeTmpLabel = 'Available';
          if (info != null && info['tmp'] is Map) {
            final tmp = info['tmp'] as Map;
            final freeKb = (tmp['avail'] ?? tmp['free']) as num?;
            if (freeKb != null) {
              freeMb = freeKb / 1024.0;
              freeTmpLabel = '${freeMb.toStringAsFixed(1)} MB';
            }
          }

          if (mounted) {
            setState(() {
              if (model != null && model.isNotEmpty) _routerModel = model;
              if (target != null && target.isNotEmpty) {
                _targetArch = target;
              } else if (boardName != null && boardName.isNotEmpty) {
                _targetArch = boardName;
              }
              if (desc != null && desc.isNotEmpty) {
                _firmwareVersion = desc;
              } else if (rel?['version'] != null) {
                _firmwareVersion = '$dist ${rel!['version']}';
              }
              _romFlavor = dist;
              _tmpAvailableSpace = freeTmpLabel;
              _tmpAvailableMb = freeMb;
            });
            return;
          }
        }
      } catch (e) {
        Logger.warning(
          'SystemBackupUpgradeScreen: ubus sysinfo load failed: $e',
        );
      }
    }

    // Strategy 2: Command execution fallback for legacy or custom environments
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
    final router = appState.selectedRouter;
    final sysauth = appState.sysauth;
    final api = appState.apiService;

    try {
      String? mtdOutput;
      // 1. Try ubus file.read on /proc/mtd (allowed in standard rpcd ACL)
      if (router != null && sysauth != null && api != null) {
        try {
          final res = await api.call(
            router.ipAddress,
            sysauth,
            router.useHttps,
            object: 'file',
            method: 'read',
            params: {'path': '/proc/mtd'},
          );
          if (res is List && res.length > 1 && res[0] == 0) {
            final data = res[1];
            if (data is Map && data['data'] != null) {
              mtdOutput = data['data'].toString();
            }
          }
        } catch (_) {}
      }

      // 2. Command execution fallback
      mtdOutput ??= await appState.executeRouterCommandOutput('cat', [
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

    // No MTD partitions detected — leave _mtdList empty.
    // We do NOT fall back to a hardcoded list of fictitious partitions.
    if (mounted) {
      setState(() {
        _mtdList = [];
        _selectedMtdDevice = null;
      });
    }
  }

  /// Perform a full router upgrade scan using [RouterUpgradeScanService].
  ///
  /// All probe failures are represented as [DetectedValue.unknown]; no
  /// fabricated values are substituted.
  Future<void> _performUpgradeScan() async {
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final sysauth = appState.sysauth;
    if (router == null || sysauth == null) return;

    if (mounted) setState(() => _scanInProgress = true);

    try {
      final api = appState.apiService;
      if (api == null) {
        Logger.warning(
          'SystemBackupUpgradeScreen: apiService is null, cannot scan',
        );
        return;
      }
      final scanService = RouterUpgradeScanService(
        apiService: api,
        ipAddress: router.ipAddress,
        sysauth: sysauth,
        useHttps: router.useHttps,
      );
      final scan = await scanService.scan();

      if (!mounted) return;

      // Build preservation impact and migration analysis from scan results
      final analyzer = PreservationImpactAnalyzer(
        apiService: api,
        ipAddress: router.ipAddress,
        sysauth: sysauth,
        useHttps: router.useHttps,
      );
      final inventory = await analyzer.analyze(scan);
      // Package migration analysis is only initialized when an OPKG router is
      // upgrading to an APK-based target firmware (e.g. OpenWrt 25.12+).
      // For APK routers or before an update is checked, keep migration null.
      final report = const UpgradeReadinessAssessor().assess(
        scan: scan,
        imageFileName: null,
        imageSizeBytes: null,
        imageValidation: _imageValidation,
        keepSettings: _keepSettings,
        forceUpgrade: _forceSysupgrade,
        backupWasGenerated: _backupGeneratedInSession,
      );
      setState(() {
        _upgradeScan = scan;
        _preservationInventory = inventory;
        _migrationAnalysis = null;
        _readinessReport = report;

        // Keep top header in sync with scan data
        if (scan.modelName.isKnown && scan.modelName.value != null) {
          _routerModel = scan.modelName.value!;
        }
        if (scan.distribTarget.isKnown && scan.distribTarget.value != null) {
          _targetArch = scan.distribTarget.value!;
        } else if (scan.boardName.isKnown && scan.boardName.value != null) {
          _targetArch = scan.boardName.value!;
        }
        if (scan.distribDescription.isKnown &&
            scan.distribDescription.value != null) {
          _firmwareVersion = scan.distribDescription.value!;
        } else if (scan.distribRelease.isKnown &&
            scan.distribRelease.value != null) {
          _firmwareVersion = 'OpenWrt ${scan.distribRelease.value}';
        }
        if (scan.firmwareFamilyLabel.isKnown &&
            scan.firmwareFamilyLabel.value != null) {
          _romFlavor = scan.firmwareFamilyLabel.value!;
        }
        if (scan.tmpAvailableBytes.isKnown &&
            scan.tmpAvailableBytes.value != null) {
          final mb = scan.tmpAvailableBytes.value! / (1024 * 1024);
          _tmpAvailableMb = mb;
          _tmpAvailableSpace = '${mb.toStringAsFixed(1)} MB';
        }
      });

      Logger.info(
        'SystemBackupUpgradeScreen: Upgrade scan completed. '
        'Model=${scan.modelName.value}, '
        'Family=${scan.firmwareFamily.value?.name}, '
        'PkgMgr=${scan.packageManager.value?.name}',
      );
    } catch (e, stack) {
      Logger.error('SystemBackupUpgradeScreen: Upgrade scan failed: $e', stack);
    } finally {
      if (mounted) setState(() => _scanInProgress = false);
    }
  }

  /// Check firmware upgrade availability using the current scan.
  Future<void> _checkForUpgrades() async {
    final scan = _upgradeScan;
    if (scan == null) {
      context.showToastWarning(
        'Router scan is still in progress. Please wait and try again.',
      );
      return;
    }

    if (mounted) setState(() => _upgradeCheckInProgress = true);
    try {
      const checker = FirmwareUpgradeChecker();
      final result = await checker.check(scan);
      if (mounted) {
        setState(() {
          _upgradeAvailability = result;
          // If router is currently OPKG and the available upgrade is OpenWrt 25.12+,
          // analyze migration to APK.
          if (scan.packageManager.value == RouterPackageManager.opkg &&
              result.isUpgradeAvailable &&
              result.latestVersion != null) {
            final branchStr = result.latestVersion!
                .split('.')
                .take(2)
                .join('.');
            final branch = double.tryParse(branchStr) ?? 0;
            if (branch >= 25.12) {
              _migrationAnalysis = PreservationImpactAnalyzer.analyzeMigration(
                currentEngine: RouterPackageManager.opkg,
                targetEngine: RouterPackageManager.apk,
                installedPackages: const [],
              );
            } else {
              _migrationAnalysis = null;
            }
          } else {
            _migrationAnalysis = null;
          }
        });
      }
    } catch (e) {
      Logger.error('FirmwareUpgradeChecker error: $e');
    } finally {
      if (mounted) setState(() => _upgradeCheckInProgress = false);
    }
  }

  Future<void> _showCurrentBackupFileList() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _isProcessing = true;
      _statusMessage =
          l10n?.backupStatusFetchingPreserved ??
          'Fetching preserved backup files list...';
    });

    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final sysauth = appState.sysauth;
    final api = appState.apiService;

    String? fileList;
    String? confContent;

    // 1. Try ubus file.exec /sbin/sysupgrade --list-backup (allowed in modern rpcd ACL)
    if (router != null && sysauth != null && api != null) {
      try {
        final res = await api.call(
          router.ipAddress,
          sysauth,
          router.useHttps,
          object: 'file',
          method: 'exec',
          params: {
            'command': '/sbin/sysupgrade',
            'params': ['--list-backup'],
          },
        );
        if (res is List && res.length > 1 && res[0] == 0) {
          final data = res[1];
          if (data is Map && data['stdout'] != null) {
            fileList = data['stdout'].toString();
          }
        }
      } catch (_) {}

      // Try reading /etc/sysupgrade.conf via ubus
      try {
        final res = await api.call(
          router.ipAddress,
          sysauth,
          router.useHttps,
          object: 'file',
          method: 'read',
          params: {'path': '/etc/sysupgrade.conf'},
        );
        if (res is List && res.length > 1 && res[0] == 0) {
          final data = res[1];
          if (data is Map && data['data'] != null) {
            confContent = data['data'].toString();
          }
        }
      } catch (_) {}
    }

    if (fileList == null || fileList.trim().isEmpty) {
      fileList = await appState.executeRouterCommandOutput('sh', [
        '-c',
        'sysupgrade -l',
      ]);
    }
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

    confContent ??= await appState.executeRouterCommandOutput('cat', [
      '/etc/sysupgrade.conf',
    ]);

    if (!mounted) return;
    setState(() => _isProcessing = false);

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
    // Strategy 0: Native LuCI RPC file.read with base64 & maxsize (100% ubus ACL compliant, 0 shell processes)
    try {
      final res = await appState.callRpc('file', 'read', {
        'path': filePath,
        'base64': true,
        'maxsize':
            10 * 1024 * 1024, // Read up to 10 MB in a single RPC roundtrip
      });

      final dataStr = _extractDataStringFromRpcResult(res);
      final chunkBytes = _parseRawOutputToBytes(dataStr);
      if (chunkBytes != null && chunkBytes.isNotEmpty) {
        Logger.info(
          'Read $filePath via file.read RPC: ${chunkBytes.length} bytes',
        );
        return chunkBytes;
      }
    } catch (e) {
      Logger.warning('Strategy 0 file.read RPC failed for $filePath: $e');
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

    // The official OpenWrt/LuCI standard backup endpoint is /cgi-bin/cgi-backup.
    // It accepts a POST with application/x-www-form-urlencoded sessionid=<sysauth>
    // and streams the complete configuration tar.gz archive directly.
    final candidateUrls = [
      '$scheme://$ip/cgi-bin/cgi-backup',
      '$scheme://$ip/cgi-backup',
      '$scheme://$ip/luci/cgi-bin/cgi-backup',
      '$scheme://$ip/cgi-bin/luci/admin/system/flashops/backup',
      '$scheme://$ip/cgi-bin/luci/;stok=$sysauth/admin/system/backup',
      '$scheme://$ip/cgi-bin/luci/;stok=$sysauth/admin/system/flashops/backup',
    ];

    final bodyStr = 'sessionid=${Uri.encodeQueryComponent(sysauth)}';
    final bodyBytes = utf8.encode(bodyStr);

    for (final urlStr in candidateUrls) {
      // 1. Try POST with application/x-www-form-urlencoded and explicit Content-Length (Native LuCI cgi-backup protocol)
      try {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => true;
        client.connectionTimeout = const Duration(seconds: 5);
        try {
          final request = await client.postUrl(Uri.parse(urlStr));
          request.headers.contentType = ContentType(
            'application',
            'x-www-form-urlencoded',
          );
          request.headers.add(
            'Cookie',
            'sysauth=$sysauth; sysauth_http=$sysauth; sysauth_https=$sysauth',
          );
          request.headers.add(
            'User-Agent',
            'Mozilla/5.0 (YALA OpenWrt Manager)',
          );
          // Explicit Content-Length is required by cgi-io postdecode to avoid 400 Invalid form data
          request.contentLength = bodyBytes.length;
          request.add(bodyBytes);

          final response = await request.close().timeout(
            const Duration(seconds: 15),
          );
          if (response.statusCode == 200) {
            final chunks = <int>[];
            await for (final chunk in response) {
              chunks.addAll(chunk);
            }
            final resBytes = Uint8List.fromList(chunks);
            if (resBytes.isNotEmpty && _validateBackupArchiveBytes(resBytes)) {
              Logger.info(
                'Successfully downloaded backup archive via HTTP POST to $urlStr (${resBytes.length} bytes)',
              );
              return resBytes;
            }
          }
        } finally {
          client.close(force: true);
        }
      } catch (e) {
        Logger.debug('POST backup request to $urlStr failed: $e');
      }

      // 2. Try GET request fallback for older LuCI versions
      try {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => true;
        client.connectionTimeout = const Duration(seconds: 4);
        try {
          final request = await client.getUrl(Uri.parse(urlStr));
          request.headers.add(
            'Cookie',
            'sysauth=$sysauth; sysauth_http=$sysauth; sysauth_https=$sysauth',
          );
          request.headers.add(
            'User-Agent',
            'Mozilla/5.0 (YALA OpenWrt Manager)',
          );
          final response = await request.close().timeout(
            const Duration(seconds: 10),
          );
          if (response.statusCode == 200) {
            final chunks = <int>[];
            await for (final chunk in response) {
              chunks.addAll(chunk);
            }
            final resBytes = Uint8List.fromList(chunks);
            if (resBytes.isNotEmpty && _validateBackupArchiveBytes(resBytes)) {
              Logger.info(
                'Successfully downloaded backup archive via HTTP GET to $urlStr (${resBytes.length} bytes)',
              );
              return resBytes;
            }
          }
        } finally {
          client.close(force: true);
        }
      } catch (e) {
        Logger.debug('GET backup request to $urlStr failed: $e');
      }
    }
    return null;
  }

  Future<void> _handleGenerateBackup() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _isProcessing = true;
      _uploadProgress = null;
      _statusMessage =
          l10n?.backupStatusGenerating ??
          'Generating configuration backup on router...';
    });

    final appState = ref.read(appStateProvider);
    try {
      Uint8List? bytes;

      // Strategy 1: Native OpenWrt / LuCI cgi-backup HTTP Endpoint (Instant, 0 shell execution, official standard)
      Logger.info(
        'Backup Strategy 1: Downloading via LuCI cgi-backup HTTP endpoint...',
      );
      bytes = await _downloadBackupViaHttp(appState);
      if (bytes != null && bytes.isNotEmpty) {
        if (_validateBackupArchiveBytes(bytes)) {
          Logger.info(
            'Backup Strategy 1 (LuCI cgi-backup) succeeded: ${bytes.length} bytes downloaded',
          );
        } else {
          Logger.warning(
            'Backup Strategy 1 returned invalid archive bytes, falling back...',
          );
          bytes = null;
        }
      }

      // Strategy 2: Create backup archive on router & read via RPC/file
      if (bytes == null || bytes.isEmpty) {
        Logger.info(
          'Backup Strategy 2: Creating /tmp/app_backup.tar.gz and reading via RPC/file...',
        );
        setState(() {
          _statusMessage =
              l10n?.backupStatusGenerating ??
              'Generating configuration backup on router...';
        });

        await appState.executeRouterCommand('sh', [
          '-c',
          'sysupgrade -b /tmp/app_backup.tar.gz 2>/dev/null || tar -czf /tmp/app_backup.tar.gz -C / etc/config etc/passwd etc/shadow etc/dropbear etc/uhttpd etc/dnsmasq.conf etc/sysupgrade.conf etc/uci-defaults 2>/dev/null',
        ]);

        bytes = await _readRouterFileAsBytes(
          appState,
          '/tmp/app_backup.tar.gz',
        );
        unawaited(
          appState.executeRouterCommand('rm', ['-f', '/tmp/app_backup.tar.gz']),
        );

        if (bytes != null && bytes.isNotEmpty) {
          if (_validateBackupArchiveBytes(bytes)) {
            Logger.info(
              'Backup Strategy 2 succeeded: ${bytes.length} bytes downloaded',
            );
          } else {
            Logger.warning(
              'Backup Strategy 2 generated invalid payload, falling back...',
            );
            bytes = null;
          }
        }
      }

      // Strategy 3: Direct single-command stream to Base64 (sysupgrade -b - | base64)
      if (bytes == null || bytes.isEmpty) {
        Logger.info('Backup Strategy 3: Single-command stream to base64...');
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
                'Backup Strategy 3 succeeded: ${bytes.length} bytes downloaded',
              );
            }
          } catch (e) {
            Logger.warning('Backup Strategy 3 decode error: $e');
          }
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

      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final routerName =
          (appState.selectedRouter?.name ??
                  appState.selectedRouter?.ipAddress ??
                  'openwrt')
              .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final isArchive = _validateBackupArchiveBytes(bytes);
      final extension = isArchive
          ? 'tar.gz'
          : (bytes.isNotEmpty && bytes[0] == 0x7B ? 'json' : 'uci');
      final fileName = 'backup-$routerName-$dateStr.$extension';

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
        if (mounted) setState(() => _backupGeneratedInSession = true);
        context.showToastSuccess(
          l10n?.backupDownloadedSuccess ??
              'Backup archive downloaded successfully.',
        );
        await OsPlatformIntegration.showBackupDownloadedPrompt(
          context,
          saveResult,
        );
      } else {
        context.showToastError(
          l10n?.backupWriteFailed ?? 'Failed to write backup file to storage.',
          subtitle: 'Please check app storage permissions or available space.',
        );
      }
    } catch (e, stack) {
      Logger.error('Backup Generation Error: $e', stack);
      if (mounted) {
        setState(() => _isProcessing = false);
        context.showToastError(
          'Backup Generation Failed',
          subtitle: LuciToastManager.parseErrorReason(e),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _flashStarted = false;
        });
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
    final l10n = AppLocalizations.of(context);
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
            l10n?.backupInvalidArchiveExt ?? 'Invalid Archive Extension',
            subtitle:
                l10n?.backupInvalidArchiveExtSubtitle ??
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
                l10n?.backupFileReadError ?? 'File Read Error',
                subtitle:
                    l10n?.backupFileReadErrorSubtitle ??
                    'Could not read selected file from storage.',
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
            l10n?.backupCorruptArchive ?? 'Corrupt or Invalid Archive Payload',
            subtitle:
                l10n?.backupCorruptArchiveSubtitle ??
                'The selected file is corrupt or not a valid gzipped tarball. Pre-restore validation aborted to prevent router configuration corruption.',
          );
        }
        return;
      }

      setState(() {
        _isProcessing = true;
        _uploadProgress = 0.0;
        _statusMessage =
            l10n?.backupStatusUploadingArchive ??
            'Uploading archive to router...';
      });

      final appState = ref.read(appStateProvider);
      final b64Str = base64Encode(fileBytes);

      const chunkSize = 8000;
      await appState.executeRouterCommand('sh', [
        '-c',
        'rm -f /tmp/backup.tar.gz.b64 /tmp/backup.tar.gz',
      ]);
      for (var i = 0; i < b64Str.length; i += chunkSize) {
        final end = (i + chunkSize < b64Str.length)
            ? i + chunkSize
            : b64Str.length;
        final chunk = b64Str.substring(i, end);
        await appState.executeRouterCommand('sh', [
          '-c',
          'echo -n "$chunk" >> /tmp/backup.tar.gz.b64',
        ]);
        if (mounted) {
          setState(() {
            _uploadProgress = end / b64Str.length;
          });
        }
      }

      await appState.executeRouterCommand('sh', [
        '-c',
        'base64 -d /tmp/backup.tar.gz.b64 > /tmp/backup.tar.gz 2>/dev/null || openssl base64 -d -in /tmp/backup.tar.gz.b64 -out /tmp/backup.tar.gz 2>/dev/null || uudecode -o /tmp/backup.tar.gz /tmp/backup.tar.gz.b64 2>/dev/null && rm -f /tmp/backup.tar.gz.b64',
      ]);

      setState(() {
        _statusMessage =
            l10n?.backupStatusRestoring ?? 'Restoring backup configuration...';
        _uploadProgress = null;
      });

      // Try official OpenWrt rpcd ACL-permitted command first: /sbin/sysupgrade --restore-backup /tmp/backup.tar.gz
      var restoreSuccess = await appState.executeRouterCommand('sysupgrade', [
        '--restore-backup',
        '/tmp/backup.tar.gz',
      ]);
      if (!restoreSuccess) {
        restoreSuccess = await appState.executeRouterCommand('sysupgrade', [
          '-r',
          '/tmp/backup.tar.gz',
        ]);
      }
      final fallbackSuccess = !restoreSuccess
          ? await appState.executeRouterCommand('tar', [
              '-xzf',
              '/tmp/backup.tar.gz',
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
          l10n?.backupRestoredSuccess ??
              'Configuration restored successfully from archive.',
        );
        _showPostRestoreRebootDialog();
      } else {
        context.showToastError(
          l10n?.backupRestoreFailed ??
              'Failed to restore backup configuration.',
          subtitle: 'Check router permissions or archive integrity.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      context.showToastError(
        'Archive Upload Failed',
        subtitle: LuciToastManager.parseErrorReason(e),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _flashStarted = false;
        });
      }
    }
  }

  void _showPostRestoreRebootDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          actionsOverflowButtonSpacing: 8,
          actionsOverflowDirection: VerticalDirection.down,
          title: Text(l10n?.backupRestoreComplete ?? 'Restore Complete'),
          content: SingleChildScrollView(
            child: Text(
              l10n?.backupRestoreCompleteContent ??
                  'Configuration files have been restored to the router.\n\n'
                      'Would you like to reboot the router now to ensure all restored daemons and network interfaces initialize cleanly?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n?.backupLaterBtn ?? 'Later'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(l10n?.backupRebootRouter ?? 'Reboot Router'),
              onPressed: () async {
                Navigator.pop(ctx);
                final appState = ref.read(appStateProvider);
                await appState.executeRouterCommand('reboot', []);
                if (mounted && context.mounted) {
                  context.showToastWarning('Rebooting router...');
                  _showRebootCountdownDialog();
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleFactoryReset() async {
    final l10n = AppLocalizations.of(context);
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
            Expanded(
              child: Text(
                l10n?.sysUpgradeResetConfirmTitle ?? 'Reset to Defaults?',
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            l10n?.sysUpgradeResetConfirmDesc ??
                'Are you sure you want to perform a factory reset? All user configurations, installed packages, and custom passwords will be permanently wiped.\n\nThe router will automatically reboot upon completion. Continue?',
            style: const TextStyle(fontSize: 14),
          ),
        ),
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n?.actionCancel ?? 'Cancel'),
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
            child: Text(l10n?.sysUpgradeBtnPerformReset ?? 'Perform Reset'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isProcessing = true;
      _uploadProgress = null;
      _statusMessage =
          l10n?.backupStatusFactoryReset ??
          'The system is erasing the configuration partition now and will reboot itself when finished.';
    });

    final appState = ref.read(appStateProvider);
    final success = await appState.executeRouterCommand('firstboot', [
      '-r',
      '-y',
    ]);

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (success) {
      context.showToastWarning(
        l10n?.sysUpgradeFactoryResetInitiated ??
            'Factory reset initiated. Router is now rebooting...',
      );
      _showRebootCountdownDialog(isFactoryReset: true);
    } else {
      context.showToastError(
        l10n?.sysUpgradeFactoryResetFailed ??
            'Failed to execute factory reset on router.',
        subtitle: 'Check router RPC permissions or system state.',
      );
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

      // Strategy 0: Native LuCI cgi-download HTTP endpoint (Instant streaming, 0 shell commands, 100% ACL compliant)
      final ip = appState.selectedRouter?.ipAddress;
      final sysauth = appState.sysauth;
      final useHttps = appState.selectedRouter?.useHttps ?? false;
      final scheme = useHttps ? 'https' : 'http';

      if (ip != null && sysauth != null) {
        for (final targetDev in candidates) {
          try {
            Logger.info(
              'MTD Dump Strategy 0 (Native LuCI cgi-download): $targetDev...',
            );
            final candidateUrls = [
              '$scheme://$ip/cgi-bin/cgi-download',
              '$scheme://$ip/cgi-download',
              '$scheme://$ip/luci/cgi-bin/cgi-download',
            ];
            final devBasename = targetDev.split('/').last;
            final postBody =
                'sessionid=${Uri.encodeQueryComponent(sysauth)}&path=${Uri.encodeQueryComponent(targetDev)}&filename=${Uri.encodeQueryComponent("$devBasename.bin")}&mimetype=application/octet-stream';
            final postBytes = utf8.encode(postBody);

            for (final urlStr in candidateUrls) {
              try {
                final client = HttpClient();
                client.badCertificateCallback = (cert, host, port) => true;
                client.connectionTimeout = const Duration(seconds: 5);
                try {
                  final request = await client.postUrl(Uri.parse(urlStr));
                  request.headers.contentType = ContentType(
                    'application',
                    'x-www-form-urlencoded',
                  );
                  request.headers.add(
                    'Cookie',
                    'sysauth=$sysauth; sysauth_http=$sysauth; sysauth_https=$sysauth',
                  );
                  request.headers.add(
                    'User-Agent',
                    'Mozilla/5.0 (YALA OpenWrt Manager)',
                  );
                  request.contentLength = postBytes.length;
                  request.add(postBytes);

                  final response = await request.close().timeout(
                    const Duration(seconds: 30),
                  );
                  if (response.statusCode == 200) {
                    final chunks = <int>[];
                    await for (final chunk in response) {
                      chunks.addAll(chunk);
                      if (onProgress != null) {
                        onProgress(chunks.length, expectedSize);
                      }
                    }
                    final mtdBytes = Uint8List.fromList(chunks);
                    if (mtdBytes.isNotEmpty) {
                      Logger.info(
                        'MTD Dump Strategy 0 succeeded: ${mtdBytes.length} bytes downloaded from $targetDev',
                      );
                      return mtdBytes;
                    }
                  }
                } finally {
                  client.close(force: true);
                }
              } catch (_) {}
            }
          } catch (_) {}
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
    final l10n = AppLocalizations.of(context);
    final dev = _selectedMtdDevice!;
    final filename = dev.split('/').last;

    setState(() {
      _isProcessing = true;
      _uploadProgress = 0.0;
      _statusMessage =
          l10n?.backupStatusDumpingPartition(dev) ??
          'Dumping partition image ($dev)...';
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
        context.showToastSuccess(
          l10n?.sysUpgradePartitionSaved ??
              'Partition image saved successfully.',
        );
        await OsPlatformIntegration.showBackupDownloadedPrompt(
          context,
          saveResult,
        );
      } else {
        context.showToastError(
          l10n?.sysUpgradePartitionSaveFailed ??
              'Failed to write partition image file to storage.',
          subtitle: 'Please check app storage permissions or available space.',
        );
      }
    } catch (e, stack) {
      Logger.error('Partition Image Download Error: $e', stack);
      if (mounted) {
        setState(() => _isProcessing = false);
        context.showToastError(
          'Failed to save mtdblock',
          subtitle: LuciToastManager.parseErrorReason(e),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _flashStarted = false;
        });
      }
    }
  }

  Future<void> _handlePerformSysupgrade() async {
    // Prevent double-tap from submitting the flash command twice.
    if (_flashStarted) {
      Logger.warning('_handlePerformSysupgrade: duplicate invocation blocked');
      return;
    }
    final l10n = AppLocalizations.of(context);
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
            l10n?.sysUpgradeInvalidFirmwareFormat ?? 'Invalid Firmware Format',
            subtitle:
                l10n?.sysUpgradeInvalidFirmwareFormatSubtitle ??
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
          'Insufficient /tmp space for upload',
          subtitle:
              '$fileSizeMbStr MB required, ${_tmpAvailableMb.toStringAsFixed(1)} MB available.',
        );
        return;
      }

      // Upload file to router /tmp with chunked progress
      setState(() {
        _isProcessing = true;
        _uploadProgress = 0.0;
        _statusMessage =
            l10n?.backupStatusUploadingFirmware(fileSizeMbStr) ??
            'Uploading firmware image ($fileSizeMbStr MB)...';
      });

      final appState = ref.read(appStateProvider);
      final router = appState.selectedRouter;
      final sysauth = appState.sysauth;
      final api = appState.apiService;

      if (router != null && sysauth != null && api != null) {
        // Remove existing /tmp/firmware.bin first
        try {
          await api.call(
            router.ipAddress,
            sysauth,
            router.useHttps,
            object: 'file',
            method: 'remove',
            params: {'path': '/tmp/firmware.bin'},
          );
        } catch (_) {}

        final b64Str = base64Encode(fileBytes);
        const chunkSize = 24000;
        for (var i = 0; i < b64Str.length; i += chunkSize) {
          final end = (i + chunkSize < b64Str.length)
              ? i + chunkSize
              : b64Str.length;
          final chunk = b64Str.substring(i, end);
          await api.call(
            router.ipAddress,
            sysauth,
            router.useHttps,
            object: 'file',
            method: 'write',
            params: {
              'path': '/tmp/firmware.bin',
              'data': chunk,
              'base64': true,
              if (i > 0) 'append': true,
            },
          );
          if (mounted) {
            setState(() {
              _uploadProgress = end / b64Str.length;
            });
          }
        }
      } else {
        await appState.executeRouterCommand('sh', [
          '-c',
          'rm -f /tmp/firmware.bin',
        ]);
      }

      // Pre-Flash Image Validation Check (`sysupgrade -t` / `system.validate_firmware_image`)
      setState(() {
        _statusMessage =
            l10n?.backupStatusVerifyingFirmware ??
            'Verifying image compatibility (sysupgrade -t)...';
        _uploadProgress = null;
      });

      FirmwareImageValidationResult imageValidationResult;
      if (router != null && sysauth != null && api != null) {
        final scanService = RouterUpgradeScanService(
          apiService: api,
          ipAddress: router.ipAddress,
          sysauth: sysauth,
          useHttps: router.useHttps,
        );
        imageValidationResult = await scanService.validateImage(
          '/tmp/firmware.bin',
          force: _forceSysupgrade,
        );
      } else {
        imageValidationResult = const FirmwareImageValidationResult(
          status: ImageValidationStatus.inconclusive,
          commandOutput: 'Router connection unavailable',
        );
      }

      // Store the validation result so the readiness report can use it
      if (mounted) {
        setState(() => _imageValidation = imageValidationResult);
      }

      final isVerified =
          imageValidationResult.status == ImageValidationStatus.passed;

      if (!mounted) return;
      setState(() => _isProcessing = false);
      unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));

      // Pre-Flash Confirmation & Settings Sheet
      final proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) {
            final colorScheme = Theme.of(context).colorScheme;
            return AlertDialog(
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.system_update_alt,
                      color: colorScheme.primary,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n?.sysUpgradePreFlashTitle ??
                          'Firmware Pre-Flash Check',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
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
                                      ? (l10n?.sysUpgradeImgVerified ??
                                            'Image Verification Passed')
                                      : (l10n?.sysUpgradeImgUnverified ??
                                            'Pre-Flash Test Unverified'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isVerified
                                        ? Colors.teal
                                        : Colors.orange.shade900,
                                  ),
                                ),
                                Text(
                                  isVerified
                                      ? (l10n?.sysUpgradeImgVerifiedDesc(
                                              _romFlavor,
                                            ) ??
                                            'Firmware image matches target architecture for $_romFlavor.')
                                      : (l10n?.sysUpgradeImgUnverifiedDesc ??
                                            'sysupgrade -t test warning. Verify board compatibility before flashing.'),
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
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      'Target ROM: $_romFlavor',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Divider(height: 24),
                    CheckboxListTile(
                      title: Text(
                        l10n?.sysUpgradeKeepSettings ??
                            'Keep settings and current configuration (-k)',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        l10n?.sysUpgradeKeepSettingsDialogSubtitle ??
                            'Retain active network, Wi-Fi, and user credentials.',
                        style: const TextStyle(fontSize: 11),
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
                      title: Text(
                        l10n?.sysUpgradeForceSysupgrade ?? 'Force upgrade (-F)',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        l10n?.sysUpgradeForceSysupgradeDesc ??
                            'Bypass board architecture validation (CAUTION!)',
                        style: const TextStyle(fontSize: 11),
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
                      child: Row(
                        children: [
                          const Icon(Icons.bolt, color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n?.sysUpgradeFlashWarning ??
                                  'WARNING: Do NOT disconnect power or ethernet during the flashing process!',
                              style: const TextStyle(
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
                  child: Text(
                    AppLocalizations.of(context)?.actionCancel ?? 'Cancel',
                  ),
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
                  label: Text(
                    AppLocalizations.of(context)?.backupFlashFirmwareNow ??
                        'Flash Firmware Now',
                  ),
                ),
              ],
            );
          },
        ),
      );

      // Clean up uploaded firmware file from router /tmp on cancel
      if (proceed != true) {
        final router = appState.selectedRouter;
        final sysauth = appState.sysauth;
        final api = appState.apiService;
        if (router != null && sysauth != null && api != null) {
          unawaited(
            api.call(
              router.ipAddress,
              sysauth,
              router.useHttps,
              object: 'file',
              method: 'remove',
              params: {'path': '/tmp/firmware.bin'},
            ),
          );
        }
        return;
      }

      // Atomically set the guard to prevent duplicate flash submissions
      if (_flashStarted) {
        Logger.warning(
          'Flash dedup guard triggered — aborting duplicate submission.',
        );
        return;
      }
      _flashStarted = true;

      setState(() {
        _isProcessing = true;
        _uploadProgress = null;
        _statusMessage =
            l10n?.backupStatusFlashing ??
            'Executing sysupgrade flash on router...';
      });

      // Prepare sysupgrade arguments matching rpcd ACL:
      // Allowed: /sbin/sysupgrade [-k | -n] [--force] /tmp/firmware.bin
      final sysupgradeArgs = <String>[
        if (_forceSysupgrade) '--force',
        _keepSettings ? '-k' : '-n',
        '/tmp/firmware.bin',
      ];

      bool flashInitiated = false;

      if (router != null && sysauth != null && api != null) {
        // Strategy 1: Direct file.exec /sbin/sysupgrade (explicitly in rpcd ACL)
        try {
          final res = await api.call(
            router.ipAddress,
            sysauth,
            router.useHttps,
            object: 'file',
            method: 'exec',
            params: {'command': '/sbin/sysupgrade', 'params': sysupgradeArgs},
          );
          if (res is List && res.length > 1 && res[0] == 0) {
            flashInitiated = true;
          }
        } catch (_) {}

        // Strategy 2: ubus rpc-sys upgrade_start if supported
        if (!flashInitiated) {
          try {
            final res = await api.call(
              router.ipAddress,
              sysauth,
              router.useHttps,
              object: 'rpc-sys',
              method: 'upgrade_start',
              params: {'keep': _keepSettings},
            );
            if (res is List && res.length > 1 && res[0] == 0) {
              flashInitiated = true;
            }
          } catch (_) {}
        }
      }

      // Strategy 3: Fallback through appState.executeRouterCommand
      if (!flashInitiated) {
        flashInitiated = await appState.executeRouterCommand(
          '/sbin/sysupgrade',
          sysupgradeArgs,
        );
      }

      if (!mounted) return;
      context.showToastSuccess(
        l10n?.sysUpgradeFlashInitiated ??
            'Firmware flash initiated successfully. Router is rebooting.',
      );
      _showRebootCountdownDialog();
    } catch (e) {
      if (!mounted) return;
      // Socket exception or network disconnection is expected when router shuts down interface during sysupgrade
      if (e.toString().toLowerCase().contains('socket') ||
          e.toString().toLowerCase().contains('connection')) {
        context.showToastSuccess(
          l10n?.sysUpgradeFlashInitiated ??
              'Firmware flash initiated successfully. Router is rebooting.',
        );
        _showRebootCountdownDialog();
      } else {
        context.showToastError(
          l10n?.sysUpgradeFlashFailed ?? 'Firmware Flash Failed',
          subtitle: LuciToastManager.parseErrorReason(e),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _flashStarted = false;
        });
      }
    }
  }

  /// Automated LuCI Attended Sysupgrade:
  /// Attempts direct router-side download first (via uclient-fetch / wget / curl).
  /// If direct router download is unavailable, falls back to client-assisted download
  /// and chunked transfer. Validates the image on the router with
  /// `system.validate_firmware_image` / `sysupgrade -t`, and initiates the flash.
  Future<void> _handleInstallUpgrade(FirmwareUpgradeAvailability avail) async {
    final l10n = AppLocalizations.of(context);
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final sysauth = appState.sysauth;
    final api = appState.apiService;

    if (router == null || sysauth == null || api == null) {
      context.showToastError(
        l10n?.sysUpgradeRouterNotActive ?? 'Router connection is not active.',
        subtitle: 'Please re-connect to the router and try again.',
      );
      return;
    }

    if (avail.downloadUrl == null) {
      context.showToastError(
        l10n?.sysUpgradeUrlNotFound ??
            'Download URL not found for this upgrade.',
        subtitle: 'The firmware server did not provide a valid image URL.',
      );
      return;
    }

    // 1. Show Confirmation Dialog
    bool keepSettingsLocal = _keepSettings;
    bool forceUpgradeLocal = _forceSysupgrade;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final dialogTheme = Theme.of(ctx);
          final dialogColors = dialogTheme.colorScheme;
          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  Icons.system_update_rounded,
                  color: LuciStatusColors.connectedColor(ctx),
                  size: 26,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n?.sysUpgradeInstallTitle ?? 'Install Firmware Upgrade',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n?.sysUpgradeInstallReadyDesc(
                          avail.latestVersion ?? '',
                        ) ??
                        'An official OpenWrt upgrade (${avail.latestVersion}) is ready to be installed directly on your router.',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: dialogColors.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        _buildDetailRow(
                          ctx,
                          label:
                              l10n?.sysUpgradeInstallTargetVersion ??
                              'Target Version',
                          value: 'OpenWrt ${avail.latestVersion ?? ""}',
                        ),
                        if (avail.currentVersion != null)
                          _buildDetailRow(
                            ctx,
                            label:
                                l10n?.sysUpgradeInstallCurrentVersion ??
                                'Current Version',
                            value: avail.currentVersion!,
                          ),
                        if (avail.imageName != null)
                          _buildDetailRow(
                            ctx,
                            label:
                                l10n?.sysUpgradeInstallImageFile ??
                                'Image File',
                            value: avail.imageName!,
                            isMonospace: true,
                          ),
                        if (avail.formattedImageSize != null)
                          _buildDetailRow(
                            ctx,
                            label:
                                l10n?.sysUpgradeInstallDownloadSize ??
                                'Download Size',
                            value: avail.formattedImageSize!,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    title: Text(
                      l10n?.sysUpgradeKeepSettingsOption ??
                          'Keep settings and current configuration (-k)',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      l10n?.sysUpgradeKeepSettingsOptionDesc ??
                          'Retain network interfaces, Wi-Fi keys, and passwords.',
                      style: TextStyle(
                        fontSize: 11,
                        color: dialogColors.onSurfaceVariant,
                      ),
                    ),
                    value: keepSettingsLocal,
                    onChanged: (val) {
                      setDialogState(() => keepSettingsLocal = val ?? true);
                      setState(() => _keepSettings = val ?? true);
                    },
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    title: Text(
                      l10n?.sysUpgradeForceOption ?? 'Force upgrade (--force)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: LuciStatusColors.warningColor(ctx),
                      ),
                    ),
                    subtitle: Text(
                      l10n?.sysUpgradeForceOptionDesc ??
                          'Bypass architecture safety checks (not recommended).',
                      style: TextStyle(
                        fontSize: 11,
                        color: dialogColors.onSurfaceVariant,
                      ),
                    ),
                    value: forceUpgradeLocal,
                    onChanged: (val) {
                      setDialogState(() => forceUpgradeLocal = val ?? false);
                      setState(() => _forceSysupgrade = val ?? false);
                    },
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: dialogColors.errorContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: dialogColors.error.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: dialogColors.error,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n?.sysUpgradeDoNotPowerOff ??
                                'Do NOT power off or disconnect the router during the upgrade.',
                            style: TextStyle(
                              fontSize: 11,
                              color: dialogColors.error,
                              fontWeight: FontWeight.w600,
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
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: Text(l10n?.actionCancel ?? 'Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: LuciStatusColors.connectedColor(ctx),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                child: Text(
                  l10n?.sysUpgradeInstallNow ?? 'Install Upgrade Now',
                ),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;

    if (_flashStarted) {
      Logger.warning(
        'Flash dedup guard triggered — aborting duplicate submission.',
      );
      return;
    }
    _flashStarted = true;

    setState(() {
      _isProcessing = true;
      _uploadProgress = 0.05;
      _statusMessage =
          l10n?.sysUpgradeDirectRouterDownload(
            avail.formattedImageSize ?? '',
          ) ??
          'Instructing router to download firmware directly (${avail.formattedImageSize ?? ""} )...';
    });

    try {
      // Clear any prior /tmp/firmware.bin
      try {
        await api.call(
          router.ipAddress,
          sysauth,
          router.useHttps,
          object: 'file',
          method: 'remove',
          params: {'path': '/tmp/firmware.bin'},
        );
      } catch (_) {}

      // Step 1: Attempt direct download on the router
      bool directDownloadSuccess = false;
      final directDownloadCandidates = [
        {
          'cmd': '/bin/uclient-fetch',
          'args': ['-O', '/tmp/firmware.bin', avail.downloadUrl!],
        },
        {
          'cmd': '/usr/bin/wget',
          'args': ['-O', '/tmp/firmware.bin', avail.downloadUrl!],
        },
        {
          'cmd': 'uclient-fetch',
          'args': ['-O', '/tmp/firmware.bin', avail.downloadUrl!],
        },
        {
          'cmd': 'wget',
          'args': ['-O', '/tmp/firmware.bin', avail.downloadUrl!],
        },
        {
          'cmd': 'curl',
          'args': [
            '-s',
            '-k',
            '-L',
            '-o',
            '/tmp/firmware.bin',
            avail.downloadUrl!,
          ],
        },
      ];

      for (final candidate in directDownloadCandidates) {
        try {
          final res = await api.call(
            router.ipAddress,
            sysauth,
            router.useHttps,
            object: 'file',
            method: 'exec',
            params: {'command': candidate['cmd'], 'params': candidate['args']},
          );
          if (res is List && res.length > 1 && res[0] == 0) {
            // Verify file was written and is at least 1MB
            final statRes = await api.call(
              router.ipAddress,
              sysauth,
              router.useHttps,
              object: 'file',
              method: 'stat',
              params: {'path': '/tmp/firmware.bin'},
            );
            if (statRes is List && statRes.length > 1 && statRes[0] == 0) {
              final statData = statRes[1] as Map<String, dynamic>?;
              final size = statData?['size'] as int? ?? 0;
              if (size > 1024 * 1024) {
                directDownloadSuccess = true;
                Logger.info(
                  'Router directly downloaded firmware image ($size bytes)',
                );
                break;
              }
            }
          }
        } catch (_) {}
      }

      // Step 2: Fall back to client streaming if direct router download was unavailable
      if (!directDownloadSuccess) {
        if (mounted) {
          setState(() {
            _statusMessage =
                l10n?.sysUpgradeFallbackStreaming ??
                'Router direct download unavailable; streaming image from app to router...';
            _uploadProgress = 0.10;
          });
        }

        final dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(minutes: 5),
            headers: {'User-Agent': 'YALA-Mobile-OpenWrt-Client'},
          ),
        );

        final response = await dio.get<List<int>>(
          avail.downloadUrl!,
          options: Options(responseType: ResponseType.bytes),
          onReceiveProgress: (received, total) {
            if (total > 0 && mounted) {
              setState(() {
                _statusMessage =
                    l10n?.sysUpgradeDownloadingImage(
                      avail.latestVersion ?? '',
                      avail.formattedImageSize ?? '',
                    ) ??
                    'Downloading OpenWrt ${avail.latestVersion}...';
                _uploadProgress = (received / total) * 0.40; // 0 to 40%
              });
            }
          },
        );

        final bytes = Uint8List.fromList(response.data!);
        if (bytes.isEmpty) {
          throw Exception('Downloaded firmware image is empty.');
        }

        // SHA-256 Checksum validation
        if (mounted) {
          setState(() {
            _statusMessage =
                l10n?.sysUpgradeVerifyingChecksum ??
                'Verifying SHA-256 checksum...';
            _uploadProgress = 0.42;
          });
        }

        final computedSha256 = Sha256.hex(bytes);
        if (avail.sha256 != null &&
            computedSha256.toLowerCase() != avail.sha256!.toLowerCase()) {
          throw Exception(
            l10n?.sysUpgradeChecksumMismatch(avail.sha256!, computedSha256) ??
                'SHA-256 checksum mismatch! Upgrade aborted for device safety.',
          );
        }

        // Transfer to Router (/tmp/firmware.bin)
        final sizeMb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
        if (mounted) {
          setState(() {
            _statusMessage =
                l10n?.sysUpgradeTransferringImage(sizeMb) ??
                'Transferring image to router ($sizeMb MB)...';
            _uploadProgress = 0.45;
          });
        }

        final b64Str = base64Encode(bytes);
        const chunkSize = 24000;
        for (var i = 0; i < b64Str.length; i += chunkSize) {
          final end = (i + chunkSize < b64Str.length)
              ? i + chunkSize
              : b64Str.length;
          final chunk = b64Str.substring(i, end);
          await api.call(
            router.ipAddress,
            sysauth,
            router.useHttps,
            object: 'file',
            method: 'write',
            params: {
              'path': '/tmp/firmware.bin',
              'data': chunk,
              'base64': true,
              if (i > 0) 'append': true,
            },
          );
          if (mounted) {
            setState(() {
              _uploadProgress =
                  0.45 + (end / b64Str.length) * 0.45; // 45% to 90%
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _statusMessage =
                l10n?.sysUpgradeDirectRouterDownloadSuccess ??
                'Firmware downloaded directly onto router.';
            _uploadProgress = 0.90;
          });
        }
      }

      // Step 3: Router Verification (system.validate_firmware_image / sysupgrade -t)
      if (mounted) {
        setState(() {
          _statusMessage =
              l10n?.sysUpgradeVerifyingRouterCompatibility ??
              'Verifying compatibility on router (sysupgrade -t)...';
          _uploadProgress = 0.92;
        });
      }

      final scanService = RouterUpgradeScanService(
        apiService: api,
        ipAddress: router.ipAddress,
        sysauth: sysauth,
        useHttps: router.useHttps,
      );
      final validationResult = await scanService.validateImage(
        '/tmp/firmware.bin',
        force: forceUpgradeLocal,
      );

      if (!validationResult.isAcceptableForFlash) {
        // Remove corrupt / incompatible image from /tmp/firmware.bin
        try {
          await api.call(
            router.ipAddress,
            sysauth,
            router.useHttps,
            object: 'file',
            method: 'remove',
            params: {'path': '/tmp/firmware.bin'},
          );
        } catch (_) {}

        throw Exception(
          l10n?.sysUpgradeValidationFailed(
                validationResult.commandOutput ?? "Incompatible image",
              ) ??
              'Router pre-flash validation check failed. Upgrade cancelled.',
        );
      }

      // Step 4: Flash Invocation & Reboot
      if (mounted) {
        setState(() {
          _statusMessage =
              l10n?.sysUpgradeExecutingFlash ??
              'Executing sysupgrade flash on router...';
          _uploadProgress = 0.98;
        });
      }

      final sysupgradeArgs = <String>[
        if (forceUpgradeLocal) '--force',
        keepSettingsLocal ? '-k' : '-n',
        '/tmp/firmware.bin',
      ];

      bool flashInitiated = false;
      // Strategy 1: file.exec with /sbin/sysupgrade
      try {
        final res = await api.call(
          router.ipAddress,
          sysauth,
          router.useHttps,
          object: 'file',
          method: 'exec',
          params: {'command': '/sbin/sysupgrade', 'params': sysupgradeArgs},
        );
        if (res is List && res.length > 1 && res[0] == 0) {
          flashInitiated = true;
        }
      } catch (_) {}

      // Strategy 2: rpc-sys.upgrade_start (LuCI default)
      if (!flashInitiated) {
        try {
          final res = await api.call(
            router.ipAddress,
            sysauth,
            router.useHttps,
            object: 'rpc-sys',
            method: 'upgrade_start',
            params: {'keep': keepSettingsLocal},
          );
          if (res is List && res.length > 1 && res[0] == 0) {
            flashInitiated = true;
          }
        } catch (_) {}
      }

      // Strategy 3: appState.executeRouterCommand
      if (!flashInitiated) {
        flashInitiated = await appState.executeRouterCommand(
          '/sbin/sysupgrade',
          sysupgradeArgs,
        );
      }

      if (!mounted) return;

      // Invalidate screen upgrade cache so the old update available card will not linger
      setState(() {
        _isProcessing = false;
        _flashStarted = false;
        _upgradeAvailability = null;
        _upgradeScan = null;
        _readinessReport = null;
        _imageValidation = const FirmwareImageValidationResult(
          status: ImageValidationStatus.notRun,
        );
      });

      context.showToastSuccess(
        l10n?.sysUpgradeFlashInitiated ??
            'Firmware flash initiated successfully. Router is rebooting.',
      );
      _showRebootCountdownDialog();
    } catch (e) {
      if (!mounted) return;
      // Network drop or socket exception is expected if the router reboots immediately
      if (e.toString().toLowerCase().contains('socket') ||
          e.toString().toLowerCase().contains('connection') ||
          e.toString().toLowerCase().contains('closed')) {
        setState(() {
          _isProcessing = false;
          _flashStarted = false;
          _upgradeAvailability = null;
          _upgradeScan = null;
          _readinessReport = null;
          _imageValidation = const FirmwareImageValidationResult(
            status: ImageValidationStatus.notRun,
          );
        });
        context.showToastSuccess(
          l10n?.sysUpgradeFlashInitiated ??
              'Firmware flash initiated successfully. Router is rebooting.',
        );
        _showRebootCountdownDialog();
      } else {
        setState(() {
          _isProcessing = false;
          _flashStarted = false;
        });
        Logger.error('Automated upgrade failed: $e');
        context.showToastError(
          'Upgrade failed',
          subtitle: LuciToastManager.parseErrorReason(e),
        );
      }
    }
  }

  void _showRebootCountdownDialog({bool isFactoryReset = false}) {
    final l10n = AppLocalizations.of(context);
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final originalIp = router?.ipAddress ?? '192.168.1.1';
    final originalUseHttps = router?.useHttps ?? false;

    int remainingSeconds = isFactoryReset ? 75 : 120;
    bool isOnline = false;
    String discoveredHost = isFactoryReset ? '192.168.1.1' : originalIp;
    bool discoveredHttps = isFactoryReset ? false : originalUseHttps;
    Timer? countdownTimer;
    Timer? probeTimer;

    // After initial reboot delay, probe whether the router has come back online
    probeTimer = Timer.periodic(const Duration(seconds: 3), (t) async {
      final probeThreshold = isFactoryReset ? 60 : 95;
      if (remainingSeconds > probeThreshold) return;
      if (isOnline) {
        t.cancel();
        return;
      }

      final candidates = <_ProbeTarget>[
        if (isFactoryReset) ...[
          const _ProbeTarget('http', '192.168.1.1'),
          const _ProbeTarget('https', '192.168.1.1'),
          const _ProbeTarget('http', 'openwrt.lan'),
          _ProbeTarget(originalUseHttps ? 'https' : 'http', originalIp),
        ] else ...[
          _ProbeTarget(originalUseHttps ? 'https' : 'http', originalIp),
          const _ProbeTarget('http', '192.168.1.1'),
        ],
      ];

      for (final target in candidates) {
        if (isOnline) break;
        try {
          final client = HttpClient()
            ..connectionTimeout = const Duration(seconds: 2)
            ..badCertificateCallback = ((cert, host, port) => true);
          final uri = Uri.parse('${target.scheme}://${target.host}/ubus');
          final request = await client.postUrl(uri);
          request.headers.contentType = ContentType.json;
          final payload = jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'list',
            'params': [],
          });
          request.write(payload);
          final response = await request.close();
          if (response.statusCode == 200 ||
              response.statusCode == 403 ||
              response.statusCode == 400) {
            isOnline = true;
            discoveredHost = target.host;
            discoveredHttps = target.scheme == 'https';
            t.cancel();
            break;
          }
        } catch (_) {}
      }
    });

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: false,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (t) {
            if (remainingSeconds > 0 && !isOnline) {
              setModalState(() {
                remainingSeconds--;
              });
            } else if (isOnline) {
              setModalState(() {});
              t.cancel();
            } else {
              setModalState(() {});
              t.cancel();
            }
          });

          return SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isOnline)
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.green,
                        size: 52,
                      )
                    else
                      const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    Text(
                      isOnline
                          ? (isFactoryReset
                                ? 'Router Reset & Back Online!'
                                : (l10n?.sysUpgradeRebootOnline ??
                                      'Router is back online!'))
                          : (isFactoryReset
                                ? (l10n?.sysUpgradeResetDefaults ??
                                      'Resetting to Defaults & Rebooting...')
                                : (l10n?.sysUpgradeRebooting ??
                                      'Router Rebooting & Flashing...')),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isOnline
                          ? (isFactoryReset
                                ? 'The router has completed factory reset and is back online at ${discoveredHttps ? "https" : "http"}://$discoveredHost with default settings.\n\nRoot password has been cleared to factory defaults (empty).'
                                : (l10n?.sysUpgradeRebootOnlineDesc ??
                                      'The router has rebooted successfully into the new firmware. You can return to the dashboard now.'))
                          : (isFactoryReset
                                ? 'The system is erasing the configuration partition now and will reboot itself when finished.\nEstimated time: ${remainingSeconds}s'
                                : (l10n?.sysUpgradeRebootWait(
                                        remainingSeconds,
                                      ) ??
                                      'Please wait while OpenWrt applies changes and restarts network services.\nEstimated time: ${remainingSeconds}s')),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: isOnline
                            ? ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade700,
                                foregroundColor: Colors.white,
                              )
                            : null,
                        onPressed: () async {
                          countdownTimer?.cancel();
                          probeTimer?.cancel();
                          Navigator.of(ctx).pop();
                          if (mounted) {
                            if (isFactoryReset) {
                              // Factory reset wipes session credentials; return to main login entrypoint
                              await ref.read(appStateProvider).logout();
                              if (mounted) {
                                Navigator.of(
                                  this.context,
                                ).popUntil((route) => route.isFirst);
                              }
                            } else {
                              Navigator.of(this.context).pop();
                              unawaited(
                                ref
                                    .read(appStateProvider)
                                    .fetchDashboardData(force: true),
                              );
                            }
                          }
                        },
                        child: Text(
                          isOnline
                              ? (isFactoryReset
                                    ? 'Go to Login ($discoveredHost)'
                                    : (l10n?.sysUpgradeReturnDashboard ??
                                          'Return to Dashboard'))
                              : (l10n?.backupDismissReturnDashboard ??
                                    'Dismiss & Return to Dashboard'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ).then((_) {
      countdownTimer?.cancel();
      probeTimer?.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final textScaler = mediaQuery.textScaler;
    final isTablet = screenWidth >= 600;

    const double headerVerticalPadding = 4.0;
    final double tabHeight;
    if (isTablet) {
      tabHeight = (textScaler.scale(12.0) * 1.3 * 2 + 20.0).clamp(52.0, 76.0);
    } else {
      // Dynamic height accounting for 16px icon, 4px gap, 3 full lines of text at scaled font, and padding
      final textHeight = textScaler.scale(11.0) * 1.18 * 3;
      tabHeight = (16.0 + 4.0 + textHeight + 10.0).clamp(72.0, 120.0);
    }
    final headerHeight = tabHeight + (headerVerticalPadding * 2);

    return Scaffold(
      appBar: LuciAppBar(
        title: l10n?.sysUpgradeTitle ?? 'Backup / Flash Firmware',
        showBack: true,
      ),
      body: Stack(
        children: [
          NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LuciContextualHintBanner(
                          hintId: 'backup_safety_advisory_hint',
                          title:
                              l10n?.sysUpgradeHintTitle ??
                              'Backup & Sysupgrade Guidance',
                          message:
                              l10n?.sysUpgradeHintDesc ??
                              'Downloading a backup archive preserves your custom settings across firmware updates. Always double-check target architecture before flashing new images.',
                          icon: Icons.shield_outlined,
                          accentColor: Colors.teal,
                        ),
                        const SizedBox(height: 10),
                        _buildHeroContextCard(context, l10n),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SliverTabBarDelegate(
                    height: headerHeight,
                    child: Container(
                      color: theme.scaffoldBackgroundColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: headerVerticalPadding,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          indicatorSize: TabBarIndicatorSize.tab,
                          dividerColor: Colors.transparent,
                          indicator: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          labelColor: theme.colorScheme.onPrimary,
                          unselectedLabelColor:
                              theme.colorScheme.onSurfaceVariant,
                          tabs: [
                            _buildNavigationTab(
                              icon: Icons.system_update_alt,
                              label:
                                  l10n?.sysUpgradeSectionFlash ??
                                  'Flash New Firmware',
                              tabHeight: tabHeight,
                              isTablet: isTablet,
                            ),
                            _buildNavigationTab(
                              icon: Icons.archive_outlined,
                              label:
                                  l10n?.sysUpgradeSectionBackup ??
                                  'Backup & Restore',
                              tabHeight: tabHeight,
                              isTablet: isTablet,
                            ),
                            _buildNavigationTab(
                              icon: Icons.tune_rounded,
                              label:
                                  l10n?.sysUpgradeMtdBlockSection ??
                                  'MTD Block Partitions',
                              tabHeight: tabHeight,
                              isTablet: isTablet,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ];
            },
            body: TabBarView(
              controller: _tabController,
              children: [
                _buildUpgradeTab(context, l10n),
                _buildBackupRestoreTab(context, l10n),
                _buildAdvancedTab(context, l10n),
              ],
            ),
          ),
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
                              l10n?.sysUpgradeUploading(
                                    (_uploadProgress! * 100).toInt(),
                                  ) ??
                                  '${(_uploadProgress! * 100).toInt()}% uploaded',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ] else ...[
                            const CircularProgressIndicator(),
                          ],
                          const SizedBox(height: 16),
                          Text(
                            _statusMessage ??
                                (l10n?.sysUpgradeProcessing ?? 'Processing...'),
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
                                l10n?.sysUpgradeOverlayDismissed ??
                                    'Operation overlay dismissed.',
                              );
                            },
                            icon: const Icon(Icons.close_rounded, size: 18),
                            label: Text(
                              l10n?.sysUpgradeBtnCancelDismiss ??
                                  'Cancel / Dismiss',
                            ),
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

  Widget _buildNavigationTab({
    required IconData icon,
    required String label,
    required double tabHeight,
    required bool isTablet,
  }) {
    return Tab(
      height: tabHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: isTablet
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 16),
                  const SizedBox(height: 3),
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildHeroContextCard(BuildContext context, AppLocalizations? l10n) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
              Theme.of(context).colorScheme.surfaceContainer,
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
                Icon(
                  Icons.router,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _routerModel == 'Detecting hardware...'
                        ? (l10n?.detectingHardware ?? 'Detecting hardware…')
                        : _routerModel,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${l10n?.sysUpgradeRamSpace ?? "/tmp Space"}: ${_resolveTmpSpace(l10n)}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                ),
                Text(
                  '${l10n?.sysUpgradeTargetArch ?? "Target Arch"}: $_targetArch',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (_upgradeScan != null &&
                    _upgradeScan!.packageManager.isKnown &&
                    _upgradeScan!.packageManager.value != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Pkg: ${_packageManagerLabel(l10n, _upgradeScan!.packageManager)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${l10n?.sysUpgradeFirmwareVersion ?? "Firmware Version"}: $_firmwareVersion',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpgradeTab(BuildContext context, AppLocalizations? l10n) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        if (_scanInProgress)
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    l10n?.upgradeScanInProgressLabel ??
                        'Running router compatibility scan…',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        if (_scanInProgress) const SizedBox(height: 12),

        if (_upgradeScan != null && _upgradeScan!.isPartial)
          _buildUpgradeBanner(
            context,
            icon: Icons.warning_amber_rounded,
            color: Colors.orange,
            title: l10n?.upgradeScanIncompleteTitle ?? 'Scan Incomplete',
            body:
                _upgradeScan!.partialScanReason ??
                (l10n?.upgradeScanIncompleteBody ??
                    'Some router probes failed. Compatibility data may be incomplete.'),
          ),
        if (_upgradeScan != null && _upgradeScan!.isPartial)
          const SizedBox(height: 12),

        // 1. Automated Firmware Upgrade Center (Attended Sysupgrade)
        LuciCollapsibleCard(
          title: l10n?.upgradeCenterTitle ?? 'Firmware Upgrade Center',
          subtitle: _upgradeScan == null
              ? (l10n?.upgradeCenterSubtitleScanning ?? 'Scanning router…')
              : (l10n?.upgradeCenterSubtitleReady ??
                    'Check for available firmware updates'),
          icon: Icons.system_update_alt,
          iconColor: Colors.indigo,
          initiallyExpanded: true,
          child: _buildUpgradeCenterContent(context),
        ),

        const SizedBox(height: 16),

        // 2. Flash Custom Firmware Image
        LuciCollapsibleCard(
          title: l10n?.sysUpgradeSectionFlash ?? 'Flash Firmware Image',
          subtitle:
              l10n?.sysUpgradeFlashSubtitle ??
              'Sysupgrade firmware upgrade (.bin, .img.gz, .tar.gz)',
          icon: Icons.flash_on_rounded,
          iconColor: Colors.blue,
          initiallyExpanded: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n?.sysUpgradeKeepSettingsDesc ??
                    'Upload a sysupgrade-compatible firmware image to upgrade or replace running OpenWrt firmware.',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 14),
              CheckboxListTile(
                title: Text(
                  l10n?.sysUpgradeKeepSettings ??
                      'Keep settings and current configuration (-k)',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                value: _keepSettings,
                onChanged: _isProcessing
                    ? null
                    : (val) => setState(() => _keepSettings = val ?? true),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                title: Text(
                  l10n?.sysUpgradeForceSysupgrade ?? 'Force upgrade (--force)',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
                subtitle: Text(
                  l10n?.sysUpgradeForceSysupgradeDesc ??
                      'Bypass platform architecture & checksum compatibility checks (--force).',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                value: _forceSysupgrade,
                onChanged: _isProcessing
                    ? null
                    : (val) => setState(() => _forceSysupgrade = val ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 12),
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
                  label: Text(
                    l10n?.sysUpgradeBtnSelectFirmware ??
                        'Select & Flash Firmware...',
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Readiness report card (shown after image validation)
        if (_imageValidation.status != ImageValidationStatus.notRun) ...[
          LuciCollapsibleCard(
            title: l10n?.readinessReportTitle ?? 'Upgrade Readiness Report',
            subtitle: _buildReadinessSummary(l10n),
            icon: Icons.checklist_rounded,
            iconColor: _readinessReportColor(),
            initiallyExpanded: true,
            child: _buildReadinessReportContent(context),
          ),
          const SizedBox(height: 16),
        ],

        // Migration analysis (ONLY shown when OPKG router upgrading to APK)
        if (_migrationAnalysis != null &&
            _migrationAnalysis!.transition ==
                PackageMigrationTransition.opkgToApk &&
            _upgradeScan?.packageManager.value ==
                RouterPackageManager.opkg) ...[
          LuciCollapsibleCard(
            title: l10n?.migrationNoticeTitle ?? 'Package Migration Notice',
            subtitle: _migrationTransitionLabel(
              l10n,
              _migrationAnalysis!.transition,
            ),
            icon: Icons.swap_horiz_rounded,
            iconColor: Colors.deepOrange,
            initiallyExpanded: true,
            child: _buildMigrationContent(context, _migrationAnalysis!),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _buildBackupRestoreTab(BuildContext context, AppLocalizations? l10n) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // 1. Backup Section
        _buildSectionCard(
          title:
              l10n?.sysUpgradeSectionBackup ?? 'Backup Configuration Archive',
          icon: Icons.archive_outlined,
          iconColor: Colors.teal,
          description:
              l10n?.sysUpgradeGenerateBackupDesc ??
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
                label: Text(
                  l10n?.sysUpgradeBtnDownloadBackup ??
                      'Generate & Download Backup Archive',
                ),
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
                label: Text(
                  l10n?.sysUpgradeBtnCustomize ??
                      'View Preserved Backup File List',
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 2. Restore Section
        _buildSectionCard(
          title: l10n?.sysUpgradeRestoreBackup ?? 'Restore Backup Archive',
          icon: Icons.restore_page_outlined,
          iconColor: Colors.deepPurple,
          description:
              l10n?.sysUpgradeRestoreBackupDesc ??
              'Upload a previously generated tar.gz configuration archive to restore system settings.',
          actionWidget: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _isProcessing ? null : _handleUploadArchive,
              icon: const Icon(Icons.upload_file),
              label: Text(
                l10n?.sysUpgradeBtnUploadArchive ?? 'Upload Archive...',
              ),
            ),
          ),
        ),

        if (_preservationInventory != null) ...[
          const SizedBox(height: 16),
          LuciCollapsibleCard(
            title: l10n?.preservationImpactTitle ?? 'Preserved Files Overview',
            subtitle: _buildPreservationSummary(l10n, _preservationInventory!),
            icon: Icons.folder_special_outlined,
            iconColor: Colors.teal.shade700,
            initiallyExpanded: false,
            child: _buildPreservationContent(context, _preservationInventory!),
          ),
        ],
      ],
    );
  }

  Widget _buildAdvancedTab(BuildContext context, AppLocalizations? l10n) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // 1. Save mtdblock contents
        LuciCollapsibleCard(
          title:
              l10n?.sysUpgradeMtdBlockSection ??
              'Save Partition (mtdblock) Image',
          subtitle:
              l10n?.sysUpgradeMtdBlockDesc ??
              'Low-level partition dumps (bootloader, art, firmware)',
          icon: Icons.sd_storage_outlined,
          iconColor: Colors.amber.shade800,
          initiallyExpanded: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n?.sysUpgradeMtdBlockDesc ??
                    'Download raw partition dumps for low-level system recovery. (ADVANCED USERS ONLY)',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 480;
                  final dropdown = DropdownButtonFormField<String>(
                    isExpanded: true,
                    isDense: true,
                    initialValue: _selectedMtdDevice,
                    borderRadius: BorderRadius.circular(16),
                    dropdownColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHigh,
                    elevation: 4,
                    menuMaxHeight: 360,
                    icon: const Icon(Icons.arrow_drop_down_rounded),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
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
                  );

                  final actionButton = ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    onPressed: _isProcessing ? null : _handleSaveMtdblock,
                    label: Text(
                      l10n?.sysUpgradeBtnBackupPartition ?? 'Save mtdblock',
                      textAlign: TextAlign.center,
                    ),
                  );

                  if (isCompact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        dropdown,
                        const SizedBox(height: 10),
                        actionButton,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: dropdown),
                      const SizedBox(width: 12),
                      actionButton,
                    ],
                  );
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 2. Factory Reset
        _buildSectionCard(
          title: l10n?.sysUpgradeResetDefaults ?? 'Reset to Defaults',
          icon: Icons.warning_amber_rounded,
          iconColor: Colors.redAccent,
          description:
              l10n?.sysUpgradeResetDefaultsDesc ??
              'Erase all configurations and restore router to initial flash defaults (firstboot).',
          actionWidget: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _isProcessing ? null : _handleFactoryReset,
              icon: const Icon(Icons.delete_forever_rounded),
              label: Text(l10n?.sysUpgradeBtnPerformReset ?? 'Perform Reset'),
            ),
          ),
        ),

        if (_preservationInventory != null) ...[
          const SizedBox(height: 16),
          LuciCollapsibleCard(
            title: l10n?.preservationImpactTitle ?? 'Full Preservation Audit',
            subtitle: _buildPreservationSummary(l10n, _preservationInventory!),
            icon: Icons.shield_outlined,
            iconColor: Colors.teal,
            initiallyExpanded: false,
            child: _buildPreservationContent(context, _preservationInventory!),
          ),
        ],
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

  // ── Upgrade Center helper widgets ────────────────────────────────────────

  /// Small colorized banner used for scan warnings and upgrade status.
  Widget _buildUpgradeBanner(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Content of the Firmware Upgrade Center collapsible card.
  Widget _buildUpgradeCenterContent(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scan = _upgradeScan;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Router identity rows
        if (scan != null) ...[
          _buildScanRow(
            l10n?.upgradeScanLabelModel ?? 'Model',
            scan.modelName.isKnown
                ? scan.modelName.value!
                : (l10n?.upgradeScanRowNotDetected ?? 'Not detected'),
            scan.modelName.isKnown
                ? Icons.check_circle_outline
                : Icons.help_outline,
            scan.modelName.isKnown ? Colors.green : Colors.grey,
          ),
          _buildScanRow(
            l10n?.upgradeScanLabelBoard ?? 'Board',
            scan.boardName.isKnown
                ? scan.boardName.value!
                : (l10n?.upgradeScanRowNotDetected ?? 'Not detected'),
            scan.boardName.isKnown
                ? Icons.check_circle_outline
                : Icons.help_outline,
            scan.boardName.isKnown ? Colors.green : Colors.grey,
          ),
          _buildScanRow(
            l10n?.upgradeScanLabelFirmware ?? 'Firmware',
            scan.distribDescription.value ??
                (scan.firmwareFamilyLabel.value ??
                    (l10n?.upgradeScanRowUnknown ?? 'Unknown')),
            Icons.info_outline,
            Colors.blue,
          ),
          if (scan.distribTarget.isKnown)
            _buildScanRow(
              l10n?.upgradeScanLabelTarget ?? 'Target',
              scan.distribTarget.value!,
              Icons.memory,
              Colors.purple,
            ),
          if (scan.distribArch.isKnown)
            _buildScanRow(
              l10n?.upgradeScanLabelArch ?? 'Arch',
              scan.distribArch.value!,
              Icons.memory,
              Colors.purple,
            ),
          _buildScanRow(
            l10n?.upgradeScanLabelPackageManager ?? 'Package Manager',
            _packageManagerLabel(l10n, scan.packageManager),
            Icons.inventory_2_outlined,
            Colors.teal,
          ),
          _buildScanRow(
            l10n?.upgradeScanLabelSysupgrade ?? 'Sysupgrade',
            scan.hasSysupgrade.value == true
                ? (l10n?.upgradeScanRowSysupgradeAvailable ?? 'Available')
                : scan.hasSysupgrade.isUnknown
                ? (l10n?.upgradeScanRowUnknown ?? 'Unknown')
                : (l10n?.upgradeScanRowSysupgradeNotFound ?? 'Not found'),
            scan.hasSysupgrade.value == true
                ? Icons.check_circle_outline
                : Icons.cancel_outlined,
            scan.hasSysupgrade.value == true ? Colors.green : Colors.red,
          ),
          _buildScanRow(
            l10n?.upgradeScanLabelTmpSpace ?? '/tmp Space',
            scan.tmpSpaceLabel,
            Icons.storage_outlined,
            Colors.teal,
          ),
          if (scan.isStale)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _buildUpgradeBanner(
                context,
                icon: Icons.schedule,
                color: Colors.orange,
                title: l10n?.upgradeScanStaleTitle ?? 'Scan data may be stale',
                body:
                    l10n?.upgradeScanStaleBody ??
                    'Last scanned more than 5 minutes ago. Tap Refresh to update.',
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(l10n?.upgradeRefreshScanBtn ?? 'Refresh Scan'),
                  onPressed: _scanInProgress ? null : _performUpgradeScan,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.indigo,
                    side: const BorderSide(color: Colors.indigo),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        // Upgrade availability check
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: (_upgradeCheckInProgress || _scanInProgress)
                ? null
                : _checkForUpgrades,
            icon: _upgradeCheckInProgress
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.cloud_sync_outlined),
            label: Text(l10n?.upgradeCheckBtn ?? 'Check for Firmware Upgrades'),
          ),
        ),
        // Availability result
        if (_upgradeAvailability != null) ...[
          const SizedBox(height: 12),
          _buildUpgradeAvailabilityResult(context, _upgradeAvailability!),
        ],
      ],
    );
  }

  Widget _buildScanRow(String label, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpgradeAvailabilityResult(
    BuildContext context,
    FirmwareUpgradeAvailability avail,
  ) {
    final l10n = AppLocalizations.of(context);
    final Color color;
    final IconData icon;
    final String statusTitle;

    switch (avail.status) {
      case UpgradeAvailabilityStatus.upgradeAvailable:
        color = Colors.green;
        icon = Icons.new_releases_rounded;
        statusTitle =
            l10n?.upgradeAvailStatusUpdateAvailable ?? 'Update Available';
      case UpgradeAvailabilityStatus.currentVersionLatest:
        color = Colors.teal;
        icon = Icons.check_circle_rounded;
        statusTitle = l10n?.upgradeAvailStatusUpToDate ?? 'Up to Date';
      case UpgradeAvailabilityStatus.unsupportedFirmwareSource:
        color = Colors.orange;
        icon = Icons.info_outline;
        statusTitle =
            l10n?.upgradeAvailStatusManualCheckRequired ??
            'Manual Check Required';
      case UpgradeAvailabilityStatus.currentVersionUnknown:
        color = Colors.grey;
        icon = Icons.help_outline;
        statusTitle =
            l10n?.upgradeAvailStatusVersionUnknown ?? 'Current Version Unknown';
      case UpgradeAvailabilityStatus.compatibilityUnverifiable:
        color = Colors.red;
        icon = Icons.warning_amber_rounded;
        statusTitle =
            l10n?.upgradeAvailStatusCompatibilityUnverifiable ??
            'Compatibility Unverifiable';
      case UpgradeAvailabilityStatus.noMatchingImageFound:
        color = Colors.red;
        icon = Icons.search_off_rounded;
        statusTitle =
            l10n?.upgradeAvailStatusNoMatchingImage ??
            'No Matching Image Found';
      case UpgradeAvailabilityStatus.updateSourceUnavailable:
        color = Colors.red;
        icon = Icons.cloud_off_outlined;
        statusTitle =
            l10n?.upgradeAvailStatusSourceUnavailable ??
            'Update Source Unavailable';
      case UpgradeAvailabilityStatus.notChecked:
        color = Colors.grey;
        icon = Icons.pending_outlined;
        statusTitle = l10n?.upgradeAvailStatusNotChecked ?? 'Not Checked';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  avail.status == UpgradeAvailabilityStatus.upgradeAvailable &&
                          avail.latestVersion != null
                      ? '${l10n?.upgradeAvailStatusUpdateAvailable ?? "Update Available"}: OpenWrt ${avail.latestVersion}'
                      : statusTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: color,
                  ),
                ),
              ),
              if (avail.currentVersion != null)
                Text(
                  l10n?.upgradeAvailCurrentVersion(avail.currentVersion!) ??
                      'Current: ${avail.currentVersion}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
            ],
          ),
          if (avail.explanation != null) ...[
            const SizedBox(height: 8),
            Text(
              avail.explanation!,
              style: const TextStyle(fontSize: 12, height: 1.3),
            ),
          ],
          // Extra details for available upgrade
          if (avail.isUpgradeAvailable && avail.imageName != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n?.upgradeAvailImageDetails ?? 'Firmware Image Details',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildDetailRow(
                    context,
                    label: 'Target Model',
                    value: avail.modelTitle ?? _routerModel,
                  ),
                  _buildDetailRow(
                    context,
                    label: 'Sysupgrade File',
                    value: avail.imageName!,
                    isMonospace: true,
                  ),
                  if (avail.formattedImageSize != null)
                    _buildDetailRow(
                      context,
                      label: 'Image Size',
                      value: avail.formattedImageSize!,
                    ),
                  if (avail.sha256 != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SHA-256: ',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            avail.sha256!,
                            style: const TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(
                              ClipboardData(text: avail.sha256!),
                            );
                            context.showToastInfo(
                              l10n?.upgradeAvailCopiedToast ??
                                  'Copied to clipboard',
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              Icons.copy_rounded,
                              size: 14,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Action Buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (avail.downloadUrl != null)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _isProcessing
                        ? null
                        : () => _handleInstallUpgrade(avail),
                    icon: const Icon(Icons.system_update_rounded, size: 16),
                    label: Text(
                      avail.latestVersion != null
                          ? (l10n?.sysUpgradeInstallAction(
                                  avail.latestVersion!,
                                ) ??
                                'Install Upgrade (OpenWrt ${avail.latestVersion})')
                          : (l10n?.sysUpgradeInstallNow ?? 'Install Upgrade'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (avail.downloadUrl != null)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => launchUrlString(
                      avail.downloadUrl!,
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: Text(
                      l10n?.upgradeAvailDownloadFirmware ??
                          'Download Image (.bin)',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                if (avail.downloadUrl != null)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: avail.downloadUrl!),
                      );
                      context.showToastInfo(
                        l10n?.upgradeAvailCopiedToast ?? 'Copied to clipboard',
                      );
                    },
                    icon: const Icon(Icons.link_rounded, size: 16),
                    label: Text(
                      l10n?.upgradeAvailCopyDownloadLink ??
                          'Copy Download Link',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ],
          // Retry button for source unavailable
          if (avail.status ==
              UpgradeAvailabilityStatus.updateSourceUnavailable) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _upgradeCheckInProgress ? null : _checkForUpgrades,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(
                l10n?.upgradeAvailRetryCheck ?? 'Retry Check',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context, {
    required String label,
    required String value,
    bool isMonospace = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11,
                fontFamily: isMonospace ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Readiness report color based on highest severity.
  Color _readinessReportColor() {
    // Use cached report if available (set after scan completes)
    final cached = _readinessReport;
    if (cached != null) {
      if (cached.hasBlockingIssues) return Colors.red;
      if (cached.hasWarnings) return Colors.orange;
      return Colors.green;
    }
    final scan = _upgradeScan;
    if (scan == null) return Colors.grey;
    final report = const UpgradeReadinessAssessor().assess(
      scan: scan,
      imageFileName: null,
      imageSizeBytes: null,
      imageValidation: _imageValidation,
      keepSettings: _keepSettings,
      forceUpgrade: _forceSysupgrade,
      backupWasGenerated: _backupGeneratedInSession,
    );
    if (report.hasBlockingIssues) return Colors.red;
    if (report.hasWarnings) return Colors.orange;
    return Colors.green;
  }

  String _buildReadinessSummary([AppLocalizations? l10n]) {
    final scan = _upgradeScan;
    if (scan == null) {
      return l10n?.readinessReportScanNotComplete ?? 'Router scan not complete';
    }
    final report = const UpgradeReadinessAssessor().assess(
      scan: scan,
      imageFileName: null,
      imageSizeBytes: null,
      imageValidation: _imageValidation,
      keepSettings: _keepSettings,
      forceUpgrade: _forceSysupgrade,
      backupWasGenerated: _backupGeneratedInSession,
    );
    final blocking = report.blocking.length;
    final warnings = report.warnings.length;
    if (blocking > 0) {
      return l10n?.readinessReportSummaryBlocking(blocking) ??
          '$blocking blocking issue${blocking > 1 ? 's' : ''} — flash not recommended';
    }
    if (warnings > 0) {
      return l10n?.readinessReportSummaryWarnings(warnings) ??
          '$warnings warning${warnings > 1 ? 's' : ''} — review before flashing';
    }
    return l10n?.readinessReportSummaryReady ?? 'Ready to flash';
  }

  Widget _buildReadinessReportContent(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Rebuild the report with current params
    final scan = _upgradeScan;
    if (scan == null) {
      return Text(
        l10n?.readinessReportScanNotCompleteHint ??
            'Router scan not yet complete. Refresh scan to generate readiness report.',
        style: const TextStyle(fontSize: 13, color: Colors.grey),
      );
    }
    final report = const UpgradeReadinessAssessor().assess(
      scan: scan,
      imageFileName: null,
      imageSizeBytes: null,
      imageValidation: _imageValidation,
      keepSettings: _keepSettings,
      forceUpgrade: _forceSysupgrade,
      backupWasGenerated: _backupGeneratedInSession,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (report.basedOnStaleData)
          _buildUpgradeBanner(
            context,
            icon: Icons.schedule,
            color: Colors.orange,
            title:
                l10n?.readinessReportStaleDataTitle ??
                'Based on stale scan data',
            body:
                l10n?.readinessReportStaleDataBody ??
                'Refresh the router scan for an up-to-date assessment.',
          ),
        if (report.basedOnStaleData) const SizedBox(height: 10),
        ...report.checks.map((check) => _buildReadinessCheckRow(check)),
      ],
    );
  }

  Widget _buildReadinessCheckRow(ReadinessCheckItem check) {
    final Color color;
    final IconData icon;
    switch (check.severity) {
      case ReadinessCheckSeverity.blocking:
        color = Colors.red;
        icon = Icons.block_rounded;
      case ReadinessCheckSeverity.warning:
        color = Colors.orange;
        icon = Icons.warning_amber_rounded;
      case ReadinessCheckSeverity.info:
        color = Colors.teal;
        icon = Icons.check_circle_outline;
      case ReadinessCheckSeverity.unknown:
        color = Colors.grey;
        icon = Icons.help_outline;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  check.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                Text(
                  check.description,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                if (check.detail != null)
                  Text(
                    check.detail!,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _migrationTransitionLabel(
    AppLocalizations? l10n,
    PackageMigrationTransition t,
  ) {
    switch (t) {
      case PackageMigrationTransition.opkgToApk:
        return l10n?.migrationTransitionOpkgToApk ??
            'OPKG → APK transition detected';
      case PackageMigrationTransition.apkToOpkg:
        return l10n?.migrationTransitionApkToOpkg ??
            'APK → OPKG transition detected';
      case PackageMigrationTransition.mixedOrVendor:
        return l10n?.migrationTransitionMixed ??
            'Mixed / vendor-specific package environment';
      case PackageMigrationTransition.opkgToOpkg:
      case PackageMigrationTransition.apkToApk:
        return l10n?.migrationTransitionNone ?? 'No package migration required';
      case PackageMigrationTransition.unknown:
        return l10n?.migrationTransitionUnknown ??
            'Package migration status unknown';
    }
  }

  Widget _buildMigrationContent(
    BuildContext context,
    PackageMigrationAnalysis analysis,
  ) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildUpgradeBanner(
          context,
          icon: Icons.swap_horiz_rounded,
          color: Colors.deepOrange,
          title: _migrationTransitionLabel(l10n, analysis.transition),
          body: analysis.summary,
        ),
        if (analysis.packages.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            l10n?.migrationInstalledPackagesLabel(analysis.packages.length) ??
                'Installed packages (${analysis.packages.length} detected):',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          ...analysis.packages.map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _migrationStatusIcon(item.migrationStatus),
                    size: 14,
                    color: _migrationStatusColor(item.migrationStatus),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.packageName,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (item.note != null)
                          Text(
                            item.note!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        _buildUpgradeBanner(
          context,
          icon: Icons.info_outline,
          color: Colors.blue,
          title: l10n?.migrationAfterUpgradeTitle ?? 'After upgrade',
          body:
              l10n?.migrationAfterUpgradeBody ??
              'Reinstall your required packages using the new package manager '
                  'after the firmware upgrade is complete.',
        ),
      ],
    );
  }

  IconData _migrationStatusIcon(PackageMigrationStatus s) {
    switch (s) {
      case PackageMigrationStatus.confirmed:
        return Icons.check_circle_outline;
      case PackageMigrationStatus.possibleEquivalent:
        return Icons.swap_horiz;
      case PackageMigrationStatus.noEquivalentFound:
        return Icons.cancel_outlined;
      case PackageMigrationStatus.kernelModuleRequiresTargetBuild:
        return Icons.memory_outlined;
      case PackageMigrationStatus.thirdPartyUnverified:
        return Icons.warning_amber_outlined;
      case PackageMigrationStatus.unknown:
        return Icons.help_outline;
    }
  }

  Color _migrationStatusColor(PackageMigrationStatus s) {
    switch (s) {
      case PackageMigrationStatus.confirmed:
        return Colors.green;
      case PackageMigrationStatus.possibleEquivalent:
        return Colors.orange;
      case PackageMigrationStatus.noEquivalentFound:
        return Colors.red;
      case PackageMigrationStatus.kernelModuleRequiresTargetBuild:
        return Colors.red;
      case PackageMigrationStatus.thirdPartyUnverified:
        return Colors.orange;
      case PackageMigrationStatus.unknown:
        return Colors.grey;
    }
  }

  String _buildPreservationSummary(
    AppLocalizations? l10n,
    PreservationImpactInventory inv,
  ) {
    final confirmed = inv.preserved.length;
    final lost = inv.lost.length;
    final conditional = inv.conditional.length;
    final unknownCount = inv.unknown.length;
    final parts = <String>[];
    if (confirmed > 0) {
      parts.add(
        l10n?.preservationSummaryPreserved(confirmed) ?? '$confirmed preserved',
      );
    }
    if (conditional > 0) {
      parts.add(
        l10n?.preservationSummaryConditional(conditional) ??
            '$conditional conditional',
      );
    }
    if (unknownCount > 0) {
      parts.add(
        l10n?.preservationSummaryUnknown(unknownCount) ??
            '$unknownCount unknown',
      );
    }
    if (lost > 0) {
      parts.add(l10n?.preservationSummaryLost(lost) ?? '$lost lost');
    }
    return parts.isEmpty
        ? (l10n?.preservationSummaryNoItems ?? 'No items detected')
        : parts.join(', ');
  }

  Widget _buildPreservationContent(
    BuildContext context,
    PreservationImpactInventory inv,
  ) {
    final l10n = AppLocalizations.of(context);
    if (inv.items.isEmpty) {
      return Text(
        l10n?.preservationNoItemsDetected ??
            'No configuration items could be detected. The router scan may be incomplete.',
        style: const TextStyle(fontSize: 13, color: Colors.grey),
      );
    }

    final attentionItems = [
      ...inv.lost,
      ...inv.conditional,
      ...inv.needsAction.where(
        (a) => !inv.lost.contains(a) && !inv.conditional.contains(a),
      ),
    ];

    // Filter preserved items by search text
    final query = _preservationFilter.trim().toLowerCase();
    final filteredPreserved = query.isEmpty
        ? inv.preserved
        : inv.preserved
              .where((item) => item.path.toLowerCase().contains(query))
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (inv.isPartial)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildUpgradeBanner(
              context,
              icon: Icons.warning_amber_rounded,
              color: Colors.orange,
              title:
                  l10n?.preservationPartialInventoryTitle ??
                  'Partial inventory',
              body:
                  inv.limitationNote ??
                  (l10n?.preservationPartialInventoryBody ??
                      'Some configuration items could not be inspected. '
                          'The list below may be incomplete.'),
            ),
          ),

        // 1. High-level metric summary chips
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildPreservationChip(
              icon: Icons.check_circle_outline,
              label: '${inv.preserved.length} Preserved',
              color: Colors.green,
            ),
            if (inv.conditional.isNotEmpty)
              _buildPreservationChip(
                icon: Icons.help_outline,
                label: '${inv.conditional.length} Conditional',
                color: Colors.orange,
              ),
            if (inv.lost.isNotEmpty)
              _buildPreservationChip(
                icon: Icons.cancel_outlined,
                label: '${inv.lost.length} Lost',
                color: Colors.red,
              ),
            if (inv.unknown.isNotEmpty)
              _buildPreservationChip(
                icon: Icons.help_outline,
                label: '${inv.unknown.length} Unknown',
                color: Colors.grey,
              ),
          ],
        ),

        const SizedBox(height: 12),

        // 2. Section for items requiring attention
        if (attentionItems.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n?.preservationItemsRequiringAttention ??
                          'Items Requiring Attention (${attentionItems.length})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepOrange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...attentionItems.map((item) {
                  final displayPath = item.isSensitive
                      ? (l10n?.preservationSensitivePath ??
                            '[sensitive — path redacted]')
                      : item.path;
                  final color = item.outcome == PreservationOutcome.lost
                      ? Colors.red
                      : Colors.orange;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          item.outcome == PreservationOutcome.lost
                              ? Icons.cancel_outlined
                              : Icons.help_outline,
                          size: 14,
                          color: color,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayPath,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: color,
                                ),
                              ),
                              if (item.recommendedAction != null)
                                Text(
                                  '→ ${item.recommendedAction}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.deepOrange,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ] else ...[
          // Reassuring notice when all items are preserved
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: Colors.green,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n?.preservationAllCovered ??
                        'All detected configurations are covered by sysupgrade preservation.',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 3. Expandable Preserved Files Explorer
        if (inv.preserved.isNotEmpty) ...[
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              setState(() {
                _isPreservedFilesExpanded = !_isPreservedFilesExpanded;
              });
            },
            icon: Icon(
              _isPreservedFilesExpanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              size: 18,
            ),
            label: Text(
              _isPreservedFilesExpanded
                  ? (l10n?.preservationHideFiles ?? 'Hide Preserved Files')
                  : (l10n?.preservationViewAllFiles(inv.preserved.length) ??
                        'View All Preserved Files (${inv.preserved.length})'),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (_isPreservedFilesExpanded) ...[
            const SizedBox(height: 8),
            // Search filter field
            TextField(
              decoration: InputDecoration(
                hintText:
                    l10n?.preservationSearchHint ?? 'Filter preserved files...',
                hintStyle: const TextStyle(fontSize: 12),
                prefixIcon: const Icon(Icons.search, size: 16),
                suffixIcon: _preservationFilter.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 14),
                        onPressed: () =>
                            setState(() => _preservationFilter = ''),
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              style: const TextStyle(fontSize: 12),
              onChanged: (val) => setState(() => _preservationFilter = val),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 260),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                ),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: filteredPreserved.length,
                separatorBuilder: (_, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = filteredPreserved[index];
                  final displayPath = item.isSensitive
                      ? (l10n?.preservationSensitivePath ??
                            '[sensitive — path redacted]')
                      : item.path;

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          size: 14,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            displayPath,
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.category.name,
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.teal,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildPreservationChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _packageManagerLabel(
    AppLocalizations? l10n,
    DetectedValue<RouterPackageManager> pm,
  ) {
    if (pm.isUnknown) return l10n?.packageManagerLabelUnknown ?? 'Unknown';
    switch (pm.value!) {
      case RouterPackageManager.opkg:
        return l10n?.packageManagerLabelOpkg ?? 'OPKG';
      case RouterPackageManager.apk:
        return l10n?.packageManagerLabelApk ?? 'APK';
      case RouterPackageManager.mixed:
        return l10n?.packageManagerLabelMixed ?? 'OPKG + APK';
      case RouterPackageManager.vendorSpecific:
        return l10n?.packageManagerLabelVendor ?? 'Vendor-specific';
      case RouterPackageManager.none:
        return l10n?.packageManagerLabelNone ?? 'None detected';
      case RouterPackageManager.unknown:
        return l10n?.packageManagerLabelUnknown ?? 'Unknown';
    }
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  _SliverTabBarDelegate({required this.child, required this.height});

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return true;
  }
}

class _ProbeTarget {
  final String scheme;
  final String host;
  const _ProbeTarget(this.scheme, this.host);
}
