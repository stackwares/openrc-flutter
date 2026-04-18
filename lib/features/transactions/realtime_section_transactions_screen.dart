import 'package:flutter/material.dart';
import 'package:revenuecat/core/shell_insets.dart';
import 'package:revenuecat/core/utils/subscriber_tenure_format.dart';
import 'package:revenuecat/features/transactions/transaction_detail_screen.dart';
import 'package:revenuecat/features/transactions/transactions_common.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_item.dart';
import 'package:revenuecat/features/transactions/widgets/transactions_app_filter_sheet.dart';
import 'package:revenuecat/models/rc_transaction.dart';

/// Lists transactions in the Realtime window for one [TransactionDaySectionFilter] category.
class RealtimeSectionTransactionsScreen extends StatefulWidget {
  final List<RcTransaction> windowTransactions;
  final TransactionDaySectionFilter filter;

  const RealtimeSectionTransactionsScreen({
    super.key,
    required this.windowTransactions,
    required this.filter,
  });

  @override
  State<RealtimeSectionTransactionsScreen> createState() =>
      _RealtimeSectionTransactionsScreenState();
}

class _RealtimeSectionTransactionsScreenState
    extends State<RealtimeSectionTransactionsScreen> {
  Set<String>? _appIncludeFilter;

  List<RcTransaction> _appFilteredWindow() {
    if (_appIncludeFilter == null) return widget.windowTransactions;
    return widget.windowTransactions
        .where((tx) => _appIncludeFilter!.contains(appKeyForTransaction(tx)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final appFiltered = _appFilteredWindow();
    final filtered = appFiltered
        .where((t) => transactionMatchesSectionFilter(t, widget.filter))
        .toList();
    filtered.sort((a, b) {
      final ma =
          DateTime.tryParse(a.purchaseDate ?? '')?.millisecondsSinceEpoch ?? 0;
      final mb =
          DateTime.tryParse(b.purchaseDate ?? '')?.millisecondsSinceEpoch ?? 0;
      return mb.compareTo(ma);
    });

    final tenureMap =
        earliestPurchaseLocalDayBySubscriberId(widget.windowTransactions);

    final heading =
        '${filtered.length} ${transactionDaySectionGridLabel(widget.filter)}';

    final filterOptions =
        collectAppFilterOptions({'_': widget.windowTransactions});
    final canFilterApps = filterOptions.isNotEmpty;

    String emptyMessage() {
      if (appFiltered.isEmpty && _appIncludeFilter != null) {
        return 'No transactions for the selected apps in this window.';
      }
      return 'No transactions in this category for the loaded window.';
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              heading,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              kRealtimeWindowSubtitle,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.filter_list,
              color: _appIncludeFilter != null ? scheme.primary : null,
            ),
            tooltip: 'Filter by app',
            onPressed: !canFilterApps || widget.windowTransactions.isEmpty
                ? null
                : () {
                    showTransactionsAppFilterSheet(
                      context: context,
                      filterSource: {'_': widget.windowTransactions},
                      currentIncludeFilter: _appIncludeFilter,
                      onApply: (next) {
                        setState(() => _appIncludeFilter = next);
                      },
                    );
                  },
          ),
        ],
      ),
      body: filtered.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  emptyMessage(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : ListView.builder(
              padding: EdgeInsets.only(
                top: 8,
                bottom: mainShellFloatingTabBarScrollPadding(context),
              ),
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final tx = filtered[i];
                return TransactionItem(
                  transaction: tx,
                  subscriberEarliestPurchaseLocalDayById: tenureMap,
                  inSectionCard: false,
                  onTap: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (context) =>
                            TransactionDetailScreen(transaction: tx),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
