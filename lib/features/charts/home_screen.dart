import 'package:flutter/material.dart';
import 'package:revenuecat/widgets/app_state_message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/core/animations/app_motion.dart';
import 'package:revenuecat/core/shell_insets.dart';
import 'package:revenuecat/features/settings/settings_screen.dart';
import 'package:revenuecat/features/charts/home_notifier.dart';
import 'package:revenuecat/features/charts/overview_metric_detail_screen.dart';
import 'package:revenuecat/features/charts/widgets/home_chart_date_range_sheet.dart';
import 'package:revenuecat/features/charts/widgets/overview_item_card.dart';
import 'package:revenuecat/models/overview_metric_type.dart';

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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homeProvider);
    final notifier = ref.read(homeProvider.notifier);
    final metrics = OverviewMetricType.values;
    final rangeLabel = notifier.formatChartRangeLabel();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          rangeLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
        bottom: state.isLoading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                ),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range_outlined),
            tooltip: 'Chart date range',
            onPressed: state.isLoading ? null : _pickChartRange,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed:
                state.isLoading ? null : () => notifier.fetchData(),
          ),
          const SettingsAppBarAction(),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(homeProvider.notifier).fetchData(),
        child: _buildBody(context, state, notifier, metrics, rangeLabel),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    HomeState state,
    HomeNotifier notifier,
    List<OverviewMetricType> metrics,
    String rangeLabel,
  ) {
    if (state.isLoading && state.overview == null) {
      return GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          8,
          8,
          8,
          8 + mainShellFloatingTabBarScrollPadding(context),
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1.5,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: metrics.length,
        itemBuilder: (context, index) => OverviewItemCard(
          metric: metrics[index],
          isLoading: true,
          chartPeriodLabel: rangeLabel,
        ),
      );
    }

    if (state.error != null && state.overview == null) {
      return AppStateMessage.error(
        title: 'Couldn\u2019t load your overview',
        message: state.error!,
        onRetry: notifier.fetchData,
        bottomPadding: mainShellFloatingTabBarScrollPadding(context),
      );
    }

    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        8,
        8,
        8,
        8 + mainShellFloatingTabBarScrollPadding(context),
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: metrics.length,
      itemBuilder: (context, index) {
        final metric = metrics[index];
        final value = notifier.getValue(metric);
        final chartData = notifier.getChartData(metric);
        final loading = state.isLoading;
        final card = OverviewItemCard(
          metric: metric,
          value: value,
          chartData: loading ? null : chartData,
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
        return loading ? card : card.appListItemEntrance(index);
      },
    );
  }
}
