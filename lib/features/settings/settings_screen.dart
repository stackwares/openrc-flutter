import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:revenuecat/core/animations/app_motion.dart';
import 'package:revenuecat/core/constants/app_constants.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/core/utils/currency_format.dart';
import 'package:revenuecat/features/settings/widgets/accent_scheme_sheet.dart';
import 'package:revenuecat/features/settings/widgets/account_header.dart';
import 'package:revenuecat/features/settings/widgets/appearance_pickers.dart';
import 'package:revenuecat/features/settings/widgets/currency_sheet.dart';
import 'package:revenuecat/features/settings/widgets/settings_rows.dart';
import 'package:revenuecat/features/settings/widgets/store_fee_sheet.dart';
import 'package:revenuecat/services/commission_settings_store.dart';
import 'package:revenuecat/services/display_currency_store.dart';
import 'package:revenuecat/services/rc_auth_service.dart';
import 'package:revenuecat/services/utilities_service.dart';
import 'package:revenuecat/widgets/animated_reveal.dart';
import 'package:revenuecat/widgets/app_card.dart';
import 'package:revenuecat/widgets/grouped_list.dart';
import 'package:revenuecat/widgets/shell_header.dart';

/// Example amount for the display-currency preview.
const double _kCurrencyExample = 1234.56;

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const routeName = '/settings';

  static void open(BuildContext context) {
    Navigator.of(context).pushNamed(routeName);
  }

  static Future<void> _confirmSignOut(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final email = ref.read(rcMeProvider)?.email?.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = dialogContext.appColors;
        return AlertDialog(
          title: const Text('Log out?'),
          content: Text(
            email == null || email.isEmpty
                ? 'You’ll need to sign in again to see your revenue.'
                : 'You’ll need to sign in again as $email to see your '
                      'revenue.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.negative,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Log out'),
            ),
          ],
        );
      },
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
      store: isApple ? 'App Store' : 'Google Play',
      company: isApple ? 'Apple' : 'Google',
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
    if (context.mounted) context.showSnackBar('Distinct ID copied');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(displayCurrencyProvider);
    final currencyOption = lookupDisplayCurrencyOption(currency);
    final commission = ref.watch(commissionSettingsProvider);
    final me = ref.watch(rcMeProvider);
    final themeMode = ref.watch(themeModeProvider);
    final colorScheme = ref.watch(colorSchemeProvider);
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    final distinctId = me?.distinctId?.trim();
    final currencyName = currencyOption == null
        ? currency
        : '${currencyOption.label[0].toUpperCase()}'
              '${currencyOption.label.substring(1)}';
    final currencyExample = currency == 'USD'
        ? formatExactUsd(_kCurrencyExample)
        : formatExactForeign(_kCurrencyExample, currency);

    void toggleFees() {
      UtilitiesService.hapticSelection();
      ref
          .read(commissionSettingsProvider.notifier)
          .setAdjustmentEnabled(!commission.adjustmentEnabled);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          const SettingsAccountHeader().appCardEntrance(),

          const SettingsGroupLabel('Appearance'),
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
                          'Accent color',
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
                const SizedBox(height: 16),
              ],
            ),
          ).appCardEntrance(delay: const Duration(milliseconds: 40)),

          const SettingsGroupLabel('Revenue'),
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
                  title: 'Display currency',
                  subtitle: '$currencyName · shown as $currencyExample',
                  trailing: Text(currency),
                  onTap: () => showDisplayCurrencySheet(context),
                ),
                const Divider(indent: kSettingsDividerIndent),
                SettingsRow(
                  icon: Icons.percent_rounded,
                  title: 'Subtract store fees',
                  subtitle: commission.adjustmentEnabled
                      ? 'Revenue is shown after your store fees'
                      : 'Revenue is shown before App Store and Google Play '
                            'fees',
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
                        title: 'App Store fee',
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
                        title: 'Google Play fee',
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

          const SettingsGroupLabel('Account'),
          GroupedCard(
            margin: EdgeInsets.zero,
            dividerIndent: kSettingsDividerIndent,
            children: [
              SettingsRow(
                icon: Icons.fingerprint_rounded,
                title: 'Distinct ID',
                subtitle: distinctId == null || distinctId.isEmpty
                    ? 'Not available'
                    : distinctId,
                trailing: distinctId == null || distinctId.isEmpty
                    ? null
                    : Icon(
                        Icons.copy_rounded,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                showChevron: false,
                semanticsLabel: 'Copy distinct ID',
                onTap: distinctId == null || distinctId.isEmpty
                    ? null
                    : () => _copyDistinctId(context, distinctId),
              ),
              SettingsRow(
                icon: Icons.logout_rounded,
                title: 'Log out',
                destructive: true,
                showChevron: false,
                onTap: () => _confirmSignOut(context, ref),
              ),
            ],
          ).appCardEntrance(delay: const Duration(milliseconds: 120)),

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
            Icon(
              Icons.account_balance_wallet_rounded,
              size: 22,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 6),
            Text(
              AppConstants.appName,
              style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              info == null
                  ? ' '
                  : 'Version ${info.version} (${info.buildNumber})',
              style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        );
      },
    );
  }
}

/// App bar button that opens [SettingsScreen] on its own route.
class SettingsAppBarAction extends StatelessWidget {
  const SettingsAppBarAction({super.key});

  @override
  Widget build(BuildContext context) {
    return HeaderIconButton(
      tooltip: 'Settings',
      icon: Icons.settings_outlined,
      onPressed: () => SettingsScreen.open(context),
    );
  }
}
