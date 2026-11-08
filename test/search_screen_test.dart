import 'package:dio/dio.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/search/search_screen.dart';
import 'package:openrc/features/transactions/transactions_screen.dart';
import 'package:openrc/features/transactions/widgets/transaction_item.dart';
import 'package:openrc/features/upcoming/upcoming_provider.dart';
import 'package:openrc/models/rc_project.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/models/rc_transaction_detail.dart';
import 'package:openrc/models/rc_transaction_detail_activity.dart';
import 'package:openrc/services/exchange_rate_provider.dart';
import 'package:openrc/services/rc_account_projects_provider.dart';
import 'package:openrc/services/rc_api_service.dart';
import 'package:openrc/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Fixed extends TransactionsNotifier {
  _Fixed(super.ref, TransactionsState initial) {
    state = initial;
  }

  @override
  Future<void> fetchInitial({String source = 'manual'}) async {}
}

/// Knows one customer, `known-customer`, in `proj1`.
class _CustomerApi extends RcApiService {
  final lookups = <String>[];

  @override
  Future<RcTransactionDetailResponse> transactionDetail({
    required String projectId,
    required String subscriberId,
    bool sandboxMode = false,
  }) async {
    lookups.add('$projectId/$subscriberId');
    if (subscriberId != 'known-customer') {
      final options = RequestOptions(path: '/subscribers/$subscriberId');
      throw DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 404),
        type: DioExceptionType.badResponse,
      );
    }
    return const RcTransactionDetailResponse(dollarsSpent: 42);
  }

  @override
  Future<RcTransactionDetailActivityResponse> transactionDetailActivity({
    required String projectId,
    required String subscriberId,
    bool sandboxMode = false,
  }) async => const RcTransactionDetailActivityResponse();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_CustomerApi> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = _CustomerApi();
    final state = TransactionsState(
      selectedDayKey: '2026-11-02',
      hasMore: false,
      grouped: {
        '2026-11-02': [
          const RcTransaction(
            app: RcTransactionApp(id: 'proj1', name: 'Demo App'),
            storeTransactionIdentifier: 'GPA.1234-5678',
            subscriberId: 'loaded-customer',
            productIdentifier: 'pro.monthly',
            purchaseDate: '2026-11-02T10:00:00Z',
            store: 'Play Store',
            revenue: 4.99,
          ),
        ],
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rcApiServiceProvider.overrideWithValue(api),
          transactionsProvider.overrideWith((ref) => _Fixed(ref, state)),
          upcomingTransactionsProvider.overrideWith(
            (ref) => UpcomingNotifier.ready(
              ref,
              const UpcomingLoadState(loadComplete: true),
            ),
          ),
          rcAccountProjectsProvider.overrideWith(
            (ref) async => const [RcProject(id: 'proj1', name: 'Demo App')],
          ),
          usdExchangeRatesProvider.overrideWith((ref) async => const {}),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(FlexScheme.indigoM3),
          home: const SearchScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return api;
  }

  testWidgets('finds a loaded sale by its transaction id', (tester) async {
    await pump(tester);
    expect(find.text('Search transactions and customers'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'gpa.1234');
    await tester.pumpAndSettle();

    expect(find.text('1 match'), findsOneWidget);
    expect(find.byType(TransactionItem), findsOneWidget);
  });

  testWidgets('looks up a customer with no loaded sales', (tester) async {
    final api = await pump(tester);

    await tester.enterText(find.byType(TextField), 'known-customer');
    await tester.pumpAndSettle();
    expect(find.text('No loaded transactions match'), findsOneWidget);

    await tester.tap(find.text('Look up customer'));
    await tester.pumpAndSettle();

    expect(api.lookups, contains('proj1/known-customer'));
    expect(find.text('Customer'), findsOneWidget);
    expect(find.text('Total spent'), findsWidgets);
  });

  testWidgets('says when the customer is not in the project', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'nobody-here');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Look up customer'));
    await tester.pumpAndSettle();

    expect(
      find.text('No customer with this ID in Demo App.'),
      findsOneWidget,
    );
  });
}
