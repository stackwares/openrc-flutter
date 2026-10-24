import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/core/utils/store_display_name.dart';
import 'package:openrc/core/utils/store_payday_schedule.dart';
import 'package:openrc/features/revenue/payout_detail_screen.dart';
import 'package:openrc/features/revenue/payout_history.dart';
import 'package:openrc/features/revenue/payout_history_provider.dart';
import 'package:openrc/features/revenue/widgets/payout_history_chart.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/side_panel.dart';
import 'package:openrc/widgets/animated_number.dart';
import 'package:openrc/widgets/app_card.dart';
import 'package:openrc/widgets/app_state_message.dart';
import 'package:openrc/widgets/delta_badge.dart';
import 'package:openrc/widgets/dual_currency_text.dart';
import 'package:openrc/widgets/grouped_list.dart';
import 'package:openrc/widgets/section_header.dart';
import 'package:openrc/widgets/split_bar.dart';
import 'package:skeletonizer/skeletonizer.dart';

enum _StoreFilter { all, apple, google }

/// What App Store and Google Play paid over the last 12 months, by month.
class PayoutHistoryScreen extends ConsumerStatefulWidget {
  const PayoutHistoryScreen({super.key});

  @override
  ConsumerState<PayoutHistoryScreen> createState() =>
      _PayoutHistoryScreenState();
}

class _PayoutHistoryScreenState extends ConsumerState<PayoutHistoryScreen> {
  _StoreFilter _filter = _StoreFilter.all;
  int? _selectedMonth;

