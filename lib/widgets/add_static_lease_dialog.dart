// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/modules/dhcp_dns/models/dhcp_dns_info.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/utils/os_platform_integration.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';

/// Reusable dialog to create or edit a DHCP static IP reservation (host mapping).
class AddStaticLeaseDialog extends StatefulWidget {
  final String? macAddress;
  final String? initialIp;
  final String? initialIp6;
  final String? initialDuid;
  final String? initialHostname;
  final Client? client;
  final List<Client>? allClients;
  final DhcpStaticMapping? existingMapping;
  final VoidCallback? onSaved;

  const AddStaticLeaseDialog({
    super.key,
    this.macAddress,
    this.initialIp,
    this.initialIp6,
    this.initialDuid,
    this.initialHostname,
    this.client,
    this.allClients,
    this.existingMapping,
    this.onSaved,
  });

  @override
  State<AddStaticLeaseDialog> createState() => _AddStaticLeaseDialogState();
}

class _AddStaticLeaseDialogState extends State<AddStaticLeaseDialog> {
  late TextEditingController _macController;
  late TextEditingController _nameController;
  late TextEditingController _ipController;
  late TextEditingController _ip6Controller;
  late TextEditingController _duidController;
  late TextEditingController _customLeaseController;

  String _selectedLeasePreset = '12h';
  bool _submittedOnce = false;
  bool _macTouched = false;
  bool _nameTouched = false;
  bool _ipTouched = false;
  bool _ip6Touched = false;
  bool _duidTouched = false;
  bool _customLeaseTouched = false;
  // Whether the optional IPv6/DUID section is expanded by the user
  bool _showIp6Section = false;

  String? _rawMacError;
  String? _rawNameError;
  String? _rawIpError;
  String? _rawIp6Error;
  String? _rawDuidError;
  String? _rawLeaseError;

  String? _macError;
  String? _nameError;
  String? _ipError;
  String? _ip6Error;
  String? _duidError;
  String? _leaseTimeError;

  String? _clipboardMac;

  final List<Map<String, String>> _leasePresets = [
    {'label': '12 Hours (Default)', 'value': '12h'},
    {'label': '24 Hours (1 Day)', 'value': '24h'},
    {'label': '7 Days (1 Week)', 'value': '7d'},
    {'label': 'Infinite (Permanent)', 'value': 'infinite'},
    {'label': 'Custom Duration...', 'value': 'custom'},
  ];

  DhcpStaticMapping? _detectedMapping;

  late final String _initialMacText;
  late final String _initialNameText;
  late final String _initialIpText;
  late final String _initialLeasePreset;
  late final String _initialCustomLeaseText;

  bool get _isEditing =>
      _detectedMapping != null ||
      widget.existingMapping != null ||
      (widget.client != null && widget.client!.isStatic);

  bool get _hasChanges {
    if (!_isEditing) return true;

    final currentMac = _normMac(_effectiveMac);
    final currentName = _nameController.text.trim();
    final currentIp = _ipController.text.trim();
    final currentPreset = _selectedLeasePreset;
    final currentCustomLease = _customLeaseController.text.trim();

    if (currentMac != _initialMacText) return true;
    if (currentName != _initialNameText) return true;
    if (currentIp != _initialIpText) return true;
    if (currentPreset != _initialLeasePreset) return true;
    if (currentPreset == 'custom' &&
        currentCustomLease != _initialCustomLeaseText) {
      return true;
    }

    return false;
  }

