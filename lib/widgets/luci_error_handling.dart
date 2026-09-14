// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../design/luci_design_system.dart';
import 'luci_toast.dart';

/// Enhanced error handling widget with consistent styling and animations
class LuciErrorCard extends StatefulWidget {
  const LuciErrorCard({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    this.type = LuciErrorType.error,
    this.showAnimation = true,
  });

  final String title;
  final String message;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;
  final LuciErrorType type;
  final bool showAnimation;

  @override
  State<LuciErrorCard> createState() => _LuciErrorCardState();
}

class _LuciErrorCardState extends State<LuciErrorCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: LuciAnimations.standard,
      vsync: this,
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: LuciAnimations.easeOut,
          ),
        );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: LuciAnimations.easeOut,
      ),
    );

    if (widget.showAnimation) {
      _animationController.forward();
    } else {
      _animationController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleDismiss() {
    if (widget.onDismiss != null) {
      _animationController.reverse().then((_) {
        if (mounted) {
          widget.onDismiss!();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final errorConfig = _getErrorConfig(widget.type, colorScheme);

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: LuciCardStyles.standardRadius,
            side: BorderSide(color: errorConfig.borderColor, width: 1),
          ),
          color: errorConfig.backgroundColor,
          child: Padding(
            padding: EdgeInsets.all(LuciSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      widget.icon ?? errorConfig.icon,
                      color: errorConfig.iconColor,
                      size: 24,
                    ),
                    SizedBox(width: LuciSpacing.sm),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: LuciTextStyles.cardTitle(
                          context,
                        ).copyWith(color: errorConfig.titleColor),
                      ),
                    ),
                    if (widget.onDismiss != null)
                      IconButton(
                        onPressed: _handleDismiss,
                        icon: Icon(
                          Icons.close,
                          color: errorConfig.iconColor,
                          size: 20,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                      ),
                  ],
                ),
                SizedBox(height: LuciSpacing.sm),
                Text(
                  widget.message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: errorConfig.messageColor,
                  ),
                ),
                if (widget.actionLabel != null && widget.onAction != null) ...[
                  SizedBox(height: LuciSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonal(
                      onPressed: widget.onAction,
                      style: FilledButton.styleFrom(
                        backgroundColor: errorConfig.buttonBackgroundColor,
                        foregroundColor: errorConfig.buttonTextColor,
                      ),
                      child: Text(widget.actionLabel!),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  _ErrorConfig _getErrorConfig(LuciErrorType type, ColorScheme colorScheme) {
    switch (type) {
      case LuciErrorType.error:
        return _ErrorConfig(
          backgroundColor: colorScheme.errorContainer,
          borderColor: colorScheme.error,
          iconColor: colorScheme.error,
          titleColor: colorScheme.onErrorContainer,
          messageColor: colorScheme.onErrorContainer,
          buttonBackgroundColor: colorScheme.error,
          buttonTextColor: colorScheme.onError,
          icon: Icons.error_outline,
        );
      case LuciErrorType.warning:
        return _ErrorConfig(
          backgroundColor: colorScheme.secondaryContainer,
          borderColor: colorScheme.secondary,
          iconColor: colorScheme.secondary,
          titleColor: colorScheme.onSecondaryContainer,
          messageColor: colorScheme.onSecondaryContainer,
          buttonBackgroundColor: colorScheme.secondary,
          buttonTextColor: colorScheme.onSecondary,
          icon: Icons.warning_outlined,
        );
      case LuciErrorType.info:
        return _ErrorConfig(
          backgroundColor: colorScheme.primaryContainer,
          borderColor: colorScheme.primary,
          iconColor: colorScheme.primary,
          titleColor: colorScheme.onPrimaryContainer,
          messageColor: colorScheme.onPrimaryContainer,
          buttonBackgroundColor: colorScheme.primary,
          buttonTextColor: colorScheme.onPrimary,
          icon: Icons.info_outline,
        );
      case LuciErrorType.success:
        return _ErrorConfig(
          backgroundColor: colorScheme.tertiaryContainer,
          borderColor: colorScheme.tertiary,
          iconColor: colorScheme.tertiary,
          titleColor: colorScheme.onTertiaryContainer,
          messageColor: colorScheme.onTertiaryContainer,
          buttonBackgroundColor: colorScheme.tertiary,
          buttonTextColor: colorScheme.onTertiary,
          icon: Icons.check_circle_outline,
        );
    }
  }
}

/// Error types for consistent styling
enum LuciErrorType { error, warning, info, success }

/// Configuration for error styling
class _ErrorConfig {
  const _ErrorConfig({
    required this.backgroundColor,
    required this.borderColor,
    required this.iconColor,
    required this.titleColor,
    required this.messageColor,
    required this.buttonBackgroundColor,
    required this.buttonTextColor,
    required this.icon,
  });

  final Color backgroundColor;
  final Color borderColor;
  final Color iconColor;
  final Color titleColor;
  final Color messageColor;
  final Color buttonBackgroundColor;
  final Color buttonTextColor;
  final IconData icon;
}

/// Inline error widget for form fields and compact spaces
class LuciInlineError extends StatefulWidget {
  const LuciInlineError({
    super.key,
    required this.message,
    this.type = LuciErrorType.error,
    this.showAnimation = true,
  });

  final String message;
  final LuciErrorType type;
  final bool showAnimation;

  @override
  State<LuciInlineError> createState() => _LuciInlineErrorState();
}

class _LuciInlineErrorState extends State<LuciInlineError>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: LuciAnimations.fast,
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    if (widget.showAnimation) {
      _animationController.forward();
    } else {
      _animationController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = _getErrorColor(widget.type, colorScheme);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: LuciSpacing.sm,
            vertical: LuciSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(LuciSpacing.xs),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_getErrorIcon(widget.type), size: 16, color: color),
              SizedBox(width: LuciSpacing.xs),
              Flexible(
                child: Text(
                  widget.message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getErrorColor(LuciErrorType type, ColorScheme colorScheme) {
    switch (type) {
      case LuciErrorType.error:
        return colorScheme.error;
      case LuciErrorType.warning:
        return colorScheme.secondary;
      case LuciErrorType.info:
        return colorScheme.primary;
      case LuciErrorType.success:
        return colorScheme.tertiary;
    }
  }

  IconData _getErrorIcon(LuciErrorType type) {
    switch (type) {
      case LuciErrorType.error:
        return Icons.error_outline;
      case LuciErrorType.warning:
        return Icons.warning_outlined;
      case LuciErrorType.info:
        return Icons.info_outline;
      case LuciErrorType.success:
        return Icons.check_circle_outline;
    }
  }
}

/// Snackbar-style error notification delegated to unified LuciToast system
class LuciErrorSnackbar {
  static void show(
    BuildContext context, {
    required String message,
    String? title,
    LuciErrorType type = LuciErrorType.error,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 4),
  }) {
    LuciToastType toastType;
    switch (type) {
      case LuciErrorType.error:
        toastType = LuciToastType.error;
        break;
      case LuciErrorType.warning:
        toastType = LuciToastType.warning;
        break;
      case LuciErrorType.info:
        toastType = LuciToastType.info;
        break;
      case LuciErrorType.success:
        toastType = LuciToastType.success;
        break;
    }

    LuciToastManager.show(
      context,
      title: title ?? message,
      subtitle: title != null ? message : null,
      type: toastType,
      duration: duration,
      onAction: onAction,
      actionLabel: actionLabel,
    );
  }
}
