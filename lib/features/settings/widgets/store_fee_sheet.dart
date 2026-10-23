import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/core/utils/currency_format.dart';
import 'package:openrc/features/settings/widgets/settings_rows.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/adaptive_modal.dart';
import 'package:openrc/widgets/animated_reveal.dart';

/// Example sale used to show what a fee means in money.
const double kStoreFeeExampleSale = 9.99;

/// `12.5` → `12.5%`, `15.0` → `15%`.
String formatFeePercent(double v) => (v - v.roundToDouble()).abs() < 1e-9
    ? '${v.round()}%'
    : '${v.toStringAsFixed(1)}%';

/// "A $9.99 sale counts as $8.49" for a fee of [percent].
String storeFeeExample(double percent) => 'settings.storeFeeExample'.tr(
  namedArgs: {
    'sale': formatExactUsd(kStoreFeeExampleSale),
    'counted': formatExactUsd(kStoreFeeExampleSale * (1 - percent / 100)),
  },
);

/// Edits one store's fee. Returns the new percent, or null when dismissed.
Future<double?> showStoreFeeSheet(
  BuildContext context, {
  required String store,
  required String company,
  required IconData icon,
  required double current,
}) {
  return showAdaptiveSheet<double>(
    context: context,
    builder: (_) => _StoreFeeSheet(
      store: store,
      company: company,
      icon: icon,
      current: current,
    ),
  );
}

enum _FeeChoice { fifteen, thirty, custom }

class _StoreFeeSheet extends StatefulWidget {
  const _StoreFeeSheet({
    required this.store,
    required this.company,
    required this.icon,
    required this.current,
  });

  final String store;

  /// Who takes the fee ("Apple", "Google").
  final String company;
  final IconData icon;
  final double current;

  @override
  State<_StoreFeeSheet> createState() => _StoreFeeSheetState();
}

class _StoreFeeSheetState extends State<_StoreFeeSheet> {
  late _FeeChoice _choice;
  late final TextEditingController _custom;
  final _customFocus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.current;
    _choice = c == 15
        ? _FeeChoice.fifteen
        : c == 30
        ? _FeeChoice.thirty
        : _FeeChoice.custom;
    _custom = TextEditingController(
      text: _choice == _FeeChoice.custom
          ? formatFeePercent(c).replaceAll('%', '')
          : '',
    );
  }

  @override
  void dispose() {
    _custom.dispose();
    _customFocus.dispose();
    super.dispose();
  }

  void _choose(_FeeChoice choice) {
    final previous = _value;
    setState(() {
      _choice = choice;
      _error = null;
    });
    if (choice != _FeeChoice.custom) return;
    // Start from the fee they had, selected, so typing replaces it.
    if (_custom.text.trim().isEmpty && previous != null) {
      _custom.text = formatFeePercent(previous).replaceAll('%', '');
    }
    _custom.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _custom.text.length,
    );
    _customFocus.requestFocus();
  }

  /// The chosen fee, or null when the custom field isn't a valid 0–100.
  double? get _value => switch (_choice) {
    _FeeChoice.fifteen => 15,
    _FeeChoice.thirty => 30,
    _FeeChoice.custom => () {
      final v = double.tryParse(_custom.text.trim().replaceAll(',', '.'));
      return v == null || v < 0 || v > 100 ? null : v;
    }(),
  };

  void _save() {
    final v = _value;
    if (v == null) {
      setState(() => _error = 'settings.feeRangeError'.tr());
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    final value = _value;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SettingsIconTile(icon: widget.icon),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'settings.storeFeeTitle'.tr(
                    namedArgs: {'store': widget.store},
                  ),
                  style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'settings.storeFeeBody'.tr(
              namedArgs: {
                'company': widget.company,
                'store': widget.store,
              },
            ),
            style: tt.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          SegmentedButton<_FeeChoice>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: _FeeChoice.fifteen, label: Text('15%')),
              ButtonSegment(value: _FeeChoice.thirty, label: Text('30%')),
              ButtonSegment(
                value: _FeeChoice.custom,
                label: Text('settings.custom'.tr()),
              ),
            ],
            selected: {_choice},
            onSelectionChanged: (s) => _choose(s.single),
          ),
          AnimatedReveal(
            visible: _choice == _FeeChoice.custom,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: TextField(
                controller: _custom,
                focusNode: _customFocus,
                autofocus: _choice == _FeeChoice.custom,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: 'settings.feeLabel'.tr(),
                  suffixText: '%',
                  errorText: _error,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.tile),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    value == null
                        ? 'settings.feePreviewEmpty'.tr()
                        : storeFeeExample(value),
                    style: tt.bodyMedium?.copyWith(
                      fontFeatures: AppText.tabular,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text('settings.save'.tr()),
          ),
        ],
      ),
    );
  }
}
