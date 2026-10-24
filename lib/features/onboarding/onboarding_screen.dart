import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/features/onboarding/onboarding_pages.dart';
import 'package:openrc/features/onboarding/onboarding_steps.dart';
import 'package:openrc/services/onboarding_analytics.dart';
import 'package:openrc/services/onboarding_prefs_store.dart';
import 'package:openrc/services/utilities_service.dart';
import 'package:openrc/theme/app_tokens.dart';

/// First-launch wizard. Settings replay uses [trackAnalytics] false so it
/// does not write last-step or fire begin.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.trackAnalytics = true});

  static const previewRouteName = '/onboarding-preview';

  final bool trackAnalytics;

  static Future<void> openPreview(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: previewRouteName),
        builder: (_) => const OnboardingScreen(trackAnalytics: false),
      ),
    );
  }

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late final List<OnboardingStep> _steps;
  late final String _platform;
  var _index = 0;
  String? _role;
  String? _focus;
  var _busy = false;

  bool get _track => widget.trackAnalytics;

  OnboardingStep get _step => _steps[_index];

  @override
  void initState() {
    super.initState();
    _steps = onboardingStepsForCurrentPlatform();
    _platform = onboardingPlatformName();
    final prefs = ref.read(onboardingPrefsProvider);
    _role = prefs.role;
    _focus = prefs.focus;
    if (_track) {
      if (prefs.hasStarted &&
          prefs.lastStep != OnboardingPrefsNotifier.completeStepId) {
        logOnboardingEvent(
          onboardingResumeEvent(
            lastStep: prefs.lastStep!,
            stepIndex: prefs.lastStepIndex ?? 0,
            platform: _platform,
          ),
          track: true,
        );
      } else {
        logOnboardingEvent(
          onboardingBeginEvent(
            stepCount: _steps.length,
            platform: _platform,
          ),
          track: true,
        );
      }
      _logStep();
    }
  }

  void _logStep() {
    if (!_track) return;
    final step = _step;
    logOnboardingEvent(
      onboardingStepViewEvent(
        step: step.id,
        stepIndex: _index,
        platform: _platform,
      ),
      track: true,
    );
    unawaited(
      ref
          .read(onboardingPrefsProvider.notifier)
          .recordProgress(step: step.id, stepIndex: _index),
    );
  }

  void _advance({String outcome = 'advance'}) {
    if (_busy) return;
    UtilitiesService.hapticLight();
    logOnboardingEvent(
      onboardingCtaEvent(step: _step.id, outcome: outcome),
      track: _track,
    );
    if (_index >= _steps.length - 1 || outcome == 'complete') {
      unawaited(_finish());
      return;
    }
    setState(() => _index++);
    _logStep();
  }

  void _back() {
    if (_index == 0) return;
    UtilitiesService.hapticLight();
    final from = _step;
    final to = _steps[_index - 1];
    logOnboardingEvent(
      onboardingBackEvent(fromStep: from.id, toStep: to.id),
      track: _track,
    );
    setState(() => _index--);
    _logStep();
  }

  Future<void> _finish() async {
    if (_busy) return;
    setState(() => _busy = true);
    if (_track) {
      final store = ref.read(onboardingPrefsProvider.notifier);
      await store.markCompleted(
        role: _role,
        focus: _focus,
        fromWizard: true,
      );
      logOnboardingEvent(
        onboardingCompleteEvent(
          platform: _platform,
          stepCount: _steps.length,
        ),
        track: true,
      );
    } else if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _skip() async {
    if (_busy) return;
    UtilitiesService.hapticLight();
    logOnboardingEvent(
      onboardingCtaEvent(step: _step.id, outcome: 'complete'),
      track: _track,
    );
    await _finish();
  }

  void _selectRole(String role) {
    setState(() => _role = role);
    if (_track) {
      unawaited(ref.read(onboardingPrefsProvider.notifier).saveRole(role));
      logOnboardingEvent(
        onboardingAnswerEvent(step: OnboardingStep.role.id, answer: role),
        track: true,
      );
    }
  }

  void _selectFocus(String focus) {
    setState(() => _focus = focus);
    if (_track) {
      unawaited(ref.read(onboardingPrefsProvider.notifier).saveFocus(focus));
      logOnboardingEvent(
        onboardingAnswerEvent(step: OnboardingStep.focus.id, answer: focus),
        track: true,
      );
    }
  }

  Future<void> _continueWithAsk() async {
    if (_track) {
      unawaited(
        ref.read(onboardingPrefsProvider.notifier).setAiConsentGranted(true),
      );
      logOnboardingEvent(
        onboardingAnswerEvent(
          step: OnboardingStep.aiConsent.id,
          answer: 'provided',
        ),
        track: true,
      );
    }
    _advance();
  }

  Future<void> _declineAsk() async {
    if (_track) {
      unawaited(
        ref.read(onboardingPrefsProvider.notifier).setAiConsentGranted(false),
      );
      logOnboardingEvent(
        onboardingAnswerEvent(step: OnboardingStep.aiConsent.id, answer: 'none'),
        track: true,
      );
    }
    _advance();
  }

  Future<void> _rate() async {
    logOnboardingEvent(
      onboardingAnswerEvent(
        step: OnboardingStep.helpUsGrow.id,
        answer: 'provided',
      ),
      track: _track,
    );
    try {
      final review = InAppReview.instance;
      if (await review.isAvailable()) {
        await review.requestReview();
      }
    } catch (_) {}
    if (!mounted) return;
    _advance();
  }

  void _rateLater() {
    logOnboardingEvent(
      onboardingAnswerEvent(step: OnboardingStep.helpUsGrow.id, answer: 'none'),
      track: _track,
    );
    _advance();
  }

  bool get _ctaEnabled {
    if (_busy) return false;
    return switch (_step) {
      OnboardingStep.role => _role != null,
      OnboardingStep.focus => _focus != null,
      _ => true,
    };
  }

  String get _ctaLabel => switch (_step) {
    OnboardingStep.role => onboardingRoleContinueLabel(_role),
    OnboardingStep.focus => onboardingFocusContinueLabel(_focus),
    OnboardingStep.aiConsent => 'onboarding.aiConsent.continue'.tr(),
    OnboardingStep.helpUsGrow => 'onboarding.helpUsGrow.rate'.tr(),
    OnboardingStep.ready => 'onboarding.ready.signIn'.tr(),
    _ => 'onboarding.continue'.tr(),
  };

  VoidCallback? get _onCta {
    if (!_ctaEnabled) return null;
    return switch (_step) {
      OnboardingStep.aiConsent => _continueWithAsk,
      OnboardingStep.helpUsGrow => _rate,
      OnboardingStep.ready => () => _advance(outcome: 'complete'),
      _ => _advance,
    };
  }

  String? get _secondaryLabel => switch (_step) {
    OnboardingStep.aiConsent => 'onboarding.aiConsent.notNow'.tr(),
    OnboardingStep.helpUsGrow => 'onboarding.helpUsGrow.later'.tr(),
    _ => null,
  };

  VoidCallback? get _onSecondary => switch (_step) {
    OnboardingStep.aiConsent => _declineAsk,
    OnboardingStep.helpUsGrow => _rateLater,
    _ => null,
  };

  Widget _page() {
    return switch (_step) {
      OnboardingStep.welcome => const OnboardingWelcomePage(),
      OnboardingStep.proof => const OnboardingProofPage(),
      OnboardingStep.role => OnboardingRolePage(
        selected: _role,
        onSelected: _selectRole,
      ),
      OnboardingStep.focus => OnboardingFocusPage(
        selected: _focus,
        onSelected: _selectFocus,
      ),
      OnboardingStep.showcase => const OnboardingShowcasePage(),
      OnboardingStep.appearance => const OnboardingAppearancePage(),
      OnboardingStep.money => const OnboardingMoneyPage(),
      OnboardingStep.aiConsent => const OnboardingAiConsentPage(),
      OnboardingStep.helpUsGrow => const OnboardingHelpUsGrowPage(),
      OnboardingStep.ready => const OnboardingReadyPage(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final page = _page();
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _back();
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.xs,
                  AppSpace.xxs,
                  AppSpace.sm,
                  0,
                ),
                child: _Chrome(
                  index: _index,
                  total: _steps.length,
                  showBack: _index > 0,
                  showSkip: _index == 0,
                  onBack: _back,
                  onSkip: _skip,
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final side = AppBreakpoints.centeringInset(
                      constraints.maxWidth,
                      maxWidth: kOnboardingColumnWidth,
                    );
                    return AnimatedSwitcher(
                      duration: reduce
                          ? Duration.zero
                          : AppMotion.duration,
                      switchInCurve: AppMotion.curve,
                      switchOutCurve: Curves.easeIn,
                      child: KeyedSubtree(
                        key: ValueKey(_step),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                              AppSpace.lg + side,
                              AppSpace.md,
                              AppSpace.lg + side,
                              AppSpace.md,
                            ),
                            child: _Entrance(child: page),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final side = AppBreakpoints.centeringInset(
                    constraints.maxWidth,
                    maxWidth: kOnboardingColumnWidth,
                  );
                  final bottomInset = MediaQuery.paddingOf(context).bottom;
                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpace.lg + side,
                      0,
                      AppSpace.lg + side,
                      bottomInset > 0 ? bottomInset : AppSpace.xs,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_secondaryLabel != null) ...[
                          TextButton(
                            onPressed: _busy ? null : _onSecondary,
                            child: Text(_secondaryLabel!),
                          ),
                        ],
                        _PillButton(
                          label: _ctaLabel,
                          onPressed: _onCta,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Entrance extends StatelessWidget {
  const _Entrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return child
        .animate()
        .fadeIn(duration: AppMotion.duration, curve: AppMotion.curve)
        .slide(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
          duration: AppMotion.duration,
          curve: AppMotion.curve,
        );
  }
}

class _Chrome extends StatelessWidget {
  const _Chrome({
    required this.index,
    required this.total,
    required this.showBack,
    required this.showSkip,
    required this.onBack,
    required this.onSkip,
  });

  final int index;
  final int total;
  final bool showBack;
  final bool showSkip;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: showBack
                    ? IconButton(
                        tooltip: 'onboarding.back'.tr(),
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back_rounded),
                      )
                    : null,
              ),
              Expanded(
                child: Text(
                  'onboarding.stepOf'.tr(
                    namedArgs: {
                      'current': '${index + 1}',
                      'total': '$total',
                    },
                  ),
                  textAlign: TextAlign.center,
                  style: context.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontFeatures: AppText.tabular,
                  ),
                ),
              ),
              SizedBox(
                width: 72,
                child: showSkip
                    ? TextButton(
                        onPressed: onSkip,
                        child: Text('onboarding.skip'.tr()),
                      )
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < total; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              AnimatedContainer(
                duration: AppMotion.of(context, AppMotion.fast),
                width: i == index ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: i == index
                      ? scheme.primary
                      : scheme.onSurface.withValues(alpha: 0.18),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          textStyle: context.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
