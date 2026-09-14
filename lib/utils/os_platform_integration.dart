// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async' show unawaited;
import 'dart:io' show Platform, File, Directory, Process;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yet_another_luci_app/modules/storage_monitoring/models/storage_info.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';

/// Semantic haptic feedback intensity types.
enum OsHapticType { light, medium, heavy, selection }

enum StoragePermissionChoice { preferPublic, preferSandbox, cancelled }

class FileSaveResult {
  final String filePath;
  final bool isPublicDownloads;
  final String storageMethodLabel;

  FileSaveResult({
    required this.filePath,
    required this.isPublicDownloads,
    required this.storageMethodLabel,
  });
}

/// Centralized utility for native OS hardware integration & system API capability detection
/// with 100% fallback protection across Android, iOS, Linux, Windows, macOS, and Web.
///
/// Fully compliant with Scoped Storage / Sandboxing permission boundaries.
class OsPlatformIntegration {
  /// Safely triggers OS hardware haptic feedback engine with silent platform fallback.
  static Future<void> triggerHaptic(OsHapticType type) async {
    if (kIsWeb) return;
    try {
      switch (type) {
        case OsHapticType.light:
          await HapticFeedback.lightImpact();
          return;
        case OsHapticType.medium:
          await HapticFeedback.mediumImpact();
          return;
        case OsHapticType.heavy:
          await HapticFeedback.heavyImpact();
          return;
        case OsHapticType.selection:
          await HapticFeedback.selectionClick();
          return;
      }
    } catch (_) {}
  }

