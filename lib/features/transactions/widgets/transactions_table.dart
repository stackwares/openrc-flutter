import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/core/theme/store_brand_icon_colors.dart';
import 'package:openrc/core/utils/product_identifier_display.dart';
import 'package:openrc/core/utils/region_display_name.dart';
import 'package:openrc/core/utils/relative_time_format.dart';
import 'package:openrc/features/transactions/transactions_common.dart';
import 'package:openrc/features/transactions/widgets/transaction_item.dart';
import 'package:openrc/features/transactions/widgets/transaction_leading_avatar.dart';
import 'package:openrc/features/transactions/widgets/transaction_type_badge.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/models/transaction_list_sort_mode.dart';
import 'package:openrc/services/auto_app_icons_store.dart';
import 'package:openrc/services/transaction_list_sort_store.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/dual_currency_text.dart';
import 'package:openrc/widgets/status_label.dart';

enum _Column {
  customer(3),
  project(3),
  store(2),
  product(3),
  purchased(2),
  expires(2),
  revenue(2),
  type(2);

  const _Column(this.flex);

  final int flex;

  String get label => switch (this) {
    _Column.customer => 'transactions.table.customer'.tr(),
    _Column.project => 'transactions.table.project'.tr(),
    _Column.store => 'transactions.store'.tr(),
    _Column.product => 'transactions.table.product'.tr(),
    _Column.purchased => 'transactions.purchased'.tr(),
    _Column.expires => 'transactions.table.expires'.tr(),
    _Column.revenue => 'transactions.revenue'.tr(),
    _Column.type => 'transactions.table.type'.tr(),
  };
}

/// Columns that fit [width]: Expires goes first, then Customer.
List<_Column> _columnsFor(double width) => [
  for (final c in _Column.values)
    if (!(c == _Column.expires && width < 1100) &&
        !(c == _Column.customer && width < 1000))
      c,
];

const EdgeInsets _cellPadding = EdgeInsets.symmetric(horizontal: 8);
const EdgeInsets _rowPadding = EdgeInsets.symmetric(horizontal: 8);

/// `$RCAnonymousID:a1b2…` → `a1b2••••9f0e`: enough to tell rows apart.
String _maskedSubscriberId(String id) {
  final bare = id.startsWith(r'$RCAnonymousID:')
      ? id.substring(r'$RCAnonymousID:'.length)
      : id;
  if (bare.length <= 10) return bare;
  return '${bare.substring(0, 4)}••••${bare.substring(bare.length - 4)}';
}

/// The dashboard's transactions (wide Transactions and Revenue): a header
/// that sorts by purchase time or revenue, and one row per transaction in a
/// card like [GroupedSliverList]. A sliver; [transactions] come filtered and
/// sorted.
class TransactionsTable extends ConsumerWidget {
  const TransactionsTable({
    super.key,
    required this.transactions,
    required this.width,
    required this.onOpen,
  });

  final List<RcTransaction> transactions;

