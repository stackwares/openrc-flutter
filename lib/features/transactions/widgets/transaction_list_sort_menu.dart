import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/models/transaction_list_sort_mode.dart';
import 'package:revenuecat/services/transaction_list_sort_store.dart';

class TransactionListSortMenuButton extends ConsumerWidget {
  const TransactionListSortMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(transactionListSortProvider);
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<TransactionListSortMode>(
      icon: Icon(
        Icons.sort_rounded,
        color: current == TransactionListSortMode.purchaseNewestFirst
            ? null
            : scheme.primary,
      ),
      tooltip: 'Sort list',
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
    );
  }
}
