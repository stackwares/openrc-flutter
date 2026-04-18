import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/core/utils/region_display_name.dart';
import 'package:revenuecat/core/theme/store_brand_icon_colors.dart';
import 'package:revenuecat/features/transactions/transactions_common.dart';
import 'package:revenuecat/features/transactions/transactions_revenue_insights_compute.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_leading_avatar.dart';
import 'package:revenuecat/models/rc_project.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/app_icon_overrides_store.dart';

typedef TransactionsFilterSheetOnApply =
    void Function(
      Set<String>? includeApps,
      Set<String>? countryCodes,
      Set<TransactionPlatformFilter>? platforms,
    );

enum _FilterSheetPanel { apps, country }

Set<String> _normalizedCountrySelection(Set<String>? raw) {
  if (raw == null || raw.isEmpty) return {};
  final allowed = {
    for (final e in sortedSupportedIso3166Alpha2Countries()) e.code,
    '__',
  };
  final out = <String>{};
  for (final c in raw) {
    final u = c.trim().toUpperCase();
    if (allowed.contains(u)) out.add(u);
  }
  return out;
}

InputDecoration _filterSheetSearchDecoration(ColorScheme scheme, String hint) {
  return InputDecoration(
    hintText: hint,
    prefixIcon: const Icon(Icons.search_rounded, size: 22),
    filled: true,
    fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
  );
}

/// Bottom sheet to filter transactions by app, store platform, and country.
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

  final allKeys = options.map((o) => o.key).toSet();
  final initialSelected = currentIncludeFilter == null
      ? Set<String>.from(allKeys)
      : () {
          final i = currentIncludeFilter.intersection(allKeys);
          return i.isEmpty ? Set<String>.from(allKeys) : i;
        }();

  final maxHeight = MediaQuery.sizeOf(context).height * 0.75;

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SizedBox(
            height: maxHeight,
            child: TransactionsAppFilterModal(
              options: options,
              allKeys: allKeys,
              initialSelected: initialSelected,
              initialCountrySelection: _normalizedCountrySelection(
                currentCountryCodes,
              ),
              initialPlatformSelection:
                  currentPlatforms == null || currentPlatforms.isEmpty
                  ? <TransactionPlatformFilter>{}
                  : Set<TransactionPlatformFilter>.from(currentPlatforms),
              onApply: (selected, countries, platforms) {
                Navigator.pop(sheetContext);
                final apps = selected.length == allKeys.length ? null : selected;
                onApply(apps, countries, platforms);
              },
            ),
          ),
        ),
      );
    },
  );
}

class TransactionsAppFilterModal extends ConsumerStatefulWidget {
  final List<AppFilterOption> options;
  final Set<String> allKeys;
  final Set<String> initialSelected;
  final Set<String> initialCountrySelection;
  final Set<TransactionPlatformFilter> initialPlatformSelection;
  final void Function(
    Set<String> selected,
    Set<String>? countryCodes,
    Set<TransactionPlatformFilter>? platforms,
  )
  onApply;

  const TransactionsAppFilterModal({
    super.key,
    required this.options,
    required this.allKeys,
    required this.initialSelected,
    required this.initialCountrySelection,
    required this.initialPlatformSelection,
    required this.onApply,
  });

  @override
  ConsumerState<TransactionsAppFilterModal> createState() =>
      _TransactionsAppFilterModalState();
}

