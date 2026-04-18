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
class TransactionTypeBadge extends StatelessWidget {
  final RcTransaction transaction;

  const TransactionTypeBadge({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final type = transaction.type;
    final color =
        transactionTypeAccentColor(type, context, transaction: transaction);
    final label = transactionTypeBadgeLabel(type);
    return Container(
      padding: TransactionPillStyle.padding,
      decoration: TransactionPillStyle.decoration(color),
      child: Text(
        label,
        style: TransactionPillStyle.textStyle(color),
      ),
    );
  }
}
