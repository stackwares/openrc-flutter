import 'package:flutter/material.dart';

/// Centered empty / error state with an optional action.
///
/// Scrollable so it still works inside a [RefreshIndicator] (pull to retry).
class AppStateMessage extends StatelessWidget {
  const AppStateMessage({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.isError = false,
    this.bottomPadding = 0,
  });

  /// Standard "couldn't load" state with a Retry button.
  const AppStateMessage.error({
    super.key,
    required String this.message,
    required VoidCallback onRetry,
    this.title = 'Couldn\u2019t load data',
    this.bottomPadding = 0,
  }) : icon = Icons.cloud_off_outlined,
       actionLabel = 'Try again',
       actionIcon = Icons.refresh,
       onAction = onRetry,
       isError = true;

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final bool isError;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final accent = isError ? scheme.error : scheme.onSurfaceVariant;
    final label = actionLabel;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.hasBoundedHeight
                ? (constraints.maxHeight - bottomPadding).clamp(
                    0,
                    double.infinity,
                  )
                : 0,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 34, color: accent),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (message != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        message!,
                        textAlign: TextAlign.center,
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (label != null && onAction != null) ...[
                      const SizedBox(height: 24),
                      FilledButton.tonalIcon(
                        onPressed: onAction,
                        icon: Icon(actionIcon ?? Icons.arrow_forward, size: 18),
                        label: Text(label),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
