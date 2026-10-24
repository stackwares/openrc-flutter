import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/ask/ask_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openrc/features/transactions/transactions_screen.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/models/rc_transaction_detail.dart';
import 'package:openrc/models/rc_transaction_detail_activity.dart';
import 'package:openrc/services/agent/agent_repair_compositor.dart';
import 'package:openrc/services/agent/agent_tool_executor.dart';
import 'package:openrc/services/rc_api_service.dart';
import 'package:openrc/models/agent_block.dart';

class _SeededTx extends TransactionsNotifier {
  _SeededTx(super.ref, List<RcTransaction> txs) {
    state = TransactionsState(
      selectedDayKey: '2026-10-24',
      grouped: {'2026-10-24': txs},
      hasMore: false,
      realtimeLoadComplete: true,
    );
  }

  @override
  Future<void> fetchInitial() async {}
}

class _DetailApi extends RcApiService {
  @override
  Future<RcTransactionDetailResponse> transactionDetail({
    required String projectId,
    required String subscriberId,
    bool sandboxMode = false,
  }) async {
    return const RcTransactionDetailResponse(
      dollarsSpent: 42,
      lastSeenCountry: 'US',
      history: [
        RcSubscriberHistory(
          at: '2026-10-01',
          event: 'purchase',
          alias: r'$RCAnonymousID:abcdefghijklmnop',
        ),
      ],
    );
  }

  @override
  Future<RcTransactionDetailActivityResponse> transactionDetailActivity({
    required String projectId,
    required String subscriberId,
    bool sandboxMode = false,
  }) async {
    return const RcTransactionDetailActivityResponse(
      subscriberAppUserId: r'$RCAnonymousID:abcdefghijklmnop',
      events: [
        RcTransactionDetailEvent(
          type: 'CANCELLATION',
          transferredFrom: [r'$RCAnonymousID:abcdefghijklmnop'],
        ),
      ],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const tx = RcTransaction(
    app: RcTransactionApp(id: 'proj', name: 'Widget Hub'),
    productIdentifier: 'pro_monthly',
    store: 'APP_STORE',
    revenue: 9.99,
    purchaseDate: '2026-10-24T12:00:00Z',
    storeTransactionIdentifier: '2000000123',
    subscriberId: r'$RCAnonymousID:abcdefghijklmnop',
    wasRefunded: true,
  );

  ProviderContainer container() {
    return ProviderContainer(
      overrides: [
        rcApiServiceProvider.overrideWithValue(_DetailApi()),
        transactionsProvider.overrideWith((ref) => _SeededTx(ref, [tx])),
      ],
    );
  }

  void focusSale(ProviderContainer c) {
    c.read(askFocusTransactionIdProvider.notifier).state = '2000000123';
  }

  test('get_transaction masks subscriber ids and keeps the sale', () async {
    final c = container();
    addTearDown(c.dispose);
    final result = await c.read(agentToolExecutorProvider).run(
      'get_transaction',
      {'store_transaction_id': '2000000123'},
    );
    expect(result['error'], isNull);
    final row = result['transaction'] as Map;
    expect(row['store_transaction_id'], '2000000123');
    expect(row['subscriber_id'], 'abcd••••mnop');
    expect(row['type'], 'refund');
    expect(jsonContainsRawId(result), isFalse);

    final subscriber = result['subscriber'] as Map;
    expect(subscriber['subscriber_id'], 'abcd••••mnop');
    expect(subscriber['dollars_spent_usd'], 42);
    final history = subscriber['history'] as List;
    expect((history.first as Map)['alias'], 'abcd••••mnop');

    final activity = result['activity'] as List;
    expect((activity.first as Map)['transferred_from'], ['abcd••••mnop']);
  });

  test('get_transaction uses the focused sale when no id is passed', () async {
    final c = container();
    addTearDown(c.dispose);
    focusSale(c);
    final result = await c.read(agentToolExecutorProvider).run(
      'get_transaction',
      {},
    );
    expect(
      (result['transaction'] as Map)['store_transaction_id'],
      '2000000123',
    );
  });

  test('get_transaction reports not_found for an unknown sale', () async {
    final c = container();
    addTearDown(c.dispose);
    final result = await c.read(agentToolExecutorProvider).run(
      'get_transaction',
      {'store_transaction_id': 'missing'},
    );
    expect(result['error'], 'not_found');
  });

  test('snapshot includes the focused store transaction id', () {
    final c = container();
    addTearDown(c.dispose);
    focusSale(c);
    final snap = c.read(agentToolExecutorProvider).snapshot();
    expect(snap['focus_store_transaction_id'], '2000000123');
  });

  test('repair compositor draws a transaction list from get_transaction', () {
    const repair = AgentRepairCompositor();
    final blocks = repair.blocksFromToolResults(
      resultsByToolName: {
        'get_transaction': {
          'transactions': [
            {'store_transaction_id': '2000000123'},
          ],
        },
      },
    );
    expect(
      blocks.any((b) => b.type == AgentPresentationType.transactionList),
      isTrue,
    );
  });
}

bool jsonContainsRawId(Map<String, dynamic> result) {
  return result.toString().contains(r'$RCAnonymousID:abcdefghijklmnop');
}
