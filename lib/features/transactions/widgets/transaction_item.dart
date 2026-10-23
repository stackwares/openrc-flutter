import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/core/theme/store_brand_icon_colors.dart';
import 'package:openrc/core/utils/region_display_name.dart';
import 'package:openrc/core/utils/subscriber_tenure_format.dart';
import 'package:openrc/core/utils/relative_time_format.dart';
import 'package:openrc/core/utils/product_identifier_display.dart';
import 'package:openrc/features/transactions/widgets/transaction_leading_avatar.dart';
import 'package:openrc/features/transactions/widgets/transaction_type_badge.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/auto_app_icons_store.dart';
import 'package:openrc/services/utilities_service.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/dual_currency_text.dart';
import 'package:openrc/widgets/status_label.dart';

/// Leading inset of the hairline between rows (avatar + gaps).
const double kTransactionRowDividerIndent = 64;

/// One transaction row. Place it inside a grouped card
/// ([GroupedSliverList] / [GroupedCard]); it draws no background of its own.
class TransactionItem extends ConsumerWidget {
  final RcTransaction transaction;
  final VoidCallback? onTap;

  /// Earliest loaded [RcTransaction.purchaseDate] per subscriber (fallback when API omits created-at).
  final Map<String, DateTime> subscriberEarliestPurchaseLocalDayById;

  /// Earliest loaded purchase **instant** per subscriber (same-day tenure `ago` anchor).
  final Map<String, DateTime> subscriberEarliestPurchaseLocalInstantById;

  /// When set, the app icon flies into [TransactionDetailScreen] with this tag.
  final Object? heroTag;

  const TransactionItem({
    super.key,
    required this.transaction,
    this.onTap,
    this.heroTag,
    this.subscriberEarliestPurchaseLocalDayById = const {},
    this.subscriberEarliestPurchaseLocalInstantById = const {},
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.colorScheme;
    final sid = transaction.subscriberId?.trim();
    final tenureSubtitle = formatSubscriberTenureSubtitle(
      subscriberCreatedAtIso: transaction.subscriberCreatedAt,
      fallbackFirstPurchaseLocalDay: sid != null && sid.isNotEmpty
          ? subscriberEarliestPurchaseLocalDayById[sid]
          : null,
      fallbackFirstPurchaseLocalInstant: sid != null && sid.isNotEmpty
          ? subscriberEarliestPurchaseLocalInstantById[sid]
          : null,
    );

    final type = transaction.type;
    final statusColor = transactionStatusColor(transaction, context);
    final appId = transaction.app?.id;
    final iconUrl = appId != null
        ? ref.watch(resolvedAppIconsProvider)[appId]
        : null;

    final appName = transaction.app?.name?.trim();
    final hasAppName = appName != null && appName.isNotEmpty;
    final product = productIdentifierDisplayTitle(
      transaction.productIdentifier,
    );
    final title = hasAppName ? appName : product;
    final cc = transaction.subscriberCountryCode;
    final country = cc == null
        ? null
        : '${_countryFlag(cc)} ${regionDisplayNameEnglish(cc)}';
    final subtitle = [if (hasAppName) product, ?country].join('  ·  ');
    final meta = [
      ?tenureSubtitle,
      if (transaction.purchaseDate != null)
        formatTransactionListTime(transaction.purchaseDate),
    ].join('  ·  ');

    final revenue = transaction.tileDisplayRevenue;
    final isZero = revenue != null && revenue.abs() < 0.005;
    final revenueStyle = context.textTheme.bodyLarge?.copyWith(
      fontWeight: FontWeight.w700,
      fontSize: 15,
      fontFeatures: AppText.tabular,
      color: isZero ? scheme.onSurfaceVariant : scheme.onSurface,
      decoration: transaction.tileShowRefundRevenueStrikethrough
          ? TextDecoration.lineThrough
          : null,
      decorationColor: scheme.onSurfaceVariant,
    );
    final mutedStyle = context.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.3,
    );

    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              UtilitiesService.hapticLight();
              onTap!.call();
            },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _withHero(
              TransactionLeadingAvatar(
                imageUrl: iconUrl,
                tintColor: statusColor,
                fallback: Icon(_typeIcon(type), color: statusColor, size: 20),
                platformIcon: _storeIcon(transaction.store),
                platformIconColor: storeBrandIconTint(transaction.store),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            height: 1.25,
                          ),
                        ),
                      ),
                      if (revenue != null) ...[
                        const SizedBox(width: 8),
                        DualCurrencyExactText(
                          amount: revenue,
                          commissionStore: transaction.storeForCommission,
                          style: revenueStyle,
                          textAlign: TextAlign.end,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: mutedStyle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusLabel(
                        text: transactionStatusLabel(transaction),
                        color: statusColor,
                      ),
                    ],
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mutedStyle?.copyWith(fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _withHero(Widget avatar) {
    final tag = heroTag;
    return tag == null ? avatar : Hero(tag: tag, child: avatar);
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
    return String.fromCharCodes(upper.codeUnits.map((c) => c + 127397));
  }
}
