// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/utils/os_platform_integration.dart';
import 'package:yet_another_luci_app/widgets/luci_app_bar.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import '../controllers/diagnostics_controller.dart';
import '../models/dns_lookup_result.dart';
import '../models/internet_reachability.dart';
import '../models/ping_result.dart';
import '../models/routing_neighbor_info.dart';
import '../models/traceroute_result.dart';
import '../widgets/speed_test_view.dart';
import '../widgets/dns_benchmark_view.dart';
import 'package:yet_another_luci_app/modules/network_diagnostic/screens/network_diagnostic_screen.dart';
import 'package:yet_another_luci_app/modules/network_diagnostic/controllers/network_diagnostic_controller.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';

class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Controllers for inputs
  final TextEditingController _pingTargetController = TextEditingController(
    text: '1.1.1.1',
  );
  int _pingCount = 3;
  bool _pingIpv6 = false;

  final TextEditingController _traceTargetController = TextEditingController(
    text: '1.1.1.1',
  );
  int _traceMaxHops = 15;
  bool _traceIpv6 = false;

  final TextEditingController _dnsHostController = TextEditingController(
    text: 'openwrt.org',
  );
  final TextEditingController _dnsServerController = TextEditingController();

  int _networkTableSegment = 0; // 0: Routes, 1: Neighbors, 2: Conntrack
  bool _isReportSelectable = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
    _tabController.addListener(_handleTabChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(diagnosticsControllerProvider.notifier)
          .testReachability(context: context);
      ref
          .read(diagnosticsControllerProvider.notifier)
          .loadNetworkTables(context: context);
    });
  }

  void _handleTabChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _pingTargetController.dispose();
    _traceTargetController.dispose();
    _dnsHostController.dispose();
    _dnsServerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(diagnosticsControllerProvider);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: LuciAppBar(
        title: l10n?.diagNetworkDiagnostics ?? 'Network Diagnostics',
        showBack: true,
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: _buildReachabilityHeroCard(context, state),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverTabBarDelegate(
                child: Container(
                  color: theme.colorScheme.surface,
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                    labelColor: theme.colorScheme.primary,
                    unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                    indicatorColor: theme.colorScheme.primary,
                    indicatorWeight: 3,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    tabs: [
                      Tab(
                        icon: const Icon(Icons.troubleshoot_rounded, size: 20),
                        text: l10n?.diagTabHealth ?? 'Health & Diagnostic',
                      ),
                      Tab(
                        icon: const Icon(Icons.speed_rounded, size: 20),
                        text: l10n?.diagTabSpeedTest ?? 'Speed Test',
                      ),
                      Tab(
                        icon: const Icon(Icons.timer_outlined, size: 20),
                        text: l10n?.diagTabDnsLatency ?? 'DNS Latency',
                      ),
                      Tab(
                        icon: const Icon(Icons.network_ping, size: 20),
                        text: l10n?.diagTabPing ?? 'Ping',
                      ),
                      Tab(
                        icon: const Icon(Icons.route_outlined, size: 20),
                        text: l10n?.diagTabTraceroute ?? 'Traceroute',
                      ),
                      Tab(
                        icon: const Icon(Icons.dns_outlined, size: 20),
                        text: l10n?.diagTabDns ?? 'DNS Lookup',
                      ),
                      Tab(
                        icon: const Icon(Icons.alt_route, size: 20),
                        text: l10n?.diagTabRoutesArp ?? 'Routes & ARP',
                      ),
                      Tab(
                        icon: const Icon(Icons.summarize_outlined, size: 20),
                        text: l10n?.diagTabExport ?? 'Export Report',
                      ),
                    ],
                  ),
                ),
                height: 54,
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            const NetworkDiagnosticView(showAppBar: false),
            const SpeedTestView(),
            const DnsBenchmarkView(),
            _buildPingTab(context, state),
            _buildTracerouteTab(context, state),
            _buildDnsTab(context, state),
            _buildNetworkTablesTab(context, state),
            _buildExportReportTab(context, state),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. HERO REACHABILITY CARD
  // ---------------------------------------------------------------------------
  Widget _buildReachabilityHeroCard(
    BuildContext context,
    DiagnosticsState state,
  ) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final reach = state.internetReachability;
    final isTesting = state.isTestingReachability;

    Color badgeColor;
    Color badgeBg;
    IconData statusIcon;
    String statusTitle;

    if (isTesting) {
      badgeColor = theme.colorScheme.primary;
      badgeBg = theme.colorScheme.primary.withValues(alpha: 0.15);
      statusIcon = Icons.hourglass_top_rounded;
      statusTitle = l10n?.diagTestingConnectivity ?? 'Testing Connectivity...';
    } else if (reach == null || reach.status == ReachabilityStatus.unknown) {
      badgeColor = LuciStatusColors.inactive;
      badgeBg = theme.colorScheme.surfaceContainerHighest;
      statusIcon = Icons.help_outline_rounded;
      statusTitle = l10n?.diagReachabilityUnknown ?? 'Reachability Unknown';
    } else if (reach.status == ReachabilityStatus.online) {
      badgeColor = LuciStatusColors.connected;
      badgeBg = LuciStatusColors.successBg(context);
      statusIcon = Icons.check_circle_rounded;
      statusTitle = l10n?.diagConnectedInternet ?? 'Connected to Internet';
    } else if (reach.status == ReachabilityStatus.partial) {
      badgeColor = LuciStatusColors.warning;
      badgeBg = LuciStatusColors.warning.withValues(alpha: 0.15);
      statusIcon = Icons.warning_amber_rounded;
      statusTitle =
          l10n?.diagPartialConnectivity ?? 'Partial Connectivity (Gateway OK)';
    } else {
      badgeColor = LuciStatusColors.error;
      badgeBg = LuciStatusColors.errorBg(context);
      statusIcon = Icons.cancel_rounded;
      statusTitle = l10n?.diagInternetDisconnected ?? 'Internet Disconnected';
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(statusIcon, color: badgeColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _getLocalizedReachabilityMessage(reach, l10n),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: l10n?.diagRetestConnection ?? 'Retest Connection',
                  onPressed: isTesting
                      ? null
                      : () => ref
                            .read(diagnosticsControllerProvider.notifier)
                            .testReachability(context: context),
                  icon: isTesting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            if (reach != null && !isTesting) ...[
              const Divider(height: 20),
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          context,
                          label:
                              l10n?.diagMetricWanInterface ?? 'WAN Interface',
                          value:
                              reach.wanInterface ?? (l10n?.diagNone ?? 'None'),
                          icon: Icons.public,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildMetricCard(
                          context,
                          label: reach.gatewayIp != null
                              ? (l10n?.diagMetricGatewayWithIp(
                                      reach.gatewayIp!,
                                    ) ??
                                    'Gateway (${reach.gatewayIp})')
                              : (l10n?.diagMetricGateway ?? 'Gateway'),
                          value: reach.gatewayReachable
                              ? (reach.gatewayLatencyMs != null
                                    ? '${reach.gatewayLatencyMs!.toStringAsFixed(1)} ms'
                                    : (l10n?.diagStatusReachable ??
                                          'Reachable'))
                              : (reach.gatewayIp != null
                                    ? (l10n?.diagStatusUnreachable ??
                                          'Unreachable')
                                    : (l10n?.diagNone ?? 'None')),
                          icon: Icons.router,
                          color: reach.gatewayReachable
                              ? LuciStatusColors.connected
                              : (reach.gatewayIp != null
                                    ? LuciStatusColors.error
                                    : LuciStatusColors.inactive),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          context,
                          label:
                              l10n?.diagMetricPublicIcmp('1.1.1.1') ??
                              'Public ICMP (1.1.1.1)',
                          value: reach.publicDnsReachable
                              ? (reach.publicDnsLatencyMs != null
                                    ? '${reach.publicDnsLatencyMs!.toStringAsFixed(1)} ms'
                                    : (l10n?.diagStatusOK ?? 'OK'))
                              : (l10n?.diagStatusFailed ?? 'Failed'),
                          icon: Icons.speed,
                          color: reach.publicDnsReachable
                              ? LuciStatusColors.connected
                              : LuciStatusColors.error,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildMetricCard(
                          context,
                          label:
                              l10n?.diagMetricDnsResolution ?? 'DNS Resolution',
                          value: reach.dnsResolving
                              ? (l10n?.diagStatusWorking ?? 'Working')
                              : (l10n?.diagStatusFailing ?? 'Failing'),
                          icon: Icons.dns,
                          color: reach.dnsResolving
                              ? LuciStatusColors.connected
                              : LuciStatusColors.error,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                minimumSize: const Size.fromHeight(40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.troubleshoot_rounded, size: 18),
              label: Text(
                l10n?.diagBtnWhyBroken ??
                    '“Why Is My Internet Broken?” Diagnostic',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              onPressed: () {
                _tabController.animateTo(0);
                ref
                    .read(networkDiagnosticControllerProvider.notifier)
                    .runDiagnostics();
              },
            ),
          ],
        ),
      ),
    );
  }

  String _getLocalizedReachabilityMessage(
    InternetReachability? reach,
    AppLocalizations? l10n,
  ) {
    if (reach == null) {
      return l10n?.diagTapToTest ?? 'Tap below to test network reachability';
    }
    final msg = reach.statusMessage;
    switch (reach.status) {
      case ReachabilityStatus.online:
        if (msg.contains('All probes passed')) {
          return l10n?.diagReachAllProbesPassed ?? msg;
        } else if (msg.contains('Point-to-Point') || msg.contains('via')) {
          return l10n?.diagReachViaGateway(reach.gatewayIp ?? '') ?? msg;
        } else if (msg.contains('Gateway ICMP unprompted') ||
            msg.contains('WAN OK')) {
          return l10n?.diagReachWanOkGatewayUnprompted ?? msg;
        } else if (msg.contains('DNS operational') ||
            msg.contains('ICMP ping blocked')) {
          return l10n?.diagReachDnsOnlyIcmpBlocked ?? msg;
        }
        return msg;
      case ReachabilityStatus.partial:
        if (msg.contains('DNS resolution failed') ||
            msg.contains('Check router DNS settings')) {
          return l10n?.diagReachDnsFailed ?? msg;
        } else if (msg.contains('Local Gateway reachable')) {
          return l10n?.diagReachGatewayOnly(reach.gatewayIp ?? '') ?? msg;
        }
        return msg;
      case ReachabilityStatus.offline:
        if (reach.gatewayIp == null || msg.contains('No active WAN gateway')) {
          return l10n?.diagReachNoGateway ?? msg;
        } else if (msg.contains('Gateway and Internet are unreachable')) {
          return l10n?.diagReachOffline ?? msg;
        } else if (msg == 'Internet unreachable') {
          return l10n?.diagReachInternetUnreachable ?? msg;
        }
        return msg;
      case ReachabilityStatus.testing:
        return l10n?.diagReachTesting ?? msg;
      case ReachabilityStatus.unknown:
        return l10n?.diagReachNotTested ?? msg;
    }
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. PING TAB
  // ---------------------------------------------------------------------------
  Widget _buildPingTab(BuildContext context, DiagnosticsState state) {
    final lastPing = state.lastPingResult;
    final l10n = AppLocalizations.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInputCard(
            context,
            title: l10n?.diagPingTarget ?? 'Ping Host or IP',
            subtitle:
                l10n?.diagPingSubtitle ??
                'Send ICMP ECHO_REQUEST packets from the router',
            controller: _pingTargetController,
            hint: l10n?.diagPingTargetHint ?? 'e.g. 1.1.1.1, google.com',
            quickChips: [
              if (state.internetReachability?.gatewayIp != null)
                'gw:${state.internetReachability!.gatewayIp!}',
              '1.1.1.1',
              '8.8.8.8',
              'openwrt.org',
            ],
            onChipTap: (val) {
              if (val.startsWith('gw:')) {
                _pingTargetController.text = val.substring(3);
              } else {
                _pingTargetController.text = val;
              }
            },
            extraControls: Row(
              children: [
                DropdownButton<int>(
                  value: _pingCount,
                  underline: const SizedBox(),
                  borderRadius: BorderRadius.circular(16),
                  dropdownColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHigh,
                  elevation: 4,
                  menuMaxHeight: 360,
                  icon: const Icon(Icons.arrow_drop_down_rounded),
                  items: [
                    DropdownMenuItem(
                      value: 3,
                      child: Text(l10n?.diagPingPacketsCount(3) ?? '3 Packets'),
                    ),
                    DropdownMenuItem(
                      value: 5,
                      child: Text(l10n?.diagPingPacketsCount(5) ?? '5 Packets'),
                    ),
                    DropdownMenuItem(
                      value: 10,
                      child: Text(
                        l10n?.diagPingPacketsCount(10) ?? '10 Packets',
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _pingCount = v);
                  },
                ),
                const Spacer(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n?.diagIpv6 ?? 'IPv6',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Switch(
                      value: _pingIpv6,
                      onChanged: (v) => setState(() => _pingIpv6 = v),
                    ),
                  ],
                ),
              ],
            ),
            isLoading: state.isPinging,
            onActionPressed: () {
              ref
                  .read(diagnosticsControllerProvider.notifier)
                  .ping(
                    _pingTargetController.text,
                    count: _pingCount,
                    isIpv6: _pingIpv6,
                    context: context,
                  );
            },
            actionLabel: state.isPinging
                ? (l10n?.diagBtnPinging ?? 'Pinging...')
                : (l10n?.diagBtnStartPing ?? 'Start Ping Test'),
            actionIcon: Icons.play_arrow_rounded,
          ),
          const SizedBox(height: 16),
          if (lastPing != null) _buildPingResultsCard(context, lastPing),
        ],
      ),
    );
  }

  Widget _buildPingResultsCard(BuildContext context, PingResult ping) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isSuccess = ping.isSuccess;
    final lossColor = ping.packetLossPercent == 0
        ? LuciStatusColors.connected
        : (ping.packetLossPercent < 50
              ? LuciStatusColors.warning
              : LuciStatusColors.error);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSuccess ? Icons.check_circle_outline : Icons.error_outline,
                  color: isSuccess
                      ? LuciStatusColors.connected
                      : LuciStatusColors.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n?.diagPingResultTo(ping.target) ??
                        'Ping to ${ping.target}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: lossColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    l10n?.diagPacketLoss(
                          ping.packetLossPercent.toStringAsFixed(0),
                        ) ??
                        '${ping.packetLossPercent.toStringAsFixed(0)}% Loss',
                    style: TextStyle(
                      color: lossColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (isSuccess && ping.avgRttMs != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatColumn(
                    l10n?.diagMinLatency ?? 'Min Latency',
                    '${ping.minRttMs?.toStringAsFixed(1) ?? "-"} ms',
                  ),
                  _buildStatColumn(
                    l10n?.diagAvgLatency ?? 'Avg Latency',
                    '${ping.avgRttMs?.toStringAsFixed(1) ?? "-"} ms',
                    highlight: true,
                  ),
                  _buildStatColumn(
                    l10n?.diagMaxLatency ?? 'Max Latency',
                    '${ping.maxRttMs?.toStringAsFixed(1) ?? "-"} ms',
                  ),
                  _buildStatColumn(
                    l10n?.diagPackets ?? 'Packets',
                    '${ping.packetsReceived} / ${ping.packetsTransmitted}',
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (ping.replies.isNotEmpty) ...[
              Text(
                l10n?.diagIndividualReplies ?? 'Individual Replies',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ...ping.replies.map(
                (r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3.0),
                  child: Row(
                    children: [
                      Text(
                        'icmp_seq=${r.seq}',
                        style: GoogleFonts.geistMono(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (r.ttl != null)
                        Text(
                          'ttl=${r.ttl}',
                          style: GoogleFonts.geistMono(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      const Spacer(),
                      Text(
                        '${r.timeMs.toStringAsFixed(2)} ms',
                        style: GoogleFonts.geistMono(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (ping.rawOutput.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildRawConsoleExpansion(context, ping.rawOutput),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(
    String label,
    String value, {
    bool highlight = false,
  }) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: highlight ? 16 : 14,
            fontWeight: FontWeight.bold,
            color: highlight ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 3. TRACEROUTE TAB
  // ---------------------------------------------------------------------------
  Widget _buildTracerouteTab(BuildContext context, DiagnosticsState state) {
    final lastTrace = state.lastTracerouteResult;
    final l10n = AppLocalizations.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInputCard(
            context,
            title: l10n?.diagTraceTarget ?? 'Target Host / IP',
            subtitle:
                l10n?.diagTraceSubtitle ??
                'Trace network hops from router to destination',
            controller: _traceTargetController,
            hint: l10n?.diagTraceTargetHint ?? 'e.g. 1.1.1.1, google.com',
            quickChips: const ['1.1.1.1', '8.8.8.8', 'openwrt.org'],
            onChipTap: (val) => _traceTargetController.text = val,
            extraControls: Row(
              children: [
                DropdownButton<int>(
                  value: _traceMaxHops,
                  underline: const SizedBox(),
                  borderRadius: BorderRadius.circular(16),
                  dropdownColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHigh,
                  elevation: 4,
                  menuMaxHeight: 360,
                  icon: const Icon(Icons.arrow_drop_down_rounded),
                  items: [
                    DropdownMenuItem(
                      value: 15,
                      child: Text(l10n?.diagTraceMaxHops(15) ?? 'Max 15 Hops'),
                    ),
                    DropdownMenuItem(
                      value: 30,
                      child: Text(l10n?.diagTraceMaxHops(30) ?? 'Max 30 Hops'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _traceMaxHops = v);
                  },
                ),
                const Spacer(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n?.diagIpv6 ?? 'IPv6',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Switch(
                      value: _traceIpv6,
                      onChanged: (v) => setState(() => _traceIpv6 = v),
                    ),
                  ],
                ),
              ],
            ),
            isLoading: state.isTracing,
            onActionPressed: () {
              ref
                  .read(diagnosticsControllerProvider.notifier)
                  .traceroute(
                    _traceTargetController.text,
                    maxHops: _traceMaxHops,
                    isIpv6: _traceIpv6,
                    context: context,
                  );
            },
            actionLabel: state.isTracing
                ? (l10n?.diagBtnTracing ?? 'Tracing...')
                : (l10n?.diagBtnStartTrace ?? 'Trace Route'),
            actionIcon: Icons.alt_route_rounded,
          ),
          const SizedBox(height: 16),
          if (lastTrace != null)
            _buildTracerouteResultsCard(context, lastTrace),
        ],
      ),
    );
  }

  Widget _buildTracerouteResultsCard(
    BuildContext context,
    TracerouteResult trace,
  ) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.route, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n?.diagTraceResultTo(trace.target) ??
                        'Traceroute to ${trace.target}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    l10n?.diagHopsCount(trace.hops.length) ??
                        '${trace.hops.length} Hops',
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (trace.hops.isEmpty)
              Text(
                l10n?.diagTraceNoHops ??
                    'No hops recorded or destination unreachable.',
              )
            else
              ...trace.hops.map((hop) {
                final isTimeout = hop.isTimeout;
                final avg = hop.avgRttMs;
                final latencyColor = isTimeout
                    ? LuciStatusColors.error
                    : (avg == null || avg > 80
                          ? Colors.orange
                          : (avg > 40
                                ? Colors.amber.shade700
                                : LuciStatusColors.connected));

                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isTimeout
                          ? theme.colorScheme.error.withValues(alpha: 0.2)
                          : theme.colorScheme.outlineVariant.withValues(
                              alpha: 0.3,
                            ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${hop.hopNumber}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isTimeout
                                  ? (l10n?.diagRequestTimedOut ??
                                        '* * * Request Timed Out')
                                  : hop.displayAddress,
                              style: GoogleFonts.geistMono(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isTimeout
                                    ? theme.colorScheme.error
                                    : null,
                              ),
                            ),
                            if (!isTimeout &&
                                hop.host != null &&
                                hop.ip != null)
                              Text(
                                hop.host!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (!isTimeout && avg != null)
                        Text(
                          '${avg.toStringAsFixed(1)} ms',
                          style: GoogleFonts.geistMono(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: latencyColor,
                          ),
                        ),
                    ],
                  ),
                );
              }),
            if (trace.rawOutput.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildRawConsoleExpansion(context, trace.rawOutput),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. DNS LOOKUP TAB
  // ---------------------------------------------------------------------------
  Widget _buildDnsTab(BuildContext context, DiagnosticsState state) {
    final lastDns = state.lastDnsResult;
    final l10n = AppLocalizations.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFlushDnsCard(context, state),
          const SizedBox(height: 16),
          _buildInputCard(
            context,
            title: l10n?.diagDnsHostname ?? 'Hostname to Query',
            subtitle:
                l10n?.diagDnsSubtitle ??
                'Test domain name resolution from router DNS resolver',
            controller: _dnsHostController,
            hint: l10n?.diagDnsHint ?? 'e.g. google.com, openwrt.org',
            quickChips: const [
              'openwrt.org',
              'google.com',
              'cloudflare.com',
              'github.com',
            ],
            onChipTap: (val) => _dnsHostController.text = val,
            extraControls: TextField(
              controller: _dnsServerController,
              decoration: InputDecoration(
                labelText:
                    l10n?.diagDnsServerOptional ??
                    'Custom DNS Server (Optional)',
                hintText:
                    l10n?.diagDnsServerHint ??
                    'e.g. 1.1.1.1 or leave blank for router default',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            isLoading: state.isLookingUpDns,
            onActionPressed: () {
              ref
                  .read(diagnosticsControllerProvider.notifier)
                  .dnsLookup(
                    _dnsHostController.text,
                    server: _dnsServerController.text,
                    context: context,
                  );
            },
            actionLabel: state.isLookingUpDns
                ? (l10n?.diagBtnQueryingDns ?? 'Querying DNS...')
                : (l10n?.diagBtnQueryDns ?? 'Lookup DNS'),
            actionIcon: Icons.search_rounded,
          ),
          const SizedBox(height: 16),
          if (lastDns != null) _buildDnsResultsCard(context, lastDns),
        ],
      ),
    );
  }

  Widget _buildFlushDnsCard(BuildContext context, DiagnosticsState state) {
    final theme = Theme.of(context);
    final flush = state.lastFlushResult;
    final l10n = AppLocalizations.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.cleaning_services_rounded,
                    color: theme.colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n?.diagFlushDnsTitle ?? 'Flush DNS Cache',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n?.diagFlushDnsSubtitle ??
                            'Purge local resolver cache (dnsmasq / unbound) & reload local hosts',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: state.isFlushingDns
                      ? null
                      : () async {
                          final res = await ref
                              .read(diagnosticsControllerProvider.notifier)
                              .flushDns(context: context);
                          if (context.mounted && res != null) {
                            if (res.isSuccess) {
                              context.showToastSuccess(
                                l10n?.diagDnsCacheFlushed ??
                                    'DNS Cache Flushed',
                                subtitle: res.message,
                              );
                            } else {
                              context.showToastError(
                                l10n?.diagFlushDnsFailed ?? 'Flush DNS Failed',
                                subtitle: res.message,
                              );
                            }
                          }
                        },
                  icon: state.isFlushingDns
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(
                    state.isFlushingDns
                        ? (l10n?.diagBtnFlushingDns ?? 'Flushing...')
                        : (l10n?.diagBtnFlushDns ?? 'Flush Cache'),
                  ),
                ),
              ],
            ),
            if (flush != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: flush.isSuccess
                      ? LuciStatusColors.connected.withValues(alpha: 0.08)
                      : LuciStatusColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: flush.isSuccess
                        ? LuciStatusColors.connected.withValues(alpha: 0.3)
                        : LuciStatusColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      flush.isSuccess
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      size: 18,
                      color: flush.isSuccess
                          ? LuciStatusColors.connected
                          : LuciStatusColors.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            flush.message,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: flush.isSuccess
                                  ? LuciStatusColors.connected
                                  : LuciStatusColors.error,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n?.diagStatusUpdatedAt(
                                  '${flush.timestamp.hour.toString().padLeft(2, '0')}:${flush.timestamp.minute.toString().padLeft(2, '0')}:${flush.timestamp.second.toString().padLeft(2, '0')}',
                                ) ??
                                'Status updated at ${flush.timestamp.hour.toString().padLeft(2, '0')}:${flush.timestamp.minute.toString().padLeft(2, '0')}:${flush.timestamp.second.toString().padLeft(2, '0')}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDnsResultsCard(BuildContext context, DnsLookupResult dns) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isSuccess = dns.isSuccess;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSuccess ? Icons.dns : Icons.error_outline,
                  color: isSuccess
                      ? LuciStatusColors.connected
                      : LuciStatusColors.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'DNS: ${dns.query}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (dns.server != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      l10n?.diagViaServer(dns.server!) ?? 'via ${dns.server}',
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (dns.ipv4Addresses.isNotEmpty) ...[
              Text(
                l10n?.diagIpv4Addresses ?? 'IPv4 Addresses (A Records)',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: dns.ipv4Addresses.map((ip) {
                  return ActionChip(
                    avatar: const Icon(Icons.public, size: 14),
                    label: Text(
                      ip,
                      style: GoogleFonts.geistMono(fontWeight: FontWeight.w600),
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: ip));
                      context.showToastSuccess('$ip copied');
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],
            if (dns.ipv6Addresses.isNotEmpty) ...[
              Text(
                l10n?.diagIpv6Addresses ?? 'IPv6 Addresses (AAAA Records)',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: dns.ipv6Addresses.map((ip) {
                  return ActionChip(
                    avatar: const Icon(Icons.language, size: 14),
                    label: Text(
                      ip,
                      style: GoogleFonts.geistMono(fontWeight: FontWeight.w600),
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: ip));
                      context.showToastSuccess('$ip copied');
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],
            if (dns.cnames.isNotEmpty) ...[
              Text(
                l10n?.diagCnames ?? 'Canonical Names (CNAME)',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              ...dns.cnames.map(
                (c) => Text(
                  '• $c',
                  style: GoogleFonts.geistMono(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (dns.rawOutput.isNotEmpty)
              _buildRawConsoleExpansion(context, dns.rawOutput),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 5. ROUTES & ARP TAB
  // ---------------------------------------------------------------------------
  Widget _buildNetworkTablesTab(BuildContext context, DiagnosticsState state) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 0,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: [
                    ButtonSegment(
                      value: 0,
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.alt_route, size: 14),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              l10n?.diagSegmentRoutes ?? 'Routes',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ButtonSegment(
                      value: 1,
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.devices, size: 14),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              l10n?.diagSegmentArp ?? 'ARP',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ButtonSegment(
                      value: 2,
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.hub, size: 14),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              l10n?.diagSegmentConntrack ?? 'Conntrack',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  selected: {_networkTableSegment},
                  onSelectionChanged: (set) {
                    setState(() => _networkTableSegment = set.first);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: l10n?.diagRefreshTables ?? 'Refresh Tables',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: state.isLoadingNetworkTables
                        ? null
                        : () => ref
                              .read(diagnosticsControllerProvider.notifier)
                              .loadNetworkTables(context: context),
                    child: Container(
                      height: 38,
                      width: 36,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: state.isLoadingNetworkTables
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Icons.refresh_rounded,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_networkTableSegment == 0)
            _buildRoutesList(context, state.routes),
          if (_networkTableSegment == 1)
            _buildNeighborsList(context, state.neighbors),
          if (_networkTableSegment == 2)
            _buildConntrackCard(context, state.conntrack),
        ],
      ),
    );
  }

  Widget _buildRoutesList(BuildContext context, List<RouteEntry> routes) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    if (routes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(l10n?.diagNoRoutes ?? 'No route entries found.'),
        ),
      );
    }

    return Column(
      children: routes.map((r) {
        return Card(
          elevation: 1,
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: r.destination));
              if (context.mounted) {
                context.showToastSuccess(
                  l10n?.toastCopiedToClipboard ?? 'Copied to clipboard.',
                  subtitle: r.destination,
                );
              }
            },
            leading: Icon(
              r.isDefault ? Icons.star_rounded : Icons.arrow_forward_rounded,
              color: r.isDefault
                  ? Colors.amber.shade700
                  : theme.colorScheme.primary,
            ),
            title: Text(
              r.destination,
              style: LuciTypography.monoStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${r.gateway != null ? "via ${r.gateway} " : ""}${r.interface != null ? "dev ${r.interface} " : ""}${r.table != null ? "[table: ${r.table}]" : ""}',
              style: LuciTypography.monoStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: r.isDefault
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      l10n?.diagDefaultRouteBadge ?? 'Default',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade800,
                      ),
                    ),
                  )
                : null,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildNeighborsList(
    BuildContext context,
    List<NeighborEntry> neighbors,
  ) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    if (neighbors.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(l10n?.diagNoArp ?? 'No ARP neighbors found.'),
        ),
      );
    }

    return Column(
      children: neighbors.map((n) {
        final isReachable = n.state == 'REACHABLE' || n.state == 'PERMANENT';
        return Card(
          elevation: 1,
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: n.ip));
              if (context.mounted) {
                context.showToastSuccess(
                  l10n?.toastCopiedToClipboard ?? 'Copied to clipboard.',
                  subtitle: n.ip,
                );
              }
            },
            onLongPress: () async {
              final info = '${n.ip} ${n.mac ?? ""}';
              await Clipboard.setData(ClipboardData(text: info));
              if (context.mounted) {
                context.showToastSuccess(
                  l10n?.toastCopiedToClipboard ?? 'Copied to clipboard.',
                  subtitle: info,
                );
              }
            },
            leading: Icon(
              Icons.computer_rounded,
              color: isReachable
                  ? LuciStatusColors.connected
                  : LuciStatusColors.inactive,
            ),
            title: Text(
              n.ip,
              style: LuciTypography.monoStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${n.mac ?? (l10n?.diagUnknownMac ?? "Unknown MAC")} • ${n.interface ?? "dev"}',
              style: LuciTypography.monoStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color:
                    (isReachable
                            ? LuciStatusColors.connected
                            : LuciStatusColors.inactive)
                        .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                n.state,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isReachable
                      ? LuciStatusColors.connected
                      : LuciStatusColors.inactive,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildConntrackCard(BuildContext context, ConntrackInfo? conntrack) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    if (conntrack == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            l10n?.diagNoConntrack ?? 'Connection tracking info unavailable.',
          ),
        ),
      );
    }

    final util = conntrack.utilizationPercent;
    final progressColor = util > 85
        ? LuciStatusColors.error
        : (util > 60 ? Colors.orange : LuciStatusColors.connected);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.hub, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  l10n?.diagConntrackTitle ?? 'Active NAT Connection Tracking',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: conntrack.max > 0 ? (conntrack.count / conntrack.max) : 0,
              minHeight: 10,
              borderRadius: BorderRadius.circular(5),
              color: progressColor,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n?.diagActiveConnectionsCount(conntrack.count) ??
                      '${conntrack.count} active connections',
                  style: GoogleFonts.geistMono(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  l10n?.diagMaxTableConntrack(
                        conntrack.max,
                        util.toStringAsFixed(1),
                      ) ??
                      'Max table: ${conntrack.max} (${util.toStringAsFixed(1)}%)',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 6. EXPORT DIAGNOSTIC REPORT TAB
  // ---------------------------------------------------------------------------
  Widget _buildExportReportTab(BuildContext context, DiagnosticsState state) {
    final theme = Theme.of(context);
    final report = state.lastReport;
    final isGenerating = state.isGeneratingReport;
    final redact = state.redactSensitiveData;
    final l10n = AppLocalizations.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.summarize_rounded,
                        color: theme.colorScheme.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n?.diagExportCardTitle ??
                                  'Generate Diagnostic Report',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              l10n?.diagExportCardSubtitle ??
                                  'Gathers system vitals, routing, ARP neighbors, connectivity & logs into an exportable bundle',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      l10n?.diagMaskSensitive ??
                          'Mask Sensitive Data (Privacy Redaction)',
                    ),
                    subtitle: Text(
                      l10n?.diagMaskSensitiveDesc ??
                          'Anonymizes public WAN IPs and MAC addresses for safe forum sharing',
                    ),
                    value: redact,
                    onChanged: (v) {
                      ref
                          .read(diagnosticsControllerProvider.notifier)
                          .toggleRedaction(v);
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: isGenerating
                          ? null
                          : () {
                              ref
                                  .read(diagnosticsControllerProvider.notifier)
                                  .generateReport(context: context);
                            },
                      icon: isGenerating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.auto_awesome),
                      label: Text(
                        isGenerating
                            ? (l10n?.diagGeneratingBundle ??
                                  'Generating Bundle...')
                            : (l10n?.diagBtnGenerateFullReport ??
                                  'Generate Full Report'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (report != null) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final md = report.generateMarkdown(redact: redact);
                      await Clipboard.setData(ClipboardData(text: md));
                      if (context.mounted) {
                        context.showToastSuccess(
                          l10n?.toastCopiedToClipboard ??
                              'Copied to clipboard.',
                          subtitle:
                              l10n?.diagReportCopied ??
                              'Diagnostic report copied',
                        );
                      }
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: Text(
                      l10n?.diagBtnCopyClipboard ?? 'Copy to Clipboard',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      final md = report.generateMarkdown(redact: redact);
                      final bytes = Uint8List.fromList(utf8.encode(md));
                      final fileName =
                          'openwrt-diagnostic-${report.hostname}-${DateTime.now().millisecondsSinceEpoch}.md';
                      final res =
                          await OsPlatformIntegration.saveDownloadedFileWithResult(
                            bytes: bytes,
                            fileName: fileName,
                          );
                      if (res != null && context.mounted) {
                        await OsPlatformIntegration.showFileDownloadedPrompt(
                          context,
                          res,
                          title:
                              l10n?.diagReportSaved ??
                              'Diagnostic Report Saved',
                          fileLabel: l10n?.diagReportFileLabel ?? 'Report File',
                        );
                      }
                    },
                    icon: const Icon(Icons.download, size: 18),
                    label: Text(l10n?.diagBtnSaveDevice ?? 'Save to Device'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          l10n?.diagReportPreview ?? 'Report Preview',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          tooltip: _isReportSelectable
                              ? (l10n?.diagSwitchSmoothScrolling ??
                                    'Switch to smooth scrolling')
                              : (l10n?.diagEnableTextSelection ??
                                    'Enable text selection'),
                          icon: Icon(
                            _isReportSelectable
                                ? Icons.pan_tool_alt
                                : Icons.text_fields,
                            size: 18,
                            color: _isReportSelectable
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          onPressed: () {
                            setState(
                              () => _isReportSelectable = !_isReportSelectable,
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          tooltip:
                              l10n?.diagCopyPreviewTooltip ?? 'Copy preview',
                          icon: const Icon(Icons.copy, size: 18),
                          onPressed: () async {
                            final md = report.generateMarkdown(redact: redact);
                            await Clipboard.setData(ClipboardData(text: md));
                            if (context.mounted) {
                              context.showToastSuccess(
                                l10n?.toastCopiedToClipboard ??
                                    'Copied to clipboard.',
                              );
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _isReportSelectable
                          ? SelectableText(
                              report.generateMarkdown(redact: redact),
                              style: GoogleFonts.geistMono(fontSize: 11),
                            )
                          : Text(
                              report.generateMarkdown(redact: redact),
                              style: GoogleFonts.geistMono(fontSize: 11),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HELPER WIDGETS
  // ---------------------------------------------------------------------------
  Widget _buildInputCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required String hint,
    List<String> quickChips = const [],
    required ValueChanged<String> onChipTap,
    Widget? extraControls,
    required bool isLoading,
    required VoidCallback onActionPressed,
    required String actionLabel,
    required IconData actionIcon,
  }) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => controller.clear()),
                      )
                    : null,
              ),
            ),
            if (quickChips.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: quickChips.map((chipText) {
                  final label = chipText.startsWith('gw:')
                      ? (l10n?.diagQuickGateway(chipText.substring(3)) ??
                            'Gateway (${chipText.substring(3)})')
                      : chipText;
                  return ActionChip(
                    label: Text(label, style: const TextStyle(fontSize: 11)),
                    onPressed: () => onChipTap(chipText),
                  );
                }).toList(),
              ),
            ],
            if (extraControls != null) ...[
              const SizedBox(height: 12),
              extraControls,
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isLoading ? null : onActionPressed,
                icon: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(actionIcon),
                label: Text(
                  isLoading ? (l10n?.diagRunning ?? 'Running...') : actionLabel,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRawConsoleExpansion(BuildContext context, String rawText) {
    final l10n = AppLocalizations.of(context);
    return ExpansionTile(
      title: Text(
        l10n?.diagRawOutput ?? 'Raw Console Output',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.copy_rounded, size: 16),
        tooltip: 'Copy Raw Output',
        onPressed: () {
          Clipboard.setData(ClipboardData(text: rawText));
          context.showToastSuccess('Raw console output copied');
        },
      ),
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            rawText,
            style: GoogleFonts.geistMono(
              color: Colors.greenAccent,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  _SliverTabBarDelegate({required this.child, this.height = 54});

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
