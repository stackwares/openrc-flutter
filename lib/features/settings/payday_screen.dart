import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:revenuecat/core/theme/store_brand_icon_colors.dart';
import 'package:revenuecat/core/utils/store_payday_schedule.dart';
import 'package:url_launcher/url_launcher.dart';

/// Store payout schedules: Apple fiscal calendar (from [Kedi](https://github.com/sereisoglu/Kedi))
/// and approximate Google Play monthly initiation dates.
class PaydayScreen extends StatelessWidget {
  const PaydayScreen({super.key});

  static Future<void> openUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open link: $url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final appleUp = AppStorePayday.upcoming;
    final googleUp = GooglePlayPayday.upcoming;
    final googleAll = GooglePlayPayday.all;
    final googleByYear = GooglePlayPayday.byEarningsYear(googleAll);
    final googleYears = googleByYear.keys.toList()..sort((a, b) => b.compareTo(a));

    final appleYears = AppStorePayday.fiscalYearsDescending;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payout calendar'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.info_outline),
            onSelected: (v) => openUrl(context, v),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value:
                    'https://www.revenuecat.com/blog/growth/apple-fiscal-calendar-year-payment-dates',
                child: Text('Apple fiscal calendar (article)'),
              ),
              PopupMenuItem(
                value:
                    'https://support.google.com/googleplay/android-developer/answer/137997',
                child: Text('Google Play payouts (help)'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _IntroCard(scheme: scheme),
          const SizedBox(height: 8),
          _StoreSectionHeader(
            icon: Icons.apple,
            iconColor: StoreBrandIconColors.appleBlue,
            title: 'App Store',
            subtitle: 'Fiscal month closing dates and when deposits land',
          ),
          if (appleUp != null) _AppleUpcomingSection(payday: appleUp, now: now),
          for (var i = 0; i < appleYears.length; i++) ...[
            _YearPaydayCard(
              title: 'Fiscal year ${appleYears[i]}',
              child: Column(
                children: _withDividers(
                  context,
                  AppStorePayday.groupedYearDescending(appleYears[i]).map(
                    (p) => _PaydayRow(
                      emoji: p.proximityState(now).emoji,
                      title: formatPaydayAbbrev(p.paymentDate),
                      subtitle:
                          '${formatPaydayMonthYear(p.fiscalMonthStart)} (${formatPaydayAbbrev(p.startDate)} – ${formatPaydayAbbrev(p.endDate)})',
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (appleUp == null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                'No further App Store dates are bundled yet—check Apple’s fiscal calendar for new months.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
          const SizedBox(height: 12),
          _StoreSectionHeader(
            icon: Icons.android,
            iconColor: StoreBrandIconColors.androidGreen,
            title: 'Google Play',
            subtitle: 'Estimated initiation (15th rule, weekends adjusted)',
          ),
          _PlayDisclaimerCard(scheme: scheme),
          if (googleUp != null) _GoogleUpcomingSection(payday: googleUp, now: now),
          for (final year in googleYears) ...[
            _YearPaydayCard(
              title: 'Earnings in $year',
              child: Column(
                children: _withDividers(
                  context,
                  (googleByYear[year] ?? []).map(
                    (p) => _PaydayRow(
                      emoji: p.proximityState(now).emoji,
                      title: formatPaydayAbbrev(p.paymentDate),
                      subtitle:
                          '${DateFormat.yMMMM().format(DateTime(p.earningsYear, p.earningsMonth, 1))} '
                          '(${formatPaydayAbbrev(p.earningsStart)} – ${formatPaydayAbbrev(p.earningsEnd)})',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static List<Widget> _withDividers(BuildContext context, Iterable<Widget> rows) {
    final list = rows.toList();
    if (list.isEmpty) return [];
    final scheme = Theme.of(context).colorScheme;
    final out = <Widget>[];
    for (var i = 0; i < list.length; i++) {
      if (i > 0) {
        out.add(
          Divider(
            height: 1,
            thickness: 1,
            indent: 56,
            endIndent: 0,
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        );
      }
      out.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: list[i],
      ));
    }
    return out;
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.lightbulb_outline_rounded,
              color: scheme.primary,
              size: 26,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How to read this',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Apple pays on fixed fiscal-month dates. Play usually starts bank transfers around the 15th of the month after your earnings period—holidays and your payments profile can shift that. Use the · menu for official documentation.',
                    style: tt.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreSectionHeader extends StatelessWidget {
  const _StoreSectionHeader({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(icon, color: iconColor, size: 22),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: tt.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: tt.bodySmall?.copyWith(
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

class _PlayDisclaimerCard extends StatelessWidget {
  const _PlayDisclaimerCard({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: StoreBrandIconColors.androidGreen.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: StoreBrandIconColors.androidGreen.withValues(alpha: 0.22),
          ),
        ),
        child: Text(
          'Dates are estimates (15th of the following month with weekend adjustment only). Confirm in Play Console for your account.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
        ),
      ),
    );
  }
}

class _YearPaydayCard extends StatelessWidget {
  const _YearPaydayCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(
              title,
              style: tt.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _AccentStripeCard extends StatelessWidget {
  const _AccentStripeCard({
    required this.accent,
    required this.child,
  });

  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: accent),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _AppleUpcomingSection extends StatelessWidget {
  const _AppleUpcomingSection({
    required this.payday,
    required this.now,
  });

  final AppStorePayday payday;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final state = payday.proximityState(now);
    final scheme = Theme.of(context).colorScheme;

    String title;
    switch (state) {
      case PaydayProximityState.today:
        title = 'It’s payday!';
      case PaydayProximityState.tomorrow:
        title = 'Tomorrow – ${formatPaydayAbbrev(payday.paymentDate)}';
      default:
        title =
            '${paydayRelativeLine(payday.paymentDate, now)} – ${formatPaydayAbbrev(payday.paymentDate)}';
    }

    final subtitle =
        '${formatPaydayMonthYear(payday.fiscalMonthStart)} (${formatPaydayAbbrev(payday.startDate)} – ${formatPaydayAbbrev(payday.endDate)})';

    return _AccentStripeCard(
      accent: StoreBrandIconColors.appleBlue,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              state.title.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
            ),
            const SizedBox(height: 12),
            _PaydayRow(emoji: state.emoji, title: title, subtitle: subtitle),
            const SizedBox(height: 12),
            Text(
              'Earnings from the ${formatPaydayMonthYear(payday.fiscalMonthStart)} fiscal month '
              'are deposited ${formatPaydayAbbrev(payday.paymentDate)}.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleUpcomingSection extends StatelessWidget {
  const _GoogleUpcomingSection({
    required this.payday,
    required this.now,
  });

  final GooglePlayPayday payday;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final state = payday.proximityState(now);
    final scheme = Theme.of(context).colorScheme;

    String title;
    switch (state) {
      case PaydayProximityState.today:
        title = 'Payout may start today';
      case PaydayProximityState.tomorrow:
        title = 'Around ${formatPaydayAbbrev(payday.paymentDate)}';
      default:
        title =
            '${paydayRelativeLine(payday.paymentDate, now)} – ${formatPaydayAbbrev(payday.paymentDate)}';
    }

    final monthLabel =
        DateFormat.yMMMM().format(DateTime(payday.earningsYear, payday.earningsMonth, 1));
    final subtitle =
        '$monthLabel (${formatPaydayAbbrev(payday.earningsStart)} – ${formatPaydayAbbrev(payday.earningsEnd)})';

    return _AccentStripeCard(
      accent: StoreBrandIconColors.androidGreen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NEXT ESTIMATED INITIATION',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: StoreBrandIconColors.androidGreen,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
            ),
            const SizedBox(height: 12),
            _PaydayRow(emoji: state.emoji, title: title, subtitle: subtitle),
            const SizedBox(height: 12),
            Text(
              'Calendar-month earnings are typically paid in the following month; '
              'this row uses the 15th with weekend adjustment only.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaydayRow extends StatelessWidget {
  const _PaydayRow({
    required this.emoji,
    required this.title,
    required this.subtitle,
  });

  final String emoji;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 40,
          child: Center(
            child: Text(
              emoji,
              style: const TextStyle(fontSize: 22, height: 1.2),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
