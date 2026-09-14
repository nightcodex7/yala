// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

/// A smooth, constant-speed 360° circular progress spinner for Yet Another LuCI App.
/// Uses wall-clock phase matching to ensure continuous, seamless rotation without resetting or restarting
/// when rebuilt or recreated across dynamic toast and dialog state updates.
class LuciSmoothSpinner extends StatefulWidget {
  final double size;
  final double strokeWidth;
  final Color? color;
  final double strokeAlign;

  const LuciSmoothSpinner({
    super.key,
    this.size = 24.0,
    this.strokeWidth = 2.5,
    this.color,
    this.strokeAlign = CircularProgressIndicator.strokeAlignCenter,
  });

  @override
  State<LuciSmoothSpinner> createState() => _LuciSmoothSpinnerState();
}

class _LuciSmoothSpinnerState extends State<LuciSmoothSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Compute current rotation phase (0.0 to 1.0) based on wall clock (1000ms loop)
    final initialPhase =
        (DateTime.now().millisecondsSinceEpoch % 1000) / 1000.0;
    _controller = AnimationController(
      value: initialPhase,
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spinnerColor = widget.color ?? Theme.of(context).colorScheme.primary;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: RotationTransition(
          turns: _controller,
          child: CircularProgressIndicator(
            strokeWidth: widget.strokeWidth,
            strokeCap: StrokeCap.round,
            strokeAlign: widget.strokeAlign,
            value: 0.72,
            valueColor: AlwaysStoppedAnimation<Color>(spinnerColor),
            backgroundColor: spinnerColor.withValues(alpha: 0.16),
          ),
        ),
      ),
    );
  }
}
