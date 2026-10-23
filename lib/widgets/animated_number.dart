import 'package:flutter/material.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/widgets/dual_currency_text.dart';

/// A USD amount (shown in the display currency) that counts smoothly to each
/// new value instead of jumping.
class AnimatedExactAmount extends StatelessWidget {
  const AnimatedExactAmount({
    super.key,
    required this.amount,
    this.style,
    this.textAlign = TextAlign.start,
    this.applyCommissionAdjustment = true,
    this.countFromZero = false,
  });

  final double amount;
  final TextStyle? style;
  final TextAlign textAlign;
  final bool applyCommissionAdjustment;

  /// Count up from zero the first time it appears (hero totals).
  final bool countFromZero;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: countFromZero ? 0 : null, end: amount),
      duration: AppMotion.of(context, AppMotion.counter),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => DualCurrencyExactText(
        amount: value,
        style: style,
        textAlign: textAlign,
        applyCommissionAdjustment: applyCommissionAdjustment,
      ),
    );
  }
}

/// A whole number that counts to each new value.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({
    super.key,
    required this.count,
    this.style,
    this.countFromZero = true,
  });

  final int count;
  final TextStyle? style;
  final bool countFromZero;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: countFromZero ? 0 : null,
        end: count.toDouble(),
      ),
      duration: AppMotion.of(context, AppMotion.counter),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) =>
          Text('${value.round()}', style: style, semanticsLabel: '$count'),
    );
  }
}
