import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/app/app.dart';
import 'package:openrc/app/floating_tab_chrome.dart';
import 'package:openrc/app/main_shell.dart';
import 'package:openrc/features/charts/home_notifier.dart';
import 'package:openrc/features/settings/settings_screen.dart';
import 'package:openrc/features/transactions/transactions_screen.dart';
import 'package:openrc/models/rc_me_response.dart';
import 'package:openrc/models/agent_preset.dart';
import 'package:openrc/services/agent/agent_settings_store.dart';
import 'package:openrc/services/exchange_rate_provider.dart';
import 'package:openrc/services/rc_account_projects_provider.dart';
import 'package:openrc/services/rc_auth_service.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:package_info_plus/package_info_plus.dart';
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

  Future<ProviderContainer> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isSignedInProvider.overrideWith((ref) => true),
          rcMeProvider.overrideWith(
            (ref) => const RcMeResponse(
              name: 'Ada Lovelace',
              email: 'ada@example.com',
            ),
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
    return ProviderScope.containerOf(tester.element(find.byType(MainShell)));
  }

  testWidgets('phones get the floating tab bar', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    expect(find.byType(FloatingTabChrome), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byTooltip('Settings'), findsOneWidget);
  });

  testWidgets('tablets get a navigation rail with Settings', (tester) async {
    await pumpAt(tester, const Size(820, 1180));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(FloatingTabChrome), findsNothing);
    // One Settings button, in the rail rather than the header.
    expect(find.byTooltip('Settings'), findsOneWidget);
  });

  testWidgets('wide windows get a sidebar that switches tabs', (tester) async {
    final container = await pumpAt(tester, const Size(1280, 800));
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(FloatingTabChrome), findsNothing);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    // The account opens Settings, so there is no separate row for it.
    expect(find.text('Settings'), findsNothing);

    await tester.tap(find.text('Charts'));
    await tester.pumpAndSettle();
    expect(container.read(mainShellTabIndexProvider), 2);
  });

  testWidgets('phones open Settings on its own screen', (tester) async {
    // Wide enough for the theme picker in the test font, as in
    // settings_screen_test.
    await pumpAt(tester, const Size(430, 932));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('tablets open Settings from the rail in a dialog', (
    tester,
  ) async {
    await pumpAt(tester, const Size(820, 1180));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(SettingsScreen),
      ),
      findsOneWidget,
    );
  });

  testWidgets('wide windows open Settings from the account in a dialog', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1280, 800));
    await tester.tap(find.text('Ada Lovelace'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(SettingsScreen),
      ),
      findsOneWidget,
    );
    expect(find.byType(BackButton), findsNothing);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
  });

  testWidgets('keyboard shortcuts switch tabs', (tester) async {
    final container = await pumpAt(tester, const Size(1280, 800));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(container.read(mainShellTabIndexProvider), 1);
  });

  testWidgets('resizing across breakpoints keeps the selected tab', (
    tester,
  ) async {
    final container = await pumpAt(tester, const Size(390, 844));
    container.read(mainShellTabIndexProvider.notifier).state = 1;
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();
    expect(find.byType(FloatingTabChrome), findsNothing);
    expect(container.read(mainShellTabIndexProvider), 1);
  });

  test('only phone-sized screens count as phones', () {
    expect(isPhoneSized(const Size(390, 844)), isTrue);
    expect(isPhoneSized(const Size(844, 390)), isTrue);
    expect(isPhoneSized(const Size(820, 1180)), isFalse);
    expect(isPhoneSized(const Size(1280, 800)), isFalse);
  });
}
