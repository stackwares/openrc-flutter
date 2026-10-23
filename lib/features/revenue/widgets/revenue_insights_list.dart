import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/core/animations/app_motion.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/features/revenue/revenue_insights_compute.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_leading_avatar.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/auto_app_icons_store.dart';
import 'package:revenuecat/services/commission_settings_store.dart';
import 'package:revenuecat/theme/app_tokens.dart';
import 'package:revenuecat/widgets/app_card.dart';
import 'package:revenuecat/widgets/dual_currency_text.dart';
import 'package:revenuecat/widgets/share_row.dart';
import 'package:revenuecat/widgets/split_bar.dart';

Future<void> _showRevenueInsightsSheet({
  required BuildContext context,
  required List<RcTransaction> transactions,
  required bool compactRevenueAmounts,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final height = MediaQuery.sizeOf(sheetContext).height * 0.88;
      return SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Revenue breakdown',
                style: sheetContext.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: RealtimeRevenueInsightsList(
                  transactions: transactions,
                  compactRevenueAmounts: compactRevenueAmounts,
                  showInsightsHeader: false,
                  cardMargin: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Revenue breakdown for a transaction list (stores, new vs renewals, top
/// apps, top countries). On the Transactions day view it is a compact
/// "Breakdown" card that opens the full list in a sheet.
class RealtimeRevenueInsightsList extends ConsumerWidget {
  final List<RcTransaction> transactions;

  /// When true (Transactions day view), shows a compact card that opens a bottom sheet.
  final bool asModalEntry;

  /// Outer margin; use [EdgeInsets.zero] when embedding in a sheet.
  final EdgeInsetsGeometry cardMargin;

  /// When false, omits the card title (e.g. sheet has its own title).
  final bool showInsightsHeader;

  /// When false (e.g. Revenue tab), revenue amounts use full grouping ($5,001.00)
  /// instead of compact ($5.1K).
  final bool compactRevenueAmounts;

  const RealtimeRevenueInsightsList({
    super.key,
    required this.transactions,
    this.asModalEntry = false,
    this.cardMargin = const EdgeInsets.fromLTRB(16, 0, 16, 12),
    this.showInsightsHeader = true,
    this.compactRevenueAmounts = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.colorScheme;
    final colors = context.appColors;

    if (transactions.isEmpty) {
      return AppCard(
        margin: cardMargin,
        child: Text(
          'No transactions to break down yet.',
          style: context.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final commission = ref.watch(commissionSettingsProvider);
    final data = computeRevenueInsights(transactions, commission);
    final appIcons = ref.watch(resolvedAppIconsProvider);

    if (asModalEntry) {
      return _CollapsedBreakdownCard(
        data: data,
        appIcons: appIcons,
        margin: cardMargin,
        onTap: () => _showRevenueInsightsSheet(
          context: context,
          transactions: transactions,
          compactRevenueAmounts: compactRevenueAmounts,
        ),
      );
    }

    Widget amount(double revenue) => compactRevenueAmounts
        ? DualCurrencyCompactText(amount: revenue, textAlign: TextAlign.end)
        : DualCurrencyExactText(
            amount: revenue,
            applyCommissionAdjustment: false,
            textAlign: TextAlign.end,
          );

    var rowIndex = 0;
    Widget enter(Widget w) => w.appListItemEntrance(rowIndex++);

    final sections = <Widget>[
      _InsightsSection(
        title: 'Stores',
        rows: [
          enter(
            ShareRow(
              label: 'App Store',
              pct: data.applePct,
              amount: amount(data.appleRevenue),
              barColor: colors.apple,
              leading: _LeadingIconTile(icon: Icons.apple, color: colors.apple),
            ),
          ),
          enter(
            ShareRow(
              label: 'Google Play',
              pct: data.googlePct,
              amount: amount(data.googleRevenue),
              barColor: colors.google,
              leading: _LeadingIconTile(
                icon: Icons.android,
                color: colors.google,
              ),
            ),
          ),
        ],
      ),
      _InsightsSection(
        title: 'New vs renewals',
        rows: [
          enter(
            ShareRow(
              label: 'New',
              pct: data.newPct,
              amount: amount(data.newRevenue),
              barColor: colors.purchase,
              leading: _LeadingIconTile(
                icon: Icons.add_circle_outline,
                color: colors.purchase,
              ),
            ),
          ),
          enter(
            ShareRow(
              label: 'Renewals',
              pct: data.renewalPct,
              amount: amount(data.renewalRevenue),
              barColor: colors.renewal,
              leading: _LeadingIconTile(
                icon: Icons.autorenew,
                color: colors.renewal,
              ),
            ),
          ),
        ],
      ),
      _InsightsSection(
        title: 'Top apps',
        emptyText: 'No app revenue',
        rows: [
          for (final e in data.topApps)
            enter(
              ShareRow(
                label: e.label,
                pct: e.pct,
                amount: amount(e.revenue),
                barColor: scheme.primary,
                leading: _AppIcon(
                  url: e.appId != null ? appIcons[e.appId] : null,
                  size: 36,
                ),
              ),
            ),
        ],
      ),
      _InsightsSection(
        title: 'Top countries',
        emptyText: 'No country data',
        rows: [
          for (final e in data.topCountries)
            enter(
              ShareRow(
                label: e.name,
                pct: e.pct,
                amount: amount(e.revenue),
                barColor: scheme.onSurfaceVariant,
                leading: _LeadingEmojiTile(
                  glyph: countryInsightLeadingEmoji(e.countryKey),
                ),
              ),
            ),
        ],
      ),
    ];

    return Card(
      margin: cardMargin,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showInsightsHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                'Revenue breakdown',
                style: context.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const Divider(),
            sections[i],
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// Compact breakdown on the Transactions day view.
class _CollapsedBreakdownCard extends StatelessWidget {
  const _CollapsedBreakdownCard({
    required this.data,
    required this.appIcons,
    required this.margin,
    required this.onTap,
  });

  final RevenueInsightsSnapshot data;
  final Map<String, String> appIcons;
  final EdgeInsetsGeometry margin;
  final VoidCallback onTap;

  static const _previewCount = 3;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final colors = context.appColors;
    final labelStyle = context.textTheme.labelMedium?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    final valueStyle = context.textTheme.labelMedium?.copyWith(
      color: scheme.onSurface,
      fontWeight: FontWeight.w700,
      fontFeatures: AppText.tabular,
    );
    final apps = data.topApps.take(_previewCount).toList();
    final countries = data.topCountries.take(_previewCount).toList();

    return AppCard(
      margin: margin,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Breakdown',
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant,
                semanticLabel: 'Open breakdown',
              ),
            ],
          ),
          const SizedBox(height: 12),
          SplitBar(
            height: 6,
            segments: [
              SplitSegment(
                value: data.applePct,
                color: colors.apple,
                label: 'App Store',
              ),
              SplitSegment(
                value: data.googlePct,
                color: colors.google,
                label: 'Google Play',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.apple, size: 15, color: colors.apple),
              const SizedBox(width: 4),
              Text('App Store ', style: labelStyle),
              Text('${data.applePct.toStringAsFixed(1)}%', style: valueStyle),
              const Spacer(),
              Text('Google Play ', style: labelStyle),
              Text('${data.googlePct.toStringAsFixed(1)}%', style: valueStyle),
              const SizedBox(width: 4),
              Icon(Icons.android, size: 15, color: colors.google),
            ],
          ),
          if (apps.isNotEmpty) ...[
            const SizedBox(height: 14),
            _PreviewLine(
              title: 'Top apps',
              more: data.topApps.length - apps.length,
              items: [
                for (final a in apps)
                  _PreviewItem(
                    leading: _AppIcon(
                      url: a.appId != null ? appIcons[a.appId] : null,
                      size: 18,
                    ),
                    label: a.label,
                    pct: a.pct,
                  ),
              ],
            ),
          ],
          if (countries.isNotEmpty) ...[
            const SizedBox(height: 10),
            _PreviewLine(
              title: 'Top countries',
              more: data.topCountries.length - countries.length,
              items: [
                for (final c in countries)
                  _PreviewItem(
                    leading: Text(
                      countryInsightLeadingEmoji(c.countryKey),
                      style: const TextStyle(fontSize: 14, height: 1.1),
                    ),
                    label: c.countryKey.length == 2 ? c.countryKey : c.name,
                    pct: c.pct,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PreviewItem {
  const _PreviewItem({
    required this.leading,
    required this.label,
    required this.pct,
  });

  final Widget leading;
  final String label;
  final double pct;
}

class _PreviewLine extends StatelessWidget {
  const _PreviewLine({
    required this.title,
    required this.items,
    required this.more,
  });

  final String title;
  final List<_PreviewItem> items;
  final int more;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final small = context.textTheme.labelMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: small?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final item in items)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  item.leading,
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 96),
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: small?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${item.pct.toStringAsFixed(0)}%',
                    style: small?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      fontFeatures: AppText.tabular,
                    ),
                  ),
                ],
              ),
            if (more > 0)
              Text(
                '+$more more',
                style: small?.copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ],
    );
  }
}

class _InsightsSection extends StatelessWidget {
  const _InsightsSection({
    required this.title,
    required this.rows,
    this.emptyText,
  });

  final String title;
  final List<Widget> rows;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
          child: Text(
            title,
            style: context.textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (rows.isEmpty && emptyText != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              emptyText!,
              style: context.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ...rows,
      ],
    );
  }
}

class _LeadingIconTile extends StatelessWidget {
  const _LeadingIconTile({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.icon),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 20, color: color),
    );
  }
}

class _LeadingEmojiTile extends StatelessWidget {
  const _LeadingEmojiTile({required this.glyph});

  final String glyph;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.icon),
      ),
      alignment: Alignment.center,
      child: Text(glyph, style: const TextStyle(fontSize: 19, height: 1.05)),
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.url, required this.size});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return TransactionLeadingAvatar(
      imageUrl: url,
      size: size,
      borderRadius: size * 0.24,
      tintColor: scheme.onSurfaceVariant,
      fallback: Icon(
        Icons.apps_outlined,
        size: size * 0.55,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}
