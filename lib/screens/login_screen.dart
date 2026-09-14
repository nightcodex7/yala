// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:yet_another_luci_app/config/app_config.dart';
import 'package:yet_another_luci_app/services/local_network_permission_service.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/utils/url_parser.dart';
import 'package:yet_another_luci_app/widgets/luci_toast.dart';
import 'package:yet_another_luci_app/widgets/theme_router_logo.dart';
import 'package:yet_another_luci_app/widgets/luci_smooth_spinner.dart';
import 'package:yet_another_luci_app/screens/main_screen.dart';
import 'package:yet_another_luci_app/screens/manage_routers_screen.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/utils/os_platform_integration.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final String? initialIp;
  final String? initialUsername;
  final String? initialPassword;

  const LoginScreen({
    super.key,
    this.initialIp,
    this.initialUsername,
    this.initialPassword,
  });

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _ipController = TextEditingController();
  final _profileNameController = TextEditingController();
  final _usernameController = TextEditingController(text: 'root');
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();

  final _ipFocusNode = FocusNode();
  final _usernameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _scrollController = ScrollController();

  String? _selectedProfileId;

  bool _isConnecting = false;
  bool _passwordVisible = false;
  bool _detectingGatewayIp = false;
  late AnimationController _logoAnimController;
  late AnimationController _progressAnimController;
  bool _isActivatingReviewerMode = false;

  bool _showAutoFillHint = false;
  bool _hasDismissedAutoFillHint = false;
  String? _autoFilledIp;
  Timer? _autoFillHintTimer;

  Future<void> _dismissAutoFillHint() async {
    _autoFillHintTimer?.cancel();
    _autoFillHintTimer = null;
    if (mounted) {
      setState(() {
        _showAutoFillHint = false;
        _hasDismissedAutoFillHint = true;
      });
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hint_dismissed_login_autofill_ip', true);
    } catch (_) {
      // Guardrail: ignore storage failure
    }
  }

  Future<void> _detectGatewayIp({bool isOnInit = false}) async {
    if (_detectingGatewayIp) return;
    if (!isOnInit && mounted) {
      setState(() {
        _detectingGatewayIp = true;
      });
    }

    String? foundGateway;
    bool isMobileData = false;

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      NetworkInterface? wifiOrEthInterface;

      // 1. Check for active Wi-Fi or Ethernet interfaces (wlan, wifi, wl, eth, en, lan)
      for (final interface in interfaces) {
        final name = interface.name.toLowerCase();
        final isWifiOrEth =
            name.contains('wlan') ||
            name.contains('wifi') ||
            name.contains('wl') ||
            name.contains('eth') ||
            (name.contains('en') && !name.contains('entry')) ||
            name.contains('lan');

        if (isWifiOrEth &&
            interface.addresses.any(
              (a) => !a.isLoopback && a.type == InternetAddressType.IPv4,
            )) {
          wifiOrEthInterface = interface;
          break;
        }
      }

      // 2. Check if mobile data / cellular interface is active and NO Wi-Fi/Ethernet interface is found
      if (wifiOrEthInterface == null) {
        final hasMobileInterface = interfaces.any((interface) {
          final name = interface.name.toLowerCase();
          return name.startsWith('rmnet') ||
              name.startsWith('ccmni') ||
              name.startsWith('pdp') ||
              name.startsWith('wwan') ||
              name.startsWith('cellular') ||
              name.startsWith('mobile') ||
              name.startsWith('gprs') ||
              name.startsWith('3g') ||
              name.startsWith('4g') ||
              name.startsWith('5g') ||
              name.startsWith('lte') ||
              name.startsWith('ppp');
        });

        if (hasMobileInterface) {
          isMobileData = true;
        }
      }

      if (wifiOrEthInterface != null) {
        for (final addr in wifiOrEthInterface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              foundGateway = '${parts[0]}.${parts[1]}.${parts[2]}.1';
              break;
            }
          }
        }
      }

      if (mounted) {
        bool nextShowHint = _showAutoFillHint;
        if (isMobileData) {
          nextShowHint = false;
          if (!isOnInit) {
            context.showToastInfo(
              'Mobile Data Active',
              subtitle: 'Router IP prefill skipped on cellular connection.',
              showProgressBar: false,
            );
          }
        } else if (foundGateway != null) {
          // When triggered manually (!isOnInit) or if field is empty, update the input field
          if (!isOnInit || _ipController.text.trim().isEmpty) {
            _ipController.text = foundGateway;
            _autoFilledIp = foundGateway;
          }
          if (!_hasDismissedAutoFillHint) {
            nextShowHint = true;
            _autoFillHintTimer?.cancel();
            _autoFillHintTimer = null;
          } else {
            nextShowHint = false;
          }
          if (!isOnInit) {
            context.showToastSuccess(
              'Gateway IP Detected',
              subtitle: foundGateway,
              showProgressBar: false,
            );
          }
        } else {
          nextShowHint = false;
          if (!isOnInit) {
            context.showToastInfo(
              'No Local Gateway Detected',
              subtitle: 'Please check your Wi-Fi or Ethernet connection.',
              showProgressBar: false,
            );
          }
        }

        if (_showAutoFillHint != nextShowHint) {
          setState(() {
            _showAutoFillHint = nextShowHint;
          });
        }
      }
    } catch (_) {
      // Fail silently without clearing inputs
    } finally {
      if (mounted && !isOnInit) {
        setState(() {
          _detectingGatewayIp = false;
        });
      }
    }
  }

  void _onOtherFieldActivity() {
    final appState = ref.read(appStateProvider);
    if (appState.errorMessage != null) {
      appState.setError(null);
    }
    if (_showAutoFillHint && _autoFillHintTimer == null) {
      _startHintTimeout();
    }
  }

  void _startHintTimeout() {
    _autoFillHintTimer?.cancel();
    _autoFillHintTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        _dismissAutoFillHint();
      }
    });
  }

  Future<void> _initializeLoginScreenState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hintDismissed =
          prefs.getBool('hint_dismissed_login_autofill_ip') ?? false;

      if (!mounted) return;

      _hasDismissedAutoFillHint = hintDismissed;
    } catch (_) {
      // Guardrail: ignore storage failure
    }
  }

  @override
  void initState() {
    super.initState();

    // 1. Pre-fill form fields synchronously from constructor arguments or selectedRouter BEFORE adding listeners
    final currentRouter = ref.read(appStateProvider).selectedRouter;
    _selectedProfileId = currentRouter?.id;
    if (currentRouter?.name != null && currentRouter!.name!.isNotEmpty) {
      _profileNameController.text = currentRouter.name!;
    }
    final ip = widget.initialIp ?? currentRouter?.ipAddress;
    final user = widget.initialUsername ?? currentRouter?.username;
    final pass = widget.initialPassword ?? currentRouter?.password;

    if (ip != null && ip.isNotEmpty) {
      _ipController.text =
          (currentRouter != null &&
              currentRouter.useHttps &&
              !ip.startsWith('https://'))
          ? 'https://$ip'
          : ip;
    }
    if (user != null && user.isNotEmpty) {
      _usernameController.text = user;
    }
    if (pass != null && pass.isNotEmpty) {
      _passwordController.text = pass;
    }

    // 2. Attach focus & controller listeners after initial controller text assignment
    _ipController.addListener(_onIpChanged);
    _ipFocusNode.addListener(() => _handleFieldFocus(_ipFocusNode));
    _usernameFocusNode.addListener(() => _handleFieldFocus(_usernameFocusNode));
    _passwordFocusNode.addListener(() => _handleFieldFocus(_passwordFocusNode));
    _usernameController.addListener(_onOtherFieldActivity);
    _passwordController.addListener(_onOtherFieldActivity);

    _logoAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _progressAnimController = AnimationController(
      vsync: this,
      duration: AppConfig.reviewerModeActivationDuration,
    );

    // 3. Defer secondary async checks post-frame to keep screen transition fluid
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initializeLoginScreenState();
    });
  }

  void _selectProfile(model.Router router) {
    setState(() {
      _selectedProfileId = router.id;
      _profileNameController.text = router.name ?? '';
      _ipController.text =
          (router.useHttps && !router.ipAddress.startsWith('https://'))
          ? 'https://${router.ipAddress}'
          : router.ipAddress;
      _usernameController.text = router.username;
      _passwordController.text = router.password;
    });
    ref.read(appStateProvider).routerService?.selectRouter(router.id);
  }

  void _setupNewRouterProfile() {
    setState(() {
      _selectedProfileId = null;
      _profileNameController.clear();
      _ipController.clear();
      _usernameController.text = 'root';
      _passwordController.clear();
    });
    _detectGatewayIp();
  }

  Future<void> _openManageRouters() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ManageRoutersScreen(isFromLogin: true),
      ),
    );
    if (!mounted) return;
    final appState = ref.read(appStateProvider);
    await appState.loadRouters();
    if (!mounted) return;
    final activeRouter =
        appState.selectedRouter ??
        (appState.routers.isNotEmpty ? appState.routers.first : null);
    if (activeRouter != null) {
      _selectProfile(activeRouter);
    } else {
      _setupNewRouterProfile();
    }
  }

  void _onIpChanged() {
    if (mounted) {
      final appState = ref.read(appStateProvider);
      if (appState.errorMessage != null) {
        appState.setError(null);
      }
      final input = _ipController.text.trim();
      final cleanInput = input
          .replaceFirst('https://', '')
          .replaceFirst('http://', '')
          .replaceAll('/', '')
          .trim();
      final matchingRouter = appState.routers
          .where((r) => r.ipAddress == input || r.ipAddress == cleanInput)
          .firstOrNull;
      if (matchingRouter != null) {
        if (_selectedProfileId != matchingRouter.id) {
          setState(() {
            _selectedProfileId = matchingRouter.id;
            _profileNameController.text = matchingRouter.name ?? '';
          });
        }
      } else if (_selectedProfileId != null) {
        setState(() {
          _selectedProfileId = null;
        });
      }
    }
  }

  void _navigateToMainScreen(BuildContext context) {
    if (!mounted) return;
    final appState = ref.read(appStateProvider);
    if (!appState.hasActiveSession) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const MainScreen()),
      (route) => false,
    );
  }

  void _startReviewerModeActivation() {
    setState(() {
      _isActivatingReviewerMode = true;
    });

    // Start progress animation
    _progressAnimController.forward();

    // Start a timer to check if the user has held for 5 seconds
    Future.delayed(AppConfig.reviewerModeActivationDuration, () {
      if (_isActivatingReviewerMode && mounted) {
        _showReviewerModeDialog();
      }
    });
  }

  void _cancelReviewerModeActivation() {
    setState(() {
      _isActivatingReviewerMode = false;
    });
    // Reset progress animation
    _progressAnimController.reset();
  }

  void _showReviewerModeDialog() {
    _confirmationController.clear();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Activate Reviewer Mode?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This will enable reviewer mode which bypasses authentication '
                  'and provides mock data for app demonstration purposes.',
                ),
                const SizedBox(height: 16),
                const Text(
                  'To confirm, type "REVIEWER" below:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _confirmationController,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    TextInputFormatter.withFunction(
                      (oldValue, newValue) => TextEditingValue(
                        text: newValue.text.toUpperCase(),
                        selection: newValue.selection,
                      ),
                    ),
                  ],
                  decoration: const InputDecoration(
                    hintText: 'Type REVIEWER',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  _confirmationController.text.trim().toUpperCase() ==
                      'REVIEWER'
                  ? () {
                      Navigator.of(context).pop();
                      _activateReviewerMode();
                    }
                  : null,
              child: const Text('Activate'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _activateReviewerMode() async {
    final appState = ref.read(appStateProvider);
    await appState.setReviewerMode(true);

    if (mounted) {
      _navigateToMainScreen(context);
    }
  }

  void _handleFieldFocus(FocusNode focusNode) {
    if (focusNode.hasFocus) {
      _onOtherFieldActivity();
      final targetContext = focusNode.context;
      if (targetContext == null) return;
      Future.delayed(const Duration(milliseconds: 180), () {
        if (!mounted || !targetContext.mounted) return;
        Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          alignment: 0.5,
        );
      });
    }
  }

  @override
  void dispose() {
    _autoFillHintTimer?.cancel();
    _usernameController.removeListener(_onOtherFieldActivity);
    _passwordController.removeListener(_onOtherFieldActivity);
    _ipController.removeListener(_onIpChanged);
    _ipController.dispose();
    _profileNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    _ipFocusNode.dispose();
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    _scrollController.dispose();
    _logoAnimController.dispose();
    _progressAnimController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_formKey.currentState!.validate()) {
      final hasPermission =
          await LocalNetworkPermissionService.ensurePermissionGranted();
      if (!hasPermission) {
        ref
            .read(appStateProvider)
            .setError(
              'Local Network Access permission is required to connect to your router.',
            );
        return;
      }

      if (mounted) {
        setState(() {
          _isConnecting = true;
        });
      }
      final appState = ref.read(appStateProvider);
      final input = _ipController.text.trim();
      final user = _usernameController.text.trim();
      final pass = _passwordController.text;

      // Parse the input to extract host, port, and protocol
      final parsedUrl = UrlParser.parse(input);

      if (!parsedUrl.isValid) {
        appState.setError(parsedUrl.error ?? 'Invalid address format');
        if (mounted) {
          setState(() {
            _isConnecting = false;
          });
        }
        return;
      }

      if (!mounted) return;
      FocusScope.of(context).unfocus();

      const actionKey = 'login_connecting';
      context.showToastLoading(
        'Connecting',
        subtitle: 'Attempting connection to ${parsedUrl.displayUrl}...',
        actionKey: actionKey,
      );

      try {
        final customName = _profileNameController.text.trim().isEmpty
            ? null
            : _profileNameController.text.trim();
        final success = await appState.login(
          parsedUrl.hostWithPort,
          user,
          pass,
          parsedUrl.useHttps,
          fromRouter: false,
          routerName: customName,
          context: mounted ? context : null,
        );

        if (success && mounted) {
          LuciToastManager.dismissAllLoading();
          TextInput.finishAutofillContext(shouldSave: true);
          _navigateToMainScreen(context);
        } else if (mounted) {
          LuciToastManager.dismissAllLoading();
          final errorMsg =
              appState.errorMessage ??
              'Connection failed to ${parsedUrl.displayUrl}. Please check host reachability, username, and password.';
          context.showToastError('Connection Failed', subtitle: errorMsg);
        }
      } catch (err) {
        if (mounted) {
          LuciToastManager.dismissAllLoading();
          context.showToastError('Connection Error', subtitle: err.toString());
        }
      } finally {
        if (mounted) {
          setState(() {
            _isConnecting = false;
          });
        }
        // Guarantee loading toast cleanup even if context was unmounted during route push
        LuciToastManager.dismissAllLoading();
      }
    }
  }

  Future<void> _openGitHubIssues() async {
    final url = AppConfig.githubIssuesUrl;
    final success = await launchUrlString(
      url,
      mode: LaunchMode.externalApplication,
    );
    if (!success && mounted) {
      context.showToastError(
        'GitHub Error',
        subtitle: 'Could not open GitHub issues link.',
      );
    }
  }

  void _showHelpBottomSheet(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.help_outline_rounded, color: colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  'Login Troubleshooting Guide',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildHelpItem(
              context,
              icon: Icons.wifi_find_rounded,
              title: 'Connect to Router Wi-Fi / Network',
              description:
                  'Ensure your device is directly connected to your router\'s Wi-Fi network or local subnet.',
            ),
            const SizedBox(height: 12),
            _buildHelpItem(
              context,
              icon: Icons.lan_rounded,
              title: 'Verify Gateway IP Address',
              description:
                  'Most OpenWrt routers use 192.168.1.1 or 192.168.0.1. Check your network settings if custom subnets are used.',
            ),
            const SizedBox(height: 12),
            _buildHelpItem(
              context,
              icon: Icons.lock_person_rounded,
              title: 'LuCI Admin Credentials',
              description:
                  'Use the same username (default: root) and password as your standard LuCI browser web interface.',
            ),
            const SizedBox(height: 12),
            _buildHelpItem(
              context,
              icon: Icons.https_rounded,
              title: 'Self-Signed SSL / HTTPS Settings',
              description:
                  'If your router uses HTTPS with self-signed SSL certificates, open Advanced Options and toggle "Use HTTPS".',
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openGitHubIssues();
                    },
                    icon: const Icon(Icons.bug_report_rounded, size: 18),
                    label: const Text('GitHub Issues'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Got It'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<bool?> _showExitConfirmationDialog(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.exit_to_app_rounded,
                color: colorScheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Exit Yala?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to exit the application?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final meshColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.04);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await _showExitConfirmationDialog(context);
        if (shouldExit == true && context.mounted) {
          await OsPlatformIntegration.exitApp(context: context);
        }
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Stack(
          children: [
            // Elegant Matte Network Topology Mesh Background Graphic
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _NetworkTopologyMeshPainter(meshColor: meshColor),
                ),
              ),
            ),

            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide =
                      constraints.maxWidth >= 768 &&
                      constraints.maxHeight >= 480;

                  return SingleChildScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: ClampingScrollPhysics(),
                    ),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.symmetric(
                      horizontal: isWide ? 32 : 20,
                      vertical: 18,
                    ),
                    child: Align(
                      alignment: isWide
                          ? Alignment.center
                          : Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: (constraints.maxHeight - 36).clamp(
                            0.0,
                            double.infinity,
                          ),
                          maxWidth: isWide ? 920 : 460,
                        ),
                        child: isWide
                            ? IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // Left Pane: Hero Brand, LAN Security & Footers
                                    Expanded(
                                      flex: 5,
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          _buildHeaderLockup(
                                            context,
                                            isWide: true,
                                          ),
                                          const SizedBox(height: 24),
                                          _buildSecurityAssurance(context),
                                          const SizedBox(height: 20),
                                          _buildFooterLinks(context),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 32),
                                    // Right Pane: Router Endpoint Console Form
                                    Expanded(
                                      flex: 6,
                                      child: Center(
                                        child: _buildFormCard(
                                          context,
                                          showSecurityInCard: false,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : IntrinsicHeight(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const SizedBox(height: 8),
                                    _buildHeaderLockup(context),
                                    const SizedBox(height: 18),
                                    _buildFormCard(
                                      context,
                                      showSecurityInCard: true,
                                    ),
                                    const SizedBox(height: 20),
                                    _buildFooterLinks(context),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderLockup(BuildContext context, {bool isWide = false}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primaryColor = colorScheme.primary;

    return GestureDetector(
      onLongPress: _startReviewerModeActivation,
      onLongPressUp: _cancelReviewerModeActivation,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(isWide ? 20 : 16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ThemeRouterLogo(
              width: isWide ? 80 : 68,
              height: isWide ? 80 : 68,
              showShadow: false,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Yet Another LuCI App',
            style:
                (isWide
                        ? theme.textTheme.headlineLarge
                        : theme.textTheme.headlineMedium)
                    ?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                      letterSpacing: 0.3,
                    ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'OpenWrt Router Console',
            style: theme.textTheme.titleSmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          // Console Technical Tag
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'DIRECT LAN CONNECTION',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: primaryColor,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _isActivatingReviewerMode
                ? Padding(
                    key: const ValueKey('progress'),
                    padding: const EdgeInsets.only(top: 14),
                    child: AnimatedBuilder(
                      animation: _progressAnimController,
                      builder: (context, child) {
                        return Column(
                          children: [
                            Text(
                              'Hold to activate reviewer mode...',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: primaryColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: 240,
                              height: 5,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: colorScheme.surfaceContainerHighest,
                                border: Border.all(
                                  color: colorScheme.outlineVariant.withValues(
                                    alpha: 0.4,
                                  ),
                                  width: 0.5,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: LinearProgressIndicator(
                                  value: _progressAnimController.value,
                                  backgroundColor: Colors.transparent,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    primaryColor,
                                  ),
                                  minHeight: 5,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  )
                : const SizedBox(key: ValueKey('empty'), height: 0),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard(
    BuildContext context, {
    required bool showSecurityInCard,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primaryColor = colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18.0),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Router Profiles Selector
              _buildRouterProfilesSelector(context),

              // Network Target Endpoint Banner
              Row(
                children: [
                  Icon(Icons.lan_outlined, size: 15, color: primaryColor),
                  const SizedBox(width: 6),
                  Text(
                    'TARGET ROUTER ENDPOINT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Profile Name Field (Optional)
              TextFormField(
                key: const ValueKey('login_profile_name_field'),
                controller: _profileNameController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Profile Name (Optional)',
                  hintText: 'e.g. Home Lab, Living Room, Travel Router',
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.35,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: primaryColor, width: 1.5),
                  ),
                  prefixIcon: Icon(
                    Icons.label_outline_rounded,
                    color: primaryColor,
                  ),
                  helperText: 'A custom nickname to identify this router',
                ),
              ),
              const SizedBox(height: 14),

              // Router Address Field
              Tooltip(
                message:
                    'Enter the IP address, hostname, or full URL of your router',
                child: TextFormField(
                  key: const ValueKey('login_ip_field'),
                  controller: _ipController,
                  focusNode: _ipFocusNode,
                  keyboardType: TextInputType.url,
                  scrollPadding: const EdgeInsets.only(
                    bottom: 100.0,
                    top: 20.0,
                  ),
                  autofillHints: const [AutofillHints.url],
                  decoration: InputDecoration(
                    labelText: 'Router Address',
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.35,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: primaryColor, width: 1.5),
                    ),
                    prefixIcon: Icon(
                      Icons.router_outlined,
                      color: primaryColor,
                    ),
                    suffixIcon: IconButton(
                      icon: _detectingGatewayIp
                          ? LuciSmoothSpinner(
                              size: 18,
                              strokeWidth: 2,
                              color: primaryColor,
                            )
                          : Icon(
                              Icons.my_location_rounded,
                              color: primaryColor,
                            ),
                      tooltip: 'Auto-detect Wi-Fi Gateway IP',
                      onPressed: () => _detectGatewayIp(),
                    ),
                    helperText: 'e.g. 192.168.1.1, router.local:8080',
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter the router address';
                    }
                    final parsed = UrlParser.parse(value);
                    if (!parsed.isValid) {
                      return parsed.error ?? 'Invalid address format';
                    }
                    return null;
                  },
                ),
              ),

              // Auto-fill hint banner
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) => SizeTransition(
                  sizeFactor: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: (_showAutoFillHint && _autoFilledIp != null)
                    ? Container(
                        key: const ValueKey('autofill_floating_hint'),
                        margin: const EdgeInsets.only(top: 8, bottom: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.6,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: primaryColor.withValues(alpha: 0.4),
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              size: 14,
                              color: primaryColor,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Auto-filled $_autoFilledIp from active network',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: _dismissAutoFillHint,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(3.0),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 15,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(
                        key: ValueKey('no_autofill_hint'),
                        height: 8,
                      ),
              ),

              const SizedBox(height: 10),

              // Username Field
              Tooltip(
                message: 'Enter your router username',
                child: TextFormField(
                  key: const ValueKey('login_user_field'),
                  controller: _usernameController,
                  focusNode: _usernameFocusNode,
                  keyboardType: TextInputType.text,
                  scrollPadding: const EdgeInsets.only(
                    bottom: 100.0,
                    top: 20.0,
                  ),
                  autofillHints: const [
                    AutofillHints.username,
                    AutofillHints.email,
                  ],
                  decoration: InputDecoration(
                    labelText: 'Username',
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.35,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: primaryColor, width: 1.5),
                    ),
                    prefixIcon: Icon(
                      Icons.person_outlined,
                      color: primaryColor,
                    ),
                    helperText: 'Default is usually root',
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter the username';
                    }
                    return null;
                  },
                ),
              ),

              const SizedBox(height: 10),

              // Password Field
              Tooltip(
                message: 'Enter your router password',
                child: TextFormField(
                  key: const ValueKey('login_pass_field'),
                  controller: _passwordController,
                  focusNode: _passwordFocusNode,
                  obscureText: !_passwordVisible,
                  keyboardType: TextInputType.visiblePassword,
                  scrollPadding: const EdgeInsets.only(
                    bottom: 100.0,
                    top: 20.0,
                  ),
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'Password',
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.35,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: primaryColor, width: 1.5),
                    ),
                    prefixIcon: Icon(Icons.lock_outlined, color: primaryColor),
                    helperText: 'Your router password',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _passwordVisible
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      onPressed: () =>
                          setState(() => _passwordVisible = !_passwordVisible),
                      tooltip: _passwordVisible
                          ? 'Hide password'
                          : 'Show password',
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                ),
              ),

              // Error Message Banner
              Consumer(
                builder: (context, ref, child) {
                  final errorMessage = ref.watch(
                    appStateProvider.select((s) => s.errorMessage),
                  );
                  final hasError =
                      errorMessage != null && errorMessage.trim().isNotEmpty;
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: hasError
                        ? Padding(
                            key: const ValueKey('error'),
                            padding: const EdgeInsets.only(top: 14.0),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: colorScheme.error.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    color: colorScheme.onErrorContainer,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      errorMessage,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: colorScheme.onErrorContainer,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  );
                },
              ),

              const SizedBox(height: 18),

              // Matte Tactile Connect Action Button
              Consumer(
                builder: (context, ref, child) {
                  final isLoading = ref.watch(
                    appStateProvider.select((s) => s.isLoading),
                  );
                  return TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 100),
                    tween: Tween<double>(begin: 1, end: isLoading ? 0.98 : 1),
                    builder: (context, scale, child) {
                      return Transform.scale(scale: scale, child: child);
                    },
                    child: FilledButton(
                      onPressed: (isLoading || _isConnecting) ? null : _connect,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: primaryColor,
                        foregroundColor: colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: isLoading
                          ? LuciSmoothSpinner(
                              size: 22,
                              strokeWidth: 2.5,
                              color: colorScheme.onPrimary,
                            )
                          : FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.arrow_forward_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'CONNECT TO ROUTER',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  );
                },
              ),

              if (showSecurityInCard) ...[
                const SizedBox(height: 14),
                _buildSecurityAssurance(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRouterProfilesSelector(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final routers = appState.routers;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primaryColor = colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(Icons.router_outlined, size: 15, color: primaryColor),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      routers.isEmpty
                          ? 'ROUTER PROFILES'
                          : 'ROUTER PROFILES (${routers.length})',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.8,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: _openManageRouters,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tune_rounded, size: 14, color: primaryColor),
                    const SizedBox(width: 4),
                    Text(
                      'Manage',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (routers.isNotEmpty)
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: routers.length + 1,
              separatorBuilder: (context, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                if (index == routers.length) {
                  // "+ New Router" chip
                  final isNewSelected = _selectedProfileId == null;
                  return ActionChip(
                    avatar: Icon(
                      Icons.add_rounded,
                      size: 16,
                      color: isNewSelected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                    label: Text(
                      'New Router',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isNewSelected
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: isNewSelected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    backgroundColor: isNewSelected
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.4,
                          ),
                    side: BorderSide(
                      color: isNewSelected
                          ? primaryColor.withValues(alpha: 0.5)
                          : colorScheme.outlineVariant.withValues(alpha: 0.4),
                      width: 1,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    onPressed: _setupNewRouterProfile,
                  );
                }

                final router = routers[index];
                final isSelected =
                    _selectedProfileId == router.id ||
                    (_selectedProfileId == null &&
                        _ipController.text == router.ipAddress);
                final displayName = router.displayName;

                return ChoiceChip(
                  avatar: isSelected
                      ? Icon(
                          Icons.check_circle_rounded,
                          size: 15,
                          color: colorScheme.onPrimary,
                        )
                      : Icon(
                          Icons.dns_outlined,
                          size: 15,
                          color: colorScheme.onSurfaceVariant,
                        ),
                  label: Text(
                    displayName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: isSelected
                          ? colorScheme.onPrimary
                          : colorScheme.onSurface,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: primaryColor,
                  backgroundColor: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.35),
                  side: BorderSide(
                    color: isSelected
                        ? primaryColor
                        : colorScheme.outlineVariant.withValues(alpha: 0.4),
                    width: 1,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  showCheckmark: false,
                  onSelected: (selected) {
                    if (selected) {
                      _selectProfile(router);
                    }
                  },
                );
              },
            ),
          )
        else
          InkWell(
            onTap: _openManageRouters,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.25,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.add_circle_outline_rounded,
                    size: 16,
                    color: primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No routers saved. Setup multiple routers or connect below.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _buildSecurityAssurance(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primaryColor = colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 18, color: primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Direct Local Connection: ',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  TextSpan(
                    text:
                        'Communicates exclusively with your local OpenWrt router over LAN/Wi-Fi. Zero analytics or cloud servers.',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.3,
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

  Widget _buildFooterLinks(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primaryColor = colorScheme.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Need Help Link
        Tooltip(
          message: 'Open troubleshooting guide',
          child: TextButton(
            onPressed: () => _showHelpBottomSheet(context),
            style: TextButton.styleFrom(
              foregroundColor: primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text(
              'Need help?',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ),
        // Version & Legal Footer Links
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snapshot) {
            final versionText = snapshot.hasData
                ? 'Version ${snapshot.data!.version}'
                : 'Version 1.0.0';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    versionText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.6,
                      ),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      InkWell(
                        onTap: () => launchUrlString(
                          AppConfig.privacyPolicyUrl,
                          mode: LaunchMode.externalApplication,
                        ),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            'Privacy Policy',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary.withValues(
                                alpha: 0.85,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Text(
                        '•',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => launchUrlString(
                          AppConfig.termsAndConditionsUrl,
                          mode: LaunchMode.externalApplication,
                        ),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            'Terms & Conditions',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary.withValues(
                                alpha: 0.85,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Attractive Network Topology Mesh Background Graphic
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
