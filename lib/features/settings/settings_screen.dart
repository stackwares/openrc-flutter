import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/core/constants/app_constants.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/core/utils/currency_format.dart';
import 'package:openrc/features/notifications/widgets/notifications_settings_row.dart';
import 'package:openrc/features/onboarding/onboarding_screen.dart';
import 'package:openrc/features/onboarding/onboarding_steps.dart';
import 'package:openrc/features/settings/widgets/accent_scheme_sheet.dart';
import 'package:openrc/features/settings/widgets/agent_settings_section.dart';
import 'package:openrc/features/settings/widgets/account_header.dart';
import 'package:openrc/features/settings/widgets/appearance_pickers.dart';
import 'package:openrc/features/settings/widgets/currency_sheet.dart';
import 'package:openrc/features/settings/widgets/language_sheet.dart';
import 'package:openrc/features/settings/widgets/settings_rows.dart';
import 'package:openrc/features/settings/widgets/store_fee_sheet.dart';
import 'package:openrc/services/commission_settings_store.dart';
import 'package:openrc/services/onboarding_prefs_store.dart';
import 'package:openrc/services/display_currency_store.dart';
import 'package:openrc/services/push/push_notifications.dart';
import 'package:openrc/services/rc_auth_service.dart';
import 'package:openrc/services/telemetry.dart';
import 'package:openrc/services/utilities_service.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/adaptive_modal.dart';
import 'package:openrc/widgets/animated_reveal.dart';
import 'package:openrc/widgets/app_card.dart';
import 'package:openrc/widgets/app_logo.dart';
import 'package:openrc/widgets/dialog_navigator.dart';
import 'package:openrc/widgets/grouped_list.dart';
import 'package:openrc/widgets/shell_header.dart';

/// Example amount for the display-currency preview.
const double _kCurrencyExample = 1234.56;

