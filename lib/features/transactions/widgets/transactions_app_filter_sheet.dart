import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/core/utils/store_commission.dart';
import 'package:revenuecat/features/transactions/transactions_common.dart';
import 'package:revenuecat/features/transactions/transactions_revenue_insights_compute.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_leading_avatar.dart';
import 'package:revenuecat/models/rc_project.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/app_icon_overrides_store.dart';

typedef TransactionsFilterSheetOnApply =
    void Function(
      Set<String>? includeApps,
      String? countryCode,
      StoreCommissionPlatform? platform,
    );

enum TransactionFilterPlatformSegment { all, apple, google, other }

TransactionFilterPlatformSegment transactionFilterPlatformSegmentFromFilter(
  StoreCommissionPlatform? p,
) {
  return switch (p) {
    null => TransactionFilterPlatformSegment.all,
    StoreCommissionPlatform.apple => TransactionFilterPlatformSegment.apple,
    StoreCommissionPlatform.google => TransactionFilterPlatformSegment.google,
    StoreCommissionPlatform.other => TransactionFilterPlatformSegment.other,
  };
}

StoreCommissionPlatform? storeCommissionPlatformFromFilterSegment(
  TransactionFilterPlatformSegment s,
) {
  return switch (s) {
    TransactionFilterPlatformSegment.all => null,
    TransactionFilterPlatformSegment.apple => StoreCommissionPlatform.apple,
    TransactionFilterPlatformSegment.google => StoreCommissionPlatform.google,
    TransactionFilterPlatformSegment.other => StoreCommissionPlatform.other,
  };
}

/// Bottom sheet to filter transactions by app, store platform, and country.
Future<void> showTransactionsAppFilterSheet({
  required BuildContext context,
  required Map<String, List<RcTransaction>> filterSource,
  required Set<String>? currentIncludeFilter,
  String? currentCountryCode,
  StoreCommissionPlatform? currentPlatform,
  List<RcProject> accountProjects = const [],
  required TransactionsFilterSheetOnApply onApply,
}) {
  final options = collectAppFilterOptionsWithProjects(
    filterSource,
    accountProjects,
  );
  if (options.isEmpty) return Future.value();

  final flatTxs = filterSource.values.expand((e) => e);
  final countryInfo = collectCountryFilterCodes(flatTxs);

  final allKeys = options.map((o) => o.key).toSet();
  final initialSelected = currentIncludeFilter == null
      ? Set<String>.from(allKeys)
      : () {
          final i = currentIncludeFilter.intersection(allKeys);
          return i.isEmpty ? Set<String>.from(allKeys) : i;
        }();

  final validCountryCodes = countryInfo.codes.toSet();
  final initialCountry = () {
    final c = currentCountryCode;
    if (c == null) return null;
    if (c == '__') return countryInfo.hasUnknown ? '__' : null;
    final u = c.toUpperCase();
    return validCountryCodes.contains(u) ? u : null;
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
              countryCodes: countryInfo.codes,
              hasUnknownCountry: countryInfo.hasUnknown,
              initialCountryCode: initialCountry,
              initialPlatformSegment: transactionFilterPlatformSegmentFromFilter(
                currentPlatform,
              ),
              onApply: (selected, country, platform) {
                Navigator.pop(sheetContext);
                final apps = selected.length == allKeys.length ? null : selected;
                onApply(apps, country, platform);
              },
            ),
          ),
        ),
      );
    },
  );
}

class TransactionsAppFilterModal extends StatefulWidget {
  final List<AppFilterOption> options;
  final Set<String> allKeys;
  final Set<String> initialSelected;
  final List<String> countryCodes;
  final bool hasUnknownCountry;
  final String? initialCountryCode;
  final TransactionFilterPlatformSegment initialPlatformSegment;
  final void Function(
    Set<String> selected,
    String? countryCode,
    StoreCommissionPlatform? platform,
  )
  onApply;

