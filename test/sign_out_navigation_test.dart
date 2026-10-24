import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:openrc/app/app.dart';
import 'package:openrc/app/main_shell.dart';
import 'package:openrc/features/charts/home_notifier.dart';
import 'package:openrc/features/settings/settings_screen.dart';
import 'package:openrc/features/sign_in/sign_in_screen.dart';
import 'package:openrc/features/transactions/transactions_screen.dart';
import 'package:openrc/models/agent_preset.dart';
import 'package:openrc/models/rc_me_response.dart';
import 'package:openrc/services/agent/agent_settings_store.dart';
import 'package:openrc/services/exchange_rate_provider.dart';
import 'package:openrc/services/rc_account_projects_provider.dart';
import 'package:openrc/services/rc_auth_service.dart';
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

class _FakeAgentSettings extends AgentSettingsNotifier {
  @override
  Future<AgentSettings> build() async => const AgentSettings(
        providerId: AgentProviderId.openrouter,
        model: '',
        customBaseUrl: '',
        customStyle: AgentApiStyle.openAi,
        useFasterModel: false,
        hasKey: true,
      );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'OpenRC',
      packageName: 'com.openrc.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
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
          agentSettingsProvider.overrideWith(_FakeAgentSettings.new),
        ],
        child: const OpenRcApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> signOut(WidgetTester tester) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    container.read(isSignedInProvider.notifier).state = false;
    await tester.pumpAndSettle();
  }

  testWidgets('signing out closes Settings and shows sign-in', (tester) async {
    await pumpAt(tester, const Size(430, 932));

    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .pushNamed(SettingsScreen.routeName);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    await signOut(tester);

    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('signing out closes the Settings dialog on wide windows', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1280, 800));

    SettingsScreen.open(tester.element(find.byType(MainShell)));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    await signOut(tester);

    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(SignInScreen), findsOneWidget);
  });
}
