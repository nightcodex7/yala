// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class ChartSeriesData {
  final List<double> spots;
  final List<Color> gradientColors;
  final String label;

  const ChartSeriesData({
    required this.spots,
    required this.gradientColors,
    required this.label,
  });
}

/// Shared real-time line chart component built with fl_chart.
class RealtimeLineChart extends StatelessWidget {
  final List<ChartSeriesData> series;
  final String Function(double value)? valueFormatter;
  final double? minY;
  final double? maxY;
  final double height;
  final bool showGrid;
  final int maxPoints;

  const RealtimeLineChart({
    super.key,
    required this.series,
    this.valueFormatter,
    this.minY,
    this.maxY,
    this.height = 140,
    this.showGrid = true,
    this.maxPoints = 30,
  });

  double _calculateNiceMax(double maxVal, {bool isThroughput = false}) {
    if (isThroughput) {
      final double bitsPerSec = maxVal * 8.0;
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

      return (niceResidual * magnitude) / 8.0;
    } else {
      final double target = math.max(maxVal * 1.2, 10.0);
      final double exponent = (math.log(target) / math.ln10).floorToDouble();
      final double magnitude = math.pow(10, exponent).toDouble();
      final double residual = target / magnitude;

      double niceResidual;
      if (residual <= 1.0) {
        niceResidual = 1.0;
      } else if (residual <= 2.0) {
        niceResidual = 2.0;
      } else if (residual <= 5.0) {
        niceResidual = 5.0;
      } else {
        niceResidual = 10.0;
      }
      return niceResidual * magnitude;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty || series.every((s) => s.spots.isEmpty)) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Collecting metric samples...',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    double effectiveMaxY = maxY ?? 100.0;
    if (maxY == null) {
      double maxVal = 0.0;
      for (final s in series) {
        for (final spot in s.spots) {
          if (spot > maxVal) maxVal = spot;
        }
      }
      effectiveMaxY = _calculateNiceMax(
        maxVal,
        isThroughput: valueFormatter != null,
      );
    }
    final double interval = effectiveMaxY / 4.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Live line legend text row
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: series.map((s) {
              final latestVal = s.spots.isNotEmpty ? s.spots.last : 0.0;
              final formattedText = valueFormatter != null
                  ? valueFormatter!(latestVal)
                  : latestVal.toStringAsFixed(1);
              final primaryColor = s.gradientColors.first;

              return Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: primaryColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${s.label}: ',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      Text(
                        formattedText,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.only(right: 8.0, bottom: 4.0),
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (maxPoints - 1).toDouble(),
                minY: minY ?? 0.0,
                maxY: effectiveMaxY,
                clipData: const FlClipData.all(),
                gridData: FlGridData(
                  show: showGrid,
                  drawVerticalLine: false,
                  horizontalInterval: interval > 0 ? interval : 1.0,
                  getDrawingHorizontalLine: (val) => FlLine(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.25),
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
                      reservedSize: 64,
                      interval: interval > 0 ? interval : 1.0,
                      getTitlesWidget: (value, meta) {
                        if (value < -0.001 || value > effectiveMaxY + 0.001) {
                          return const SizedBox.shrink();
                        }
                        final String text = valueFormatter != null
                            ? valueFormatter!(value)
                            : value.toStringAsFixed(0);

                        return SideTitleWidget(
                          meta: meta,
                          space: 6,
                          fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                          child: Text(
                            text,
                            style: TextStyle(
                              fontSize: 9.5,
                              color: colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.75,
                              ),
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
                    getTooltipColor: (spot) => Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.95),
                    tooltipBorderRadius: BorderRadius.circular(8),
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final seriesData = spot.barIndex < series.length
                            ? series[spot.barIndex]
                            : null;
                        final labelName = seriesData?.label ?? 'Metric';
                        final color =
                            spot.bar.gradient?.colors.first ??
                            spot.bar.color ??
                            Colors.white;
                        final formatted = valueFormatter != null
                            ? valueFormatter!(spot.y)
                            : spot.y.toStringAsFixed(1);
                        return LineTooltipItem(
                          '$labelName: $formatted',
                          TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: series
                    .asMap()
                    .entries
                    .map((e) => _buildBarData(e.value, barIndex: e.key))
                    .toList(),
              ),
              duration: Duration.zero,
            ),
          ),
        ),
      ],
    );
  }

  LineChartBarData _buildBarData(
    ChartSeriesData seriesData, {
    int barIndex = 0,
  }) {
    final data = seriesData.spots;
    final colors = seriesData.gradientColors;

    if (data.isEmpty) {
      return LineChartBarData(
        spots: [const FlSpot(0, 0), FlSpot((maxPoints - 1).toDouble(), 0)],
        isCurved: false,
        gradient: LinearGradient(colors: colors),
        barWidth: barIndex == 0 ? 2.5 : 2.0,
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
      gradient: LinearGradient(colors: colors),
      barWidth: 2.8,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
    );
  }
}
