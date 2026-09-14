// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

/// Flavor types supported by the build pipeline
enum AppFlavor { community, playstore }

/// Central configuration for build flavor detection and compile-time feature toggling.
class AppConfig {
  // GitHub repository URL - update this with your actual repository
  static const String githubRepositoryUrl =
      'https://github.com/nightcodex7/yala';

  // GitHub issues URL
  static const String githubIssuesUrl = '$githubRepositoryUrl/issues';

  // Legal & Privacy Policy URLs
  static const String privacyPolicyUrl =
      'https://nightcode.co.in/privacy-policy.html';
  static const String termsAndConditionsUrl =
      'https://nightcode.co.in/terms.html';
  static const String contactUrl = 'https://nightcode.co.in/contact.html';

  // Maintainer & Contact Configuration
  static const String appAuthor = '@nightcodex7';
  static const String appAuthorGithub = '@nightcodex7';
  static const String supportEmail = 'yala+support@nightcode.co.in';
  static const String feedbackEmail = 'yala+feedback@nightcode.co.in';
  static const String privacyEmail = 'yala+privacy@nightcode.co.in';
  static const String legalEmail = 'yala+legal@nightcode.co.in';

  // Upstream Attribution & GPLv3 Copyleft Licensing
  static const String upstreamAuthor = 'cogwheel0';
  static const String upstreamRepositoryUrl =
      'https://github.com/cogwheel0/luci-mobile';
  static const String licenseName = 'GNU General Public License v3.0';
  static const String licenseSpdx = 'GPL-3.0-or-later';
  static const String copyrightNotice =
      'Original work Copyright (C) 2025–2026 cogwheel0\nModifications Copyright (C) 2026 @nightcodex7';
  static const String gplWarrantyDisclaimer =
      'This program is free software: you can redistribute it and/or modify '
      'it under the terms of the GNU General Public License as published by '
      'the Free Software Foundation, either version 3 of the License, or '
      '(at your option) any later version.\n\n'
      'This program is distributed in the hope that it will be useful, '
      'but WITHOUT ANY WARRANTY; without even the implied warranty of '
      'MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the '
      'GNU General Public License for more details.';

  // Reviewer mode configuration
  static const String reviewerModeKey = 'reviewer_mode_enabled';
  static const String mockDataPath = 'assets/mock/';
  static const Duration reviewerModeActivationDuration = Duration(seconds: 5);
  static const String reviewerModeWatermark = 'Reviewer Mode';

  /// The current flavor set via compile-time `--dart-define=FLAVOR=community` or `playstore`.
  /// Defaults to `community` if unspecified.
  static const String _flavorStr = String.fromEnvironment(
    'FLAVOR',
    defaultValue: 'community',
  );

  /// Whether this build is verified as an official release build.
  /// Controlled via compile-time flag `--dart-define=OFFICIAL_BUILD=true`.
  /// Defaults to `false` for local developer builds, debug builds, and unofficial forks.
  static bool get isOfficialBuild =>
      const bool.fromEnvironment('OFFICIAL_BUILD', defaultValue: false);

  /// Whether voluntary Support the Developer feature is enabled in UI.
  /// Enabled via compile-time flag `--dart-define=ENABLE_SUPPORT_DEV=true` or in debug mode (`kDebugMode`).
  /// Disabled by default in release builds.
  static const bool isSupportDevEnabled = false;


  static AppFlavor get flavor {
    if (_flavorStr.toLowerCase() == 'playstore') {
      return AppFlavor.playstore;
    }
    return AppFlavor.community;
  }

  /// Whether the current build is the FOSS community flavor.
  static bool get isCommunityFlavor => flavor == AppFlavor.community;

  /// Human-readable build channel description.
  static String get flavorName =>
      flavor == AppFlavor.playstore ? 'Play Store' : 'Community';
}
