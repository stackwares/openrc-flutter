import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/core/utils/currency_format.dart';
import 'package:revenuecat/services/exchange_rate_provider.dart';
import 'package:revenuecat/services/secondary_currency_store.dart';

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
    final secondary = ref.watch(secondaryCurrencyProvider);
    final usd = formatCompactUsd(amount);
    if (secondary == null || secondary.isEmpty) {
      return Text(usd, style: style, maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    final rateAsync = ref.watch(exchangeRateProvider(secondary));
    return rateAsync.when(
      data: (rate) {
        if (rate == null) {
          return Text(usd, style: style, maxLines: 2, overflow: TextOverflow.ellipsis);
        }
        final other = formatCompactForeign(amount * rate, secondary);
        return Text(
          '$usd · $other',
          style: style,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
      },
      loading: () =>
          Text(usd, style: style, maxLines: 2, overflow: TextOverflow.ellipsis),
      error: (_, _) =>
          Text(usd, style: style, maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }
}

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
    final secondary = ref.watch(secondaryCurrencyProvider);
    final usd = formatExactUsd(amount);
    if (secondary == null || secondary.isEmpty) {
      return Text(usd, style: style, textAlign: textAlign);
    }
    final rateAsync = ref.watch(exchangeRateProvider(secondary));
    return rateAsync.when(
      data: (rate) {
        if (rate == null) {
          return Text(usd, style: style, textAlign: textAlign);
        }
        final other = formatExactForeign(amount * rate, secondary);
        return Text(
          '$usd · $other',
          style: style,
          textAlign: textAlign,
        );
      },
      loading: () => Text(usd, style: style, textAlign: textAlign),
      error: (_, _) => Text(usd, style: style, textAlign: textAlign),
    );
  }
}
