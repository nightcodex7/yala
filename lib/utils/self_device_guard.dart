// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/widgets/luci_guardrail.dart';

class SelfDeviceGuard {
  static Set<String>? _cachedLocalIpsAndMacs;
  static DateTime? _lastCacheTime;

  /// Fetches all active local network IP addresses and MAC addresses of this device.
  static Future<Set<String>> getLocalDeviceAddresses() async {
    final now = DateTime.now();
    if (_cachedLocalIpsAndMacs != null &&
        _lastCacheTime != null &&
        now.difference(_lastCacheTime!) < const Duration(seconds: 10)) {
      return _cachedLocalIpsAndMacs!;
    }

    final addresses = <String>{};
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: true,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final clean = addr.address.toLowerCase().trim();
          if (clean.isNotEmpty) {
            addresses.add(clean);
          }
        }
      }
    } catch (_) {}

    _cachedLocalIpsAndMacs = addresses;
    _lastCacheTime = now;
    return addresses;
  }

  /// Normalizes MAC address string for comparison (e.g., 'AA:BB:CC:DD:EE:FF')
  static String normalizeMac(String mac) {
    return ClientNamingHelper.normalizeMac(mac);
  }

  /// Checks if target MAC or target IP belongs to the current device running this app.
  static Future<bool> isSelfDevice(
    String? targetMac, [
    String? targetIp,
  ]) async {
    final addresses = await getLocalDeviceAddresses();

    if (targetIp != null && targetIp.isNotEmpty && targetIp != 'N/A') {
      final cleanIp = targetIp.toLowerCase().trim();
      if (addresses.contains(cleanIp)) return true;
    }

    if (targetMac != null && targetMac.isNotEmpty && targetMac != 'N/A') {
      final normTargetMac = normalizeMac(targetMac);
      for (final addr in addresses) {
        if (normalizeMac(addr) == normTargetMac) return true;
      }
    }

    return false;
  }

  /// Prompts a guardrail confirmation dialog if the target MAC or IP belongs to this device.
  /// Returns `true` if it's safe to proceed (either not self-device, or user explicitly confirmed).
  static Future<bool> checkSelfActionGuardrail(
    BuildContext context, {
    required String actionName,
    String? targetMac,
    String? targetIp,
    String? targetHostname,
  }) async {
    final isSelf = await isSelfDevice(targetMac, targetIp);
    if (!isSelf || !context.mounted) return true;

    final displayName =
        targetHostname ?? targetIp ?? targetMac ?? 'Current Device';

    final confirmed = await LuciGuardrail.showConfirmation(
      context,
      title: 'Managing Device Warning',
      subtitle:
          'Target ($displayName) is the phone/device currently running this app.\n\nPerforming "$actionName" on your own managing device will sever your router connection and disconnect this app session.',
      confirmLabel: 'Proceed Anyway',
      cancelLabel: 'Cancel (Recommended)',
      icon: Icons.phonelink_setup_rounded,
      iconColor: Colors.amber.shade900,
      isDestructive: true,
      barrierDismissible: false,
    );

    if (context.mounted) {
      if (confirmed != true) {
        LuciToastManager.showGuardrail(
          context,
          'Action Aborted by Guardrail',
          subtitle:
              'Modification on active managing device cancelled for safety.',
        );
      } else {
        LuciToastManager.showWarning(
          context,
          'Self-Device Guardrail Bypassed',
          subtitle: 'Proceeding with "$actionName" on managing device.',
        );
      }
    }

    return confirmed == true;
  }
}
