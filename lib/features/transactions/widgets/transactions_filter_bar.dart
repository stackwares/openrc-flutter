import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/core/utils/region_display_name.dart';
import 'package:openrc/core/utils/store_display_name.dart';
import 'package:openrc/features/transactions/transactions_common.dart';
import 'package:openrc/features/transactions/transactions_screen.dart';
import 'package:openrc/features/transactions/widgets/day_summary_card.dart';
import 'package:openrc/features/transactions/widgets/transaction_leading_avatar.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/auto_app_icons_store.dart';
import 'package:openrc/services/rc_account_projects_provider.dart';
import 'package:openrc/theme/app_tokens.dart';

const double _chipHeight = 36;
const double _chipPadding = 12;
const double _chipIconSize = 18;
const double _chipIconGap = 6;
const double _chipSpacing = 8;

/// Country key for transactions without a country.
const String _unknownCountry = '__';

/// ⌘ on Apple platforms, Ctrl elsewhere: held while clicking a project to
/// pick several.
bool get _usesCommandKey =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

bool get _addsToSelection =>
    HardwareKeyboard.instance.isMetaPressed ||
    HardwareKeyboard.instance.isControlPressed;

String _platformName(TransactionPlatformFilter p) =>
    transactionPlatformFilterLabel(p);

IconData _platformIcon(TransactionPlatformFilter p) => switch (p) {
  TransactionPlatformFilter.apple => Icons.apple,
  TransactionPlatformFilter.google => Icons.android,
  TransactionPlatformFilter.web => Icons.language_rounded,
};

String _countryName(String code) => code == _unknownCountry
    ? 'transactions.unknown'.tr()
    : regionDisplayNameEnglish(code);

String _countryFlag(String code) =>
    code == _unknownCountry ? '🌐' : countryFlagEmoji(code);

/// Filters above the dashboard (wide Transactions and Revenue): projects as
/// chips, then store and country menus. Reads and writes the shared filter
/// providers, so both tabs and the filter sheet stay in step.
class TransactionsFilterBar extends ConsumerWidget {
  const TransactionsFilterBar({
    super.key,
    required this.transactions,
    required this.onOpenAllFilters,
    this.sectionFilters = const {},
    this.onRemoveSection,
    this.onClearSections,
  });

  /// The tab's rows before filtering: the countries the menu offers.
  final List<RcTransaction> transactions;

  /// Opens the full filter sheet (country search).
  final VoidCallback onOpenAllFilters;

  /// Type tiles picked on the page, shown as removable chips.
  final Set<TransactionDaySectionFilter> sectionFilters;
  final ValueChanged<TransactionDaySectionFilter>? onRemoveSection;
  final VoidCallback? onClearSections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(transactionsAppIncludeFilterProvider);
    final platforms = ref.watch(transactionsPlatformFilterProvider);
    final countries = ref.watch(transactionsCountryFilterProvider);
    final projects =
        ref.watch(rcAccountProjectsProvider).asData?.value ?? const [];

    final options = collectAppFilterOptionsWithProjects(
      {'_': transactions},
      projects,
    )..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    final projectIcons = {
      for (final p in projects)
        if (p.id != null && p.iconUrl != null) p.id!: p.iconUrl!,
    };

    final active =
        apps != null ||
        (platforms != null && platforms.isNotEmpty) ||
        (countries != null && countries.isNotEmpty) ||
        sectionFilters.isNotEmpty;

