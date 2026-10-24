import 'package:flutter/material.dart';
import 'package:openrc/core/extensions/context_extensions.dart';

/// Labeled jump into Ask. Not a header icon — the fourth tab is already there.
class AskContextChip extends StatelessWidget {
  const AskContextChip({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(
        Icons.auto_awesome_outlined,
        size: 16,
        color: scheme.primary,
      ),
      label: Text(label),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        foregroundColor: scheme.primary,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: context.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
