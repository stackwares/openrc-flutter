import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/services/onboarding_analytics.dart';

void main() {
  test('platform names stay anonymous device classes', () {
    expect(onboardingPlatformName(platform: TargetPlatform.iOS, isWeb: false), 'ios');
    expect(
      onboardingPlatformName(platform: TargetPlatform.android, isWeb: false),
      'android',
    );
    expect(
      onboardingPlatformName(platform: TargetPlatform.macOS, isWeb: false),
      'macos',
    );
    expect(onboardingPlatformName(platform: TargetPlatform.iOS, isWeb: true), 'web');
  });

  test('funnel payloads are categorical ids only', () {
    expect(
      onboardingBeginEvent(stepCount: 9, platform: 'ios').name,
      'onboarding_begin',
    );
    expect(onboardingBeginEvent(stepCount: 9, platform: 'ios').parameters, {
      'step_count': 9,
      'platform': 'ios',
    });

    expect(
      onboardingResumeEvent(
        lastStep: 'role',
        stepIndex: 2,
        platform: 'android',
      ).parameters,
      {'last_step': 'role', 'step_index': 2, 'platform': 'android'},
    );

    expect(
      onboardingAnswerEvent(step: 'role', answer: 'indie').parameters,
      {'step': 'role', 'answer': 'indie'},
    );
    expect(
      onboardingAnswerEvent(step: 'ai_consent', answer: 'none').parameters,
      {'step': 'ai_consent', 'answer': 'none'},
    );

    expect(onboardingHomeArrivedEvent().name, 'onboarding_home_arrived');
    expect(onboardingHomeArrivedEvent().parameters, isEmpty);
  });

  test('track:false never reaches Telemetry', () {
    final prints = <String>[];
    final previous = debugPrint;
    addTearDown(() => debugPrint = previous);
    debugPrint = (message, {wrapWidth}) {
      if (message != null) prints.add(message);
    };

    logOnboardingEvent(
      onboardingBeginEvent(stepCount: 9, platform: 'ios'),
      track: false,
    );
    expect(prints.where((line) => line.contains('[ANALYTICS]')), isEmpty);
  });
}
