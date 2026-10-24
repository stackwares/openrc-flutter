import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/features/revenue/revenue_insights_compute.dart';
import 'package:openrc/features/transactions/widgets/transaction_leading_avatar.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/auto_app_icons_store.dart';
import 'package:openrc/services/commission_settings_store.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/adaptive_modal.dart';
import 'package:openrc/widgets/app_card.dart';
import 'package:openrc/widgets/dual_currency_text.dart';
import 'package:openrc/widgets/share_row.dart';
import 'package:openrc/widgets/split_bar.dart';

Future<void> _showRevenueInsightsSheet({
  required BuildContext context,
  required List<RcTransaction> transactions,
  required bool compactRevenueAmounts,
}) {
  return showAdaptiveSheet<void>(
    context: context,
    heightFactor: 0.88,
    builder: (sheetContext) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'revenue.revenueBreakdown'.tr(),
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

  /// 2 lays the sections out in pairs side by side (dashboard layouts).
  final int columns;

  const RealtimeRevenueInsightsList({
    super.key,
    required this.transactions,
    this.asModalEntry = false,
    this.cardMargin = const EdgeInsets.fromLTRB(16, 0, 16, 12),
    this.showInsightsHeader = true,
    this.compactRevenueAmounts = true,
    this.columns = 1,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.colorScheme;
    final colors = context.appColors;

    if (transactions.isEmpty) {
      return AppCard(
        margin: cardMargin,
        child: Text(
          'revenue.noTransactionsToBreakDown'.tr(),
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
        title: 'revenue.stores'.tr(),
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
          if (data.otherStoresRevenue.abs() > 1e-9)
            enter(
              ShareRow(
                label: 'revenue.webAndOtherStores'.tr(),
                pct: data.otherStoresPct,
                amount: amount(data.otherStoresRevenue),
                barColor: colors.web,
                leading: _LeadingIconTile(
                  icon: Icons.language_rounded,
                  color: colors.web,
                ),
              ),
            ),
        ],
      ),
      _InsightsSection(
        title: 'revenue.newVsRenewals'.tr(),
        rows: [
          enter(
            ShareRow(
              label: 'revenue.new'.tr(),
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
              label: 'revenue.renewals'.tr(),
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
        title: 'revenue.topApps'.tr(),
        emptyText: 'revenue.noAppRevenue'.tr(),
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
        title: 'revenue.topCountries'.tr(),
        emptyText: 'revenue.noCountryData'.tr(),
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
                'revenue.revenueBreakdown'.tr(),
                style: context.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          if (columns < 2)
            for (var i = 0; i < sections.length; i++) ...[
              if (i > 0) const Divider(),
              sections[i],
            ]
          else
            for (var i = 0; i < sections.length; i += 2) ...[
              if (i > 0) const Divider(),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: sections[i]),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: i + 1 < sections.length
                          ? sections[i + 1]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
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
                  'revenue.breakdown'.tr(),
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant,
                semanticLabel: 'revenue.openBreakdown'.tr(),
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
              SplitSegment(
                value: data.otherStoresPct,
                color: colors.web,
                label: 'revenue.webAndOtherStores'.tr(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Names give way (ellipsis) before the percentages on narrow
          // screens or large text.
          Row(
            children: [
              Expanded(
                child: _StoreShareLabel(
                  icon: Icons.apple,
                  color: colors.apple,
                  name: 'App Store',
                  pct: data.applePct,
                  labelStyle: labelStyle,
                  valueStyle: valueStyle,
                ),
              ),
              if (data.otherStoresPct.abs() >= 0.05) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _StoreShareLabel(
                    icon: Icons.language_rounded,
                    color: colors.web,
                    name: 'revenue.web'.tr(),
                    pct: data.otherStoresPct,
                    labelStyle: labelStyle,
                    valueStyle: valueStyle,
                    alignment: MainAxisAlignment.center,
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: _StoreShareLabel(
                  icon: Icons.android,
                  color: colors.google,
                  name: 'Google Play',
                  pct: data.googlePct,
                  labelStyle: labelStyle,
                  valueStyle: valueStyle,
                  alignment: MainAxisAlignment.end,
                  iconAfter: true,
                ),
              ),
            ],
          ),
          if (apps.isNotEmpty) ...[
            const SizedBox(height: 14),
            _PreviewLine(
              title: 'revenue.topApps'.tr(),
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
              title: 'revenue.topCountries'.tr(),
              more: data.topCountries.length - countries.length,
              items: [
                for (final c in countries)
                  _PreviewItem(
                    leading: Text(
                      countryInsightLeadingEmoji(c.countryKey),
                      style: const TextStyle(fontSize: 14, height: 1.1),
                    ),
                    // ISO codes read short; the unknown bucket ('__') by name.
                    label: c.countryKey.length == 2 && c.countryKey != '__'
                        ? c.countryKey
                        : c.name,
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

/// One store's share on the compact Breakdown card.
class _StoreShareLabel extends StatelessWidget {
  const _StoreShareLabel({
    required this.icon,
    required this.color,
    required this.name,
    required this.pct,
    required this.labelStyle,
    required this.valueStyle,
    this.alignment = MainAxisAlignment.start,
    this.iconAfter = false,
  });

  final IconData icon;
  final Color color;
  final String name;
  final double pct;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;
  final MainAxisAlignment alignment;
  final bool iconAfter;

  @override
  Widget build(BuildContext context) {
    final mark = Icon(icon, size: 15, color: color);
    return Row(
      mainAxisAlignment: alignment,
      children: [
        if (!iconAfter) ...[mark, const SizedBox(width: 4)],
        Flexible(
          child: Text(
            name,
            style: labelStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        Text('${pct.toStringAsFixed(1)}%', style: valueStyle),
        if (iconAfter) ...[const SizedBox(width: 4), mark],
      ],
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
                'revenue.moreCount'.tr(namedArgs: {'count': '$more'}),
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
