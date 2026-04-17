import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/models/rc_transaction.dart';

class TransactionItem extends StatelessWidget {
  final RcTransaction transaction;

  const TransactionItem({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final type = transaction.type;
    final color = _typeColor(context, type);
    final icon = _typeIcon(type);
    final storeIcon = _storeIcon(transaction.store);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          transaction.productIdentifier ?? 'Unknown',
                          style: context.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (transaction.revenue != null)
                        Text(
                          _formatRevenue(transaction.revenue!),
                          style: context.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (storeIcon != null) ...[
                        Icon(storeIcon, size: 14, color: context.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                      ],
                      if (transaction.app?.name != null) ...[
                        Flexible(
                          child: Text(
                            transaction.app!.name!,
                            style: context.textTheme.bodySmall?.copyWith(
                              color: context.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (transaction.subscriberCountryCode != null) ...[
                        Text(
                          _countryFlag(transaction.subscriberCountryCode!),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                      const Spacer(),
                      if (transaction.purchaseDate != null)
                        Text(
                          _formatTime(transaction.purchaseDate!),
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _typeColor(BuildContext context, RcTransactionType type) {
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
        return Colors.blue;
      case RcTransactionType.refund:
        return Colors.red;
      case RcTransactionType.unknown:
        return context.colorScheme.onSurfaceVariant;
    }
  }

  IconData _typeIcon(RcTransactionType type) {
    switch (type) {
      case RcTransactionType.newSubscription:
        return Icons.add_circle_outline;
      case RcTransactionType.oneTimePurchase:
        return Icons.shopping_bag_outlined;
      case RcTransactionType.renewal:
        return Icons.autorenew;
      case RcTransactionType.trial:
        return Icons.science_outlined;
      case RcTransactionType.conversion:
        return Icons.swap_horiz;
      case RcTransactionType.refund:
        return Icons.undo;
      case RcTransactionType.unknown:
        return Icons.help_outline;
    }
  }

  IconData? _storeIcon(String? store) {
    if (store == null) return null;
    switch (store) {
      case 'App Store':
        return Icons.apple;
      case 'Play Store':
        return Icons.android;
      case 'Stripe':
        return Icons.credit_card;
      default:
        return Icons.store;
    }
  }

  String _formatRevenue(double revenue) {
    final format = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    return format.format(revenue);
  }

  String _formatTime(String dateStr) {
    try {
      final dt = DateTime.tryParse(dateStr);
      if (dt != null) {
        return DateFormat.Hm().format(dt);
      }
    } catch (_) {}
    return dateStr;
  }

  String _countryFlag(String code) {
    if (code.length != 2) return code;
    final upper = code.toUpperCase();
    return String.fromCharCodes(
      upper.codeUnits.map((c) => c + 127397),
    );
  }
}
