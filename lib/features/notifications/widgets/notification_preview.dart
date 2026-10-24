import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/widgets/app_logo.dart';

/// A made-up OpenRC notification as the system would show it, so people see
/// what they're turning on.
class NotificationPreview extends StatelessWidget {
  const NotificationPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    return Semantics(
      label: 'notifications.preview.semantics'.tr(),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: const AppLogo(size: 38),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'OpenRC',
                          style: tt.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        'notifications.preview.now'.tr(),
                        style: tt.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'notifications.preview.title'.tr(),
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'notifications.preview.body'.tr(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
