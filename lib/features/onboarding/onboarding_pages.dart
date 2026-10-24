import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/core/utils/currency_format.dart';
import 'package:openrc/features/onboarding/onboarding_steps.dart';
import 'package:openrc/features/settings/widgets/appearance_pickers.dart';
import 'package:openrc/features/settings/widgets/currency_sheet.dart';
import 'package:openrc/services/commission_settings_store.dart';
import 'package:openrc/services/display_currency_store.dart';
import 'package:openrc/services/utilities_service.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/app_card.dart';
import 'package:openrc/widgets/app_logo.dart';
import 'package:openrc/widgets/pressable_scale.dart';

const kOnboardingColumnWidth = 520.0;

const _kQuickCurrencies = ['USD', 'EUR', 'GBP', 'JPY', 'CAD', 'AUD'];

class OnboardingWelcomePage extends StatelessWidget {
  const OnboardingWelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpace.lg),
        const Center(child: AppLogo(size: 72)),
        const SizedBox(height: AppSpace.xl),
        Text(
          'onboarding.welcome.title'.tr(),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
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
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: tt.titleMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.35,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: AppSpace.xxl),
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

class OnboardingAppearancePage extends ConsumerWidget {
  const OnboardingAppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final scheme = ref.watch(colorSchemeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PageHeader(
          icon: Icons.palette_rounded,
          title: 'onboarding.appearance.title'.tr(),
          subtitle: 'onboarding.appearance.subtitle'.tr(),
        ),
        ThemeModePicker(
          mode: mode,
          scheme: scheme,
          onChanged: (next) {
            UtilitiesService.hapticSelection();
            ref.read(themeModeProvider.notifier).state = next;
            ref.read(utilitiesServiceProvider).saveThemeMode(next);
          },
        ),
      ],
    );
  }
}

class OnboardingMoneyPage extends ConsumerWidget {
  const OnboardingMoneyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(displayCurrencyProvider);
    final fees = ref.watch(commissionSettingsProvider);
    final codes = [
      if (!_kQuickCurrencies.contains(currency)) currency,
      ..._kQuickCurrencies,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PageHeader(
          icon: Icons.payments_rounded,
          title: 'onboarding.money.title'.tr(),
          subtitle: 'onboarding.money.subtitle'.tr(),
        ),
        Text(
          'onboarding.money.currency'.tr(),
          textAlign: TextAlign.center,
          style: context.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.xs,
          runSpacing: AppSpace.xs,
          alignment: WrapAlignment.center,
          children: [
            for (final code in codes)
              _CurrencyChip(
                code: code,
                selected: currency == code,
                onTap: () {
                  UtilitiesService.hapticSelection();
                  ref.read(displayCurrencyProvider.notifier).setCurrency(code);
                },
              ),
            _CurrencyChip(
              code: 'onboarding.money.more'.tr(),
              selected: false,
              onTap: () => showDisplayCurrencySheet(context),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.xl),
        AppCard(
          onTap: () {
            UtilitiesService.hapticSelection();
            ref
                .read(commissionSettingsProvider.notifier)
                .setAdjustmentEnabled(!fees.adjustmentEnabled);
          },
          child: Row(
            children: [
              const _TileEmoji('🧾'),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'onboarding.money.fees'.tr(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'onboarding.money.feesHint'.tr(),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Switch(
                value: fees.adjustmentEnabled,
                onChanged: (value) {
                  UtilitiesService.hapticSelection();
                  ref
                      .read(commissionSettingsProvider.notifier)
                      .setAdjustmentEnabled(value);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CurrencyChip extends StatelessWidget {
  const _CurrencyChip({
    required this.code,
    required this.selected,
    required this.onTap,
  });

  final String code;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final option = lookupDisplayCurrencyOption(code);
    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.of(context, AppMotion.fast),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.12)
                : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: selected ? scheme.primary : context.appColors.hairline,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            option == null ? code : '${option.flagEmoji} $code',
            style: context.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: selected ? scheme.primary : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class OnboardingAiConsentPage extends StatelessWidget {
  const OnboardingAiConsentPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PageHeader(
          icon: Icons.auto_awesome_rounded,
          title: 'onboarding.aiConsent.title'.tr(),
          subtitle: 'onboarding.aiConsent.body'.tr(),
        ),
      ],
    );
  }
}

class OnboardingHelpUsGrowPage extends StatelessWidget {
  const OnboardingHelpUsGrowPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PageHeader(
          icon: Icons.share_rounded,
          title: 'onboarding.helpUsGrow.title'.tr(),
          subtitle: 'onboarding.helpUsGrow.body'.tr(),
        ),
      ],
    );
  }
}

class OnboardingReadyPage extends StatelessWidget {
  const OnboardingReadyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PageHeader(
          icon: Icons.check_circle_rounded,
          title: 'onboarding.ready.title'.tr(),
          subtitle: 'onboarding.ready.body'.tr(),
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
  const _PageHeader({
    required this.title,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xl, bottom: AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            _HeroIcon(icon!),
            const SizedBox(height: AppSpace.lg),
          ],
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
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
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
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
    return Text(
      emoji,
      style: const TextStyle(fontSize: 22, height: 1.15),
    );
  }
}

class _HeroIcon extends StatelessWidget {
  const _HeroIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Container(
      width: 76,
      height: 76,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 38, color: scheme.primary),
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
