import 'package:flutter/material.dart';
import 'package:revenuecat/widgets/app_state_message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/core/animations/app_motion.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/core/shell_insets.dart';
import 'package:revenuecat/features/settings/settings_screen.dart';
import 'package:revenuecat/features/charts/home_notifier.dart';
import 'package:revenuecat/features/charts/overview_metric_detail_screen.dart';
import 'package:revenuecat/features/charts/widgets/home_chart_date_range_sheet.dart';
import 'package:revenuecat/features/charts/widgets/overview_item_card.dart';
import 'package:revenuecat/models/overview_metric_type.dart';
import 'package:revenuecat/widgets/shell_header.dart';

/// Quick chart ranges shown as chips (all end today).
enum _RangePreset { last7Days, last30Days, thisMonth }

extension on _RangePreset {
  String get label => switch (this) {
    _RangePreset.last7Days => '7 days',
    _RangePreset.last30Days => '30 days',
    _RangePreset.thisMonth => 'This month',
  };

  DateTimeRange get range {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    return switch (this) {
      _RangePreset.last7Days => DateTimeRange(
        start: today.subtract(const Duration(days: 6)),
        end: today,
      ),
      _RangePreset.last30Days => DateTimeRange(
        start: today.subtract(const Duration(days: 29)),
        end: today,
      ),
      _RangePreset.thisMonth => DateTimeRange(
        start: DateTime(today.year, today.month, 1),
        end: today,
      ),
    };
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(homeProvider.notifier).fetchData();
    });
  }

  Future<void> _pickChartRange() async {
    final current = ref.read(homeProvider);
    final picked = await HomeChartDateRangeSheet.show(
      context,
      chartRangeStart: current.chartRangeStart,
      chartRangeEnd: current.chartRangeEnd,
    );
    if (picked == null || !mounted) return;
    ref.read(homeProvider.notifier).setChartDateRange(picked.start, picked.end);
  }

  _RangePreset? _matchingPreset(HomeState state) {
    for (final p in _RangePreset.values) {
      final r = p.range;
      if (DateUtils.isSameDay(r.start, state.chartRangeStart) &&
          DateUtils.isSameDay(r.end, state.chartRangeEnd)) {
        return p;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homeProvider);
    final notifier = ref.read(homeProvider.notifier);
    final rangeLabel = notifier.formatChartRangeLabel();

    return Scaffold(
      appBar: ShellHeader(
        title: 'Charts',
        subtitle: rangeLabel,
        bottom: state.isLoading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                ),
              )
            : null,
        actions: [
          if (ShellHeader.showsRefreshButton)
            HeaderIconButton(
              icon: Icons.refresh_rounded,
              tooltip: 'Refresh',
              onPressed: state.isLoading ? null : () => notifier.fetchData(),
            ),
          const SettingsAppBarAction(),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(homeProvider.notifier).fetchData(),
        child: _buildBody(context, state, notifier, rangeLabel),
      ),
    );
  }

  Widget _buildRangeChips(HomeState state) {
    final selected = _matchingPreset(state);
    final notifier = ref.read(homeProvider.notifier);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        children: [
          for (final p in _RangePreset.values) ...[
            _RangeChip(
              label: p.label,
              selected: selected == p,
              onTap: state.isLoading || selected == p
                  ? null
                  : () =>
                        notifier.setChartDateRange(p.range.start, p.range.end),
            ),
            const SizedBox(width: 8),
          ],
          _RangeChip(
            label: 'Custom',
            icon: Icons.calendar_today_rounded,
            selected: selected == null,
            onTap: state.isLoading ? null : _pickChartRange,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    HomeState state,
    HomeNotifier notifier,
    String rangeLabel,
  ) {
    if (state.error != null && state.overview == null) {
      return AppStateMessage.error(
        title: 'Couldn’t load your overview',
        message: state.error!,
        onRetry: notifier.fetchData,
        bottomPadding: mainShellFloatingTabBarScrollPadding(context),
      );
    }

    final loadingFirst = state.isLoading && state.overview == null;
    final loading = state.isLoading;
    final gridMetrics = OverviewMetricType.values
        .where((m) => m != OverviewMetricType.mrr)
        .toList();

    Widget card(OverviewMetricType metric, {bool featured = false}) {
      return OverviewItemCard(
        metric: metric,
        featured: featured,
        value: loadingFirst ? null : notifier.getValue(metric),
        chartData: loading ? null : notifier.getChartData(metric),
        isLoading: loading,
        chartPeriodLabel: rangeLabel,
        onTap: loading
            ? null
            : () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (context) =>
                        OverviewMetricDetailScreen(metric: metric),
                  ),
                );
              },
      );
    }

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _buildRangeChips(state)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          sliver: SliverToBoxAdapter(
            child: loading
                ? card(OverviewMetricType.mrr, featured: true)
                : card(
                    OverviewMetricType.mrr,
                    featured: true,
                  ).appCardEntrance(),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            8 + mainShellFloatingTabBarScrollPadding(context),
          ),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 128,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: gridMetrics.length,
            itemBuilder: (context, index) {
              final c = card(gridMetrics[index]);
              return loading ? c : c.appListItemEntrance(index);
            },
          ),
        ),
      ],
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final fg = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? Color.alphaBlend(
                scheme.primary.withValues(alpha: 0.16),
                scheme.surfaceContainerLow,
              )
            : scheme.surfaceContainerLow,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected
                ? scheme.primary.withValues(alpha: 0.5)
                : context.appColors.hairline,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: context.textTheme.labelLarge?.copyWith(
                    color: selected ? scheme.primary : scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
