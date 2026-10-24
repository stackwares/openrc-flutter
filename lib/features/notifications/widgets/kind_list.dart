import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/features/settings/widgets/settings_rows.dart';
import 'package:openrc/services/push/push_kinds.dart';

/// Kinds in the groups people think in.
const _groups = [
  ('notifications.groupSales', PushKind.sales),
  ('notifications.groupChurn', PushKind.churn),
  ('notifications.groupOther', {PushKind.change}),
];

/// Quick picks, matched against the current choice.
const kindPresets = [
  ('notifications.presetAll', null),
  ('notifications.presetSales', PushKind.sales),
  ('notifications.presetNew', PushKind.newCustomers),
];

Set<PushKind> presetKinds(Set<PushKind>? preset) => preset ?? PushKind.all;

/// One-tap choices above a [KindList].
class KindPresets extends StatelessWidget {
  const KindPresets({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final Set<PushKind> selected;
  final ValueChanged<Set<PushKind>>? onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (key, preset) in kindPresets)
          ChoiceChip(
            label: Text(key.tr()),
            selected:
                selected.length == presetKinds(preset).length &&
                selected.containsAll(presetKinds(preset)),
            onSelected: onSelected == null
                ? null
                : (_) => onSelected!({...presetKinds(preset)}),
          ),
      ],
    );
  }
}

/// Every kind with its emoji and a switch, grouped. The last one on can't be
/// turned off: choosing nothing is turning the project or device off.
class KindList extends StatelessWidget {
  const KindList({super.key, required this.selected, required this.onChanged});

  final Set<PushKind> selected;

  /// Null disables the switches (while saving, say).
  final void Function(PushKind kind, bool on)? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (title, kinds) in _groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
            child: Text(
              title.tr(),
              style: tt.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, kind) in kinds.indexed) ...[
                  if (i > 0) const Divider(indent: kSettingsDividerIndent),
                  _KindRow(
                    kind: kind,
                    on: selected.contains(kind),
                    onChanged:
                        onChanged == null ||
                            (selected.length == 1 && selected.contains(kind))
                        ? null
                        : (on) => onChanged!(kind, on),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _KindRow extends StatelessWidget {
  const _KindRow({
    required this.kind,
    required this.on,
    required this.onChanged,
  });

  final PushKind kind;
  final bool on;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      leading: SettingsIconTile(
        child: Text(kind.emoji, style: const TextStyle(fontSize: 15)),
      ),
      title: 'notifications.kind.${kind.id}'.tr(),
      subtitle: 'notifications.kindHint.${kind.id}'.tr(),
      trailing: Switch(value: on, onChanged: onChanged),
      showChevron: false,
      onTap: onChanged == null ? null : () => onChanged!(!on),
    );
  }
}
