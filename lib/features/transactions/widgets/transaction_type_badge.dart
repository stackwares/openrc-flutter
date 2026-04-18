import 'package:flutter/material.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/models/rc_transaction.dart';

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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          height: 1.1,
          color: color,
        ),
      ),
    );
  }
}
