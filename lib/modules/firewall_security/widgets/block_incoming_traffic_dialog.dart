// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/modules/firewall_security/models/firewall_info.dart';
import 'package:yet_another_luci_app/modules/firewall_security/utils/firewall_validator.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';

enum BlockTargetType { externalIp, portOrService, commonApp }

class CommonThreatPreset {
  final String name;
  final String port;
  final String proto;

  const CommonThreatPreset({
    required this.name,
    required this.port,
    required this.proto,
  });
}

const List<CommonThreatPreset> commonThreatPresets = [
  CommonThreatPreset(name: 'Telnet (Insecure Shell)', port: '23', proto: 'tcp'),
  CommonThreatPreset(name: 'SMB / Windows Sharing', port: '445', proto: 'tcp'),
  CommonThreatPreset(name: 'NetBIOS', port: '137-139', proto: 'tcp udp'),
  CommonThreatPreset(name: 'RDP (Remote Desktop)', port: '3389', proto: 'tcp'),
];

/// Simple "Block an Incoming Connection" dialog.
class BlockIncomingTrafficDialog extends ConsumerStatefulWidget {
  const BlockIncomingTrafficDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const BlockIncomingTrafficDialog(),
    );
  }

  @override
  ConsumerState<BlockIncomingTrafficDialog> createState() =>
      _BlockIncomingTrafficDialogState();
}

