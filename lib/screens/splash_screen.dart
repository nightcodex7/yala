// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/services/secure_storage_service.dart';
import 'package:yet_another_luci_app/config/app_config.dart';
import 'package:yet_another_luci_app/widgets/theme_router_logo.dart';
import 'package:yet_another_luci_app/screens/main_screen.dart';
import 'package:yet_another_luci_app/screens/login_screen.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:yet_another_luci_app/utils/logger.dart';

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
    final appState = AppState.instance;

    try {
      // Concurrently await AppState startup hydration alongside credentials and fingerprints
      final reviewerStorageFuture = SecureStorageService().readValue(
        AppConfig.reviewerModeKey,
      );
      final credsFuture = SecureStorageService().getCredentials();
      final fingerprintsFuture = ClientFingerprintService.instance.initialize();
      final appStateInitFuture = appState.initializationFuture;
      final disableAnimations = mounted
          ? MediaQuery.of(context).disableAnimations
          : false;
      final minSplashDurationFuture = disableAnimations
          ? Future<void>.value()
          : Future<void>.delayed(const Duration(milliseconds: 750));

      final results = await Future.wait([
        reviewerStorageFuture,
        credsFuture,
        fingerprintsFuture,
        appStateInitFuture,
        minSplashDurationFuture,
      ]);

      final reviewerModeEnabled = results[0] as String?;
      final creds = results[1] as Map<String, String?>;

      if (!mounted) return;

      if (reviewerModeEnabled == 'true') {
        await appState.setReviewerMode(true);
        if (!mounted) return;
        _navigateToMainScreen();
        return;
      }

      final savedIp = creds['ipAddress'] ?? appState.selectedRouter?.ipAddress;
      final savedUser = creds['username'] ?? appState.selectedRouter?.username;
      final savedPass = creds['password'] ?? appState.selectedRouter?.password;

      _navigateToLoginScreen(
        initialIp: savedIp,
        initialUsername: savedUser,
        initialPassword: savedPass,
      );
    } catch (e, stack) {
      Logger.exception(
        'SplashScreen initialization failed, navigating to login fallback',
        e,
        stack,
      );
      if (!mounted) return;
      _navigateToLoginScreen();
    }
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
    final l10n = AppLocalizations.of(context);

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
                                            l10n?.splashRouterManagementSubtitle ??
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
                                      l10n?.splashInitializingConsole ??
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
                    child: Tooltip(
                      message: 'GitHub: @nightcodex7',
                      child: InkWell(
                        onTap: () => launchUrlString(
                          'https://github.com/nightcodex7',
                          mode: LaunchMode.externalApplication,
                        ),
                        borderRadius: BorderRadius.circular(12),
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
                              CustomPaint(
                                size: const Size(14, 14),
                                painter: _GithubMarkPainter(
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.85),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  '@nightcodex7',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.9),
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.2,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
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

/// Permitted monochromatic GitHub Invertocat Logo vector mark conforming to
/// brand.github.com/foundations/logo.
class _GithubMarkPainter extends CustomPainter {
  final Color color;

  const _GithubMarkPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.save();
    canvas.scale(size.width / 24.0, size.height / 24.0);

    final path = Path();
    path.moveTo(12.0, 0.297);
    path.relativeCubicTo(-6.63, 0.0, -12.0, 5.373, -12.0, 12.0);
    path.relativeCubicTo(0.0, 5.303, 3.438, 9.8, 8.205, 11.385);
    path.relativeCubicTo(0.6, 0.113, 0.82, -0.258, 0.82, -0.577);
    path.relativeCubicTo(0.0, -0.285, -0.01, -1.04, -0.015, -2.04);
    path.relativeCubicTo(-3.338, 0.724, -4.042, -1.61, -4.042, -1.61);
    path.cubicTo(4.422, 18.07, 3.633, 17.7, 3.633, 17.7);
    path.relativeCubicTo(-1.087, -0.744, 0.084, -0.729, 0.084, -0.729);
    path.relativeCubicTo(1.205, 0.084, 1.838, 1.236, 1.838, 1.236);
    path.relativeCubicTo(1.07, 1.835, 2.809, 1.305, 3.495, 0.998);
    path.relativeCubicTo(0.108, -0.776, 0.417, -1.305, 0.76, -1.605);
    path.relativeCubicTo(-2.665, -0.3, -5.466, -1.332, -5.466, -5.93);
    path.relativeCubicTo(0.0, -1.31, 0.465, -2.38, 1.235, -3.22);
    path.relativeCubicTo(-0.135, -0.303, -0.54, -1.523, 0.105, -3.176);
    path.relativeCubicTo(0.0, 0.0, 1.005, -0.322, 3.3, 1.23);
    path.relativeCubicTo(0.96, -0.267, 1.98, -0.399, 3.0, -0.405);
    path.relativeCubicTo(1.02, 0.006, 2.04, 0.138, 3.0, 0.405);
    path.relativeCubicTo(2.28, -1.552, 3.285, -1.23, 3.285, -1.23);
    path.relativeCubicTo(0.645, 1.653, 0.24, 2.873, 0.12, 3.176);
    path.relativeCubicTo(0.765, 0.84, 1.23, 1.91, 1.23, 3.22);
    path.relativeCubicTo(0.0, 4.61, -2.805, 5.625, -5.475, 5.92);
    path.relativeCubicTo(0.42, 0.36, 0.81, 1.096, 0.81, 2.22);
    path.relativeCubicTo(0.0, 1.606, -0.015, 2.896, -0.015, 3.286);
    path.relativeCubicTo(0.0, 0.315, 0.21, 0.69, 0.825, 0.57);
    path.cubicTo(20.565, 22.092, 24.0, 17.592, 24.0, 12.297);
    path.relativeCubicTo(0.0, -6.627, -5.373, -12.0, -12.0, -12.0);
    path.close();

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GithubMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
