// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

/// Represents a supported language option within the application.
class AppLanguageOption {
  final Locale? locale;
  final String label;
  final String nativeLabel;
  final String code;

  const AppLanguageOption({
    required this.locale,
    required this.label,
    required this.nativeLabel,
    required this.code,
  });
}

/// All languages supported by YALA.
const kAppLanguages = <AppLanguageOption>[
  AppLanguageOption(
    locale: null,
    label: 'System Default',
    nativeLabel: 'Follow system settings',
    code: 'AUTO',
  ),
  AppLanguageOption(
    locale: Locale('en'),
    label: 'English',
    nativeLabel: 'English',
    code: 'EN',
  ),
  AppLanguageOption(
    locale: Locale('ru'),
    label: 'Russian',
    nativeLabel: 'Русский',
    code: 'RU',
  ),
  AppLanguageOption(
    locale: Locale('es'),
    label: 'Spanish',
    nativeLabel: 'Español',
    code: 'ES',
  ),
  AppLanguageOption(
    locale: Locale('de'),
    label: 'German',
    nativeLabel: 'Deutsch',
    code: 'DE',
  ),
  AppLanguageOption(
    locale: Locale('fr'),
    label: 'French',
    nativeLabel: 'Français',
    code: 'FR',
  ),
  AppLanguageOption(
    locale: Locale('id'),
    label: 'Indonesian',
    nativeLabel: 'Bahasa Indonesia',
    code: 'ID',
  ),
  AppLanguageOption(
    locale: Locale('pt', 'BR'),
    label: 'Portuguese (Brazil)',
    nativeLabel: 'Português (Brasil)',
    code: 'PT-BR',
  ),
  AppLanguageOption(
    locale: Locale('pt'),
    label: 'Portuguese (Portugal)',
    nativeLabel: 'Português (Portugal)',
    code: 'PT',
  ),
  AppLanguageOption(
    locale: Locale('zh'),
    label: 'Chinese (Simplified)',
    nativeLabel: '简体中文',
    code: 'ZH',
  ),
  AppLanguageOption(
    locale: Locale('uk'),
    label: 'Ukrainian',
    nativeLabel: 'Українська',
    code: 'UK',
  ),
  AppLanguageOption(
    locale: Locale('it'),
    label: 'Italian',
    nativeLabel: 'Italiano',
    code: 'IT',
  ),
  AppLanguageOption(
    locale: Locale('ja'),
    label: 'Japanese',
    nativeLabel: '日本語',
    code: 'JA',
  ),
];

/// A compact Material 3 badge indicating that multi-language localization is currently in beta.
class LocalizationBetaBadge extends StatelessWidget {
  const LocalizationBetaBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fontSize = compact ? 8.5 : 10.0;
    final hPadding = compact ? 4.5 : 6.0;
    final vPadding = compact ? 1.0 : 2.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: vPadding),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(compact ? 4 : 6),
        border: Border.all(
          color: colorScheme.tertiary.withValues(alpha: 0.35),
          width: 0.75,
        ),
      ),
      child: Text(
        'BETA',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: colorScheme.onTertiaryContainer,
          height: 1.1,
        ),
      ),
    );
  }
}

/// Displays the Material 3 language picker dialog.
Future<void> showLanguagePickerDialog(
  BuildContext context, {
  required AppState appState,
}) async {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final currentLocale = appState.locale;
  final l10n = AppLocalizations.of(context);

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      actionsOverflowButtonSpacing: 8,
      actionsOverflowDirection: VerticalDirection.down,
      title: Row(
        children: [
          Icon(Icons.translate_rounded, color: colorScheme.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    l10n?.languageTitle ?? 'Select Language',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const LocalizationBetaBadge(),
              ],
            ),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: kAppLanguages.length,
          separatorBuilder: (context, index) => Divider(
            height: 1,
            thickness: 0.6,
            color: colorScheme.outlineVariant.withValues(alpha: 0.25),
          ),
          itemBuilder: (context, index) {
            final opt = kAppLanguages[index];
            final isSelected =
                (opt.locale == null && currentLocale == null) ||
                (opt.locale != null &&
                    currentLocale != null &&
                    opt.locale!.languageCode == currentLocale.languageCode &&
                    (opt.locale!.countryCode == null ||
                        opt.locale!.countryCode == currentLocale.countryCode));

            return ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 2,
              ),
              title: Text(
                opt.locale == null
                    ? (l10n?.languageSystemDefault ?? 'System Default')
                    : opt.nativeLabel,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 14,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurface,
                ),
              ),
              subtitle: Text(
                opt.locale == null ? opt.nativeLabel : opt.label,
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected
                      ? colorScheme.primary.withValues(alpha: 0.8)
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: isSelected
                  ? Icon(
                      Icons.check_circle_rounded,
                      color: colorScheme.primary,
                      size: 20,
                    )
                  : null,
              onTap: () async {
                Navigator.of(context).pop();
                await appState.setLocale(opt.locale);
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n?.actionCancel ?? 'Cancel'),
        ),
      ],
    ),
  );
}

/// A compact, self-explanatory language selector badge designed for the login screen.
///
/// Features:
/// - Universal Material 3 `Icons.translate_rounded` icon.
/// - Active language code display (`EN`, `RU`, `ID`, etc.).
/// - Accessible semantics and tooltip.
/// - Subtly elevated pill appearance that harmonizes with YALA's matte UI.
class LanguageSelectorBadge extends ConsumerWidget {
  const LanguageSelectorBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    // Watch current locale preference
    final currentPrefLocale = ref.watch(
      appStateProvider.select((s) => s.locale),
    );

    // Resolved locale currently active on the device/app
    final resolvedLocale = currentPrefLocale ?? Localizations.localeOf(context);

    final displayCode =
        (resolvedLocale.languageCode == 'pt' &&
            resolvedLocale.countryCode == 'BR')
        ? 'BR'
        : resolvedLocale.languageCode.toUpperCase();

    final tooltipMsg = l10n?.languageTitle ?? 'Select Language';

    return Semantics(
      button: true,
      label: '$tooltipMsg: $displayCode',
      child: Tooltip(
        message: tooltipMsg,
        child: Material(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(18),
          elevation: 0,
          child: InkWell(
            key: const ValueKey('login_language_selector_button'),
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              HapticFeedback.lightImpact();
              showLanguagePickerDialog(
                context,
                appState: ref.read(appStateProvider),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.translate_rounded,
                    size: 15,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    displayCode,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                      letterSpacing: 0.6,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const LocalizationBetaBadge(compact: true),
                  const SizedBox(width: 1),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
