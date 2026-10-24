import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/core/utils/region_display_name.dart';
import 'package:openrc/core/utils/store_display_name.dart';
import 'package:openrc/features/revenue/revenue_insights_compute.dart';
import 'package:openrc/features/transactions/transactions_common.dart';
import 'package:openrc/features/transactions/widgets/transaction_leading_avatar.dart';
import 'package:openrc/models/rc_project.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/auto_app_icons_store.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/adaptive_modal.dart';
import 'package:openrc/widgets/grouped_list.dart';
import 'package:openrc/widgets/pressable_scale.dart';
import 'package:openrc/widgets/search_field_decoration.dart';
import 'package:openrc/widgets/section_header.dart';

typedef TransactionsFilterSheetOnApply =
    void Function(
      Set<String>? includeApps,
      Set<String>? countryCodes,
      Set<TransactionPlatformFilter>? platforms,
    );

/// Country key for transactions without a country.
const String _unknownCountry = '__';

/// Content width from which stores and apps sit beside the countries.
const double _twoColumnMinWidth = 680;

/// Apps get a search field once there are more than this many.
const int _appSearchThreshold = 8;

/// Leading tile plus the row's padding and gap: where row dividers start.
const double _rowDividerIndent = 60;

String _countryKey(RcTransaction tx) {
  final code = tx.subscriberCountryCode?.trim().toUpperCase();
  return code == null || code.isEmpty ? _unknownCountry : code;
}

String _countryName(String code) => code == _unknownCountry
    ? 'transactions.unknown'.tr()
    : regionDisplayNameEnglish(code);

Set<String> _normalizedCountrySelection(
  Set<String>? raw,
  Iterable<String> seenInTransactions,
) {
  if (raw == null || raw.isEmpty) return {};
  final allowed = {
    for (final e in sortedSupportedIso3166Alpha2Countries()) e.code,
    ...seenInTransactions,
    _unknownCountry,
  };
  return {
    for (final c in raw)
      if (allowed.contains(c.trim().toUpperCase())) c.trim().toUpperCase(),
  };
}

/// Filters transactions by store, app and country: a bottom sheet on phones
/// and a two-column dialog on larger windows. Changes apply as they're made;
/// the footer counts the matching transactions and closes the sheet.
///
/// Every section works the same way: nothing picked means everything, and
/// each pick narrows the list.
Future<void> showTransactionsAppFilterSheet({
  required BuildContext context,
  required Map<String, List<RcTransaction>> filterSource,
  required Set<String>? currentIncludeFilter,
  Set<String>? currentCountryCodes,
  Set<TransactionPlatformFilter>? currentPlatforms,
  List<RcProject> accountProjects = const [],
  required TransactionsFilterSheetOnApply onApply,
}) {
  final options = collectAppFilterOptionsWithProjects(
    filterSource,
    accountProjects,
  );
  if (options.isEmpty) return Future.value();

  final transactions = flattenGroupedTransactionsDeduped(filterSource);
  final allKeys = options.map((o) => o.key).toSet();
  // `null` and every app both mean "all apps": shown as nothing picked.
  final currentApps = currentIncludeFilter?.intersection(allKeys);
  final initialApps =
      currentApps == null || currentApps.length == allKeys.length
      ? <String>{}
      : currentApps;

  return showAdaptiveSheet<void>(
    context: context,
    // Leaves the top 30% of a phone free: the list stays in view, and
    // there's room to tap out of the sheet.
    heightFactor: 0.7,
    dialogMaxWidth: 880,
    dialogMaxHeight: 720,
    builder: (_) => TransactionsAppFilterModal(
      options: options,
      transactions: transactions,
      initialSelected: initialApps,
      initialCountrySelection: _normalizedCountrySelection(
        currentCountryCodes,
        transactions.map(_countryKey),
      ),
      initialPlatformSelection: {...?currentPlatforms},
      onFiltersChanged: onApply,
    ),
  );
}

class TransactionsAppFilterModal extends ConsumerStatefulWidget {
  final List<AppFilterOption> options;

  /// The transactions being filtered, for the live counts.
  final List<RcTransaction> transactions;

  /// Picked apps; empty = all apps.
  final Set<String> initialSelected;
  final Set<String> initialCountrySelection;
  final Set<TransactionPlatformFilter> initialPlatformSelection;

  /// Called after every change; `null` means no restriction.
  final TransactionsFilterSheetOnApply onFiltersChanged;

  const TransactionsAppFilterModal({
    super.key,
    required this.options,
    this.transactions = const [],
    required this.initialSelected,
    required this.initialCountrySelection,
    required this.initialPlatformSelection,
    required this.onFiltersChanged,
  });

