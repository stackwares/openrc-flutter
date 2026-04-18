import 'package:flutter/material.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/models/rc_transaction.dart';

/// Pill shape, padding, border, and typography shared with day-summary badges
/// (TRIAL, CONV, REN, SUB) on the transactions screen.
abstract final class TransactionPillStyle {
  static const EdgeInsets padding =
      EdgeInsets.symmetric(horizontal: 10, vertical: 5);

  static BoxDecoration decoration(
    Color accent, {
    bool selected = false,
  }) {
    return BoxDecoration(
      color: accent.withValues(alpha: selected ? 0.28 : 0.14),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: accent.withValues(alpha: selected ? 0.85 : 0.35),
        width: selected ? 1.5 : 1,
      ),
    );
  }

  static TextStyle textStyle(Color accent, {bool enabled = true}) {
    return TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.15,
      height: 1.1,
      color: enabled ? accent : accent.withValues(alpha: 0.45),
    );
  }

  /// Linear scale for list-row pills (20% smaller than [padding] / base [textStyle]).
  static BoxDecoration decorationScaled(
    Color accent,
    double scale, {
    bool selected = false,
  }) {
    final borderW = (selected ? 1.5 : 1.0) * scale;
    return BoxDecoration(
      color: accent.withValues(alpha: selected ? 0.28 : 0.14),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: accent.withValues(alpha: selected ? 0.85 : 0.35),
        width: borderW < 0.5 ? 0.5 : borderW,
      ),
    );
  }
}

String transactionTypeBadgeLabel(RcTransactionType type) {
  switch (type) {
    case RcTransactionType.newSubscription:
      return 'SUB';
    case RcTransactionType.oneTimePurchase:
      return 'ONE-TIME';
    case RcTransactionType.renewal:
      return 'RENEWAL';
    case RcTransactionType.trial:
      return 'TRIAL';
    case RcTransactionType.conversion:
      return 'CONVERSION';
    case RcTransactionType.refund:
      return 'REFUND';
    case RcTransactionType.unknown:
      return 'OTHER';
  }
}

/// Same text and accent grouping as [TransactionsScreen] day-summary header pills.
String transactionTypeHeaderPillLabel(RcTransactionType type) {
  switch (type) {
    case RcTransactionType.newSubscription:
    case RcTransactionType.oneTimePurchase:
      return 'SUB';
    case RcTransactionType.renewal:
      return 'REN';
    case RcTransactionType.trial:
      return 'TRIAL';
    case RcTransactionType.conversion:
      return 'CONV';
    case RcTransactionType.refund:
      return 'REFUND';
    case RcTransactionType.unknown:
      return 'OTHER';
  }
}

/// List rows on the transactions screen: same SUB grouping (and blue accent) as day header pills.
Color transactionTypeAccentColorForTransactionsList(
  RcTransaction transaction,
  BuildContext context,
) {
  final type = transaction.type;
  if (type == RcTransactionType.oneTimePurchase ||
      type == RcTransactionType.newSubscription) {
    return transactionTypeAccentColor(
      RcTransactionType.newSubscription,
      context,
    );
  }
  return transactionTypeAccentColor(type, context, transaction: transaction);
}

Color transactionTypeAccentColor(
  RcTransactionType type,
  BuildContext context, {
  RcTransaction? transaction,
}) {
  if (type == RcTransactionType.trial &&
      transaction != null &&
      transaction.isCanceledTrial) {
    return Colors.red;
  }
  switch (type) {
    case RcTransactionType.newSubscription:
      return Colors.blue;
    case RcTransactionType.oneTimePurchase:
      return Colors.purple;
    case RcTransactionType.renewal:
      return Colors.green;
    case RcTransactionType.trial:
      return Colors.orange;
    case RcTransactionType.conversion:
      return Colors.teal;
    case RcTransactionType.refund:
      return Colors.red;
    case RcTransactionType.unknown:
      return context.colorScheme.onSurfaceVariant;
  }
}

/// Compact pill label for [RcTransaction.type] (e.g. TRIAL, RENEWAL).
///
/// When [useHeaderPillStyle] is true (list rows on the transactions screen),
/// uses the same abbreviations and SUB accent as the day header (TRIAL / CONV / REN / SUB),
/// at 80% scale (20% smaller than header / detail pills).
class TransactionTypeBadge extends StatelessWidget {
  static const double _listTileScale = 0.8;

  final RcTransaction transaction;
  final bool useHeaderPillStyle;

  const TransactionTypeBadge({
    super.key,
    required this.transaction,
    this.useHeaderPillStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    final type = transaction.type;
    final color = _pillColor(context, type);
    final label = useHeaderPillStyle
        ? transactionTypeHeaderPillLabel(type)
        : transactionTypeBadgeLabel(type);
    final scale = useHeaderPillStyle ? _listTileScale : 1.0;
    final padding = EdgeInsets.symmetric(
      horizontal: 10 * scale,
      vertical: 5 * scale,
    );
    final baseText = TransactionPillStyle.textStyle(color);
    final textStyle = useHeaderPillStyle
        ? baseText.copyWith(
            fontSize: (baseText.fontSize ?? 11) * scale,
            letterSpacing: (baseText.letterSpacing ?? 0.15) * scale,
          )
        : baseText;
    final decoration = useHeaderPillStyle
        ? TransactionPillStyle.decorationScaled(color, scale)
        : TransactionPillStyle.decoration(color);
    return Container(
      padding: padding,
      decoration: decoration,
      child: Text(
        label,
        style: textStyle,
      ),
    );
  }

  Color _pillColor(BuildContext context, RcTransactionType type) {
    if (!useHeaderPillStyle) {
      return transactionTypeAccentColor(type, context, transaction: transaction);
    }
    return transactionTypeAccentColorForTransactionsList(transaction, context);
  }
}
