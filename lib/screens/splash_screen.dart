// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/services/secure_storage_service.dart';
import 'package:yet_another_luci_app/services/local_network_permission_service.dart';
import 'package:yet_another_luci_app/config/app_config.dart';
import 'package:yet_another_luci_app/widgets/theme_router_logo.dart';
import 'package:yet_another_luci_app/screens/main_screen.dart';
import 'package:yet_another_luci_app/screens/login_screen.dart';

import 'package:yet_another_luci_app/services/client_fingerprint_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _logoScale;
  late Animation<double> _logoFade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _logoScale = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _logoFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
    );
    _controller.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initializeAppSession();
    });
  }

  Future<void> _initializeAppSession() async {
    // Concurrently read minimum signals (reviewer mode preference & saved credentials & local fingerprints)
    final reviewerStorageFuture = SecureStorageService().readValue(
      AppConfig.reviewerModeKey,
    );
    final credsFuture = SecureStorageService().getCredentials();
    final fingerprintsFuture = ClientFingerprintService.instance.initialize();

    final results = await Future.wait([
      reviewerStorageFuture,
      credsFuture,
      fingerprintsFuture,
    ]);

    final reviewerModeEnabled = results[0] as String?;
    final creds = results[1] as Map<String, String?>;

    if (!mounted) return;

    final appState = AppState.instance;

    if (reviewerModeEnabled == 'true') {
      await appState.setReviewerMode(true);
      if (!mounted) return;
      _navigateToMainScreen();
      return;
    }

    final hasSavedCreds =
        creds['ipAddress'] != null &&
        creds['ipAddress']!.isNotEmpty &&
        creds['password'] != null;

    if (hasSavedCreds) {
      final hasPermission =
          await LocalNetworkPermissionService.ensurePermissionGranted();
      if (!mounted) return;
      if (!hasPermission) {
        _navigateToLoginScreen(
          initialIp: creds['ipAddress'],
          initialUsername: creds['username'],
          initialPassword: creds['password'],
        );
        return;
      }
      final success = await appState.tryAutoLogin(
        context: mounted ? context : null,
      );
      if (!mounted) return;
      if (success && appState.hasActiveSession) {
        _navigateToMainScreen();
        return;
      }
    }

    _navigateToLoginScreen(
      initialIp: creds['ipAddress'],
      initialUsername: creds['username'],
      initialPassword: creds['password'],
    );
  }

  void _navigateToMainScreen() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const MainScreen()),
      (route) => false,
    );
  }

  void _navigateToLoginScreen({
    String? initialIp,
    String? initialUsername,
    String? initialPassword,
  }) {
    if (!mounted) return;
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => LoginScreen(
          initialIp: initialIp,
          initialUsername: initialUsername,
          initialPassword: initialPassword,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (disableAnimations) return child;
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOutCubic,
          );
          final scaleAnimation = Tween<double>(
            begin: 0.97,
            end: 1.0,
          ).animate(curved);
          return RepaintBoundary(
            child: FadeTransition(
              opacity: curved,
              child: ScaleTransition(scale: scaleAnimation, child: child),
            ),
          );
        },
        transitionDuration: disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 450),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primaryColor = colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;

    final meshColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.04);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Subtle Network Topology Mesh Background Graphic
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _NetworkTopologyMeshPainter(meshColor: meshColor),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  // Centered Vertical Lockup
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Clean Logo Container
                            ScaleTransition(
                              scale: _logoScale,
                              child: FadeTransition(
                                opacity: _logoFade,
                                child: Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainer,
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.04,
                                        ),
                                        blurRadius: 16,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const ThemeRouterLogo(
                                    width: 88,
                                    height: 88,
                                    showShadow: false,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Technical Brand Typography
                            FadeTransition(
                              opacity: _logoFade,
                              child: Column(
                                children: [
                                  Text(
                                    'Yet Another LuCI App',
                                    style: theme.textTheme.headlineMedium
                                        ?.copyWith(
                                          color: colorScheme.onSurface,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.3,
                                        ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 10),

                                  // Matte Technical Subtitle Badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainerHighest
                                          .withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: colorScheme.outlineVariant
                                            .withValues(alpha: 0.6),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.router_outlined,
                                          size: 14,
                                          color: primaryColor,
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            'OpenWrt Router Management System',
                                            style: theme.textTheme.labelMedium
                                                ?.copyWith(
                                                  color: colorScheme
                                                      .onSurfaceVariant,
                                                  fontWeight: FontWeight.w600,
                                                  letterSpacing: 0.2,
                                                ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),

                            // Compact Status / Loading Indicator
                            FadeTransition(
                              opacity: _logoFade,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainer
                                      .withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: colorScheme.outlineVariant
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              primaryColor,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'INITIALIZING CONSOLE',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.8,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Clean Footer Pinned at Bottom
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainer.withValues(
                          alpha: 0.7,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.4,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'by @nightcodex7',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.8,
                              ),
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                          const Text('🐙', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 4),
                          Text(
                            '@nightcodex7',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: primaryColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Network Topology Mesh Background Graphic
class _NetworkTopologyMeshPainter extends CustomPainter {
  final Color meshColor;

  _NetworkTopologyMeshPainter({required this.meshColor});

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = meshColor
      ..strokeWidth = 1.0;

    final nodePaint = Paint()
      ..color = meshColor.withValues(alpha: (meshColor.a * 1.8).clamp(0.0, 1.0))
      ..style = PaintingStyle.fill;

    const double spacing = 64.0;
    final int cols = (size.width / spacing).ceil() + 1;
    final int rows = (size.height / spacing).ceil() + 1;

    // Generate deterministic grid node offsets for an architectural isometric mesh
    final List<List<Offset>> grid = [];

    for (int r = 0; r < rows; r++) {
      final List<Offset> row = [];
      for (int c = 0; c < cols; c++) {
        final double x = c * spacing + (r % 2 == 1 ? spacing * 0.5 : 0.0);
        final double y = r * spacing * 0.866; // Hexagonal vertical ratio
        row.add(Offset(x, y));
      }
      grid.add(row);
    }

    // Draw isometric connecting lines
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final Offset pt = grid[r][c];

        // Right connection
        if (c + 1 < cols) {
          canvas.drawLine(pt, grid[r][c + 1], linePaint);
        }
        // Down-right connection
        if (r + 1 < rows) {
          if (r % 2 == 0) {
            if (c < cols) canvas.drawLine(pt, grid[r + 1][c], linePaint);
            if (c - 1 >= 0) canvas.drawLine(pt, grid[r + 1][c - 1], linePaint);
          } else {
            if (c < cols) canvas.drawLine(pt, grid[r + 1][c], linePaint);
            if (c + 1 < cols) {
              canvas.drawLine(pt, grid[r + 1][c + 1], linePaint);
            }
          }
        }

        // Draw small node points at alternate intersections
        if ((r + c) % 3 == 0) {
          canvas.drawCircle(pt, 2.0, nodePaint);
        }
      }
    }

    // Border tick marks / scale indicators for technical feel
    final tickPaint = Paint()
      ..color = meshColor.withValues(alpha: (meshColor.a * 2.0).clamp(0.0, 1.0))
      ..strokeWidth = 1.2;

    const double tickLen = 6.0;
    for (double y = 40; y < size.height - 40; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(tickLen, y), tickPaint);
      canvas.drawLine(
        Offset(size.width - tickLen, y),
        Offset(size.width, y),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NetworkTopologyMeshPainter oldDelegate) {
    return oldDelegate.meshColor != meshColor;
  }
}
