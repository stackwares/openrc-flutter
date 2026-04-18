import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/core/animations/app_motion.dart';
import 'package:revenuecat/core/shell_insets.dart';
import 'package:revenuecat/core/utils/subscriber_tenure_format.dart';
import 'package:revenuecat/features/transactions/transaction_detail_screen.dart';
import 'package:revenuecat/features/transactions/transactions_common.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_item.dart';
import 'package:revenuecat/features/transactions/widgets/transactions_app_filter_sheet.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/rc_account_projects_provider.dart';

/// Lists transactions in the Revenue tab window for one [TransactionDaySectionFilter] category.
class RealtimeSectionTransactionsScreen extends ConsumerStatefulWidget {
  final List<RcTransaction> windowTransactions;
  final TransactionDaySectionFilter filter;

  const RealtimeSectionTransactionsScreen({
    super.key,
    required this.windowTransactions,
    required this.filter,
  });

  @override
  ConsumerState<RealtimeSectionTransactionsScreen> createState() =>
      _RealtimeSectionTransactionsScreenState();
}

class _RealtimeSectionTransactionsScreenState
    extends ConsumerState<RealtimeSectionTransactionsScreen> {
  Set<String>? _appIncludeFilter;
  Set<String>? _countryFilter;
  Set<TransactionPlatformFilter>? _platformFilter;

  List<RcTransaction> _appFilteredWindow() {
    var list = widget.windowTransactions;
    if (_appIncludeFilter != null) {
      list = list
          .where((tx) => _appIncludeFilter!.contains(appKeyForTransaction(tx)))
          .toList();
    }
    return list
        .where(
          (tx) =>
              transactionMatchesCountryFilters(tx, _countryFilter) &&
              transactionMatchesPlatformFilter(tx, _platformFilter),
        )
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

    final accountProjects =
        ref.watch(rcAccountProjectsProvider).asData?.value ?? const [];
    final filterOptions = collectAppFilterOptionsWithProjects(
      {'_': widget.windowTransactions},
      accountProjects,
    );
    final canFilterApps = filterOptions.isNotEmpty;

    String emptyMessage() {
      final countryOn =
          _countryFilter != null && _countryFilter!.isNotEmpty;
      final platformOn =
          _platformFilter != null && _platformFilter!.isNotEmpty;
      final filtersOn =
          _appIncludeFilter != null || countryOn || platformOn;
      if (appFiltered.isEmpty && filtersOn) {
        return 'No transactions match your filters in this window.';
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
          if (_appIncludeFilter != null ||
              (_countryFilter != null && _countryFilter!.isNotEmpty) ||
              (_platformFilter != null && _platformFilter!.isNotEmpty))
            IconButton(
              icon: const Icon(Icons.filter_alt_off_outlined),
              tooltip: 'Clear filters',
              onPressed: () {
                setState(() {
                  _appIncludeFilter = null;
                  _countryFilter = null;
                  _platformFilter = null;
                });
              },
            ),
          IconButton(
            icon: Icon(
              Icons.filter_list,
              color: _appIncludeFilter != null ||
                      (_countryFilter != null && _countryFilter!.isNotEmpty) ||
                      (_platformFilter != null && _platformFilter!.isNotEmpty)
                  ? scheme.primary
                  : null,
            ),
            tooltip: 'Filter transactions',
            onPressed: !canFilterApps
                ? null
                : () async {
                    final projects = await ref.read(
                      rcAccountProjectsProvider.future,
                    );
                    if (!context.mounted) return;
                    showTransactionsAppFilterSheet(
                      context: context,
                      filterSource: {'_': widget.windowTransactions},
                      currentIncludeFilter: _appIncludeFilter,
                      currentCountryCodes: _countryFilter,
                      currentPlatforms: _platformFilter,
                      accountProjects: projects,
                      onApply: (apps, countryCodes, platforms) {
                        setState(() {
                          _appIncludeFilter = apps;
                          _countryFilter = countryCodes;
                          _platformFilter = platforms;
                        });
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
                ).appListItemEntrance(i);
              },
            ),
    );
  }
}
