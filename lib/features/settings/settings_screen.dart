import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/core/utils/currency_format.dart';
import 'package:revenuecat/services/rc_auth_service.dart';
import 'package:revenuecat/services/secondary_currency_store.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(secondaryCurrencyProvider);
    final notifier = ref.read(secondaryCurrencyProvider.notifier);
    final checkColor = context.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () async {
              await ref.read(rcAuthServiceProvider).signOut();
            },
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'DISPLAY CURRENCY',
              style: context.textTheme.labelMedium?.copyWith(
                color: context.colorScheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Amounts are always based on USD from RevenueCat. Choose an optional second currency to show converted values beside USD. Rates update from the European Central Bank (Frankfurter API).',
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: _currencyLeading(context, emoji: '🇺🇸', symbol: r'$'),
            title: const Text('USD only'),
            subtitle: Text(
              r'$ · USD',
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: selected == null
                ? Icon(Icons.check_circle, color: checkColor, size: 22)
                : null,
            onTap: () => notifier.setCurrency(null),
          ),
          const Divider(height: 1),
          ...kSecondaryCurrencyOptions.map(
            (o) {
              final sym = currencySymbolFor(o.code);
              return ListTile(
                leading: _currencyLeading(context, emoji: o.flagEmoji, symbol: sym),
                title: Text(o.label),
                subtitle: Text(
                  '$sym · ${o.code}',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: selected == o.code
                    ? Icon(Icons.check_circle, color: checkColor, size: 22)
                    : null,
                onTap: () => notifier.setCurrency(o.code),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Flag + currency symbol (settings list).
  static Widget _currencyLeading(
    BuildContext context, {
    required String emoji,
    required String symbol,
  }) {
    return SizedBox(
      width: 56,
      child: Row(
        children: [
          Text(
            emoji,
            style: const TextStyle(fontSize: 26, height: 1),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              symbol,
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
