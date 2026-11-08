// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:yet_another_luci_app/config/app_config.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';

/// Manages manual update checks against GitHub Releases.
/// For iOS IPA sideloadable builds, it checks for the latest iOS beta release.
/// For standard/Android Community builds, it checks for the latest stable release.
class UpdateCheckerService {
  @visibleForTesting
  static const String githubReleasesUrl =
      'https://api.github.com/repos/nightcodex7/yala/releases';

  /// Performs a manual check for updates on GitHub Releases and displays an interactive dialog.
  /// For IPA builds, it checks for the latest iOS beta release and provides a redirect to the release page.
  /// For non-IPA builds, it checks for the latest stable release and provides a download button.
  static Future<void> checkForUpdates(
    BuildContext context, {
    bool? isIpa,
    http.Client? client,
  }) async {
    if (AppConfig.isFdroidBuild) {
      return;
    }
    final isIpaBuild = isIpa ?? AppConfig.isIpaBuild;
    final l10n = AppLocalizations.of(context);
    // Display progress dialog
    unawaited(
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(l10n?.checkingForUpdates ?? 'Checking for updates...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersionStr = info.version.trim();

      final httpClient = client ?? http.Client();
      final response = await httpClient
          .get(
            Uri.parse(githubReleasesUrl),
            headers: {
              'Accept': 'application/vnd.github.v3+json',
              'User-Agent':
                  'YetAnotherLuCIApp/${info.version}${isIpaBuild ? " (iOS-IPA)" : ""}',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading
      }

      if (response.statusCode == 200) {
        final rawData = json.decode(response.body);
        Map<String, dynamic>? latestRelease;

        if (rawData is List && rawData.isNotEmpty) {
          latestRelease = selectTargetRelease(rawData, isIpaBuild: isIpaBuild);
        } else if (rawData is Map<String, dynamic>) {
          if (isIpaBuild) {
            if (isIpaBetaRelease(rawData)) latestRelease = rawData;
          } else {
            if (isStableRelease(rawData)) latestRelease = rawData;
          }
        }

        if (latestRelease != null) {
          final rawTagName = (latestRelease['tag_name'] as String? ?? '')
              .trim();
          final latestVersionStr = rawTagName.startsWith('v')
              ? rawTagName.substring(1)
              : rawTagName;
          final htmlUrl =
              latestRelease['html_url'] as String? ??
              'https://github.com/nightcodex7/yala/releases';
          final releaseNotes =
              latestRelease['body'] as String? ?? 'No release notes available.';

          final int comparison = compareVersions(
            currentVersionStr,
            latestVersionStr,
          );

          if (!context.mounted) return;

          if (comparison < 0) {
            // Latest on GitHub is newer than current app version
            showUpdateAvailableDialog(
              context,
              currentVersion: currentVersionStr,
              latestVersion: latestVersionStr,
              releaseNotes: releaseNotes,
              downloadUrl: htmlUrl,
              isIpaBuild: isIpaBuild,
            );
          } else if (comparison > 0) {
            // Current local build is newer than latest GitHub release (unreleased/dev build)
            showAheadOfReleaseDialog(
              context,
              currentVersion: currentVersionStr,
              latestGithubVersion: latestVersionStr,
              isIpaBuild: isIpaBuild,
            );
          } else {
            // Versions match exactly
            showUpToDateDialog(
              context,
              currentVersion: currentVersionStr,
              isIpaBuild: isIpaBuild,
            );
          }
        } else {
          if (!context.mounted) return;
          _showErrorDialog(
            context,
            isIpaBuild
                ? (l10n?.updateNoBetaReleasesFound ??
                      'No iOS beta releases found on GitHub.')
                : (l10n?.updateNoReleasesFound ??
                      'No releases found on GitHub.'),
          );
        }
      } else {
        if (!context.mounted) return;
        _showErrorDialog(
          context,
          l10n?.updateCheckFailedDesc ??
              'Unable to check for updates at this time.',
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).pop(); // Dismiss loading if open
        final errL10n = AppLocalizations.of(context);
        _showErrorDialog(
          context,
          errL10n?.updateConnectionError ??
              'Could not connect to GitHub to check for updates.',
        );
      }
    }
  }

  /// Returns true if a release represents an iOS IPA beta release.
  @visibleForTesting
  static bool isIpaBetaRelease(Map<String, dynamic> release) {
    if (release['draft'] == true) return false;
    final tagName = (release['tag_name'] as String? ?? '').trim().toLowerCase();
    final releaseName = (release['name'] as String? ?? '').trim().toLowerCase();
    final isPrerelease = release['prerelease'] == true;
    final assets = release['assets'] as List? ?? [];
    final hasIpaAsset = assets.any(
      (a) =>
          a is Map &&
          (a['name'] as String? ?? '').toLowerCase().endsWith('.ipa'),
    );

    final isBeta =
        isPrerelease ||
        tagName.contains('beta') ||
        releaseName.contains('beta');
    final isIosOrIpa =
        tagName.contains('ipa') ||
        tagName.contains('ios') ||
        releaseName.contains('ios') ||
        releaseName.contains('ipa') ||
        hasIpaAsset;

    return isBeta && isIosOrIpa;
  }

  /// Returns true if a release represents a stable release (non-beta, non-prerelease, non-IPA).
  @visibleForTesting
  static bool isStableRelease(Map<String, dynamic> release) {
    if (release['draft'] == true) return false;
    if (release['prerelease'] == true) return false;
    final tagName = (release['tag_name'] as String? ?? '').trim().toLowerCase();
    final releaseName = (release['name'] as String? ?? '').trim().toLowerCase();
    if (tagName.contains('beta') || releaseName.contains('beta')) return false;
    if (isIpaBetaRelease(release)) return false;
    return true;
  }

  /// Selects the target release from GitHub release list.
  /// For IPA builds: selects the latest iOS beta release.
  /// For standard/Android builds: selects the latest stable release.
  @visibleForTesting
  static Map<String, dynamic>? selectTargetRelease(
    List<dynamic> releases, {
    required bool isIpaBuild,
  }) {
    final validReleases = releases.whereType<Map<String, dynamic>>().where(
      (r) => r['draft'] != true,
    );

    if (isIpaBuild) {
      for (final r in validReleases) {
        if (isIpaBetaRelease(r)) return r;
      }
      return null;
    } else {
      for (final r in validReleases) {
        if (isStableRelease(r)) return r;
      }
      return null;
    }
  }

  /// Compares two semver strings (current vs latest).
  /// Returns:
  /// - Negative integer if current < latest (update available)
  /// - 0 if current == latest (up to date)
  /// - Positive integer if current > latest (ahead of GitHub release / local dev build)
  @visibleForTesting
  static int compareVersions(String current, String latest) {
    if (current == latest) return 0;

    final currentClean = current.split('+').first.split('-').first.trim();
    final latestClean = latest.split('+').first.split('-').first.trim();

    final currentParts = currentClean
        .split('.')
        .map((e) => int.tryParse(e.replaceAll(RegExp(r'\D'), '')) ?? 0)
        .toList();
    final latestParts = latestClean
        .split('.')
        .map((e) => int.tryParse(e.replaceAll(RegExp(r'\D'), '')) ?? 0)
        .toList();

    final maxLength = currentParts.length > latestParts.length
        ? currentParts.length
        : latestParts.length;

    for (int i = 0; i < maxLength; i++) {
      final cPart = i < currentParts.length ? currentParts[i] : 0;
      final lPart = i < latestParts.length ? latestParts[i] : 0;
      if (cPart < lPart) return -1;
      if (cPart > lPart) return 1;
    }

    if (currentClean == latestClean) {
      // If base versions are identical, compare build numbers if both have '+'
      final currentBuild = current.contains('+')
          ? int.tryParse(current.split('+').last)
          : null;
      final latestBuild = latest.contains('+')
          ? int.tryParse(latest.split('+').last)
          : null;
      if (currentBuild != null &&
          latestBuild != null &&
          currentBuild != latestBuild) {
        return currentBuild.compareTo(latestBuild);
      }
    }

    return 0;
  }

  @visibleForTesting
  static void showUpdateAvailableDialog(
    BuildContext context, {
    required String currentVersion,
    required String latestVersion,
    required String releaseNotes,
    required String downloadUrl,
    bool isIpaBuild = false,
  }) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        title: Row(
          children: [
            Icon(Icons.system_update_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(l10n?.updateAvailableTitle ?? 'Update Available'),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Text(
                        '${currentVersion.startsWith("v") ? "" : "v"}$currentVersion',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        '${latestVersion.startsWith("v") ? "" : "v"}$latestVersion',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n?.updateReleaseNotes ?? 'Release Notes:',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: Text(releaseNotes, style: theme.textTheme.bodyMedium),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n?.updateLater ?? 'Later'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.of(context).pop();
              await launchUrlString(
                downloadUrl,
                mode: LaunchMode.externalApplication,
              );
            },
            icon: Icon(
              isIpaBuild ? Icons.open_in_new_rounded : Icons.download_rounded,
              size: 18,
            ),
            label: Text(
              isIpaBuild
                  ? (l10n?.updateRedirectToRelease ?? 'View Release')
                  : (l10n?.updateDownload ?? 'Download'),
            ),
          ),
        ],
      ),
    );
  }

