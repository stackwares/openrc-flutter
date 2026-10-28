import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/onboarding/onboarding_steps.dart';

void main() {
  const shared = [
    OnboardingStep.welcome,
    OnboardingStep.proof,
    OnboardingStep.role,
    OnboardingStep.focus,
    OnboardingStep.showcase,
  ];

  test('step ids are unique and stable', () {
    const ids = [
      'welcome',
      'proof',
      'role',
      'focus',
      'showcase',
      'ai_consent',
      'help_us_grow',
      'ready',
    ];
    expect(OnboardingStep.values.map((s) => s.id), ids);
    expect(ids.toSet().length, ids.length);
  });

  test('Apple inserts only ai_consent', () {
    const apple = [...shared, OnboardingStep.aiConsent, OnboardingStep.ready];
    expect(onboardingStepsFor(TargetPlatform.iOS, isWeb: false), apple);
    expect(onboardingStepsFor(TargetPlatform.macOS, isWeb: false), apple);
  });

  test('Android inserts only help_us_grow', () {
    expect(onboardingStepsFor(TargetPlatform.android, isWeb: false), [
      ...shared,
      OnboardingStep.helpUsGrow,
      OnboardingStep.ready,
    ]);
  });

  test('web and other platforms insert neither ask', () {
    const neither = [...shared, OnboardingStep.ready];
    expect(onboardingStepsFor(TargetPlatform.iOS, isWeb: true), neither);
    expect(onboardingStepsFor(TargetPlatform.android, isWeb: true), neither);
    expect(onboardingStepsFor(TargetPlatform.macOS, isWeb: true), neither);
    expect(onboardingStepsFor(TargetPlatform.windows, isWeb: false), neither);
    expect(onboardingStepsFor(TargetPlatform.linux, isWeb: false), neither);
  });

  test('consent and rating platforms follow native flags', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(isAppleAiConsentPlatform, isTrue);
    expect(isAndroidRatingPlatform, isFalse);

    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(isAppleAiConsentPlatform, isTrue);
    expect(isAndroidRatingPlatform, isFalse);

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(isAppleAiConsentPlatform, isFalse);
    expect(isAndroidRatingPlatform, isTrue);

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(isAppleAiConsentPlatform, isFalse);
    expect(isAndroidRatingPlatform, isFalse);
  });

  test('focus maps to the three main tabs', () {
    expect(onboardingTabIndexForFocus(OnboardingAnswers.focusLiveSales), 0);
    expect(onboardingTabIndexForFocus(OnboardingAnswers.focusRevenue), 1);
    expect(onboardingTabIndexForFocus(OnboardingAnswers.focusCharts), 2);
    expect(onboardingTabIndexForFocus(null), 0);
    expect(onboardingTabIndexForFocus('unknown'), 0);
  });
}
