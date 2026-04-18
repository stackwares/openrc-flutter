import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/core/animations/app_motion.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/core/shell_insets.dart';
import 'package:revenuecat/features/home/home_notifier.dart';
import 'package:revenuecat/features/home/overview_metric_detail_screen.dart';
import 'package:revenuecat/features/home/widgets/home_chart_date_range_sheet.dart';
import 'package:revenuecat/features/home/widgets/overview_item_card.dart';
import 'package:revenuecat/services/commission_settings_store.dart';
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
    ref.watch(commissionSettingsProvider);
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
          style: context.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
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
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: mainShellFloatingTabBarScrollPadding(context),
        ),
        children: [
          SizedBox(height: context.screenHeight * 0.3),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: context.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(state.error!, style: context.textTheme.bodyMedium),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () => notifier.fetchData(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ],
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
