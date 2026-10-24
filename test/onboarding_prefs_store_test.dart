import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/services/onboarding_prefs_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('progress round-trips through SharedPreferences', () async {
    final store = OnboardingPrefsNotifier.loaded(const OnboardingPrefs());
    await store.recordProgress(step: 'role', stepIndex: 2);
    await store.saveRole('indie');
    await store.saveFocus('charts');

    expect(store.state.lastStep, 'role');
    expect(store.state.lastStepIndex, 2);
    expect(store.state.role, 'indie');
    expect(store.state.focus, 'charts');
    expect(store.state.hasStarted, isTrue);

    final restored = OnboardingPrefsNotifier.loaded(const OnboardingPrefs());
    await restored.load();
    expect(restored.state.lastStep, 'role');
    expect(restored.state.lastStepIndex, 2);
    expect(restored.state.role, 'indie');
    expect(restored.state.focus, 'charts');
  });

  test('empty stored strings are treated as missing', () async {
    SharedPreferences.setMockInitialValues({
      OnboardingPrefsNotifier.lastStepKey: '   ',
      OnboardingPrefsNotifier.roleKey: '',
      OnboardingPrefsNotifier.focusKey: ' ',
    });
    final store = OnboardingPrefsNotifier.loaded(const OnboardingPrefs());
    await store.load();
    expect(store.state.lastStep, isNull);
    expect(store.state.role, isNull);
    expect(store.state.focus, isNull);
    expect(store.state.hasStarted, isFalse);
  });

  test('markCompleted sticks and later progress is a no-op', () async {
    final store = OnboardingPrefsNotifier.loaded(const OnboardingPrefs());
    await store.markCompleted(role: 'indie', focus: 'charts');

    expect(store.state.completed, isTrue);
    expect(store.state.lastStep, OnboardingPrefsNotifier.completeStepId);
    expect(store.state.lastStepIndex, -1);
    expect(store.state.role, 'indie');
    expect(store.state.focus, 'charts');
    expect(store.state.pendingHomeArrived, isTrue);
    expect(store.state.focusApplied, isFalse);

    await store.recordProgress(step: 'welcome', stepIndex: 0);
    await store.saveRole('agency');
    await store.saveFocus('live_sales');
    expect(store.state.lastStep, OnboardingPrefsNotifier.completeStepId);
    expect(store.state.role, 'indie');
    expect(store.state.focus, 'charts');

    final restored = OnboardingPrefsNotifier.loaded(const OnboardingPrefs());
    await restored.load();
    expect(restored.state.completed, isTrue);
    expect(restored.state.lastStep, OnboardingPrefsNotifier.completeStepId);
    expect(restored.state.role, 'indie');
  });

  test('returning users skip the home-arrived pulse', () async {
    final store = OnboardingPrefsNotifier.loaded(const OnboardingPrefs());
    await store.markCompletedForReturningUser();
    expect(store.state.completed, isTrue);
    expect(store.state.pendingHomeArrived, isFalse);
    expect(store.state.focusApplied, isTrue);

    await store.markCompletedForReturningUser();
    expect(store.state.pendingHomeArrived, isFalse);
  });

  test('reset is test-only and clears every key', () async {
    final store = OnboardingPrefsNotifier.loaded(const OnboardingPrefs());
    await store.markCompleted(
      role: 'indie',
      focus: 'charts',
      aiConsentGranted: true,
    );
    await store.reset();

    expect(store.state.completed, isFalse);
    expect(store.state.lastStep, isNull);
    expect(store.state.role, isNull);
    expect(store.state.focus, isNull);
    expect(store.state.aiConsentGranted, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(OnboardingPrefsNotifier.completedKey), isNull);
    expect(prefs.getString(OnboardingPrefsNotifier.lastStepKey), isNull);
    expect(prefs.getString(OnboardingPrefsNotifier.roleKey), isNull);
  });
}
