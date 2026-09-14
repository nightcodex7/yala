// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:yet_another_luci_app/design/luci_design_system.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/utils/os_platform_integration.dart';
import 'package:yet_another_luci_app/widgets/luci_smooth_spinner.dart';

/// Semantic toast notification types.
enum LuciToastType {
  success,
  info,
  warning,
  error,
  guardrail,
  rateLimited,
  loading,
}

/// Simple rate-limiter and action cooldown tracker to prevent rapid request spamming.
class ActionRateLimiter {
  static final Map<String, DateTime> _lastActionTimes = {};
  static final Map<String, int> _actionSuppressionCounts = {};

  /// Checks if an action key is rate-limited based on [cooldown].
  /// Returns `true` if action is RATE LIMITED (should be blocked), `false` if allowed to proceed.
  static bool isRateLimited(
    String actionKey, {
    Duration cooldown = const Duration(milliseconds: 1500),
  }) {
    final now = DateTime.now();
    final last = _lastActionTimes[actionKey];

    if (last != null) {
      final elapsed = now.difference(last);
      if (elapsed < cooldown) {
        _actionSuppressionCounts[actionKey] =
            (_actionSuppressionCounts[actionKey] ?? 0) + 1;
        return true;
      }
    }

    _lastActionTimes[actionKey] = now;
    _actionSuppressionCounts[actionKey] = 0;
    return false;
  }

  /// Returns the remaining cooldown duration for an action key.
  static Duration getRemainingCooldown(
    String actionKey, {
    Duration cooldown = const Duration(milliseconds: 1500),
  }) {
    final last = _lastActionTimes[actionKey];
    if (last == null) return Duration.zero;
    final elapsed = DateTime.now().difference(last);
    final remaining = cooldown - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Returns how many rapid repeated calls were suppressed for an action.
  static int getSuppressionCount(String actionKey) =>
      _actionSuppressionCounts[actionKey] ?? 0;

  /// Clears rate limiting state for a given action key or all keys.
  static void reset([String? actionKey]) {
    if (actionKey != null) {
      _lastActionTimes.remove(actionKey);
      _actionSuppressionCounts.remove(actionKey);
    } else {
      _lastActionTimes.clear();
      _actionSuppressionCounts.clear();
    }
  }
}

/// Returns style parameters matching the unified LuciDesignSystem theme tokens.
/// When [dynamicColorScheme] is provided (e.g. Dynamic Material Theming enabled),
/// surface elevation and semantic tones are derived directly from the M3 ColorScheme.
({Color background, Color accent, IconData icon}) getLuciToastStyle(
  LuciToastType type,
  bool isDark, {
  ColorScheme? dynamicColorScheme,
}) {
  if (dynamicColorScheme != null) {
    Color accent;
    IconData icon;
    switch (type) {
      case LuciToastType.success:
        accent = dynamicColorScheme.primary;
        icon = Icons.check_circle_rounded;
        break;
      case LuciToastType.error:
        accent = dynamicColorScheme.error;
        icon = Icons.error_rounded;
        break;
      case LuciToastType.warning:
        accent = dynamicColorScheme.tertiary;
        icon = Icons.warning_amber_rounded;
        break;
      case LuciToastType.guardrail:
        accent = dynamicColorScheme.tertiary;
        icon = Icons.shield_rounded;
        break;
      case LuciToastType.rateLimited:
        accent = dynamicColorScheme.error;
        icon = Icons.speed_rounded;
        break;
      case LuciToastType.info:
        accent = dynamicColorScheme.secondary;
        icon = Icons.info_rounded;
        break;
      case LuciToastType.loading:
        accent = dynamicColorScheme.primary;
        icon = Icons.sync_rounded;
        break;
    }

    final surfaceBase = isDark
        ? dynamicColorScheme.surfaceContainerHigh
        : dynamicColorScheme.surfaceContainerHighest;

    final background = Color.alphaBlend(
      accent.withValues(alpha: isDark ? 0.16 : 0.10),
      surfaceBase,
    );

    return (background: background, accent: accent, icon: icon);
  }

  // Classic YALA Orange brand colors
  switch (type) {
    case LuciToastType.success:
      return (
        background: isDark ? const Color(0xF0142A1D) : const Color(0xF2F0FDF4),
        accent: LuciStatusColors.connected,
        icon: Icons.check_circle_rounded,
      );
    case LuciToastType.error:
      return (
        background: isDark ? const Color(0xF0341718) : const Color(0xF2FEF2F2),
        accent: LuciStatusColors.error,
        icon: Icons.error_rounded,
      );
    case LuciToastType.warning:
      return (
        background: isDark ? const Color(0xF0342514) : const Color(0xF2FFFBEB),
        accent: LuciStatusColors.warning,
        icon: Icons.warning_amber_rounded,
      );
    case LuciToastType.guardrail:
      return (
        background: isDark ? const Color(0xF0271533) : const Color(0xF2FAF5FF),
        accent: isDark ? const Color(0xFFA855F7) : const Color(0xFF9333EA),
        icon: Icons.shield_rounded,
      );
    case LuciToastType.rateLimited:
      return (
        background: isDark ? const Color(0xF0341E17) : const Color(0xF2FFF5F0),
        accent: LuciColors.rx,
        icon: Icons.speed_rounded,
      );
    case LuciToastType.info:
      return (
        background: isDark ? const Color(0xF0132538) : const Color(0xF2EFF6FF),
        accent: LuciStatusColors.info,
        icon: Icons.info_rounded,
      );
    case LuciToastType.loading:
      return (
        background: isDark ? const Color(0xF0132538) : const Color(0xF2EFF6FF),
        accent: LuciStatusColors.info,
        icon: Icons.sync_rounded,
      );
  }
}

class _KeyedToastItem {
  final _ToastItem toastItem;
  final Timer timeoutTimer;
  _KeyedToastItem({required this.toastItem, required this.timeoutTimer});
}

/// Global Toast Notification Manager for modern animated toasts with rate limiting & guardrails.
class LuciToastManager {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static final List<_ToastItem> _activeToasts = [];
  static final Map<String, DateTime> _recentToastMessages = {};
  static final Map<String, _KeyedToastItem> _activeKeyedToasts = {};
  static const Duration _duplicateWindow = Duration(seconds: 2);

