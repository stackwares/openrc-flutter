import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/features/transactions/transaction_detail_screen.dart';
import 'package:openrc/features/transactions/widgets/transaction_item.dart';
import 'package:openrc/features/upcoming/upcoming_projection.dart';
import 'package:openrc/features/upcoming/upcoming_screen.dart';
import 'package:openrc/services/commission_settings_store.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/animated_reveal.dart';
import 'package:openrc/widgets/dual_currency_text.dart';
import 'package:openrc/widgets/side_panel.dart';

void _openSource(BuildContext context, UpcomingEvent event) => openDetail(
  context,
  (context) => TransactionDetailScreen(transaction: event.source),
);

/// Today's hero card line: where the day should end up once the renewals
/// and conversions still due today go through.
class UpcomingTodayForecast extends ConsumerWidget {
  const UpcomingTodayForecast({
    super.key,
    required this.soFar,
    required this.events,
  });

  /// Today's net revenue so far.
  final double soFar;

  /// Events still due today.
  final List<UpcomingEvent> events;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = UpcomingSummary.of(
      events,
      commission: ref.watch(commissionSettingsProvider),
    );
    if (summary.expectedUsd <= 0.005) return const SizedBox.shrink();
    final scheme = context.colorScheme;
    final muted = context.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
      fontFeatures: AppText.tabular,
    );
    final strong = muted?.copyWith(
      color: scheme.onSurface,
      fontWeight: FontWeight.w700,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 2,
        children: [
          Icon(Icons.trending_up_rounded, size: 15, color: scheme.primary),
          Text('upcoming.onTrackFor'.tr(), style: muted),
          DualCurrencyExactText(
            amount: soFar + summary.expectedUsd,
            applyCommissionAdjustment: false,
            style: strong,
          ),
          Text('·', style: muted),
          DualCurrencyExactText(
            amount: summary.expectedUsd,
            applyCommissionAdjustment: false,
            style: muted,
          ),
          Text('upcoming.stillDueToday'.tr(), style: muted),
        ],
      ),
    );
  }
}

/// Collapsible card of today's renewals, conversions and lapses still to
/// come, under the day's tiles.
class UpcomingDueTodaySection extends ConsumerWidget {
  const UpcomingDueTodaySection({
    super.key,
    required this.events,
    required this.expanded,
    required this.onExpandedChanged,
    this.margin = const EdgeInsets.fromLTRB(16, 12, 16, 0),
  });

  final List<UpcomingEvent> events;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.colorScheme;
    final summary = UpcomingSummary.of(
      events,
      commission: ref.watch(commissionSettingsProvider),
    );
    final muted = TextStyle(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
    );
    return Card(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => onExpandedChanged(!expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Icon(
                    Icons.event_repeat_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: 'upcoming.dueLaterToday'.tr(),
                        children: [
                          TextSpan(text: '  ${events.length}', style: muted),
                        ],
                      ),
                      style: context.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (summary.expectedUsd > 0.005)
                    DualCurrencyExactText(
                      amount: summary.expectedUsd,
                      applyCommissionAdjustment: false,
                      style: context.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: AppText.tabular,
                      ),
                    ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: scheme.onSurfaceVariant,
                      semanticLabel: expanded
                          ? 'transactions.collapse'.tr()
                          : 'transactions.expand'.tr(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedReveal(
            visible: expanded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in events) ...[
                  const Divider(indent: kTransactionRowDividerIndent),
                  UpcomingEventRow(
                    event: e,
                    onTap: () => _openSource(context, e),
                  ),
                ],
                const Divider(height: 1),
                _SeeAllButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A day that hasn't happened yet: its projected rows in one card.
class UpcomingDayList extends StatelessWidget {
  const UpcomingDayList({
    super.key,
    required this.events,
    this.margin = const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
  });

  final List<UpcomingEvent> events;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, e) in events.indexed) ...[
            if (i > 0) const Divider(indent: kTransactionRowDividerIndent),
            UpcomingEventRow(event: e, onTap: () => _openSource(context, e)),
          ],
          const Divider(height: 1),
          _SeeAllButton(),
        ],
      ),
    );
  }
}

class _SeeAllButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => openDetail(
        context,
        (_) => const UpcomingScreen(initialHorizonDays: 30),
      ),
      icon: const Icon(Icons.calendar_month_outlined, size: 18),
      label: Text('upcoming.seeNext30'.tr()),
    );
  }
}