  @override
  void initState() {
    super.initState();
    // After the first frame: loading updates a provider, not allowed mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() => ref.read(payoutHistoryProvider.notifier).load();

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(payoutHistoryProvider);
    final today = DateTime.now();

    final saved = [
      for (final store in PayoutStore.values)
        for (final p in paidPayouts(store, today))
          if (history.amounts[p.id] case final amount?) Payout(p, amount),
    ];
    bool paidSomething(Payout p) => p.amount.abs() >= 0.005;
    // A store that paid nothing all year is left out, filter and all.
    final stores = [
      for (final s in PayoutStore.values)
        if (saved.any((p) => p.period.store == s && paidSomething(p))) s,
    ];
    final filter = stores.length > 1 ? _filter : _StoreFilter.all;
    final shown = switch (filter) {
      _StoreFilter.all => stores,
      _StoreFilter.apple => const [PayoutStore.apple],
      _StoreFilter.google => const [PayoutStore.google],
    };
    final payouts = [
      for (final p in saved)
        if (shown.contains(p.period.store) && paidSomething(p)) p,
    ];

    final Widget body;
    if (payouts.isEmpty && (history.isLoading || !history.hasLoaded)) {
      body = const _PayoutHistorySkeleton();
    } else if (payouts.isEmpty && history.storeSplitUnavailable) {
      body = AppStateMessage(
        icon: Icons.call_split_rounded,
        title: 'revenue.payouts.splitUnavailableTitle'.tr(),
        message: 'revenue.payouts.splitUnavailableMessage'.tr(),
      );
    } else if (payouts.isEmpty && history.error != null) {
      body = AppStateMessage.error(
        title: 'revenue.payouts.couldntLoad'.tr(),
        message: history.error!,
        onRetry: _load,
      );
    } else if (payouts.isEmpty) {
      body = RefreshIndicator(
        onRefresh: _load,
        child: AppStateMessage(
          icon: Icons.account_balance_outlined,
          title: 'revenue.payouts.emptyTitle'.tr(),
          message: 'revenue.payouts.emptyMessage'.tr(),
        ),
      );
    } else {
      body = _content(
        context,
        today: today,
        payouts: payouts,
        stores: stores,
        shown: shown,
        filter: filter,
        refreshFailed: history.error != null || history.storeSplitUnavailable,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('revenue.payouts.title'.tr()),
        // Fetching newer payouts while saved ones show. Built only while
        // loading: an indeterminate bar animates even when invisible.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: AnimatedSwitcher(
            duration: AppMotion.of(context, AppMotion.fast),
            child: history.isLoading && payouts.isNotEmpty
                ? const LinearProgressIndicator(minHeight: 2)
                : const SizedBox(height: 2),
          ),
        ),
      ),
      body: body,
    );
  }

  Widget _content(
    BuildContext context, {
    required DateTime today,
    required List<Payout> payouts,
    required List<PayoutStore> stores,
    required List<PayoutStore> shown,
    required _StoreFilter filter,
    required bool refreshFailed,
  }) {
    final months = payoutMonths(payouts, today);
    final latestPaid = months.lastIndexWhere((m) => m.payouts.isNotEmpty);
    final selected = (_selectedMonth ?? latestPaid).clamp(0, months.length - 1);
    final previous = previousPayouts(payouts);
    final total = payouts.fold(0.0, (sum, p) => sum + p.amount);
    final muted = context.textTheme.bodySmall?.copyWith(
      color: context.colorScheme.onSurfaceVariant,
      height: 1.35,
    );

    // Centered in the width this screen gets, not the window's: on wide
    // windows it opens as a side panel far narrower than the window.
    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = AppBreakpoints.centeringInset(
          constraints.maxWidth,
          maxWidth: AppBreakpoints.readableWidth + 2 * AppSpace.gutter,
        );
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              inset,
              AppSpace.xs,
              inset,
              AppSpace.xl + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              if (refreshFailed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _RefreshFailedBanner(onRetry: _load),
                ),
              if (stores.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SegmentedButton<_StoreFilter>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: _StoreFilter.all,
                        label: Text('revenue.payouts.all'.tr()),
                      ),
                      ButtonSegment(
                        value: _StoreFilter.apple,
                        label: Text(PayoutStore.apple.displayLabel),
                      ),
                      ButtonSegment(
                        value: _StoreFilter.google,
                        label: Text(PayoutStore.google.displayLabel),
                      ),
                    ],
                    selected: {filter},
                    onSelectionChanged: (s) =>
                        setState(() => _filter = s.single),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _TotalCard(
                  total: total,
                  count: payouts.length,
                  since: months.first.month,
                  stores: shown,
                  payouts: payouts,
                ).appCardEntrance(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _MonthChartCard(
                  months: months,
                  stores: shown,
                  selected: selected,
                  onSelected: (i) => setState(() => _selectedMonth = i),
                ).appCardEntrance(delay: const Duration(milliseconds: 60)),
              ),
              for (final month in months.reversed)
                if (month.payouts.isNotEmpty) ...[
                  SectionHeader(
                    title: formatPaydayMonthYear(month.month),
                    trailing: DualCurrencyExactText(
                      amount: month.total,
                      applyCommissionAdjustment: false,
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontFeatures: AppText.tabular,
                      ),
                    ),
                  ),
                  GroupedCard(
                    dividerIndent: 64,
                    children: [
                      for (final (i, p) in month.payouts.indexed)
                        _PayoutRow(
                          payout: p,
                          previous: previous[p.period.id],
                        ).appListItemEntrance(i),
                    ],
                  ),
                ],
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
                child: Text(
                  '${'revenue.payouts.estimateNote'.tr()}\n\n'
                  '${'revenue.payouts.savedNote'.tr()}',
                  textAlign: TextAlign.center,
                  style: muted,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

Color _storeColor(BuildContext context, PayoutStore store) => switch (store) {
  PayoutStore.apple => context.appColors.apple,
  PayoutStore.google => context.appColors.google,
};

IconData _storeIcon(PayoutStore store) => switch (store) {
  PayoutStore.apple => Icons.apple,
  PayoutStore.google => Icons.android,
};

/// The year's total, how many payouts made it, and each store's part.
class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.total,
    required this.count,
    required this.since,
    required this.stores,
    required this.payouts,
  });

  final double total;
  final int count;
  final DateTime since;
  final List<PayoutStore> stores;
  final List<Payout> payouts;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    double storeTotal(PayoutStore s) => payouts
        .where((p) => p.period.store == s)
        .fold(0.0, (sum, p) => sum + p.amount);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'revenue.payouts.paidInLast12Months'.tr(),
            style: context.textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          AnimatedExactAmount(
            amount: total,
            applyCommissionAdjustment: false,
            countFromZero: true,
            style: AppText.amount(context, size: 34),
          ),
          const SizedBox(height: 4),
          Text(
            'revenue.payouts.countSince'.plural(
              count,
              namedArgs: {'month': formatPaydayMonthYear(since)},
            ),
            style: context.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (stores.length > 1) ...[
            const SizedBox(height: 14),
            SplitBar(
              height: 6,
              segments: [
                for (final s in stores)
                  SplitSegment(
                    value: storeTotal(s).clamp(0.0, double.infinity),
                    color: _storeColor(context, s),
                    label: s.displayLabel,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _StoreAmounts(amounts: {for (final s in stores) s: storeTotal(s)}),
          ],
        ],
      ),
    );
  }
}

/// A dot, store name and amount for each store, wrapping when narrow.
class _StoreAmounts extends StatelessWidget {
  const _StoreAmounts({required this.amounts});

