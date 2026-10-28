import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/core/utils/currency_format.dart';
import 'package:openrc/features/onboarding/onboarding_steps.dart';
import 'package:openrc/services/utilities_service.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/app_card.dart';
import 'package:openrc/widgets/app_logo.dart';

/// Reading width of the wizard's column on phones and tablets.
const kOnboardingColumnWidth = 520.0;

/// The same column in a wide window: a little wider, still one measure.
const kOnboardingWideColumnWidth = 560.0;

/// Tallest the wizard's band grows before it centers in the window.
///
/// Chrome, page and call to action share the band, so on a tall screen the
/// button stays under the page it acts on instead of sinking to the bottom
/// edge, a window's height away from it.
const kOnboardingBandMaxHeight = 780.0;

class OnboardingWelcomePage extends StatelessWidget {
  const OnboardingWelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    // A short window (a phone in landscape) keeps the mark small, so the
    // headline and the first chips are in view without scrolling.
    final tight = MediaQuery.sizeOf(context).height < 700;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: tight ? AppSpace.xs : AppSpace.md),
        Center(child: AppLogo(size: tight ? 56 : 72)),
        SizedBox(height: tight ? AppSpace.md : AppSpace.xl),
        Text(
          'onboarding.welcome.title'.tr(),
          textAlign: TextAlign.center,
          style: tt.headlineLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            height: 1.1,
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          'onboarding.welcome.subtitle'.tr(),
          textAlign: TextAlign.center,
          style: tt.titleMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.35,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: tight ? AppSpace.lg : AppSpace.xxl),
        Wrap(
          spacing: AppSpace.xs,
          runSpacing: AppSpace.xs,
          alignment: WrapAlignment.center,
          children: [
            _CapabilityChip(
              emoji: '⚡️',
              label: 'onboarding.welcome.chips.liveSales'.tr(),
            ),
            _CapabilityChip(
              emoji: '💵',
              label: 'onboarding.welcome.chips.proceeds'.tr(),
            ),
            _CapabilityChip(
              emoji: '📅',
              label: 'onboarding.welcome.chips.payouts'.tr(),
            ),
            _CapabilityChip(
              emoji: '📈',
              label: 'onboarding.welcome.chips.charts'.tr(),
            ),
          ],
        ),
      ],
    );
  }
}

class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip({required this.emoji, required this.label});

  final String emoji;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: context.appColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14, height: 1)),
          const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class OnboardingProofPage extends StatelessWidget {
  const OnboardingProofPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PageHeader(
          icon: Icons.shield_rounded,
          title: 'onboarding.proof.title'.tr(),
        ),
        _FactCard(
          emoji: '⚡️',
          title: 'onboarding.proof.sales.title'.tr(),
          body: 'onboarding.proof.sales.body'.tr(),
        ).appListItemEntrance(0),
        const SizedBox(height: AppSpace.sm),
        _FactCard(
          emoji: '📱',
          title: 'onboarding.proof.local.title'.tr(),
          body: 'onboarding.proof.local.body'.tr(),
        ).appListItemEntrance(1),
        const SizedBox(height: AppSpace.sm),
        _FactCard(
          emoji: '🔐',
          title: 'onboarding.proof.password.title'.tr(),
          body: 'onboarding.proof.password.body'.tr(),
        ).appListItemEntrance(2),
      ],
    );
  }
}

class _FactCard extends StatelessWidget {
  const _FactCard({
    required this.emoji,
    required this.title,
    required this.body,
  });

  final String emoji;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TileEmoji(emoji),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OnboardingRolePage extends StatelessWidget {
  const OnboardingRolePage({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PageHeader(
          icon: Icons.waving_hand_rounded,
          title: 'onboarding.role.title'.tr(),
          subtitle: 'onboarding.role.subtitle'.tr(),
        ),
        OnboardingOptionCard(
          emoji: '🧑‍💻',
          title: 'onboarding.role.indie'.tr(),
          subtitle: 'onboarding.role.indieHint'.tr(),
          selected: selected == OnboardingAnswers.roleIndie,
          onTap: () => onSelected(OnboardingAnswers.roleIndie),
        ),
        const SizedBox(height: AppSpace.sm),
        OnboardingOptionCard(
          emoji: '👥',
          title: 'onboarding.role.studio'.tr(),
          subtitle: 'onboarding.role.studioHint'.tr(),
          selected: selected == OnboardingAnswers.roleStudio,
          onTap: () => onSelected(OnboardingAnswers.roleStudio),
        ),
        const SizedBox(height: AppSpace.sm),
        OnboardingOptionCard(
          emoji: '🏢',
          title: 'onboarding.role.agency'.tr(),
          subtitle: 'onboarding.role.agencyHint'.tr(),
          selected: selected == OnboardingAnswers.roleAgency,
          onTap: () => onSelected(OnboardingAnswers.roleAgency),
        ),
        const SizedBox(height: AppSpace.sm),
        OnboardingOptionCard(
          emoji: '📊',
          title: 'onboarding.role.finance'.tr(),
          subtitle: 'onboarding.role.financeHint'.tr(),
          selected: selected == OnboardingAnswers.roleFinance,
          onTap: () => onSelected(OnboardingAnswers.roleFinance),
        ),
      ],
    );
  }
}