  @visibleForTesting
  static void showUpToDateDialog(
    BuildContext context, {
    required String currentVersion,
    bool isIpaBuild = false,
  }) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        title: Row(
          children: [
            Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(l10n?.updateUpToDate ?? 'Up to Date')),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            l10n?.updateUpToDateDesc(currentVersion) ??
                'You are running the latest version of Yet Another LuCI App (v$currentVersion).',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n?.actionConfirm ?? 'OK'),
          ),
        ],
      ),
    );
  }

  @visibleForTesting
  static void showAheadOfReleaseDialog(
    BuildContext context, {
    required String currentVersion,
    required String latestGithubVersion,
    bool isIpaBuild = false,
  }) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        title: Row(
          children: [
            Icon(Icons.verified_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(l10n?.updatePreReleaseTitle ?? 'Pre-Release Build'),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n?.updatePreReleaseNotice(currentVersion) ??
                    'You are running an unreleased / local build (v$currentVersion).',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                l10n?.updateNoUpdateRequired(latestGithubVersion) ??
                    'The latest public release on GitHub is v$latestGithubVersion. No update is required.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n?.actionConfirm ?? 'OK'),
          ),
        ],
      ),
    );
  }

  static void _showErrorDialog(BuildContext context, String message) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        title: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: LuciStatusColors.warningColor(context),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(l10n?.updateCheckFailedTitle ?? 'Check Failed'),
            ),
          ],
        ),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n?.actionConfirm ?? 'OK'),
          ),
        ],
      ),
    );
  }
}
