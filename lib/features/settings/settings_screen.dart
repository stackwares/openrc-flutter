import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/core/shell_insets.dart';
import 'package:revenuecat/core/theme/store_brand_icon_colors.dart';
import 'package:revenuecat/core/utils/currency_format.dart';
import 'package:revenuecat/core/utils/store_payday_schedule.dart';
import 'package:revenuecat/features/settings/payday_screen.dart';
import 'package:revenuecat/services/commission_settings_store.dart';
import 'package:revenuecat/services/display_currency_store.dart';
import 'package:revenuecat/services/rc_auth_service.dart';
import 'package:revenuecat/services/utilities_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static void _showCurrencyBottomSheet(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.56;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: maxH),
      builder: (sheetContext) {
        return Consumer(
          builder: (context, ref, _) {
            final selected = ref.watch(displayCurrencyProvider);
            final notifier = ref.read(displayCurrencyProvider.notifier);
            final bottom = MediaQuery.paddingOf(sheetContext).bottom;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Display currency',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: kDisplayCurrencyOptions.map((o) {
                      final isSel = o.code == selected;
                      return ChoiceChip(
                        label: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                o.flagEmoji,
                                style: const TextStyle(
                                  fontSize: 20,
                                  height: 1,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                o.code,
                                style: TextStyle(
                                  fontWeight:
                                      isSel ? FontWeight.w700 : FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        selected: isSel,
                        onSelected: (_) async {
                          await notifier.setCurrency(o.code);
                          if (sheetContext.mounted) {
                            Navigator.of(sheetContext).pop();
                          }
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('Log out?'),
          content: const Text(
            'You will need to sign in again to use the app.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
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
    ref.read(themeModeProvider.notifier).state = mode;
    await ref.read(utilitiesServiceProvider).saveThemeMode(mode);
  }

  static Future<void> _editCommissionPercent(
    BuildContext context,
    WidgetRef ref, {
    required bool isApple,
  }) async {
    final notifier = ref.read(commissionSettingsProvider.notifier);
    final current = ref.read(commissionSettingsProvider);
    final initial = isApple
        ? current.appleCommissionPercent
        : current.googleCommissionPercent;
    final controller = TextEditingController(
      text: initial == initial.roundToDouble()
          ? initial.toStringAsFixed(0)
          : initial.toStringAsFixed(1),
    );
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            isApple ? 'App Store commission' : 'Google Play commission',
          ),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Fee',
              suffixText: '%',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (saved == true && context.mounted) {
        final v = double.tryParse(controller.text.trim().replaceAll(',', '.'));
        if (v == null) return;
        if (isApple) {
          await notifier.setAppleCommissionPercent(v);
        } else {
          await notifier.setGoogleCommissionPercent(v);
        }
      }
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(displayCurrencyProvider);
    final sym = currencySymbolFor(selected);
    final selectedOption = lookupDisplayCurrencyOption(selected);
    final commission = ref.watch(commissionSettingsProvider);
    final me = ref.watch(rcMeProvider);
    final themeMode = ref.watch(themeModeProvider);
    final scheme = Theme.of(context).colorScheme;
    final sectionLabelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        );

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: mainShellFloatingTabBarScrollPadding(context),
        ),
        children: [
          ListTile(
            leading: const Icon(Icons.currency_exchange_outlined),
            title: const Text('Display currency'),
            subtitle: Row(
              children: [
                Text(
                  selectedOption?.flagEmoji ?? '🏳️',
                  style: const TextStyle(fontSize: 22, height: 1.1),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$selected · $sym',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showCurrencyBottomSheet(context),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('APPEARANCE', style: sectionLabelStyle),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('System'),
                  selected: themeMode == ThemeMode.system,
                  onSelected: (_) => _setThemeMode(ref, ThemeMode.system),
                ),
                ChoiceChip(
                  label: const Text('Bright'),
                  selected: themeMode == ThemeMode.light,
                  onSelected: (_) => _setThemeMode(ref, ThemeMode.light),
                ),
                ChoiceChip(
                  label: const Text('Dark'),
                  selected: themeMode == ThemeMode.dark,
                  onSelected: (_) => _setThemeMode(ref, ThemeMode.dark),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: _PaydaysSettingsCard(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const PaydayScreen(),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('STORE COMMISSION', style: sectionLabelStyle),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.percent_outlined),
            title: const Text('Adjust revenue for store fees'),
            subtitle: Text(
              commission.adjustmentEnabled
                  ? 'Net = gross × (1 − fee) for App Store & Play Store'
                  : 'Show gross amounts from RevenueCat',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            value: commission.adjustmentEnabled,
            onChanged: (v) => ref
                .read(commissionSettingsProvider.notifier)
                .setAdjustmentEnabled(v),
          ),
          if (commission.adjustmentEnabled) ...[
            ListTile(
              leading: const Icon(Icons.apple),
              title: const Text('App Store'),
              subtitle: Text(
                '${commission.appleCommissionPercent.toStringAsFixed(1)}%',
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editCommissionPercent(context, ref, isApple: true),
            ),
            ListTile(
              leading: const Icon(Icons.android),
              title: const Text('Google Play'),
              subtitle: Text(
                '${commission.googleCommissionPercent.toStringAsFixed(1)}%',
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editCommissionPercent(context, ref, isApple: false),
            ),
          ],
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('ACCOUNT', style: sectionLabelStyle),
          ),
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: const Text('Email'),
            subtitle: Text(
              me?.email ?? '—',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('ID'),
            subtitle: Text(
              me?.distinctId ?? '—',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          ListTile(
            leading: Icon(Icons.logout, color: scheme.error),
            title: Text(
              'Log out',
              style: TextStyle(color: scheme.error),
            ),
            onTap: () => _confirmSignOut(context, ref),
          ),
        ],
      ),
    );
  }
}

class _PaydaysSettingsCard extends StatelessWidget {
  const _PaydaysSettingsCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final now = DateTime.now();
    final apple = AppStorePayday.upcoming;
    final google = GooglePlayPayday.upcoming;

    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.calendar_month_rounded,
                    color: scheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Payout calendar',
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'App Store fiscal deposits and estimated Play payout timing',
                style: tt.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _PaydayStorePreview(
                      icon: Icons.apple,
                      iconColor: StoreBrandIconColors.appleBlue,
                      label: 'App Store',
                      dateLine: apple != null
                          ? formatPaydayAbbrev(apple.paymentDate)
                          : '—',
                      daysToGo: apple != null
                          ? paydayDaysToGoLabel(apple.paymentDate, now)
                          : null,
                      hint: apple != null ? 'Next deposit' : 'Open for schedule',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PaydayStorePreview(
                      icon: Icons.android,
                      iconColor: StoreBrandIconColors.androidGreen,
                      label: 'Google Play',
                      dateLine: google != null
                          ? formatPaydayAbbrev(google.paymentDate)
                          : '—',
                      daysToGo: google != null
                          ? paydayDaysToGoLabel(google.paymentDate, now)
                          : null,
                      hint: google != null ? 'Est. initiation' : 'Open for schedule',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaydayStorePreview extends StatelessWidget {
  const _PaydayStorePreview({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.dateLine,
    this.daysToGo,
    required this.hint,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String dateLine;
  final String? daysToGo;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: tt.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            dateLine,
            style: tt.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          if (daysToGo != null) ...[
            const SizedBox(height: 4),
            Text(
              daysToGo!,
              style: tt.labelLarge?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 2),
          Text(
            hint,
            style: tt.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
