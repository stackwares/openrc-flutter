import 'package:flutter/material.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/features/transactions/transactions_common.dart';
import 'package:openrc/core/utils/store_display_name.dart';
import 'package:openrc/features/transactions/widgets/day_summary_card.dart';
import 'package:easy_localization/easy_localization.dart';

/// Chips for each active filter, each removable, plus "Clear all".
class ActiveFiltersRow extends StatelessWidget {
  const ActiveFiltersRow({
    super.key,
    required this.appCount,
    required this.countryCodes,
    required this.platforms,
    this.sectionFilters = const {},
    required this.onOpenFilters,
    required this.onClearApps,
    required this.onClearCountries,
    required this.onClearPlatforms,
    this.onRemoveSection,
    required this.onClearAll,
  });

  final int? appCount;
  final Set<String>? countryCodes;
  final Set<TransactionPlatformFilter>? platforms;
  final Set<TransactionDaySectionFilter> sectionFilters;
  final VoidCallback onOpenFilters;
  final VoidCallback onClearApps;
  final VoidCallback onClearCountries;
  final VoidCallback onClearPlatforms;
  final void Function(TransactionDaySectionFilter)? onRemoveSection;
  final VoidCallback onClearAll;

  static String _platformName(TransactionPlatformFilter p) =>
      transactionPlatformFilterLabel(p);

  @override
  Widget build(BuildContext context) {
    final countries = countryCodes;
    final stores = platforms;
    final chips = <Widget>[
      if (appCount != null)
        _FilterChip(
          label: 'transactions.appCount'.plural(appCount!),
          onPressed: onOpenFilters,
          onDeleted: onClearApps,
        ),
      if (countries != null && countries.isNotEmpty)
        _FilterChip(
          label: countries.length == 1
              ? (countries.single == '__'
                    ? 'transactions.unknownCountry'.tr()
                    : countries.single)
              : 'transactions.countryCount'.plural(countries.length),
          onPressed: onOpenFilters,
          onDeleted: onClearCountries,
        ),
      if (stores != null && stores.isNotEmpty)
        _FilterChip(
          label: stores.length == 1
              ? _platformName(stores.single)
              : 'transactions.storeCount'.plural(stores.length),
          onPressed: onOpenFilters,
          onDeleted: onClearPlatforms,
        ),
      for (final f in TransactionDaySectionFilter.values)
        if (sectionFilters.contains(f))
          _FilterChip(
            label: daySummaryTileLabel(f),
            dotColor: daySummaryPillAccent(context, f),
            onPressed: () => onRemoveSection?.call(f),
            onDeleted: () => onRemoveSection?.call(f),
          ),
    ];
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        children: [
          for (final c in chips) ...[c, const SizedBox(width: 8)],
          TextButton(onPressed: onClearAll, child: Text('transactions.clearAll'.tr())),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.onPressed,
    required this.onDeleted,
    this.dotColor,
  });

  final String label;
  final VoidCallback onPressed;
  final VoidCallback onDeleted;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return InputChip(
      label: Text(label),
      avatar: dotColor == null
          ? null
          : Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
      onPressed: onPressed,
      onDeleted: onDeleted,
      deleteIcon: const Icon(Icons.close_rounded, size: 16),
      deleteButtonTooltipMessage: 'transactions.removeFilter'.tr(),
      visualDensity: VisualDensity.compact,
      backgroundColor: Color.alphaBlend(
        scheme.primary.withValues(alpha: 0.12),
        scheme.surfaceContainerLow,
      ),
      side: BorderSide(color: scheme.primary.withValues(alpha: 0.35)),
      shape: const StadiumBorder(),
      labelStyle: context.textTheme.labelLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
