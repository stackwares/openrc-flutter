import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/core/utils/currency_format.dart';
import 'package:revenuecat/services/display_currency_store.dart';
import 'package:revenuecat/services/exchange_rate_provider.dart';

/// Formats a **USD** amount using the user’s app-wide [displayCurrencyProvider].
/// When currency is USD or rates are unavailable, shows USD.
class DualCurrencyCompactText extends ConsumerWidget {
  final double amount;
  final TextStyle? style;

  const DualCurrencyCompactText({
    super.key,
    required this.amount,
    this.style,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(displayCurrencyProvider);
    if (currency == 'USD') {
      return Text(
        formatCompactUsd(amount),
        style: style,
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
            formatCompactUsd(amount),
            style: style,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          );
        }
        return Text(
          formatCompactForeign(amount * r, currency),
          style: style,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
      },
      loading: () => Text(
        formatCompactUsd(amount),
        style: style,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      error: (_, _) => Text(
        formatCompactUsd(amount),
        style: style,
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

  const DualCurrencyExactText({
    super.key,
    required this.amount,
    this.style,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(displayCurrencyProvider);
    if (currency == 'USD') {
      return Text(
        formatExactUsd(amount),
        style: style,
        textAlign: textAlign,
      );
    }

    final ratesAsync = ref.watch(usdExchangeRatesProvider);
    return ratesAsync.when(
      data: (map) {
        final r = map[currency.toLowerCase()];
        if (r == null || r == 0) {
          return Text(formatExactUsd(amount), style: style, textAlign: textAlign);
        }
        return Text(
          formatExactForeign(amount * r, currency),
          style: style,
          textAlign: textAlign,
        );
      },
      loading: () => Text(formatExactUsd(amount), style: style, textAlign: textAlign),
      error: (_, _) =>
          Text(formatExactUsd(amount), style: style, textAlign: textAlign),
    );
  }
}
