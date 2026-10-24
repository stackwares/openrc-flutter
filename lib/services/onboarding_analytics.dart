import 'package:flutter/foundation.dart';
import 'package:openrc/services/telemetry.dart';

/// Pure event payload. Unit-tested without PostHog.
class AnalyticsEvent {
  const AnalyticsEvent(this.name, [this.parameters = const {}]);

  final String name;
  final Map<String, Object> parameters;
}

/// `ios` / `android` / `web` / `macos` (and the other Flutter platforms).
String onboardingPlatformName({
  TargetPlatform? platform,
  bool? isWeb,
}) {
  if (isWeb ?? kIsWeb) return 'web';
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.iOS => 'ios',
    TargetPlatform.android => 'android',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.windows => 'windows',
    TargetPlatform.linux => 'linux',
    TargetPlatform.fuchsia => 'fuchsia',
  };
}

AnalyticsEvent onboardingBeginEvent({
  required int stepCount,
  required String platform,
}) => AnalyticsEvent('onboarding_begin', {
  'step_count': stepCount,
  'platform': platform,
});

AnalyticsEvent onboardingResumeEvent({
  required String lastStep,
  required int stepIndex,
  required String platform,
}) => AnalyticsEvent('onboarding_resume', {
  'last_step': lastStep,
  'step_index': stepIndex,
  'platform': platform,
});

AnalyticsEvent onboardingStepViewEvent({
  required String step,
  required int stepIndex,
  required String platform,
}) => AnalyticsEvent('onboarding_step_view', {
  'step': step,
  'step_index': stepIndex,
  'platform': platform,
});

/// [answer] is a categorical id, `provided`, or `none`. Never a name or email.
AnalyticsEvent onboardingAnswerEvent({
  required String step,
  required String answer,
}) => AnalyticsEvent('onboarding_answer', {
  'step': step,
  'answer': answer,
});

AnalyticsEvent onboardingCtaEvent({
  required String step,
  required String outcome,
}) => AnalyticsEvent('onboarding_cta', {
  'step': step,
  'outcome': outcome,
});

AnalyticsEvent onboardingBackEvent({
  required String fromStep,
  required String toStep,
}) => AnalyticsEvent('onboarding_back', {
  'from_step': fromStep,
  'to_step': toStep,
});

AnalyticsEvent onboardingCompleteEvent({
  required String platform,
  required int stepCount,
}) => AnalyticsEvent('onboarding_complete', {
  'platform': platform,
  'step_count': stepCount,
});

AnalyticsEvent onboardingHomeArrivedEvent() =>
    const AnalyticsEvent('onboarding_home_arrived');

/// Fire-and-forget. No-op when [track] is false or the user turned telemetry
/// off. Debug builds still print at [Telemetry.event].
void logOnboardingEvent(AnalyticsEvent event, {required bool track}) {
  if (!track) return;
  if (Telemetry.isAvailable && !Telemetry.enabled) return;
  Telemetry.event(event.name, event.parameters);
}
