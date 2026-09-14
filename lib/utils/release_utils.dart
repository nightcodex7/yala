// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

enum RouterDistribution {
  openWrt,
  immortalWrt,
  glInet,
  iStoreOS,
  xWrt,
  ddWrt,
  tomato,
  pandoraBox,
  lede,
  custom,
}

/// Parsed firmware release metadata including distribution, version, and release channel.
class FirmwareReleaseInfo {
  final RouterDistribution distribution;
  final String distributionName;
  final String version;
  final String channel;
  final String rawDescription;
  final String? baseOpenWrtVersion;

  const FirmwareReleaseInfo({
    required this.distribution,
    required this.distributionName,
    required this.version,
    required this.channel,
    required this.rawDescription,
    this.baseOpenWrtVersion,
  });

  /// Formatted display string e.g. "ImmortalWrt 23.05.3" or "GL.iNet 4.6.2"
  String get displayName {
    if (version.isEmpty || version == 'N/A') {
      return distributionName;
    }
    if (version.toLowerCase().startsWith(distributionName.toLowerCase())) {
      return version;
    }
    return '$distributionName $version';
  }
}

/// Shared release channel derivation utility.
///
/// Inspects an OpenWrt `/etc/os-release`, `/etc/openwrt_release`, or `ubus`
/// response payload (Map or String) to determine if the router firmware is
/// running `snapshot`, `beta`, `alpha`, `rc`, `testing`, or `stable`.
String deriveReleaseChannel(dynamic releaseInput) {
  if (releaseInput == null) {
    return 'stable';
  }

  String combined = '';
  if (releaseInput is Map) {
    if (releaseInput.isEmpty) return 'stable';
    final buffer = StringBuffer();
    for (final entry in releaseInput.entries) {
      if (entry.value != null) {
        buffer
          ..write(' ')
          ..write(entry.key.toString().toLowerCase())
          ..write('=')
          ..write(entry.value.toString().toLowerCase());
      }
    }
    combined = buffer.toString();
  } else {
    combined = releaseInput.toString().toLowerCase().trim();
  }

  if (combined.isEmpty) {
    return 'stable';
  }

  // 1. SNAPSHOT check (snapshot, dev, master, git, nightly)
  if (combined.contains('snapshot') ||
      combined.contains('git-') ||
      combined.contains('dev') ||
      combined.contains('master') ||
      combined.contains('nightly')) {
    return 'snapshot';
  }

  // Pure revision version check (e.g. version="r28597-d3e1c1fba8")
  final hasSemver = RegExp(r'\b\d+\.\d+').hasMatch(combined);
  final hasRevisionOnly = RegExp(r'\b[rR]\d{4,6}-').hasMatch(combined);
  if (hasRevisionOnly && !hasSemver) {
    return 'snapshot';
  }

  // 2. RC (Release Candidate) check
  // Matches: -rc1, .rc1, _rc1, -rc-1, rc1, rc2, rc3, -rc, rc.1, release-candidate
  final rcRegex = RegExp(
    r'(?:^|[\s\-_.\/])rc[\d\-_.]*|release[\-_.]?candidate',
    caseSensitive: false,
  );
  if (combined.contains('-rc') ||
      combined.contains('_rc') ||
      combined.contains('.rc') ||
      rcRegex.hasMatch(combined)) {
    // Avoid false positives like "source", "search", "arch"
    if (!combined.contains('source') &&
        !combined.contains('search') &&
        !combined.contains('arch')) {
      return 'rc';
    }
  }

  // 3. BETA check
  if (combined.contains('beta')) {
    return 'beta';
  }

  // 4. ALPHA check
  if (combined.contains('alpha')) {
    return 'alpha';
  }

  // 5. TESTING check
  if (combined.contains('testing')) {
    return 'testing';
  }

  return 'stable';
}