class OnboardingFocusPage extends StatelessWidget {
  const OnboardingFocusPage({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PageHeader(
          icon: Icons.track_changes_rounded,
          title: 'onboarding.focus.title'.tr(),
          subtitle: 'onboarding.focus.subtitle'.tr(),
        ),
        OnboardingOptionCard(
          emoji: '⚡️',
          title: 'onboarding.focus.liveSales'.tr(),
          subtitle: 'onboarding.focus.liveSalesHint'.tr(),
          selected: selected == OnboardingAnswers.focusLiveSales,
          onTap: () => onSelected(OnboardingAnswers.focusLiveSales),
        ),
        const SizedBox(height: AppSpace.sm),
        OnboardingOptionCard(
          emoji: '💰',
          title: 'onboarding.focus.revenue'.tr(),
          subtitle: 'onboarding.focus.revenueHint'.tr(),
          selected: selected == OnboardingAnswers.focusRevenue,
          onTap: () => onSelected(OnboardingAnswers.focusRevenue),
        ),
        const SizedBox(height: AppSpace.sm),
        OnboardingOptionCard(
          emoji: '📈',
          title: 'onboarding.focus.charts'.tr(),
          subtitle: 'onboarding.focus.chartsHint'.tr(),
          selected: selected == OnboardingAnswers.focusCharts,
          onTap: () => onSelected(OnboardingAnswers.focusCharts),
        ),
      ],
    );
  }
}

class OnboardingShowcasePage extends StatelessWidget {
  const OnboardingShowcasePage({super.key});

