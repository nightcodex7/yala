// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yet_another_luci_app/widgets/local_network_permission_dialog.dart';

/// Service for checking and requesting Android 15+ (API 35+ / Target API 37) Local Network Permission
/// in full compliance with Google Play Restricted Permissions policy (answer/18100766).
class LocalNetworkPermissionService {
  static const MethodChannel _channel = MethodChannel(
    'com.nightcode.luci/local_network_permission',
  );

  /// Checks whether local network permission (`ACCESS_LOCAL_NETWORK`) is granted.
  /// Returns `true` on non-Android platforms or Android < 17.
  static Future<bool> isGranted() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        'checkLocalNetworkPermission',
      );
      return result ?? true;
    } on PlatformException catch (e) {
      debugPrint('Error checking local network permission: $e');
      return true;
    } on MissingPluginException {
      return true;
    }
  }

  /// Requests local network permission (`ACCESS_LOCAL_NETWORK`) from the user at runtime.
  /// Returns `true` if granted, or `true` on non-Android platforms / Android < 17.
  static Future<bool> requestPermission() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final bool? granted = await _channel.invokeMethod<bool>(
        'requestLocalNetworkPermission',
      );
      return granted ?? true;
    } on PlatformException catch (e) {
      debugPrint('Error requesting local network permission: $e');
      return true;
    } on MissingPluginException {
      return true;
    }
  }

  /// Opens the host OS application settings screen so the user can re-enable permissions.
  static Future<bool> openAppSettings() async {
    if (kIsWeb) return false;
    if (Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>(
          'openAppSettings',
        );
        return result ?? false;
      } on PlatformException catch (e) {
        debugPrint('Error opening app settings: $e');
        return false;
      } on MissingPluginException {
        return false;
      }
    } else if (Platform.isIOS) {
      try {
        final uri = Uri.parse('app-settings:');
        if (await canLaunchUrl(uri)) {
          return await launchUrl(uri);
        }
      } catch (_) {}
    }
    return false;
  }

  /// Checks and requests permission with an educational in-app prominent disclosure
  /// before triggering the native OS prompt, ensuring full compliance with Google Play
  /// policy (answer/18100766).
  ///
  /// If the user denies or permanently denies the permission, presents a recovery
  /// bottom sheet with a direct link to App Settings.
  static Future<bool> requestWithRationale(BuildContext context) async {
    if (kIsWeb || !Platform.isAndroid) return true;

    final alreadyGranted = await isGranted();
    if (alreadyGranted) return true;

    if (!context.mounted) return false;

    // 1. Prominent in-app disclosure prior to OS prompt
    final proceed = await LocalNetworkPermissionDialog.show(context);
    if (proceed != true) return false;

    // 2. Request system permission
    final granted = await requestPermission();
    if (granted) return true;

    // 3. User denied or permanently denied — show recovery sheet with settings link
    if (context.mounted) {
      await LocalNetworkPermissionDialog.show(
        context,
        isPermanentlyDenied: true,
      );
    }
    return false;
  }

  /// Helper to check and request permission if not already granted.
  static Future<bool> ensurePermissionGranted() async {
    final granted = await isGranted();
    if (!granted) {
      return await requestPermission();
    }
    return true;
  }
}