    void clearAll() {
      ref.read(transactionsAppIncludeFilterProvider.notifier).state = null;
      ref.read(transactionsPlatformFilterProvider.notifier).state = null;
      ref.read(transactionsCountryFilterProvider.notifier).state = null;
      onClearSections?.call();
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm, bottom: AppSpace.xs),
      child: Row(
        children: [
          Expanded(
            child: options.length > 1
                ? _ProjectChips(
                    options: options,
                    projectIcons: projectIcons,
                    selected: apps,
                    onChanged: (next) =>
                        ref
                                .read(
                                  transactionsAppIncludeFilterProvider.notifier,
                                )
                                .state =
                            next,
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: AppSpace.sm),
          for (final f in sectionFilters) ...[
            _BarChip(
              label: daySummaryTileLabel(f),
              selected: true,
              leading: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: daySummaryPillAccent(context, f),
                  shape: BoxShape.circle,
                ),
              ),
              trailingIcon: Icons.close_rounded,
              onTap: onRemoveSection == null ? null : () => onRemoveSection!(f),
            ),
            const SizedBox(width: _chipSpacing),
          ],
          _StoreMenu(
            selected: platforms ?? const {},
            onChanged: (next) =>
                ref.read(transactionsPlatformFilterProvider.notifier).state =
                    next.isEmpty ? null : next,
          ),
          const SizedBox(width: _chipSpacing),
          _CountryMenu(
            transactions: transactions,
            selected: countries ?? const {},
            onChanged: (next) =>
                ref.read(transactionsCountryFilterProvider.notifier).state =
                    next.isEmpty ? null : next,
            onOpenAllFilters: onOpenAllFilters,
          ),
          AnimatedSize(
            duration: AppMotion.of(context, AppMotion.fast),
            curve: Curves.easeOut,
            child: active
                ? Padding(
                    padding: const EdgeInsets.only(left: AppSpace.xxs),
                    child: TextButton(
                      onPressed: clearAll,
                      child: Text('transactions.clearFilters'.tr()),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// "All projects", then a chip per project on one line; the ones that don't
/// fit go into a "+N more" menu.
class _ProjectChips extends ConsumerWidget {
  const _ProjectChips({
    required this.options,
    required this.projectIcons,
    required this.selected,
    required this.onChanged,
  });

  final List<AppFilterOption> options;
  final Map<String, String> projectIcons;

  /// `null` = every project.
  final Set<String>? selected;
  final ValueChanged<Set<String>?> onChanged;

  /// A plain click shows only [key] (or everything again when it was the
  /// only one); [add] adds or removes it from the picked projects.
  void _pick(String key, {required bool add}) {
    final current = selected;
    if (!add) {
      onChanged(
        current != null && current.length == 1 && current.contains(key)
            ? null
            : {key},
      );
      return;
    }
    final next = {...?current};
    if (!next.remove(key)) next.add(key);
    onChanged(next.isEmpty || next.length == options.length ? null : next);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icons = ref.watch(resolvedAppIconsProvider);
    final style = _BarChip.labelStyle(context);
    final scaler = MediaQuery.textScalerOf(context);
    final hint = _usesCommandKey
        ? 'transactions.filterBar.pickSeveralMac'.tr()
        : 'transactions.filterBar.pickSeveral'.tr();

    double widthOf(String label, {bool icon = false, bool chevron = false}) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout();
      return 2 * _chipPadding +
          2 +
          painter.width +
          (icon ? _chipIconSize + _chipIconGap : 0) +
          (chevron ? _chipIconSize + 2 : 0);
    }

    final allLabel = 'transactions.filterBar.allProjects'.tr();
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fits chips in order, keeping room for the "+N more" chip once
        // they stop fitting.
        final moreWidth = widthOf(
          'revenue.moreCount'.tr(namedArgs: {'count': '${options.length}'}),
          chevron: true,
        );
        var used = widthOf(allLabel) + _chipSpacing;
        var shown = 0;
        for (var i = 0; i < options.length; i++) {
          final w = widthOf(options[i].label, icon: true) + _chipSpacing;
          final last = i == options.length - 1;
          final room = constraints.maxWidth - (last ? 0 : moreWidth);
          if (used + w > room) break;
          used += w;
          shown++;
        }
        final hidden = options.sublist(shown);
        final current = selected;

        Widget avatar(AppFilterOption o) {
          final url = icons[o.key] ?? projectIcons[o.key];
          return TransactionLeadingAvatar(
            imageUrl: url,
            size: _chipIconSize,
            borderRadius: 5,
            tintColor: context.colorScheme.primary,
            fallback: Icon(
              Icons.apps_rounded,
              size: 12,
              color: context.colorScheme.primary,
            ),
          );
        }

        return Row(
          children: [
            _BarChip(
              label: allLabel,
              selected: current == null,
              onTap: () => onChanged(null),
            ),
            for (final o in options.take(shown)) ...[
              const SizedBox(width: _chipSpacing),
              Tooltip(
                message: hint,
                waitDuration: const Duration(milliseconds: 800),
                child: _BarChip(
                  label: o.label,
                  leading: avatar(o),
                  selected: current?.contains(o.key) ?? false,
                  onTap: () => _pick(o.key, add: _addsToSelection),
                ),
              ),
            ],
            if (hidden.isNotEmpty) ...[
              const SizedBox(width: _chipSpacing),
              _MenuChip(
                label: 'revenue.moreCount'.tr(
                  namedArgs: {'count': '${hidden.length}'},
                ),
                selected: hidden.any((o) => current?.contains(o.key) ?? false),
                menuChildren: [
                  for (final o in hidden)
                    CheckboxMenuButton(
                      value: current?.contains(o.key) ?? false,
                      closeOnActivate: false,
                      onChanged: (_) => _pick(o.key, add: true),
                      trailingIcon: avatar(o),
                      child: Text(o.label),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _StoreMenu extends StatelessWidget {
  const _StoreMenu({required this.selected, required this.onChanged});

  final Set<TransactionPlatformFilter> selected;
  final ValueChanged<Set<TransactionPlatformFilter>> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    Color tint(TransactionPlatformFilter p) => switch (p) {
      TransactionPlatformFilter.apple => colors.apple,
      TransactionPlatformFilter.google => colors.google,
      TransactionPlatformFilter.web => colors.web,
    };
    final label = switch (selected.length) {
      0 => 'transactions.filterBar.allStores'.tr(),
      1 => _platformName(selected.single),
      _ => 'transactions.storeCount'.plural(selected.length),
    };
    return _MenuChip(
      label: label,
      leadingIcon: selected.length == 1
          ? _platformIcon(selected.single)
          : Icons.storefront_outlined,
      selected: selected.isNotEmpty,
      menuChildren: [
        for (final p in TransactionPlatformFilter.values)
          CheckboxMenuButton(
            value: selected.contains(p),
            closeOnActivate: false,
            onChanged: (_) {
              final next = {...selected};
              if (!next.remove(p)) next.add(p);
              onChanged(next);
            },
            trailingIcon: Icon(_platformIcon(p), size: 18, color: tint(p)),
            child: Text(_platformName(p)),
          ),
      ],
    );
  }
}

class _CountryMenu extends StatelessWidget {
  const _CountryMenu({
    required this.transactions,
    required this.selected,
    required this.onChanged,
    required this.onOpenAllFilters,
  });

  final List<RcTransaction> transactions;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final VoidCallback onOpenAllFilters;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final tx in transactions) {
      final code = tx.subscriberCountryCode?.trim().toUpperCase();
      final key = code == null || code.isEmpty ? _unknownCountry : code;
      counts.update(key, (n) => n + 1, ifAbsent: () => 1);
    }
    // Busiest first, then any picked elsewhere (the sheet's full list).
    final codes = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0
            ? byCount
            : _countryName(a).compareTo(_countryName(b));
      });
    for (final c in selected) {
      if (!codes.contains(c)) codes.add(c);
    }

    final label = switch (selected.length) {
      0 => 'transactions.allCountries'.tr(),
      1 => '${_countryFlag(selected.single)}  ${_countryName(selected.single)}',
      _ => 'transactions.countryCount'.plural(selected.length),
    };
    final muted = context.textTheme.labelMedium?.copyWith(
      color: context.colorScheme.onSurfaceVariant,
      fontFeatures: AppText.tabular,
    );
    return _MenuChip(
      label: label,
      leadingIcon: selected.length == 1 ? null : Icons.public_rounded,
      selected: selected.isNotEmpty,
      menuChildren: [
        for (final c in codes)
          CheckboxMenuButton(
            value: selected.contains(c),
            closeOnActivate: false,
            onChanged: (_) {
              final next = {...selected};
              if (!next.remove(c)) next.add(c);
              onChanged(next);
            },
            trailingIcon: counts[c] == null
                ? null
                : Text(
                    NumberFormat.decimalPattern().format(counts[c]),
                    style: muted,
                  ),
            child: Text('${_countryFlag(c)}  ${_countryName(c)}'),
          ),
        if (codes.isNotEmpty) const Divider(height: 8),
        MenuItemButton(
          leadingIcon: const Icon(Icons.search_rounded, size: 18),
          onPressed: onOpenAllFilters,
          child: Text('transactions.filterBar.allCountriesMenu'.tr()),
        ),
      ],
    );
  }
}

/// A [_BarChip] that opens a menu below it.
class _MenuChip extends StatelessWidget {
  const _MenuChip({
    required this.label,
    required this.selected,
    required this.menuChildren,
    this.leadingIcon,
  });

  final String label;
  final bool selected;
  final List<Widget> menuChildren;
  final IconData? leadingIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      style: const MenuStyle(
        maximumSize: WidgetStatePropertyAll(Size(340, 440)),
      ),
      menuChildren: menuChildren,
      builder: (context, controller, _) => _BarChip(
        label: label,
        selected: selected,
        leading: leadingIcon == null
            ? null
            : Icon(
                leadingIcon,
                size: _chipIconSize,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
        trailingIcon: Icons.expand_more_rounded,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// Stadium chip used throughout the bar; tinted with the accent when
/// [selected].
class _BarChip extends StatelessWidget {
  const _BarChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
    this.trailingIcon,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? leading;
  final IconData? trailingIcon;

  static TextStyle? labelStyle(BuildContext context) =>
      context.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600);

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final fg = selected ? scheme.primary : scheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: AppMotion.of(context, AppMotion.fast),
        curve: Curves.easeOut,
        height: _chipHeight,
        decoration: ShapeDecoration(
          color: selected
              ? Color.alphaBlend(
                  scheme.primary.withValues(alpha: 0.14),
                  scheme.surfaceContainerLow,
                )
              : scheme.surfaceContainerLow,
          shape: StadiumBorder(
            side: BorderSide(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.5)
                  : context.appColors.hairline,
            ),
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _chipPadding),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: _chipIconGap),
                  ],
                  Text(
                    label,
                    maxLines: 1,
                    style: labelStyle(context)?.copyWith(color: fg),
                  ),
                  if (trailingIcon != null) ...[
                    const SizedBox(width: 2),
                    Icon(
                      trailingIcon,
                      size: _chipIconSize,
                      color: selected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