  /// Copies text to OS system clipboard with haptic confirmation and toast notification.
  static Future<void> copyToClipboard(
    BuildContext context, {
    required String text,
    required String label,
  }) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      await triggerHaptic(OsHapticType.light);
      if (context.mounted) {
        context.showToastSuccess('Copied $label', subtitle: text);
      }
    } catch (e) {
      if (context.mounted) {
        context.showToastError(
          'Clipboard Error',
          subtitle: 'Failed to copy $label.',
        );
      }
    }
  }

  /// Safely opens the device application settings screen on Android/iOS/Desktop
  /// to allow the user to grant or re-enable revoked permissions.
  static Future<bool> openSystemSettings(BuildContext context) async {
    await triggerHaptic(OsHapticType.medium);
    bool launched = false;

    if (kIsWeb) return false;

    try {
      if (Platform.isAndroid) {
        final intentUri = Uri.parse('package:yet_another_luci_app');
        if (await canLaunchUrl(intentUri)) {
          launched = await launchUrl(intentUri);
        }
      }
    } catch (_) {
      launched = false;
    }

    if (!launched && context.mounted) {
      context.showToastInfo(
        'Please open device Settings > Apps > Yet Another LuCI App to manage permissions.',
      );
    }

    return launched;
  }

  /// Helper to evaluate whether a filesystem path is genuinely public Downloads.
  static bool isPathPublic(String path) {
    final lower = path.toLowerCase();
    if (lower.contains('/android/data/') ||
        lower.contains('/data/user/') ||
        lower.contains('com.nightcode.luci')) {
      return false;
    }
    return true;
  }

  /// Fetches or maps the host OS public Downloads folder (/storage/emulated/0/Download).
  static Future<Directory?> getPublicDownloadsDirectory() async {
    if (kIsWeb) return null;

    if (Platform.isAndroid) {
      final stdDownload = Directory('/storage/emulated/0/Download');
      if (!stdDownload.existsSync()) {
        try {
          stdDownload.createSync(recursive: true);
        } catch (_) {}
      }
      if (stdDownload.existsSync()) {
        return stdDownload;
      }

      final sdDownload = Directory('/sdcard/Download');
      if (sdDownload.existsSync()) {
        return sdDownload;
      }
    }

    try {
      final d = await getDownloadsDirectory();
      if (d != null) return d;
    } catch (_) {}

    try {
      if (Platform.isLinux || Platform.isMacOS) {
        final home = Platform.environment['HOME'];
        if (home != null && home.isNotEmpty) {
          final userDownload = Directory('$home/Downloads');
          if (userDownload.existsSync()) return userDownload;
        }
      } else if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'];
        if (userProfile != null && userProfile.isNotEmpty) {
          final winDownload = Directory('$userProfile\\Downloads');
          if (winDownload.existsSync()) return winDownload;
        }
      }
    } catch (_) {}

    return null;
  }

  /// Direct save to /storage/emulated/0/Download/ (Public Downloads).
  static Future<FileSaveResult?> saveDownloadedFileWithResult({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (kIsWeb) return null;

    // Tier 1: Public Downloads Directory (/storage/emulated/0/Download)
    try {
      Directory? targetDir = Directory('/storage/emulated/0/Download');
      if (!targetDir.existsSync()) {
        try {
          targetDir.createSync(recursive: true);
        } catch (_) {
          targetDir = await getPublicDownloadsDirectory();
        }
      }
      targetDir ??= await getPublicDownloadsDirectory();

      if (targetDir != null && targetDir.existsSync()) {
        final file = File('${targetDir.path}/$fileName');
        await file.writeAsBytes(bytes, flush: true);
        if (Platform.isAndroid) {
          try {
            await Process.run('am', [
              'broadcast',
              '-a',
              'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
              '-d',
              'file://${file.path}',
            ]);
          } catch (_) {}
        }
        return FileSaveResult(
          filePath: file.path,
          isPublicDownloads: isPathPublic(file.path),
          storageMethodLabel: 'Public Downloads Folder',
        );
      }
    } catch (_) {
      // Primary public storage threw permission or IO exception on older hardware
    }

    // Tier 2: External App Storage Directory (/sdcard/Android/data/... or external files)
    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        if (!extDir.existsSync()) extDir.createSync(recursive: true);
        final file = File('${extDir.path}/$fileName');
        await file.writeAsBytes(bytes, flush: true);
        return FileSaveResult(
          filePath: file.path,
          isPublicDownloads: isPathPublic(file.path),
          storageMethodLabel: 'External App Storage',
        );
      }
    } catch (_) {}

    // Tier 3: Application Documents Directory (Internal App Sandbox - 100% permission safe)
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      if (!docsDir.existsSync()) docsDir.createSync(recursive: true);
      final file = File('${docsDir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return FileSaveResult(
        filePath: file.path,
        isPublicDownloads: false,
        storageMethodLabel: 'App Storage (Sandbox)',
      );
    } catch (_) {}

    // Tier 4: Temporary Directory
    try {
      final tempDir = await getTemporaryDirectory();
      if (!tempDir.existsSync()) tempDir.createSync(recursive: true);
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return FileSaveResult(
        filePath: file.path,
        isPublicDownloads: false,
        storageMethodLabel: 'Temporary Storage',
      );
    } catch (_) {}

    return null;
  }

  /// Saves downloaded file bytes to public Downloads.
  static Future<String?> saveDownloadedFile({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final res = await saveDownloadedFileWithResult(
      bytes: bytes,
      fileName: fileName,
    );
    return res?.filePath;
  }

  /// Displays a clean prompt after file download, showing the saved path
  /// and providing a clipboard copy button.
  static Future<void> showFileDownloadedPrompt(
    BuildContext context,
    FileSaveResult saveResult, {
    String title = 'File Saved Successfully',
    String fileLabel = 'File Path',
    IconData icon = Icons.check_circle_outline,
    Color accentColor = Colors.teal,
  }) async {
    if (!context.mounted) return;
    await triggerHaptic(OsHapticType.medium);
    if (!context.mounted) return;

    final file = File(saveResult.filePath);
    int fileSizeInBytes = 0;
    try {
      if (file.existsSync()) {
        fileSizeInBytes = file.lengthSync();
      }
    } catch (_) {}

    final formattedSize = StorageOverview.formatBytes(fileSizeInBytes);

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fileName = file.path.split(Platform.pathSeparator).last;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        icon: Icon(icon, color: accentColor, size: 40),
        title: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // File Summary Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.6,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.insert_drive_file_outlined,
                        size: 20,
                        color: accentColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          fileName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Size: $formattedSize',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              saveResult.isPublicDownloads
                                  ? Icons.folder_special_outlined
                                  : Icons.folder_outlined,
                              size: 11,
                              color: accentColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              saveResult.storageMethodLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: accentColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Saved File Location:',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: SelectableText(
                saveResult.filePath,
                style: GoogleFonts.geistMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              unawaited(
                copyToClipboard(
                  context,
                  text: saveResult.filePath,
                  label: fileLabel,
                ),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy File Path'),
          ),
        ],
      ),
    );
  }

  /// Displays a clean prompt after backup download.
  static Future<void> showBackupDownloadedPrompt(
    BuildContext context,
    FileSaveResult saveResult,
  ) async {
    return showFileDownloadedPrompt(
      context,
      saveResult,
      title: 'Backup Downloaded Successfully',
      fileLabel: 'Backup Path',
      icon: Icons.check_circle_outline,
      accentColor: Colors.teal,
    );
  }

  /// Attempts to open the host OS file manager directory containing the specified file.
  /// Falls back gracefully to showing an interactive path dialog with clipboard copying and file metrics.
  static Future<void> openSavedDirectoryOrFile(
    BuildContext context,
    String filePath,
  ) async {
    final isPublic = isPathPublic(filePath);
    final saveResult = FileSaveResult(
      filePath: filePath,
      isPublicDownloads: isPublic,
      storageMethodLabel: isPublic
          ? 'Public Downloads Folder'
          : 'Private App Storage (/Android/data/)',
    );
    await showBackupDownloadedPrompt(context, saveResult);
  }

  /// Returns `true` if current OS platform is Android (Phone, Tablet, Chromebook ARC subsystem).
  static bool get isAndroidPlatform {
    if (kIsWeb) return false;
    return Platform.isAndroid;
  }

  /// Returns `true` if current OS platform supports edge-to-edge system bar insets.
  static bool get supportsEdgeToEdge {
    if (kIsWeb) return false;
    return Platform.isAndroid;
  }

  /// Returns `true` if current OS platform supports native platform toast channels.
  static bool get supportsNativeOsToast {
    if (kIsWeb) return false;
    return Platform.isAndroid;
  }

  /// Returns `true` if current device is Android 12 (API level 31) or higher.
  /// On Android 12+, native text toasts are restricted to 2 lines max and prepended with app icon.
  static bool get isAndroid12OrHigher {
    if (kIsWeb) return false;
    if (!Platform.isAndroid) return false;
    try {
      final version = Platform.operatingSystemVersion;
      final match = RegExp(
        r'(?:API|SDK)\s*(\d+)|Android\s*(\d+)',
      ).firstMatch(version);
      if (match != null) {
        final sdkStr = match.group(1);
        if (sdkStr != null) {
          final sdkInt = int.tryParse(sdkStr);
          if (sdkInt != null) return sdkInt >= 31;
        }
        final verStr = match.group(2);
        if (verStr != null) {
          final verInt = int.tryParse(verStr);
          if (verInt != null) return verInt >= 12;
        }
      }
    } catch (_) {}
    return true; // Safely enforce custom Flutter toast on Android if version string format varies
  }

  /// Evaluates safe top inset padding considering OS status bar cutouts & notch insets.
  static double getSafeAreaTopPadding(
    BuildContext context, {
    double defaultOffset = 12.0,
  }) {
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top;
    final viewTopPadding = mediaQuery.viewPadding.top;
    final safeTop = topPadding > viewTopPadding ? topPadding : viewTopPadding;
    return safeTop + defaultOffset;
  }

  /// Evaluates safe bottom inset padding considering OS navigation bar / gesture bar cutouts.
  static double getSafeAreaBottomPadding(
    BuildContext context, {
    double defaultOffset = 24.0,
  }) {
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.padding.bottom;
    final viewBottomPadding = mediaQuery.viewPadding.bottom;
    final safeBottom = bottomPadding > viewBottomPadding
        ? bottomPadding
        : viewBottomPadding;
    return safeBottom + defaultOffset;
  }

  /// Returns a summary description of the target platform capabilities
  /// (Android Phones, Tablets, Chromebooks, and Custom Android Derivatives/ROMs).
  static String getPlatformInfo() {
    if (kIsWeb) return 'Web Preview Mode';
    if (Platform.isAndroid) {
      final ver = Platform.operatingSystemVersion.toLowerCase();
      final sysVer = Platform.version.toLowerCase();
      if (ver.contains('chrome') || sysVer.contains('chrome')) {
        return 'Chromebook (ChromeOS ARC)';
      }
      if (ver.contains('graphene') || sysVer.contains('graphene')) {
        return 'GrapheneOS Android Subsystem';
      }
      if (ver.contains('calyx') || sysVer.contains('calyx')) {
        return 'CalyxOS Android Subsystem';
      }
      if (ver.contains('lineage') || sysVer.contains('lineage')) {
        return 'LineageOS Android Subsystem';
      }
      if (ver.contains('fire') || sysVer.contains('fire')) {
        return 'Fire OS Subsystem';
      }
      if (ver.contains('harmony') || sysVer.contains('huawei')) {
        return 'HarmonyOS Android Runtime';
      }
      if (ver.contains('waydroid')) {
        return 'Waydroid Linux-Android Subsystem';
      }
      return 'Android OS & Derivatives (Phone/Tablet)';
    }
    return 'Android Target Host Environment';
  }

  /// Gracefully minimizes/exits the application without corrupting Android task affinity
  /// or destroying the native Window surface, preventing black screens on reopen.
  static Future<void> exitApp({BuildContext? context}) async {
    if (kIsWeb) return;
    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('com.nightcode.luci/app_lifecycle');
        try {
          await platform.invokeMethod('exitApp');
          return;
        } catch (_) {}
      }
      await SystemNavigator.pop();
    } catch (_) {
      try {
        await SystemNavigator.pop();
      } catch (_) {}
    }
  }

  /// Sends the application task to the background (equivalent to Home button)
  /// preserving full in-memory state and eliminating cold start latency on resume.
  static Future<bool> minimizeApp() async {
    if (kIsWeb) return false;
    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('com.nightcode.luci/app_lifecycle');
        final res = await platform.invokeMethod<bool>('moveTaskToBack');
        return res ?? false;
      }
    } catch (_) {}
    return false;
  }
}
