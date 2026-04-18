import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/features/transactions/transactions_common.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_leading_avatar.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/app_icon_overrides_store.dart';

/// Shows a bottom sheet to pick which apps to include in transaction lists.
Future<void> showTransactionsAppFilterSheet({
  required BuildContext context,
  required Map<String, List<RcTransaction>> filterSource,
  required Set<String>? currentIncludeFilter,
  required void Function(Set<String>? newIncludeFilter) onApply,
}) {
  final options = collectAppFilterOptions(filterSource);
  if (options.isEmpty) return Future.value();

  final allKeys = options.map((o) => o.key).toSet();
  final initialSelected = currentIncludeFilter == null
      ? Set<String>.from(allKeys)
      : () {
          final i = currentIncludeFilter.intersection(allKeys);
          return i.isEmpty ? Set<String>.from(allKeys) : i;
        }();

  final maxHeight = MediaQuery.sizeOf(context).height * 0.62;

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
              onApply: (selected) {
                Navigator.pop(sheetContext);
                if (selected.length == allKeys.length) {
                  onApply(null);
                } else {
                  onApply(selected);
                }
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
  final void Function(Set<String> selected) onApply;

  const TransactionsAppFilterModal({
    super.key,
    required this.options,
    required this.allKeys,
    required this.initialSelected,
    required this.onApply,
  });

  @override
  State<TransactionsAppFilterModal> createState() =>
      _TransactionsAppFilterModalState();
}

class _TransactionsAppFilterModalState extends State<TransactionsAppFilterModal> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initialSelected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
          child: Row(
            children: [
              Text(
                'Apps',
                style: theme.textTheme.titleLarge?.copyWith(
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
                onPressed: () => widget.onApply(Set<String>.from(_selected)),
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