/// Derives comprehensive distribution and release information from board/release payloads.
FirmwareReleaseInfo deriveDistributionInfo(
  dynamic releaseInput, {
  String? model,
  String? descriptionOverride,
}) {
  Map<String, dynamic> releaseMap = {};
  String rawString = '';

  if (releaseInput is Map<String, dynamic>) {
    releaseMap = releaseInput;
  } else if (releaseInput is Map) {
    releaseMap = Map<String, dynamic>.from(releaseInput);
  } else if (releaseInput != null) {
    rawString = releaseInput.toString();
  }

  final distRaw = (releaseMap['distribution'] ?? '').toString().trim();
  final versionRaw = (releaseMap['version'] ?? '').toString().trim();
  final descRaw =
      (descriptionOverride ?? releaseMap['description'] ?? rawString)
          .toString()
          .trim();
  final modelRaw = (model ?? '').trim();

  final combinedSearch = '$distRaw $versionRaw $descRaw $modelRaw'
      .toLowerCase();

  RouterDistribution dist = RouterDistribution.openWrt;
  String distName = 'OpenWrt';

  if (combinedSearch.contains('immortalwrt')) {
    dist = RouterDistribution.immortalWrt;
    distName = 'ImmortalWrt';
  } else if (combinedSearch.contains('gl.inet') ||
      combinedSearch.contains('gl-inet') ||
      combinedSearch.contains('glinet') ||
      modelRaw.toLowerCase().startsWith('gl-')) {
    dist = RouterDistribution.glInet;
    distName = 'GL.iNet';
  } else if (combinedSearch.contains('istoreos')) {
    dist = RouterDistribution.iStoreOS;
    distName = 'iStoreOS';
  } else if (combinedSearch.contains('x-wrt') ||
      combinedSearch.contains('xwrt')) {
    dist = RouterDistribution.xWrt;
    distName = 'X-WRT';
  } else if (combinedSearch.contains('dd-wrt') ||
      combinedSearch.contains('ddwrt')) {
    dist = RouterDistribution.ddWrt;
    distName = 'DD-WRT';
  } else if (combinedSearch.contains('freshtomato') ||
      combinedSearch.contains('tomato')) {
    dist = RouterDistribution.tomato;
    distName = combinedSearch.contains('freshtomato')
        ? 'FreshTomato'
        : 'Tomato';
  } else if (combinedSearch.contains('pandorabox')) {
    dist = RouterDistribution.pandoraBox;
    distName = 'PandoraBox';
  } else if (combinedSearch.contains('lede')) {
    dist = RouterDistribution.lede;
    distName = 'LEDE';
  } else if (distRaw.isNotEmpty && distRaw != 'OpenWrt') {
    dist = RouterDistribution.custom;
    distName = distRaw;
  }

  // Extract base OpenWrt version if embedded in GL.iNet / derivative descriptions
  String? baseOpenWrt;
  final baseMatch = RegExp(
    r'OpenWrt\s+(\d+\.\d+(?:\.\d+)?)',
    caseSensitive: false,
  ).firstMatch(descRaw);
  if (baseMatch != null && dist != RouterDistribution.openWrt) {
    baseOpenWrt = 'OpenWrt ${baseMatch.group(1)}';
  }

  String finalVersion = versionRaw.isNotEmpty ? versionRaw : 'N/A';
  if (finalVersion == 'N/A' && rawString.isNotEmpty) {
    final vMatch = RegExp(
      r'\b\d+\.\d+(?:\.\d+)?(?:-[\w.-]+)?',
    ).firstMatch(rawString);
    if (vMatch != null) {
      finalVersion = vMatch.group(0)!;
    } else {
      finalVersion = rawString;
    }
  }

  final channel = deriveReleaseChannel(
    releaseMap.isNotEmpty ? releaseMap : descRaw,
  );

  return FirmwareReleaseInfo(
    distribution: dist,
    distributionName: distName,
    version: finalVersion,
    channel: channel,
    rawDescription: descRaw.isNotEmpty ? descRaw : '$distName $finalVersion',
    baseOpenWrtVersion: baseOpenWrt,
  );
}