  static const _bars = [0.42, 0.55, 0.38, 0.7, 0.48, 0.62, 0.88];

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PageHeader(
          icon: Icons.bar_chart_rounded,
          title: 'onboarding.showcase.title'.tr(),
          subtitle: 'onboarding.showcase.subtitle'.tr(),
        ),
        IgnorePointer(
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    'onboarding.showcase.example'.tr(),
                    style: context.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  'onboarding.showcase.today'.tr(),
                  style: context.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatExactUsd(1248.50),
                  style: AppText.amount(context, size: 36),
                ),
                const SizedBox(height: AppSpace.lg),
                SizedBox(
                  height: 56,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final (i, t) in _bars.indexed)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Container(
                              height: 16 + t * 40,
                              decoration: BoxDecoration(
                                color: i == _bars.length - 1
                                    ? scheme.primary
                                    : scheme.primary.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class OnboardingAiConsentPage extends StatelessWidget {
  const OnboardingAiConsentPage({super.key});

  /// Questions Ask already offers, so the ask shows what it buys instead of
  /// only describing it.
  static const _questions = [
    'agent.suggestions.today',
    'agent.suggestions.mrr',
    'agent.suggestions.countries',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PageHeader(
          icon: Icons.auto_awesome_rounded,
          title: 'onboarding.aiConsent.title'.tr(),
          subtitle: 'onboarding.aiConsent.body'.tr(),
        ),
        IgnorePointer(
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    'agent.askAbout'.tr(),
                    style: context.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                Wrap(
                  spacing: AppSpace.xs,
                  runSpacing: AppSpace.xs,
                  children: [
                    for (final key in _questions)
                      _QuestionChip(label: key.tr()),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One question Ask could answer, drawn as the app draws a suggestion.
class _QuestionChip extends StatelessWidget {
  const _QuestionChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: context.appColors.hairline),
      ),
      child: Text(
        label,
        style: context.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class OnboardingHelpUsGrowPage extends StatelessWidget {
  const OnboardingHelpUsGrowPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PageHeader(
          icon: Icons.share_rounded,
          title: 'onboarding.helpUsGrow.title'.tr(),
          subtitle: 'onboarding.helpUsGrow.body'.tr(),
        ),
        IgnorePointer(
          child: AppCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 5; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.star_rounded,
                      size: 32,
                      color: scheme.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class OnboardingReadyPage extends StatelessWidget {
  const OnboardingReadyPage({super.key, this.role, this.focus});

  /// What the two questions were answered with, so the last page repeats the
  /// choices back instead of only announcing the end.
  final String? role;
  final String? focus;

  @override
  Widget build(BuildContext context) {
    final roleLabel = onboardingRoleLabel(role);
    final focusLabel = onboardingFocusLabel(focus);
    final answers = [?roleLabel, ?focusLabel];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PageHeader(
          icon: Icons.check_circle_rounded,
          title: 'onboarding.ready.title'.tr(),
          subtitle: 'onboarding.ready.body'.tr(),
        ),
        if (answers.isNotEmpty)
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            alignment: WrapAlignment.center,
            children: [
              for (final answer in answers)
                _CapabilityChip(emoji: '✓', label: answer),
            ],
          ),
      ],
    );
  }
}

class OnboardingOptionCard extends StatelessWidget {
  const OnboardingOptionCard({
    super.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final duration = AppMotion.of(context, AppMotion.fast);
    return AppCard(
      onTap: () {
        UtilitiesService.hapticSelection();
        onTap();
      },
      borderColor: selected ? scheme.primary : null,
      borderWidth: selected ? 1.5 : 1,
      child: Row(
        children: [
          _TileEmoji(emoji),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          AnimatedSwitcher(
            duration: duration,
            child: Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              key: ValueKey(selected),
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title, this.subtitle, this.icon});

  final String title;
  final String? subtitle;
  final IconData? icon;

  /// Below this height the header tightens, as an Apple device in landscape or
  /// a small desktop window has little to spare.
  static const _tightHeight = 700.0;

  @override
  Widget build(BuildContext context) {
    final tight = MediaQuery.sizeOf(context).height < _tightHeight;
    return Padding(
      padding: EdgeInsets.only(
        top: tight ? AppSpace.md : AppSpace.xl,
        bottom: tight ? AppSpace.md : AppSpace.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            _HeroIcon(icon!, size: tight ? 56 : 76),
            SizedBox(height: tight ? AppSpace.md : AppSpace.lg),
          ],
          // No line limit: the page scrolls, and a long translation
          // (`onboarding.role.title` in Hindi, say) would only get cut.
          Text(
            title,
            textAlign: TextAlign.center,
            style: context.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              height: 1.15,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: context.textTheme.bodyLarge?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TileEmoji extends StatelessWidget {
  const _TileEmoji(this.emoji);

  final String emoji;

  @override
  Widget build(BuildContext context) {
    return Text(emoji, style: const TextStyle(fontSize: 22, height: 1.15));
  }
}

class _HeroIcon extends StatelessWidget {
  const _HeroIcon(this.icon, {this.size = 76});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: size / 2, color: scheme.primary),
    );
  }
}

String onboardingRoleContinueLabel(String? role) => switch (role) {
  OnboardingAnswers.roleIndie => 'onboarding.role.continueIndie'.tr(),
  OnboardingAnswers.roleStudio => 'onboarding.role.continueStudio'.tr(),
  OnboardingAnswers.roleAgency => 'onboarding.role.continueAgency'.tr(),
  OnboardingAnswers.roleFinance => 'onboarding.role.continueFinance'.tr(),
  _ => 'onboarding.continue'.tr(),
};

String onboardingFocusContinueLabel(String? focus) => switch (focus) {
  OnboardingAnswers.focusLiveSales => 'onboarding.focus.continueLiveSales'.tr(),
  OnboardingAnswers.focusRevenue => 'onboarding.focus.continueRevenue'.tr(),
  OnboardingAnswers.focusCharts => 'onboarding.focus.continueCharts'.tr(),
  _ => 'onboarding.continue'.tr(),
};

/// What a role answer is called, or null when none was given.
String? onboardingRoleLabel(String? role) => switch (role) {
  OnboardingAnswers.roleIndie => 'onboarding.role.indie'.tr(),
  OnboardingAnswers.roleStudio => 'onboarding.role.studio'.tr(),
  OnboardingAnswers.roleAgency => 'onboarding.role.agency'.tr(),
  OnboardingAnswers.roleFinance => 'onboarding.role.finance'.tr(),
  _ => null,
};

/// What a focus answer is called, or null when none was given.
String? onboardingFocusLabel(String? focus) => switch (focus) {
  OnboardingAnswers.focusLiveSales => 'onboarding.focus.liveSales'.tr(),
  OnboardingAnswers.focusRevenue => 'onboarding.focus.revenue'.tr(),
  OnboardingAnswers.focusCharts => 'onboarding.focus.charts'.tr(),
  _ => null,
};
