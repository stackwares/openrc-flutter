import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/core/theme/store_brand_icon_colors.dart';
import 'package:openrc/core/utils/plan_display.dart';
import 'package:openrc/core/utils/region_display_name.dart';
import 'package:openrc/features/transactions/transaction_detail_screen.dart';
import 'package:openrc/features/transactions/transactions_common.dart';
import 'package:openrc/features/transactions/transactions_screen.dart';
import 'package:openrc/features/transactions/widgets/active_filters_row.dart';
import 'package:openrc/features/transactions/widgets/transaction_item.dart';
import 'package:openrc/features/transactions/widgets/transaction_leading_avatar.dart';
import 'package:openrc/features/transactions/widgets/transactions_app_filter_sheet.dart';
import 'package:openrc/features/upcoming/upcoming_projection.dart';
import 'package:openrc/features/upcoming/upcoming_provider.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/auto_app_icons_store.dart';
import 'package:openrc/services/commission_settings_store.dart';
import 'package:openrc/services/product_labels_store.dart';
import 'package:openrc/services/rc_account_projects_provider.dart';
import 'package:openrc/services/telemetry.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/animated_reveal.dart';
import 'package:openrc/widgets/app_card.dart';
import 'package:openrc/widgets/app_segmented_control.dart';
import 'package:openrc/widgets/app_state_message.dart';
import 'package:openrc/widgets/dual_currency_text.dart';
import 'package:openrc/widgets/grouped_list.dart';
import 'package:openrc/widgets/section_header.dart';
import 'package:openrc/widgets/shell_header.dart';
import 'package:openrc/widgets/side_panel.dart';
import 'package:openrc/widgets/status_label.dart';

/// Look-ahead choices on the Upcoming screen, in days.
const kUpcomingHorizons = [7, 30];

/// [events] narrowed by the Revenue tab's app, country and store filters.
List<UpcomingEvent> filterUpcomingEvents(
  List<UpcomingEvent> events, {
  Set<String>? apps,
  Set<String>? countryCodes,
  Set<TransactionPlatformFilter>? platforms,
}) {
  if (apps == null &&
      (countryCodes == null || countryCodes.isEmpty) &&
      (platforms == null || platforms.isEmpty)) {
    return events;
  }
  return [
    for (final e in events)
      if ((apps == null || apps.contains(appKeyForTransaction(e.source))) &&
          transactionMatchesCountryFilters(e.source, countryCodes) &&
          transactionMatchesPlatformFilter(e.source, platforms))
        e,
  ];
}

/// Accent for an [UpcomingKind] label and avatar tint.
Color upcomingKindColor(UpcomingKind kind, BuildContext context) {
  final colors = context.appColors;
  switch (kind) {
    case UpcomingKind.renewal:
      return colors.renewal;
    case UpcomingKind.trialConversion:
      return colors.conversion;
    case UpcomingKind.trialEnding:
      return colors.negative;
    case UpcomingKind.expiring:
      return colors.cancelled;
  }
}

IconData _kindIcon(UpcomingKind kind) {
  switch (kind) {
    case UpcomingKind.renewal:
      return Icons.autorenew;
    case UpcomingKind.trialConversion:
      return Icons.swap_horiz;
    case UpcomingKind.trialEnding:
      return Icons.science_outlined;
    case UpcomingKind.expiring:
      return Icons.event_busy_outlined;
  }
}

/// Renewals, trial conversions and lapses due in the next 7 or 30 days.
class UpcomingScreen extends ConsumerStatefulWidget {
  const UpcomingScreen({super.key, this.initialHorizonDays = 7});

  final int initialHorizonDays;

  @override
  ConsumerState<UpcomingScreen> createState() => _UpcomingScreenState();
}

class _UpcomingScreenState extends ConsumerState<UpcomingScreen> {
  late int _horizonDays = widget.initialHorizonDays;
  Set<UpcomingKind> _kinds = {};

  @override
  void initState() {
    super.initState();
    Telemetry.screen('Upcoming');
  }

