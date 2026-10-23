import 'package:flutter/material.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/theme/app_tokens.dart';
import 'package:revenuecat/widgets/section_header.dart';

/// Inset of row dividers: padding + icon tile + gap.
const double kSettingsDividerIndent = 62;

/// Heading above a settings group.
class SettingsGroupLabel extends StatelessWidget {
  const SettingsGroupLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SectionHeader(
      title: text,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    );
  }
}

/// Neutral rounded tile behind a row icon.
class SettingsIconTile extends StatelessWidget {
  const SettingsIconTile({super.key, this.icon, this.child, this.color});

  final IconData? icon;
  final Widget? child;

  /// Icon color; neutral by default, red for destructive rows.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tint = color ?? scheme.onSurface;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color != null
            ? color!.withValues(alpha: 0.14)
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: child ?? Icon(icon, size: 18, color: tint),
    );
  }
}

/// One settings row: icon tile, title and subtitle, trailing value.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.icon,
    this.leading,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showChevron = true,
    this.destructive = false,
    this.semanticsLabel,
  });

  final String title;
  final IconData? icon;

  /// Replaces the icon tile (e.g. a flag).
  final Widget? leading;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;
  final bool destructive;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tt = context.textTheme;
    final danger = destructive ? context.appColors.negative : null;
    return Semantics(
      label: semanticsLabel,
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
            child: Row(
              children: [
                leading ?? SettingsIconTile(icon: icon, color: danger),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: tt.bodyLarge?.copyWith(
                          color: danger,
                          fontWeight: destructive
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: tt.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.3,
                            fontFeatures: AppText.tabular,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 170),
                    child: DefaultTextStyle.merge(
                      style: tt.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: AppText.tabular,
                      ),
                      child: trailing!,
                    ),
                  ),
                ],
                if (showChevron && onTap != null) ...[
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