  @override
  ConsumerState<TransactionsAppFilterModal> createState() =>
      _TransactionsAppFilterModalState();
}

class _TransactionsAppFilterModalState
    extends ConsumerState<TransactionsAppFilterModal> {
  NumberFormat get _number => NumberFormat.decimalPattern();

  late final Set<String> _apps = {...widget.initialSelected};
  late final Set<TransactionPlatformFilter> _stores = {
    ...widget.initialPlatformSelection,
  };
  late final Set<String> _countries = {...widget.initialCountrySelection};
  final _appSearch = TextEditingController();
  final _countrySearch = TextEditingController();

  late final List<({String code, String displayName})> _allCountries =
      sortedSupportedIso3166Alpha2Countries();

  /// Countries offered as quick picks: those in the transactions, busiest
  /// first, then any picked from the full list. Only grows while open, so
  /// chips never move under a finger.
  late final List<String> _quickCountries;
  late _Facets _facets;

  @override
  void initState() {
    super.initState();
    final seen = <String, int>{};
    for (final tx in widget.transactions) {
      seen.update(_countryKey(tx), (n) => n + 1, ifAbsent: () => 1);
    }
    _quickCountries = seen.keys.toList()
      ..sort((a, b) {
        final byCount = seen[b]!.compareTo(seen[a]!);
        return byCount != 0
            ? byCount
            : _countryName(a).compareTo(_countryName(b));
      });
    for (final code in _countries) {
      if (!_quickCountries.contains(code)) _quickCountries.add(code);
    }
    _facets = _count();
  }

  @override
  void dispose() {
    _appSearch.dispose();
    _countrySearch.dispose();
    super.dispose();
  }

  bool get _appsActive =>
      _apps.isNotEmpty && _apps.length < widget.options.length;

  int get _activeSections =>
      (_stores.isNotEmpty ? 1 : 0) +
      (_appsActive ? 1 : 0) +
      (_countries.isNotEmpty ? 1 : 0);

  _Facets _count() => _Facets(
    widget.transactions,
    apps: _appsActive ? _apps : null,
    countries: _countries.isEmpty ? null : _countries,
    stores: _stores.isEmpty ? null : _stores,
  );

  void _update(VoidCallback change) {
    HapticFeedback.selectionClick();
    setState(() {
      change();
      _facets = _count();
    });
    widget.onFiltersChanged(
      _appsActive ? {..._apps} : null,
      _countries.isEmpty ? null : {..._countries},
      _stores.isEmpty ? null : {..._stores},
    );
  }

  void _toggle<T>(Set<T> set, T value) =>
      _update(() => set.remove(value) || set.add(value));

  void _toggleCountry(String code) => _update(() {
    if (!_countries.remove(code)) {
      _countries.add(code);
      if (!_quickCountries.contains(code)) _quickCountries.add(code);
    }
  });

  void _clearAll() => _update(() {
    _apps.clear();
    _stores.clear();
    _countries.clear();
  });

  /// Counts only mean something when there are transactions to count.
  int? _countFor(int? n) => widget.transactions.isEmpty ? null : n ?? 0;

  String? _pickedCount(int n) => n == 0 ? null : _number.format(n);

  @override
  Widget build(BuildContext context) {
    final inDialog = context.windowSize != WindowSize.compact;
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= _twoColumnMinWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, inDialog),
            Expanded(
              child: twoColumns
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _scroll([
                            ..._storeSlivers(context),
                            ..._appSlivers(context),
                          ]),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: _scroll(_countrySlivers(context, first: true)),
                        ),
                      ],
                    )
                  : _scroll([
                      ..._storeSlivers(context),
                      ..._appSlivers(context),
                      ..._countrySlivers(context),
                    ]),
            ),
            _footer(context, wide: twoColumns),
          ],
        );
      },
    );
  }

  Widget _scroll(List<Widget> slivers) => CustomScrollView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    slivers: [
      ...slivers,
      const SliverToBoxAdapter(child: SizedBox(height: AppSpace.lg)),
    ],
  );

  Widget _header(BuildContext context, bool inDialog) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpace.lg,
        0,
        inDialog ? AppSpace.sm : AppSpace.xs,
        AppSpace.xxs,
      ),
      child: SizedBox(
        height: inDialog ? 48 : 40,
        child: Row(
          children: [
            Text(
              'transactions.filters'.tr(),
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 10),
            _CountBadge(count: _activeSections),
            const Spacer(),
            // Only there while something is filtered, beside the count it
            // clears; the footer keeps the one button that finishes.
            AnimatedSwitcher(
              duration: AppMotion.of(context, AppMotion.fast),
              child: _activeSections == 0
                  ? const SizedBox.shrink()
                  : TextButton(
                      key: const ValueKey('reset'),
                      onPressed: _clearAll,
                      child: Text('transactions.reset'.tr()),
                    ),
            ),
            if (inDialog)
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
          ],
        ),
      ),
    );
  }

  /// Muted "All" while nothing is picked, a Clear button once something is.
  Widget _sectionTrailing(
    BuildContext context, {
    required bool active,
    required VoidCallback onClear,
  }) {
    return SizedBox(
      height: 40,
      child: AnimatedSwitcher(
        duration: AppMotion.of(context, AppMotion.fast),
        child: active
            ? TextButton(
                key: const ValueKey('clear'),
                onPressed: onClear,
                child: Text('transactions.clear'.tr()),
              )
            : Padding(
                key: const ValueKey('all'),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  child: Text(
                    'transactions.all'.tr(),
                    style: context.textTheme.labelLarge?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  EdgeInsets _headerPadding({bool first = false}) => EdgeInsets.fromLTRB(
    AppSpace.lg,
    first ? AppSpace.xs : AppSpace.lg,
    AppSpace.xs,
    AppSpace.xxs,
  );

  List<Widget> _storeSlivers(BuildContext context) {
    final colors = context.appColors;
    final stores = [
      (
        filter: TransactionPlatformFilter.apple,
        label: transactionPlatformFilterLabel(TransactionPlatformFilter.apple),
        icon: Icons.apple,
        color: colors.apple,
      ),
      (
        filter: TransactionPlatformFilter.google,
        label: transactionPlatformFilterLabel(TransactionPlatformFilter.google),
        icon: Icons.android,
        color: colors.google,
      ),
      (
        filter: TransactionPlatformFilter.web,
        label: 'transactions.web'.tr(),
        icon: Icons.language_rounded,
        color: colors.web,
      ),
    ];
    return [
      SliverToBoxAdapter(
        child: SectionHeader(
          title: 'transactions.store'.tr(),
          count: _pickedCount(_stores.length),
          padding: _headerPadding(first: true),
          trailing: _sectionTrailing(
            context,
            active: _stores.isNotEmpty,
            onClear: () => _update(_stores.clear),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
        sliver: SliverToBoxAdapter(
          child: Row(
            children: [
              for (var i = 0; i < stores.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: _StoreTile(
                    icon: stores[i].icon,
                    color: stores[i].color,
                    label: stores[i].label,
                    count: _countFor(_facets.byStore[stores[i].filter]),
                    selected: _stores.contains(stores[i].filter),
                    onTap: () => _toggle(_stores, stores[i].filter),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _appSlivers(BuildContext context) {
    final query = _appSearch.text.trim().toLowerCase();
    final apps = query.isEmpty
        ? widget.options
        : [
            for (final o in widget.options)
              if (o.label.toLowerCase().contains(query) ||
                  o.key.toLowerCase().contains(query))
                o,
          ];
    return [
      SliverToBoxAdapter(
        child: SectionHeader(
          title: 'transactions.apps'.tr(),
          count: _pickedCount(_appsActive ? _apps.length : 0),
          padding: _headerPadding(),
          trailing: _sectionTrailing(
            context,
            active: _appsActive,
            onClear: () => _update(_apps.clear),
          ),
        ),
      ),
      if (widget.options.length > _appSearchThreshold)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter,
              AppSpace.xxs,
              AppSpace.gutter,
              AppSpace.sm,
            ),
            child: _SearchField(
              controller: _appSearch,
              hint: 'transactions.searchApps'.tr(),
              onChanged: () => setState(() {}),
            ),
          ),
        ),
      if (apps.isEmpty)
        SliverToBoxAdapter(child: _NoMatches(query: _appSearch.text.trim()))
      else
        GroupedSliverList(
          itemCount: apps.length,
          dividerIndent: _rowDividerIndent,
          itemBuilder: (context, i) {
            final app = apps[i];
            return _OptionRow(
              leading: _AppAvatar(appId: app.appId),
              label: app.label,
              count: _countFor(_facets.byApp[app.key]),
              selected: _apps.contains(app.key),
              onTap: () => _toggle(_apps, app.key),
            );
          },
        ),
    ];
  }

  List<Widget> _countrySlivers(BuildContext context, {bool first = false}) {
    final tt = context.textTheme;
    final scheme = context.colorScheme;
    final rawQuery = _countrySearch.text.trim();
    final query = rawQuery.toLowerCase();
    bool matches(String code, String name) =>
        query.isEmpty ||
        name.toLowerCase().contains(query) ||
        code.toLowerCase().contains(query);
    final rows = [
      if (matches('', _countryName(_unknownCountry))) _unknownCountry,
      for (final c in _allCountries)
        if (matches(c.code, c.displayName)) c.code,
    ];

    return [
      SliverToBoxAdapter(
        child: SectionHeader(
          title: 'transactions.country'.tr(),
          count: _pickedCount(_countries.length),
          padding: _headerPadding(first: first),
          trailing: _sectionTrailing(
            context,
            active: _countries.isNotEmpty,
            onClear: () => _update(_countries.clear),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.xxs,
            AppSpace.gutter,
            AppSpace.sm,
          ),
          child: _SearchField(
            controller: _countrySearch,
            hint: 'transactions.searchCountries'.tr(),
            onChanged: () => setState(() {}),
          ),
        ),
      ),
      if (query.isEmpty && _quickCountries.isNotEmpty) ...[
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
          sliver: SliverToBoxAdapter(
            child: Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: [
                for (final code in _quickCountries)
                  _CountryChip(
                    flag: countryInsightLeadingEmoji(code),
                    name: _countryName(code),
                    count: _countFor(_facets.byCountry[code]),
                    selected: _countries.contains(code),
                    onTap: () => _toggleCountry(code),
                  ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.lg,
              AppSpace.lg,
              AppSpace.xs,
            ),
            child: Text(
              'transactions.allCountries'.tr(),
              style: tt.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      ],
      if (rows.isEmpty)
        SliverToBoxAdapter(child: _NoMatches(query: rawQuery))
      else
        GroupedSliverList(
          itemCount: rows.length,
          dividerIndent: _rowDividerIndent,
          itemBuilder: (context, i) {
            final code = rows[i];
            return _OptionRow(
              leading: _FlagTile(flag: countryInsightLeadingEmoji(code)),
              label: _countryName(code),
              count: _countFor(_facets.byCountry[code]),
              selected: _countries.contains(code),
              onTap: () => _toggleCountry(code),
            );
          },
        ),
    ];
  }

  Widget _footer(BuildContext context, {required bool wide}) {
    final label = widget.transactions.isEmpty
        ? 'transactions.done'.tr()
        : 'transactions.showResults'.plural(_facets.matching, format: _number);
    final show = FilledButton(
      onPressed: () => Navigator.of(context).pop(),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
      ),
      child: AnimatedSwitcher(
        duration: AppMotion.of(context, AppMotion.fast),
        child: Text(
          label,
          key: ValueKey(label),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.appColors.hairline)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.gutter,
          vertical: AppSpace.sm,
        ),
        child: wide
            ? Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 220),
                  child: show,
                ),
              )
            : show,
      ),
    );
  }
}

/// How many transactions each choice would show alongside the other
/// sections' picks, so a dead end reads as 0 before it's tapped.
class _Facets {
  _Facets(
    List<RcTransaction> transactions, {
    Set<String>? apps,
    Set<String>? countries,
    Set<TransactionPlatformFilter>? stores,
  }) {
    final single = {
      for (final p in TransactionPlatformFilter.values) p: {p},
    };
    for (final tx in transactions) {
      final appKey = appKeyForTransaction(tx);
      final app = apps == null || apps.contains(appKey);
      final country = transactionMatchesCountryFilters(tx, countries);
      final store = transactionMatchesPlatformFilter(tx, stores);
      if (app && country && store) matching++;
      if (app && country) {
        for (final p in TransactionPlatformFilter.values) {
          if (transactionMatchesPlatformFilter(tx, single[p])) {
            byStore.update(p, (n) => n + 1, ifAbsent: () => 1);
          }
        }
      }
      if (country && store) {
        byApp.update(appKey, (n) => n + 1, ifAbsent: () => 1);
      }
      if (app && store) {
        byCountry.update(_countryKey(tx), (n) => n + 1, ifAbsent: () => 1);
      }
    }
  }

  int matching = 0;
  final byStore = <TransactionPlatformFilter, int>{};
  final byApp = <String, int>{};
  final byCountry = <String, int>{};
}

/// Number of sections with a pick, beside the title.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return AnimatedScale(
      scale: count == 0 ? 0 : 1,
      duration: AppMotion.of(context, AppMotion.duration),
      curve: count == 0 ? Curves.easeIn : Curves.easeOutBack,
      child: Container(
        constraints: const BoxConstraints(minWidth: 24),
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          '${count == 0 ? '' : count}',
          style: context.textTheme.labelMedium?.copyWith(
            color: scheme.onPrimary,
            fontWeight: FontWeight.w800,
            fontFeatures: AppText.tabular,
          ),
        ),
      ),
    );
  }
}

class _StoreTile extends StatelessWidget {
  const _StoreTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    final selectedFill = Color.alphaBlend(
      scheme.primary.withValues(alpha: context.isDark ? 0.18 : 0.08),
      scheme.surfaceContainerLow,
    );
    return MergeSemantics(
      child: Semantics(
        checked: selected,
        child: PressableScale(
          child: AnimatedContainer(
            duration: AppMotion.of(context, AppMotion.fast),
            curve: AppMotion.curve,
            decoration: BoxDecoration(
              color: selected ? selectedFill : scheme.surfaceContainerLow,
              borderRadius: AppRadius.tileAll,
              border: Border.all(
                color: selected ? scheme.primary : context.appColors.hairline,
                width: 1.5,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                borderRadius: AppRadius.tileAll,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(
                                AppRadius.icon,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Icon(icon, size: 20, color: color),
                          ),
                          const Spacer(),
                          _SelectionMark(selected: selected),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          label,
                          maxLines: 1,
                          style: tt.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (count != null)
                        Text(
                          NumberFormat.decimalPattern().format(count),
                          style: tt.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontFeatures: AppText.tabular,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One app or country: tile, name, how many transactions it has, check box.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.leading,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final Widget leading;
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    final n = count;
    // Nothing to show with the other picks: muted, still pickable.
    final empty = n == 0 && !selected;
    return MergeSemantics(
      child: Semantics(
        checked: selected,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyLarge?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: empty ? scheme.onSurfaceVariant : null,
                    ),
                  ),
                ),
                if (n != null && n > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, right: 12),
                    child: Text(
                      NumberFormat.decimalPattern().format(n),
                      style: tt.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: AppText.tabular,
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 12),
                _SelectionMark(selected: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded check box that fills with the accent when picked.
class _SelectionMark extends StatelessWidget {
  const _SelectionMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final duration = AppMotion.of(context, AppMotion.fast);
    return AnimatedContainer(
      duration: duration,
      curve: AppMotion.curve,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: selected ? scheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: selected
              ? scheme.primary
              : scheme.onSurfaceVariant.withValues(alpha: 0.45),
          width: 1.5,
        ),
      ),
      child: AnimatedScale(
        scale: selected ? 1 : 0,
        duration: duration,
        curve: selected ? Curves.easeOutBack : Curves.easeIn,
        child: Icon(Icons.check_rounded, size: 16, color: scheme.onPrimary),
      ),
    );
  }
}

class _CountryChip extends StatelessWidget {
  const _CountryChip({
    required this.flag,
    required this.name,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String flag;
  final String name;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.textTheme;
    final n = count;
    return FilterChip(
      showCheckmark: false,
      selected: selected,
      onSelected: (_) => onTap(),
      label: Text.rich(
        TextSpan(
          text: '$flag  $name',
          children: [
            if (n != null && n > 0)
              TextSpan(
                text: '  ${NumberFormat.decimalPattern().format(n)}',
                style: TextStyle(
                  color: context.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                  fontFeatures: AppText.tabular,
                ),
              ),
          ],
        ),
        style: tt.labelLarge?.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: n == 0 && !selected
              ? context.colorScheme.onSurfaceVariant
              : null,
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: (_) => onChanged(),
      textInputAction: TextInputAction.search,
      decoration: searchFieldDecoration(context.colorScheme, hint).copyWith(
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'transactions.clear'.tr(),
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  controller.clear();
                  onChanged();
                },
              ),
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.xs,
        AppSpace.lg,
        AppSpace.xs,
      ),
      child: Text(
        'transactions.noSearchMatches'.tr(namedArgs: {'query': query}),
        style: context.textTheme.bodyMedium?.copyWith(
          color: context.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _FlagTile extends StatelessWidget {
  const _FlagTile({required this.flag});

  final String flag;

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
      child: Text(flag, style: const TextStyle(fontSize: 19, height: 1.05)),
    );
  }
}

class _AppAvatar extends ConsumerWidget {
  const _AppAvatar({required this.appId});

  final String? appId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.colorScheme;
    final url = appId != null
        ? ref.watch(resolvedAppIconsProvider)[appId]
        : null;
    return TransactionLeadingAvatar(
      imageUrl: url,
      size: 36,
      borderRadius: AppRadius.icon,
      tintColor: scheme.primary,
      fallback: Icon(Icons.apps_rounded, color: scheme.primary, size: 18),
    );
  }
}