  void _toggleKind(UpcomingKind kind) {
    setState(() {
      final next = Set<UpcomingKind>.from(_kinds);
      if (!next.remove(kind)) next.add(kind);
      _kinds = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final load = ref.watch(upcomingTransactionsProvider);
    final commission = ref.watch(commissionSettingsProvider);
    final appFilter = ref.watch(transactionsAppIncludeFilterProvider);
    final countryFilter = ref.watch(transactionsCountryFilterProvider);
    final platformFilter = ref.watch(transactionsPlatformFilterProvider);
    final allEvents = ref.watch(upcomingEventsProvider(_horizonDays));
    final events = filterUpcomingEvents(
      allEvents,
      apps: appFilter,
      countryCodes: countryFilter,
      platforms: platformFilter,
    );
    final summary = UpcomingSummary.of(events, commission: commission);
    final rows = _kinds.isEmpty
        ? events
        : events.where((e) => _kinds.contains(e.kind)).toList();

    final filtersOn =
        appFilter != null ||
        (countryFilter != null && countryFilter.isNotEmpty) ||
        (platformFilter != null && platformFilter.isNotEmpty);
    final filterSource = <String, List<RcTransaction>>{
      if (allEvents.isNotEmpty) '_': [for (final e in allEvents) e.source],
    };

    Future<void> openFilters() async {
      final projects = await ref.read(rcAccountProjectsProvider.future);
      if (!context.mounted) return;
      showTransactionsAppFilterSheet(
        context: context,
        filterSource: filterSource,
        currentIncludeFilter: appFilter,
        currentCountryCodes: countryFilter,
        currentPlatforms: platformFilter,
        accountProjects: projects,
        onApply: (apps, countryCodes, platforms) {
          ref.read(transactionsAppIncludeFilterProvider.notifier).state = apps;
          ref.read(transactionsCountryFilterProvider.notifier).state =
              countryCodes;
          ref.read(transactionsPlatformFilterProvider.notifier).state =
              platforms;
        },
      );
    }

    void clearFilters() {
      ref.read(transactionsAppIncludeFilterProvider.notifier).state = null;
      ref.read(transactionsCountryFilterProvider.notifier).state = null;
      ref.read(transactionsPlatformFilterProvider.notifier).state = null;
    }

    Future<void> refresh() =>
        ref.read(upcomingTransactionsProvider.notifier).load();

    final Widget body;
    if (allEvents.isEmpty && load.error != null && !load.isLoading) {
      body = AppStateMessage.error(
        title: 'upcoming.couldntLoad'.tr(),
        message: load.error!,
        onRetry: refresh,
      );
    } else {
      body = _UpcomingBody(
        horizonDays: _horizonDays,
        onHorizonChanged: (days) => setState(() => _horizonDays = days),
        summary: summary,
        showGross: commission.adjustmentEnabled,
        rows: rows,
        kinds: _kinds,
        onToggleKind: _toggleKind,
        loading: load.isLoading,
        truncated: load.truncated,
        error: load.error,
        filtersOn: filtersOn,
        filtersRow: ActiveFiltersRow(
          appCount: appFilter?.length,
          countryCodes: countryFilter,
          platforms: platformFilter,
          onOpenFilters: openFilters,
          onClearApps: () =>
              ref.read(transactionsAppIncludeFilterProvider.notifier).state =
                  null,
          onClearCountries: () =>
              ref.read(transactionsCountryFilterProvider.notifier).state = null,
          onClearPlatforms: () =>
              ref.read(transactionsPlatformFilterProvider.notifier).state =
                  null,
          onClearAll: clearFilters,
        ),
        onRefresh: refresh,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('upcoming.title'.tr()),
        actions: [
          HeaderIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'revenue.filterTransactions'.tr(),
            badge: filtersOn,
            onPressed: filterSource.isEmpty ? null : openFilters,
          ),
          if (ShellHeader.showsRefreshButton)
            HeaderIconButton(
              icon: Icons.refresh_rounded,
              tooltip: 'revenue.refresh'.tr(),
              onPressed: load.isLoading ? null : refresh,
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: body,
    );
  }
}

class _UpcomingBody extends StatelessWidget {
  const _UpcomingBody({
    required this.horizonDays,
    required this.onHorizonChanged,
    required this.summary,
    required this.showGross,
    required this.rows,
    required this.kinds,
    required this.onToggleKind,
    required this.loading,
    required this.truncated,
    required this.error,
    required this.filtersOn,
    required this.filtersRow,
    required this.onRefresh,
  });

  final int horizonDays;
  final ValueChanged<int> onHorizonChanged;
  final UpcomingSummary summary;
  final bool showGross;
  final List<UpcomingEvent> rows;
  final Set<UpcomingKind> kinds;
  final ValueChanged<UpcomingKind> onToggleKind;
  final bool loading;
  final bool truncated;
  final String? error;
  final bool filtersOn;
  final Widget filtersRow;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final muted = context.textTheme.bodySmall?.copyWith(
      color: context.colorScheme.onSurfaceVariant,
    );
    final byDay = <DateTime, List<UpcomingEvent>>{};
    for (final e in rows) {
      byDay.putIfAbsent(localCalendarDay(e.dueAt), () => []).add(e);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = AppBreakpoints.centeringInset(
          constraints.maxWidth,
          maxWidth: AppBreakpoints.readableWidth + 2 * AppSpace.gutter,
        );
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              inset,
              AppSpace.xs,
              inset,
              AppSpace.xl + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              AnimatedReveal(visible: filtersOn, child: filtersRow),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: AppSegmentedControl<int>(
                  values: kUpcomingHorizons,
                  labels: {
                    for (final d in kUpcomingHorizons)
                      d: 'upcoming.days'.plural(d),
                  },
                  groupValue: horizonDays,
                  onValueChanged: (d) {
                    if (d != null) onHorizonChanged(d);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: UpcomingSummaryCard(
                  summary: summary,
                  horizonDays: horizonDays,
                  showGross: showGross,
                  selectedKinds: kinds,
                  onKindTap: onToggleKind,
                ).appCardEntrance(),
              ),
              AnimatedReveal(
                visible: loading,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: [
                      const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Text('upcoming.loadingLonger'.tr(), style: muted),
                    ],
                  ),
                ),
              ),
              if (rows.isEmpty && !loading)
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 32, 28, 8),
                  child: Column(
                    children: [
                      Text(
                        'upcoming.noneTitle'.tr(),
                        style: context.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        filtersOn || kinds.isNotEmpty
                            ? 'upcoming.noFilterMatches'.tr()
                            : 'upcoming.noneMessage'.tr(),
                        textAlign: TextAlign.center,
                        style: muted,
                      ),
                    ],
                  ),
                ),
              for (final entry in byDay.entries) ...[
                SectionHeader(
                  title: _dayLabel(entry.key),
                  count: '${entry.value.length}',
                  trailing: _DayTotal(events: entry.value),
                ),
                GroupedCard(
                  dividerIndent: kTransactionRowDividerIndent,
                  children: [
                    for (final e in entry.value)
                      UpcomingEventRow(
                        event: e,
                        onTap: () => openDetail(
                          context,
                          (context) =>
                              TransactionDetailScreen(transaction: e.source),
                        ),
                      ),
                  ],
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 16),
                child: Text(
                  [
                    if (error != null && rows.isNotEmpty) error!,
                    if (truncated) 'upcoming.truncated'.tr(),
                    'upcoming.note'.tr(),
                  ].join('\n\n'),
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

  static String _dayLabel(DateTime day) {
    final today = localCalendarDay(DateTime.now());
    if (day == today) return 'transactions.today'.tr();
    if (day == today.add(const Duration(days: 1))) {
      return 'upcoming.tomorrow'.tr();
    }
    return DateFormat.MMMEd().format(day);
  }
}

/// Expected charges for one day, in the section header.
class _DayTotal extends StatelessWidget {
  const _DayTotal({required this.events});

  final List<UpcomingEvent> events;

  @override
  Widget build(BuildContext context) {
    final charges = events.where((e) => e.isCharge && e.amountUsd != null);
    if (charges.isEmpty) return const SizedBox.shrink();
    return Consumer(
      builder: (context, ref, _) {
        final total = UpcomingSummary.of(
          charges,
          commission: ref.watch(commissionSettingsProvider),
        ).expectedUsd;
        return DualCurrencyExactText(
          amount: total,
          applyCommissionAdjustment: false,
          style: context.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontFeatures: AppText.tabular,
            color: context.colorScheme.onSurfaceVariant,
          ),
        );
      },
    );
  }
}

/// Expected and at-risk totals with a count per kind; counts toggle filters
/// when [onKindTap] is set.
class UpcomingSummaryCard extends StatelessWidget {
  const UpcomingSummaryCard({
    super.key,
    required this.summary,
    required this.horizonDays,
    required this.showGross,
    this.selectedKinds = const {},
    this.onKindTap,
    this.onTap,
    this.margin = EdgeInsets.zero,
  });

  final UpcomingSummary summary;
  final int horizonDays;
  final bool showGross;
  final Set<UpcomingKind> selectedKinds;
  final ValueChanged<UpcomingKind>? onKindTap;

  /// Makes the whole card a button (the Revenue tab's entry point).
  final VoidCallback? onTap;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final muted = context.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.3,
    );
    final counts = <UpcomingKind, int>{
      UpcomingKind.renewal: summary.renewals,
      UpcomingKind.trialConversion: summary.trialConversions,
      UpcomingKind.trialEnding: summary.trialsEnding,
      UpcomingKind.expiring: summary.expiring,
    };

    return AppCard(
      margin: margin,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  onTap != null
                      ? 'upcoming.cardTitle'.tr()
                      : 'upcoming.nextDays'.plural(horizonDays),
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              if (onTap != null) ...[
                Text('upcoming.nextDays'.plural(horizonDays), style: muted),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                  semanticLabel: 'upcoming.open'.tr(),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Total(
                  label: 'upcoming.expected'.tr(),
                  amount: summary.expectedUsd,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Total(
                  label: 'upcoming.atRisk'.tr(),
                  amount: summary.atRiskUsd,
                  color: summary.atRiskUsd > 0.005
                      ? context.appColors.cancelled
                      : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          Text(
            showGross ? 'upcoming.afterFees'.tr() : 'upcoming.beforeFees'.tr(),
            style: muted,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in counts.entries)
                if (entry.value > 0 || onKindTap != null)
                  _KindChip(
                    kind: entry.key,
                    count: entry.value,
                    selected: selectedKinds.contains(entry.key),
                    onTap: onKindTap == null
                        ? null
                        : () => onKindTap!(entry.key),
                  ),
            ],
          ),
          if (summary.unpriced > 0) ...[
            const SizedBox(height: 8),
            Text('upcoming.unpriced'.plural(summary.unpriced), style: muted),
          ],
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.textTheme.bodySmall?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        DualCurrencyExactText(
          amount: amount,
          applyCommissionAdjustment: false,
          style: AppText.amount(context, size: 22).copyWith(color: color),
        ),
      ],
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.kind,
    required this.count,
    required this.selected,
    this.onTap,
  });

  final UpcomingKind kind;
  final int count;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = upcomingKindColor(kind, context);
    final scheme = context.colorScheme;
    final label = 'upcoming.count.${kind.name}'.plural(count);
    return Material(
      color: selected
          ? color.withValues(alpha: 0.16)
          : scheme.surfaceContainerHigh,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? color : Colors.transparent),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_kindIcon(kind), size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: context.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One projected charge or lapse. Draws no background; place it in a
/// [GroupedCard].
class UpcomingEventRow extends ConsumerWidget {
  const UpcomingEventRow({super.key, required this.event, this.onTap});

  final UpcomingEvent event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tx = event.source;
    final scheme = context.colorScheme;
    final color = upcomingKindColor(event.kind, context);
    final appId = tx.app?.id;
    final iconUrl = appId == null
        ? null
        : ref.watch(resolvedAppIconsProvider.select((icons) => icons[appId]));
    final appName = tx.app?.name?.trim();
    final hasAppName = appName != null && appName.isNotEmpty;
    final product = planDescription(
      tx,
      labels: ref.watch(productLabelsProvider),
    );
    final cc = tx.subscriberCountryCode;
    final country = cc == null
        ? null
        : '${countryFlagEmoji(cc)} ${regionDisplayNameEnglish(cc)}';
    final subtitle = [if (hasAppName) product, ?country].join('  ·  ');
    final amount = event.amountUsd;
    final mutedStyle = context.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.3,
    );

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TransactionLeadingAvatar(
              imageUrl: iconUrl,
              tintColor: color,
              fallback: Icon(_kindIcon(event.kind), color: color, size: 20),
              platformIcon: transactionStoreIcon(tx.store),
              platformIconColor: storeBrandIconTint(tx.store),
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
                          hasAppName ? appName : product,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            height: 1.25,
                          ),
                        ),
                      ),
                      if (amount != null) ...[
                        const SizedBox(width: 8),
                        DualCurrencyExactText(
                          amount: amount,
                          commissionStore: tx.storeForCommission,
                          textAlign: TextAlign.end,
                          style: context.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            fontFeatures: AppText.tabular,
                            color: event.isCharge
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
                            decoration: event.isCharge
                                ? null
                                : TextDecoration.lineThrough,
                            decorationColor: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
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
                        text: 'upcoming.kind.${event.kind.name}'.tr(),
                        color: color,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat.jm().format(event.dueAt),
                    style: mutedStyle?.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Revenue tab entry point: the next 7 days at a glance, opening
/// [UpcomingScreen].
class UpcomingRevenueCard extends ConsumerWidget {
  const UpcomingRevenueCard({
    super.key,
    this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 12),
  });

  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const days = 7;
    final commission = ref.watch(commissionSettingsProvider);
    final events = filterUpcomingEvents(
      ref.watch(upcomingEventsProvider(days)),
      apps: ref.watch(transactionsAppIncludeFilterProvider),
      countryCodes: ref.watch(transactionsCountryFilterProvider),
      platforms: ref.watch(transactionsPlatformFilterProvider),
    );
    return UpcomingSummaryCard(
      summary: UpcomingSummary.of(events, commission: commission),
      horizonDays: days,
      showGross: commission.adjustmentEnabled,
      margin: margin,
      onTap: () => openDetail(context, (_) => const UpcomingScreen()),
    );
  }
}
