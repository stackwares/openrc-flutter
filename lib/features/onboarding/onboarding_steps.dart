import 'package:flutter/foundation.dart';

/// Stable snake_case ids for the first-launch wizard and its funnel.
enum OnboardingStep {
  welcome,
  proof,
  role,
  focus,
  showcase,
  appearance,
  money,
  aiConsent,
  helpUsGrow,
  ready,
}

extension OnboardingStepX on OnboardingStep {
  /// Funnel id. Do not rename: drop-off attaches to these strings.
  String get id => switch (this) {
    OnboardingStep.welcome => 'welcome',
    OnboardingStep.proof => 'proof',
    OnboardingStep.role => 'role',
    OnboardingStep.focus => 'focus',
    OnboardingStep.showcase => 'showcase',
    OnboardingStep.appearance => 'appearance',
    OnboardingStep.money => 'money',
    OnboardingStep.aiConsent => 'ai_consent',
    OnboardingStep.helpUsGrow => 'help_us_grow',
    OnboardingStep.ready => 'ready',
  };
}

/// Categorical survey ids stored locally and sent as event answers.
abstract final class OnboardingAnswers {
  static const roleIndie = 'indie';
  static const roleStudio = 'small_studio';
  static const roleAgency = 'agency';
  static const roleFinance = 'finance_ops';

  static const focusLiveSales = 'live_sales';
  static const focusRevenue = 'revenue_payouts';
  static const focusCharts = 'charts';

  static const List<String> roles = [
    roleIndie,
    roleStudio,
    roleAgency,
    roleFinance,
  ];

  static const List<String> focuses = [
    focusLiveSales,
    focusRevenue,
    focusCharts,
  ];
}

/// Ask consent is an Apple-only functional ask, never shown or enforced
/// on web even when the browser is running on an Apple OS.
bool get isAppleAiConsentPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// Android-only rating ask. Omitted on Apple platforms and on web.
bool get isAndroidRatingPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Wizard pages for this install. Apple and Android each insert one extra
/// functional ask; web shows neither.
List<OnboardingStep> onboardingStepsFor(
  TargetPlatform platform, {
  required bool isWeb,
}) {
  return [
    OnboardingStep.welcome,
    OnboardingStep.proof,
    OnboardingStep.role,
    OnboardingStep.focus,
    OnboardingStep.showcase,
    OnboardingStep.appearance,
    OnboardingStep.money,
    if (!isWeb &&
        (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS))
      OnboardingStep.aiConsent,
    if (!isWeb && platform == TargetPlatform.android) OnboardingStep.helpUsGrow,
    OnboardingStep.ready,
  ];
}

List<OnboardingStep> onboardingStepsForCurrentPlatform() => onboardingStepsFor(
  defaultTargetPlatform,
  isWeb: kIsWeb,
);

int onboardingTabIndexForFocus(String? focus) => switch (focus) {
  OnboardingAnswers.focusLiveSales => 0,
  OnboardingAnswers.focusRevenue => 1,
  OnboardingAnswers.focusCharts => 2,
  _ => 0,
};
