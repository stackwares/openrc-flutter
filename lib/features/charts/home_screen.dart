import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:openrc/widgets/app_state_message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/core/shell_insets.dart';
import 'package:openrc/app/main_shell.dart';
import 'package:openrc/features/ask/ask_context.dart';
import 'package:openrc/features/ask/widgets/ask_context_chip.dart';
import 'package:openrc/features/settings/settings_screen.dart';
import 'package:openrc/features/charts/home_notifier.dart';
import 'package:openrc/features/charts/overview_metric_detail_screen.dart';
import 'package:openrc/features/charts/widgets/home_chart_date_range_sheet.dart';
import 'package:openrc/features/charts/widgets/overview_item_card.dart';
import 'package:openrc/models/overview_metric_type.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/pressable_scale.dart';
import 'package:openrc/widgets/shell_header.dart';

/// Quick chart ranges shown as chips (all end today).
enum _RangePreset { last7Days, last30Days, thisMonth }

extension on _RangePreset {
  String get label => switch (this) {
    _RangePreset.last7Days => 'charts.rangeChips.last7Days'.tr(),
    _RangePreset.last30Days => 'charts.rangeChips.last30Days'.tr(),
    _RangePreset.thisMonth => 'charts.presets.thisMonth'.tr(),
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
        title: 'charts.title'.tr(),
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
              tooltip: 'charts.refresh'.tr(),
              onPressed: state.isLoading ? null : () => notifier.fetchData(),
            ),
          AskContextChip(
            label: 'agent.askAboutRange'.tr(),
            onPressed: () => openAskTab(
              ref,
              context: AskPrefills.chartRange(range: rangeLabel),
            ),
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

  Widget _buildRangeChips(
    HomeState state, {
    double inset = 0,
  }) {
    final selected = _matchingPreset(state);
    final notifier = ref.read(homeProvider.notifier);
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(16 + inset, 4, 16 + inset, 4),
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
            label: 'charts.rangeChips.custom'.tr(),
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
        title: 'charts.errors.loadTitle'.tr(),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // More, narrower cards as the window widens; centered past 1200.
        final columns = width >= 900
            ? 4
            : width >= 600
            ? 3
            : 2;
        final inset = AppBreakpoints.centeringInset(width, maxWidth: 1232);
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _buildRangeChips(
                state,
                inset: inset,
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16 + inset, 4, 16 + inset, 0),
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
                16 + inset,
                8,
                16 + inset,
                8 + mainShellFloatingTabBarScrollPadding(context),
              ),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
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
      },
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
      child: PressableScale(
        enabled: onTap != null,
        child: AnimatedContainer(
          duration: AppMotion.of(context, AppMotion.fast),
          curve: Curves.easeOut,
          decoration: ShapeDecoration(
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
          ),
          child: Material(
            type: MaterialType.transparency,
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
        ),
      ),
    );
  }
}
