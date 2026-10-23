import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:revenuecat/app/app.dart';
import 'package:revenuecat/features/charts/home_notifier.dart';
import 'package:revenuecat/features/settings/settings_screen.dart';
import 'package:revenuecat/features/sign_in/sign_in_screen.dart';
import 'package:revenuecat/features/transactions/transactions_screen.dart';
import 'package:revenuecat/models/rc_me_response.dart';
import 'package:revenuecat/services/exchange_rate_provider.dart';
import 'package:revenuecat/services/rc_account_projects_provider.dart';
import 'package:revenuecat/services/rc_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _IdleTransactions extends TransactionsNotifier {
  _IdleTransactions(super.ref) {
    state = TransactionsState(
      selectedDayKey: state.selectedDayKey,
      hasMore: false,
      realtimeLoadComplete: true,
    );
  }

  @override
  Future<void> fetchInitial() async {}
}

class _IdleHome extends HomeNotifier {
  _IdleHome(super.ref);

  @override
  Future<void> fetchData() async {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'RevenueCat',
      packageName: 'com.example.revenuecat',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('signing out closes Settings and shows sign-in', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isSignedInProvider.overrideWith((ref) => true),
          rcMeProvider.overrideWith(
            (ref) => const RcMeResponse(email: 'ada@example.com'),
          ),
          transactionsProvider.overrideWith((ref) => _IdleTransactions(ref)),
          homeProvider.overrideWith((ref) => _IdleHome(ref)),
          rcAccountProjectsProvider.overrideWith((ref) async => const []),
          usdExchangeRatesProvider.overrideWith((ref) async => const {}),
        ],
        child: const RevenueCatApp(),
      ),
    );
    await tester.pumpAndSettle();

    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .pushNamed(SettingsScreen.routeName);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    container.read(isSignedInProvider.notifier).state = false;
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(SignInScreen), findsOneWidget);
  });
}
