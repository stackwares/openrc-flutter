import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revenuecat/features/transactions/transaction_detail_screen.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/models/rc_transaction_detail.dart';
import 'package:revenuecat/models/rc_transaction_detail_activity.dart';
import 'package:revenuecat/services/rc_api_service.dart';

class _SlowDetailApi extends RcApiService {
  final gate = Completer<void>();
  int created = 0;

  @override
  Future<RcTransactionDetailResponse> transactionDetail({
    required String projectId,
    required String subscriberId,
    bool sandboxMode = false,
  }) async {
    created++;
    await gate.future;
    return const RcTransactionDetailResponse();
  }

  @override
  Future<RcTransactionDetailActivityResponse> transactionDetailActivity({
    required String projectId,
    required String subscriberId,
    bool sandboxMode = false,
  }) async {
    await gate.future;
    return const RcTransactionDetailActivityResponse();
  }
}

void main() {
  test(
    'detail data is released when its screen closes, even mid-load',
    () async {
      final api = _SlowDetailApi();
      final container = ProviderContainer(
        overrides: [rcApiServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      const tx = RcTransaction(
        app: RcTransactionApp(id: 'proj'),
        subscriberId: 'sub',
      );

      final sub = container.listen(transactionDetailProvider(tx), (_, _) {});
      expect(api.created, 1);
      sub.close();
      await container.pump();

      // The late response must not touch the disposed notifier.
      api.gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Reopening loads fresh instead of reusing a kept-alive entry.
      container.listen(transactionDetailProvider(tx), (_, _) {});
      expect(api.created, 2);
    },
  );
}