class _TransactionsAppFilterModalState
    extends ConsumerState<TransactionsAppFilterModal> {
  late Set<String> _selected;
  late Set<TransactionPlatformFilter> _platformSelection;
  late Set<String> _countrySelection;
  _FilterSheetPanel _panel = _FilterSheetPanel.apps;
  String _appSearchQuery = '';
  String _countrySearchQuery = '';

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initialSelected);
    _platformSelection =
        Set<TransactionPlatformFilter>.from(widget.initialPlatformSelection);
    _countrySelection = Set<String>.from(widget.initialCountrySelection);
  }

  List<AppFilterOption> get _appsMatchingSearch {
    final q = _appSearchQuery.trim().toLowerCase();
    if (q.isEmpty) return widget.options;
    return widget.options.where((o) {
      return o.label.toLowerCase().contains(q) ||
          o.key.toLowerCase().contains(q);
    }).toList();
  }

  List<({String code, String displayName})> get _countriesMatchingSearch {
    final q = _countrySearchQuery.trim().toLowerCase();
    final all = sortedSupportedIso3166Alpha2Countries();
    if (q.isEmpty) return all;
    return all.where((e) {
      return e.displayName.toLowerCase().contains(q) ||
          e.code.toLowerCase().contains(q);
    }).toList();
  }

  bool get _unknownChipMatchesSearch {
    final q = _countrySearchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    return 'unknown'.contains(q) ||
        'other'.contains(q) ||
        '__'.contains(q) ||
        'missing'.contains(q);
  }

  bool get _allAppsSelected =>
      _selected.length == widget.allKeys.length && widget.allKeys.isNotEmpty;

  String get _platformSummaryLine {
    if (_platformSelection.isEmpty) {
      return 'All platforms (no store filter)';
    }
    if (_platformSelection.length == 1) {
      return switch (_platformSelection.first) {
        TransactionPlatformFilter.apple => 'Apple App Store',
        TransactionPlatformFilter.google => 'Google Play',
        TransactionPlatformFilter.web => 'Web & third-party billing',
        TransactionPlatformFilter.test => 'Sandbox & test purchases',
      };
    }
    return '${_platformSelection.length} platforms selected';
  }

  List<
    ({
      TransactionPlatformFilter filter,
      String label,
      IconData icon,
      Color? iconColor,
    })
  >
  _platformChipDefs(ColorScheme scheme) {
    return [
      (
        filter: TransactionPlatformFilter.apple,
        label: 'Apple',
        icon: Icons.phone_iphone_rounded,
        iconColor: storeBrandIconTint('App Store') ?? scheme.primary,
      ),
      (
        filter: TransactionPlatformFilter.google,
        label: 'Google Play',
        icon: Icons.android_rounded,
        iconColor: storeBrandIconTint('Play Store') ?? scheme.primary,
      ),
      (
        filter: TransactionPlatformFilter.web,
        label: 'Web',
        icon: Icons.language_rounded,
        iconColor: scheme.primary,
      ),
      (
        filter: TransactionPlatformFilter.test,
        label: 'Test',
        icon: Icons.science_outlined,
        iconColor: scheme.primary,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(
            'Filters',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _platformSummaryLine,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _platformSelection.isEmpty
                        ? null
                        : () => setState(() => _platformSelection = {}),
                    child: const Text('Reset'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in _platformChipDefs(scheme))
                    FilterChip(
                      showCheckmark: false,
                      selected: _platformSelection.contains(p.filter),
                      avatar: CircleAvatar(
                        radius: 14,
                        backgroundColor: scheme.surfaceContainerHighest
                            .withValues(alpha: 0.65),
                        child: Icon(
                          p.icon,
                          size: 18,
                          color: p.iconColor ?? scheme.primary,
                        ),
                      ),
                      label: Text(
                        p.label,
                        style: theme.textTheme.labelLarge,
                      ),
                      onSelected: (sel) {
                        setState(() {
                          if (sel) {
                            _platformSelection.add(p.filter);
                          } else {
                            _platformSelection.remove(p.filter);
                          }
                        });
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SegmentedButton<_FilterSheetPanel>(
            style: SegmentedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment<_FilterSheetPanel>(
                value: _FilterSheetPanel.apps,
                label: Text('Apps'),
                icon: Icon(Icons.apps_outlined, size: 18),
              ),
              ButtonSegment<_FilterSheetPanel>(
                value: _FilterSheetPanel.country,
                label: Text('Country'),
                icon: Icon(Icons.public_outlined, size: 18),
              ),
            ],
            selected: {_panel},
            onSelectionChanged: (next) {
              if (next.isEmpty) return;
              setState(() => _panel = next.single);
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildPanelBody(theme, scheme)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => widget.onApply(
                  Set<String>.from(_selected),
                  _countrySelection.isEmpty
                      ? null
                      : Set<String>.from(_countrySelection),
                  _platformSelection.isEmpty
                      ? null
                      : Set<TransactionPlatformFilter>.from(
                          _platformSelection,
                        ),
                ),
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPanelBody(ThemeData theme, ColorScheme scheme) {
    switch (_panel) {
      case _FilterSheetPanel.apps:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selected.isEmpty
                          ? 'No apps selected'
                          : _allAppsSelected
                          ? 'All apps included'
                          : '${_selected.length} of ${widget.allKeys.length} apps',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed:
                        _allAppsSelected || widget.allKeys.isEmpty
                        ? null
                        : () => setState(
                            () => _selected = Set<String>.from(widget.allKeys),
                          ),
                    child: const Text('All'),
                  ),
                  TextButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => setState(() => _selected = {}),
                    child: const Text('None'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: TextField(
                onChanged: (v) => setState(() => _appSearchQuery = v),
                decoration: _filterSheetSearchDecoration(
                  scheme,
                  'Search apps',
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final opt in _appsMatchingSearch)
                      FilterChip(
                        showCheckmark: false,
                        selected: _selected.contains(opt.key),
                        avatar: _AppChipAvatar(
                          appId: opt.appId,
                          scheme: scheme,
                        ),
                        label: Text(
                          opt.label,
                          style: theme.textTheme.labelLarge,
                        ),
                        onSelected: (sel) {
                          setState(() {
                            if (sel) {
                              _selected.add(opt.key);
                            } else {
                              _selected.remove(opt.key);
                            }
                          });
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      case _FilterSheetPanel.country:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _countrySelection.isEmpty
                          ? 'All regions (no country filter)'
                          : '${_countrySelection.length} region${_countrySelection.length == 1 ? '' : 's'} selected',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _countrySelection.isEmpty
                        ? null
                        : () => setState(() => _countrySelection = {}),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: TextField(
                onChanged: (v) => setState(() => _countrySearchQuery = v),
                decoration: _filterSheetSearchDecoration(
                  scheme,
                  'Search countries',
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_unknownChipMatchesSearch)
                      FilterChip(
                        showCheckmark: false,
                        selected: _countrySelection.contains('__'),
                        label: Text(
                          '${countryInsightLeadingEmoji('__')} Unknown',
                          style: theme.textTheme.labelLarge,
                        ),
                        onSelected: (sel) {
                          setState(() {
                            if (sel) {
                              _countrySelection.add('__');
                            } else {
                              _countrySelection.remove('__');
                            }
                          });
                        },
                      ),
                    ..._countriesMatchingSearch.map((e) {
                      final code = e.code;
                      final selected = _countrySelection.contains(code);
                      return FilterChip(
                        showCheckmark: false,
                        selected: selected,
                        label: Text(
                          '${countryInsightLeadingEmoji(code)} ${e.displayName}',
                          style: theme.textTheme.labelLarge,
                        ),
                        onSelected: (sel) {
                          setState(() {
                            if (sel) {
                              _countrySelection.add(code);
                            } else {
                              _countrySelection.remove(code);
                            }
                          });
                        },
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        );
    }
  }
}

class _AppChipAvatar extends ConsumerWidget {
  const _AppChipAvatar({required this.appId, required this.scheme});

  final String? appId;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = appId != null
        ? ref.watch(appIconOverridesProvider)[appId]
        : null;
    return CircleAvatar(
      radius: 14,
      backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: TransactionLeadingAvatar(
          imageUrl: url,
          size: 26,
          borderRadius: 8,
          tintColor: scheme.primary,
          fallback: Icon(
            Icons.apps_outlined,
            color: scheme.primary,
            size: 16,
          ),
        ),
      ),
    );
  }
}
