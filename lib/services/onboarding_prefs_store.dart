import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local onboarding answers and funnel progress. SharedPreferences, same
/// pattern as [UtilitiesService]. There is no Firestore copy.
class OnboardingPrefs {
  const OnboardingPrefs({
    this.completed = false,
    this.lastStep,
    this.lastStepIndex,
    this.role,
    this.focus,
    this.aiConsentGranted = false,
    this.focusApplied = false,
    this.pendingHomeArrived = false,
  });

  final bool completed;
  final String? lastStep;
  final int? lastStepIndex;
  final String? role;
  final String? focus;
  final bool aiConsentGranted;
  final bool focusApplied;
  final bool pendingHomeArrived;

  bool get hasStarted => lastStep != null && lastStep!.isNotEmpty;

  OnboardingPrefs copyWith({
    bool? completed,
    String? lastStep,
    int? lastStepIndex,
    String? role,
    String? focus,
    bool? aiConsentGranted,
    bool? focusApplied,
    bool? pendingHomeArrived,
    bool clearLastStep = false,
    bool clearRole = false,
    bool clearFocus = false,
  }) {
    return OnboardingPrefs(
      completed: completed ?? this.completed,
      lastStep: clearLastStep ? null : (lastStep ?? this.lastStep),
      lastStepIndex: clearLastStep ? null : (lastStepIndex ?? this.lastStepIndex),
      role: clearRole ? null : (role ?? this.role),
      focus: clearFocus ? null : (focus ?? this.focus),
      aiConsentGranted: aiConsentGranted ?? this.aiConsentGranted,
      focusApplied: focusApplied ?? this.focusApplied,
      pendingHomeArrived: pendingHomeArrived ?? this.pendingHomeArrived,
    );
  }
}

final onboardingPrefsProvider =
    StateNotifierProvider<OnboardingPrefsNotifier, OnboardingPrefs>((ref) {
      return OnboardingPrefsNotifier();
    });

class OnboardingPrefsNotifier extends StateNotifier<OnboardingPrefs> {
  static const completedKey = 'onboarding_completed';
  static const lastStepKey = 'onboarding_last_step';
  static const lastStepIndexKey = 'onboarding_last_step_index';
  static const roleKey = 'onboarding_role';
  static const focusKey = 'onboarding_focus';
  static const aiConsentKey = 'ai_consent_granted';
  static const focusAppliedKey = 'onboarding_focus_applied';
  static const pendingHomeArrivedKey = 'onboarding_pending_home_arrived';
  static const completeStepId = 'complete';

  OnboardingPrefsNotifier() : super(const OnboardingPrefs()) {
    load();
  }

  /// In-memory snapshot for tests that should not hit SharedPreferences yet.
  OnboardingPrefsNotifier.loaded(super.state);

  bool get isCompleted => state.completed;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = OnboardingPrefs(
      completed: prefs.getBool(completedKey) ?? false,
      lastStep: _nonEmpty(prefs.getString(lastStepKey)),
      lastStepIndex: prefs.getInt(lastStepIndexKey),
      role: _nonEmpty(prefs.getString(roleKey)),
      focus: _nonEmpty(prefs.getString(focusKey)),
      aiConsentGranted: prefs.getBool(aiConsentKey) ?? false,
      focusApplied: prefs.getBool(focusAppliedKey) ?? false,
      pendingHomeArrived: prefs.getBool(pendingHomeArrivedKey) ?? false,
    );
  }

  /// Kill-proof last page. No-op once onboarding has finished.
  Future<void> recordProgress({
    required String step,
    required int stepIndex,
  }) async {
    if (state.completed) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(completedKey) ?? false) {
      state = state.copyWith(completed: true);
      return;
    }
    await prefs.setString(lastStepKey, step);
    await prefs.setInt(lastStepIndexKey, stepIndex);
    if (state.completed) return;
    state = state.copyWith(lastStep: step, lastStepIndex: stepIndex);
  }

  Future<void> saveRole(String role) async {
    if (state.completed) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(roleKey, role);
    if (state.completed) return;
    state = state.copyWith(role: role);
  }

  Future<void> saveFocus(String focus) async {
    if (state.completed) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(focusKey, focus);
    if (state.completed) return;
    state = state.copyWith(focus: focus);
  }

  Future<void> setAiConsentGranted(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(aiConsentKey, value);
    state = state.copyWith(aiConsentGranted: value);
  }

  /// First-launch finish. [fromWizard] arms `onboarding_home_arrived`.
  Future<void> markCompleted({
    String? role,
    String? focus,
    bool? aiConsentGranted,
    bool fromWizard = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(completedKey, true);
    await prefs.setString(lastStepKey, completeStepId);
    await prefs.setInt(lastStepIndexKey, -1);
    if (role != null) await prefs.setString(roleKey, role);
    if (focus != null) await prefs.setString(focusKey, focus);
    if (aiConsentGranted != null) {
      await prefs.setBool(aiConsentKey, aiConsentGranted);
    }
    if (fromWizard) {
      await prefs.setBool(pendingHomeArrivedKey, true);
      await prefs.setBool(focusAppliedKey, false);
    } else {
      await prefs.setBool(pendingHomeArrivedKey, false);
      await prefs.setBool(focusAppliedKey, true);
    }
    state = state.copyWith(
      completed: true,
      lastStep: completeStepId,
      lastStepIndex: -1,
      role: role ?? state.role,
      focus: focus ?? state.focus,
      aiConsentGranted: aiConsentGranted ?? state.aiConsentGranted,
      pendingHomeArrived: fromWizard,
      focusApplied: !fromWizard,
    );
  }

  /// Restored session or a remembered sign-in email: never show the wizard.
  Future<void> markCompletedForReturningUser() async {
    if (state.completed) return;
    await markCompleted(fromWizard: false);
  }

  Future<void> markFocusApplied() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(focusAppliedKey, true);
    state = state.copyWith(focusApplied: true);
  }

  Future<void> markHomeArrived() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(pendingHomeArrivedKey, false);
    state = state.copyWith(pendingHomeArrived: false);
  }

  /// Test-only. Production Settings has no reset for onboarding.
  @visibleForTesting
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(completedKey);
    await prefs.remove(lastStepKey);
    await prefs.remove(lastStepIndexKey);
    await prefs.remove(roleKey);
    await prefs.remove(focusKey);
    await prefs.remove(aiConsentKey);
    await prefs.remove(focusAppliedKey);
    await prefs.remove(pendingHomeArrivedKey);
    state = const OnboardingPrefs();
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}
