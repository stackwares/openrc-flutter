import 'package:flutter/material.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/theme/app_tokens.dart';

/// Sentence-case status text in its meaning color, optionally in a soft pill.
class StatusLabel extends StatelessWidget {
  const StatusLabel({
    super.key,
    required this.text,
    required this.color,
    this.pill = false,
  });

  final String text;
  final Color color;
  final bool pill;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.textTheme.labelMedium?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
        height: 1.15,
      ),
    );
    if (!pill) return label;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: label,
      ),
    );
  }
}