const double _dialogMaxWidth = 600;
const double _dialogMaxHeight = 820;

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.inDialog = false});

  static const routeName = '/settings';

  /// Shown by [open] in a dialog rather than on its own route.
  final bool inDialog;

  /// Phones push Settings as a screen; larger windows show it in a dialog
  /// over the app.
  static void open(BuildContext context) {
    if (context.windowSize == WindowSize.compact) {
      Navigator.of(context).pushNamed(routeName);
      return;
    }
    showDialog<void>(
      context: context,
      // Named like the route, so telemetry still reports a Settings view.
      routeSettings: const RouteSettings(name: routeName),
      builder: (context) {
        final size = MediaQuery.sizeOf(context);
        return Dialog(
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: math.min(_dialogMaxWidth, size.width - 80),
            height: math.min(_dialogMaxHeight, size.height * 0.9),
            // The window's safe area (e.g. the macOS title bar) is the
            // app's, not the dialog's.
            child: MediaQuery.removePadding(
              context: context,
              removeLeft: true,
              removeTop: true,
              removeRight: true,
              removeBottom: true,
              // Everything Settings opens slides in inside the dialog.
              child: const DialogNavigator(
                child: SettingsScreen(inDialog: true),
              ),
            ),
          ),
        );
      },
    );
  }

  static Future<void> _confirmSignOut(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final email = ref.read(rcMeProvider)?.email?.trim();
    final confirmed = await showAdaptiveForm<bool>(
      context: context,
      title: 'settings.logOutTitle'.tr(),
      content: (_) => Text(
        email == null || email.isEmpty
            ? 'settings.logOutMessage'.tr()
            : 'settings.logOutAs'.tr(namedArgs: {'email': email}),
      ),
      actions: (dialogContext) => [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text('settings.cancel'.tr()),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: dialogContext.appColors.negative,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text('settings.logOut'.tr()),
        ),
      ],
    );
    if (confirmed == true && context.mounted) {
      await ref.read(rcAuthServiceProvider).signOut();
    }
  }

  static Future<void> _setThemeMode(WidgetRef ref, ThemeMode mode) async {
    UtilitiesService.hapticSelection();
    ref.read(themeModeProvider.notifier).state = mode;
    await ref.read(utilitiesServiceProvider).saveThemeMode(mode);
  }

  static Future<void> _editFee(
    BuildContext context,
    WidgetRef ref, {
    required bool isApple,
  }) async {
    final current = ref.read(commissionSettingsProvider);
    final picked = await showStoreFeeSheet(
      context,
      store: isApple
          ? 'storeNames.appStore'.tr()
          : 'storeNames.googlePlay'.tr(),
      company: isApple
          ? 'storeNames.appleCompany'.tr()
          : 'storeNames.googleCompany'.tr(),
      icon: isApple ? Icons.apple : Icons.android,
      current: isApple
          ? current.appleCommissionPercent
          : current.googleCommissionPercent,
    );
    if (picked == null) return;
    final notifier = ref.read(commissionSettingsProvider.notifier);
    if (isApple) {
      await notifier.setAppleCommissionPercent(picked);
    } else {
      await notifier.setGoogleCommissionPercent(picked);
    }
  }

  static Future<void> _copyDistinctId(BuildContext context, String id) async {
    UtilitiesService.hapticLight();
    await UtilitiesService().copyToClipboard(id);
    if (context.mounted) context.showSnackBar('settings.distinctIdCopied'.tr());
  }

  static Future<void> _setTelemetry(WidgetRef ref, bool enabled) async {
    UtilitiesService.hapticSelection();
    ref.read(telemetryEnabledProvider.notifier).state = enabled;
    await Telemetry.setEnabled(enabled);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(displayCurrencyProvider);
    final currencyOption = lookupDisplayCurrencyOption(currency);
    final commission = ref.watch(commissionSettingsProvider);
    final me = ref.watch(rcMeProvider);
    final themeMode = ref.watch(themeModeProvider);
    final colorScheme = ref.watch(colorSchemeProvider);
    final telemetryEnabled = ref.watch(telemetryEnabledProvider);
    // A browser that can't get pushes still shows the row, to say why.
    final pushAvailable =
        ref.watch(pushMessagingProvider) != null ||
        (PushNotifications.isAvailable && !PushNotifications.isSupported);
    final language = ref.watch(appLanguageProvider);
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    final distinctId = me?.distinctId?.trim();
    final currencyName = currencyOption?.label ?? currency;
    final currencyExample = currency == 'USD'
        ? formatExactUsd(_kCurrencyExample)
        : formatExactForeign(_kCurrencyExample, currency);
    final currencySubtitle = 'settings.currencySubtitle'.tr(
      namedArgs: {'name': currencyName, 'example': currencyExample},
    );

    void toggleFees() {
      UtilitiesService.hapticSelection();
      ref
          .read(commissionSettingsProvider.notifier)
          .setAdjustmentEnabled(!commission.adjustmentEnabled);
    }

    // The dialog is already a readable width; the window size says nothing
    // about it.
    final inset = inDialog
        ? 0.0
        : AppBreakpoints.centeringInset(
            MediaQuery.sizeOf(context).width,
            maxWidth: 640,
          );

    return Scaffold(
      appBar: AppBar(
        title: Text('settings.title'.tr()),
        automaticallyImplyLeading: !inDialog,
        actions: [
          if (inDialog)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                icon: const Icon(Icons.close_rounded),
                // The dialog is on the app's navigator, not the one inside it.
                onPressed: () =>
                    Navigator.of(context, rootNavigator: true).pop(),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16 + inset,
          4,
          16 + inset,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          const SettingsAccountHeader().appCardEntrance(),

          SettingsGroupLabel('settings.appearance'.tr()),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  child: ThemeModePicker(
                    mode: themeMode,
                    scheme: colorScheme,
                    onChanged: (m) => _setThemeMode(ref, m),
                  ),
                ),
                const Divider(),
                InkWell(
                  onTap: () => showAccentSchemeSheet(context),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
                    child: Row(
                      children: [
                        Text(
                          'settings.accentColor'.tr(),
                          style: tt.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            colorScheme.data.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: tt.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
                AccentSwatchRow(
                  selected: colorScheme,
                  onSelected: (s) {
                    UtilitiesService.hapticSelection();
                    setAccentScheme(ref, s);
                  },
                  onMore: () => showAccentSchemeSheet(context),
                ),
                const SizedBox(height: 12),
                const Divider(),
                InkWell(
                  onTap: () => showLanguageSheet(context),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                    child: Row(
                      children: [
                        Text(
                          'settings.language'.tr(),
                          style: tt.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            languageLabel(language),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: tt.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ).appCardEntrance(delay: const Duration(milliseconds: 40)),

          SettingsGroupLabel('settings.revenue'.tr()),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsRow(
                  leading: SettingsIconTile(
                    child: Text(
                      currencyOption?.flagEmoji ?? '\u{1F4B1}',
                      style: const TextStyle(fontSize: 18, height: 1),
                    ),
                  ),
                  title: 'settings.displayCurrency'.tr(),
                  subtitle: currencySubtitle,
                  trailing: Text(currency),
                  onTap: () => showDisplayCurrencySheet(context),
                ),
                const Divider(indent: kSettingsDividerIndent),
                SettingsRow(
                  icon: Icons.percent_rounded,
                  title: 'settings.subtractFees'.tr(),
                  subtitle: commission.adjustmentEnabled
                      ? 'settings.feesAfter'.tr()
                      : 'settings.feesBefore'.tr(),
                  trailing: Switch(
                    value: commission.adjustmentEnabled,
                    onChanged: (_) => toggleFees(),
                  ),
                  showChevron: false,
                  onTap: toggleFees,
                ),
                AnimatedReveal(
                  visible: commission.adjustmentEnabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Divider(indent: kSettingsDividerIndent),
                      SettingsRow(
                        icon: Icons.apple,
                        title: 'settings.appStoreFee'.tr(),
                        subtitle: storeFeeExample(
                          commission.appleCommissionPercent,
                        ),
                        trailing: Text(
                          formatFeePercent(commission.appleCommissionPercent),
                        ),
                        onTap: () => _editFee(context, ref, isApple: true),
                      ),
                      const Divider(indent: kSettingsDividerIndent),
                      SettingsRow(
                        icon: Icons.android,
                        title: 'settings.googlePlayFee'.tr(),
                        subtitle: storeFeeExample(
                          commission.googleCommissionPercent,
                        ),
                        trailing: Text(
                          formatFeePercent(commission.googleCommissionPercent),
                        ),
                        onTap: () => _editFee(context, ref, isApple: false),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).appCardEntrance(delay: const Duration(milliseconds: 80)),

          const AgentSettingsSection().appCardEntrance(
            delay: const Duration(milliseconds: 85),
          ),

          // Only builds with Firebase settings, on platforms that get pushes.
          if (pushAvailable) ...[
            SettingsGroupLabel('notifications.title'.tr()),
            const NotificationsSettingsRow().appCardEntrance(
              delay: const Duration(milliseconds: 90),
            ),
          ],

          // Apple Ask consent always has a Privacy row; usage sharing only
          // appears in builds that can send anything.
          if (Telemetry.isAvailable || isAppleAiConsentPlatform) ...[
            SettingsGroupLabel('settings.privacy'.tr()),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  if (isAppleAiConsentPlatform)
                    SettingsRow(
                      icon: Icons.auto_awesome_outlined,
                      title: 'settings.aiConsent'.tr(),
                      subtitle: 'settings.aiConsentHint'.tr(),
                      trailing: Switch(
                        value: ref.watch(onboardingPrefsProvider).aiConsentGranted,
                        onChanged: (v) {
                          UtilitiesService.hapticSelection();
                          ref
                              .read(onboardingPrefsProvider.notifier)
                              .setAiConsentGranted(v);
                        },
                      ),
                      showChevron: false,
                      onTap: () {
                        UtilitiesService.hapticSelection();
                        final next = !ref
                            .read(onboardingPrefsProvider)
                            .aiConsentGranted;
                        ref
                            .read(onboardingPrefsProvider.notifier)
                            .setAiConsentGranted(next);
                      },
                    ),
                  if (isAppleAiConsentPlatform && Telemetry.isAvailable)
                    const Divider(indent: kSettingsDividerIndent),
                  if (Telemetry.isAvailable)
                    SettingsRow(
                      icon: Icons.insights_rounded,
                      title: 'settings.shareUsage'.tr(),
                      subtitle: 'settings.shareUsageHint'.tr(),
                      trailing: Switch(
                        value: telemetryEnabled,
                        onChanged: (v) => _setTelemetry(ref, v),
                      ),
                      showChevron: false,
                      onTap: () => _setTelemetry(ref, !telemetryEnabled),
                    ),
                ],
              ),
            ).appCardEntrance(delay: const Duration(milliseconds: 100)),
          ],

          SettingsGroupLabel('settings.account'.tr()),
          GroupedCard(
            margin: EdgeInsets.zero,
            dividerIndent: kSettingsDividerIndent,
            children: [
              SettingsRow(
                icon: Icons.fingerprint_rounded,
                title: 'settings.distinctId'.tr(),
                subtitle: distinctId == null || distinctId.isEmpty
                    ? 'settings.notAvailable'.tr()
                    : distinctId,
                trailing: distinctId == null || distinctId.isEmpty
                    ? null
                    : Icon(
                        Icons.copy_rounded,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                showChevron: false,
                semanticsLabel: 'settings.copyDistinctId'.tr(),
                onTap: distinctId == null || distinctId.isEmpty
                    ? null
                    : () => _copyDistinctId(context, distinctId),
              ),
              SettingsRow(
                icon: Icons.logout_rounded,
                title: 'settings.logOut'.tr(),
                destructive: true,
                showChevron: false,
                onTap: () => _confirmSignOut(context, ref),
              ),
            ],
          ).appCardEntrance(delay: const Duration(milliseconds: 120)),

          SettingsGroupLabel('settings.help'.tr()),
          Card(
            clipBehavior: Clip.antiAlias,
            child: SettingsRow(
              icon: Icons.auto_stories_outlined,
              title: 'settings.watchIntroduction'.tr(),
              onTap: () => OnboardingScreen.openPreview(context),
            ),
          ).appCardEntrance(delay: const Duration(milliseconds: 140)),

          const SizedBox(height: 28),
          const _AboutFooter(),
        ],
      ),
    );
  }
}

/// App name and version, for bug reports.
class _AboutFooter extends StatelessWidget {
  const _AboutFooter();

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        return Column(
          children: [
            const AppLogo(size: 40),
            const SizedBox(height: 8),
            Text(
              AppConstants.appName,
              style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              info == null
                  ? ' '
                  : 'settings.version'.tr(
                      namedArgs: {
                        'version': info.version,
                        'build': info.buildNumber,
                      },
                    ),
              style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        );
      },
    );
  }
}

/// App bar button that opens [SettingsScreen] on its own route. Larger
/// windows open it from the rail or the sidebar's account instead.
class SettingsAppBarAction extends StatelessWidget {
  const SettingsAppBarAction({super.key});

  @override
  Widget build(BuildContext context) {
    if (context.windowSize != WindowSize.compact) {
      return const SizedBox.shrink();
    }
    return HeaderIconButton(
      tooltip: 'settings.title'.tr(),
      icon: Icons.settings_outlined,
      onPressed: () => SettingsScreen.open(context),
    );
  }
}