  /// Width the table is laid out in; narrower tables drop columns.
  final double width;
  final ValueChanged<RcTransaction> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.colorScheme;
    final columns = _columnsFor(width);
    const radius = Radius.circular(AppRadius.card);
    return DecoratedSliver(
      decoration: ShapeDecoration(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: BorderSide(color: context.appColors.hairline),
        ),
      ),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(child: _HeaderRow(columns: columns)),
          SliverList.separated(
            itemCount: transactions.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final tx = transactions[index];
              return ClipRRect(
                borderRadius: BorderRadius.vertical(
                  bottom: index == transactions.length - 1
                      ? radius
                      : Radius.zero,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: _TransactionRow(
                    key: ValueKey(rcTransactionDedupKey(tx) ?? '$index'),
                    transaction: tx,
                    columns: columns,
                    onTap: () => onOpen(tx),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HeaderRow extends ConsumerWidget {
  const _HeaderRow({required this.columns});

  final List<_Column> columns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.colorScheme;
    final sort = ref.watch(transactionListSortProvider);
    final notifier = ref.read(transactionListSortProvider.notifier);
    final style = context.textTheme.labelMedium?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    final byPurchase =
        sort == TransactionListSortMode.purchaseNewestFirst ||
        sort == TransactionListSortMode.purchaseOldestFirst;

    Widget cell(_Column c) {
      final end = c == _Column.revenue;
      Widget label({bool active = false}) => Text(
        c.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: active ? style?.copyWith(color: scheme.primary) : style,
      );
      final Widget content;
      switch (c) {
        case _Column.purchased:
        case _Column.revenue:
          final purchased = c == _Column.purchased;
          final active = purchased ? byPurchase : !byPurchase;
          final descending =
              sort == TransactionListSortMode.purchaseNewestFirst ||
              sort == TransactionListSortMode.revenueHighToLow;
          content = Tooltip(
            message: 'transactions.sortList'.tr(),
            waitDuration: const Duration(milliseconds: 600),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.icon),
              onTap: () => notifier.setMode(switch ((purchased, active)) {
                (true, true) =>
                  sort == TransactionListSortMode.purchaseNewestFirst
                      ? TransactionListSortMode.purchaseOldestFirst
                      : TransactionListSortMode.purchaseNewestFirst,
                (true, false) => TransactionListSortMode.purchaseNewestFirst,
                (false, true) =>
                  sort == TransactionListSortMode.revenueHighToLow
                      ? TransactionListSortMode.revenueLowToHigh
                      : TransactionListSortMode.revenueHighToLow,
                (false, false) => TransactionListSortMode.revenueHighToLow,
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: label(active: active)),
                    if (active) ...[
                      const SizedBox(width: 2),
                      Icon(
                        descending
                            ? Icons.arrow_downward_rounded
                            : Icons.arrow_upward_rounded,
                        size: 14,
                        color: scheme.primary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        default:
          content = label();
      }
      return Expanded(
        flex: c.flex,
        child: Padding(
          padding: _cellPadding,
          child: Align(
            alignment: end ? Alignment.centerRight : Alignment.centerLeft,
            child: content,
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.appColors.hairline)),
      ),
      child: Padding(
        padding: _rowPadding.add(const EdgeInsets.symmetric(vertical: 8)),
        child: Row(children: [for (final c in columns) cell(c)]),
      ),
    );
  }
}

class _TransactionRow extends ConsumerWidget {
  const _TransactionRow({
    super.key,
    required this.transaction,
    required this.columns,
    required this.onTap,
  });

  final RcTransaction transaction;
  final List<_Column> columns;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.colorScheme;
    final tx = transaction;
    final body = context.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w500,
    );
    final muted = body?.copyWith(color: scheme.onSurfaceVariant);

    Widget text(String value, {TextStyle? style, String? tooltip}) {
      final t = Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style ?? body,
      );
      return tooltip == null
          ? t
          : Tooltip(
              message: tooltip,
              waitDuration: const Duration(milliseconds: 500),
              child: t,
            );
    }

    Widget withLeading(Widget leading, Widget child) => Row(
      children: [
        leading,
        const SizedBox(width: 8),
        Flexible(child: child),
      ],
    );

    Widget cellFor(_Column c) {
      switch (c) {
        case _Column.customer:
          final id = tx.subscriberId?.trim();
          final cc = tx.subscriberCountryCode?.trim();
          return withLeading(
            SizedBox(
              width: 20,
              child: Text(
                cc == null || cc.isEmpty ? '' : countryFlagEmoji(cc),
                semanticsLabel: cc == null
                    ? null
                    : regionDisplayNameEnglish(cc),
              ),
            ),
            text(
              id == null || id.isEmpty ? '—' : _maskedSubscriberId(id),
              style: body?.copyWith(fontFeatures: AppText.tabular),
              tooltip: id,
            ),
          );
        case _Column.project:
          final appId = tx.app?.id;
          final iconUrl = appId == null
              ? null
              : ref.watch(resolvedAppIconsProvider)[appId];
          return withLeading(
            TransactionLeadingAvatar(
              imageUrl: iconUrl,
              size: 22,
              borderRadius: 6,
              tintColor: scheme.primary,
              fallback: Icon(
                Icons.apps_rounded,
                size: 14,
                color: scheme.primary,
              ),
            ),
            text(appLabelForTransaction(tx)),
          );
        case _Column.store:
          final store = tx.store;
          return withLeading(
            Icon(
              transactionStoreIcon(store) ?? Icons.store,
              size: 16,
              color: storeBrandIconTint(store) ?? scheme.onSurfaceVariant,
            ),
            text(store ?? '—'),
          );
        case _Column.product:
          return text(
            productIdentifierDisplayTitle(tx.productIdentifier),
            tooltip: tx.productIdentifier,
          );
        case _Column.purchased:
          final date = DateTime.tryParse(tx.purchaseDate ?? '')?.toLocal();
          return text(
            formatRelativeTimeShort(tx.purchaseDate),
            style: muted,
            tooltip: date == null
                ? null
                : DateFormat.yMMMd().add_jm().format(date),
          );
        case _Column.expires:
          final label = formatEntitlementExpiresInLabel(tx.expiresDate);
          return text(label.isEmpty ? '—' : label, style: muted);
        case _Column.revenue:
          final revenue = tx.tileDisplayRevenue;
          if (revenue == null || revenue.abs() < 0.005) {
            return text('—', style: muted);
          }
          return DualCurrencyExactText(
            amount: revenue,
            commissionStore: tx.storeForCommission,
            textAlign: TextAlign.end,
            style: body?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: AppText.tabular,
              decoration: tx.tileShowRefundRevenueStrikethrough
                  ? TextDecoration.lineThrough
                  : null,
              decorationColor: scheme.onSurfaceVariant,
            ),
          );
        case _Column.type:
          return StatusLabel(
            text: transactionStatusLabel(tx),
            color: transactionStatusColor(tx, context),
            pill: true,
          );
      }
    }

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: _rowPadding.add(const EdgeInsets.symmetric(vertical: 10)),
          child: Row(
            children: [
              for (final c in columns)
                Expanded(
                  flex: c.flex,
                  child: Padding(
                    padding: _cellPadding,
                    child: Align(
                      alignment: c == _Column.revenue
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: cellFor(c),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
