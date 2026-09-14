// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../design/luci_design_system.dart';

/// A skeleton loading widget that displays animated placeholders
/// while content is loading. Provides consistent loading states
/// across the entire app.
class LuciSkeleton extends StatefulWidget {
  const LuciSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
    this.margin,
  });

  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final EdgeInsets? margin;

  @override
  State<LuciSkeleton> createState() => _LuciSkeletonState();
}

class _LuciSkeletonState extends State<LuciSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      margin: widget.margin,
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius ?? LuciCardStyles.standardRadius,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              borderRadius:
                  widget.borderRadius ?? LuciCardStyles.standardRadius,
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Theme.of(context).colorScheme.surfaceContainerHighest,
                  Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  Theme.of(context).colorScheme.surfaceContainerHighest,
                ],
                stops: [
                  _animation.value - 0.3,
                  _animation.value,
                  _animation.value + 0.3,
                ].map((stop) => stop.clamp(0.0, 1.0)).toList(),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Skeleton loading for card content
class LuciCardSkeleton extends StatelessWidget {
  const LuciCardSkeleton({
    super.key,
    this.showTitle = true,
    this.showSubtitle = true,
    this.showContent = true,
    this.contentLines = 3,
  });

  final bool showTitle;
  final bool showSubtitle;
  final bool showContent;
  final int contentLines;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: LuciCardStyles.standardRadius,
      ),
      child: Padding(
        padding: EdgeInsets.all(LuciSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showTitle) ...[
              LuciSkeleton(
                width: MediaQuery.of(context).size.width * 0.6,
                height: 20,
              ),
              SizedBox(height: LuciSpacing.sm),
            ],
            if (showSubtitle) ...[
              LuciSkeleton(
                width: MediaQuery.of(context).size.width * 0.4,
                height: 16,
              ),
              SizedBox(height: LuciSpacing.md),
            ],
            if (showContent) ...[
              ...List.generate(contentLines, (index) {
                final isLast = index == contentLines - 1;
                return Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : LuciSpacing.sm),
                  child: LuciSkeleton(
                    width:
                        MediaQuery.of(context).size.width *
                        (isLast ? 0.3 : 0.8), // Make last line shorter
                    height: 14,
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

/// Skeleton loading for list items
class LuciListItemSkeleton extends StatelessWidget {
  const LuciListItemSkeleton({
    super.key,
    this.showLeading = false,
    this.showTrailing = false,
  });

  final bool showLeading;
  final bool showTrailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: showLeading
          ? const LuciSkeleton(
              width: 40,
              height: 40,
              borderRadius: BorderRadius.all(Radius.circular(20)),
            )
          : null,
      title: LuciSkeleton(
        width: MediaQuery.of(context).size.width * 0.5,
        height: 16,
      ),
      subtitle: LuciSkeleton(
        width: MediaQuery.of(context).size.width * 0.3,
        height: 14,
        margin: EdgeInsets.only(top: LuciSpacing.xs),
      ),
      trailing: showTrailing
          ? const LuciSkeleton(
              width: 24,
              height: 24,
              borderRadius: BorderRadius.all(Radius.circular(12)),
            )
          : null,
    );
  }
}

/// Skeleton loading for chart areas
class LuciChartSkeleton extends StatelessWidget {
  const LuciChartSkeleton({super.key, this.height = 200});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: EdgeInsets.all(LuciSpacing.md),
      child: Column(
        children: [
          // Chart title skeleton
          LuciSkeleton(
            width: MediaQuery.of(context).size.width * 0.4,
            height: 18,
            margin: EdgeInsets.only(bottom: LuciSpacing.md),
          ),
          // Chart area
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: LuciCardStyles.standardRadius,
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Stack(
                children: [
                  // Chart lines simulation
                  ...List.generate(5, (index) {
                    return Align(
                      alignment: Alignment.bottomLeft,
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: LuciSpacing.md,
                          right: LuciSpacing.md,
                          bottom: LuciSpacing.md + (index * (height - 80) / 5),
                        ),
                        child: const LuciSkeleton(
                          width: double.infinity,
                          height: 2,
                        ),
                      ),
                    );
                  }),
                  // Data points simulation
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: LuciSpacing.lg,
                        left: MediaQuery.of(context).size.width * 0.3,
                      ),
                      child: const LuciSkeleton(
                        width: 8,
                        height: 8,
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: LuciSpacing.xl,
                        left: MediaQuery.of(context).size.width * 0.6,
                      ),
                      child: const LuciSkeleton(
                        width: 8,
                        height: 8,
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: LuciSpacing.sm),
          // Legend skeleton
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              LuciSkeleton(
                width: 60,
                height: 12,
                margin: EdgeInsets.only(right: LuciSpacing.md),
              ),
              LuciSkeleton(width: 60, height: 12),
            ],
          ),
        ],
      ),
    );
  }
}
