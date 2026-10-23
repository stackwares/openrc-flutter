import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_leading_avatar.dart';
import 'package:revenuecat/models/rc_project.dart';
import 'package:revenuecat/services/rc_account_projects_provider.dart';
import 'package:revenuecat/services/rc_auth_service.dart';
import 'package:revenuecat/widgets/app_card.dart';

/// Who is signed in: initials avatar, name / email, plan and projects.
class SettingsAccountHeader extends ConsumerWidget {
  const SettingsAccountHeader({super.key});

  static String initialsFor(String? name, String? email) {
    final words = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isNotEmpty) {
      return words.take(2).map((w) => w[0].toUpperCase()).join();
    }
    final e = email?.trim() ?? '';
    return e.isEmpty ? '' : e[0].toUpperCase();
  }

  static String? planLabel(String? plan) {
    final p = plan?.trim().replaceAll('_', ' ') ?? '';
    if (p.isEmpty) return null;
    return '${p[0].toUpperCase()}${p.substring(1)} plan';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    final me = ref.watch(rcMeProvider);
    final projects =
        ref.watch(rcAccountProjectsProvider).asData?.value ?? const [];
    final name = me?.name?.trim();
    final email = me?.email?.trim();
    final hasName = name != null && name.isNotEmpty;
    final title = hasName ? name : (email ?? 'RevenueCat account');
    final subtitle = hasName ? email : 'Signed in to RevenueCat';
    final initials = initialsFor(name, email);
    final plan = planLabel(me?.currentPlan);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: initials.isEmpty
                ? Icon(Icons.person_rounded, color: scheme.primary)
                : Text(
                    initials,
                    style: tt.titleLarge?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                if (plan != null || projects.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (plan != null)
                        _Pill(
                          leading: Icon(
                            Icons.workspace_premium_outlined,
                            size: 14,
                            color: scheme.primary,
                          ),
                          label: plan,
                        ),
                      if (projects.isNotEmpty)
                        _Pill(
                          leading: _ProjectIcons(projects: projects),
                          label:
                              '${projects.length} project'
                              '${projects.length == 1 ? '' : 's'}',
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.leading, required this.label});

  final Widget leading;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 6),
          Text(
            label,
            style: context.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Up to three project icons, overlapping.
class _ProjectIcons extends StatelessWidget {
  const _ProjectIcons({required this.projects});

  final List<RcProject> projects;

  static const double _size = 18;
  static const double _step = 11;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final shown = projects.take(3).toList();
    return SizedBox(
      width: _size + _step * (shown.length - 1),
      height: _size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * _step,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: scheme.surfaceContainerHigh,
                    width: 1.5,
                  ),
                ),
                child: TransactionLeadingAvatar(
                  imageUrl: shown[i].iconUrl,
                  size: _size - 3,
                  borderRadius: 4,
                  tintColor: scheme.onSurfaceVariant,
                  fallback: Icon(
                    Icons.apps_rounded,
                    size: 10,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
