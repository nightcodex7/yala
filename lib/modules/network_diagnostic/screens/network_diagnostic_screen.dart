// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../design/luci_design_system.dart';
import '../../../l10n/app_localizations.dart';
import '../../../main.dart';
import '../../../widgets/luci_app_bar.dart';
import '../controllers/network_diagnostic_controller.dart';
import '../models/diagnostic_confidence.dart';
import '../models/diagnostic_status.dart';
import '../models/diagnostic_test_result.dart';
import '../models/root_cause_finding.dart';

typedef NetworkDiagnosticView = NetworkDiagnosticScreen;

class NetworkDiagnosticScreen extends ConsumerWidget {
  final bool showAppBar;

  const NetworkDiagnosticScreen({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(networkDiagnosticControllerProvider);
    final controller = ref.read(networkDiagnosticControllerProvider.notifier);
    final appState = ref.watch(appStateProvider);

    final routerName =
        appState.selectedRouter?.name ??
        (appState.reviewerModeEnabled
            ? 'Demo Router (Reviewer Mode)'
            : 'Router');
    final routerIp =
        appState.selectedRouter?.ipAddress ??
        (appState.reviewerModeEnabled ? '192.168.1.1' : 'Unknown IP');

    final displayResults = state.showOnlyIssues
        ? state.liveResults.where((r) => r.status.isProblem).toList()
        : state.liveResults;

    final issueCount = state.liveResults
        .where((r) => r.status.isProblem)
        .length;

    final content = SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: LuciSpacing.md,
        vertical: LuciSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Hero Assessment & Action Card
          _buildHeroAssessmentCard(
            context,
            state: state,
            controller: controller,
            routerName: routerName,
            routerIp: routerIp,
          ),
          const SizedBox(height: LuciSpacing.md),

          // 2. Active Root Cause Findings (if any)
          if (state.report?.findings.isNotEmpty == true) ...[
            _buildSectionHeader(
              context,
              title:
                  l10n?.netDiagSectionFindings ??
                  'Root-Cause Findings & Evidence',
              icon: Icons.lightbulb_outline_rounded,
            ),
            const SizedBox(height: LuciSpacing.xs),
            ...state.report!.findings.map(
              (finding) => _buildFindingCard(context, finding),
            ),
            const SizedBox(height: LuciSpacing.md),
          ],

          // 3. Test Results Breakdown
          if (state.liveResults.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSectionHeader(
                  context,
                  title:
                      l10n?.netDiagSectionResults ?? 'Diagnostic Test Results',
                  icon: Icons.checklist_rounded,
                ),
                if (issueCount > 0)
                  FilterChip(
                    label: Text(
                      l10n?.netDiagFilterShowIssuesOnly(issueCount) ??
                          'Show Issues Only ($issueCount)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: state.showOnlyIssues
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    selected: state.showOnlyIssues,
                    onSelected: (_) => controller.toggleShowOnlyIssues(),
                  ),
              ],
            ),
            const SizedBox(height: LuciSpacing.xs),
            ...displayResults.map(
              (test) => _buildTestResultCard(context, test),
            ),
            const SizedBox(height: LuciSpacing.md),
          ],

          // 4. Limitations & Unverified Domains Disclosure
          if (state.report?.unverifiedAreas.isNotEmpty == true) ...[
            _buildUnverifiedAreasCard(context, state.report!.unverifiedAreas),
            const SizedBox(height: LuciSpacing.lg),
          ],
        ],
      ),
    );

    if (!showAppBar) {
      return content;
    }

    return Scaffold(
      appBar: LuciAppBar(
        title: l10n?.netDiagTitle ?? 'Network Diagnostic',
        showBack: true,
        actions: [
          if (state.report != null && !state.isAnalyzing)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: l10n?.netDiagBtnRerun ?? 'Rerun Diagnostics',
              onPressed: controller.runDiagnostics,
            ),
        ],
      ),
      body: content,
    );
  }

  // ---------------------------------------------------------------------------
  // 1. HERO ASSESSMENT & ACTION CARD
  // ---------------------------------------------------------------------------
  Widget _buildHeroAssessmentCard(
    BuildContext context, {
    required NetworkDiagnosticState state,
    required NetworkDiagnosticController controller,
    required String routerName,
    required String routerIp,
  }) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final report = state.report;
    final isAnalyzing = state.isAnalyzing;

    Color headerBg;
    Color headerBorder;
    Color iconColor;
    IconData statusIcon;
    String statusTitle;
    String statusSummary;

    if (isAnalyzing) {
      headerBg = theme.colorScheme.primaryContainer.withValues(alpha: 0.3);
      headerBorder = theme.colorScheme.primary.withValues(alpha: 0.4);
      iconColor = theme.colorScheme.primary;
      statusIcon = Icons.sync_rounded;
      statusTitle =
          l10n?.netDiagRunningTitle ?? 'Running Network Diagnostics...';
      statusSummary =
          state.currentStepTitle ??
          (l10n?.netDiagRunningSummary ??
              'Gathering configuration and probing network paths...');
    } else if (report == null) {
      headerBg = theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.4,
      );
      headerBorder = theme.colorScheme.outlineVariant.withValues(alpha: 0.3);
      iconColor = theme.colorScheme.primary;
      statusIcon = Icons.troubleshoot_rounded;
      statusTitle = l10n?.netDiagReadyTitle ?? 'Network Diagnostic Ready';
      statusSummary =
          l10n?.netDiagSubtitleReady ??
          'Perform automated, evidence-based root-cause analysis on router uplink, DNS resolution, default routes, IPv4, IPv6, and external reachability.';
    } else {
      switch (report.overallStatus) {
        case DiagnosticStatus.healthy:
          headerBg = LuciStatusColors.successBg(context);
          headerBorder = LuciStatusColors.successBorder(context);
          iconColor = LuciStatusColors.connectedColor(context);
          statusIcon = Icons.check_circle_rounded;
          statusTitle = l10n?.netDiagHealthyTitle ?? 'Network Healthy';
          statusSummary = _getLocalizedSummary(report.overallSummary, l10n);
          break;
        case DiagnosticStatus.degraded:
        case DiagnosticStatus.suspected:
          headerBg = LuciStatusColors.warningBg(context);
          headerBorder = LuciStatusColors.warningBorder(context);
          iconColor = LuciStatusColors.warningColor(context);
          statusIcon = Icons.warning_amber_rounded;
          statusTitle = report.overallStatus == DiagnosticStatus.degraded
              ? (l10n?.netDiagDegradedTitle ?? 'Connectivity Degraded')
              : (l10n?.netDiagSuspectedTitle ?? 'Suspected Issue');
          statusSummary = _getLocalizedSummary(report.overallSummary, l10n);
          break;
        case DiagnosticStatus.failureConfirmed:
          headerBg = LuciStatusColors.errorBg(context);
          headerBorder = LuciStatusColors.errorBorder(context);
          iconColor = theme.colorScheme.error;
          statusIcon = Icons.error_outline_rounded;
          statusTitle =
              l10n?.netDiagIssueDetectedTitle ?? 'Connectivity Issue Detected';
          statusSummary = _getLocalizedSummary(report.overallSummary, l10n);
          break;
        case DiagnosticStatus.inconclusive:
        case DiagnosticStatus.notTested:
        case DiagnosticStatus.unsupported:
        case DiagnosticStatus.notApplicable:
          headerBg = theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          );
          headerBorder = theme.colorScheme.outlineVariant;
          iconColor = theme.colorScheme.outline;
          statusIcon = Icons.help_outline_rounded;
          statusTitle = _getLocalizedStatusLabel(report.overallStatus, l10n);
          statusSummary = _getLocalizedSummary(report.overallSummary, l10n);
          break;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: headerBg,
        borderRadius: LuciCardStyles.standardRadius,
        border: Border.all(color: headerBorder),
      ),
      padding: const EdgeInsets.all(LuciSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(statusIcon, color: iconColor, size: 28),
              ),
              const SizedBox(width: LuciSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n?.netDiagTargetRouter(routerName, routerIp) ??
                          'Target: $routerName ($routerIp)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: LuciSpacing.md),
          Text(
            statusSummary,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              height: 1.4,
            ),
          ),
          if (isAnalyzing) ...[
            const SizedBox(height: LuciSpacing.md),
            LinearProgressIndicator(
              value: state.currentProgress > 0 ? state.currentProgress : null,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
          if (report != null && !isAnalyzing) ...[
            const SizedBox(height: LuciSpacing.sm),
            Text(
              l10n?.netDiagCollectedAt(
                    _formatTime(report.timestamp),
                    report.sessionId,
                  ) ??
                  'Collected at: ${_formatTime(report.timestamp)} • Session ID: ${report.sessionId}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: LuciSpacing.md),
          Row(
            children: [
              if (isAnalyzing)
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: Text(l10n?.netDiagBtnCancel ?? 'Cancel Analysis'),
                    onPressed: controller.cancel,
                  ),
                )
              else
                Expanded(
                  child: FilledButton.icon(
                    icon: Icon(
                      report == null
                          ? Icons.play_arrow_rounded
                          : Icons.refresh_rounded,
                      size: 20,
                    ),
                    label: Text(
                      report == null
                          ? (l10n?.netDiagBtnRun ?? 'Run Diagnostics')
                          : (l10n?.netDiagBtnRerun ?? 'Rerun Diagnostics'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: controller.runDiagnostics,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. ROOT CAUSE FINDING CARDS
  // ---------------------------------------------------------------------------
  Widget _buildFindingCard(BuildContext context, RootCauseFinding finding) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    Color badgeColor;
    IconData findingIcon;
    switch (finding.status) {
      case DiagnosticStatus.healthy:
        badgeColor = LuciStatusColors.connectedColor(context);
        findingIcon = Icons.check_circle_outline_rounded;
        break;
      case DiagnosticStatus.degraded:
      case DiagnosticStatus.suspected:
        badgeColor = LuciStatusColors.warningColor(context);
        findingIcon = Icons.warning_amber_rounded;
        break;
      case DiagnosticStatus.failureConfirmed:
        badgeColor = theme.colorScheme.error;
        findingIcon = Icons.error_outline_rounded;
        break;
      default:
        badgeColor = theme.colorScheme.outline;
        findingIcon = Icons.info_outline_rounded;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: LuciSpacing.sm),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: LuciCardStyles.standardRadius,
        side: BorderSide(color: badgeColor.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(LuciSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(findingIcon, color: badgeColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _getLocalizedFindingTitle(finding, l10n),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: badgeColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    _getLocalizedConfidenceLabel(finding.confidence, l10n),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: badgeColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _getLocalizedFindingDesc(finding, l10n),
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.4,
                color: theme.colorScheme.onSurface,
              ),
            ),
            if (finding.supportingEvidence.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                l10n?.netDiagSupportingEvidence ?? 'Supporting Observations:',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              ...finding.supportingEvidence.map(
                (ev) => Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• ', style: TextStyle(color: badgeColor)),
                      Expanded(
                        child: Text(
                          _getLocalizedEvidence(ev, l10n),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (finding.contradictoryEvidence.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                l10n?.netDiagConflictingEvidence ??
                    'Conflicting / Mitigating Observations:',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: LuciStatusColors.warningColor(context),
                ),
              ),
              const SizedBox(height: 4),
              ...finding.contradictoryEvidence.map(
                (ev) => Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('⚠ ', style: TextStyle(fontSize: 11)),
                      Expanded(
                        child: Text(
                          ev,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (finding.recommendedSteps.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.arrow_circle_right_outlined,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          l10n?.netDiagRecommendedActions ??
                              'Recommended Next Steps:',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...finding.recommendedSteps.asMap().entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          '${e.key + 1}. ${e.value}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. TEST RESULT ITEM CARDS
  // ---------------------------------------------------------------------------
  Widget _buildTestResultCard(BuildContext context, DiagnosticTestResult test) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    Color statusColor;
    IconData statusIcon;

    switch (test.status) {
      case DiagnosticStatus.healthy:
        statusColor = LuciStatusColors.connectedColor(context);
        statusIcon = Icons.check_circle_rounded;
        break;
      case DiagnosticStatus.degraded:
      case DiagnosticStatus.suspected:
        statusColor = LuciStatusColors.warningColor(context);
        statusIcon = Icons.warning_amber_rounded;
        break;
      case DiagnosticStatus.failureConfirmed:
        statusColor = theme.colorScheme.error;
        statusIcon = Icons.cancel_rounded;
        break;
      case DiagnosticStatus.unsupported:
        statusColor = theme.colorScheme.tertiary;
        statusIcon = Icons.block_flipped;
        break;
      case DiagnosticStatus.notApplicable:
        statusColor = theme.colorScheme.outline;
        statusIcon = Icons.remove_circle_outline_rounded;
        break;
      case DiagnosticStatus.inconclusive:
      case DiagnosticStatus.notTested:
        statusColor = theme.colorScheme.outline;
        statusIcon = Icons.help_outline_rounded;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: LuciSpacing.xs),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: LuciCardStyles.standardRadius,
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          leading: Icon(statusIcon, color: statusColor, size: 22),
          title: Text(
            _getLocalizedTestTitle(test, l10n),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          subtitle: Text(
            _getLocalizedTestExplanation(test, l10n),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              _getLocalizedStatusLabel(test.status, l10n),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
          ),
          children: [
            const Divider(),
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n?.netDiagWhyItMatters ?? 'Why This Matters:',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _getLocalizedTestWhyItMatters(test, l10n),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (test.recommendedStep != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n?.netDiagSuggestedAction ?? 'Suggested Action:',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      test.recommendedStep!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (test.evidence.facts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n?.netDiagObservedFacts ?? 'Observed Facts:',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    ...test.evidence.facts.map(
                      (f) => Text(
                        '• $f',
                        style: LuciTypography.monoStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  if (test.duration != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      l10n?.netDiagExecutionDuration(
                            test.duration!.inMilliseconds,
                          ) ??
                          'Execution Duration: ${test.duration!.inMilliseconds} ms',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. LIMITATIONS & UNVERIFIED DOMAINS CARD
  // ---------------------------------------------------------------------------
  Widget _buildUnverifiedAreasCard(
    BuildContext context,
    List<String> unverified,
  ) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(LuciSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: LuciCardStyles.standardRadius,
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                l10n?.netDiagSectionScope ??
                    'Diagnostic Scope & Unverified Domains',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n?.netDiagUnverifiedExplanation ??
                'In accordance with strict diagnostic accuracy, tests are executed from the router itself. The following factors cannot be evaluated without on-device client probes:',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
          ...unverified.map(
            (u) => Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                '• $u',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  static String _getLocalizedStatusLabel(
    DiagnosticStatus status,
    AppLocalizations? l10n,
  ) {
    if (l10n == null) return status.label;
    switch (status) {
      case DiagnosticStatus.healthy:
        return l10n.netDiagStatusHealthy;
      case DiagnosticStatus.degraded:
        return l10n.netDiagStatusDegraded;
      case DiagnosticStatus.suspected:
        return l10n.netDiagStatusSuspected;
      case DiagnosticStatus.failureConfirmed:
        return l10n.netDiagStatusFailureConfirmed;
      case DiagnosticStatus.inconclusive:
        return l10n.netDiagStatusInconclusive;
      case DiagnosticStatus.notTested:
        return l10n.netDiagStatusNotTested;
      case DiagnosticStatus.unsupported:
        return l10n.netDiagStatusUnsupported;
      case DiagnosticStatus.notApplicable:
        return l10n.netDiagStatusNotApplicable;
    }
  }

  static String _getLocalizedConfidenceLabel(
    DiagnosticConfidence confidence,
    AppLocalizations? l10n,
  ) {
    if (l10n == null) return confidence.label;
    switch (confidence) {
      case DiagnosticConfidence.high:
        return l10n.netDiagConfidenceHigh;
      case DiagnosticConfidence.moderate:
        return l10n.netDiagConfidenceModerate;
      case DiagnosticConfidence.low:
        return l10n.netDiagConfidenceLow;
      case DiagnosticConfidence.inconclusive:
        return l10n.netDiagStatusInconclusive;
    }
  }

  static String _getLocalizedSummary(String summary, AppLocalizations? l10n) {
    if (summary ==
        'Internet connection is operational. Router reachability and DNS resolution verified.') {
      return l10n?.netDiagSummaryHealthy ?? summary;
    }
    return summary;
  }

  static String _getLocalizedFindingTitle(
    RootCauseFinding finding,
    AppLocalizations? l10n,
  ) {
    switch (finding.id) {
      case 'ipv6_not_configured':
        return l10n?.netDiagFindingIpv4OnlyTitle ?? finding.title;
      case 'router_healthy_client_unverified':
        return l10n?.netDiagFindingRouterReachabilityTitle ?? finding.title;
      default:
        return finding.title;
    }
  }

  static String _getLocalizedFindingDesc(
    RootCauseFinding finding,
    AppLocalizations? l10n,
  ) {
    switch (finding.id) {
      case 'ipv6_not_configured':
        return l10n?.netDiagFindingIpv4OnlyDesc ?? finding.description;
      case 'router_healthy_client_unverified':
        return l10n?.netDiagFindingRouterReachabilityDesc ??
            finding.description;
      default:
        return finding.description;
    }
  }

  static String _getLocalizedEvidence(String evidence, AppLocalizations? l10n) {
    if (evidence ==
        'No global unicast IPv6 address found on active interfaces.') {
      return l10n?.netDiagEvidenceNoIpv6 ?? evidence;
    }
    if (evidence == 'All router-originated connectivity probes passed.') {
      return l10n?.netDiagEvidenceAllProbesPassed ?? evidence;
    }
    if (evidence ==
        'LAN-to-WAN forwarding policy verified in firewall configuration.') {
      return l10n?.netDiagEvidenceLanWanForwardingOk ?? evidence;
    }
    return evidence;
  }

  static String _getLocalizedTestTitle(
    DiagnosticTestResult test,
    AppLocalizations? l10n,
  ) {
    if (l10n == null) return test.title;
    switch (test.id) {
      case 'router_management_api':
        return l10n.netDiagTestMgmtTitle;
      case 'wan_interface_state':
        return l10n.netDiagTestUplinkTitle;
      case 'default_route_verification':
        return l10n.netDiagTestRouteTitle;
      case 'gateway_reachability':
        return l10n.netDiagTestGatewayTitle;
      case 'dns_resolution_checks':
      case 'dns_resolution':
        return l10n.netDiagTestDnsTitle;
      case 'ipv4_external_reachability':
        return l10n.netDiagTestIpv4Title;
      case 'ipv6_external_reachability':
        return l10n.netDiagTestIpv6Title;
      case 'lan_forwarding_nat':
      case 'client_forwarding_policy':
        return l10n.netDiagTestForwardingTitle;
      case 'path_mtu_fragmentation':
      case 'path_mtu_check':
        return l10n.netDiagTestMtuTitle;
      default:
        return test.title;
    }
  }

  static String _getLocalizedTestExplanation(
    DiagnosticTestResult test,
    AppLocalizations? l10n,
  ) {
    if (l10n == null) return test.explanation;

    final exp = test.explanation;
    if (exp.startsWith('Skipped: ')) {
      return l10n.netDiagTestSkipped(exp.substring(9));
    }

    switch (test.id) {
      case 'router_management_api':
        if (test.status == DiagnosticStatus.healthy) {
          return l10n.netDiagTestMgmtDescHealthy;
        } else if (test.status == DiagnosticStatus.failureConfirmed) {
          return l10n.netDiagTestMgmtDescFailed;
        }
        break;

      case 'wan_interface_state':
        final upMatch = RegExp(
          r'^Active uplink "([^"]+)" is up with protocol ([^.]+)\.',
        ).firstMatch(exp);
        if (upMatch != null) {
          return l10n.netDiagTestUplinkDescUp(
            upMatch.group(1)!,
            upMatch.group(2)!,
          );
        }
        if (exp.contains('is down') || exp.contains('disconnected')) {
          return l10n.netDiagTestUplinkDescDown;
        }
        break;

      case 'default_route_verification':
        if (test.status == DiagnosticStatus.healthy) {
          return l10n.netDiagTestRouteDescHealthy;
        } else if (test.status == DiagnosticStatus.failureConfirmed) {
          return l10n.netDiagTestRouteDescFailed;
        }
        break;

      case 'gateway_reachability':
        final gwMatch = RegExp(
          r'^Upstream gateway \(([^)]+)\) is reachable \(RTT: ([^ ]+) ms\)\.',
        ).firstMatch(exp);
        if (gwMatch != null) {
          return l10n.netDiagTestGatewayDescReachable(
            gwMatch.group(1)!,
            gwMatch.group(2)!,
          );
        }
        final noRespMatch = RegExp(
          r'^Upstream gateway \(([^)]+)\) did not respond to ICMP ping',
        ).firstMatch(exp);
        if (noRespMatch != null) {
          return l10n.netDiagTestGatewayDescNoResponse(noRespMatch.group(1)!);
        }
        if (exp.contains('PPPoE point-to-point link')) {
          return l10n.netDiagTestGatewayDescPppoe;
        }
        if (exp.contains('No upstream gateway IP could be verified') ||
            exp.contains('No gateway IP was identified')) {
          return l10n.netDiagTestGatewayDescNoGw;
        }
        break;

      case 'dns_resolution_checks':
      case 'dns_resolution':
        if (test.status == DiagnosticStatus.healthy) {
          return l10n.netDiagTestDnsDescHealthy;
        } else if (test.status == DiagnosticStatus.failureConfirmed) {
          return l10n.netDiagTestDnsDescFailed;
        }
        break;

      case 'ipv4_external_reachability':
        final v4Match = RegExp(
          r'^Direct IPv4 external connectivity verified across all test endpoints \(min RTT: ([^ ]+) ms\)\.',
        ).firstMatch(exp);
        if (v4Match != null) {
          return l10n.netDiagTestIpv4DescHealthy(v4Match.group(1)!);
        }
        if (test.status == DiagnosticStatus.failureConfirmed) {
          return l10n.netDiagTestIpv4DescFailed;
        }
        break;

      case 'ipv6_external_reachability':
        if (exp.contains('IPv4-only network') ||
            exp.contains('IPv6 is not configured')) {
          return l10n.netDiagTestIpv6DescNotConfigured;
        }
        final v6Match = RegExp(r'min RTT: ([^ ]+) ms').firstMatch(exp);
        if (v6Match != null) {
          return l10n.netDiagTestIpv6DescVerified(v6Match.group(1)!);
        }
        if (test.status == DiagnosticStatus.failureConfirmed) {
          return l10n.netDiagTestIpv6DescFailed;
        }
        break;

      case 'lan_forwarding_nat':
      case 'client_forwarding_policy':
        if (test.status == DiagnosticStatus.healthy) {
          return l10n.netDiagTestForwardingDescHealthy;
        } else if (test.status == DiagnosticStatus.failureConfirmed) {
          return l10n.netDiagTestForwardingDescFailed;
        }
        break;

      case 'path_mtu_fragmentation':
      case 'path_mtu_check':
        if (test.status == DiagnosticStatus.healthy) {
          return l10n.netDiagTestMtuDescHealthy;
        } else if (test.status == DiagnosticStatus.failureConfirmed) {
          return l10n.netDiagTestMtuDescFailed;
        }
        break;
    }

    return exp;
  }

  static String _getLocalizedTestWhyItMatters(
    DiagnosticTestResult test,
    AppLocalizations? l10n,
  ) {
    if (l10n == null) return test.whyItMatters;
    switch (test.id) {
      case 'router_management_api':
        return l10n.netDiagTestMgmtWhy;
      case 'wan_interface_state':
        return l10n.netDiagTestUplinkWhy;
      case 'default_route_verification':
        return l10n.netDiagTestRouteWhy;
      case 'gateway_reachability':
        return l10n.netDiagTestGatewayWhy;
      case 'dns_resolution_checks':
      case 'dns_resolution':
        return l10n.netDiagTestDnsWhy;
      case 'ipv4_external_reachability':
        return l10n.netDiagTestIpv4Why;
      case 'ipv6_external_reachability':
        return l10n.netDiagTestIpv6Why;
      case 'lan_forwarding_nat':
      case 'client_forwarding_policy':
        return l10n.netDiagTestForwardingWhy;
      case 'path_mtu_fragmentation':
      case 'path_mtu_check':
        return l10n.netDiagTestMtuWhy;
      default:
        return test.whyItMatters;
    }
  }
}
