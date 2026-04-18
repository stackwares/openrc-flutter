import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/core/utils/currency_format.dart';
import 'package:revenuecat/services/display_currency_store.dart';
import 'package:revenuecat/services/exchange_rate_provider.dart';
import 'package:revenuecat/services/rc_auth_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(displayCurrencyProvider);
    final notifier = ref.read(displayCurrencyProvider.notifier);
    final checkColor = context.colorScheme.primary;
    final rates = ref.watch(usdExchangeRatesProvider);

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
              'RevenueCat amounts are stored in USD. Choose the currency used everywhere in the app. Exchange rates are loaded from '
              'fawazahmed0/currency-api (GitHub) via jsDelivr, with a Cloudflare Pages fallback, and update on the upstream schedule.',
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: rates.when(
              data: (m) => Text(
                m.isEmpty
                    ? 'Rates: unavailable (showing USD until loaded)'
                    : 'Rates: loaded (${m.length} pairs)',
                style: context.textTheme.labelSmall?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              loading: () => Text(
                'Rates: loading…',
                style: context.textTheme.labelSmall?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              error: (_, _) => Text(
                'Rates: error (using USD fallback)',
                style: context.textTheme.labelSmall?.copyWith(
                  color: context.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () => ref.invalidate(usdExchangeRatesProvider),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Refresh exchange rates'),
          ),
          const SizedBox(height: 4),
          const Divider(height: 1),
          ...kDisplayCurrencyOptions.map(
            (o) {
              final sym = currencySymbolFor(o.code);
              return ListTile(
                leading:
                    _currencyLeading(context, emoji: o.flagEmoji, symbol: sym),
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