  const TransactionsAppFilterModal({
    super.key,
    required this.options,
    required this.allKeys,
    required this.initialSelected,
    required this.countryCodes,
    required this.hasUnknownCountry,
    required this.initialCountryCode,
    required this.initialPlatformSegment,
    required this.onApply,
  });

  @override
  State<TransactionsAppFilterModal> createState() =>
      _TransactionsAppFilterModalState();
}

class _TransactionsAppFilterModalState extends State<TransactionsAppFilterModal> {
  late Set<String> _selected;
  late String? _countryCode;
  late TransactionFilterPlatformSegment _platformSeg;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initialSelected);
    _countryCode = widget.initialCountryCode;
    _platformSeg = widget.initialPlatformSegment;
  }

  bool get _showCountrySection =>
      widget.countryCodes.isNotEmpty || widget.hasUnknownCountry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final countrySegments = <ButtonSegment<String?>>[
      const ButtonSegment<String?>(value: null, label: Text('All')),
      ...widget.countryCodes.map(
        (code) => ButtonSegment<String?>(
          value: code,
          label: Text(
            '${countryInsightLeadingEmoji(code)} $code',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      if (widget.hasUnknownCountry)
        ButtonSegment<String?>(
          value: '__',
          label: Text('${countryInsightLeadingEmoji('__')} Other'),
        ),
    ];

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
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Platform',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SegmentedButton<TransactionFilterPlatformSegment>(
            style: SegmentedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: TransactionFilterPlatformSegment.all,
                label: Text('All'),
              ),
              ButtonSegment(
                value: TransactionFilterPlatformSegment.apple,
                label: Text('Apple'),
              ),
              ButtonSegment(
                value: TransactionFilterPlatformSegment.google,
                label: Text('Google'),
              ),
              ButtonSegment(
                value: TransactionFilterPlatformSegment.other,
                label: Text('Other'),
              ),
            ],
            selected: {_platformSeg},
            onSelectionChanged: (next) {
              if (next.isEmpty) return;
              setState(() => _platformSeg = next.single);
            },
          ),
        ),
        if (_showCountrySection) ...[
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Country',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, _) {
              final vw = MediaQuery.sizeOf(context).width;
              const minSeg = 72.0;
              final minBar = math.max(
                vw - 40,
                countrySegments.length * minSeg,
              );
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: minBar),
                  child: SegmentedButton<String?>(
                    style: SegmentedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                    showSelectedIcon: false,
                    segments: countrySegments,
                    selected: {_countryCode},
                    onSelectionChanged: (next) {
                      if (next.isEmpty) return;
                      setState(() => _countryCode = next.single);
                    },
                  ),
                ),
              );
            },
          ),
        ],
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
          child: Row(
            children: [
              Text(
                'Apps',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() => _selected = Set<String>.from(widget.allKeys));
                },
                child: const Text('ALL'),
              ),
              TextButton(
                onPressed: () => setState(() => _selected = {}),
                child: const Text('NONE'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: widget.options.length,
            itemBuilder: (context, index) {
              final opt = widget.options[index];
              return CheckboxListTile(
                value: _selected.contains(opt.key),
                onChanged: (checked) {
                  setState(() {
                    if (checked == true) {
                      _selected.add(opt.key);
                    } else {
                      _selected.remove(opt.key);
                    }
                  });
                },
                title: Row(
                  children: [
                    Consumer(
                      builder: (context, ref, _) {
                        final scheme = Theme.of(context).colorScheme;
                        final url = opt.appId != null
                            ? ref.watch(appIconOverridesProvider)[opt.appId]
                            : null;
                        return TransactionLeadingAvatar(
                          imageUrl: url,
                          size: 40,
                          borderRadius: 10,
                          tintColor: scheme.primary,
                          fallback: Icon(
                            Icons.apps_outlined,
                            color: scheme.primary,
                            size: 22,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        opt.label,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ),
                controlAffinity: ListTileControlAffinity.leading,
              );
            },
          ),
        ),
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
                  _countryCode,
                  storeCommissionPlatformFromFilterSegment(_platformSeg),
                ),
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
