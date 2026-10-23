import 'package:flutter/material.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/theme/app_tokens.dart';
import 'package:revenuecat/widgets/status_label.dart';

/// Soft pill shared by small type / status labels.
abstract final class TransactionPillStyle {
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 9,
    vertical: 4,
  );

  static BoxDecoration decoration(Color accent, {bool selected = false}) {
    return BoxDecoration(
      color: accent.withValues(alpha: selected ? 0.24 : 0.14),
      borderRadius: BorderRadius.circular(AppRadius.pill),
    );
  }

  static TextStyle textStyle(Color accent, {bool enabled = true}) {
    return TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      height: 1.15,
      color: enabled ? accent : accent.withValues(alpha: 0.45),
    );
  }
}

/// Sentence-case state of one transaction (Trial, Converted, Refunded, …).
String transactionStatusLabel(RcTransaction transaction) {
  if (transaction.type == RcTransactionType.refund) return 'Refunded';
  if (transaction.isCancelledSummaryBadge) return 'Cancelled';
  switch (transaction.type) {
    case RcTransactionType.newSubscription:
    case RcTransactionType.oneTimePurchase:
      return 'Purchased';
    case RcTransactionType.renewal:
      return 'Renewed';
    case RcTransactionType.trial:
      return 'Trial';
    case RcTransactionType.conversion:
      return 'Converted';
    case RcTransactionType.refund:
      return 'Refunded';
    case RcTransactionType.unknown:
      return 'Other';
  }
}

/// Color for [transactionStatusLabel]: purchases share one color (as in the
/// day summary tiles), refunds and cancellations win over the type.
Color transactionStatusColor(RcTransaction transaction, BuildContext context) {
  final colors = context.appColors;
  if (transaction.type == RcTransactionType.refund) return colors.refund;
  if (transaction.isCancelledSummaryBadge) return colors.cancelled;
  final type = transaction.type;
  if (type == RcTransactionType.oneTimePurchase ||
      type == RcTransactionType.newSubscription) {
    return colors.purchase;
  }
  return transactionTypeAccentColor(type, context, transaction: transaction);
}

Color transactionTypeAccentColor(
  RcTransactionType type,
  BuildContext context, {
  RcTransaction? transaction,
}) {
  final colors = context.appColors;
  if (type == RcTransactionType.trial &&
      transaction != null &&
      transaction.isCanceledTrial) {
    return colors.negative;
  }
  switch (type) {
    case RcTransactionType.newSubscription:
      return colors.purchase;
    case RcTransactionType.oneTimePurchase:
      return colors.oneTimePurchase;
    case RcTransactionType.renewal:
      return colors.renewal;
    case RcTransactionType.trial:
      return colors.trial;
    case RcTransactionType.conversion:
      return colors.conversion;
    case RcTransactionType.refund:
      return colors.refund;
    case RcTransactionType.unknown:
      return context.colorScheme.onSurfaceVariant;
  }
}

/// Accent for customer history / activity [event] strings (e.g. `REFUND`, `CANCELLATION`,
/// `INITIAL_PURCHASE`, `RENEWAL`), matching [transactionTypeAccentColor] and
/// [transactionStatusColor].
Color transactionHistoryEventAccentColor(String rawType, BuildContext context) {
  var t = rawType.trim().toUpperCase();
  t = t.replaceAll(RegExp(r'\s+'), '_');
  if (t.isEmpty) {
    return context.colorScheme.onSurfaceVariant;
  }

  if (t.contains('UNCANCELLATION') || t.contains('REACTIVAT')) {
    return transactionTypeAccentColor(RcTransactionType.renewal, context);
  }
  if (t.contains('REFUND')) {
    return transactionTypeAccentColor(RcTransactionType.refund, context);
  }
  if (t.contains('CANCELLATION') ||
      t.contains('EXPIRATION') ||
      t == 'EXPIRED' ||
      (t.contains('CANCEL') && !t.contains('UNCANCELLATION'))) {
    return context.appColors.cancelled;
  }
  if (t.contains('CONVERSION') || t.contains('CONVERTED')) {
    return transactionTypeAccentColor(RcTransactionType.conversion, context);
  }
  if (t.contains('RENEWAL') || t == 'RENEW' || t.contains('RENEWED')) {
    return transactionTypeAccentColor(RcTransactionType.renewal, context);
  }
  if (t.contains('TRIAL')) {
    return transactionTypeAccentColor(RcTransactionType.trial, context);
  }
  if (t.contains('PURCHASE') ||
      t.contains('NON_RENEWING') ||
      t.contains('INITIAL') ||
      t.contains('ONE_TIME') ||
      t.contains('NEW_SUBSCRIPTION') ||
      t.contains('PRODUCT_CHANGE') ||
      t.contains('LIFETIME') ||
      t.contains('NON_CONSUMABLE') ||
      t.contains('CONSUMABLE') ||
      t.contains('IAP') ||
      t.contains('PROMO')) {
    return transactionTypeAccentColor(
      RcTransactionType.newSubscription,
      context,
    );
  }
  if (t.contains('EXTENDED')) {
    return transactionTypeAccentColor(RcTransactionType.renewal, context);
  }
  if (t.contains('SUBSCRIPTION') && t.contains('CONVERT')) {
    return transactionTypeAccentColor(RcTransactionType.conversion, context);
  }

  return context.colorScheme.onSurfaceVariant;
}

/// Status of one transaction as a soft pill (detail header).
class TransactionTypeBadge extends StatelessWidget {
  final RcTransaction transaction;

  /// Plain colored text instead of a pill (list rows).
  final bool plain;

  const TransactionTypeBadge({
    super.key,
    required this.transaction,
    this.plain = false,
  });

  @override
  Widget build(BuildContext context) {
    return StatusLabel(
      text: transactionStatusLabel(transaction),
      color: transactionStatusColor(transaction, context),
      pill: !plain,
    );
  }
}
