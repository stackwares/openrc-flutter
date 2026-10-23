import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/models/transaction_list_sort_mode.dart';
import 'package:openrc/services/transaction_list_sort_store.dart';
import 'package:easy_localization/easy_localization.dart';

class TransactionListSortMenuButton extends ConsumerWidget {
  const TransactionListSortMenuButton({super.key, this.showLabel = false});

  /// Text + chevron ("Newest ⌄") instead of an icon (list headers).
  final bool showLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(transactionListSortProvider);
    final scheme = Theme.of(context).colorScheme;
    final changed = current != TransactionListSortMode.purchaseNewestFirst;
    final labelColor = changed ? scheme.primary : scheme.onSurfaceVariant;
    return PopupMenuButton<TransactionListSortMode>(
      icon: showLabel
          ? null
          : Icon(Icons.sort_rounded, color: changed ? scheme.primary : null),
      tooltip: 'transactions.sortList'.tr(),
      onSelected: (mode) =>
          ref.read(transactionListSortProvider.notifier).setMode(mode),
      itemBuilder: (context) => [
        for (final m in TransactionListSortMode.values)
          PopupMenuItem<TransactionListSortMode>(
            value: m,
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: m == current
                      ? Icon(Icons.check, size: 18, color: scheme.primary)
                      : null,
                ),
                Expanded(child: Text(m.menuLabel)),
              ],
            ),
          ),
      ],
      child: showLabel
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    current.shortLabel,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: labelColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.expand_more_rounded, size: 18, color: labelColor),
                ],
              ),
            )
          : null,
    );
  }
}
