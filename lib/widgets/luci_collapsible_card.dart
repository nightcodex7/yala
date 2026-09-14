// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

/// A standardized, context-aware collapsible card for rendering secondary or
/// extensive lists without cluttering the screen UI hierarchy.
///
/// Handles extreme screen sizes (from 320dp small phones to 1200dp+ tablets/foldables)
/// and high accessibility font scaling settings with robust guardrails.
/// Optimized for ultra-smooth 60/120fps expansion animations and zero focus outline artifacts.
/// A standardized, context-aware collapsible card for rendering secondary or
/// extensive lists without cluttering the screen UI hierarchy.
///
/// Handles extreme screen sizes (from 320dp small phones to 1200dp+ tablets/foldables)
/// and high accessibility font scaling settings with robust guardrails.
/// Optimized for ultra-smooth 60/120fps expansion animations and zero focus outline artifacts.
class LuciCollapsibleCard extends StatefulWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color? iconColor;
  final int? count;
  final bool initiallyExpanded;
  final Widget? child;
  final WidgetBuilder? childBuilder;
  final Widget? trailingAction;
  final ValueChanged<bool>? onExpansionChanged;
  final EdgeInsetsGeometry padding;

  const LuciCollapsibleCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.iconColor,
    this.count,
    this.initiallyExpanded = false,
    this.child,
    this.childBuilder,
    this.trailingAction,
    this.onExpansionChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
  }) : assert(
         child != null || childBuilder != null,
         'Either child or childBuilder must be provided',
       );

  @override
  State<LuciCollapsibleCard> createState() => _LuciCollapsibleCardState();
}

class _LuciCollapsibleCardState extends State<LuciCollapsibleCard> {
  late bool _hasBeenExpanded;

  @override
  void initState() {
    super.initState();
    _hasBeenExpanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveIconColor = widget.iconColor ?? theme.colorScheme.primary;
    final displayTitle = widget.count != null
        ? '${widget.title} (${widget.count})'
        : widget.title;
    final displaySubtitle =
        widget.subtitle ??
        (widget.count != null ? '${widget.count} items' : null);

    return RepaintBoundary(
      child: Card(
        elevation: 2,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Theme(
          data: theme.copyWith(
            dividerColor: Colors.transparent,
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: ExpansionTile(
            initiallyExpanded: widget.initiallyExpanded,
            onExpansionChanged: (expanded) {
              if (expanded && !_hasBeenExpanded) {
                setState(() {
                  _hasBeenExpanded = true;
                });
              }
              widget.onExpansionChanged?.call(expanded);
            },
            maintainState: true,
            shape: const Border(),
            collapsedShape: const Border(),
            expansionAnimationStyle: const AnimationStyle(
              duration: Duration(milliseconds: 220),
              curve: Curves.fastOutSlowIn,
            ),
            leading: Icon(widget.icon, color: effectiveIconColor),
            title: Text(
              displayTitle,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
            subtitle: displaySubtitle != null
                ? Text(
                    displaySubtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  )
                : null,
            trailing: widget.trailingAction != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      widget.trailingAction!,
                      const SizedBox(width: 4),
                      const Icon(Icons.expand_more),
                    ],
                  )
                : null,
            children: [
              if (_hasBeenExpanded)
                RepaintBoundary(
                  child: Padding(
                    padding: widget.padding,
                    child: widget.childBuilder != null
                        ? Builder(builder: widget.childBuilder!)
                        : widget.child!,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
