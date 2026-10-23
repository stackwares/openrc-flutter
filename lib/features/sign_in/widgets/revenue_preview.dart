import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:revenuecat/core/animations/app_motion.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/core/utils/currency_format.dart';
import 'package:revenuecat/features/transactions/widgets/day_revenue_strip.dart';
import 'package:revenuecat/theme/app_colors.dart';
import 'package:revenuecat/theme/app_tokens.dart';
import 'package:revenuecat/widgets/app_card.dart';
import 'package:revenuecat/widgets/delta_badge.dart';
import 'package:revenuecat/widgets/status_label.dart';

/// Example figures for the sign-in preview. Clearly labelled "Example" on
/// screen; never the user's data.
const double _kExampleToday = 1284.50;
const double _kExampleYesterday = 1088.60;
const List<double> _kExampleWeek = [
  820,
  1140,
  960,
  1310,
  1015,
  _kExampleYesterday,
  _kExampleToday,
];

class _ExampleSale {
  const _ExampleSale({
    required this.app,
    required this.detail,
    required this.icon,
    required this.amount,
    required this.status,
    required this.color,
  });

  final String app;
  final String detail;
  final IconData icon;
  final double amount;
  final String status;
  final Color Function(AppColors c) color;
}

final List<_ExampleSale> _kExampleSales = [
  _ExampleSale(
    app: 'Focus Timer',
    detail: 'Annual · United States',
    icon: Icons.timer_outlined,
    amount: 39.99,
    status: 'Converted',
    color: (c) => c.conversion,
  ),
  _ExampleSale(
    app: 'Photo Lab',
    detail: 'Monthly · Germany',
    icon: Icons.photo_camera_outlined,
    amount: 4.99,
    status: 'Renewed',
    color: (c) => c.renewal,
  ),
  _ExampleSale(
    app: 'Calm Notes',
    detail: 'Annual · Japan',
    icon: Icons.edit_note_rounded,
    amount: 0,
    status: 'Trial',
    color: (c) => c.trial,
  ),
  _ExampleSale(
    app: 'Habit Garden',
    detail: 'Lifetime · Canada',
    icon: Icons.spa_outlined,
    amount: 59.99,
    status: 'Purchased',
    color: (c) => c.purchase,
  ),
];

/// A small, live-looking sketch of the app shown before sign-in: today's total
/// counting up, the 7-day bars, and example sales arriving one by one.
class RevenuePreview extends StatelessWidget {
  const RevenuePreview({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Example of the app: today’s revenue, the last 7 days, and '
          'each new sale as it happens',
      excludeSemantics: true,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [_ExampleTodayCard(), SizedBox(height: 10), _SaleTicker()],
      ),
    );
  }
}

class _ExampleTodayCard extends StatelessWidget {
  const _ExampleTodayCard();

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final today = DateTime.now();
    final days = [
      for (var i = 0; i < _kExampleWeek.length; i++)
        () {
          final date = DateTime(
            today.year,
            today.month,
            today.day - (_kExampleWeek.length - 1 - i),
          );
          return DayRevenueStripDay(
            dayKey: DateFormat('yyyy-MM-dd').format(date),
            date: date,
            total: _kExampleWeek[i],
          );
        }(),
    ];
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Today',
                style: context.textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              const _ExampleChip(),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: _kExampleToday),
                duration: AppMotion.of(
                  context,
                  const Duration(milliseconds: 1200),
                ),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => Text(
                  formatExactUsd(v),
                  style: AppText.amount(context, size: 28),
                ),
              ),
              const SizedBox(width: 10),
              DeltaBadge.percent(
                current: _kExampleToday,
                previous: _kExampleYesterday,
              ),
            ],
          ),
          const SizedBox(height: 12),
          DayRevenueStrip(
            days: days,
            selectedDayKey: days.last.dayKey,
            formatAmount: formatExactUsd,
            barAreaHeight: 34,
          ),
        ],
      ),
    );
  }
}

class _ExampleChip extends StatelessWidget {
  const _ExampleChip();

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        'Example',
        style: context.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Example sales sliding in one at a time, like push alerts in the app.
class _SaleTicker extends StatefulWidget {
  const _SaleTicker();

  @override
  State<_SaleTicker> createState() => _SaleTickerState();
}

class _SaleTickerState extends State<_SaleTicker> {
  Timer? _timer;
  int _index = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timer?.cancel();
    _timer = null;
    // A still preview when the system asks to reduce motion.
    if (!MediaQuery.disableAnimationsOf(context)) {
      _timer = Timer.periodic(const Duration(milliseconds: 2800), (_) {
        if (mounted) {
          setState(() => _index = (_index + 1) % _kExampleSales.length);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.of(context, const Duration(milliseconds: 420));
    return AnimatedSwitcher(
      duration: duration,
      // The old sale leaves quickly so the two never overlap for long.
      reverseDuration: AppMotion.of(context, const Duration(milliseconds: 160)),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) {
        final incoming = child.key == ValueKey(_index);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(0, incoming ? 0.5 : -0.3),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: _SaleCard(key: ValueKey(_index), sale: _kExampleSales[_index]),
    );
  }
}

class _SaleCard extends StatelessWidget {
  const _SaleCard({super.key, required this.sale});

  final _ExampleSale sale;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final color = sale.color(context.appColors);
    final tt = context.textTheme;
    return AppCard(
      radius: AppRadius.tile,
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppRadius.icon),
            ),
            alignment: Alignment.center,
            child: Icon(sale.icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sale.app,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${sale.detail} · now',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatExactUsd(sale.amount),
                style: tt.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: AppText.tabular,
                  color: sale.amount == 0
                      ? scheme.onSurfaceVariant
                      : scheme.onSurface,
                ),
              ),
              StatusLabel(text: sale.status, color: color),
            ],
          ),
        ],
      ),
    );
  }
}
