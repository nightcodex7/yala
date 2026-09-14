// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';

/// Reusable widget wrapper that catches scroll notifications to pause
/// background periodic data rebuilds during active gesture scrolling.
///
/// Completely eliminates mid-scrolling refresh jitters and dropped frames.
class ScrollJitterGuard extends ConsumerWidget {
  final Widget child;

  const ScrollJitterGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth != 0) return false;
        final appState = ref.read(appStateProvider);
        if (notification is ScrollStartNotification) {
          appState.setScrollState(true);
        } else if (notification is ScrollEndNotification) {
          appState.setScrollState(false);
        }
        return false; // allow notification to continue bubbling
      },
      child: child,
    );
  }
}
