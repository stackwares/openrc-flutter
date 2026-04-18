import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/core/animations/app_motion.dart';
import 'package:revenuecat/core/shell_insets.dart';
import 'package:revenuecat/core/utils/currency_format.dart';
import 'package:revenuecat/features/settings/webhooks_screen.dart';
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
            final scheme = Theme.of(context).colorScheme;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Display currency',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Used for transaction amounts and summaries.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: kDisplayCurrencyOptions.map((o) {
                      final isSel = o.code == selected;
                      return FilterChip(
                        showCheckmark: false,
                        label: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                o.flagEmoji,
                                style: const TextStyle(fontSize: 20, height: 1),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${currencySymbolFor(o.code)} ${o.code}',
                                style: TextStyle(
                                  fontWeight: isSel
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  letterSpacing: 0.15,
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

  static Future<void> _confirmSignOut(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('Log out?'),
          content: const Text('You will need to sign in again to use the app.'),
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
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          16 + mainShellFloatingTabBarScrollPadding(context),
        ),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Preferences',
                style: tt.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.25,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Currency, appearance, and how revenue is shown.',
                style: tt.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ).appCardEntrance(),
          _SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SettingsCardHeader(
                  icon: Icons.currency_exchange_rounded,
                  title: 'Display currency',
                ),
                const SizedBox(height: 12),
                Material(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () => _showCurrencyBottomSheet(context),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Text(
                            selectedOption?.flagEmoji ?? '🏳️',
                            style: const TextStyle(fontSize: 28, height: 1),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              '$sym $selected',
                              style: tt.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.expand_more_rounded,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ).appCardEntrance(delay: const Duration(milliseconds: 50)),
          const SizedBox(height: 12),
          _SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SettingsCardHeader(
                  icon: Icons.palette_outlined,
                  title: 'Appearance',
                ),
                const SizedBox(height: 12),
                SegmentedButton<ThemeMode>(
                  style: SegmentedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.brightness_auto_outlined, size: 18),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode_outlined, size: 18),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_outlined, size: 18),
                    ),
                  ],
                  selected: {themeMode},
                  onSelectionChanged: (next) {
                    if (next.isEmpty) return;
                    _setThemeMode(ref, next.single);
                  },
                ),
              ],
            ),
          ).appCardEntrance(delay: const Duration(milliseconds: 100)),
          const SizedBox(height: 12),
          _SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SettingsCardHeader(
                  icon: Icons.notifications_active_outlined,
                  title: 'Purchase alerts',
                ),
                const SizedBox(height: 4),
                Text(
                  'Webhook relay and Firebase Cloud Messaging.',
                  style: tt.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.link_rounded, color: scheme.primary),
                  title: const Text('RevenueCat webhooks'),
                  subtitle: Text(
                    'Enable per-project notifications',
                    style: tt.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                  onTap: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (ctx) => const WebhooksScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ).appCardEntrance(delay: const Duration(milliseconds: 125)),
          const SizedBox(height: 12),
          _SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SettingsCardHeader(
                  icon: Icons.percent_rounded,
                  title: 'Store commission',
                ),
                const SizedBox(height: 4),
                Text(
                  'Optional net revenue after platform fees.',
                  style: tt.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Commission Rate'),
                  value: commission.adjustmentEnabled,
                  onChanged: (v) => ref
                      .read(commissionSettingsProvider.notifier)
                      .setAdjustmentEnabled(v),
                ),
                if (commission.adjustmentEnabled) ...[
                  const Divider(height: 24),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.apple),
                    title: const Text('App Store fee'),
                    subtitle: Text(
                      '${commission.appleCommissionPercent.toStringAsFixed(1)}%',
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    trailing: Icon(Icons.edit_outlined, color: scheme.primary),
                    onTap: () =>
                        _editCommissionPercent(context, ref, isApple: true),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.android),
                    title: const Text('Google Play fee'),
                    subtitle: Text(
                      '${commission.googleCommissionPercent.toStringAsFixed(1)}%',
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    trailing: Icon(Icons.edit_outlined, color: scheme.primary),
                    onTap: () =>
                        _editCommissionPercent(context, ref, isApple: false),
                  ),
                ],
              ],
            ),
          ).appCardEntrance(delay: const Duration(milliseconds: 150)),
          const SizedBox(height: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Account',
                style: tt.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.25,
                ),
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: scheme.primaryContainer.withValues(
                          alpha: 0.65,
                        ),
                        foregroundColor: scheme.onPrimaryContainer,
                        child: const Icon(Icons.person_outline, size: 22),
                      ),
                      title: const Text('Email'),
                      subtitle: Text(
                        me?.email ?? '—',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Divider(height: 28),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.fingerprint_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                      title: const Text('Distinct ID'),
                      subtitle: SelectableText(
                        me?.distinctId ?? '—',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: scheme.error,
                          side: BorderSide(
                            color: scheme.error.withValues(alpha: 0.45),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => _confirmSignOut(context, ref),
                        icon: Icon(Icons.logout_rounded, color: scheme.error),
                        label: const Text('Log out'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ).appCardEntrance(delay: const Duration(milliseconds: 200)),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: child,
      ),
    );
  }
}

class _SettingsCardHeader extends StatelessWidget {
  const _SettingsCardHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, size: 22, color: scheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: tt.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.15,
            ),
          ),
        ),
      ],
    );
  }
}
