import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/onboarding/onboarding_pages.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(body: SingleChildScrollView(child: page)),
      ),
    );
    // Pages stagger their cards in; let those timers run out.
    await tester.pumpAndSettle();
  }

  testWidgets('the Ask consent page shows what Ask can answer', (tester) async {
    await pump(tester, const OnboardingAiConsentPage());

    expect(find.text('Ask'), findsOneWidget);
    expect(find.text('How was today vs yesterday?'), findsOneWidget);
    expect(find.text('What is my MRR trend?'), findsOneWidget);
  });

  testWidgets('the rating page shows the stars it asks for', (tester) async {
    await pump(tester, const OnboardingHelpUsGrowPage());

    expect(find.byIcon(Icons.star_rounded), findsNWidgets(5));
  });

  testWidgets('the last page repeats only the answers given', (tester) async {
    await pump(tester, const OnboardingReadyPage(role: 'indie'));
    expect(find.text('Indie'), findsOneWidget);
    expect(find.text('Charts'), findsNothing);

    await pump(tester, const OnboardingReadyPage());
    expect(find.text('Indie'), findsNothing);
  });

  testWidgets('a long title is not cut off', (tester) async {
    // The header used to cap titles at 3 lines with an ellipsis, which cut
    // translated ones (`onboarding.role.title`) in the middle.
    await pump(tester, const OnboardingProofPage());
    final title = tester.widget<Text>(
      find.text('Built to stay on your device'),
    );
    expect(title.maxLines, isNull);
    expect(title.overflow, isNull);
  });

  test('the column widths are ordered', () {
    expect(kOnboardingColumnWidth, lessThan(kOnboardingWideColumnWidth));
    expect(kOnboardingBandMaxHeight, greaterThan(kOnboardingWideColumnWidth));
  });
}
