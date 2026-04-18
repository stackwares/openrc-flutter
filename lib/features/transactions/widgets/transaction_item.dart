import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/core/theme/store_brand_icon_colors.dart';
import 'package:revenuecat/core/utils/region_display_name.dart';
import 'package:revenuecat/core/utils/relative_time_format.dart';
import 'package:revenuecat/core/utils/product_identifier_display.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_leading_avatar.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_type_badge.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/app_icon_overrides_store.dart';
import 'package:revenuecat/services/utilities_service.dart';
import 'package:revenuecat/widgets/dual_currency_text.dart';

class TransactionItem extends ConsumerWidget {
  final RcTransaction transaction;
  final VoidCallback? onTap;

  /// When true, skips the outer [Card] (for rows inside a grouped day [Card]).
  final bool inSectionCard;

  const TransactionItem({
    super.key,
    required this.transaction,
    this.onTap,
    this.inSectionCard = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = transaction.type;
    final color =
        transactionTypeAccentColorForTransactionsList(transaction, context);
    final icon = _typeIcon(type);
    final storeIcon = _storeIcon(transaction.store);
    final appId = transaction.app?.id;
    final iconUrl =
        appId != null ? ref.watch(appIconOverridesProvider)[appId] : null;

    final revenueRefunded = type == RcTransactionType.refund;
    final baseRevenueStyle = context.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.bold,
    );
    final revenueStyle = revenueRefunded
        ? baseRevenueStyle?.copyWith(
            color: context.colorScheme.error,
            decoration: TextDecoration.lineThrough,
            decorationColor: context.colorScheme.error,
          )
        : baseRevenueStyle;

    final body = InkWell(
      onTap: () {
        UtilitiesService.hapticLight();
        onTap?.call();
      },
      borderRadius: inSectionCard
          ? BorderRadius.zero
          : BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            TransactionLeadingAvatar(
              imageUrl: iconUrl,
              tintColor: color,
              fallback: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          productIdentifierDisplayTitle(
                            transaction.productIdentifier,
                          ),
                          style: context.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TransactionTypeBadge(
                        transaction: transaction,
                        useHeaderPillStyle: true,
                      ),
                      if (transaction.revenue != null) ...[
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: DualCurrencyExactText(
                            amount: transaction.revenue!,
                            commissionStore: transaction.store,
                            style: revenueStyle,
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          transaction.productIdentifier ?? '',
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            if (storeIcon != null) ...[
                              Icon(
                                storeIcon,
                                size: 14,
                                color: storeBrandIconTint(transaction.store) ??
                                    context.colorScheme.onSurfaceVariant,
                              ),
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
                            if (transaction.subscriberCountryCode != null)
                              Flexible(
                                child: Text(
                                  '${_countryFlag(transaction.subscriberCountryCode!)} ${regionDisplayNameEnglish(transaction.subscriberCountryCode)}',
                                  style: context.textTheme.bodySmall?.copyWith(
                                    color: context.colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (transaction.purchaseDate != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            formatTransactionListTime(transaction.purchaseDate),
                            style: context.textTheme.bodySmall?.copyWith(
                              color: context.colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.end,
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

    if (inSectionCard) {
      return Material(
        color: Colors.transparent,
        child: body,
      );
    }

    final scheme = context.colorScheme;
    final tileTint = Color.lerp(scheme.surface, color, 0.07) ?? scheme.surface;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: tileTint,
      surfaceTintColor: Colors.transparent,
      child: body,
    );
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

  String _countryFlag(String code) {
    if (code.length != 2) return code;
    final upper = code.toUpperCase();
    return String.fromCharCodes(
      upper.codeUnits.map((c) => c + 127397),
    );
  }
}
