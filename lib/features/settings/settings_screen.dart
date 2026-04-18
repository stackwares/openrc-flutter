import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/core/utils/currency_format.dart';
import 'package:revenuecat/core/utils/store_payday_schedule.dart';
import 'package:revenuecat/features/settings/payday_screen.dart';
import 'package:revenuecat/services/commission_settings_store.dart';
import 'package:revenuecat/services/display_currency_store.dart';
import 'package:revenuecat/services/rc_auth_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static String _paydaysSettingsSubtitle() {
    final apple = AppStorePayday.upcoming;
    final google = GooglePlayPayday.upcoming;
    final parts = <String>[];
    if (apple != null) {
      parts.add('App Store ${formatPaydayAbbrev(apple.paymentDate)}');
    }
    if (google != null) {
      parts.add('Play ${formatPaydayAbbrev(google.paymentDate)}');
    }
    if (parts.isEmpty) return 'Fiscal & monthly payout calendar';
    return parts.join(' · ');
  }

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
    final scheme = Theme.of(context).colorScheme;
    final sectionLabelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
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
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: const Text('App Store & Play paydays'),
            subtitle: Text(
              _paydaysSettingsSubtitle(),
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const PaydayScreen(),
                ),
              );
            },
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
