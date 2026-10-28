import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/core/utils/currency_format.dart';
import 'package:openrc/services/display_currency_store.dart';
import 'package:openrc/widgets/adaptive_modal.dart';
import 'package:openrc/widgets/search_field_decoration.dart';
import 'package:openrc/services/telemetry.dart';

/// Picks the currency amounts are shown in.
Future<void> showDisplayCurrencySheet(BuildContext context) {
  return showAdaptiveSheet<void>(
    context: context,
    heightFactor: 0.8,
    builder: (_) => const _DisplayCurrencySheet(),
  );
}

class _DisplayCurrencySheet extends ConsumerStatefulWidget {
  const _DisplayCurrencySheet();

  @override
  ConsumerState<_DisplayCurrencySheet> createState() =>
      _DisplayCurrencySheetState();
}

class _DisplayCurrencySheetState extends ConsumerState<_DisplayCurrencySheet> {
  String _query = '';

  bool _matches(DisplayCurrencyOption option) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    return option.code.toLowerCase().contains(query) ||
        option.label.toLowerCase().contains(query) ||
        currencySymbolFor(option.code).toLowerCase().contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(displayCurrencyProvider);
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final options = [
      for (final option in kDisplayCurrencyOptions)
        if (_matches(option)) option,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'settings.displayCurrency'.tr(),
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'settings.currencySheetBody'.tr(),
                style: tt.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                onChanged: (value) => setState(() => _query = value),
                textInputAction: TextInputAction.search,
                decoration: searchFieldDecoration(
                  scheme,
                  'settings.searchCurrencies'.tr(),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: options.isEmpty
              ? Center(
                  child: Text(
                    'settings.noCurrencies'.tr(),
                    style: tt.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 16 + bottom),
                  itemCount: options.length,
                  itemBuilder: (context, i) {
                    final o = options[i];
                    final isSelected = o.code == selected;
                    return _CurrencyRow(
                      option: o,
                      selected: isSelected,
                      onTap: () async {
                        await ref
                            .read(displayCurrencyProvider.notifier)
                            .setCurrency(o.code);
                        Telemetry.preferenceChanged(setting: 'currency');
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CurrencyRow extends StatelessWidget {
  const _CurrencyRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final DisplayCurrencyOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    final label = option.label.isEmpty
        ? option.code
        : '${option.label[0].toUpperCase()}${option.label.substring(1)}';
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            child: Row(
              children: [
                Text(option.flagEmoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: tt.bodyLarge?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  '${currencySymbolFor(option.code).trim()}  ${option.code}',
                  style: tt.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: selected
                      ? Icon(Icons.check_rounded, color: scheme.primary)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