  String get _effectiveMac {
    if (widget.macAddress != null && widget.macAddress!.trim().isNotEmpty) {
      return widget.macAddress!.trim();
    }
    if (widget.existingMapping != null &&
        widget.existingMapping!.macAddress.isNotEmpty) {
      return widget.existingMapping!.macAddress.trim();
    }
    if (widget.client != null && widget.client!.macAddress.isNotEmpty) {
      return widget.client!.macAddress.trim();
    }
    try {
      return _macController.text.trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> _checkClipboardForMac() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data != null && data.text != null && data.text!.trim().isNotEmpty) {
        final parsed = _parseFlexibleMac(data.text!);
        if (parsed != null && mounted) {
          setState(() {
            _clipboardMac = parsed;
          });
        }
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    final client = widget.client;

    final initialMac =
        (widget.macAddress != null && widget.macAddress!.trim().isNotEmpty)
        ? widget.macAddress!.trim()
        : ((widget.existingMapping != null &&
                  widget.existingMapping!.macAddress.isNotEmpty)
              ? widget.existingMapping!.macAddress.trim()
              : ((client != null && client.macAddress.isNotEmpty)
                    ? client.macAddress.trim()
                    : ''));

    if (widget.existingMapping != null) {
      _detectedMapping = widget.existingMapping;
    } else if (initialMac.isNotEmpty) {
      _detectedMapping = AppState.instance.findStaticLeaseByMac(initialMac);
    }
    final mapping = _detectedMapping;
    _macController = TextEditingController(text: initialMac.toUpperCase());

    String cleanInitialName(String? raw) {
      if (raw == null) return '';
      final trimmed = raw.trim();
      if (trimmed.isEmpty ||
          trimmed == 'Anonymous Device' ||
          trimmed == 'Anonymous IPv6 Host' ||
          trimmed == 'Unknown' ||
          trimmed == 'N/A' ||
          trimmed == '*') {
        return '';
      }
      return trimmed.replaceAll(RegExp(r'\s+'), '-');
    }

    final rawNameCandidate = (mapping != null && mapping.hostname.isNotEmpty)
        ? mapping.hostname
        : ((widget.initialHostname != null &&
                  widget.initialHostname!.isNotEmpty)
              ? widget.initialHostname!
              : ((client != null &&
                        client.displayName.isNotEmpty &&
                        client.displayName != client.macAddress &&
                        client.displayName != 'Unknown')
                    ? client.displayName
                    : (client != null && client.hostname != 'Unknown'
                          ? client.hostname
                          : '')));

    final initialName = cleanInitialName(rawNameCandidate);
    _nameController = TextEditingController(text: initialName);

    final initialIpVal =
        (mapping != null &&
            mapping.ipAddress.isNotEmpty &&
            mapping.ipAddress != 'N/A')
        ? mapping.ipAddress
        : ((widget.initialIp != null && _isValidIPv4(widget.initialIp!))
              ? widget.initialIp!
              : ((client != null && _isValidIPv4(client.ipAddress))
                    ? client.ipAddress
                    : ''));
    _ipController = TextEditingController(text: initialIpVal);

    // IPv6: only pre-fill when explicitly provided via existingMapping or initialIp6 param.
    // Do NOT auto-populate from client's active IPv6 — user must opt-in via the checkbox.
    final initialIp6Val = (mapping != null && mapping.ip6Address.isNotEmpty)
        ? mapping.ip6Address.trim()
        : ((widget.initialIp6 != null && widget.initialIp6!.trim().isNotEmpty)
              ? widget.initialIp6!.trim()
              : '');
    _ip6Controller = TextEditingController(text: initialIp6Val);

    // DUID: only pre-fill when explicitly provided via existingMapping or initialDuid param.
    final initialDuidVal = (mapping != null && mapping.duid.isNotEmpty)
        ? mapping.duid.trim()
        : ((widget.initialDuid != null && widget.initialDuid!.trim().isNotEmpty)
              ? widget.initialDuid!.trim()
              : '');
    _duidController = TextEditingController(text: initialDuidVal.toUpperCase());

    // Expand IPv6 section if there is already data (editing existing mapping)
    _showIp6Section = initialIp6Val.isNotEmpty || initialDuidVal.isNotEmpty;

    String initCustomText = '12h';
    if (mapping != null && mapping.leaseTime.trim().isNotEmpty) {
      final rawLt = mapping.leaseTime.trim().toLowerCase();
      if (['12h', '24h', '7d', 'infinite'].contains(rawLt)) {
        _selectedLeasePreset = rawLt;
      } else {
        _selectedLeasePreset = 'custom';
        initCustomText = mapping.leaseTime.trim();
      }
    }
    _customLeaseController = TextEditingController(text: initCustomText);

    _initialMacText = _normMac(initialMac);
    _initialNameText = initialName.trim();
    _initialIpText = initialIpVal.trim();
    _initialLeasePreset = _selectedLeasePreset;
    _initialCustomLeaseText = initCustomText.trim();

    _macController.addListener(() {
      if (!_macTouched && _macController.text.isNotEmpty) {
        _macTouched = true;
      }
      _validateInputs();
    });
    _nameController.addListener(() {
      if (!_nameTouched && _nameController.text.isNotEmpty) {
        _nameTouched = true;
      }
      _validateInputs();
    });
    _ipController.addListener(() {
      if (!_ipTouched && _ipController.text.isNotEmpty) {
        _ipTouched = true;
      }
      _validateInputs();
    });
    _ip6Controller.addListener(() {
      if (!_ip6Touched && _ip6Controller.text.isNotEmpty) {
        _ip6Touched = true;
      }
      _validateInputs();
    });
    _duidController.addListener(() {
      if (!_duidTouched && _duidController.text.isNotEmpty) {
        _duidTouched = true;
      }
      _validateInputs();
    });
    _customLeaseController.addListener(() {
      if (!_customLeaseTouched && _customLeaseController.text.isNotEmpty) {
        _customLeaseTouched = true;
      }
      _validateInputs();
    });

    _checkClipboardForMac();

    WidgetsBinding.instance.addPostFrameCallback((_) => _validateInputs());
  }

  @override
  void dispose() {
    _macController.dispose();
    _nameController.dispose();
    _ipController.dispose();
    _ip6Controller.dispose();
    _duidController.dispose();
    _customLeaseController.dispose();
    super.dispose();
  }

  bool _isValidIPv4(String ip) {
    if (ip == 'N/A' || ip.trim().isEmpty) return false;
    final reg = RegExp(
      r'^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.){3}(25[0-5]|(2[0-4]|1\d|[1-9]|)\d)$',
    );
    return reg.hasMatch(ip.trim());
  }

  String? _parseFlexibleMac(String input) {
    final trimmed = input.trim();
    final pairReg = RegExp(r'(?:[0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}');
    final matchPair = pairReg.firstMatch(trimmed);
    if (matchPair != null) {
      return matchPair.group(0)!.toUpperCase().replaceAll('-', ':');
    }

    final ciscoReg = RegExp(r'[0-9a-fA-F]{4}\.[0-9a-fA-F]{4}\.[0-9a-fA-F]{4}');
    final matchCisco = ciscoReg.firstMatch(trimmed);
    if (matchCisco != null) {
      final cleaned = matchCisco.group(0)!.replaceAll('.', '');
      final sb = StringBuffer();
      for (int i = 0; i < 12; i += 2) {
        if (i > 0) sb.write(':');
        sb.write(cleaned.substring(i, i + 2).toUpperCase());
      }
      return sb.toString();
    }

    final raw12Reg = RegExp(r'\b[0-9a-fA-F]{12}\b');
    final match12 = raw12Reg.firstMatch(trimmed);
    if (match12 != null) {
      final cleaned = match12.group(0)!;
      final sb = StringBuffer();
      for (int i = 0; i < 12; i += 2) {
        if (i > 0) sb.write(':');
        sb.write(cleaned.substring(i, i + 2).toUpperCase());
      }
      return sb.toString();
    }

    return null;
  }

  bool _isValidMac(String mac) {
    if (mac.trim().isEmpty) return false;
    final parsed = _parseFlexibleMac(mac);
    if (parsed != null) return true;
    final reg = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$');
    return reg.hasMatch(mac.trim());
  }

  String _normMac(String mac) {
    final parsed = _parseFlexibleMac(mac);
    if (parsed != null) return parsed;
    return mac.toUpperCase().replaceAll('-', ':');
  }

  Future<void> _pasteMacFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data != null && data.text != null && data.text!.isNotEmpty) {
        final pasted = data.text!;
        final parsed = _parseFlexibleMac(pasted);
        if (parsed != null) {
          setState(() {
            _macTouched = true;
            _macController.text = parsed;
          });
          _validateInputs();
          if (mounted) {
            unawaited(
              OsPlatformIntegration.triggerHaptic(OsHapticType.selection),
            );
            context.showToastSuccess('Pasted MAC: $parsed');
          }
          return;
        }
      }
      if (mounted) {
        unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));
        context.showToastWarning(
          'Clipboard does not contain a valid MAC address.',
        );
      }
    } catch (_) {
      if (mounted) {
        context.showToastWarning('Unable to read clipboard.');
      }
    }
  }

  bool _isValidIPv6OrHostId(String ip6) {
    final trimmed = ip6.trim();
    if (trimmed.isEmpty) return true;
    if (RegExp(r'^(::)?[0-9a-fA-F]{1,4}$').hasMatch(trimmed)) return true;
    try {
      final unbracketed = (trimmed.startsWith('[') && trimmed.endsWith(']'))
          ? trimmed.substring(1, trimmed.length - 1)
          : trimmed;
      Uri.parseIPv6Address(unbracketed.split('/').first);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _isValidDuid(String duid) {
    final trimmed = duid.trim();
    if (trimmed.isEmpty) return true;
    final clean = trimmed.replaceAll(':', '').replaceAll('-', '');
    return clean.length >= 6 &&
        clean.length % 2 == 0 &&
        RegExp(r'^[0-9a-fA-F]+$').hasMatch(clean);
  }

  void _validateInputs() {
    final mac = _effectiveMac;
    final duid = _duidController.text.trim();
    final name = _nameController.text.trim();
    final ip = _ipController.text.trim();
    final ip6 = _ip6Controller.text.trim();
    final customLease = _customLeaseController.text.trim();

    String? macErr;
    String? duidErr;
    String? nameErr;
    String? ipErr;
    String? ip6Err;
    String? leaseErr;

    // 1. MAC Address / DUID validation
    if (mac.isEmpty && duid.isEmpty) {
      macErr = 'Provide a MAC address or DUID identifier';
    } else {
      if (mac.isNotEmpty && !_isValidMac(mac) && !mac.startsWith('DUID:')) {
        macErr = 'Enter a valid MAC address (e.g. AA:BB:CC:DD:EE:FF)';
      }
      if (duid.isNotEmpty && !_isValidDuid(duid)) {
        duidErr = 'Enter a valid DUID hex string';
      }
    }

    // 2. Hostname validation
    if (name.isEmpty) {
      nameErr = 'Hostname cannot be empty';
    } else if (RegExp(r'\s').hasMatch(name)) {
      nameErr = 'Hostname cannot contain spaces';
    } else if (!RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(name)) {
      nameErr = 'Use only letters, numbers, hyphens, and dots';
    }

    // 3. IPv4 / IPv6 validation & conflict guardrails
    if (ip.isEmpty && ip6.isEmpty) {
      ipErr = 'Provide at least an IPv4 or IPv6 address reservation';
    } else {
      if (ip.isNotEmpty) {
        if (!_isValidIPv4(ip)) {
          ipErr = 'Enter a valid IPv4 address (e.g. 192.168.1.150)';
        } else {
          final appState = AppState.instance;
          final selectedRouter = appState.selectedRouter;
          final currentMacNorm = _normMac(mac);

          // Guardrail A: Check router gateway IP
          if (selectedRouter != null && selectedRouter.ipAddress.trim() == ip) {
            ipErr = 'Conflict: $ip is the router\'s gateway address';
          }

          // Guardrail B: Check active clients in client list
          if (ipErr == null && widget.allClients != null) {
            for (final other in widget.allClients!) {
              if (_normMac(other.macAddress) != currentMacNorm &&
                  other.ipAddress.trim() == ip) {
                ipErr =
                    'Conflict: $ip is used by "${other.displayName}" (${other.macAddress})';
                break;
              }
            }
          }

          // Guardrail C: Check host hints / static leases in router configuration
          if (ipErr == null) {
            final hostHints =
                appState.dashboardData?['hostHints'] as Map<String, dynamic>? ??
                {};
            hostHints.forEach((hMac, info) {
              if (ipErr != null) return;
              if (_normMac(hMac) != currentMacNorm) {
                final staticIp = info['staticLeaseIp']?.toString();
                final ipaddrs = info['ipaddrs'] as List?;
                final hintName =
                    info['name']?.toString() ??
                    info['staticLeaseName']?.toString() ??
                    hMac;
                if (staticIp == ip ||
                    (ipaddrs != null && ipaddrs.contains(ip))) {
                  ipErr =
                      'Conflict: $ip is reserved for static lease "$hintName" ($hMac)';
                }
              }
            });
          }
        }
      }

      if (ip6.isNotEmpty && !_isValidIPv6OrHostId(ip6)) {
        ip6Err =
            'Enter a valid IPv6 address or Host ID (e.g. 2405:201::100 or ::100)';
      }
    }

    // 4. Lease time validation
    if (_selectedLeasePreset == 'custom') {
      if (customLease.isEmpty) {
        leaseErr = 'Specify custom lease duration (e.g. 2h, 30m, 3d)';
      } else if (customLease.toLowerCase() != 'infinite' &&
          !RegExp(
            r'^\d+[smhdw]$',
            caseSensitive: false,
          ).hasMatch(customLease)) {
        leaseErr =
            'Invalid format (use e.g. 30m, 2h, 12h, 1d, 7w, or infinite)';
      }
    }

    _rawMacError = macErr;
    _rawDuidError = duidErr;
    _rawNameError = nameErr;
    _rawIpError = ipErr;
    _rawIp6Error = ip6Err;
    _rawLeaseError = leaseErr;

    if (mounted) {
      setState(() {
        _macError = (_submittedOnce || _macTouched || mac.isNotEmpty)
            ? macErr
            : null;
        _duidError = (_submittedOnce || _duidTouched || duid.isNotEmpty)
            ? duidErr
            : null;
        _nameError = (_submittedOnce || _nameTouched || name.isNotEmpty)
            ? nameErr
            : null;
        _ipError = (_submittedOnce || _ipTouched || ip.isNotEmpty)
            ? ipErr
            : null;
        _ip6Error = (_submittedOnce || _ip6Touched || ip6.isNotEmpty)
            ? ip6Err
            : null;
        _leaseTimeError =
            (_submittedOnce || _customLeaseTouched || customLease.isNotEmpty)
            ? leaseErr
            : null;
      });
    }
  }

  Future<void> _submit() async {
    if (ActionRateLimiter.isRateLimited(
      'add_static_lease_submit',
      cooldown: const Duration(milliseconds: 1200),
    )) {
      if (mounted) {
        context.showToastWarning('Save in progress. Please wait a moment...');
      }
      return;
    }

    _submittedOnce = true;
    _validateInputs();
    if (_rawMacError != null ||
        _rawDuidError != null ||
        _rawNameError != null ||
        _rawIpError != null ||
        _rawIp6Error != null ||
        _rawLeaseError != null) {
      if (mounted) {
        context.showToastWarning('Please fix highlighted form errors.');
      }
      return;
    }

    final targetMac = _effectiveMac;
    final hostname = _nameController.text.trim();
    final targetIp = _ipController.text.trim();
    final targetIp6 = _ip6Controller.text.trim();
    final duid = _duidController.text.trim();
    final leaseTime = _selectedLeasePreset == 'custom'
        ? _customLeaseController.text.trim()
        : _selectedLeasePreset;
    final isEditMode = _isEditing;
    final onSavedCallback = widget.onSaved;

    final liveIp = widget.client?.ipAddress ?? widget.initialIp;
    final hasIpDiscrepancy =
        liveIp != null &&
        liveIp.isNotEmpty &&
        liveIp != 'N/A' &&
        liveIp != targetIp &&
        (widget.client == null || widget.client!.isConnected);

    unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.medium));

    // Capture parent page context before popping dialog to preserve mounted context for toasts
    final parentContext = Navigator.of(context).context;
    Navigator.of(context).pop();

    final actionKey = 'static_lease_$targetMac';

    // Show non-intrusive context-aware progress toast with rotating loader
    if (parentContext.mounted) {
      parentContext.showToastLoading(
        isEditMode
            ? 'Updating static lease for $hostname...'
            : 'Creating static lease for $hostname...',
        actionKey: actionKey,
      );
    }

    // Perform backend RPC update in background with exception guardrail
    try {
      final appState = AppState.instance;
      final success = await appState.addStaticLease(
        macAddress: targetMac,
        targetIp: targetIp,
        hostname: hostname,
        targetIp6: targetIp6.isNotEmpty ? targetIp6 : null,
        duid: duid.isNotEmpty ? duid : null,
        leaseTime: leaseTime,
        context: parentContext.mounted ? parentContext : null,
      );

      if (parentContext.mounted) {
        if (success) {
          unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.medium));
          parentContext.showToastSuccess(
            isEditMode
                ? 'Updated static lease: $hostname ($targetIp)'
                : 'Static lease reserved: $hostname ($targetIp)',
            actionKey: actionKey,
          );
          onSavedCallback?.call();

          if (hasIpDiscrepancy) {
            unawaited(
              _promptLiveClientRefresh(
                parentContext,
                targetMac,
                hostname,
                liveIp,
                targetIp,
              ),
            );
          }
        } else {
          unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));
          parentContext.showToastError(
            'Failed to ${isEditMode ? "update" : "create"} static lease for $hostname.',
            actionKey: actionKey,
          );
        }
      }
    } catch (e) {
      if (parentContext.mounted) {
        unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));
        parentContext.showToastError(
          'Failed to ${isEditMode ? "update" : "create"} static lease for $hostname.',
          subtitle: 'Please check your router connection and try again.',
          actionKey: actionKey,
        );
      }
    }
  }

  Future<void> _deleteLease() async {
    final targetMac = _effectiveMac;
    final hostname = _nameController.text.trim();
    final targetIp = _ipController.text.trim();
    final duid = _duidController.text.trim();

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
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_outline,
                color: Colors.redAccent,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Remove Static Lease',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to remove the static IP reservation for "$hostname" ($targetMac)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Remove Reservation'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.medium));
    final parentContext = Navigator.of(context).context;
    final onSavedCallback = widget.onSaved;
    Navigator.of(context).pop();

    final actionKey = 'remove_lease_$targetMac';
    if (parentContext.mounted) {
      parentContext.showToastLoading(
        'Removing static lease for $hostname...',
        actionKey: actionKey,
      );
    }

    try {
      final appState = AppState.instance;
      final success = await appState.deleteStaticLease(
        macAddress: targetMac,
        targetIp: targetIp.isNotEmpty && targetIp != 'N/A' ? targetIp : null,
        hostname:
            hostname.isNotEmpty && hostname != 'Unknown' ? hostname : null,
        duid: duid.isNotEmpty && duid != 'N/A' ? duid : null,
        context: parentContext.mounted ? parentContext : null,
      );

      if (parentContext.mounted) {
        if (success) {
          appState.invalidateStaticLeasesCache();
          unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.medium));
          parentContext.showToastSuccess(
            'Static lease removed for $hostname.',
            actionKey: actionKey,
          );
          onSavedCallback?.call();
        } else {
          unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));
          parentContext.showToastError(
            'Failed to remove static lease for $hostname.',
            actionKey: actionKey,
          );
        }
      }
    } catch (_) {
      if (parentContext.mounted) {
        unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));
        parentContext.showToastError(
          'Failed to remove static lease for $hostname.',
          actionKey: actionKey,
        );
      }
    }
  }

  static Future<void> _promptLiveClientRefresh(
    BuildContext context,
    String macAddress,
    String hostname,
    String liveIp,
    String reservedIp,
  ) async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Icon(
          Icons.sync_problem_rounded,
          color: theme.colorScheme.primary,
          size: 36,
        ),
        title: const Text('Refresh Client IP Connection?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The reserved static IP ($reservedIp) differs from the client\'s current active IP ($liveIp).',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'Would you like to force refresh $hostname ($macAddress) now so it acquires its new static IP immediately?',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.3,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Targeted Action: Only $hostname will briefly reconnect. Zero disruption to other devices.',
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
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
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Current IP (Later)'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Refresh IP Now'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final res = await AppState.instance.refreshClientConnection(
        macAddress: macAddress,
        context: context,
      );
      if (context.mounted) {
        if (res) {
          context.showToastSuccess(
            'Connection refresh signal sent for $hostname.',
            subtitle:
                'Client deauthenticated. Toggle Wi-Fi on the device if it does not acquire its new IP in 10s.',
          );
        } else {
          context.showToastWarning(
            'Failed to trigger connection refresh for $macAddress.',
          );
        }
      }
    }
  }

  Future<void> _pickLeaseExpiryDateTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now.add(const Duration(minutes: 5)),
      lastDate: now.add(const Duration(days: 3650)),
      helpText: 'Select Static Lease Expiration Date',
    );

    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
      helpText: 'Select Static Lease Expiration Time',
    );

    if (pickedTime == null || !mounted) return;

    final expiryDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    final diff = expiryDateTime.difference(now);
    if (diff.inSeconds < 120) {
      if (mounted) {
        context.showToastWarning(
          'Lease expiry must be at least 2 minutes in the future.',
        );
      }
      return;
    }

    String formatted;
    if (diff.inDays >= 7 && diff.inDays % 7 == 0) {
      formatted = '${diff.inDays ~/ 7}w';
    } else if (diff.inDays >= 1) {
      formatted = '${diff.inDays}d';
    } else if (diff.inHours >= 1) {
      formatted = '${diff.inHours}h';
    } else {
      formatted = '${diff.inMinutes}m';
    }

    setState(() {
      _customLeaseController.text = formatted;
    });
    _validateInputs();
  }

  String _findSuggestedFreeIp(DhcpDnsOverview dhcpOverview) {
    final subnets = dhcpOverview.configuredSubnets;

    final targetIp =
        widget.initialIp ??
        widget.existingMapping?.ipAddress ??
        widget.client?.ipAddress ??
        _ipController.text.trim();

    SubnetInfo primarySubnet;
    if (_isValidIPv4(targetIp)) {
      primarySubnet = subnets.firstWhere(
        (s) => s.containsIp(targetIp),
        orElse: () {
          final parts = targetIp.split('.');
          final gw = '${parts[0]}.${parts[1]}.${parts[2]}.1';
          return SubnetInfo(
            interfaceName: 'lan',
            gatewayIp: gw,
            netmask: '255.255.255.0',
            poolStart: 100,
            poolLimit: 150,
          );
        },
      );
    } else {
      primarySubnet = subnets.firstWhere(
        (s) => s.interfaceName.toLowerCase() == 'lan',
        orElse: () => subnets.isNotEmpty
            ? subnets.first
            : const SubnetInfo(
                interfaceName: 'lan',
                gatewayIp: '192.168.1.1',
                netmask: '255.255.255.0',
                poolStart: 100,
                poolLimit: 150,
              ),
      );
    }

    final gwIp = primarySubnet.gatewayIp.trim();
    final parts = gwIp.split('.');
    if (parts.length != 4) return '192.168.1.150';

    final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';

    final usedIps = <String>{gwIp};

    for (final lease in dhcpOverview.activeLeases) {
      if (lease.ipAddress.isNotEmpty && lease.ipAddress != 'N/A') {
        usedIps.add(lease.ipAddress.trim());
      }
    }

    for (final mapping in dhcpOverview.staticMappings) {
      if (mapping.ipAddress.isNotEmpty && mapping.ipAddress != 'N/A') {
        usedIps.add(mapping.ipAddress.trim());
      }
    }

    if (widget.allClients != null) {
      for (final client in widget.allClients!) {
        if (client.ipAddress.isNotEmpty && client.ipAddress != 'N/A') {
          usedIps.add(client.ipAddress.trim());
        }
      }
    }

    final hostHints =
        AppState.instance.dashboardData?['hostHints']
            as Map<String, dynamic>? ??
        {};
    hostHints.forEach((_, info) {
      final staticIp = info['staticLeaseIp']?.toString();
      if (staticIp != null && staticIp.isNotEmpty) usedIps.add(staticIp.trim());
      final ipaddrs = info['ipaddrs'] as List?;
      if (ipaddrs != null) {
        for (final ip in ipaddrs) {
          if (ip != null) usedIps.add(ip.toString().trim());
        }
      }
    });

    final startHost = primarySubnet.poolStart ?? 100;
    final limitHost = primarySubnet.poolLimit ?? 150;
    final endHost = (startHost + limitHost - 1).clamp(2, 254);

    for (int host = startHost; host <= endHost; host++) {
      final cand = '$prefix.$host';
      if (!usedIps.contains(cand)) {
        return cand;
      }
    }

    for (int host = 10; host <= 254; host++) {
      final cand = '$prefix.$host';
      if (!usedIps.contains(cand)) {
        return cand;
      }
    }

    return '$prefix.150';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasFixedMac =
        (widget.macAddress != null && widget.macAddress!.isNotEmpty) ||
        (widget.existingMapping != null &&
            widget.existingMapping!.macAddress.isNotEmpty) ||
        (widget.client != null && widget.client!.macAddress.isNotEmpty);
    final canSave =
        _rawMacError == null &&
        _rawNameError == null &&
        _rawIpError == null &&
        _rawLeaseError == null &&
        _hasChanges;

    final dhcpOverview = DhcpDnsOverview.fromDashboardData(
      AppState.instance.dashboardData,
      isReviewerMode: AppState.instance.reviewerModeEnabled,
    );

    final suggestedIp = _findSuggestedFreeIp(dhcpOverview);
    final rawClientDisplay = widget.client?.displayName.trim();
    final suggestedHostname =
        (rawClientDisplay != null &&
            rawClientDisplay.isNotEmpty &&
            rawClientDisplay != 'Unknown' &&
            rawClientDisplay != 'Anonymous Device' &&
            rawClientDisplay != 'Anonymous IPv6 Host')
        ? rawClientDisplay.replaceAll(RegExp(r'\s+'), '-')
        : 'Host-${suggestedIp.split('.').last}';

    SubnetInfo? currentSubnet;
    final currentIp = _ipController.text.trim();
    if (_isValidIPv4(currentIp)) {
      for (final sub in dhcpOverview.configuredSubnets) {
        if (sub.containsIp(currentIp)) {
          currentSubnet = sub;
          break;
        }
      }
    }
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Discard Unsaved Lease?'),
            content: const Text(
              'You have unsaved changes to this static lease reservation. Are you sure you want to discard them?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep Editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        );
        if (confirm == true && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: AlertDialog(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isEditing ? Icons.edit_note : Icons.push_pin,
                color: Colors.teal,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _isEditing ? 'Edit Static Lease' : 'Add Static Lease',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Cancel',
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasFixedMac)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MAC Address',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        SelectableText(
                          _effectiveMac,
                          style: GoogleFonts.geistMono(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        'MAC Address',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_clipboardMac != null)
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _pasteMacFromClipboard,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondaryContainer
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.colorScheme.secondary.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.content_paste_go_rounded,
                                  size: 12,
                                  color: theme.colorScheme.secondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Paste MAC: $_clipboardMac',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _macController,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.visiblePassword,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9a-fA-F:-]'),
                      ),
                    ],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      hintText: 'AA:BB:CC:DD:EE:FF',
                      prefixIcon: const Icon(
                        Icons.qr_code_scanner_outlined,
                        size: 20,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.paste_rounded, size: 18),
                        tooltip: 'Paste MAC from Clipboard',
                        onPressed: _pasteMacFromClipboard,
                      ),
                      errorText: _macError,
                      filled: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // Hostname Field
                Text(
                  'Hostname / Client Name',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _nameController,
                  keyboardType: TextInputType.url,
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    hintText: 'e.g. $suggestedHostname',
                    prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                    errorText: _nameError,
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // IPv4 Address Field
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      'Reserved IPv4 Address',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (suggestedIp.isNotEmpty &&
                        _ipController.text.trim() != suggestedIp)
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          setState(() {
                            _ipTouched = true;
                            _ipController.text = suggestedIp;
                          });
                          _validateInputs();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_awesome_rounded,
                                size: 12,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Suggest Free IP: $suggestedIp',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _ipController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    hintText: 'e.g. $suggestedIp (Available in LAN)',
                    prefixIcon: const Icon(Icons.lan_outlined, size: 20),
                    errorText: _ipError,
                    errorMaxLines: 3,
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                if (currentSubnet != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        size: 13,
                        color: Colors.teal,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Matches Subnet: ${currentSubnet.gatewayIp}/${currentSubnet.netmask} (${currentSubnet.interfaceName})',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.teal,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else if (_isValidIPv4(currentIp)) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        size: 13,
                        color: Colors.teal,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Valid Private IPv4 Address (${currentIp.split('.').sublist(0, 3).join('.')}.x)',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.teal,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),

                // IPv6 / DUID section — collapsed by default, opt-in only
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() {
                      _showIp6Section = !_showIp6Section;
                      // Clear fields when collapsing so they are not submitted
                      if (!_showIp6Section) {
                        _ip6Controller.clear();
                        _duidController.clear();
                        _ip6Touched = false;
                        _duidTouched = false;
                      }
                    });
                    _validateInputs();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _showIp6Section
                          ? colorScheme.secondaryContainer.withValues(
                              alpha: 0.35,
                            )
                          : colorScheme.surfaceContainerHighest.withValues(
                              alpha: 0.4,
                            ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _showIp6Section
                            ? colorScheme.secondary.withValues(alpha: 0.4)
                            : colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _showIp6Section
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 18,
                          color: _showIp6Section
                              ? colorScheme.secondary
                              : colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Configure IPv6 Reservation & DUID',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: _showIp6Section
                                      ? colorScheme.secondary
                                      : colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                _showIp6Section
                                    ? 'Optional — tap to collapse and clear'
                                    : 'Optional — tap to add an IPv6 address or DUID',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 10,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _showIp6Section,
                          onChanged: (v) {
                            setState(() {
                              _showIp6Section = v;
                              if (!v) {
                                _ip6Controller.clear();
                                _duidController.clear();
                                _ip6Touched = false;
                                _duidTouched = false;
                              }
                            });
                            _validateInputs();
                          },
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  ),
                ),

                if (_showIp6Section) ...[
                  const SizedBox(height: 12),
                  // IPv6 Address / Host ID Field
                  Text(
                    'Reserved IPv6 Address / Host ID',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _ip6Controller,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      hintText: 'e.g. 2405:201::100 or ::100 (Host ID)',
                      prefixIcon: const Icon(Icons.language_outlined, size: 20),
                      errorText: _ip6Error,
                      errorMaxLines: 3,
                      filled: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // DUID Field
                  Text(
                    'DUID (DHCPv6 Unique Identifier)',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _duidController,
                    keyboardType: TextInputType.text,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      hintText: 'e.g. 0001000129A1B2C3D4E5F67890AB',
                      prefixIcon: const Icon(
                        Icons.fingerprint_outlined,
                        size: 20,
                      ),
                      errorText: _duidError,
                      errorMaxLines: 3,
                      filled: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // Lease Time Preset Dropdown
                Text(
                  'Lease Time Duration',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _selectedLeasePreset,
                  isExpanded: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.timer_outlined, size: 20),
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: _leasePresets.map((preset) {
                    return DropdownMenuItem<String>(
                      value: preset['value'],
                      child: Text(
                        preset['label']!,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedLeasePreset = val;
                      });
                      _validateInputs();
                    }
                  },
                ),

                // Custom Lease Time Input if 'custom' preset is selected
                if (_selectedLeasePreset == 'custom') ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _customLeaseController,
                          keyboardType: TextInputType.text,
                          textCapitalization: TextCapitalization.none,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            labelText: 'Custom Lease Duration',
                            hintText: 'e.g., 2h, 30m, 3d, 12h, infinite',
                            prefixIcon: const Icon(
                              Icons.edit_calendar_outlined,
                              size: 20,
                            ),
                            errorText: _leaseTimeError,
                            errorMaxLines: 3,
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Pick Date & Time',
                        icon: const Icon(Icons.calendar_month_rounded),
                        onPressed: () => _pickLeaseExpiryDateTime(),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (_isEditing)
            TextButton.icon(
              onPressed: _deleteLease,
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
              label: const Text(
                'Remove Lease',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: canSave ? _submit : null,
            icon: const Icon(Icons.check, size: 18),
            label: Text(_isEditing ? 'Update Reservation' : 'Save Reservation'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