  final Map<PayoutStore, double> amounts;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Wrap(
      spacing: AppSpace.lg,
      runSpacing: AppSpace.xxs,
      children: [
        for (final MapEntry(key: store, value: amount) in amounts.entries)
          MergeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _storeColor(context, store),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  store.displayLabel,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                DualCurrencyExactText(
                  amount: amount,
                  applyCommissionAdjustment: false,
                  style: context.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: AppText.tabular,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The picked month's total above a bar per month.
class _MonthChartCard extends StatelessWidget {
  const _MonthChartCard({
    required this.months,
    required this.stores,
    required this.selected,
    required this.onSelected,
  });

  final List<PayoutMonth> months;
  final List<PayoutStore> stores;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final month = months[selected];
    final muted = context.textTheme.bodySmall?.copyWith(
      color: context.colorScheme.onSurfaceVariant,
    );
    final monthName = formatPaydayMonthYear(month.month);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(monthName, style: muted),
          const SizedBox(height: 2),
          if (month.payouts.isEmpty)
            Text(
              'revenue.payouts.noneThisMonth'.tr(),
              style: AppText.amount(
                context,
                size: 17,
                weight: FontWeight.w600,
                color: context.colorScheme.onSurfaceVariant,
              ),
            )
          else
            AnimatedExactAmount(
              amount: month.total,
              applyCommissionAdjustment: false,
              style: AppText.amount(context, size: 22),
            ),
          if (stores.length > 1 && month.payouts.isNotEmpty) ...[
            const SizedBox(height: 6),
            _StoreAmounts(
              amounts: {for (final s in stores) s: month.totalFor(s)},
            ),
          ],
          const SizedBox(height: 16),
          Semantics(
            label: 'revenue.payouts.chartLabel'.tr(),
            value: monthName,
            child: PayoutHistoryChart(
              months: months,
              stores: stores,
              selectedIndex: selected,
              onSelected: onSelected,
            ),
          ),
          const SizedBox(height: 4),
          Text('revenue.payouts.tapMonth'.tr(), style: muted),
        ],
      ),
    );
  }
}

/// One payment: store, amount, pay date, the days it covers, and the change
/// from that store's payment before. Tapping it opens that earnings window as
/// the Revenue tab shows it.
class _PayoutRow extends StatelessWidget {
  const _PayoutRow({required this.payout, required this.previous});

  final Payout payout;
  final Payout? previous;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final period = payout.period;
    final color = _storeColor(context, period.store);
    final caption = context.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.3,
    );
    final date = DateFormat.MMMd().format(period.paymentDate);
    final before = previous?.amount;
    return MergeSemantics(
      child: InkWell(
        key: ValueKey('payout-row-${period.id}'),
        onTap: () => openDetail(
          context,
          (context) => PayoutDetailScreen(payout: payout),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.icon),
                ),
                alignment: Alignment.center,
                child: Icon(_storeIcon(period.store), size: 20, color: color),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            period.store.displayLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpace.xs),
                        DualCurrencyExactText(
                          amount: payout.amount,
                          applyCommissionAdjustment: false,
                          textAlign: TextAlign.end,
                          style: context.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFeatures: AppText.tabular,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            period.isProjected
                                ? 'revenue.payouts.paidAbout'.tr(
                                    namedArgs: {'date': date},
                                  )
                                : 'revenue.payouts.paid'.tr(
                                    namedArgs: {'date': date},
                                  ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: caption,
                          ),
                        ),
                        if (before != null && before.abs() >= 0.005)
                          DeltaBadge.percent(
                            current: payout.amount,
                            previous: before,
                            comparison: 'revenue.payouts.previousPayout'.tr(),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'revenue.earningsRange'.tr(
                        namedArgs: {
                          'range': formatPaydayRange(
                            period.earningsStart,
                            period.earningsEnd,
                          ),
                        },
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: caption?.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Saved payouts are on screen, but the newest couldn't be fetched.
class _RefreshFailedBanner extends StatelessWidget {
  const _RefreshFailedBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 18, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'revenue.payouts.refreshFailed'.tr(),
              style: context.textTheme.bodySmall,
            ),
          ),
          TextButton(onPressed: onRetry, child: Text('common.tryAgain'.tr())),
        ],
      ),
    );
  }
}

/// First-load placeholder in the shape of the total, chart and rows.
class _PayoutHistorySkeleton extends StatelessWidget {
  const _PayoutHistorySkeleton();

  @override
  Widget build(BuildContext context) {
    const bars = <double>[40, 64, 52, 90, 70, 110, 84, 120, 96, 140, 118, 60];
    Widget row() => const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      child: Row(
        children: [
          Bone(
            width: 36,
            height: 36,
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.icon)),
          ),
          SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Bone.text(fontSize: 14, width: 120),
                SizedBox(height: 6),
                Bone.text(fontSize: 12, width: 160),
              ],
            ),
          ),
          Bone.text(fontSize: 14, width: 64),
        ],
      ),
    );

    return Skeletonizer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          const AppCard(
            padding: EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Bone.text(fontSize: 13, width: 150),
                SizedBox(height: 8),
                Bone.text(fontSize: 32, width: 170),
                SizedBox(height: 8),
                Bone.text(fontSize: 13, width: 190),
                SizedBox(height: 16),
                Bone(
                  height: 6,
                  borderRadius: BorderRadius.all(Radius.circular(3)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Bone.text(fontSize: 12, width: 90),
                const SizedBox(height: 6),
                const Bone.text(fontSize: 22, width: 120),
                const SizedBox(height: 16),
                SizedBox(
                  height: 160,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final h in bars)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Bone(
                              height: h,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Bone.text(fontSize: 15, width: 120),
          const SizedBox(height: 10),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: [row(), const Divider(indent: 64), row()]),
          ),
        ],
      ),
    );
  }
}
