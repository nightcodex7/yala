// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/luci_app_bar.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/modules/core/luci_module_registry.dart';
import 'package:yet_another_luci_app/modules/wireless_management/models/wireless_info.dart';
import 'package:yet_another_luci_app/utils/logger.dart';
import 'package:yet_another_luci_app/utils/release_utils.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/widgets/luci_loading_states.dart';
import 'package:yet_another_luci_app/modules/system_monitoring/models/system_metrics.dart';
import 'package:yet_another_luci_app/modules/system_monitoring/models/router_temperature.dart';
import 'package:yet_another_luci_app/modules/system_monitoring/screens/system_monitoring_screen.dart';
import 'package:yet_another_luci_app/modules/system_monitoring/widgets/add_rpc_handler_dialog.dart';
import 'package:yet_another_luci_app/modules/wireless_management/screens/guest_wifi_management_screen.dart';
import 'package:yet_another_luci_app/modules/vpn_connectivity/screens/vpn_connectivity_screen.dart';
import 'package:yet_another_luci_app/screens/manage_routers_screen.dart';
import 'package:yet_another_luci_app/widgets/rpc_permissions_dialog.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';

import 'package:shared_preferences/shared_preferences.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  final bool isTabActive;

  const DashboardScreen({super.key, this.isTabActive = true});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final ScrollController _wanScrollController = ScrollController();
  bool _dismissedRpcWarning = true;
  Widget? _lastRenderedScaffold;
  String? _lastSelectedRouterId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lastRenderedScaffold = null;
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isTabActive != widget.isTabActive && widget.isTabActive) {
      _lastRenderedScaffold = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _checkRpcWarningStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LuciToastManager.dismissAllLoading();
      final appState = ref.read(appStateProvider);
      if (appState.dashboardData == null ||
          appState.dashboardData?['boardInfo'] == null) {
        appState.fetchDashboardData(force: true);
      }
    });
  }

  Future<void> _checkRpcWarningStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dismissed =
          prefs.getBool('hint_dismissed_rpc_missing_warning') ?? false;
      if (mounted) {
        setState(() {
          _dismissedRpcWarning = dismissed;
        });
      }
    } catch (_) {}
  }

  Future<void> _dismissRpcWarning() async {
    setState(() {
      _dismissedRpcWarning = true;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hint_dismissed_rpc_missing_warning', true);
    } catch (_) {}
  }

  @override
  void dispose() {
    _wanScrollController.dispose();
    super.dispose();
  }

  ({Color background, Color foreground}) _channelColors(String channel) {
    switch (channel) {
      case 'snapshot':
        return (
          background: Colors.orange.withValues(alpha: 0.15),
          foreground: Colors.orange.shade800,
        );
      case 'beta':
        return (
          background: Colors.blue.withValues(alpha: 0.15),
          foreground: Colors.blue.shade800,
        );
      case 'rc':
        return (
          background: Colors.purple.withValues(alpha: 0.15),
          foreground: Colors.purple.shade800,
        );
      case 'testing':
        return (
          background: Colors.amber.withValues(alpha: 0.18),
          foreground: Colors.amber.shade900,
        );
      default:
        return (
          background: Colors.green.withValues(alpha: 0.15),
          foreground: Colors.green.shade800,
        );
    }
  }

  Widget _buildDeviceInfoCard(AppState appState) {
    final l10n = AppLocalizations.of(context);
    final boardInfo =
        appState.dashboardData?['boardInfo'] as Map<String, dynamic>?;
    final model =
        boardInfo?['model']?.toString() ??
        (appState.capabilities?.boardName.isNotEmpty == true
            ? appState.capabilities!.boardName
            : 'N/A');
    final release = boardInfo?['release'] as Map<String, dynamic>?;

    final releaseInfo = deriveDistributionInfo(
      release ?? appState.capabilities?.releaseVersion,
      model: model,
    );

    final versionDisplay = releaseInfo.version != 'N/A'
        ? releaseInfo.version
        : (release?['version']?.toString() ?? 'N/A');
    final channelLabel = releaseInfo.channel.toUpperCase();
    final channelColors = _channelColors(releaseInfo.channel);

    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurface,
    );
    final valueStyle = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold);

    final versionRow = Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: [
        Text(versionDisplay, style: valueStyle, textAlign: TextAlign.center),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: channelColors.background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            channelLabel,
            style: TextStyle(
              color: channelColors.foreground,
              fontWeight: FontWeight.bold,
              fontSize: Theme.of(context).textTheme.bodySmall?.fontSize,
            ),
          ),
        ),
      ],
    );

    return SizedBox(
      width: double.infinity,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n?.labelModel ?? 'Model',
                      style: labelStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      model,
                      style: valueStyle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      releaseInfo.distributionName,
                      style: labelStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    versionRow,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleWithTimestamp(String title, AppState appState) {
    Color statusColor;
    String tooltipMsg;

    switch (appState.connectionStatus) {
      case RouterConnectionStatus.connected:
        statusColor = LuciStatusColors.connectionDotColor(context);
        tooltipMsg = 'Router Connected';
        break;
      case RouterConnectionStatus.reconnecting:
        statusColor = LuciStatusColors.warningColor(context);
        tooltipMsg = 'Reconnecting to Router...';
        break;
      case RouterConnectionStatus.disconnected:
        statusColor = Theme.of(context).colorScheme.error;
        tooltipMsg = 'Router Disconnected';
        break;
    }

    final hasMultipleRouters = appState.routers.length > 1;

    final Widget titleRow = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Tooltip(
          message: tooltipMsg,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (hasMultipleRouters) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ],
    );

    if (hasMultipleRouters) {
      return InkWell(
        onTap: () => _showRouterSwitchModal(context, appState),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: titleRow,
        ),
      );
    }

    return titleRow;
  }

  void _showRouterSwitchModal(BuildContext context, AppState appState) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final colorScheme = theme.colorScheme;
    final selectedRouterId = appState.selectedRouter?.id;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (bottomSheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(Icons.router_rounded, color: colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l10n?.manageRoutersTitle ?? 'Switch Router',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.settings_outlined, size: 16),
                      label: Text(l10n?.btnManage ?? 'Manage'),
                      onPressed: () {
                        Navigator.pop(bottomSheetContext);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const ManageRoutersScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  itemCount: appState.routers.length,
                  itemBuilder: (context, index) {
                    final r = appState.routers[index];
                    final isSelected = r.id == selectedRouterId;
                    final displayName = (r.name != null && r.name!.isNotEmpty)
                        ? r.name!
                        : (r.lastKnownHostname != null &&
                              r.lastKnownHostname!.isNotEmpty)
                        ? r.lastKnownHostname!
                        : r.ipAddress;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isSelected
                            ? colorScheme.primaryContainer
                            : colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.router_rounded,
                          color: isSelected
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        displayName,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text('${r.ipAddress} (${r.username})'),
                      trailing: isSelected
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 14,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Active',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : null,
                      onTap: () {
                        Navigator.pop(bottomSheetContext);
                        if (!isSelected) {
                          appState.selectRouter(r.id, context: context);
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  double _calculateNiceMaxBits(double maxDataBytesPerSec) {
    final double bitsPerSec = maxDataBytesPerSec * 8.0;
    final double target = math.max(bitsPerSec * 1.25, 64000.0);

    final double exponent = (math.log(target) / math.ln10).floorToDouble();
    final double magnitude = math.pow(10, exponent).toDouble();
    final double residual = target / magnitude;

    double niceResidual;
    if (residual <= 1.0) {
      niceResidual = 1.0;
    } else if (residual <= 1.5) {
      niceResidual = 1.5;
    } else if (residual <= 2.0) {
      niceResidual = 2.0;
    } else if (residual <= 2.5) {
      niceResidual = 2.5;
    } else if (residual <= 5.0) {
      niceResidual = 5.0;
    } else {
      niceResidual = 10.0;
    }

    return niceResidual * magnitude;
  }

  Widget _buildRealtimeThroughputCard(AppState appState) {
    final prefs = appState.dashboardPreferences;

    List<double> rxHistory;
    List<double> txHistory;
    double currentRxRate;
    double currentTxRate;
    String throughputLabel = '';

    if (!prefs.showAllThroughput && prefs.primaryThroughputInterface != null) {
      final interface = prefs.primaryThroughputInterface!;
      rxHistory = appState.getRxHistoryForInterface(interface);
      if (rxHistory.isEmpty) {
        rxHistory = appState.rxHistory;
      }
      txHistory = appState.getTxHistoryForInterface(interface);
      if (txHistory.isEmpty) {
        txHistory = appState.txHistory;
      }
      currentRxRate = appState.getCurrentRxRateForInterface(interface);
      if (currentRxRate == 0 && appState.currentRxRate > 0) {
        currentRxRate = appState.currentRxRate;
      }
      currentTxRate = appState.getCurrentTxRateForInterface(interface);
      if (currentTxRate == 0 && appState.currentTxRate > 0) {
        currentTxRate = appState.currentTxRate;
      }
      throughputLabel = ' - $interface';
    } else {
      rxHistory = appState.rxHistory;
      txHistory = appState.txHistory;
      currentRxRate = appState.currentRxRate;
      currentTxRate = appState.currentTxRate;
    }

    double maxDataVal = 0.0;
    for (final val in rxHistory) {
      if (val > maxDataVal) maxDataVal = val;
    }
    for (final val in txHistory) {
      if (val > maxDataVal) maxDataVal = val;
    }

    final double niceMaxBits = _calculateNiceMaxBits(maxDataVal);
    final double chartMaxY = niceMaxBits / 8.0;
    final double chartInterval = chartMaxY / 4.0;

    final hasValidData =
        rxHistory.isNotEmpty ||
        txHistory.isNotEmpty ||
        currentRxRate > 0 ||
        currentTxRate > 0;
    final isSwitchingRouter =
        appState.isLoading && appState.dashboardData == null;

    final card = Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (throughputLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Center(
                child: Text(
                  'Throughput$throughputLabel',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Center(
                    child: _buildSpeedIndicator(
                      Icons.arrow_downward,
                      LuciColors.rx,
                      '',
                      isSwitchingRouter ? 0.0 : currentRxRate,
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: _buildSpeedIndicator(
                      Icons.arrow_upward,
                      LuciColors.tx,
                      '',
                      isSwitchingRouter ? 0.0 : currentTxRate,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(0, 0.2),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                      child: child,
                    ),
                  );
                },
                child: hasValidData && !isSwitchingRouter
                    ? Column(
                        key: const ValueKey('throughput_chart_content'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(
                                bottom: 12.0,
                                left: 4.0,
                                right: 12.0,
                              ),
                              child: LineChart(
                                key: ValueKey(
                                  'chart_${appState.selectedRouter?.id}',
                                ),
                                LineChartData(
                                  minX: 0,
                                  maxX: 49,
                                  minY: 0,
                                  maxY: chartMaxY,
                                  gridData: FlGridData(
                                    show: true,
                                    drawVerticalLine: false,
                                    horizontalInterval: chartInterval > 0
                                        ? chartInterval
                                        : 1.0,
                                    getDrawingHorizontalLine: (val) => FlLine(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outlineVariant
                                          .withValues(alpha: 0.2),
                                      strokeWidth: 1,
                                    ),
                                  ),
                                  titlesData: FlTitlesData(
                                    show: true,
                                    topTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                    rightTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                    bottomTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                    leftTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: 72,
                                        interval: chartInterval > 0
                                            ? chartInterval
                                            : 1.0,
                                        getTitlesWidget: (value, meta) {
                                          if (value < -0.001 ||
                                              value >= chartMaxY * 0.95) {
                                            return const SizedBox.shrink();
                                          }
                                          return SideTitleWidget(
                                            meta: meta,
                                            space: 6,
                                            fitInside:
                                                SideTitleFitInsideData.fromTitleMeta(
                                                  meta,
                                                ),
                                            child: Text(
                                              _formatSpeedCompact(value),
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant
                                                    .withValues(alpha: 0.75),
                                                fontWeight: FontWeight.w600,
                                              ),
                                              textAlign: TextAlign.right,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  borderData: FlBorderData(show: false),
                                  lineTouchData: LineTouchData(
                                    touchTooltipData: LineTouchTooltipData(
                                      fitInsideVertically: true,
                                      getTooltipColor: (LineBarSpot spot) =>
                                          Theme.of(context).colorScheme.surface
                                              .withValues(alpha: 0.95),
                                      tooltipBorderRadius:
                                          BorderRadius.circular(8),
                                      tooltipPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                      getTooltipItems:
                                          (List<LineBarSpot> touchedSpots) {
                                            return touchedSpots.map((barSpot) {
                                              final flSpot = barSpot;
                                              final isRx =
                                                  barSpot.barIndex == 0;
                                              final Color color =
                                                  flSpot
                                                      .bar
                                                      .gradient
                                                      ?.colors
                                                      .first ??
                                                  flSpot.bar.color ??
                                                  Colors.white;

                                              return LineTooltipItem(
                                                '${isRx ? "RX" : "TX"}: ${_formatSpeed(flSpot.y)}',
                                                TextStyle(
                                                  color: color,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                                textAlign: TextAlign.left,
                                              );
                                            }).toList();
                                          },
                                    ),
                                  ),
                                  lineBarsData: [
                                    _buildLineChartBarData(rxHistory, [
                                      LuciColors.rx,
                                      LuciColors.rx,
                                    ], isRx: true),
                                    _buildLineChartBarData(txHistory, [
                                      LuciColors.tx,
                                      LuciColors.tx,
                                    ], isRx: false),
                                  ],
                                ),
                                duration: Duration.zero,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Center(
                        key: ValueKey('loading_${appState.selectedRouter?.id}'),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.trending_up,
                                size: 48,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                isSwitchingRouter
                                    ? 'Switching router...'
                                    : 'Collecting throughput data...',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.8),
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

    return card;
  }

  Widget _buildSpeedIndicator(
    IconData icon,
    Color color,
    String label,
    double speed,
  ) {
    final displaySpeed = speed.isNaN || speed.isInfinite || speed < 0
        ? 0.0
        : speed;
    final speedText = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        _formatSpeed(displaySpeed),
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        if (label.isNotEmpty)
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodyMedium),
                speedText,
              ],
            ),
          )
        else
          Flexible(child: speedText),
      ],
    );
  }

  LineChartBarData _buildLineChartBarData(
    List<double> data,
    List<Color> gradientColors, {
    int maxPoints = 50,
    bool isRx = true,
  }) {
    if (data.isEmpty) {
      return LineChartBarData(
        spots: [const FlSpot(0, 0), FlSpot((maxPoints - 1).toDouble(), 0)],
        isCurved: false,
        gradient: LinearGradient(colors: gradientColors),
        barWidth: isRx ? 2.5 : 2.0,
        isStrokeCapRound: true,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      );
    }

    final int n = data.length;
    final int offset = maxPoints > n ? maxPoints - n : 0;

    final spots = data.asMap().entries.map((e) {
      final x = (offset + e.key).toDouble();
      return FlSpot(x, e.value);
    }).toList();

    return LineChartBarData(
      spots: spots,
      isCurved: spots.length > 1,
      curveSmoothness: 0.25,
      preventCurveOverShooting: true,
      preventCurveOvershootingThreshold: 0.0,
      gradient: LinearGradient(colors: gradientColors),
      barWidth: 2.8,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
    );
  }

  String _formatSpeed(double bytesPerSecond) {
    // Handle edge cases
    if (bytesPerSecond.isNaN ||
        bytesPerSecond.isInfinite ||
        bytesPerSecond < 0) {
      return '0 bps';
    }

    final speedUnit = ref.read(appStateProvider).dashboardPreferences.speedUnit;
    if (speedUnit == 'bytes') {
      if (bytesPerSecond < 1024) {
        return '${bytesPerSecond.toStringAsFixed(0)} B/s';
      }
      if (bytesPerSecond < 1024 * 1024) {
        return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
      }
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(2)} MB/s';
    } else {
      final bitsPerSecond = bytesPerSecond * 8;
      if (bitsPerSecond < 1_000) {
        return '${bitsPerSecond.toStringAsFixed(0)} bps';
      }
      if (bitsPerSecond < 1_000_000) {
        return '${(bitsPerSecond / 1_000).toStringAsFixed(1)} Kbps';
      }
      return '${(bitsPerSecond / 1_000_000).toStringAsFixed(2)} Mbps';
    }
  }

  String _formatSpeedCompact(double bytesPerSecond) {
    if (bytesPerSecond.isNaN ||
        bytesPerSecond.isInfinite ||
        bytesPerSecond <= 0) {
      return '0 bps';
    }
    final bits = bytesPerSecond * 8;
    if (bits < 1000) {
      return '${bits.toStringAsFixed(0)} bps';
    } else if (bits < 1000000) {
      final val = bits / 1000;
      final str = val % 1 == 0
          ? val.toStringAsFixed(0)
          : val.toStringAsFixed(1);
      return '$str Kbps';
    } else {
      final val = bits / 1000000;
      final str = val % 1 == 0
          ? val.toStringAsFixed(0)
          : val.toStringAsFixed(1);
      return '$str Mbps';
    }
  }

  // Consistent card builder for all dashboard vitals and summary cards
  Widget _buildVitalsColumn(
    BuildContext context, {
    required String label,
    required String value,
    Color? valueColor,
    bool isLoading = false,
  }) {
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurface,
    );
    final valueStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.bold,
      color: valueColor,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, style: labelStyle),
        ),
        const SizedBox(height: 4),
        if (isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 2.0),
            child: LuciSkeleton(
              width: 44,
              height: 14,
              borderRadius: BorderRadius.all(Radius.circular(6)),
            ),
          )
        else
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: valueStyle, textAlign: TextAlign.center),
          ),
      ],
    );
  }

  Widget _buildSystemVitalsCard(AppState appState) {
    final sysInfo = appState.dashboardData?['sysInfo'] as Map<String, dynamic>?;
    final boardInfo =
        appState.dashboardData?['boardInfo'] as Map<String, dynamic>?;
    final bool isVitalsLoading = sysInfo == null || sysInfo.isEmpty;
    final metrics = SystemMetrics.fromSysInfo(
      sysInfo,
      boardInfo: boardInfo,
      temperature: appState.dashboardData?['temperature'],
    );

    final uptimeValue = isVitalsLoading ? '' : metrics.formattedUptime;
    final cpuLoadValue = isVitalsLoading
        ? ''
        : '${metrics.cpuUsagePercent.toStringAsFixed(0)}%';
    final loadAvgValue = isVitalsLoading
        ? ''
        : metrics.load1m.toStringAsFixed(2);
    final memoryValue = isVitalsLoading
        ? ''
        : (metrics.totalMemoryBytes > 0
              ? '${metrics.memoryUsagePercent.toStringAsFixed(0)}%'
              : 'N/A');
    final prefs = appState.dashboardPreferences;
    final tempValue = isVitalsLoading
        ? ''
        : metrics.formattedTemperatureForUnit(prefs.temperatureUnit);
    final vitals = <Widget>[];
    final l10n = AppLocalizations.of(context);
    if (prefs.showCpuLoad) {
      vitals.add(
        _buildVitalsColumn(
          context,
          label: l10n?.cpuUsage ?? 'CPU Usage',
          value: cpuLoadValue,
          isLoading: isVitalsLoading,
        ),
      );
    }
    if (prefs.showRamUsage) {
      vitals.add(
        _buildVitalsColumn(
          context,
          label: l10n?.memoryUsage ?? 'Memory',
          value: memoryValue,
          isLoading: isVitalsLoading,
        ),
      );
    }
    if (prefs.showLoadAverage) {
      vitals.add(
        _buildVitalsColumn(
          context,
          label: l10n?.metricLoadAvg ?? 'Load Average',
          value: loadAvgValue,
          isLoading: isVitalsLoading,
        ),
      );
    }
    if (prefs.showUptime) {
      vitals.add(
        _buildVitalsColumn(
          context,
          label: l10n?.systemUptime ?? 'Uptime',
          value: uptimeValue,
          isLoading: isVitalsLoading,
        ),
      );
    }

    // Dynamic temperature field: only added if hardware sensor exists and has valid reading
    final tempObj = metrics.temperature;
    final hasUsableTemp =
        !isVitalsLoading &&
        tempObj != null &&
        tempObj.isSupported &&
        tempObj.mainTemperature != null;
    if (prefs.showTemperature && hasUsableTemp) {
      Color? tempColor;
      if (tempObj.status == ThermalStatus.hot) {
        tempColor = Colors.red;
      } else if (tempObj.status == ThermalStatus.warm) {
        tempColor = Colors.orange;
      }
      vitals.add(
        _buildVitalsColumn(
          context,
          label: l10n?.metricTemperature ?? 'Temperature',
          value: tempValue,
          valueColor: tempColor,
        ),
      );
    }

    if (vitals.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const SystemMonitoringScreen(),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 520;
              if (isNarrow && vitals.length > 3) {
                final mid = (vitals.length / 2).ceil();
                final top = vitals.sublist(0, mid);
                final bottom = vitals.sublist(mid);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: top.map((v) => Expanded(child: v)).toList()),
                    const SizedBox(height: 10),
                    Row(
                      children: bottom.map((v) => Expanded(child: v)).toList(),
                    ),
                  ],
                );
              }
              return Row(
                children: vitals.map((v) => Expanded(child: v)).toList(),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget? _buildTemperaturePromptPill(BuildContext context, AppState appState) {
    final prefs = appState.dashboardPreferences;
    if (prefs.dismissTemperaturePrompt) {
      return null;
    }
    if (!prefs.showTemperature) {
      return null;
    }
    final data = appState.dashboardData;
    if (data == null) {
      return null;
    }
    final rawTemp = data['temperature'];
    final tempObj = rawTemp is RouterTemperature
        ? rawTemp
        : (rawTemp != null ? RouterTemperature.parse(rawTemp) : null);
    if (tempObj == null) {
      return null;
    }
    if (tempObj.isFullySupported ||
        (tempObj.isSupported && tempObj.mainTemperature != null)) {
      return null;
    }
    // Context-aware & hardware check:
    // Only display if the router physically possesses sensors and needs the script.
    // If the router hardware lacks thermal sensors entirely, DO NOT show!
    if (!tempObj.needsNativeHandler) {
      return null;
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final Color bgColor = isDark
        ? const Color(0xFF332A15)
        : const Color(0xFFFEF3C7);
    final Color borderColor = isDark
        ? const Color(0xFF854D0E)
        : const Color(0xFFFCD34D);
    final Color iconColor = isDark
        ? const Color(0xFFFBBF24)
        : const Color(0xFFB45309);
    final Color textColor = isDark
        ? const Color(0xFFFDE68A)
        : const Color(0xFF92400E);

    return Container(
      margin: const EdgeInsets.only(left: 8.0),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(13),
              ),
              onTap: () {
                AddRpcHandlerDialog.show(
                  context,
                  onDismissPermanently: () async {
                    await appState.saveDashboardPreferences(
                      prefs.copyWith(dismissTemperaturePrompt: true),
                    );
                    if (context.mounted) {
                      context.showToastInfo(
                        'Temperature script prompt dismissed permanently',
                      );
                    }
                  },
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 3.5,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.thermostat_outlined, size: 14, color: iconColor),
                    const SizedBox(width: 4),
                    Text(
                      'Temp Script Missing',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(width: 1, height: 12, color: borderColor),
            InkWell(
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(13),
              ),
              onTap: () async {
                await appState.saveDashboardPreferences(
                  prefs.copyWith(dismissTemperaturePrompt: true),
                );
                if (context.mounted) {
                  context.showToastInfo(
                    'Temperature script prompt dismissed permanently',
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 3.5,
                ),
                child: Tooltip(
                  message: "Permanently dismiss temperature prompt",
                  child: Icon(Icons.close_rounded, size: 13, color: textColor),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClientsSummaryCard(AppState appState) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    final clients = appState.clients;
    final connectedClients = clients.where((c) => c.isConnected).toList();
    final wiredCount = connectedClients
        .where((c) => c.connectionType == ConnectionType.wired)
        .length;
    final wirelessCount = connectedClients
        .where((c) => c.connectionType == ConnectionType.wireless)
        .length;
    final isLoading =
        !appState.hasFetchedClients &&
        (appState.isDashboardLoading ||
            appState.isClientsLoading ||
            appState.dashboardData == null);

    Widget buildCountText(int count) {
      if (isLoading) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 2.0),
          child: LuciSkeleton(
            width: 76,
            height: 14,
            borderRadius: BorderRadius.all(Radius.circular(6)),
          ),
        );
      }
      return Text(
        l10n?.clientsConnectedCount(count) ?? '$count Connected',
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                ),
                onTap: () {
                  appState.requestTab(
                    2,
                    clientCategoryFilter: ClientCategoryFilter.wired,
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12.0,
                    horizontal: 12.0,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colorScheme.secondary.withValues(
                              alpha: 0.25,
                            ),
                            width: 0.8,
                          ),
                        ),
                        child: Icon(
                          Icons.lan,
                          color: colorScheme.onSecondaryContainer,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                l10n?.cardWiredClients ?? 'Wired Clients',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            buildCountText(wiredCount),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              width: 1,
              height: 36,
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
            Expanded(
              child: InkWell(
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
                onTap: () {
                  appState.requestTab(
                    2,
                    clientCategoryFilter: ClientCategoryFilter.wireless,
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12.0,
                    horizontal: 12.0,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colorScheme.primary.withValues(alpha: 0.25),
                            width: 0.8,
                          ),
                        ),
                        child: Icon(
                          Icons.wifi,
                          color: colorScheme.onPrimaryContainer,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                l10n?.cardWirelessClients ?? 'Wireless Clients',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            buildCountText(wirelessCount),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                appState.requestTab(
                  2,
                  clientCategoryFilter: ClientCategoryFilter.all,
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isPublicIp(String ipText) {
    if (ipText.isEmpty ||
        ipText == 'No IPv4' ||
        ipText == 'No IPv6' ||
        ipText == 'N/A') {
      return false;
    }
    final raw = ipText.split('/')[0].trim();

    if (raw.contains('.')) {
      final parts = raw.split('.');
      if (parts.length != 4) return false;
      final octet1 = int.tryParse(parts[0]);
      final octet2 = int.tryParse(parts[1]);
      if (octet1 == null || octet2 == null) return false;

      // Private IPv4 ranges (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, loopback, link-local)
      if (octet1 == 10) return false;
      if (octet1 == 172 && octet2 >= 16 && octet2 <= 31) return false;
      if (octet1 == 192 && octet2 == 168) return false;
      if (octet1 == 127) return false;
      if (octet1 == 169 && octet2 == 254) return false;

      return true;
    } else if (raw.contains(':')) {
      final lower = raw.toLowerCase();
      if (lower == '::1') return false; // Loopback
      if (lower.startsWith('fe80:') ||
          lower.startsWith('fe8') ||
          lower.startsWith('fe9') ||
          lower.startsWith('fea') ||
          lower.startsWith('feb')) {
        return false; // Link-local
      }
      if (lower.startsWith('fc') || lower.startsWith('fd')) {
        return false; // Private ULA
      }

      return true;
    }
    return false;
  }

  String _maskIpString(String ipText) {
    if (ipText == 'No IPv4' ||
        ipText == 'No IPv6' ||
        ipText == 'N/A' ||
        ipText.isEmpty) {
      return ipText;
    }
    final parts = ipText.split('/');
    final rawIp = parts[0].trim();
    final prefix = parts.length > 1 ? '/${parts[1]}' : '';

    if (rawIp.contains('.')) {
      final octets = rawIp.split('.');
      if (octets.length == 4) {
        return '${octets[0]}.***.***.${octets[3]}$prefix';
      }
      return '***.***.***.***$prefix';
    }
    if (rawIp.contains(':')) {
      final segments = rawIp.split(':');
      if (segments.length >= 3) {
        return '${segments.first}:****:****::${segments.last}$prefix';
      }
      return '****:****::****$prefix';
    }
    return '••••••••$prefix';
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    IconData icon, {
    Widget? action,
    int maxLines = 2,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14.0, bottom: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: maxLines,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                      letterSpacing: 0.3,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action],
        ],
      ),
    );
  }

  void _showWirelessClientsBottomSheet(
    BuildContext context,
    String ssid,
    String radioName,
    String bandLabel,
    String channel,
    List<WirelessStation> stations,
    AppState appState,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        final leasesRaw = appState.dashboardData?['dhcpLeases'];
        final leases = <String, Map<String, dynamic>>{};
        if (leasesRaw is Map<String, dynamic>) {
          final dhcpList = leasesRaw['dhcp_leases'] ?? leasesRaw['leases'];
          if (dhcpList is List) {
            for (final lease in dhcpList) {
              if (lease is Map<String, dynamic>) {
                final mac =
                    lease['macaddr']?.toString().toUpperCase() ??
                    lease['mac']?.toString().toUpperCase();
                if (mac != null) {
                  leases[mac] = lease;
                }
              }
            }
          }
        }

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.wifi_tethering,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ssid,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '$radioName • $bandLabel • Channel $channel',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Chip(
                    label: Text(
                      l10n?.dashStationsConnected(stations.length) ??
                          '${stations.length} connected',
                    ),
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    labelStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              if (stations.isEmpty)
                Flexible(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24.0),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.devices_other,
                              size: 40,
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No clients currently associated with $radioName ($ssid).',
                              style: TextStyle(color: Colors.grey.shade600),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: stations.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final st = stations[index];
                      final normMac = st.macAddress.toUpperCase();
                      final lease = leases[normMac];
                      final hostname =
                          lease?['hostname']?.toString() ??
                          lease?['name']?.toString() ??
                          'Wireless Client';
                      final ip =
                          lease?['ipaddr']?.toString() ??
                          lease?['ip']?.toString() ??
                          'DHCP Unassigned';

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.15),
                          child: Icon(
                            Icons.devices,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          hostname,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          'IP: $ip\nMAC: ${st.macAddress}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  st.formattedSignal,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color:
                                        st.signalDbm != null &&
                                            st.signalDbm! > -65
                                        ? LuciStatusColors.connected
                                        : Colors.orange,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  st.signalQualityLabel,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                            PopupMenuButton<String>(
                              tooltip: '',
                              icon: const Icon(Icons.more_vert, size: 20),
                              onSelected: (val) async {
                                Navigator.pop(context);
                                final actionKey =
                                    'pause_internet_${st.macAddress}';
                                final isPaused = appState.isInternetPaused(
                                  st.macAddress,
                                );
                                if (val == 'pause') {
                                  context.showToastLoading(
                                    '${!isPaused ? "Pausing" : "Resuming"} internet access...',
                                    subtitle: 'Target: $hostname',
                                    actionKey: actionKey,
                                  );
                                  final res = await appState
                                      .pauseClientInternet(
                                        st.macAddress,
                                        pause: !isPaused,
                                        context: context,
                                      );
                                  if (context.mounted) {
                                    if (res) {
                                      context.showToastSuccess(
                                        'Internet ${!isPaused ? "paused" : "restored"} for $hostname.',
                                        actionKey: actionKey,
                                      );
                                    } else {
                                      context.showToastError(
                                        'Failed to update internet access for $hostname.',
                                        actionKey: actionKey,
                                      );
                                    }
                                  }
                                }
                              },
                              itemBuilder: (ctx) {
                                final isPaused = appState.isInternetPaused(
                                  st.macAddress,
                                );
                                return [
                                  PopupMenuItem(
                                    value: 'pause',
                                    child: Row(
                                      children: [
                                        Icon(
                                          isPaused
                                              ? Icons.play_circle_outline
                                              : Icons.pause_circle_outline,
                                          color: isPaused
                                              ? LuciStatusColors.connected
                                              : Colors.orange,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          isPaused
                                              ? 'Resume Internet'
                                              : 'Pause Internet',
                                        ),
                                      ],
                                    ),
                                  ),
                                ];
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWirelessNetworksCard(AppState appState) {
    final l10n = AppLocalizations.of(context);
    WirelessOverview overview;
    try {
      overview = WirelessOverview.fromDashboardData(
        appState.dashboardData,
        isReviewerMode: appState.reviewerModeEnabled,
      );
    } catch (e, stack) {
      Logger.error(
        'Failed to parse wireless overview for dashboard: $e',
        stack,
      );
      overview = const WirelessOverview(radios: []);
    }

    if (overview.radios.isEmpty) {
      return Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 14.0),
          child: Row(
            children: [
              Icon(
                Icons.wifi_off_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n?.noWirelessRadiosFound ??
                      'No wireless interfaces configured',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final cardWidgets = <Widget>[];

    for (final radio in overview.radios) {
      for (final iface in radio.interfaces) {
        final ssid = iface.ssid;
        final isEnabled = iface.isEnabled;

        cardWidgets.add(
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                _showWirelessClientsBottomSheet(
                  context,
                  ssid,
                  radio.name,
                  radio.bandLabel,
                  iface.channel,
                  iface.stations,
                  appState,
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: isEnabled
                          ? Colors.blue.withValues(alpha: 0.15)
                          : Colors.grey.withValues(alpha: 0.15),
                      child: Icon(
                        Icons.wifi,
                        color: isEnabled ? Colors.blue : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  ssid,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isEnabled
                                      ? LuciStatusColors.connectedColor(
                                          context,
                                        ).withValues(alpha: 0.15)
                                      : Theme.of(context).colorScheme.error
                                            .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isEnabled ? 'ENABLED' : 'DISABLED',
                                  style: TextStyle(
                                    color: isEnabled
                                        ? LuciStatusColors.connectedColor(
                                            context,
                                          )
                                        : Theme.of(context).colorScheme.error,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Radio: ${radio.name} (${radio.bandLabel}) • Ch ${iface.channel} • ${iface.encryption}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.devices,
                                size: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                l10n?.cardClientsCount(iface.stations.length) ??
                                    '${iface.stations.length} clients',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n?.cardTapForClients ?? 'Tap for clients',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: cardWidgets,
    );
  }

  IconData _getInterfaceIcon(String name, String proto) {
    final lower = name.toLowerCase();

    // Check name-based patterns first
    if (lower.contains('wan')) {
      return Icons.public_rounded;
    }
    if (lower.contains('lan')) {
      return Icons.router_rounded;
    }
    if (lower.contains('iot')) {
      return Icons.sensors_rounded;
    }
    if (lower.contains('guest')) {
      return Icons.people_rounded;
    }
    if (lower.contains('dmz')) {
      return Icons.security_rounded;
    }
    if (lower.contains('docker')) {
      return Icons.computer_rounded;
    }
    if (lower.contains('bridge') || lower.startsWith('br-')) {
      return Icons.hub_rounded;
    }
    if (lower.contains('vlan')) {
      return Icons.layers_rounded;
    }
    if (lower.startsWith('eth')) {
      return Icons.cable_rounded;
    }
    if (lower.startsWith('wlan')) {
      return Icons.wifi_rounded;
    }

    // Check protocol-based patterns
    switch (proto) {
      case 'wireguard':
      case 'openvpn':
        return Icons.vpn_key_rounded;
      case 'pppoe':
        return Icons.settings_ethernet_rounded;
      case 'dhcp':
      case 'static':
        return Icons.lan_rounded;
      default:
        return Icons.lan_rounded;
    }
  }

  Widget _buildInterfaceStatusCards(AppState appState) {
    final prefs = appState.dashboardPreferences;
    final rawDump = appState.dashboardData?['interfaceDump']?['interface'];
    final interfaces = rawDump is List
        ? rawDump
        : (rawDump is Map ? rawDump.values.toList() : null);
    Widget buildEmptyInterfaceCard() {
      return Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 14.0),
          child: Row(
            children: [
              Icon(
                Icons.lan_outlined,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No network interfaces active',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (interfaces == null || interfaces.isEmpty) {
      return buildEmptyInterfaceCard();
    }

    final wanVpnInterfaces = interfaces.where((item) {
      if (item is! Map) return false;
      final interface = item;
      final name = interface['interface']?.toString() ?? '';
      final isUp =
          interface['up'] == true ||
          interface['up'] == 1 ||
          interface['up'] == '1';

      // Skip loopback interface
      if (name == 'loopback' || name == 'lo') return false;

      // Hide inactive interfaces if preference disabled
      if (!prefs.showInactiveInterfaces && !isUp) return false;

      // If preferences are empty, show all interfaces by default
      if (prefs.enabledWiredInterfaces.isEmpty) {
        return true;
      }

      return prefs.enabledWiredInterfaces.contains(name);
    }).toList();

    if (wanVpnInterfaces.isEmpty) {
      return buildEmptyInterfaceCard();
    }

    final List<Widget> interfaceCardWidgets = [];
    for (var item in wanVpnInterfaces) {
      if (item is! Map) continue;
      final interface = item;
      final name = interface['interface']?.toString() ?? 'N/A';
      final isUp =
          interface['up'] == true ||
          interface['up'] == 1 ||
          interface['up'] == '1';
      final proto = (interface['proto']?.toString() ?? '').toUpperCase();
      final l3Dev =
          interface['l3_device']?.toString() ??
          interface['device']?.toString() ??
          '';

      String ipText = 'No IPv4';
      if (interface['ipv4-address'] is List &&
          (interface['ipv4-address'] as List).isNotEmpty) {
        final first = (interface['ipv4-address'] as List).first;
        if (first is Map) {
          final addr = first['address']?.toString() ?? '';
          final mask = first['mask']?.toString() ?? '';
          if (addr.isNotEmpty) {
            ipText = mask.isNotEmpty ? '$addr/$mask' : addr;
          }
        }
      } else if (interface['ipv6-address'] is List &&
          (interface['ipv6-address'] as List).isNotEmpty) {
        final first = (interface['ipv6-address'] as List).first;
        if (first is Map) {
          final addr = first['address']?.toString() ?? '';
          if (addr.isNotEmpty) {
            ipText = addr;
          }
        }
      }

      final isPublic = _isPublicIp(ipText);
      final displayIp = (prefs.maskPublicIp && isPublic)
          ? _maskIpString(ipText)
          : ipText;

      interfaceCardWidgets.add(
        Card(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isUp
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                  : Colors.red.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              final appState = ref.read(appStateProvider);
              appState.requestTab(1, interfaceToScroll: name);
            },
            onLongPress: () {
              final appState = ref.read(appStateProvider);
              appState.requestTab(1, interfaceToScroll: name);
            },
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _getInterfaceIcon(name, proto),
                                color: Theme.of(context).colorScheme.primary,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                name.toUpperCase(),
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isUp
                              ? LuciStatusColors.connectedColor(
                                  context,
                                ).withValues(alpha: 0.18)
                              : Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isUp
                                    ? LuciStatusColors.connectedColor(context)
                                    : Theme.of(context).colorScheme.error,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isUp ? 'UP' : 'DOWN',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isUp
                                    ? LuciStatusColors.connectedColor(context)
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onErrorContainer,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.lan_outlined,
                        size: 14,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          displayIp,
                          style: GoogleFonts.geistMono(
                            fontWeight: FontWeight.w600,
                          ),
                          softWrap: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (proto.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            proto,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                      if (l3Dev.isNotEmpty)
                        Text(
                          'Dev: $l3Dev',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontSize: 11,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.65),
                              ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    const cardWidth = 220.0;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final cardHeight = (132.0 * textScale).clamp(130.0, 168.0);
    return SizedBox(
      height: cardHeight,
      child: ListView.separated(
        controller: _wanScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: interfaceCardWidgets.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return SizedBox(width: cardWidth, child: interfaceCardWidgets[index]);
        },
      ),
    );
  }

  Widget _buildReviewerModeBanner(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      color: Colors.amber.shade900.withValues(alpha: 0.95),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.rate_review_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'REVIEWER MODE ACTIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  'Using simulated router environment with full mock data',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.amber.shade900,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            onPressed: () => _showExitReviewerModeDialog(context, ref),
            icon: const Icon(Icons.exit_to_app_rounded, size: 14),
            label: const Text(
              'Exit Mode',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showExitReviewerModeDialog(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          actionsOverflowButtonSpacing: 8,
          actionsOverflowDirection: VerticalDirection.down,
          icon: Icon(
            Icons.exit_to_app_rounded,
            color: theme.colorScheme.error,
            size: 28,
          ),
          title: Text(l10n?.exitReviewerModeTitle ?? 'Exit Reviewer Mode?'),
          content: const SingleChildScrollView(
            child: Text(
              'This will disable reviewer mode and redirect to the login screen so you can connect to a live router.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n?.actionCancel ?? 'Cancel'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                final appState = ref.read(appStateProvider);
                await appState.setReviewerMode(false);
                if (context.mounted) {
                  await Navigator.of(
                    context,
                  ).pushNamedAndRemoveUntil('/login', (route) => false);
                }
              },
              icon: const Icon(Icons.logout_rounded, size: 16),
              label: Text(l10n?.exitReviewerModeBtn ?? 'Exit Reviewer Mode'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final model.Router? selected = appState.selectedRouter;
    final currentRouterId = selected?.id;
    if (currentRouterId != _lastSelectedRouterId) {
      _lastSelectedRouterId = currentRouterId;
      _lastRenderedScaffold = null;
    }

    if (!widget.isTabActive && _lastRenderedScaffold != null) {
      return _lastRenderedScaffold!;
    }

    final boardInfo =
        appState.dashboardData?['boardInfo'] as Map<String, dynamic>?;
    final hostname = boardInfo?['hostname']?.toString();
    final headerText =
        (selected?.name != null && selected!.name!.trim().isNotEmpty)
        ? selected.name!.trim()
        : (hostname != null && hostname.isNotEmpty)
        ? hostname
        : (appState.reviewerModeEnabled
              ? 'OpenWrt-Demo'
              : (selected?.ipAddress ?? 'Loading...'));
    final scaffold = Scaffold(
      appBar: LuciAppBar(
        centerTitle: true,
        title: null, // Always use titleWidget now
        titleWidget: _buildTitleWithTimestamp(headerText, appState),
      ),
      body: Column(
        children: [
          if (appState.reviewerModeEnabled)
            _buildReviewerModeBanner(context, ref),
          Expanded(child: Stack(children: [_buildBody(appState)])),
        ],
      ),
    );
    _lastRenderedScaffold = scaffold;
    return scaffold;
  }

  Widget _buildSkeletonPill(
    BuildContext context, {
    required double width,
    required double height,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }

  Widget _buildSkeletonCard(
    BuildContext context, {
    required double height,
    Widget? child,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: SizedBox(
        height: height,
        child:
            child ??
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    _buildSkeletonPill(context, width: 36, height: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSkeletonPill(context, width: 120, height: 12),
                          const SizedBox(height: 6),
                          _buildSkeletonPill(context, width: 80, height: 10),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }

  Widget _buildSkeletonDashboard(BuildContext context, AppState appState) {
    final l10n = AppLocalizations.of(context);
    final tempPill = _buildTemperaturePromptPill(context, appState);
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          _buildDeviceInfoCard(appState),
          if (appState.isMissingRpcPackages && !_dismissedRpcWarning)
            _buildRpcWarningCard(context, appState),
          _buildSectionHeader(
            context,
            l10n?.cardRealtimeTraffic ?? 'Real-time Network Traffic',
            Icons.swap_vert,
          ),
          SizedBox(height: 220, child: _buildRealtimeThroughputCard(appState)),
          _buildSectionHeader(
            context,
            l10n?.cardSystemVitals ?? 'System Vitals',
            Icons.monitor_heart,
            action: tempPill,
          ),
          _buildSystemVitalsCard(appState),
          _buildSectionHeader(
            context,
            l10n?.cardConnectedClients ?? 'Connected Clients Overview',
            Icons.devices,
          ),
          _buildClientsSummaryCard(appState),
          _buildSectionHeader(
            context,
            l10n?.cardWirelessRadios ?? 'Wireless Radios & SSIDs',
            Icons.wifi,
          ),
          _buildSkeletonCard(context, height: 72),
          _buildSectionHeader(
            context,
            l10n?.cardNetworkInterfaces ?? 'Network Interfaces',
            Icons.lan,
          ),
          _buildSkeletonCard(context, height: 64),
          _buildSectionHeader(
            context,
            l10n?.cardSystemModules ?? 'System Modules & Storage',
            Icons.storage,
          ),
          ..._buildModuleDashboardWidgets(context),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildBody(AppState appState) {
    final l10n = AppLocalizations.of(context);
    if (appState.dashboardError != null && appState.dashboardData == null) {
      return LuciErrorDisplay(
        title: l10n?.dashConnectionFailed ?? 'Connection Failed',
        message:
            'Unable to connect to the router. Please check your network connection and router settings.',
        actionLabel: 'Retry Connection',
        onAction: () => appState.fetchDashboardData(force: true),
        icon: Icons.wifi_off_rounded,
      );
    }

    final hasCompleteData =
        appState.dashboardData != null &&
        appState.dashboardData!['boardInfo'] != null;

    if (!hasCompleteData) {
      if (appState.isDashboardLoading || appState.isLoading) {
        return RefreshIndicator(
          onRefresh: () => appState.fetchDashboardData(force: true),
          child: _buildSkeletonDashboard(context, appState),
        );
      }
      return LuciEmptyState(
        title: l10n?.dashNoDataAvailable ?? 'No Data Available',
        message:
            'Unable to fetch dashboard data. Pull down to refresh or tap the button below.',
        icon: Icons.dashboard_outlined,
        actionLabel: 'Fetch Data',
        onAction: () => appState.fetchDashboardData(force: true),
      );
    }

    return RefreshIndicator(
      onRefresh: () => appState.fetchDashboardData(force: true),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Width-based breakpoint: treats both landscape phones AND tablets
          // as "wide" so sections drop section headers and use compact layout.
          final isWide =
              constraints.maxWidth >= LuciBreakpoints.compact ||
              MediaQuery.of(context).orientation == Orientation.landscape;
          final hPad = LuciBreakpoints.horizontalPadding(context);

          final orderedContent = _buildOrderedDashboardCards(
            context,
            appState,
            isWide,
          );

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: hPad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: orderedContent,
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildOrderedDashboardCards(
    BuildContext context,
    AppState appState,
    bool isWide,
  ) {
    final prefs = appState.dashboardPreferences;
    final order = prefs.cardOrder;
    final widgets = <Widget>[];
    final l10n = AppLocalizations.of(context);

    widgets.add(const SizedBox(height: 12));

    if (appState.isMissingRpcPackages && !_dismissedRpcWarning) {
      widgets.add(_buildRpcWarningCard(context, appState));
      widgets.add(const SizedBox(height: 12));
    }

    for (final cardId in order) {
      if (!prefs.isSectionVisible(cardId)) continue;

      switch (cardId) {
        case 'quick_actions':
          final qaCard = _buildQuickActionsCard(context, appState);
          if (qaCard != null) {
            widgets.add(qaCard);
            widgets.add(const SizedBox(height: 12));
          }
          break;
        case 'device_info':
          widgets.add(_buildDeviceInfoCard(appState));
          widgets.add(const SizedBox(height: 12));
          break;
        case 'realtime_traffic':
          if (!isWide) {
            widgets.add(
              _buildSectionHeader(
                context,
                l10n?.cardRealtimeTraffic ?? 'Real-time Network Traffic',
                Icons.swap_vert,
              ),
            );
          }
          widgets.add(
            SizedBox(
              height: isWide ? 240 : 220,
              child: _buildRealtimeThroughputCard(appState),
            ),
          );
          widgets.add(const SizedBox(height: 12));
          break;
        case 'system_vitals':
          final tempPill = _buildTemperaturePromptPill(context, appState);
          if (!isWide || tempPill != null) {
            widgets.add(
              _buildSectionHeader(
                context,
                l10n?.cardSystemVitals ?? 'System Vitals',
                Icons.monitor_heart,
                action: tempPill,
              ),
            );
          }
          widgets.add(_buildSystemVitalsCard(appState));
          widgets.add(const SizedBox(height: 12));
          break;
        case 'connected_clients':
          if (!isWide) {
            widgets.add(
              _buildSectionHeader(
                context,
                l10n?.cardConnectedClients ?? 'Connected Clients Overview',
                Icons.devices,
              ),
            );
          }
          widgets.add(_buildClientsSummaryCard(appState));
          widgets.add(const SizedBox(height: 12));
          break;
        case 'wireless_networks':
          if (!isWide) {
            widgets.add(
              _buildSectionHeader(
                context,
                l10n?.cardWirelessRadios ?? 'Wireless Radios & SSIDs',
                Icons.wifi,
              ),
            );
          }
          widgets.add(_buildWirelessNetworksCard(appState));
          widgets.add(const SizedBox(height: 12));
          break;
        case 'network_interfaces':
          if (!isWide) {
            widgets.add(
              _buildSectionHeader(
                context,
                l10n?.cardNetworkInterfaces ?? 'Network Interfaces',
                Icons.lan,
                action: IconButton(
                  icon: Icon(
                    prefs.maskPublicIp
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  tooltip: prefs.maskPublicIp
                      ? 'Show public WAN IP address'
                      : 'Mask public WAN IP address for privacy',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    appState.saveDashboardPreferences(
                      prefs.copyWith(maskPublicIp: !prefs.maskPublicIp),
                    );
                  },
                ),
              ),
            );
          }
          widgets.add(_buildInterfaceStatusCards(appState));
          widgets.add(const SizedBox(height: 12));
          break;
        case 'system_modules':
          if (!isWide) {
            widgets.add(
              _buildSectionHeader(
                context,
                l10n?.cardSystemModules ?? 'System Modules & Storage',
                Icons.storage,
              ),
            );
          }
          widgets.addAll(_buildModuleDashboardWidgets(context));
          break;
      }
    }

    widgets.add(const SizedBox(height: 100));
    return widgets;
  }

  Widget? _buildQuickActionsCard(BuildContext context, AppState appState) {
    final enabledActions = appState.dashboardPreferences.enabledQuickActions;
    if (enabledActions.isEmpty) return null;
    final l10n = AppLocalizations.of(context);
    final isRpcMissing = appState.isMissingRpcPackages;

    final buttons = <Widget>[];

    if (enabledActions.contains('reboot')) {
      buttons.add(
        _buildQuickActionButton(
          context,
          icon: isRpcMissing ? Icons.lock_outline_rounded : Icons.restart_alt,
          color: Colors.amber.shade700,
          label: l10n?.quickActionReboot ?? 'Reboot',
          enabled: !isRpcMissing,
          restrictionReason: isRpcMissing
              ? 'Requires router RPC permissions'
              : null,
          onTap: isRpcMissing
              ? () => RpcPermissionsDialog.show(
                  context,
                  actionName: l10n?.quickActionReboot ?? 'Reboot Router',
                )
              : () => _showQuickRebootDialog(context, appState),
        ),
      );
    }

    if (enabledActions.contains('flush_dns')) {
      buttons.add(
        _buildQuickActionButton(
          context,
          icon: isRpcMissing
              ? Icons.lock_outline_rounded
              : Icons.cleaning_services,
          color: Colors.teal,
          label: l10n?.quickActionFlushDns ?? 'Flush DNS',
          enabled: !isRpcMissing,
          restrictionReason: isRpcMissing
              ? 'Requires router RPC permissions'
              : null,
          onTap: isRpcMissing
              ? () => RpcPermissionsDialog.show(
                  context,
                  actionName: l10n?.quickActionFlushDns ?? 'Flush DNS',
                )
              : () async {
                  const actionKey = 'flush_dns_action';
                  if (ActionRateLimiter.isRateLimited(
                    actionKey,
                    cooldown: const Duration(seconds: 2),
                  )) {
                    return;
                  }
                  context.showToastLoading(
                    'Flushing DNS cache...',
                    actionKey: actionKey,
                  );
                  try {
                    final res = await appState.flushDns(context: context);
                    if (context.mounted) {
                      if (res.isSuccess) {
                        context.showToastSuccess(
                          'DNS Cache Flushed',
                          subtitle: res.message,
                          actionKey: actionKey,
                        );
                      } else {
                        context.showToastError(
                          'Flush DNS Failed',
                          subtitle: res.message,
                          actionKey: actionKey,
                        );
                      }
                    }
                  } catch (e) {
                    if (context.mounted) {
                      context.showToastError(
                        'Flush DNS Failed',
                        subtitle: LuciToastManager.parseErrorReason(e),
                        actionKey: actionKey,
                      );
                    }
                  }
                },
        ),
      );
    }

    if (enabledActions.contains('guest_wifi')) {
      buttons.add(
        _buildQuickActionButton(
          context,
          icon: Icons.wifi_tethering,
          color: Colors.indigo,
          label: l10n?.quickActionGuestWifi ?? 'Guest Wi-Fi',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const GuestWifiManagementScreen(),
              ),
            );
          },
        ),
      );
    }

    if (enabledActions.contains('vpn')) {
      buttons.add(
        _buildQuickActionButton(
          context,
          icon: Icons.vpn_key,
          color: Colors.deepOrange,
          label: l10n?.quickActionVpn ?? 'VPN',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const VpnConnectivityScreen()),
            );
          },
        ),
      );
    }

    if (enabledActions.contains('refresh')) {
      buttons.add(
        _buildQuickActionButton(
          context,
          icon: Icons.refresh,
          color: Theme.of(context).colorScheme.primary,
          label: l10n?.quickActionRefresh ?? 'Refresh',
          onTap: () async {
            const actionKey = 'refresh_dashboard_action';
            context.showToastLoading(
              'Refreshing Dashboard...',
              actionKey: actionKey,
            );
            try {
              await appState.fetchDashboardData(force: true);
              if (context.mounted) {
                context.showToastSuccess(
                  'Dashboard Updated',
                  actionKey: actionKey,
                );
              }
            } catch (e) {
              if (context.mounted) {
                context.showToastError(
                  'Refresh Failed',
                  subtitle: LuciToastManager.parseErrorReason(e),
                  actionKey: actionKey,
                );
              }
            }
          },
        ),
      );
    }

    if (buttons.isEmpty) return null;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(top: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.flash_on,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n?.cardQuickActions ?? 'Quick Actions',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: buttons
                    .map(
                      (btn) => Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: btn,
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionButton(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
    bool enabled = true,
    String? restrictionReason,
  }) {
    final effectiveColor = enabled ? color : color.withValues(alpha: 0.55);
    final chip = Opacity(
      opacity: enabled ? 1.0 : 0.6,
      child: ActionChip(
        avatar: Icon(icon, size: 16, color: effectiveColor),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: enabled ? null : Theme.of(context).colorScheme.outline,
              ),
            ),
            if (!enabled) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.lock_outline_rounded,
                size: 11,
                color: Theme.of(context).colorScheme.outline,
              ),
            ],
          ],
        ),
        onPressed: onTap,
        backgroundColor: effectiveColor.withValues(alpha: enabled ? 0.1 : 0.05),
        side: BorderSide(
          color: effectiveColor.withValues(alpha: enabled ? 0.3 : 0.15),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );

    if (restrictionReason != null) {
      return Tooltip(message: restrictionReason, child: chip);
    }
    return chip;
  }

  void _showQuickRebootDialog(BuildContext context, AppState appState) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        title: Text(l10n?.dialogRebootTitle ?? 'Reboot Router?'),
        content: SingleChildScrollView(
          child: Text(
            l10n?.dialogRebootMessage ??
                'This will reboot the router. The app will lose connection until it comes back online. Continue?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n?.actionCancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              const actionKey = 'router_reboot';
              if (ActionRateLimiter.isRateLimited(
                actionKey,
                cooldown: const Duration(seconds: 5),
              )) {
                return;
              }
              context.showToastLoading(
                l10n?.dialogRebootToast ?? 'Rebooting Router...',
                actionKey: actionKey,
              );
              final success = await appState.reboot(context: context);
              if (context.mounted && !success) {
                final errL10n = AppLocalizations.of(context);
                context.showToastError(
                  'Reboot Failed',
                  subtitle:
                      errL10n?.dashRebootCommandFailed ??
                      'Failed to send reboot command to router.',
                  actionKey: actionKey,
                );
              }
            },
            child: Text(l10n?.dialogRebootConfirm ?? 'Reboot'),
          ),
        ],
      ),
    );
  }

  Widget _buildRpcWarningCard(BuildContext context, AppState appState) {
    final l10n = AppLocalizations.of(context);
    return Card(
      color: Theme.of(
        context,
      ).colorScheme.errorContainer.withValues(alpha: 0.85),
      elevation: 2,
      margin: const EdgeInsets.only(top: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'LuCI RPC Package Required',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    size: 18,
                  ),
                  onPressed: _dismissRpcWarning,
                  tooltip: 'Dismiss',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Your router is missing `luci-mod-rpc` or backend execution permissions. Some real-time wireless, package, and system control features require RPC support.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onErrorContainer.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final rpcL10n = AppLocalizations.of(context);
                      const actionKey = 'rpc_autofix';
                      context.showToastLoading(
                        'Installing RPC packages...',
                        subtitle:
                            rpcL10n?.dashFixingPermissions ??
                            'Fixing router RPC permissions & modules...',
                        actionKey: actionKey,
                      );
                      final success = await appState.autoFixPermissions(
                        context: context,
                      );
                      if (context.mounted) {
                        if (success) {
                          context.showToastSuccess(
                            'RPC Installed',
                            subtitle:
                                'RPC packages and permissions installed successfully!',
                            actionKey: actionKey,
                          );
                        } else {
                          context.showToastError(
                            'Auto-Install Failed',
                            subtitle:
                                rpcL10n?.dashManualInfoHint ??
                                'Tap "Manual Info" for shell commands.',
                            actionKey: actionKey,
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.build_circle_outlined, size: 18),
                    label: Text(l10n?.autoInstallRpc ?? 'Auto-Install RPC'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _showManualRpcInstallDialog(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(
                      context,
                    ).colorScheme.onErrorContainer,
                    side: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.onErrorContainer.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Text(l10n?.manualInfo ?? 'Manual Info'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showManualRpcInstallDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        title: Row(
          children: [
            Icon(Icons.terminal, color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n?.manualRpcInstallation ?? 'Manual RPC Installation',
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Connect to your router via SSH and run the following command to enable full RPC functionality:\n',
              ),
              SelectableText(
                '# OpenWrt (opkg):\n'
                'opkg update && opkg install luci-mod-rpc rpcd-mod-luci rpcd-mod-iwinfo luci-mod-status && /etc/init.d/rpcd restart\n\n'
                '# OpenWrt 25.12+ (apk):\n'
                'apk update && apk add luci-mod-rpc rpcd-mod-luci rpcd-mod-iwinfo luci-mod-status && /etc/init.d/rpcd restart',
                style: GoogleFonts.geistMono(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n?.actionClose ?? 'Close'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildModuleDashboardWidgets(BuildContext context) {
    final widgets = <Widget>[];
    final modules = LuciModuleRegistry.instance.enabledModules;
    final isRpcMissing = ref.watch(appStateProvider).isMissingRpcPackages;
    const rpcDependentModules = {
      'package_manager',
      'system_backup_upgrade',
      'diagnostics',
      'sqm',
    };

    for (final module in modules) {
      if (module.showInBottomNav) continue; // Skip core tab bar screens
      Widget? widget;
      try {
        widget = module.buildDashboardWidget(context);
      } catch (e, stack) {
        Logger.exception(
          'Failed to build dashboard widget for module ${module.id}',
          e,
          stack,
        );
        continue;
      }
      if (widget != null) {
        if (widget is SizedBox &&
            (widget.width == 0 || widget.width == null) &&
            (widget.height == 0 || widget.height == null) &&
            widget.child == null) {
          continue;
        }
        final isRestricted =
            isRpcMissing && rpcDependentModules.contains(module.id);
        widgets.add(
          Stack(
            children: [
              Opacity(
                opacity: isRestricted ? 0.65 : 1.0,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => module.buildScreen(context),
                      ),
                    );
                  },
                  child: widget,
                ),
              ),
              if (isRestricted)
                Positioned(
                  top: 12,
                  right: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade900.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 11,
                          color: Colors.white,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Permissions Required',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
        widgets.add(const SizedBox(height: 10));
      }
    }
    return widgets;
  }
}