class _BlockIncomingTrafficDialogState
    extends ConsumerState<BlockIncomingTrafficDialog> {
  final _formKey = GlobalKey<FormState>();

  BlockTargetType _targetType = BlockTargetType.externalIp;
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  String _portProto = 'tcp';
  CommonThreatPreset _selectedCommonThreat = commonThreatPresets.first;

  IncomingTrafficPreflightResult? _preflightResult;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _evaluatePreflight();
    });
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _onTargetTypeChanged(BlockTargetType newType) {
    setState(() {
      _targetType = newType;
      _errorMessage = null;
    });
    _evaluatePreflight();
  }

  void _evaluatePreflight() {
    final appState = ref.read(appStateProvider);
    final overview = FirewallOverview.fromUciData(
      appState.dashboardData?['uciFirewallConfig'],
      backend: appState.capabilities?.firewallBackend ?? FirewallBackend.fw4,
      isReviewerMode: appState.reviewerModeEnabled,
    );

    String? port;
    String? proto = 'any';
    String? ip;

    switch (_targetType) {
      case BlockTargetType.externalIp:
        final rawIp = _ipController.text.trim();
        if (rawIp.isNotEmpty && FirewallValidator.isValidIpOrCidr(rawIp)) {
          ip = rawIp;
        }
        break;
      case BlockTargetType.portOrService:
        final rawPort = _portController.text.trim();
        if (rawPort.isNotEmpty) {
          port = rawPort;
          proto = _portProto;
        }
        break;
      case BlockTargetType.commonApp:
        port = _selectedCommonThreat.port;
        proto = _selectedCommonThreat.proto;
        break;
    }

    final result = FirewallValidator.evaluateIncomingTrafficPreflight(
      overview: overview,
      incomingPort: port,
      proto: proto,
      srcIp: ip,
    );

    setState(() {
      _preflightResult = result;
    });
  }

  Future<void> _handleBlock({bool forceExplicit = false}) async {
    final loc = AppLocalizations.of(context);
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final appState = ref.read(appStateProvider);
    final canModify = appState.capabilities?.canModifyFirewall ?? true;
    if (!canModify) {
      setState(() {
        _errorMessage =
            loc?.firewallReadOnlyNotice ??
            'Read-only access: Changes cannot be applied on this router account.';
      });
      return;
    }

    final overview = FirewallOverview.fromUciData(
      appState.dashboardData?['uciFirewallConfig'],
      backend: appState.capabilities?.firewallBackend ?? FirewallBackend.fw4,
      isReviewerMode: appState.reviewerModeEnabled,
    );

    final resolvedDest =
        _preflightResult?.resolvedDestZone ?? overview.primaryLanZoneName;

    if (resolvedDest == null || resolvedDest.isEmpty) {
      setState(() {
        _errorMessage =
            loc?.firewallBlockUnableToDetermineDesc ??
            'Unable to determine safe destination zone for incoming block rule.';
      });
      return;
    }

    String ruleName;
    String? srcIp;
    String? destPort;
    String proto = 'any';

    switch (_targetType) {
      case BlockTargetType.externalIp:
        final targetIp = _ipController.text.trim();
        if (!FirewallValidator.isValidIpOrCidr(targetIp)) {
          setState(
            () => _errorMessage = 'Please enter a valid IP address or CIDR.',
          );
          return;
        }

        // Self-device guardrail check
        final safe = await SelfDeviceGuard.checkSelfActionGuardrail(
          context,
          actionName: 'Block Incoming Connection',
          targetIp: targetIp,
        );
        if (!safe || !mounted) return;

        ruleName =
            'Block_Incoming_${targetIp.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';
        srcIp = targetIp;
        break;

      case BlockTargetType.portOrService:
        final rawPort = _portController.text.trim();
        if (rawPort.isEmpty) {
          setState(() => _errorMessage = 'Please enter a port or port range.');
          return;
        }
        ruleName =
            'Block_Incoming_Port_${rawPort.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';
        destPort = rawPort;
        proto = _portProto;
        break;

      case BlockTargetType.commonApp:
        ruleName =
            'Block_Incoming_${_selectedCommonThreat.name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';
        destPort = _selectedCommonThreat.port;
        proto = _selectedCommonThreat.proto;
        break;
    }

    final candidate = FirewallCustomRule(
      sectionKey: '',
      name: ruleName,
      srcZone: 'wan',
      destZone: resolvedDest,
      target: 'DROP',
      enabled: true,
      proto: proto,
      srcIp: srcIp,
      destPort: destPort,
    );

    setState(() => _isSubmitting = true);
    try {
      final success = await appState.addFirewallCustomRule(candidate);
      if (!mounted) return;

      if (success) {
        LuciToastManager.showSuccess(
          context,
          'Incoming connection block rule created for "$ruleName".',
        );
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Failed to create firewall block rule.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.block_rounded, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              loc?.firewallBlockIncomingTitle ?? 'Block an Incoming Connection',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc?.firewallBlockWhatToBlock ?? 'What do you want to block?',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                // Target Type Selector
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<BlockTargetType>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: [
                      ButtonSegment(
                        value: BlockTargetType.externalIp,
                        label: Text(loc?.firewallBlockTabIp ?? 'IP'),
                        icon: const Icon(Icons.public_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: BlockTargetType.portOrService,
                        label: Text(loc?.firewallBlockTabPort ?? 'Port'),
                        icon: const Icon(Icons.numbers_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: BlockTargetType.commonApp,
                        label: Text(loc?.firewallBlockTabPreset ?? 'Preset'),
                        icon: const Icon(Icons.security_outlined, size: 18),
                      ),
                    ],
                    selected: {_targetType},
                    onSelectionChanged: (set) {
                      if (set.isNotEmpty) {
                        _onTargetTypeChanged(set.first);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // Input fields based on target type
                if (_targetType == BlockTargetType.externalIp) ...[
                  TextFormField(
                    controller: _ipController,
                    decoration: InputDecoration(
                      labelText:
                          loc?.firewallBlockExternalIp ?? 'External IP Address',
                      hintText: '198.51.100.25 or 198.51.100.0/24',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.public),
                    ),
                    keyboardType: TextInputType.datetime,
                    onChanged: (_) => _evaluatePreflight(),
                    validator: (val) {
                      if (_targetType == BlockTargetType.externalIp) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Please enter an external IP or CIDR';
                        }
                        if (!FirewallValidator.isValidIpOrCidr(val.trim())) {
                          return 'Invalid IP address or CIDR range';
                        }
                      }
                      return null;
                    },
                  ),
                ] else if (_targetType == BlockTargetType.portOrService) ...[
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _portController,
                          decoration: InputDecoration(
                            labelText:
                                loc?.firewallBlockPortOrService ??
                                'Port or Service',
                            hintText: '8080 or 8000-8080',
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (_) => _evaluatePreflight(),
                          validator: (val) {
                            if (_targetType == BlockTargetType.portOrService) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Enter port';
                              }
                              final ranges = FirewallValidator.parsePortRanges(
                                val,
                              );
                              if (ranges.isEmpty) {
                                return 'Invalid port';
                              }
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          initialValue: _portProto,
                          isExpanded: true,
                          borderRadius: BorderRadius.circular(16),
                          dropdownColor: theme.colorScheme.surfaceContainerHigh,
                          elevation: 4,
                          menuMaxHeight: 360,
                          icon: const Icon(Icons.arrow_drop_down_rounded),
                          decoration: InputDecoration(
                            labelText:
                                loc?.firewallWizardProtocol ?? 'Protocol',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 14,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'tcp', child: Text('TCP')),
                            DropdownMenuItem(value: 'udp', child: Text('UDP')),
                            DropdownMenuItem(
                              value: 'tcp udp',
                              child: Text('Both'),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _portProto = val);
                              _evaluatePreflight();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ] else if (_targetType == BlockTargetType.commonApp) ...[
                  DropdownButtonFormField<CommonThreatPreset>(
                    initialValue: _selectedCommonThreat,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(16),
                    dropdownColor: theme.colorScheme.surfaceContainerHigh,
                    elevation: 4,
                    menuMaxHeight: 360,
                    icon: const Icon(Icons.arrow_drop_down_rounded),
                    decoration: InputDecoration(
                      labelText: 'Threat / Common Application',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                    items: commonThreatPresets.map((preset) {
                      return DropdownMenuItem(
                        value: preset,
                        child: Text(
                          '${preset.name} (${preset.port} / ${preset.proto.toUpperCase()})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedCommonThreat = val);
                        _evaluatePreflight();
                      }
                    },
                  ),
                ],

                const SizedBox(height: 16),

                // Preflight Status Card
                if (_preflightResult != null) ...[
                  if (_preflightResult!.isAlreadyBlocked) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade700),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                color: Colors.green.shade800,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  loc?.firewallBlockAlreadyBlockedTitle ??
                                      'Already Blocked',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            loc?.firewallBlockAlreadyBlockedDesc ??
                                'This connection is already blocked by your router\'s default firewall protection.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.85,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_preflightResult!.isCurrentlyAllowed) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade700),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.amber.shade900,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  loc?.firewallBlockCurrentlyAllowedTitle ??
                                      'Currently Allowed',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            loc?.firewallBlockCurrentlyAllowedDesc ??
                                'This connection is currently permitted through your router by an active rule or port forward. Blocking it will override existing access.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.85,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_preflightResult!.isUnableToDetermine) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer.withValues(
                          alpha: 0.4,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.colorScheme.error),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.help_outline_rounded,
                                color: theme.colorScheme.error,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  loc?.firewallBlockUnableToDetermineTitle ??
                                      'Unable to Determine',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            loc?.firewallBlockUnableToDetermineDesc ??
                                'The firewall protection status for this connection could not be safely verified. To avoid creating unintended rules, please verify your router configuration.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.85,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],

                // Error message banner
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: theme.colorScheme.onErrorContainer,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: Text(
            _preflightResult?.isAlreadyBlocked == true
                ? (loc?.btnOk ?? 'OK')
                : (loc?.btnCancel ?? 'Cancel'),
          ),
        ),
        if (_preflightResult?.isAlreadyBlocked == true)
          TextButton(
            onPressed: _isSubmitting
                ? null
                : () => _handleBlock(forceExplicit: true),
            child: Text(
              loc?.firewallBlockCreateAnyway ?? 'Create Explicit Rule Anyway',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          )
        else
          ElevatedButton(
            onPressed:
                (_isSubmitting || _preflightResult?.isUnableToDetermine == true)
                ? null
                : () => _handleBlock(),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(loc?.firewallBlockButton ?? 'Block Connection'),
          ),
      ],
    );
  }
}