  /// Flag to prefer native OS toasts (e.g. Android system Toast) where applicable.
  static bool preferNativeOsToast = false;

  /// Shows a native OS Toast via Fluttertoast platform channel.
  static Future<void> showNativeToast({
    required String message,
    LuciToastType type = LuciToastType.info,
    Toast toastLength = Toast.LENGTH_SHORT,
    ToastGravity gravity = ToastGravity.BOTTOM,
  }) async {
    final style = getLuciToastStyle(type, true);

    try {
      await Fluttertoast.showToast(
        msg: message,
        toastLength: toastLength,
        gravity: gravity,
        timeInSecForIosWeb: 3,
        backgroundColor: style.accent,
        textColor: Colors.white,
        fontSize: 14.0,
      );
    } catch (_) {
      // Fallback silently if native channel is unavailable
    }
  }

  /// Guardrail to ensure technical, internal debug errors or raw exceptions are NEVER presented to users in toasts.
  static ({String title, String? subtitle}) _sanitizeToastText(
    String rawTitle,
    String? rawSubtitle,
  ) {
    bool isDebugString(String? text) {
      if (text == null || text.trim().isEmpty) return false;
      final t = text.toLowerCase();
      return t.contains('exception:') ||
          t.contains('socketexception') ||
          t.contains('handshakeexception') ||
          t.contains('formatexception') ||
          t.contains('typeerror') ||
          t.contains('nullcheckerror') ||
          t.contains('clientexception') ||
          t.contains('httpexception') ||
          t.contains('nosuchmethoderror') ||
          t.contains('stateerror') ||
          t.contains('stack trace') ||
          t.contains('#0 ') ||
          t.contains('errno =') ||
          t.contains('[debug]') ||
          t.contains('[dev]') ||
          t.contains('flutter_error') ||
          RegExp(r'\w+\.dart:\d+').hasMatch(text);
    }

    String title = rawTitle;
    String? subtitle = rawSubtitle;

    if (isDebugString(rawTitle)) {
      title = 'System Notice';
    }

    if (isDebugString(rawSubtitle)) {
      final t = (rawSubtitle ?? '').toLowerCase();
      if (t.contains('socketexception') ||
          t.contains('handshakeexception') ||
          t.contains('clientexception') ||
          t.contains('httpexception') ||
          t.contains('connection refused') ||
          t.contains('network') ||
          t.contains('timed out') ||
          t.contains('host lookup')) {
        subtitle =
            'Unable to complete request. Please verify network connection and try again.';
      } else if (t.contains('filesystemexception') ||
          t.contains('file') ||
          t.contains('picker') ||
          t.contains('archive') ||
          t.contains('json') ||
          t.contains('storage')) {
        subtitle =
            'Unable to process selected file. Please verify file format and storage permissions.';
      } else {
        subtitle = 'An unexpected error occurred. Please try again.';
      }
    }

    return (title: title, subtitle: subtitle);
  }

