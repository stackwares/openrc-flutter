import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/core/utils/currency_format.dart';
import 'package:revenuecat/core/utils/store_commission.dart';
import 'package:revenuecat/services/commission_settings_store.dart';
import 'package:revenuecat/services/display_currency_store.dart';
import 'package:revenuecat/services/exchange_rate_provider.dart';

/// Formats a **USD** amount using the user’s app-wide [displayCurrencyProvider].
/// When currency is USD or rates are unavailable, shows USD.
///
/// Optional [commissionStore] (e.g. `App Store`) applies the matching rate when
/// [commissionSettingsProvider] has adjustment enabled.
/// [applyBlendedCommission] uses the average of Apple & Google rates (for totals
/// without a store).
class DualCurrencyCompactText extends ConsumerWidget {
  final double amount;
  final TextStyle? style;
  final TextAlign textAlign;
  final String? commissionStore;
  final bool applyBlendedCommission;

  const DualCurrencyCompactText({
    super.key,
    required this.amount,
    this.style,
    this.textAlign = TextAlign.start,
    this.commissionStore,
    this.applyBlendedCommission = false,
  });

  double _effectiveUsd(WidgetRef ref) {
    ref.watch(commissionSettingsProvider);
    final settings = ref.read(commissionSettingsProvider);
    return adjustUsdForDisplay(
      gross: amount,
      settings: settings,
      store: commissionStore,
      useBlended: applyBlendedCommission,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayUsd = _effectiveUsd(ref);
    final currency = ref.watch(displayCurrencyProvider);
    if (currency == 'USD') {
      return Text(
        formatCompactUsd(displayUsd),
        style: style,
        textAlign: textAlign,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    final ratesAsync = ref.watch(usdExchangeRatesProvider);
    return ratesAsync.when(
      data: (map) {
        final r = map[currency.toLowerCase()];
        if (r == null || r == 0) {
          return Text(
            formatCompactUsd(displayUsd),
            style: style,
            textAlign: textAlign,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          );
        }
        return Text(
          formatCompactForeign(displayUsd * r, currency),
          style: style,
          textAlign: textAlign,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
      },
      loading: () => Text(
        formatCompactUsd(displayUsd),
        style: style,
        textAlign: textAlign,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      error: (_, _) => Text(
        formatCompactUsd(displayUsd),
        style: style,
        textAlign: textAlign,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Formats a **USD** amount using the user’s app-wide display currency.
class DualCurrencyExactText extends ConsumerWidget {
  final double amount;
  final TextStyle? style;
  final TextAlign textAlign;
  final String? commissionStore;
  final bool applyBlendedCommission;

  /// When false, [amount] is shown as-is in USD (before per-store commission rules).
  /// Use for **gross** figures when commission adjustment is enabled elsewhere.
  final bool applyCommissionAdjustment;

  const DualCurrencyExactText({
    super.key,
    required this.amount,
    this.style,
    this.textAlign = TextAlign.start,
    this.commissionStore,
    this.applyBlendedCommission = false,
    this.applyCommissionAdjustment = true,
  });

  double _effectiveUsd(WidgetRef ref) {
    ref.watch(commissionSettingsProvider);
    if (!applyCommissionAdjustment) return amount;
    final settings = ref.read(commissionSettingsProvider);
    return adjustUsdForDisplay(
      gross: amount,
      settings: settings,
      store: commissionStore,
      useBlended: applyBlendedCommission,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayUsd = _effectiveUsd(ref);
    final currency = ref.watch(displayCurrencyProvider);
    if (currency == 'USD') {
      return Text(
        formatExactUsd(displayUsd),
        style: style,
        textAlign: textAlign,
      );
    }

    final ratesAsync = ref.watch(usdExchangeRatesProvider);
    return ratesAsync.when(
      data: (map) {
        final r = map[currency.toLowerCase()];
        if (r == null || r == 0) {
          return Text(formatExactUsd(displayUsd), style: style, textAlign: textAlign);
        }
        return Text(
          formatExactForeign(displayUsd * r, currency),
          style: style,
          textAlign: textAlign,
        );
      },
      loading: () => Text(formatExactUsd(displayUsd), style: style, textAlign: textAlign),
      error: (_, _) =>
          Text(formatExactUsd(displayUsd), style: style, textAlign: textAlign),
    );
  }
}
