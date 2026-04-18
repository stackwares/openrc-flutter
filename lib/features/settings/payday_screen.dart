import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
        title: const Text('Store paydays'),
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
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'APP STORE',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
            ),
          ),
          if (appleUp != null) _AppleUpcomingSection(payday: appleUp, now: now),
          for (var i = 0; i < appleYears.length; i++) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(16, i == 0 && appleUp == null ? 4 : 16, 16, 8),
              child: Text(
                "Apple fiscal year ${appleYears[i]}",
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            ...AppStorePayday.groupedYearDescending(appleYears[i]).map(
              (p) => _PaydayRow(
                emoji: p.proximityState(now).emoji,
                title: formatPaydayAbbrev(p.paymentDate),
                subtitle:
                    '${formatPaydayMonthYear(p.fiscalMonthStart)} (${formatPaydayAbbrev(p.startDate)} – ${formatPaydayAbbrev(p.endDate)})',
              ),
            ),
          ],
          if (appleUp == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'No further App Store dates are bundled yet—check Apple’s fiscal calendar for new months.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              'GOOGLE PLAY',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Estimated initiation around the 15th of the following month (weekends adjusted). '
              'Holidays and your payments profile can change the date—confirm in Play Console.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: 8),
          if (googleUp != null) _GoogleUpcomingSection(payday: googleUp, now: now),
          for (final year in googleYears) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                'Earnings in $year',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            ...(googleByYear[year] ?? []).map(
              (p) => _PaydayRow(
                emoji: p.proximityState(now).emoji,
                title: formatPaydayAbbrev(p.paymentDate),
                subtitle:
                    '${DateFormat.yMMMM().format(DateTime(p.earningsYear, p.earningsMonth, 1))} '
                    '(${formatPaydayAbbrev(p.earningsStart)} – ${formatPaydayAbbrev(p.earningsEnd)})',
              ),
            ),
          ],
        ],
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NEXT ESTIMATED INITIATION',
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
              'Calendar-month earnings are typically paid in the following month; '
              'this row uses the 15th with weekend adjustment only.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 36,
          child: Text(emoji, style: const TextStyle(fontSize: 22, height: 1.2)),
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
