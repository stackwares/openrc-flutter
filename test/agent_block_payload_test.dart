import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/models/agent_block.dart';
import 'package:openrc/models/agent_block_payload.dart';
import 'package:openrc/models/overview_metric_type.dart';

void main() {
  test('reads chart points and metric', () {
    const payload = AgentBlockPayload({
      'metric': 'revenue',
      'range_start': '2026-10-01',
      'chart': {
        'values': [
          {'value': 1.0, 'cohort': 1},
          {'value': 2.5, 'cohort': 2},
        ],
      },
    });
    expect(payload.metricType(), OverviewMetricType.revenue);
    expect(payload.chartPoints(), hasLength(2));
    expect(payload.chartPoints().last.value, 2.5);
    expect(payload.rangeStart(), DateTime(2026, 10, 1));
  });

  test('prefers overview_usd for widget binding', () {
    const payload = AgentBlockPayload({
      'overview': {'mrr': 90},
      'overview_usd': {'mrr': 100},
    });
    expect(payload.overviewUsd['mrr'], 100);
    expect(payload.overview['mrr'], 90);
  });

  group('resolveView', () {
    const transactions = AgentBlockPayload({
      'transactions': [
        {'product': 'pro_monthly'},
      ],
    });
    const overview = AgentBlockPayload({
      'overview_usd': {'mrr': 100},
    });
    const chart = AgentBlockPayload({
      'chart': {
        'values': [
          {'value': 1.0},
        ],
      },
    });

    test('keeps the requested view when its data is there', () {
      expect(
        chart.resolveView(AgentPresentationType.dataTable),
        AgentPresentationType.dataTable,
      );
      expect(
        overview.resolveView(AgentPresentationType.metricCards),
        AgentPresentationType.metricCards,
      );
    });

    test('falls back to the view that fits the data', () {
      expect(
        transactions.resolveView(AgentPresentationType.dataTable),
        AgentPresentationType.transactionList,
      );
      expect(
        overview.resolveView(AgentPresentationType.lineChart),
        AgentPresentationType.metricCards,
      );
      expect(
        const AgentBlockPayload({
          'next_paydays': [
            {'store': 'App Store'},
          ],
        }).resolveView(AgentPresentationType.lineChart),
        AgentPresentationType.barChart,
      );
    });

    test('an empty answer keeps its own view', () {
      expect(
        const AgentBlockPayload({}).resolveView(AgentPresentationType.markdown),
        AgentPresentationType.markdown,
      );
    });
  });

  test('chart points get their cohort day, else count from the start', () {
    const withCohorts = AgentBlockPayload({
      'chart': {
        'values': [
          {'value': 1.0, 'cohort': 1760918400},
        ],
      },
    });
    expect(withCohorts.chartPointDays().single, DateTime(2025, 10, 20));

    const withoutCohorts = AgentBlockPayload({
      'range_start': '2026-10-01',
      'chart': {
        'values': [
          {'value': 1.0},
          {'value': 2.0},
        ],
      },
    });
    expect(withoutCohorts.chartPointDays(), [
      DateTime(2026, 10, 1),
      DateTime(2026, 10, 2),
    ]);
  });
}
