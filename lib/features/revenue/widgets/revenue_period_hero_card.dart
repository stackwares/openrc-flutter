import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/animated_number.dart';
import 'package:openrc/widgets/app_card.dart';

/// Net total for a period, optional gross before fees, and backfill progress.
class RevenuePeriodHeroCard extends StatelessWidget {
  const RevenuePeriodHeroCard({
    super.key,
    required this.title,
    required this.netTotal,
    required this.grossTotal,
    required this.showGross,
    this.loadComplete = true,
    this.loadingLabel,
  });

  final String title;
  final double netTotal;
  final double grossTotal;
  final bool showGross;
  final bool loadComplete;
  final String? loadingLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final muted = context.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
      fontFeatures: AppText.tabular,
    );
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: context.textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          AnimatedExactAmount(
            amount: netTotal,
            countFromZero: true,
            style: AppText.amount(context, size: 34),
          ),
          if (showGross) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text('revenue.beforeStoreFees'.tr(), style: muted),
                AnimatedExactAmount(
                  amount: grossTotal,
                  applyCommissionAdjustment: false,
                  style: muted,
                ),
              ],
            ),
          ],
          if (!loadComplete) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: const LinearProgressIndicator(minHeight: 3),
            ),
            const SizedBox(height: 6),
            Text(loadingLabel ?? 'revenue.loadingOlder'.tr(), style: muted),
          ],
        ],
      ),
    );
  }
}
