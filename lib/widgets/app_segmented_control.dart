import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// One iOS-style segmented control for the whole app, whatever the platform.
///
/// Wraps [CupertinoSlidingSegmentedControl] in the app's surfaces so every
/// segmented choice — project notifications, payout store filter, store fee,
/// API style — looks the same. [values] is the option order, [labels] their
/// text; [groupValue] the selected one, [onValueChanged] null while saving.
class AppSegmentedControl<T extends Object> extends StatelessWidget {
  const AppSegmentedControl({
    super.key,
    required this.values,
    required this.labels,
    required this.groupValue,
    required this.onValueChanged,
  }) : assert(values.length > 0, 'needs at least one segment'),
       assert(labels.length == values.length, 'one label per value');

  final List<T> values;
  final Map<T, String> labels;
  final T groupValue;
  final ValueChanged<T?>? onValueChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;
    // Cupertino's callback is non-nullable, so a null [onValueChanged]
    // (while saving) becomes a control that ignores input instead.
    final enabled = onValueChanged != null;
    final control = CupertinoSlidingSegmentedControl<T>(
        groupValue: groupValue,
        onValueChanged: (value) => onValueChanged?.call(value),
        backgroundColor: scheme.surfaceContainerHigh,
        thumbColor: isDark ? scheme.surfaceContainerHighest : Colors.white,
        children: {
          for (final value in values)
            value: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                labels[value]!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style:
                    textTheme.bodyMedium?.copyWith(
                      fontWeight: value == groupValue
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: onValueChanged == null
                          ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
                          : value == groupValue
                          ? scheme.primary
                          : scheme.onSurface,
                    ) ??
                    TextStyle(
                      fontWeight: value == groupValue
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: value == groupValue
                          ? scheme.primary
                          : scheme.onSurface,
                    ),
              ),
            ),
        },
      );
    return SizedBox(
      width: double.infinity,
      child: enabled
          ? control
          : IgnorePointer(
              child: Opacity(opacity: 0.5, child: control),
            ),
    );
  }
}
