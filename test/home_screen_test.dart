import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revenuecat/features/charts/home_notifier.dart';
import 'package:revenuecat/features/charts/home_screen.dart';
import 'package:revenuecat/models/rc_overview_response.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FixedHome extends HomeNotifier {
  _FixedHome(super.ref, HomeState initial) {
    state = initial;
  }

  int fetches = 0;

  @override
  Future<void> fetchData() async {
    fetches++;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_FixedHome> pump(WidgetTester tester, HomeState state) async {
    late _FixedHome notifier;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeProvider.overrideWith((ref) {
            notifier = _FixedHome(ref, state);
            return notifier;
          }),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();
    return notifier;
  }

  testWidgets('loading overview shows metric labels', (tester) async {
    await pump(
      tester,
      HomeState.initial().copyWith(isLoading: true),
    );
    expect(find.text('MRR'), findsOneWidget);
    expect(find.text('REVENUE'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('loaded overview shows MRR', (tester) async {
    await pump(
      tester,
      HomeState.initial().copyWith(
        overview: const RcOverviewResponse(mrr: 1200, subscriptions: 4),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('MRR'), findsOneWidget);
    expect(find.text('\$1.2K'), findsOneWidget);
    expect(find.text('4'), findsWidgets);
  });

  testWidgets('error state retries the overview load', (tester) async {
    final notifier = await pump(
      tester,
      HomeState.initial().copyWith(error: 'No internet connection.'),
    );
    final before = notifier.fetches;
    expect(find.text('Couldn\u2019t load your overview'), findsOneWidget);
    expect(find.text('No internet connection.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(notifier.fetches, before + 1);
  });
}