  static bool _hasBottomNavigationBar(BuildContext? context) {
    if (context == null || !context.mounted) return false;
    bool found = false;
    try {
      context.visitAncestorElements((element) {
        if (element.widget is Scaffold) {
          final scaffold = element.widget as Scaffold;
          if (scaffold.bottomNavigationBar != null) {
            found = true;
            return false;
          }
        }
        return true;
      });
    } catch (_) {}
    return found;
  }

  /// Displays a custom styled ScaffoldMessenger SnackBar matching the unified LuciToast design language.
  /// Enforces consistent visual branding across Android 12+ API 31+ restrictions and non-Overlay routes.
  static void showCustomSnackBar(
    BuildContext context, {
    required String title,
    String? subtitle,
    LuciToastType type = LuciToastType.info,
    Duration duration = const Duration(seconds: 4),
    VoidCallback? onAction,
    String? actionLabel,
  }) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final sanitized = _sanitizeToastText(title, subtitle);
    final cleanTitle = sanitized.title;
    final cleanSubtitle = sanitized.subtitle;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    bool isDynamic = false;
    try {
      isDynamic = AppState.instance.useDynamicTheme;
    } catch (_) {}
    final style = getLuciToastStyle(
      type,
      isDark,
      dynamicColorScheme: isDynamic ? theme.colorScheme : null,
    );
    final textColor = theme.colorScheme.onSurface;
    final subtitleColor = theme.colorScheme.onSurfaceVariant;
    final hasNav = _hasBottomNavigationBar(context);
    final extraBottomOffset = hasNav ? 78.0 : 12.0;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: duration,
        elevation: 6,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom:
              OsPlatformIntegration.getSafeAreaBottomPadding(context) +
              extraBottomOffset,
        ),
        backgroundColor: style.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: style.accent.withValues(alpha: isDark ? 0.4 : 0.25),
            width: 1.2,
          ),
        ),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: style.accent.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: type == LuciToastType.loading
                  ? LuciSmoothSpinner(
                      size: 20,
                      strokeWidth: 2.2,
                      color: style.accent,
                    )
                  : Icon(style.icon, color: style.accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cleanTitle,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: textColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (cleanSubtitle != null && cleanSubtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      cleanSubtitle,
                      style: TextStyle(fontSize: 11.5, color: subtitleColor),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(width: 6),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: style.accent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {
                  messenger.hideCurrentSnackBar();
                  onAction();
                },
                child: Text(
                  actionLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Shows a modern, animated top-floating Toast notification with Android 12+ API 31+ aware fallbacks.
  static void show(
    BuildContext context, {
    required String title,
    String? subtitle,
    LuciToastType type = LuciToastType.info,
    Duration duration = const Duration(seconds: 4),
    VoidCallback? onAction,
    String? actionLabel,
    String? actionKey,
    Duration? actionCooldown,
    bool? useNativeOs,
    bool showProgressBar = true,
    IconData? customIcon,
    Color? customAccentColor,
    Alignment alignment = Alignment.topCenter,
  }) {
    final sanitized = _sanitizeToastText(title, subtitle);
    title = sanitized.title;
    subtitle = sanitized.subtitle;
    final normalizedActionKey = actionKey?.toLowerCase();

    // Replace and dismiss any active keyed loading toast for this action key
    if (normalizedActionKey != null &&
        _activeKeyedToasts.containsKey(normalizedActionKey)) {
      final oldKeyed = _activeKeyedToasts.remove(normalizedActionKey);
      oldKeyed?.timeoutTimer.cancel();
      oldKeyed?.toastItem.dismiss();
    }
    if (type != LuciToastType.loading && _activeKeyedToasts.isNotEmpty) {
      // Automatically cancel and dismiss all lingering loading timers when any result toast arrives
      dismissAllLoading();
    }

    // 1. Guardrail & Rate Limiting Check on Action Key if provided
    if (normalizedActionKey != null && actionCooldown != null) {
      if (ActionRateLimiter.isRateLimited(
        normalizedActionKey,
        cooldown: actionCooldown,
      )) {
        final remaining = ActionRateLimiter.getRemainingCooldown(
          normalizedActionKey,
          cooldown: actionCooldown,
        );
        final count = ActionRateLimiter.getSuppressionCount(
          normalizedActionKey,
        );
        showRateLimited(
          context,
          actionName: title,
          remaining: remaining,
          suppressedCount: count,
        );
        return;
      }
    }

    // 2. Deduplicate identical messages in rapid succession (1.5s window) except for loading transitions
    if (type != LuciToastType.loading) {
      final msgKey = '$type:$title:${subtitle ?? ''}';
      final now = DateTime.now();
      if (_recentToastMessages.containsKey(msgKey)) {
        if (now.difference(_recentToastMessages[msgKey]!) < _duplicateWindow) {
          return; // Suppress redundant duplicate toast
        }
      }
      _recentToastMessages[msgKey] = now;
      _cleanOldMessageCache(now);
    }

    final shouldUseNative = useNativeOs ?? preferNativeOsToast;
    final isAndroid12OrHigher = OsPlatformIntegration.isAndroid12OrHigher;
    final isMultiLineOrCustom =
        (subtitle != null && subtitle.isNotEmpty) ||
        title.contains('\n') ||
        title.length > 40;

    // Android 12 (API level 31+) restricts native text toasts to 2 lines max and prepends the app icon automatically.
    if (shouldUseNative &&
        !isAndroid12OrHigher &&
        onAction == null &&
        !isMultiLineOrCustom &&
        type != LuciToastType.loading) {
      final text = subtitle != null && subtitle.isNotEmpty
          ? '$title\n$subtitle'
          : title;
      try {
        showNativeToast(message: text, type: type);
        return;
      } catch (_) {
        // Fallback to in-app overlay rendering if platform channel throws
      }
    }

    // 3. Resolve context dynamically with app-wide navigatorKey fallback for 100% context awareness
    final BuildContext? effectiveContext = context.mounted
        ? context
        : navigatorKey.currentContext;
    if (effectiveContext == null || !effectiveContext.mounted) return;

    final overlayState =
        Overlay.maybeOf(effectiveContext, rootOverlay: true) ??
        navigatorKey.currentState?.overlay;

    // 4. Fallback to custom ScaffoldMessenger SnackBar if OverlayState is unavailable
    if (overlayState == null) {
      showCustomSnackBar(
        effectiveContext,
        title: title,
        subtitle: subtitle,
        type: type,
        duration: duration,
        onAction: onAction,
        actionLabel: actionLabel,
      );
      return;
    }

    // 5. Enforce single-toast display (dismiss previous toast so toasts don't overlap)
    while (_activeToasts.isNotEmpty) {
      final old = _activeToasts.removeAt(0);
      old.dismiss();
    }

    late _ToastItem toastItem;

    late OverlayEntry entry;
    toastItem = _ToastItem(
      entry: OverlayEntry(builder: (_) => const SizedBox.shrink()),
    );

    entry = OverlayEntry(
      builder: (ctx) => _LuciToastWidget(
        title: title,
        subtitle: subtitle,
        type: type,
        duration: duration,
        onAction: onAction,
        actionLabel: actionLabel,
        showProgressBar: showProgressBar,
        toastItem: toastItem,
        parentContext: effectiveContext,
        customIcon: customIcon,
        customAccentColor: customAccentColor,
        alignment: alignment,
        onDismissed: () {
          _activeToasts.remove(toastItem);
        },
      ),
    );

    toastItem.entry = entry;
    _activeToasts.add(toastItem);

    // Context-Aware loading auto-timeout registration
    if (type == LuciToastType.loading) {
      final effectiveKey =
          normalizedActionKey ?? '$title:${subtitle ?? ''}'.toLowerCase();
      final timeoutTimer = Timer(duration, () {
        if (_activeKeyedToasts.containsKey(effectiveKey)) {
          final item = _activeKeyedToasts.remove(effectiveKey);
          item?.toastItem.dismiss();
          final timeoutContext = effectiveContext.mounted
              ? effectiveContext
              : navigatorKey.currentContext;
          if (timeoutContext != null && timeoutContext.mounted) {
            showError(
              timeoutContext,
              'Operation Timed Out',
              subtitle:
                  'The request took too long to complete. Please check network connection.',
            );
          }
        }
      });

      _activeKeyedToasts[effectiveKey] = _KeyedToastItem(
        toastItem: toastItem,
        timeoutTimer: timeoutTimer,
      );
    }

    try {
      overlayState.insert(entry);
    } catch (_) {
      _activeToasts.remove(toastItem);
    }
  }

  /// Dismisses all active loading toasts and cancels all pending loading timeout timers.
  static void dismissAllLoading() {
    final keys = List<String>.from(_activeKeyedToasts.keys);
    for (final key in keys) {
      final item = _activeKeyedToasts.remove(key);
      item?.timeoutTimer.cancel();
      if (item != null) {
        _activeToasts.remove(item.toastItem);
        item.toastItem.dismiss();
      }
    }
    _activeKeyedToasts.clear();
  }

  /// Convenience helper for Context-Aware Loading toasts.
  /// Displays a rotating circle loader till replaced by showSuccess / showError or auto-timed out.
  static void showLoading(
    BuildContext context,
    String title, {
    String? subtitle,
    String? actionKey,
    Duration timeout = const Duration(seconds: 60),
    bool? useNativeOs,
  }) {
    show(
      context,
      title: title,
      subtitle: subtitle,
      type: LuciToastType.loading,
      duration: timeout,
      actionKey: actionKey,
      useNativeOs: useNativeOs,
    );
  }

  /// Safe helper for loading toasts that dynamically resolves mounted context across async gaps.
  static void safeShowLoading(
    BuildContext? context,
    String title, {
    String? subtitle,
    String? actionKey,
    Duration timeout = const Duration(seconds: 60),
    bool? useNativeOs,
  }) {
    final ctx = (context != null && context.mounted)
        ? context
        : navigatorKey.currentContext;
    if (ctx == null) return;
    showLoading(
      ctx,
      title,
      subtitle: subtitle,
      actionKey: actionKey,
      timeout: timeout,
      useNativeOs: useNativeOs,
    );
  }

  /// Safe helper for success toasts that dynamically resolves mounted context across async gaps.
  static void safeShowSuccess(
    BuildContext? context,
    String title, {
    String? subtitle,
    Duration duration = const Duration(seconds: 3),
    String? actionKey,
    bool? useNativeOs,
    bool showProgressBar = true,
  }) {
    final ctx = (context != null && context.mounted)
        ? context
        : navigatorKey.currentContext;
    if (ctx == null) return;
    showSuccess(
      ctx,
      title,
      subtitle: subtitle,
      duration: duration,
      actionKey: actionKey,
      useNativeOs: useNativeOs,
      showProgressBar: showProgressBar,
    );
  }

  /// Safe helper for error toasts that dynamically resolves mounted context across async gaps.
  static void safeShowError(
    BuildContext? context,
    String title, {
    String? subtitle,
    Duration duration = const Duration(seconds: 5),
    VoidCallback? onRetry,
    String? actionKey,
    bool? useNativeOs,
    bool showProgressBar = true,
  }) {
    final ctx = (context != null && context.mounted)
        ? context
        : navigatorKey.currentContext;
    if (ctx == null) return;
    showError(
      ctx,
      title,
      subtitle: subtitle,
      duration: duration,
      onRetry: onRetry,
      actionKey: actionKey,
      useNativeOs: useNativeOs,
      showProgressBar: showProgressBar,
    );
  }

  /// Convenience helper for Success toasts.
  static void showSuccess(
    BuildContext context,
    String title, {
    String? subtitle,
    Duration duration = const Duration(seconds: 3),
    String? actionKey,
    bool? useNativeOs,
    bool showProgressBar = true,
  }) {
    show(
      context,
      title: title,
      subtitle: subtitle,
      type: LuciToastType.success,
      duration: duration,
      actionKey: actionKey,
      useNativeOs: useNativeOs,
      showProgressBar: showProgressBar,
    );
  }

  /// Convenience helper for Error toasts.
  static void showError(
    BuildContext context,
    String title, {
    String? subtitle,
    Duration duration = const Duration(seconds: 5),
    VoidCallback? onRetry,
    String? actionKey,
    bool? useNativeOs,
    bool showProgressBar = true,
  }) {
    show(
      context,
      title: title,
      subtitle: subtitle,
      type: LuciToastType.error,
      duration: duration,
      onAction: onRetry,
      actionLabel: onRetry != null ? 'Retry' : null,
      actionKey: actionKey,
      useNativeOs: useNativeOs,
      showProgressBar: showProgressBar,
    );
  }

  /// Convenience helper for Warning toasts.
  static void showWarning(
    BuildContext context,
    String title, {
    String? subtitle,
    Duration duration = const Duration(seconds: 4),
    String? actionKey,
    bool? useNativeOs,
    bool showProgressBar = true,
  }) {
    show(
      context,
      title: title,
      subtitle: subtitle,
      type: LuciToastType.warning,
      duration: duration,
      actionKey: actionKey,
      useNativeOs: useNativeOs,
      showProgressBar: showProgressBar,
    );
  }

  /// Convenience helper for Info toasts.
  static void showInfo(
    BuildContext context,
    String title, {
    String? subtitle,
    Duration duration = const Duration(seconds: 3),
    String? actionKey,
    bool? useNativeOs,
    bool showProgressBar = true,
  }) {
    show(
      context,
      title: title,
      subtitle: subtitle,
      type: LuciToastType.info,
      duration: duration,
      actionKey: actionKey,
      useNativeOs: useNativeOs,
      showProgressBar: showProgressBar,
    );
  }

  /// Convenience helper for Guardrail trigger toasts.
  static void showGuardrail(
    BuildContext context,
    String title, {
    String? subtitle,
    Duration duration = const Duration(seconds: 5),
    bool? useNativeOs,
  }) {
    show(
      context,
      title: title,
      subtitle: subtitle ?? 'Self-device safety guardrail engaged.',
      type: LuciToastType.guardrail,
      duration: duration,
      useNativeOs: useNativeOs,
    );
  }

  /// Convenience helper for Rate Limited feedback toasts.
  static void showRateLimited(
    BuildContext context, {
    required String actionName,
    required Duration remaining,
    int suppressedCount = 1,
    bool? useNativeOs,
  }) {
    final seconds = (remaining.inMilliseconds / 1000.0).toStringAsFixed(1);
    final countInfo = suppressedCount > 1
        ? ' ($suppressedCount taps blocked)'
        : '';

    show(
      context,
      title: 'Action Cooldown Active',
      subtitle:
          'Please wait ${seconds}s before triggering "$actionName" again$countInfo.',
      type: LuciToastType.rateLimited,
      duration: const Duration(seconds: 3),
      useNativeOs: useNativeOs,
    );
  }

  /// Removes all current active overlay toasts safely.
  static void dismissAll() {
    dismissAllLoading();
    final copy = List<_ToastItem>.from(_activeToasts);
    for (final item in copy) {
      item.dismiss();
    }
    _activeToasts.clear();
  }

  static void _cleanOldMessageCache(DateTime now) {
    _recentToastMessages.removeWhere(
      (_, time) => now.difference(time) > const Duration(seconds: 5),
    );
  }
}

class _ToastItem {
  OverlayEntry entry;
  _LuciToastWidgetState? state;
  bool isDismissed = false;

  _ToastItem({required this.entry});

  void dismiss() {
    isDismissed = true;
    if (state != null && state!.mounted) {
      state!._dismissToast();
    } else {
      try {
        if (entry.mounted) {
          entry.remove();
        }
      } catch (_) {}
    }
  }
}

/// Internal modern Toast animation & design container widget.
class _LuciToastWidget extends StatefulWidget {
  final String title;
  final String? subtitle;
  final LuciToastType type;
  final Duration duration;
  final VoidCallback? onAction;
  final String? actionLabel;
  final bool showProgressBar;
  final VoidCallback onDismissed;
  final _ToastItem toastItem;
  final BuildContext? parentContext;
  final IconData? customIcon;
  final Color? customAccentColor;
  final Alignment alignment;

  const _LuciToastWidget({
    required this.title,
    this.subtitle,
    required this.type,
    required this.duration,
    this.onAction,
    this.actionLabel,
    this.showProgressBar = true,
    required this.onDismissed,
    required this.toastItem,
    this.parentContext,
    this.customIcon,
    this.customAccentColor,
    this.alignment = Alignment.topCenter,
  });

  @override
  State<_LuciToastWidget> createState() => _LuciToastWidgetState();
}

class _LuciToastWidgetState extends State<_LuciToastWidget>
    with TickerProviderStateMixin {
  late AnimationController _animController;
  late AnimationController _progressController;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  Timer? _dismissTimer;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    widget.toastItem.state = this;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.toastItem.isDismissed && mounted) {
        _dismissToast();
      }
    });

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _progressController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _scaleAnimation = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );

    final isTop =
        widget.alignment == Alignment.topCenter || widget.alignment.y < 0;

    _slideAnimation =
        Tween<Offset>(
          begin: Offset(0.0, isTop ? -0.6 : 0.6),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );

    _animController.forward();
    _progressController.reverse(from: 1.0);

    // Trigger haptic feedback via OsPlatformIntegration
    if (widget.type == LuciToastType.error ||
        widget.type == LuciToastType.guardrail) {
      OsPlatformIntegration.triggerHaptic(OsHapticType.heavy);
    } else if (widget.type == LuciToastType.warning ||
        widget.type == LuciToastType.rateLimited) {
      OsPlatformIntegration.triggerHaptic(OsHapticType.medium);
    } else {
      OsPlatformIntegration.triggerHaptic(OsHapticType.light);
    }

    _dismissTimer = Timer(widget.duration, _dismissToast);
  }

  void _dismissToast() {
    if (_isDismissing) return;
    _isDismissing = true;
    _dismissTimer?.cancel();
    _progressController.stop();

    if (!mounted) {
      widget.onDismissed();
      try {
        if (widget.toastItem.entry.mounted) {
          widget.toastItem.entry.remove();
        }
      } catch (_) {}
      return;
    }

    _animController.reverse().then((_) {
      widget.onDismissed();
      try {
        if (widget.toastItem.entry.mounted) {
          widget.toastItem.entry.remove();
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _animController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  ({Color background, Color accent, IconData icon}) _getTypeStyle(
    BuildContext context,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    bool isDynamic = false;
    try {
      isDynamic = AppState.instance.useDynamicTheme;
    } catch (_) {}
    final base = getLuciToastStyle(
      widget.type,
      isDark,
      dynamicColorScheme: isDynamic ? theme.colorScheme : null,
    );
    return (
      background: base.background,
      accent: widget.customAccentColor ?? base.accent,
      icon: widget.customIcon ?? base.icon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = _getTypeStyle(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final topPadding = OsPlatformIntegration.getSafeAreaTopPadding(context);
    final bottomPadding = OsPlatformIntegration.getSafeAreaBottomPadding(
      context,
    );
    final hasNav =
        LuciToastManager._hasBottomNavigationBar(widget.parentContext) ||
        LuciToastManager._hasBottomNavigationBar(context);
    final isTop =
        widget.alignment == Alignment.topCenter || widget.alignment.y < 0;

    final padding = isTop
        ? EdgeInsets.only(top: topPadding + 10.0, left: 16.0, right: 16.0)
        : EdgeInsets.only(
            bottom: bottomPadding + (hasNav ? 78.0 : 12.0),
            left: 16.0,
            right: 16.0,
          );

    final textColor = theme.colorScheme.onSurface;
    final subtitleColor = theme.colorScheme.onSurfaceVariant;

    return Align(
      alignment: widget.alignment,
      child: Padding(
        padding: padding,
        child: Semantics(
          liveRegion: true,
          container: true,
          label:
              '${widget.type.name} alert: ${widget.title}. ${widget.subtitle ?? ""}',
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: RepaintBoundary(
              child: SlideTransition(
                position: _slideAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Dismissible(
                      key: const ValueKey('luci_toast_dismiss_h'),
                      direction: DismissDirection.horizontal,
                      onDismissed: (_) => _dismissToast(),
                      child: Dismissible(
                        key: const ValueKey('luci_toast_dismiss_v'),
                        direction: isTop
                            ? DismissDirection.up
                            : DismissDirection.down,
                        onDismissed: (_) => _dismissToast(),
                        child: Material(
                          color: Colors.transparent,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _dismissToast,
                            child: Container(
                              decoration: BoxDecoration(
                                color: style.background,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: style.accent.withValues(
                                    alpha: isDark ? 0.35 : 0.22,
                                  ),
                                  width: 1.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.shadowColor.withValues(
                                      alpha: isDark ? 0.35 : 0.08,
                                    ),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12.0,
                                      vertical: 8.0,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: style.accent.withValues(
                                              alpha: 0.14,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                          child:
                                              widget.type ==
                                                  LuciToastType.loading
                                              ? LuciSmoothSpinner(
                                                  size: 16,
                                                  strokeWidth: 2.0,
                                                  color: style.accent,
                                                )
                                              : Icon(
                                                  style.icon,
                                                  color: style.accent,
                                                  size: 16,
                                                ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                widget.title,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13.0,
                                                  color: textColor,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (widget.subtitle != null &&
                                                  widget
                                                      .subtitle!
                                                      .isNotEmpty) ...[
                                                const SizedBox(height: 1),
                                                Text(
                                                  widget.subtitle!,
                                                  style: TextStyle(
                                                    fontSize: 11.0,
                                                    color: subtitleColor,
                                                  ),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        if (widget.onAction != null &&
                                            widget.actionLabel != null) ...[
                                          const SizedBox(width: 6),
                                          TextButton(
                                            style: TextButton.styleFrom(
                                              foregroundColor: style.accent,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            onPressed: () {
                                              widget.onAction!();
                                              _dismissToast();
                                            },
                                            child: Text(
                                              widget.actionLabel!,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11.5,
                                              ),
                                            ),
                                          ),
                                        ],
                                        IconButton(
                                          icon: Icon(
                                            Icons.close,
                                            size: 14,
                                            color: subtitleColor,
                                          ),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 24,
                                            minHeight: 24,
                                          ),
                                          onPressed: _dismissToast,
                                          tooltip: 'Dismiss',
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (widget.showProgressBar &&
                                      widget.type != LuciToastType.loading)
                                    AnimatedBuilder(
                                      animation: _progressController,
                                      builder: (context, child) {
                                        return LinearProgressIndicator(
                                          value: _progressController.value,
                                          minHeight: 1.8,
                                          backgroundColor: Colors.transparent,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                style.accent.withValues(
                                                  alpha: 0.75,
                                                ),
                                              ),
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Extension on BuildContext for quick access to modern Toast Notifications.
extension LuciToastExtension on BuildContext {
  void showToastLoading(
    String title, {
    String? subtitle,
    String? actionKey,
    Duration? timeout,
    bool? useNativeOs,
  }) {
    LuciToastManager.showLoading(
      this,
      title,
      subtitle: subtitle,
      actionKey: actionKey,
      timeout: timeout ?? const Duration(seconds: 60),
      useNativeOs: useNativeOs,
    );
  }

  void showToastSuccess(
    String title, {
    String? subtitle,
    Duration? duration,
    String? actionKey,
    bool? useNativeOs,
    bool showProgressBar = true,
    IconData? customIcon,
    Color? customAccentColor,
  }) {
    LuciToastManager.show(
      this,
      title: title,
      subtitle: subtitle,
      type: LuciToastType.success,
      duration: duration ?? const Duration(seconds: 3),
      actionKey: actionKey,
      useNativeOs: useNativeOs,
      showProgressBar: showProgressBar,
      customIcon: customIcon,
      customAccentColor: customAccentColor,
    );
  }

  void showToastError(
    String title, {
    String? subtitle,
    Duration? duration,
    VoidCallback? onRetry,
    String? actionKey,
    bool? useNativeOs,
    bool showProgressBar = true,
    IconData? customIcon,
    Color? customAccentColor,
  }) {
    LuciToastManager.show(
      this,
      title: title,
      subtitle: subtitle,
      type: LuciToastType.error,
      duration: duration ?? const Duration(seconds: 5),
      onAction: onRetry,
      actionLabel: onRetry != null ? 'Retry' : null,
      actionKey: actionKey,
      useNativeOs: useNativeOs,
      showProgressBar: showProgressBar,
      customIcon: customIcon,
      customAccentColor: customAccentColor,
    );
  }

  void showToastWarning(
    String title, {
    String? subtitle,
    Duration? duration,
    String? actionKey,
    bool? useNativeOs,
    bool showProgressBar = true,
    IconData? customIcon,
    Color? customAccentColor,
  }) {
    LuciToastManager.show(
      this,
      title: title,
      subtitle: subtitle,
      type: LuciToastType.warning,
      duration: duration ?? const Duration(seconds: 4),
      actionKey: actionKey,
      useNativeOs: useNativeOs,
      showProgressBar: showProgressBar,
      customIcon: customIcon,
      customAccentColor: customAccentColor,
    );
  }

  void showToastInfo(
    String title, {
    String? subtitle,
    Duration? duration,
    String? actionKey,
    bool? useNativeOs,
    bool showProgressBar = true,
    IconData? customIcon,
    Color? customAccentColor,
  }) {
    LuciToastManager.show(
      this,
      title: title,
      subtitle: subtitle,
      type: LuciToastType.info,
      duration: duration ?? const Duration(seconds: 3),
      actionKey: actionKey,
      useNativeOs: useNativeOs,
      showProgressBar: showProgressBar,
      customIcon: customIcon,
      customAccentColor: customAccentColor,
    );
  }

  void showToastGuardrail(
    String title, {
    String? subtitle,
    Duration? duration,
    bool? useNativeOs,
    IconData? customIcon,
    Color? customAccentColor,
  }) {
    LuciToastManager.show(
      this,
      title: title,
      subtitle: subtitle ?? 'Self-device safety guardrail engaged.',
      type: LuciToastType.guardrail,
      duration: duration ?? const Duration(seconds: 5),
      useNativeOs: useNativeOs,
      customIcon: customIcon,
      customAccentColor: customAccentColor,
    );
  }

  void showToastRateLimited(
    String actionName,
    Duration remaining, {
    bool? useNativeOs,
  }) {
    LuciToastManager.showRateLimited(
      this,
      actionName: actionName,
      remaining: remaining,
      useNativeOs: useNativeOs,
    );
  }

  void showNativeOsToast(
    String message, {
    LuciToastType type = LuciToastType.info,
  }) {
    LuciToastManager.showNativeToast(message: message, type: type);
  }
}
